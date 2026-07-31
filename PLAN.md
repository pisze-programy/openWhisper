# Development Plan — OpenWhisper

An iOS app for fully on-device speech-to-text, with a transcription history, clipboard support and a system keyboard extension. Open source, free.

---

## 1. Goal

A simple, free iPhone app that:

- records voice and transcribes it **on-device** (no cloud) with the **Parakeet TDT 0.6B v3** model (Core ML) via the **parakeet-coreml-swift** package;
- shows a **transcription history** (add / delete / clear all / copy to clipboard);
- can **auto-copy** a transcription to the clipboard after recording (paste it into any app);
- ships a **system keyboard extension** — insert transcriptions directly into the active text field without opening the app;
- is published to the App Store as a free app for other users.

**Phase 2 (described later, separate spec):** a built-in notepad plus a small language model (LLM) for on-the-fly correction of transcriptions after each note is added.

---

## 2. Technical context (verified facts)

| Item | Fact |
|---|---|
| Package | `parakeet-coreml-swift` → **vendored** at `Packages/parakeet-coreml-swift` (upstream `github.com/mweinbach/parakeet-coreml-swift` @ 0.1.1), license **Apache-2.0**. Vendored because Xcode rejects packages using `.unsafeFlags`; only change vs upstream: removed the forced `-O` flag (Debug is slower ≈40× RTFx, Release stays `-O`). |
| SPM product | library `ParakeetTDT` (min. iOS 17 / macOS 14) |
| Model | `mweinbach1/parakeet-tdt-0.6b-v3-coreml` (HF), **~450–481 MB**, license **CC-BY-4.0** (derived from NVIDIA `nvidia/parakeet-tdt-0.6b-v3`) |
| API | `ParakeetTranscriber` (`fromHuggingFace(...)` / `init(modelsRoot:cacheDirectory:...)`), `transcribe(audioURL:)` / `transcribe(samples:)`, `ParakeetComputeUnits` (`.ane` / `.gpu` / `.cpu` / `.all`), `ModelDownloader` + `ModelCache` with a progress callback |
| Audio | 16 kHz mono Float32; the package resamples and downmixes any AVFoundation format itself |
| Languages | 25 European languages (incl. **Polish**), auto-detection, built-in punctuation and capitalization |
| Download | On first run from HF, cached in `Caches` by default (we override the location — see D3); compiled to `.mlmodelc`; subsequent starts ~0.2 s |
| Known bug | [issue #1](https://github.com/mweinbach/parakeet-coreml-swift) — short clips (< ~3 s) transcribe empty, 2–5 s clips get hallucinated tail (one-line fix not yet merged) |
| Version risk | Model card states **iOS 18+** (per `per_grouped_channel` palettization), package declares iOS 17 → **to verify on device** |
| Benchmarks | No published iPhone results (only macOS M5 Max) |

---

## 3. Assumptions & architectural decisions

- **D1. 100% on-device processing, local-only data.** Privacy is a feature — **recordings never leave the phone**, and the **history is stored only on the device** (no cloud sync, no third-party servers).
- **D2. App Group** (`group.*`): shared container for the **model cache** and **history database** → the keyboard extension uses the same model and history instead of re-downloading ~480 MB.
- **D3. Model download via the low-level path**: `ModelDownloader(cacheDirectory: appGroupContainer)` → `ParakeetTranscriber(modelsRoot:cacheDirectory:)` with **`deleteSourceAfterCompile: false`** (required — the package's `resolveModel` only looks inside `modelsRoot`; deleting the `.mlpackage` sources after the first compile breaks every later launch, since compiled `.mlmodelc`s live in a separate cache dir the package never re-inspects). Download state is persisted and **resumable** (survives app kill via the package's per-file size check); custom progress UI (progress, pause/resume, errors). `fromHuggingFace()` only in the M0 spike.
- **D4. History in SwiftData**, store file inside the app group container (readable from the extension).
- **D5. Keyboard extension (Phase 1.5)**: browse recent transcriptions + insert into the active field (`UITextDocumentProxy`). **Transcribing inside the extension** (loading the ~480 MB model within the extension memory budget) is a **spike in Phase 1.5** — the feasibility result decides whether it ships in 1.5 or moves to Phase 2.
- **D6. Auto-copy to clipboard** after transcription — toggle in settings.
- **D7. Recording rules**: **no minimum duration** — a 1 s clip may come back empty and that is acceptable; **maximum recording duration 10 minutes** (recording auto-stops at 10:00); **processing lock** — transcription jobs are single-flight (never two at once; recording is blocked while a transcription is running). Keep the local patch for bug #1 (short-clip hallucination) until the upstream fix lands.
- **D8. Target**: minimum **iOS 18.0** (decided — current public iOS is 26.6, so headroom is fine). The package's declared minimum (iOS 17) is lower, so it does not constrain us.
- **D9. Licenses**: model attribution (NVIDIA + mweinbach1, CC-BY-4.0) in the README and in-app ("About" screen). Code is Apache-2.0.
- **D10. Storage & persistence — local only** (see §4a): history, settings and the model cache live in **Application Support** (non-purgeable). **No cloud sync** — history stays on the device by design (privacy). Note: iOS deletes the sandbox on app uninstall, so data does not survive deletion (accepted trade-off for local-only).
- **D11. Onboarding & model gating** (see §4c): onboarding is **mandatory** — for the testing phase it appears **on every launch** (later: show-once). Transcription is **blocked until the model is downloaded**; the UI always guides the user ("download the model in Settings") instead of failing silently.

---

## 4. Architecture (Phase 1)

```
openWhisper.xcodeproj
├── OpenWhisper (app, SwiftUI, iOS 18+)
│   ├── AudioRecorder          — AVAudioEngine, 16 kHz mono, auto-stop at 10 min
│   ├── TranscriptionService   — async wrapper around ParakeetTranscriber, single-flight lock
│   ├── ModelDownloadManager   — HF download, progress, resume, state
│   ├── HistoryStore           — SwiftData (Transcription: id, text, date, duration, source)
│   ├── ClipboardService       — UIPasteboard (copy / auto-copy)
│   ├── SettingsStore          — compute units, auto-copy, save-to-history, max duration (10 min)
│   ├── UI/Components          — reusable: GlassCard, SectionHeader, ToggleRow, NavigationRow, StatusBadge, EmptyState
│   └── UI/Screens             — History (main), Settings, Onboarding, Download, About
├── OpenWhisperKeyboard (Custom Keyboard Extension)
│   └── History + insert via UITextDocumentProxy (Phase 1.5)
└── OpenWhisperShared (local SPM package, shared)
    ├── AppGroup (identifier, cache & store paths)
    └── Data models (SwiftData / structs)
```

### Flow: first launch
1. Welcome screen → model download from HF (progress, resumable) into the app group container → compile `.mlpackage` → `.mlmodelc` (a few seconds) → delete source.
2. Subsequent launches: model in cache, start ~0.2 s.

### Flow: transcription
Recording (up to 10 min, auto-stop) → resample to 16 kHz mono → acquire the processing lock → `transcribe(samples:)` on the selected compute units (ANE default) → release the lock → result to history (SwiftData, local-only) → optionally auto-copy to clipboard. While the lock is held, new recordings and other transcriptions are blocked.

### §4a. Storage & persistence

iOS deletes an app's sandbox (including `Application Support`) when the app is uninstalled — `Caches` is additionally purgeable by the system at any time. To meet the "survive app deletion" requirement:

| Data | Location | Survives app deletion? |
|---|---|---|
| History + settings (user data) | Application Support (local only — **no cloud**) | ❌ no — accepted trade-off for local-only privacy |
| Model cache (~480 MB, compiled `.mlmodelc`) | Application Support (app group container) | ❌ no — re-downloaded from HF after reinstall (~450 MB, progress UI) |
| Preferences (compute units, auto-copy) | Application Support / UserDefaults (app group) | ❌ no — re-created on reinstall |

Rules:
- Never use `Caches` for data that must persist (the system can purge it at any time).
- The App Group container is deleted when the *last* app of the group is removed; a reinstall wipes the sandbox regardless.
- **History is local-only by design** (privacy). If cross-device sync is ever wanted, CloudKit can be added later without changing the data model.

### §4b. UI & design language (Phase 1)

**Principle: native, minimal, premium.** As little custom UI code as possible — we iterate on the look later, the structure stays.

- **Native look** — black-on-white, standard iOS controls (`NavigationStack`, `Form`/`List`, SF Symbols). No custom color schemes, no heavy branding.
- **Glass styling (iOS 26 Liquid Glass feel)** — rounded cards with `.ultraThinMaterial` backgrounds: light blur, semi-transparent, subtly responsive to the background. Applied through a few reusable components, never ad hoc per screen.
- **Settings built on SwiftUI `Form`** — guaranteed native appearance for free (sections, toggles, rows).

**Screens (3 + About):**
1. **History (main)** — the full transcription list: tap to copy, swipe to delete, "clear all"; prominent record control; empty state.
2. **Settings** — see spec below.
3. **Download / first launch** — model progress, resumable, status ("downloaded & active" / "needs download" / "re-download").
4. **About** — version, licenses & attribution (CC-BY-4.0, Apache-2.0).

**Settings screen spec (Phase 1):**
| Section | Row / control | Behavior |
|---|---|---|
| Model | Status row (`StatusBadge`) | Shows: model **downloaded, saved on device, active** / downloading (progress) / failed / needs download; **manual "Download / Re-download" action**; compute units picker (ANE default / GPU / CPU) |
| Model | Blocked transcription | If the model is missing (e.g. onboarding skipped): message **"Transcription not supported — download the model in Settings"** (badge + disabled record control) |
| Recording | Auto-copy to clipboard | Toggle, default ON |
| Recording | Max recording duration | Informational (fixed 10 min) |
| Privacy | **Save transcriptions to history** | Toggle, default ON — when OFF, transcriptions are **not persisted** (list stays empty; privacy) |
| Reserved | Language selection, notepad / LLM corrections (Phase 2) | Placeholder rows — the section structure leaves room, no logic yet |
| Reserved | Replay onboarding | Optional "Show onboarding again" (testing / future) |
| About | Version, licenses | — |

**Reusable components (`UI/Components`):** `GlassCard`, `SectionHeader`, `ToggleRow`, `NavigationRow`, `StatusBadge`, `EmptyState` — shared across History / Settings / Download / Onboarding, and later the keyboard extension and notepad.

### §4c. Onboarding (Phase 1)

**Purpose:** a mandatory, quick introduction — teaches the user what the app does and confirms they want to download the model. **Two steps**, skippable, with a video placeholder.

- **Shows on launch** — during the testing phase it appears **on every launch**; later it becomes show-once (persisted flag).
- **Step 1 — Intro:** title + one-line description (what transcriptions are) + a creative tagline (e.g. *"Speak three times faster than you type"*); **video placeholder** (AVPlayer-ready view — the real presentation clip is added later).
- **Step 2 — Model download:** explains the ~450 MB download; **"Start download"** button → download runs in the **background** (progress visible); the user can close/finish onboarding and the download continues.
- **Controls:** Skip (either step) / Next / Finish. Skipping always leads to the main app.
- **Interruptions:** if the app is killed mid-download, the download **resumes** on next launch; on failure show a message and **re-show onboarding** (or guide to Settings).
- **Model states (persisted):** `notDownloaded` → `downloading(progress)` → `ready` | `failed`. Transcription is **blocked** until `ready`; the state is surfaced everywhere relevant (record button, Settings badge).

---

## 5. Phases & milestones

| Phase | Scope | Definition of done |
|---|---|---|
| **M0 — Spike** | Add the package to the project, run on a physical iPhone. Verify on iOS 18+: load time and memory, Polish quality, short-clip behavior, first benchmarks | Measurement report; final D7/D10 details |
| **M1 — MVP app** | Onboarding (2 steps, skip, video placeholder, background download, resume/fail states); recording → transcription; history (SwiftData); delete / clear / copy; auto-copy; Settings screen (model status + manual download, compute units, save-to-history privacy toggle); download UI; reusable components | Full cycle working on device |
| **M2 — App Group** | Move cache + database into the shared container; refactor to `OpenWhisperShared` | Extension reads history without duplicated data |
| **Phase 1.5 — Keyboard** | `OpenWhisperKeyboard`: recent transcriptions, insert into active field; **spike: transcription inside the extension** (ANE memory feasibility) | Works in any app with text input; feasibility report for in-extension transcription |
| **M4 — Release** | App icon, Polish/English UI, license/attribution screen, on-device testing, privacy policy, App Store (free) | App in review / on the store |
| **Phase 2 — Notepad** | Separate spec (TBD): notepad + LLM for on-the-fly transcription correction | — |

---

## 6. Risks & mitigations

1. **Model runtime on iOS 18+** (palettized artifacts) — verify in M0 on real devices; if any OS version is incompatible, pin it in the deployment target.
2. **Memory in the keyboard extension** (~480 MB model vs extension budget) — in F1 the extension only reads history; in-extension transcription is a separate spike.
3. **Short-clip bug (issue #1)** — empty result for very short clips is acceptable; hallucinated tail on 2–5 s clips mitigated by a local patch/fork until the upstream fix lands.
4. **480 MB download** — progress UI, resumability, shared cache in Application Support (non-purgeable). After an app reinstall the model must be re-downloaded (no sandbox location survives deletion) — documented in the UI.
5. **App Store review** — external model download: attribution screen, privacy policy, CC-BY-4.0 compliance (commercial use allowed, attribution required).
6. **No iPhone benchmarks** — measure in M0, optimize for ANE.
7. **Permissions** — microphone (app); keyboard constraints awareness (insert works without Full Access; Full Access needed e.g. to write to the clipboard from the extension).
8. **Vendored package drift** — `Packages/parakeet-coreml-swift` is a fork (unsafeFlags removed); re-sync from upstream on new releases; the short-clip bug (#1) can be patched here directly if needed.

---

## 7. Licenses & attribution

- **App source code:** Apache-2.0.
- **`parakeet-coreml-swift` package:** Apache-2.0 (author: mweinbach).
- **Model:** CC-BY-4.0 — `nvidia/parakeet-tdt-0.6b-v3` + Core ML conversion `mweinbach1/parakeet-tdt-0.6b-v3-coreml`. Attribution in README and in-app.

---

## 8. Open questions / decisions

1. ~~Name~~ **Resolved:** OpenWhisper (product name — no typo); repo folder stays `openWhisper`.
2. ~~Minimum iOS~~ **Resolved:** 18.0.
3. ~~Storage~~ **Resolved:** local-only (no cloud) — Application Support (D10); data does not survive app deletion (accepted).
4. ~~Transcription in the keyboard extension~~ **Resolved:** Phase 1.5 — spike + feasibility decides shipping.
5. ~~UI languages~~ **Resolved:** Polish + English for now; all languages planned later.
6. ~~App Store regions~~ **Resolved:** Global distribution — EU, USA, UK (excluding India, Asia, Africa, South America).
