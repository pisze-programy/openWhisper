# Optimizing Parakeet TDT on Apple silicon

Log of the optimization journey from a PyTorch model to a Swift package
that transcribes **17.5 minutes of speech in 0.92 seconds (1145× real
time)** on an M5 Max -- 2.8× faster than running the same `.mlpackage`
from Python's `coremltools`.

All numbers in this doc are 3-run medians on a single audio file
(`assets/test_audio.mp3` in the companion conversion repo, a 17.5-min
recording of MLK's "I Have a Dream"), full-file end-to-end inference
(no warmup run), on an Apple M5 Max.

---

## Executive summary

| Stage | Artifact | Best RTFx (M5 Max) | WER vs fp16 ref |
|---|---|---:|---:|
| Python reference, fp32 (CPU fallback) | baseline-fp32 | 74× | 1.40% |
| Python reference, fp16 (ANE) | baseline-fp16 | 226× | 0% (ref) |
| Python, 4-bit palettized encoder, ANE | 4bit-pgc-ane | 246× | 2.67% |
| Python, same artifacts, GPU | 4bit-pgc-ane | 414× | 3.10% |
| **Swift, same artifacts, ANE, pipelined + 2 workers** | parakeet-coreml-swift | **402×** | 3.53% |
| **Swift, same artifacts, GPU, pipelined + 4 workers** | parakeet-coreml-swift | **1145×** | 3.10% |

The model stayed the same from ~245× to ~1145× RTFx; everything from
that point was runtime engineering.

---

## Part 1: The model (Python, conversion side)

The conversion work lives in the companion repo
[`mweinbach/parakeet-coreml`](https://github.com/mweinbach/parakeet-coreml)
(the Python-side tooling that produces the `.mlpackage` artifacts the
Swift package runs).

### The base architecture

[`nvidia/parakeet-tdt-0.6b-v3`](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)
is an RNN-T-style ASR model with a "TDT" (Token-and-Duration
Transducer) twist:

- **Encoder**: 24-layer Fast Conformer (611 M params). Mel frames in,
  downsampled 8× and projected to 640-dim frames out.
- **Decoder (prediction network)**: 2-layer LSTM, 640 hidden
  (12 M params).
- **Joint**: single `Linear(640 -> 8198)` that splits into
  `[vocab (8193) | durations (5)]` (5 M params).

See [the conversion repo's architecture analysis](https://github.com/mweinbach/parakeet-coreml)
for the full graph walk.

### Conversion experiments

Every row here is a different `.mlpackage` build. All on the same 17.5
min audio, `compute_units=cpu_and_ne`, M5 Max.

| Build | Encoder size | RTFx (ANE) | WER vs fp16 | Notes |
|---|---:|---:|---:|---|
| baseline-fp32 | 2 GB | 74× | 1.40% | Can't use ANE (fp32 not supported); CPU fallback |
| **baseline-fp16** | 1 GB | **226×** | 0.00% | Reference. 1342/33 ANE/CPU op split. |
| w8a16-weight-only | 649 MB | 244× | 2.31% | `linear_quantize_weights(int8, per_channel)`, conv excluded |
| w8a8-calibrated (35 enc / 1024 dec) | 666 MB | 263× | 7.11% | Full W8A8 with small calibration set |
| w8a8-bigcal (70 enc / 2048 dec) | 666 MB | 254× | 5.96% | +3 hrs of calibration audio |
| w8a8-bigcal-perchannel | 666 MB | 256× | 7.60% | Per-channel activations -- hurts on this model |
| w8a8-bigcal-keepjoint | 666 MB | 267× | 6.81% | Joint kept fp16, encoder + decoder W8A8 |
| palettize-enc-8bit | 648 MB | 241× | 1.16% | 8-bit k-means LUT on encoder, per-tensor |
| palettize-enc-6bit | 523 MB | 245× | 3.53% | 6-bit -- tight |
| palettize-enc-4bit-pcs | 409 MB | 50× | 5.47% | **4-bit + `enable_per_channel_scale`: FAILS.** Kicks 492 ops off ANE to CPU. |
| **palettize-enc-4bit-pgc** (shipped) | **424 MB** | **246×** | 2.67% | 4-bit + `per_grouped_channel` (group_size=16). Stays on ANE. |

**Key lessons from the conversion phase:**

1. **Palettization beat linear quant** at the same bit-width (1.16% vs
   2.31% WER at int8). Apple documents this too -- their ANE tuning
   prefers the LUT/indices representation.
2. **`per_grouped_channel` is the ANE-friendly low-bit knob**, not
   `enable_per_channel_scale`. The latter looked right on paper --
   per-channel scales are Apple's documented NE recommendation -- but
   the 4-bit + PCS combination doesn't have a fused kernel on ANE, so
   the scheduler dumped 492 ops to CPU and destroyed RTFx.
3. **Activation quantization hurt WER more than expected** (2-7pp),
   calibration corpus size matters a lot (1.6pp delta from 35 to 70
   enc samples), per-channel activations hurt quality on this model
   with single-domain calibration data.
4. **Encoder-only compression is the right strategy**. Decoder (12M
   params) and joint (5M params) are small enough that the
   calibration / WER risk isn't worth the ~30 MB saved.

### The shipping build: 4-bit per-grouped-channel palettization

[`mweinbach1/parakeet-tdt-0.6b-v3-coreml`](https://huggingface.co/mweinbach1/parakeet-tdt-0.6b-v3-coreml)

- **Encoder**: 4-bit k-means palettization,
  `granularity=per_grouped_channel`, `group_size=16`. Each weight
  tensor gets multiple LUTs (one per 16-channel output group) so the
  cluster range isn't dominated by outlier channels. Conv ops stay at
  fp16 (Apple-documented hedge for the Conformer subsampling stack).
- **Decoder + joint**: fp16, no weight or activation compression.
- **Compute plan** (requested `cpu_and_ne`): encoder 1342 ANE + 32 CPU
  ops. Decoder + joint 100% CPU (they're small enough that ANE
  dispatch overhead isn't worth it).

That's the artifact the Swift runtime optimizations below are layered
on top of.

---

## Part 2: The runtime (Swift, this repo)

Running the `.mlpackage` from Python gives you ~245× RTFx on ANE and
~414× on GPU. Every number in this section was a push to do better
from Swift, against the exact same on-disk model.

### Starting point: naïve port (v0)

| Target | RTFx |
|---|---:|
| ANE | 155× |
| GPU | 115× |

35% slower than Python. The obvious suspect: we were allocating too
much per decoder step.

Each greedy TDT decode step looked like:

```swift
let provider = try MLDictionaryFeatureProvider(dictionary: [
    "input_ids": MLFeatureValue(multiArray: inputIds),
    "hidden": MLFeatureValue(multiArray: hidden),
    "cell": MLFeatureValue(multiArray: cell),
])
let out = try decoder.prediction(from: provider)  // allocates output arrays
// ... argmax, copy, etc.
```

~3000 steps per 17.5 min audio, each allocating a Swift dictionary and
bridging through `NSDictionary` to Core ML. That's ~2 ms of pure Swift
overhead per step, 6 s total.

### Optimization 1: `FeatureBag` and reused input buffers

See [`Sources/ParakeetTDT/FeatureBag.swift`](Sources/ParakeetTDT/FeatureBag.swift).

A custom `MLFeatureProvider` built once per submodule and reused for
every prediction. It holds a fixed set of `MLFeatureValue`s wrapping
`MLMultiArray`s that we pre-allocated and overwrite in place.

```swift
// Built once per submodule.
let decoderInputs = FeatureBag([
    "input_ids": MLFeatureValue(multiArray: inputIds),
    "hidden":    MLFeatureValue(multiArray: hidden),
    "cell":      MLFeatureValue(multiArray: cell),
])

// Every decode step now: overwrite the buffers, call prediction, done.
idsPtr[0] = Int32(lastTokenId)
let out = try decoder.prediction(from: decoderInputs)
```

No Swift allocations in the hot loop. Every step is just a single
`MLModel.prediction(from:)` call with no Swift-side overhead.

### Optimization 2: `autoreleasepool` around each prediction

Core ML's output `MLMultiArray`s come out of a pool of IOSurface-backed
buffers. If any stray Swift reference holds them past the next
prediction call (via capture, tuple, etc.), the pool fills up and the
process crashes with `Failed to allocate memory IOSurface object`.

Wrapping each `prediction(from:)` in an `autoreleasepool` guarantees
the outputs are released before the next iteration:

```swift
try autoreleasepool {
    let out = try worker.runDecoderStep()
    memcpy(decoderStatePtr, out.decoderHidden.dataPointer, ...)
    copyMultiArray(from: out.nextHidden, to: hidden)
    copyMultiArray(from: out.nextCell, to: cell)
    // `out` (and its IOSurface outputs) dies here.
}
```

### Optimization 3: `vDSP_maxvi` argmax

Tiny but cheap win. The greedy loop takes ~6000 argmaxes per 17.5-min
clip (once over 8193-wide vocab, once over 5-wide durations, per
symbol). `vDSP_maxvi` scans via Accelerate's SIMD path and returns the
index in a single call.

```swift
static func argmax(_ array: MLMultiArray) -> Int {
    let n = vDSP_Length(array.count)
    let ptr = UnsafePointer<Float32>(OpaquePointer(array.dataPointer))
    var maxVal: Float = 0
    var idx: vDSP_Length = 0
    vDSP_maxvi(ptr, 1, &maxVal, &idx, n)
    return Int(idx)
}
```

### Optimization 4: Blank-token cache

Per the TDT paper, about half the encoder frames emit blank (silence /
pause / middle-of-word). If the previous step emitted blank, the
decoder's LSTM state doesn't change, so we can skip the decoder call
entirely and reuse the previous `decoder_hidden`.

Implemented as a validity flag in
[`GreedyTDTDecoder.swift`](Sources/ParakeetTDT/GreedyTDTDecoder.swift):
when the flag is `true` and the last token was blank, we skip
`runDecoderStep()` and just call `runJoint()` with the cached state.

### After optimizations 1-4 (v1)

| Target | RTFx | vs Python |
|---|---:|---:|
| CPU | 136× | −1.7% |
| **ANE** | **245×** | **parity** |
| GPU | 373× | −9.9% |

Parity with Python on ANE. Within 10% everywhere else. But we're
leaving the pipeline idle between stages.

### Optimization 5: Three-stage pipeline across chunks

Long-form transcription is `ceil(audio_seconds / 30)` chunks. Each
chunk has three sequential stages on wildly different hardware:

| Stage | Hardware | Time / 30 s chunk (M5 Max, GPU build) |
|---|---|---:|
| Mel extraction | CPU (`vDSP`) | 9 ms |
| Encoder | ANE / GPU / CPU | 22-170 ms |
| Decode loop (LSTM + joint) | CPU | 42 ms |

Running them sequentially per chunk, total = `sum(stages) * N_chunks`.
Pipelining them, total = `max(stages) * N_chunks`.

Implementation: see
[`Sources/ParakeetTDT/Pipeline.swift`](Sources/ParakeetTDT/Pipeline.swift).

- Stage 1 (mel) runs on `DispatchQueue("parakeet.mel", .userInitiated)`.
- Stage 2 (encoder) runs on `DispatchQueue("parakeet.encoder", .userInitiated)`.
- Stage 3 (decode) runs on a concurrent `DispatchQueue("parakeet.decode", attributes: .concurrent)` as a worker pool (see next section).

Connected by two bounded blocking queues (`BlockingQueue` in the same
file). Capacity-2 gives ~100 ms of buffering between stages and, more
importantly, caps how many Core ML prediction outputs are in flight at
once. Without that cap, a fast encoder piles up IOSurface buffers
faster than the decode stage consumes them, and you hit the same
IOSurface exhaustion crash as before.

Because decode can finish chunks out of order (with the worker pool
below), a `ChunkResultAccumulator` keyed on chunk index reassembles
tokens in the right order at the end.

### After adding the pipeline (v2)

| Target | RTFx | vs Python |
|---|---:|---:|
| CPU | 168× | +21.7% |
| **ANE** | **404×** | **+64.4%** |
| **GPU** | **634×** | **+52.9%** |

Pipeline cleanly beats Python everywhere. The ANE and CPU targets are
now encoder-bound -- the encoder takes the whole chunk time and the
decode / mel stages run for free in parallel. GPU is the interesting
one: encoder is down to 0.77 s total, but decode is 1.5 s. **Decode
is now the bottleneck on GPU.**

### Optimization 6: Parallel decode worker pool

GPU's 0.77 s encoder + 1.5 s sequential decode means the pipeline is
spending 1.5 s waiting on CPU while GPU sits idle. Each chunk's decode
loop is independent (the LSTM state resets per chunk), so we can run
them in parallel.

See
[`Sources/ParakeetTDT/DecoderWorker.swift`](Sources/ParakeetTDT/DecoderWorker.swift).

A `DecoderWorker` owns its own private set of decode buffers:

- `input_ids` (1, 1)
- `hidden`, `cell` (2, 1, 640)
- `encoder_frame`, `decoder_state` (1, 640)
- two `FeatureBag`s wrapping those

The `MLModel` instances themselves are shared across workers; per
Apple, `MLModel.prediction(from:)` is thread-safe.

`ModelRunner` now owns a pool of N workers, handed out via a semaphored
`BlockingWorkerPool`. `Pipeline` stage 3 becomes a concurrent dispatch:

```swift
while let item = encQueue.take() {
    guard let worker = runner.acquireWorker() else { break }
    group.enter()
    decodeQ.async {
        defer {
            runner.releaseWorker(worker)
            group.leave()
        }
        let decoded = try GreedyTDTDecoder.decode(
            encoderHidden: item.hidden, ...,
            worker: worker
        )
        results.set(index: item.index, chunk: decoded)
    }
}
group.wait()
```

### Tuning worker count on M5 Max

| Workers | ANE RTFx | GPU RTFx | CPU RTFx |
|---:|---:|---:|---:|
| 1 | 403× | 585× | 168× |
| 2 | 403× | 895× | 157× |
| 3 | 403× | 1100× | — |
| **4 (GPU default)** | 403× | **1215×** | — |
| 6 | — | 1230× | — |
| 8 | — | 1241× | — |

Observations:
- **ANE**: flat regardless of worker count. Encoder takes 2.5 s per
  run, decode takes 1.4 s, so decode is never the critical path. Extra
  workers would just sit idle. Default: 2.
- **GPU**: linear speedup through 4 workers, tapers off past that as
  workers start contending on CPU cache and BLAS dispatch queues.
  Default: 4.
- **CPU**: 2+ workers *slow things down*. With the encoder also on
  CPU, decode workers steal cores from the encoder and per-chunk
  encoder time jumps from 176 ms to 190 ms. Default: 1.

These are the shipped defaults:

```swift
let workerCount: Int = {
    if let override = decoderWorkers { return max(1, override) }
    switch computeUnits {
    case .cpu: return 1
    case .ane: return 2
    case .gpu, .all: return 4
    }
}()
```

### After parallel decode (v3, shipping)

| Target | RTFx | vs Python |
|---|---:|---:|
| CPU | 163× | +17.7% |
| ANE | 402× | +63.9% |
| **GPU** | **1145×** | **+176.5%** |

GPU almost tripled Python's throughput.

---

## Part 3: What the pipeline actually looks like in production

For the 17.5-min audio clip (35 chunks, 30 s each), on GPU with 4
decode workers:

```
Time ->      0s              500ms           1000ms            1500ms
                              .               .                  .
mel    ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ (9 ms/chunk)
                              .               .                  .
enc    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓                 (22 ms/chunk)
                              .               .                  .
dec w1 ████ ████ ████ ████ ████ ████ ████ ████ ████            (70 ms/chunk)
dec w2     ████ ████ ████ ████ ████ ████ ████ ████ ████        (70 ms/chunk)
dec w3        ████ ████ ████ ████ ████ ████ ████ ████           (70 ms/chunk)
dec w4           ████ ████ ████ ████ ████ ████ ████ ████        (70 ms/chunk)
                              .               .                  .
final tokens:                                                    ready at ~870 ms
```

- Mel is "free" -- it runs in parallel with the encoder on a cold CPU
  core, never the bottleneck.
- Encoder is the critical path at ~770 ms (35 × 22 ms).
- 4 decode workers process chunks out of order; each individual chunk's
  decode is ~70 ms, but because 4 run concurrently, total decode wall
  clock is ~1500 ms / 4 = ~375 ms. Easily hidden behind the encoder.
- Total: ~870 ms. 1048 s of audio / 0.87 s wall = **1205× RTFx** (just
  about our measured 1215× at `--decoder-workers 4`).

---

## What's still on the table

Things we could still optimize but haven't, with expected ROI:

| Optimization | Where | Expected win | Cost |
|---|---|---:|---|
| IOSurface-backed encoder input | GPU builds | ~5% | Small refactor; use `MLMultiArray(pixelBuffer:...)` |
| Fused `decoder + joint` model | All | ~20% on decode loop | Python conversion change |
| `vDSP_mmul` in mel | All | ~50% of mel time | Mel is off critical path, so 0% RTFx |
| QAT for W8A8 | Quality, not speed | −1-2 pp WER at same RTFx | Training run required |
| Async mel extraction on GPU | GPU builds | Maybe ~5% | Move mel to Metal shaders |

At 1145× RTFx on a single file, most of these aren't worth it for
batch transcription. The fused `decoder + joint` model is the most
interesting because it would halve per-symbol Core ML dispatches, but
it requires a change in the Python conversion repo, not here.

---

## Reproduce

```bash
git clone https://github.com/mweinbach/parakeet-coreml-swift
cd parakeet-coreml-swift
swift build -c release

# Download the test audio (the 17.5-min MLK "I Have a Dream")
curl -L -o /tmp/test.mp3 https://huggingface.co/datasets/mweinbach1/parakeet-test-audio/resolve/main/test_audio.mp3

# Warmup + time each target
for u in cpu ane gpu; do
  for i in 1 2 3; do
    .build/release/parakeet transcribe /tmp/test.mp3 \
      --compute-units $u --show-timing 2>&1 | grep RTFx:
  done
done
```

Numbers will vary slightly on different Apple silicon. M5 Max medians:
CPU 163×, ANE 402×, GPU 1145×.

For the Python-side reproduction of the conversion experiments, see
the [`mweinbach/parakeet-coreml`](https://github.com/mweinbach/parakeet-coreml)
conversion repo.
