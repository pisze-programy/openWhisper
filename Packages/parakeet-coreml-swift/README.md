# parakeet-coreml-swift

[![Swift](https://img.shields.io/badge/Swift-5.10%20%7C%206.0-orange.svg?style=flat)](https://swift.org)
[![Platforms](https://img.shields.io/badge/platforms-macOS%2014%2B%20%7C%20iOS%2017%2B-blue.svg?style=flat)](https://developer.apple.com)
[![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-brightgreen.svg?style=flat)](https://swift.org/package-manager/)
[![License](https://img.shields.io/badge/license-Apache--2.0-lightgray.svg?style=flat)](LICENSE)

On-device speech-to-text on Apple silicon. Swift wrapper around NVIDIA's
**Parakeet TDT 0.6B v3** compiled to Core ML, tuned so it's **3× faster
than running the same `.mlpackage` from Python** on the GPU.

- **macOS 14+ / iOS 17+**
- **1145× real-time** on GPU / **402× on ANE** / **163× on CPU** (M5 Max,
  17.5-min audio, 3-run median)
- **~450 MB on-disk** (4-bit palettized encoder, fp16 decoder + joint)
- **Auto-downloads** its model from HuggingFace on first launch -- zero
  manual staging
- **Single dependency**: [swift-argument-parser](https://github.com/apple/swift-argument-parser)
  (only used by the CLI; the library itself is self-contained)

## 30-second quick start

### Library

```swift
import ParakeetTDT

let transcriber = try await ParakeetTranscriber.fromHuggingFace(
    computeUnits: .gpu           // or .ane (default), .cpu, .all
)
let result = try transcriber.transcribe(
    audioURL: URL(fileURLWithPath: "speech.wav")
)
print(result.text)
print(String(format: "%.1fx realtime", result.rtfx))
```

First call downloads ~450 MB from HuggingFace
(`mweinbach1/parakeet-tdt-0.6b-v3-coreml`) to
`~/Library/Caches/com.parakeet-tdt/hf-models/` and compiles each
`.mlpackage` into a `.mlmodelc` cache. Subsequent runs hit the cache
instantly (~0.2 s cold start).

### CLI

```bash
swift run -c release parakeet transcribe speech.wav --compute-units gpu
```

No `--models` flag needed; the CLI downloads from HuggingFace on first
run and reuses the cache after.

```bash
# If you already have the models staged locally:
swift run -c release parakeet transcribe speech.wav \
    --models /path/to/parakeet-tdt-0.6b-v3-coreml

# Pre-download without transcribing (useful for CI / build-time staging):
swift run -c release parakeet download
```

## Add to your project

### Xcode (iOS / macOS app)

1. In Xcode, open **File > Add Package Dependencies...**
2. Paste the repo URL:
   `https://github.com/mweinbach/parakeet-coreml-swift`
3. Pick the **Up to Next Major Version** rule on `0.1.0`.
4. When Xcode shows the products list, select the **`ParakeetTDT`**
   library (leave the `parakeet` CLI executable unchecked unless you
   want the command-line tool bundled) and add it to your app target.
5. In any Swift file: `import ParakeetTDT` and use
   `ParakeetTranscriber.fromHuggingFace(...)` -- it's async, so call it
   from an async context (a `Task`, `@MainActor` function, or SwiftUI
   `.task { }`).

Xcode's package resolver will pull this package and its single
dependency (`swift-argument-parser`) automatically.

The library uses `Foundation`, `CoreML`, `AVFoundation`, and
`Accelerate` -- all ship with every Apple OS, no extra frameworks to
link.

### Swift Package Manager (command line or non-Xcode Swift project)

In your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mweinbach/parakeet-coreml-swift",
             from: "0.1.0"),
]

// Target:
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "ParakeetTDT", package: "parakeet-coreml-swift"),
    ]
)
```

### App-sandbox note (macOS / iOS)

`ParakeetTranscriber.fromHuggingFace(...)` downloads a ~450 MB model
to `~/Library/Caches/...` on first run, so if your app runs inside the
App Sandbox:

- macOS: outgoing connections work by default once you enable the
  **Outgoing Connections (Client)** App Sandbox capability.
- iOS: HTTPS to `huggingface.co` works without any Info.plist entry.
- Either platform: if you ship models inside the app bundle instead of
  auto-downloading, use `ParakeetTranscriber(modelsRoot:)` directly
  and point it at your `Bundle.main.resourceURL`.

## Full API

```swift
// Zero-setup: fetch the default model from HuggingFace + transcribe.
let t = try await ParakeetTranscriber.fromHuggingFace()

// Specify a HF repo + progress callback (useful for pinning / UI).
let t = try await ParakeetTranscriber.fromHuggingFace(
    repoId: "mweinbach1/parakeet-tdt-0.6b-v3-coreml",
    computeUnits: .gpu,
    decoderWorkers: 4,
    progress: { bytesDone, bytesTotal, file in
        print("\(file): \(bytesDone)/\(bytesTotal)")
    }
)

// Fully local: point at a directory you staged yourself.
let t = try ParakeetTranscriber(
    modelsRoot: URL(fileURLWithPath: "/path/to/models"),
    computeUnits: .ane
)

// Transcribe an audio file.
let result = try t.transcribe(audioURL: audioURL)

// Or a raw Float buffer (mono, 16 kHz).
let result = try t.transcribe(samples: floatBuffer)
```

`Transcription` fields:

| Field | Type | What it is |
|---|---|---|
| `text` | `String` | Final detokenized transcript. |
| `tokenIds` | `[Int]` | Raw token IDs (blanks already stripped). |
| `frameIndices` | `[Int]` | Encoder-frame index of each token (× 8 × hop for sample-level timestamps). |
| `durations` | `[Int]` | TDT duration prediction per token (0-4 encoder frames). |
| `audioDurationSeconds` | `Double` | |
| `inferenceDurationSeconds` | `Double` | Wall-clock, excludes model load. |
| `rtfx` | `Double` | `audioDurationSeconds / inferenceDurationSeconds`. |
| `timing` | `TranscriptionTiming` | Per-stage breakdown (mel / encoder / decode / detokenize). |

## Compute units

| Option | Maps to | When to use |
|---|---|---|
| `.ane` (default) | `cpuAndNeuralEngine` | Best power/latency balance on iOS. |
| `.gpu` | `cpuAndGPU` | Fastest on M-class Macs (~3× ANE). |
| `.cpu` | `cpuOnly` | Portable fallback, no accelerator. |
| `.all` | `all` | Let Core ML pick. |

The scheduler decides per-op what runs where. You can flip between these
at load time without rebuilding the `.mlpackage`.

## Benchmarks (M5 Max, 17.5-min MLK "I Have a Dream", 3-run median)

| Target | RTFx | Inference wall | vs Python `coremltools` |
|---|---:|---:|---:|
| CPU | **163×** | 6.43 s | +17.7% |
| ANE | **402×** | 2.60 s | +63.9% |
| **GPU** | **1145×** | **0.92 s** | **+176.5%** |

See [OPTIMIZATIONS.md](OPTIMIZATIONS.md) for the full journey -- how we
went from a naive port at 115× GPU to 1145× GPU without touching the
model.

## Package layout

```
Sources/
├── ParakeetTDT/
│   ├── ParakeetTranscriber.swift   Public API
│   ├── ModelDownloader.swift       HuggingFace auto-download
│   ├── ModelCache.swift            .mlpackage -> .mlmodelc compile cache
│   ├── ModelRunner.swift           Encoder input + decoder worker pool
│   ├── DecoderWorker.swift         Per-worker decode state
│   ├── Pipeline.swift              3-stage mel / encoder / decode pipeline
│   ├── GreedyTDTDecoder.swift      Greedy TDT state machine
│   ├── AudioLoader.swift           AVFoundation -> 16 kHz mono [Float]
│   ├── MelFeatureExtractor.swift   vDSP log-mel, matches HF ParakeetFeatureExtractor
│   ├── MelFilterBank.swift         Slaney-style 128-mel bank
│   ├── Tokenizer.swift             BPE/SentencePiece decode
│   ├── FeatureBag.swift            Cached MLFeatureProvider
│   └── Types.swift                 Public structs + errors
└── ParakeetCLI/
    └── ParakeetCLI.swift           `parakeet transcribe|download`
```

## Disk-constrained deployments

For iOS / kiosk apps where you want the compiled `.mlmodelc` but not the
raw `.mlpackage`:

```swift
let t = try await ParakeetTranscriber.fromHuggingFace(
    computeUnits: .ane,
    // After `.mlpackage` downloads + compiles, delete the source.
    // `.mlmodelc` cache survives; model still runs on next launch.
    // Set during first-launch setup; not applicable when using the
    // HF auto-download flow yet -- use the ModelCache(...) API directly
    // if you need this on the HF path.
)
```

For the `modelsRoot:` path specifically:

```swift
let t = try ParakeetTranscriber(
    modelsRoot: packagedURL,
    computeUnits: .ane,
    deleteSourceAfterCompile: true    // removes `.mlpackage`s after compile
)
```

## License

- **Swift source code**: Apache 2.0 ([LICENSE](LICENSE)).
- **Model weights** (pulled from HuggingFace): CC-BY-4.0, inherited
  from NVIDIA's [Parakeet-TDT-0.6B-v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3).

## Related repos

- [`mweinbach/parakeet-coreml`](https://github.com/mweinbach/parakeet-coreml)
  -- Python conversion toolchain that produced the `.mlpackage`
  artifacts (dozens of quant / palettization experiments, MIL dumps,
  RTFx benchmarks).
- [`mweinbach1/parakeet-tdt-0.6b-v3-coreml`](https://huggingface.co/mweinbach1/parakeet-tdt-0.6b-v3-coreml)
  -- HuggingFace home of the shipping model.
