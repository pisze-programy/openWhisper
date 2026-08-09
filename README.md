<p align="center">
  <img src="logo.png" width="80" alt="OpenWhisper logo">
</p>

<h1 align="center">OpenWhisper</h1>

<p align="center">
  <strong>Dictate · Format · Translate.</strong><br>
  Private speech-to-text for **macOS** & **iPhone** — on-device, open source.<br>
  Hold hotkey → speak → release → text at the cursor. No cloud · no account · audio stays on your device.
</p>

<p align="center">Powered by <a href="https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3">Parakeet TDT 0.6B v3</a> on Apple Silicon.</p>

---

## Hotkeys

| Action | macOS |
|---|---|
| **Dictate (STT)** | hold **right ⌘+⌥**, speak, release |
| **Cycle format style** | hold **right ⌥**, tap **right ⇧** |
| **Cycle translation target** | hold **right ⌘**, tap **right ⇧** |

---

## Demos — STT · Formatting · Translation

### STT

<p align="center">
  <img src="docs/assets/macos/Rec-copy-paste.gif" width="100%" alt="STT demo">
  <br><em>Hold right ⌘+⌥ → speak → release → "Copied". Glass overlay with live waveform.</em>
</p>

### Formatting

<p align="center">
  <img src="docs/assets/macos/STT-formatting-style.gif" width="100%" alt="Formatting style demo">
  <br><em>Hold right ⌥, tap right ⇧ → overlay cycles styles → green check.</em>
</p>

### Translation

<!-- Translation demo — replace this full-width placeholder with:
     <video src="docs/assets/macos/translate.mp4" width="100%" controls muted loop></video>
     once the mp4 is added. -->
<p align="center">
  <table width="100%">
    <tr>
      <td align="center">
        <strong>Translation</strong> — hold right ⌘, tap right ⇧ → overlay cycles the target (None/English/…) → green check. Dictation is translated into the selected target.<br>
        <em>Demo video coming soon.</em>
      </td>
    </tr>
  </table>
</p>

---

## App

### Menu bar

<p align="center">
  <img src="docs/assets/macos/menu-bar.jpeg" width="520" alt="OpenWhisper menu bar">
</p>

Menu bar — status · Dictation · Translate · Settings · style picker · copy last transcription.

### Main window

<p align="center">
  <table>
    <tr>
      <td align="center" width="50%">
        <img src="docs/assets/macos/settings.jpeg" width="100%" alt="Settings">
        <br><em>Settings — API key, audio, history, permissions.</em>
      </td>
      <td align="center" width="50%">
        <img src="docs/assets/macos/history.jpg" width="100%" alt="History">
        <br><em>History — grouped by day, tap to copy.</em>
      </td>
    </tr>
    <tr>
      <td align="center" width="50%">
        <img src="docs/assets/macos/formatting-styles.jpeg" width="100%" alt="Formatting">
        <br><em>Formatting — rewrite styles or None.</em>
      </td>
      <td align="center" width="50%">
        <img src="docs/assets/macos/dication.jpeg" width="100%" alt="Dictation">
        <br><em>Dictation — speech model, auto-copy/paste.</em>
      </td>
    </tr>
    <tr>
      <td colspan="2" align="center">
        <img src="docs/assets/macos/translate.jpeg" width="100%" alt="Translate">
        <br><em>Translate — target languages + right ⌘+⇧ cycle shortcut.</em>
      </td>
    </tr>
  </table>
</p>

### iOS

iOS demos coming soon.

---

## Features

**macOS (primary)**
- **Menu-bar app** — no Dock clutter
- **Global hotkey STT** — right ⌘+⌥, anywhere
- **Glass overlay** — app icon, live waveform, phase status
- **Auto-paste** — into frontmost app (Accessibility); auto-copy too
- **AI formatting** — Formal · Casual · Minimal · Brief (OpenRouter, optional)
- **Translation** — dictation translated into the target chosen with right ⌘+⇧
- **Media handling** — pause music/video (Music, Spotify, YouTube) while dictating and resume where it stopped (public build); the App Store build mutes the output instead
- **Timeline history** — grouped by day, tap to copy
- **Launch at login**
- **25 European languages** — punctuation + number normalization

**iOS**
- **On-device STT** — GPU/CPU compute units
- **3-step onboarding** — intro, model download, privacy promise
- **History** — tap to copy, delete
- **Auto-copy** after each transcription
- **~480 MB model** — one-time, then fully offline

**Shelved (code kept, may return)**
- **Keyboard extension** — QWERTY + dictation in any text field
- **Live Activities** — progress on lock screen / Dynamic Island

---

## Tech stack

| | |
|---|---|
| UI | SwiftUI |
| Minimum OS | macOS 26 · iOS 18+ |
| STT (macOS) | [Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) via [FluidAudio](https://github.com/FluidInference/FluidAudio) |
| STT (iOS) | Parakeet TDT 0.6B v3 → [Core ML](https://huggingface.co/mweinbach1/parakeet-tdt-0.6b-v3-coreml) via [parakeet-coreml-ios](https://github.com/pisze-programy/parakeet-coreml-ios) (vendored at `Packages/`) |
| AI formatting & translation | [OpenRouter](https://openrouter.ai) (optional, needs API key) |
| Persistence | SwiftData, local-only |
| Shared code | `OpenWhisperShared` — prompts, punctuation, numbers, STT, UI |

---

## Project structure

```
openWhisperMac/        macOS app — menu bar, overlay, STT + formatting + translation
openWhisper/           iOS app — on-device STT, onboarding, history
OpenWhisperShared/     shared Swift package — logic + UI for both platforms
OpenWhisperKeyboard/   keyboard extension — shelved
Packages/              vendored parakeet-coreml-ios
scripts/make-dmg.sh    one-command Release build → DMG
```

---

## Getting started

**macOS**
1. Open `openWhisper.xcodeproj` in Xcode.
2. Run the `openWhisperMac` scheme (or `./scripts/make-dmg.sh`).
3. Onboarding — Microphone + Accessibility + model download (~460 MB).
4. Hold **right ⌘+⌥** → speak → release. Add OpenRouter key in **Settings → API Key** for formatting/translation.

**iOS**
1. Open `openWhisper.xcodeproj` in Xcode.
2. Run on a physical iPhone (iOS 18+).
3. Model downloads on first launch (~480 MB, ~1.3 GB free recommended).

---

## Roadmap

- **macOS 1.0** — core STT, overlay, history, settings, DMG
- **macOS 1.1–1.3** — AI formatting styles, translation target cycle (right ⌘+⇧), Translate tab, shared selector overlay, UX polish
- **macOS 1.4** — media handling while dictating (pause on the public build, mute on the App Store build), Release-Store build config
- **Keyboard extension** (maybe) — dictate-anywhere on iPhone
- **App Store** — macOS (and iOS), free on-device core

Details and decisions: [PLAN.md](PLAN.md) · [PLAN_MACOS.md](PLAN_MACOS.md).

---

## Release notes

- **v1.4** — Media handling while dictating: pause playback (Music/Spotify/YouTube) and resume where it stopped on the public build; the App Store build mutes the output instead. Toggle in Settings → Dictation.

---

## Support

OpenWhisper is free and open source. If it saves you time:
- **star** the repo
- **sponsor** the project (GitHub Sponsors)

---

## License & attribution

- **App source**: Apache-2.0
- **parakeet-coreml-ios**: Apache-2.0 — [pisze-programy/parakeet-coreml-ios](https://github.com/pisze-programy/parakeet-coreml-ios) (our fork of `parakeet-coreml-swift`, faster, improved, tested)
- **Model weights**: CC-BY-4.0 — NVIDIA Parakeet TDT 0.6B v3
