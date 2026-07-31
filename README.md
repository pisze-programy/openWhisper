# OpenWhisper

On-device speech-to-text for iPhone. Free, open source, private.

OpenWhisper turns your voice into text directly on your iPhone using the Parakeet TDT 0.6B v3 model (Core ML) via the `parakeet-coreml-swift` package. Audio never leaves your device — recordings are processed and stored locally. No cloud, no account.

## Features

- Voice-to-text on device, with selectable compute units (ANE / GPU / CPU)
- 25 European languages, auto-detected; punctuation and capitalization built in
- Transcription history: copy (tap), delete (swipe), clear all
- Auto-copy to clipboard after each transcription
- Up to 10-minute recordings; processing is serialized (no concurrent transcriptions)
- 3-step onboarding: intro, one-time model download, privacy promise
- One-time ~480 MB model download (needs ~1.3 GB free space), then fully offline; subsequent starts take ~0.2 s
- 100% local history — transcriptions stay on your device, never used for training

## Examples

- Dictate a message, then paste it straight into Messages or Mail (auto-copy is on by default).
- Transcribe a short note or a meeting point without typing.
- Come back later and copy any past transcription again — or delete it, or clear the whole history.
- Record up to 10 minutes in one take; the app stops and transcribes automatically at the limit.

## Tech stack

| | |
|---|---|
| UI | SwiftUI |
| Minimum OS | iOS 18+ |
| Speech model | [Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) → [Core ML](https://huggingface.co/mweinbach1/parakeet-tdt-0.6b-v3-coreml) (CC-BY-4.0) |
| Swift package | [parakeet-coreml-swift](https://github.com/mweinbach/parakeet-coreml-swift) (Apache-2.0), vendored at `Packages/` |
| Persistence | SwiftData, local-only |
| Extensions | Keyboard extension planned (Phase 1.5) |

## Getting started

1. Open `openWhisper.xcodeproj` in Xcode.
2. The vendored package is already referenced — no action needed.
3. Run on a physical iPhone (iOS 18+). The model downloads on first launch (~480 MB, ~1.3 GB free space recommended).

## Up next

- Phase 1.5 — keyboard extension: insert past transcriptions into any text field; feasibility spike for in-extension transcription
- Phase 2 — built-in notepad with on-device LLM correction of transcriptions
- Phase 3 — App Store release (free)

Details, decisions and milestones live in [PLAN.md](PLAN.md).

## License & attribution

- App source code: Apache-2.0
- `parakeet-coreml-swift`: Apache-2.0 — mweinbach
- Model weights: CC-BY-4.0 — NVIDIA Parakeet TDT 0.6B v3, Core ML conversion by [mweinbach1](https://huggingface.co/mweinbach1)
