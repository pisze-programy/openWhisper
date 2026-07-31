# OpenWhisper

On-device speech-to-text for iPhone. Free, open source, private.

OpenWhisper turns your voice into text directly on your iPhone using the **Parakeet TDT 0.6B v3** model (Core ML) via the [`parakeet-coreml-swift`](https://github.com/mweinbach/parakeet-coreml-swift) package. Audio never leaves your device — recordings are processed and stored locally. No cloud, no account.

## Features

- **Voice-to-text on-device** — ANE / GPU / CPU compute units, selectable
- **25 European languages** (incl. Polish), auto-detected; punctuation + capitalization built in
- **Transcription history** — copy, delete, or clear all
- **Auto-copy to clipboard** — paste anywhere with one tap
- **Up to 10-minute recordings** — auto-stopped; processing is serialized (no concurrent transcriptions)
- **Keyboard extension** — insert past transcriptions into any text field without opening the app
- **2-step onboarding** — quick intro with demo video (placeholder for now) and one-tap model download
- **One-time model download** (~450 MB) on first launch, stored persistently — subsequent starts take ~0.2 s
- **100% local history** — transcriptions stay on your device, never synced to any cloud
- Works fully **offline** after the initial download

## Why

- **Private** — speech processing and history stay entirely on your iPhone
- **Free & open source** — no subscriptions, no telemetry
- **Fast** — optimized for the Apple Neural Engine

## Tech stack

| | |
|---|---|
| UI | SwiftUI |
| Minimum OS | iOS 18+ |
| Speech model | [Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) → [Core ML](https://huggingface.co/mweinbach1/parakeet-tdt-0.6b-v3-coreml) (CC-BY-4.0) |
| Swift package | [`parakeet-coreml-swift`](https://github.com/mweinbach/parakeet-coreml-swift) (Apache-2.0) |
| Persistence | SwiftData, local-only (shared via App Group) |
| Extensions | Custom Keyboard Extension |

## Getting started

1. Open `openWhisper.xcodeproj` in Xcode.
2. The `parakeet-coreml-swift` package is **vendored** at `Packages/parakeet-coreml-swift` (Xcode rejects the upstream package because it uses `.unsafeFlags`; the only local change is removing that flag). It is already referenced in the project — no action needed.
3. Run on a physical iPhone (model download is ~450 MB on first launch).
4. Enable the keyboard (Phase 1.5): Settings → General → Keyboard → Keyboards → Add New Keyboard → OpenWhisper.

## Project layout

```
openWhisper.xcodeproj
├── OpenWhisper            — main app (recording, history, settings)
├── OpenWhisperKeyboard    — keyboard extension (insert from history)
└── OpenWhisperShared      — shared App Group container + data models
```

## Roadmap

- **Phase 1 (in progress):** MVP app — onboarding, recording → transcription, history, clipboard, settings, download UI
- **Phase 1.5:** Keyboard extension — history insertion + in-extension transcription (spike)
- **Phase 2:** Built-in notepad with on-device LLM correction of transcriptions
- **Phase 3:** App Store release (free)

Detailed planning lives in [PLAN.md](PLAN.md).

## License & attribution

- **App source code:** Apache-2.0
- **`parakeet-coreml-swift`:** Apache-2.0 — © mweinbach
- **Model weights:** CC-BY-4.0 — [NVIDIA Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3), Core ML conversion by [mweinbach1](https://huggingface.co/mweinbach1)
