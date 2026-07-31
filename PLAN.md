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
| Download | On first run from HF into **Application Support** (we override the package default `Caches` — see D3); compiled to `.mlmodelc`; subsequent starts ~0.2 s |
| Known bug | [issue #1](https://github.com/mweinbach/parakeet-coreml-swift) — short clips (< ~3 s) transcribe empty, 2–5 s clips get hallucinated tail (one-line fix not yet merged) |
| Runtime | Verified on device (recording → transcription works, incl. Polish); deployment target **iOS 18.0** |
| Benchmarks | No formal iPhone benchmarks yet (informal device testing done; only macOS M5 Max numbers published) |

---

## 3. Assumptions & architectural decisions

Status legend: **[Done]** implemented and verified · **[Planned]** designed, not yet built.

- **D1 [Done]. 100% on-device processing, local-only data.** Privacy is a feature — recordings never leave the phone, and the history is stored only on the device (no cloud sync, no third-party servers).
- **D2 [Planned — M2]. App Group** (`group.*`): shared container for the model cache and history database → the keyboard extension uses the same model and history instead of re-downloading ~480 MB.
- **D3 [Done]. Model download via the low-level path**: `ModelDownloader(cacheDirectory:)` → `ParakeetTranscriber(modelsRoot:cacheDirectory:)` with **`deleteSourceAfterCompile: false`** (required — the package's `resolveModel` only looks inside `modelsRoot`; deleting the `.mlpackage` sources after the first compile breaks every later launch). Download is persisted and **resumable** (survives app kill via the package's per-file size check); custom progress UI. Cache currently lives in the app sandbox's Application Support; moving it into the app group container is part of M2.
- **D4 [Planned — M2]. History in SwiftData**, store file inside the app group container (readable from the extension). Today the store lives in the app sandbox.
- **D5 [Planned — Phase 1.5]. Keyboard extension**: browse recent transcriptions + insert into the active field (`UITextDocumentProxy`). **Transcribing inside the extension** (loading the ~480 MB model within the extension memory budget) is a **spike in Phase 1.5** — the feasibility result decides whether it ships in 1.5 or moves to Phase 2.
- **D6 [Done]. Auto-copy to clipboard** after transcription — toggle in settings.
- **D7 [Done]. Recording rules**: no minimum duration (a 1 s clip may come back empty — acceptable); **maximum recording duration 10 minutes** (auto-stops); **single-flight processing lock** (never two transcriptions at once; recording is blocked while one runs). Audio-session interruptions (calls/Siri) stop the recording and transcribe what was captured. Local patch for bug #1 (short-clip hallucination) kept until the upstream fix lands.
- **D8 [Done]. Target**: minimum **iOS 18.0** (current public iOS is 26.6, headroom is fine).
- **D9 [Done]. Licenses**: model attribution (NVIDIA + mweinbach1, CC-BY-4.0) in the README and in-app ("About" screen). Code is Apache-2.0.
- **D10 [Done]. Storage & persistence — local only** (see §4a): history, settings and the model cache live in **Application Support** (non-purgeable). No cloud sync — history stays on the device by design (privacy). iOS deletes the sandbox on app uninstall, so data does not survive deletion (accepted trade-off for local-only).
- **D11 [Done]. Onboarding & model gating** (see §4c): onboarding is **mandatory** — during the testing phase it appears **on every launch** (later: show-once). Transcription is **blocked until the model is downloaded**; the UI always guides the user ("download the model in Settings") instead of failing silently.

---

## 4. Architecture (current)

```
openWhisper.xcodeproj
└── openWhisper (app, SwiftUI, iOS 18+)
    ├── Models/                    Language, TranscriptionItem (SwiftData)
    ├── Services/
    │   ├── Audio/                 AudioRecorder, AudioCapturePipeline, RecorderError
    │   ├── Transcription/         TranscriptionService, TranscriptionEngine, TranscriptionError
    │   └── (singletons)           ModelDownloadManager, ModelLocations, ModelStatus, SettingsStore, ClipboardService
    └── Views/
        ├── Components/            GlassCard, StatusBadge, ToggleRow, NavigationRow, SectionHeader,
        │                          EmptyState, ModelCardView, VideoPlaceholder
        ├── Onboarding/            OnboardingView (paging), IntroView, ModelView, PrivacyView
        ├── History/               HistoryView, HistoryRow
        ├── Settings/              SettingsView, SettingsModelSection, SettingsLanguageSection
        ├── About/                 AboutView
        └── RootView.swift

Planned (not built yet):
├── OpenWhisperKeyboard — keyboard extension (Phase 1.5)
└── OpenWhisperShared   — local SPM package with App Group container (M2)
```

### Flow: first launch
1. Onboarding → model download from HF (progress, resumable) into Application Support → compile `.mlpackage` → `.mlmodelc` (a few seconds).
2. Subsequent launches: model in cache, start ~0.2 s.

### Flow: transcription
Recording (up to 10 min, auto-stop) → resample to 16 kHz mono → acquire the single-flight lock → `transcribe(samples:)` on the selected compute units (ANE default) → release the lock → result to history (SwiftData, local-only) → optionally auto-copy to clipboard.

### §4a. Storage & persistence

iOS deletes an app's sandbox (including `Application Support`) when the app is uninstalled; `Caches` is additionally purgeable by the system at any time.

| Data | Location | Survives app deletion? |
|---|---|---|
| History + settings (user data) | Application Support (local only, no cloud) | No — accepted trade-off for local-only privacy |
| Model cache (~480 MB, compiled `.mlmodelc`) | Application Support | No — re-downloaded from HF after reinstall (~450 MB, progress UI) |
| Preferences (compute units, auto-copy, language) | UserDefaults | No — re-created on reinstall |

Rules:
- Never use `Caches` for data that must persist (the system can purge it at any time).
- The App Group container (planned, M2) is deleted when the *last* app of the group is removed; a reinstall wipes the sandbox regardless.
- History is local-only by design (privacy). If cross-device sync is ever wanted, CloudKit can be added later without changing the data model.

### §4b. UI & design language (current)

Native, minimal, premium. Black-on-white, standard iOS controls (`NavigationStack`, `Form`/`List`, SF Symbols). Glass styling (iOS 26 Liquid Glass feel) via `.ultraThinMaterial` rounded cards, applied through reusable components only. Settings built on SwiftUI `Form`.

**Screens:** History (main), Settings, Onboarding, About. The model download/progress UI is the reusable `ModelCardView` (used in onboarding step 2 and Settings).

**Settings spec (current):**
| Section | Row / control | Behavior |
|---|---|---|
| Model | `ModelCardView` | Shows the model state machine: not downloaded → downloading (progress) → ready ("Saved on this device") → failed ("Try Again"); Re-download action; compute units picker (ANE / GPU / CPU / All) with a hardware description footer |
| Model | Blocked transcription | If the model is missing (e.g. onboarding skipped): "Transcription not supported — download the model in Settings" (badge + disabled record control) |
| Recording | Auto-copy to clipboard | Toggle, default ON |
| Recording | Max recording duration | Informational (fixed 10 min) |
| Privacy | Save transcriptions to history | Toggle, default ON — when OFF, transcriptions are not persisted |
| Language | Single-select picker | Auto (Recommended) + 25 languages, one selection; persisted (`SettingsStore.languageCode`); note: Parakeet auto-detects — the pinned language is stored for Phase 2 use |
| Upcoming | Notepad / LLM corrections | Disabled placeholder (Phase 2) |
| About | Version, licenses | Attribution (CC-BY-4.0, Apache-2.0) |

**Reusable components:** `GlassCard`, `SectionHeader`, `ToggleRow`, `NavigationRow`, `StatusBadge`, `EmptyState`, `ModelCardView`, `VideoPlaceholder` — shared across screens, later the keyboard extension and notepad.

### §4c. Onboarding (current)

Mandatory, skippable introduction. **Three steps**, native horizontal paging (`TabView` + page style); vertical scrolling only when the content exceeds the screen (`scrollBounceBehavior(.basedOnSize)`).

- **Shows on launch** — during the testing phase it appears on every launch; later it becomes show-once (persisted flag).
- **Step 1 — Intro:** title, one-line description, creative tagline ("Speak three times faster than you type."), **video placeholder** (real clip added later).
- **Step 2 — Model download:** explains the ~450 MB one-time download; `ModelCardView` with Start/Progress/Ready states; **video placeholder** below (keyboard extension & live transcription demo, later).
- **Step 3 — Privacy:** one-line promise — transcriptions are never used to train models and everything stays on the device; **screenshot placeholder** (real screenshot added later).
- **Controls:** Skip (always available) / Continue / Finish. Skipping always leads to the main app; the download keeps running.
- **Interruptions:** if the app is killed mid-download, the download resumes on next launch; on failure show a message and re-show onboarding (or guide to Settings).
- **Model states (persisted):** `notDownloaded` → `downloading(progress)` → `ready` | `failed`. Transcription is blocked until `ready`.

---

## 5. Phases & milestones

| Phase | Status | Scope | Definition of done |
|---|---|---|---|
| **M0 — Spike** | **Done** | Package integrated (vendored), model download + transcription verified on a physical iPhone, audio pipeline fixed (WAV write via `.inputRanDry`) | Transcription works on device (incl. Polish) |
| **M1 — MVP app** | **Done** | Onboarding (3 steps, skip, video/screenshot placeholders, background download, resume/fail states); recording → transcription; history (SwiftData); delete / clear / copy; auto-copy; Settings (ModelCardView, compute units, save-to-history, language picker); reusable components; clean file structure | Full cycle working on device |
| **M2 — App Group** | Planned | Move cache + database into the shared container; refactor to `OpenWhisperShared` | Extension reads history without duplicated data |
| **Phase 1.5 — Keyboard** | Planned | `OpenWhisperKeyboard`: recent transcriptions, insert into active field; spike: transcription inside the extension (ANE memory feasibility) | Works in any app with text input; feasibility report |
| **M4 — Release** | Planned | App icon, Polish/English UI, real video/screenshot assets, on-device testing, privacy policy, App Store (free) | App in review / on the store |
| **Phase 2 — Notepad** | Planned | Separate spec (TBD): notepad + LLM for on-the-fly transcription correction | — |

---

## 6. Risks & mitigations

1. **Memory in the keyboard extension** (~480 MB model vs extension budget) — Phase 1.5 spike decides; the extension may only read history.
2. **Short-clip bug (issue #1)** — empty result for very short clips is acceptable; hallucinated tail on 2–5 s clips mitigated by a local patch/fork until the upstream fix lands (we control the vendored copy).
3. **480 MB download** — progress UI, resumability, cache in Application Support (non-purgeable). After an app reinstall the model must be re-downloaded (no sandbox location survives deletion) — documented in the UI.
4. **Disk usage** — sources are kept (`deleteSourceAfterCompile: false`): ~1.1–1.3 GB after download + compile. Acceptable for MVP; can be optimized later.
5. **App Store review** — external model download: attribution screen, privacy policy, CC-BY-4.0 compliance (commercial use allowed, attribution required).
6. **Vendored package drift** — `Packages/parakeet-coreml-swift` is a fork (unsafeFlags removed); re-sync from upstream on new releases; the short-clip bug (#1) can be patched here directly if needed.

---

## 7. Licenses & attribution

- **App source code:** Apache-2.0.
- **`parakeet-coreml-swift` package:** Apache-2.0 (author: mweinbach).
- **Model:** CC-BY-4.0 — `nvidia/parakeet-tdt-0.6b-v3` + Core ML conversion `mweinbach1/parakeet-tdt-0.6b-v3-coreml`. Attribution in README and in-app.

---

## 8. Decisions & open questions

Resolved:
1. Name: **OpenWhisper** (no typo); repo folder stays `openWhisper`.
2. Minimum iOS: **18.0**.
3. Storage: **local-only** (no cloud) — Application Support; data does not survive app deletion (accepted).
4. Transcription in the keyboard extension: **Phase 1.5** — spike + feasibility decides shipping.
5. UI languages: **Polish + English** for now; all languages planned later.
6. App Store regions: **Global distribution** — EU, USA, UK (excluding India, Asia, Africa, South America).
7. Onboarding: 3 steps (Intro / Model / Privacy) with video + screenshot placeholders.

Open:
1. Onboarding show-once flag (testing mode shows it on every launch today).
2. Real video and screenshot assets for onboarding.
3. App icon.
4. Localization rollout (PL + EN first).
