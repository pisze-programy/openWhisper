# Changelog — parakeet-coreml-ios

Maintained by [pisze-programy](https://github.com/pisze-programy) (Chris does
apps), forked from
[`mweinbach/parakeet-coreml-swift`](https://github.com/mweinbach/parakeet-coreml-swift)
and shipping in **OpenWhisper**, an on-device iOS speech-to-text app. Every
modification relative to upstream is documented here.

All changes are platform-agnostic. The mel work gives the largest *relative*
win on iPhone but removes real overhead on macOS too (see per-change notes).

---

## Background

Two on-device findings drove the work:

1. **Default `.ane` fails at load time on iPhone.** `MLModel(contentsOf:)` with
   `.cpuAndNeuralEngine` logged `MILCompilerForANE ... ANECCompile() FAILED` /
   `Couldn't communicate with a helper application`, took ~41 s and ballooned
   RSS to ~2.4 GB (jetsam killed the process). Not a package bug per se, but it
   means **`.gpu` is the practical default on iOS today**, and worth documenting
   as such.

2. **Mel extraction cost ~600 ms per 30 s chunk on iPhone** — two orders of
   magnitude above the 9 ms/chunk measured on M5 Max. Profiling showed the cost
   was *not* the FFT: it was per-frame Swift allocations plus **128 individual
   `vDSP_dotpr` calls per frame** (~384k dispatches per chunk).

---

## Changes

### 1. Mel: remove per-frame allocations, flatten buffers

`MelFeatureExtractor.extract()` previously allocated `real`, `imag`, `melRow`
once per STFT frame and stored output as a nested `[[Float]]` (`logMelFrames`)
that was copied again for normalization. Now:

- `real` / `imag` / `melRow` are allocated once and reused.
- Frames accumulate into a flat `melFlat[t * numMelFilters + i]` buffer.
- Normalization (mean / Bessel-corrected std) runs in place on the flat buffer.

Numerics unchanged (same accumulation order, same `log(mel + logGuard)`,
`sqrt(re²+im²)→²`, `(n-1)` denominator, `epsilon`).

Measured: `~600 ms → ~550 ms` per chunk on iPhone. Small on its own — it was
the prerequisite for change #2.

### 2. Mel: single `vDSP_mmul` for the mel projection

The per-frame projection was 128 × `vDSP_dotpr` (one per mel filter), each
wrapped in `withUnsafeBufferPointer` closures. The mel filter bank is now
flattened once in `init` (`melBankFlat[numMelFilters][numFreqBins]`, row-major)
and each frame's projection is a single matmul:

```swift
vDSP_mmul(melBankFlat, 1, power, 1, &melRow, 1,
          vDSP_Length(numMelFilters), 1, vDSP_Length(numFreqBins))
```

This removes ~384k vDSP dispatches and ~768k closure setups per chunk.
Platform-agnostic; the absolute win is biggest where mel was slow (iPhone,
**est. ~550 ms → ~50-150 ms per chunk**), but it also shaves the M5 Max case
where mel currently costs ~9 ms/chunk of pure dispatch overhead.

### 3. Robust short-clip handling: always-on audio padding

`ParakeetTranscriber.transcribe(samples:)` prepares every recording for the
encoder, not just short ones:

- a **0.5 s silent lead-in** on the left (encoder warm-up; prevents the first
  words being cut off),
- **1.5 s of trailing silence** on the right of every clip (the decoder gets
  context after the last word instead of cutting the tail off),
- clips shorter than 5 s total are padded up to `minAudioSeconds`.

```swift
private static let minAudioSeconds    = 5.0
private static let leadInSeconds      = 0.5
private static let trailingPadSeconds = 1.5
```

The reported `audioDurationSeconds` stays the real duration (measured before
padding). This addresses upstream issue #1 (empty results below ~3 s,
hallucinated tails on 2-5 s clips, cut-off endings) at the API layer, so it
covers both `transcribe(audioURL:)` and `transcribe(samples:)` on iOS and
macOS.

### 4. Make `deleteSourceAfterCompile` actually safe across launches

`resolveModel(under:named:)` only looked inside `modelsRoot`, so deleting the
`.mlpackage` sources after a successful compile (the point of
`deleteSourceAfterCompile: true`) broke every later launch once the sources were
gone. Two small additions fix that:

- `ModelCache.compiledModelURL(named:)` — finds the most recently compiled
  `.mlmodelc` for a model name anywhere under the cache directory, independent
  of its content-address (which can't be recomputed once the source is gone).
- `ParakeetTranscriber` now resolves via `resolveOrCached(...)`: source
  `.mlpackage` if present (compile-or-use-cache as before), otherwise the
  cached compiled bundle.

Existing hash-addressed caches keep working; the new lookup only activates when
the source is missing. Lets callers save ~480 MB of disk per device.

### 5. Performance logging (diagnostic)

`os.Logger` (subsystem `com.parakeet-tdt`, category `performance`) timings:

- `load.resolve+compile`, `load.encoder/decoder/joint.mlmodel`,
  `load.runner`, `load.tokenizer`, `load.featureExtractor` in `init`,
- `parse.audioURL` (decode + resample) in `transcribe(audioURL:)`.

Pure diagnostics — no behavior change. Invaluable for tracking down where model
load and pipeline time actually go on device.

### 6. Decoder confidence scoring

`Transcription` now exposes a `confidence: Float` (0…1). It is the mean over
decode steps of `sigmoid(maxLogit − meanLogit)` for the token logits — computed
with a single `vDSP_sve` reduction alongside the existing `vDSP_maxvi` (no full
softmax; a few microseconds per step). Because `max ≥ mean`, values land in
`[0.5, 1)`: near-silence hallucinations produce a flat distribution (~0.5),
confident frames a sharper peak.

This lets callers gate unreliable results. OpenWhisper discards recordings
shorter than ~1 s whose confidence is below 0.55 ("No speech detected") instead
of storing a hallucinated word. Cheap, additive, and useful for any short-clip
dictation flow.

---

## Measured impact (iPhone 15,3 / A16, compute units = GPU)

| Stage | Before | After |
|---|---:|---:|
| Model load (`prepare`) | 41.9 s (ANE, failing) | 3.0 s (GPU) |
| RSS after load | ~2.4 GB (ANE, jetsam) | ~176 MB (GPU) |
| Mel / 30 s chunk | ~600 ms | ~550 ms (buffer reuse) → **est. ~50-150 ms** (mmul) |
| 28.4 s clip, total inference | — | 1.14 s (rtfx 24.9×) |
| Short clips < 5 s | empty / hallucinated tail | always padded; confidence-gated |
| Disk footprint | ~1.1-1.3 GB (sources kept) | ~480 MB saved (sources deleted) |

Encoder/decode throughput untouched (encoder on iPhone GPU ~440 ms per 30 s
chunk; decode ~100-130 ms).

---

## Notes

- `Transcription` gained `confidence` (defaults to `0`); nothing else in the
  public API changed.
- The mel rewrite keeps the same float accumulation order where it matters for
  `MelFilterBankTests`; `swift test` passes.
- Padding is applied inside `transcribe(samples:)`, so it covers both entry
  points; the constants are tunable.
