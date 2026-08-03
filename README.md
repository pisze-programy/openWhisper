# OpenWhisper

Dictate anywhere, type faster. Private speech-to-text for **macOS** and **iPhone** — fully on-device, open source.

OpenWhisper turns your voice into text on your own hardware using the Parakeet TDT 0.6B v3 model. Audio never leaves your device — recordings are processed and stored locally. No cloud, no account, no training on your data.

---

## Screenshots & demos

> GIFs coming soon. Each section below has a placeholder — drop a recording there once captured.

### macOS — dictation overlay

![macOS dictation overlay in action](docs/gifs/macos-overlay.gif)

Press the global hotkey (right **⌘+⌥**), speak, release. A glass overlay shows the active app and a **live waveform** of your voice; the transcript is polished and pasted straight into whatever you're typing in.

### macOS — main window

![macOS main window: History + Settings](docs/gifs/macos-window.gif)

A timeline of every transcription grouped by day, and a full settings screen with formatting styles, permissions, API key and launch-at-login.

### iOS — on-device dictation

![iOS dictation](docs/gifs/ios-dictation.gif)

Tap the mic, talk, done. Same Parakeet engine, same private promise, on your iPhone.

### iOS — onboarding

![iOS onboarding](docs/gifs/ios-onboarding.gif)

Three-step setup: intro, one-time model download, privacy promise.

---

## Features

### macOS (primary)

- **Menu-bar app** — lives in the menu bar, one click away, no Dock clutter
- **Global hotkey dictation** — hold right **⌘+⌥** anywhere, speak, release
- **Glass status overlay** — shows the target app icon, a **live audio waveform** and per-phase status (listening → transcribing → polished → copied), with subtle animations
- **Auto-paste** — inserts the result into the frontmost app (Accessibility); auto-copy to clipboard too
- **AI text polish** — optional OpenRouter-powered rewrite in 4 styles: Formal, Casual, Minimal, Brief
- **Audio ducking** — gently lowers system volume while recording, restores after
- **Timeline history** — every transcription saved, grouped by day, tap to copy
- **Launch at login** — optional auto-start (Settings → General)
- **25 European languages**, punctuation and number normalization built in

### iOS

- **On-device voice-to-text** with selectable compute units (GPU / CPU)
- **3-step onboarding**: intro, one-time model download, privacy promise
- **Transcription history**: tap to copy, delete
- **Auto-copy** to clipboard after each transcription
- One-time **~480 MB model download** (~1.3 GB free space), then fully offline; subsequent starts ~0.2 s

### Shelved (code kept, may return)

- **Keyboard extension** — full QWERTY keyboard + dictation inside any text field
- **Live Activities** — dictation progress on the lock screen / Dynamic Island

---

## Tech stack

| | |
|---|---|
| UI | SwiftUI |
| Minimum OS | macOS 26 · iOS 18+ |
| Speech model (macOS) | [Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) via [FluidAudio](https://github.com/FluidInference/FluidAudio) |
| Speech model (iOS) | Parakeet TDT 0.6B v3 → [Core ML](https://huggingface.co/mweinbach1/parakeet-tdt-0.6b-v3-coreml) via `parakeet-coreml-swift` (vendored at `Packages/`) |
| AI formatting | [OpenRouter](https://openrouter.ai) (optional, needs API key) |
| Persistence | SwiftData, local-only |
| Shared code | `OpenWhisperShared` Swift package — prompts, punctuation, number normalization, STT orchestration, shared UI components |

---

## Project structure

```
openWhisperMac/        macOS app (menu bar, overlay, dictation pipeline)
openWhisper/           iOS app (on-device dictation, onboarding, history)
OpenWhisperShared/     shared Swift package (logic + UI used by both platforms)
OpenWhisperKeyboard/   keyboard extension — shelved
Packages/              vendored parakeet-coreml-swift
scripts/make-dmg.sh    one-command Release build → DMG for macOS
```

---

## Getting started

### macOS

1. Open `openWhisper.xcodeproj` in Xcode.
2. Run the `openWhisperMac` scheme (or build a DMG with `./scripts/make-dmg.sh`).
3. Complete onboarding: grant Microphone + Accessibility, download the model (~460 MB).
4. Hold right **⌘+⌥**, speak, release. Optionally add your OpenRouter key in Settings for AI polish.

### iOS

1. Open `openWhisper.xcodeproj` in Xcode.
2. Run on a physical iPhone (iOS 18+).
3. The model downloads on first launch (~480 MB, ~1.3 GB free space recommended).

---

## Roadmap

- **macOS 1.0** — core dictation loop, overlay, history, settings, DMG distribution
- **Polish pass** — refine formatting quality, more styles, punctuation tuning
- **Keyboard extension** (maybe) — bring back shelved extension for dictate-anywhere on iPhone
- **App Store release** — macOS (and iOS) with free on-device core

Details and decisions live in [PLAN.md](PLAN.md) and [PLAN_MACOS.md](PLAN_MACOS.md).

---

## Support

OpenWhisper is free and open source. If it saves you time:

- star the repo, and/or
- sponsor the project (GitHub Sponsors)

---

## License & attribution

- App source code: Apache-2.0
- `parakeet-coreml-swift`: Apache-2.0 — mweinbach
- Model weights: CC-BY-4.0 — NVIDIA Parakeet TDT 0.6B v3; Core ML conversion by [mweinbach1](https://huggingface.co/mweinbach1)
