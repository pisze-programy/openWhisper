# Development Plan — OpenWhisper

An iOS app for fully on-device speech-to-text, with a transcription history, clipboard support and a system keyboard extension. Open source, free.

---

## 1. Goal

A simple, free iPhone app that:

- records voice and transcribes it **on-device** (no cloud) with the **Parakeet TDT 0.6B v3** model (Core ML) via the **parakeet-coreml-swift** package;
- shows a **transcription history** (add / delete / copy to clipboard);
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
- **D2 [Done]. App Group** (`group.piszeprogramy.openWhisper`): shared container for the model cache and history database → the keyboard extension will use the same model and history instead of re-downloading ~480 MB.
- **D3 [Done]. Model download via the low-level path**: `ModelDownloader(cacheDirectory:)` → `ParakeetTranscriber(modelsRoot:cacheDirectory:)` with **`deleteSourceAfterCompile: false`** (required — the package's `resolveModel` only looks inside `modelsRoot`; deleting the `.mlpackage` sources after the first compile breaks every later launch). Download is persisted and **resumable** (survives app kill via the package's per-file size check); custom progress UI. Cache and the SwiftData store live in the App Group container via the `OpenWhisperShared` package.
- **D4 [Done]. History in SwiftData**, store file inside the app group container (readable from the extension).
- **D5 [Planned — Phase 1.5]. Keyboard extension (redesigned)**: a **full keyboard** (QWERTY typing) plus **cloud dictation** — record → transcribe via an **external STT provider** (OpenRouter `nvidia/parakeet-tdt-0.6b-v3`) → insert text into the active field via `UITextDocumentProxy`. The ~480 MB model is **never loaded in the extension** (jetsam kills the process); the original "transcribe-in-extension" spike is abandoned. History browse/insert is kept as a secondary panel. See §4e.
- **D6 [Done]. Auto-copy to clipboard** after transcription — toggle in settings.
- **D7 [Done]. Recording rules**: no minimum duration (a 1 s clip may come back empty — acceptable); **maximum recording duration 10 minutes** (auto-stops); **single-flight processing lock** (never two transcriptions at once; recording is blocked while one runs). Audio-session interruptions (calls/Siri) stop the recording and transcribe what was captured. Local patch for bug #1 (short-clip hallucination) kept until the upstream fix lands.
- **D8 [Done]. Target**: minimum **iOS 18.0** (current public iOS is 26.6, headroom is fine).
- **D9 [Done]. Licenses**: model attribution (NVIDIA + mweinbach1, CC-BY-4.0) in the README and in-app ("About" screen). Code is Apache-2.0.
- **D10 [Done]. Storage & persistence — local only** (see §4a): history, settings and the model cache live in **Application Support** (non-purgeable). No cloud sync — history stays on the device by design (privacy). iOS deletes the sandbox on app uninstall, so data does not survive deletion (accepted trade-off for local-only).
- **D11 [Done]. Onboarding & model gating** (see §4c): onboarding is **mandatory** — during the testing phase it appears **on every launch** (later: show-once). Transcription is **blocked until the model is downloaded**; the UI always guides the user ("download the model in Settings") instead of failing silently.
- **D12 [Done]. Audio level normalization** (à la TypeWhisper `MicrophoneBoostProcessor`): `AudioNormalizer` boosts quiet mic input to `targetRMS = 0.1` (gain 1–20, clamped) before transcription — fixes distorted words from the raw `.measurement`-mode capture.
- **D13 [Done]. Corrections dictionary**: user-editable "heard as → should be" map (`CorrectionsStore`), applied as whole-word case-insensitive regex on new transcriptions. Cheap post-process layer; the heavy **CTC vocabulary boosting** (context biasing) is deferred to Phase 2 (see §5).

---

## 4. Architecture (current)

```
openWhisper.xcodeproj
├── openWhisper (app, SwiftUI, iOS 18+)
│   ├── Services/
│   │   ├── Audio/                 AudioRecorder, AudioCapturePipeline, RecorderError
│   │   ├── Transcription/         TranscriptionService, TranscriptionEngine, TranscriptionError
│   │   └── (singletons)           ModelDownloadManager, ModelStatus, SettingsStore, ClipboardService
│   └── Views/
│       ├── Components/            GlassCard, StatusBadge, ToggleRow, NavigationRow, SectionHeader,
│       │                          EmptyState, ModelCardView, VideoPlaceholder
│       ├── Onboarding/            OnboardingView (paging), IntroView, ModelView, PrivacyView
│       ├── History/               HistoryView, HistoryRow
│       ├── Settings/              SettingsView, SettingsModelSection, SettingsLanguageSection
│       ├── About/                 AboutView
│       └── RootView.swift
├── OpenWhisperShared (local SPM package)   — AppGroup, ModelLocations, TranscriptionItem, Language
└── Packages/parakeet-coreml-swift (vendored)

Planned (redesign, Phase 1.5):
└── OpenWhisperKeyboard — full keyboard + cloud dictation (OpenRouter) + history insert
```

### Flow: first launch
1. Onboarding → model download from HF (progress, resumable) into the App Group container → compile `.mlpackage` → `.mlmodelc` (a few seconds).
2. Subsequent launches: model in cache, start ~0.2 s.

### Flow: transcription
Recording (up to 10 min, auto-stop) → resample to 16 kHz mono → acquire the single-flight lock → `transcribe(samples:)` on the selected compute units (ANE default) → release the lock → result to history (SwiftData, local-only) → optionally auto-copy to clipboard.

### §4a. Storage & persistence

iOS deletes an app's sandbox (including `Application Support`) when the app is uninstalled; `Caches` is additionally purgeable by the system at any time.

| Data | Location | Survives app deletion? |
|---|---|---|
| History + settings (user data) | App Group container (local only, no cloud) | No — accepted trade-off for local-only privacy |
| Model cache (~480 MB, compiled `.mlmodelc`) | App Group container | No — re-downloaded from HF after reinstall (~450 MB, progress UI) |
| Preferences (compute units, auto-copy, language) | UserDefaults (app sandbox) | No — re-created on reinstall |

Rules:
- Never use `Caches` for data that must persist (the system can purge it at any time).
- The App Group container is deleted when the *last* app of the group is removed; a reinstall wipes it regardless.
- History is local-only by design (privacy). If cross-device sync is ever wanted, CloudKit can be added later without changing the data model.

### §4b. UI & design language (current)

Native, minimal, premium. Black-on-white, standard iOS controls (`NavigationStack`, `Form`/`List`, SF Symbols). Glass styling (iOS 26 Liquid Glass feel) via `.ultraThinMaterial` rounded cards, applied through reusable components only. Settings built on SwiftUI `Form`.

**Screens:** History (main), Settings, Onboarding, About. The model download/progress UI is the reusable `ModelCardView` (used in onboarding step 2 and Settings).

**Settings spec (current):**
| Section | Row / control | Behavior |
|---|---|---|
| Model | `ModelCardView` | Shows the model state machine: not downloaded → downloading (progress) → ready ("Saved on this device") → failed ("Try Again"); Re-download action; compute units picker (GPU / CPU — ANE/All supported internally, not exposed) with a hardware description footer |
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

### §4d. Post-processing pipeline (planned — modeled on TypeWhisper `PostProcessingPipeline`)

Priority-ordered text steps applied to every new transcription, in order. Earlier steps get cleaner input; later steps fix the rest.

| Prio | Step | Status | Notes |
|---|---|---|---|
| 100 | **Number normalization** (PL + EN) | ✅ Done | "dwa tysiące trzysta" / "two hundred" → digits (`NumberNormalizer`, whole-word, diacritics-safe). |
| 200 | **Speech punctuation** | ✅ Done | Light `SpeechPunctuation`: sentence-capitalize, single space after `.`/`!`/`?`, no space before punctuation. |
| 300 | **LLM correction** | Phase 2 (spec below) | On-device/cloud LLM rewrites the transcript for fluency + mixed-language fixes, with provider fallback order. |
| 500 | **Snippets** | ❌ Rejected | Text shortcuts — out of scope. |
| 600 | **Corrections dictionary** | ✅ D13 | "heard as → should be", user-editable, whole-word case-insensitive (optionally exact-case). |
| — | **Audio level normalization** | ✅ D12 | `AudioNormalizer` boost before decode (TypeWhisper `MicrophoneBoostProcessor`). |
| — | **CTC vocabulary boosting** | Phase 2 | Context biasing of the decoder with user/prompt terms (TypeWhisper `CtcKeywordSpotter` + `VocabularyRescorer`). |

**Prompt / context boosting (planned, Phase 2):** a user-provided *prompt* (e.g. the topic or expected terms) is parsed into boosting terms and fed to the decoder context-bias step — exactly TypeWhisper's `configureBoostingIfNeeded(prompt:dictionaryTermHints:)` (terms from the prompt when no explicit dictionary hints are set). The prompt also feeds the LLM correction step (step 300) as context.

#### LLM correction (priority 300, Phase 2) — detail

**When it runs:** mid-pipeline — after number normalization and speech punctuation, before the corrections dictionary — so it fixes a transcript that is already lexically clean.

**Inputs:** the raw transcript text + optional user prompt/context (see below).

**Providers (ordered fallback, à la TypeWhisper):** the user picks an order from a global list; a failed/rate-limited/empty attempt falls through to the next provider:
1. On-device (default): Apple Intelligence (macOS 26+) or a local MLX model (Gemma-class) — private, offline, slower.
2. Cloud: OpenAI-compatible / Groq / etc. — only when the user explicitly enables cloud.

**Prompt template (draft):**
```
Correct the transcript for spelling, punctuation and mixed-language
code-switching. Preserve the speaker's words and meaning; fix obvious
transcription errors; do not add or remove information. Keep the same length.
Context: <user prompt/context>
Transcript: <text>
```

**Behavior:**
- On failure or empty output → fall back to the raw transcript (never block or lose the transcription).
- Preserve the corrections dictionary and number-normalized values (runs after them).
- On-device by default; cloud only behind an explicit opt-in (privacy promise in onboarding).

**UI:** Settings toggle **"Smart corrections"** (on/off) + provider order; the history row can show a subtle "corrected" badge.

#### Prompt / context boosting (Phase 2) — detail

**Source of the prompt:** optional user-provided context — a text field in Settings ("Context / expected terms") or per-recording — e.g. a topic, names, product terms.

**Two uses:**
1. **Decoder boosting:** the prompt is parsed into significant terms (tokenize → strip stopwords → keep 2+ char words) and passed to the CTC vocabulary-boosting step (context bias). If the CTC model isn't available, boosting silently skips.
2. **LLM context:** the same prompt is appended to the LLM correction template above.

**Term hygiene (à la TypeWhisper):**
- Whole-word, case-insensitive boosting; limit term count and length (over-boosting degrades WER).
- Explicit dictionary terms (D13) always take precedence over prompt-derived terms.
- `ctcMinSimilarity` threshold can be tuned per term (TypeWhisper does this) to allow near-miss matches.

**Degradation:** a bad prompt can hurt accuracy — so prompt-derived terms are capped (e.g. ≤ 20 terms) and only enabled when the user provides context.

### §4e. Keyboard extension with cloud dictation (Phase 1.5) — plan

**Context.** The original keyboard plan (D5) was history-only, with a feasibility spike to transcribe inside the extension using the ~480 MB model. That spike is abandoned: loading the model in a keyboard extension's memory budget crashes the process (jetsam). The new direction ships a **real keyboard** (typing) with **cloud dictation**: record a short clip → transcribe via an external STT provider → insert text into the active field.

**Provider (verified).** OpenRouter, model `nvidia/parakeet-tdt-0.6b-v3` (confirmed in OpenRouter's STT catalog — `output_modalities: transcription`, ~$0.0015/minute).

- Endpoint: `POST https://openrouter.ai/api/v1/audio/transcriptions`
- Auth: `Authorization: Bearer <OPENROUTER_API_KEY>`, `Content-Type: application/json`
- Body (JSON, base64 audio): `{ "model": "nvidia/parakeet-tdt-0.6b-v3", "input_audio": { "data": "<base64 wav>", "format": "wav" }, "language": "<ISO-639-1, optional>" }`
- Response: `{ "text": "…", "usage": { "seconds": …, "total_tokens": …, "input_tokens": …, "output_tokens": …, "cost": … } }`
- OpenAI-compatible `multipart/form-data` also works (base URL `https://openrouter.ai/api/v1`); multipart cap 25 MB.
- Upstream provider processing timeout ≈ 60 s → **hard cap dictation at 60 s** (auto-stop).
- Optional attribution headers: `HTTP-Referer`, `X-OpenRouter-Title`.

**Decisions.**
- **DD1 — No model in the extension.** Dictation = record (16 kHz mono Float32) → pad → base64 WAV → OpenRouter → insert. Retires risk #1 and the D5 spike.
- **DD1a — 60 s cap + silence padding.** Keyboard dictations hard-cap at **60 s** (auto-stop). Before sending, apply the **same padding the local model uses** (`ParakeetTranscriber.prepareAudio`: **0.5 s lead-in**, **1.5 s trailing silence**, pad to **min 5 s** total) — it measurably improved local transcription quality. Extract the constants into a shared `SilencePadding` helper so both paths stay consistent.
- **DD2 — BYOK first, subscription later.** The user pastes an OpenRouter API key in app Settings, stored in the **Keychain** shared via app-group keychain sharing (readable by the extension). Gate flag `keyboardDictationEnabled` is the placeholder for the future paid subscription. Local app dictation + notepad stay **always free**.
- **DD3 — Single shared lightweight package; zero duplication.** All code used by both app and keyboard lives **only** in `OpenWhisperShared` (no copy-paste between targets): move `AudioCapturePipeline` (AVFoundation) + a `WaveformBars` pure function (port of `LiveWaveform.bars`) into it, add `OpenRouterSTTClient` (Foundation networking) + `SilencePadding`. After the `TranscriptionEngine` move (below), `OpenWhisperShared` depends on **system frameworks only** (Foundation, SwiftData, AVFoundation, Observation) — no third-party packages. Both app and keyboard link the same small shared framework; **nothing heavy is pulled into the extension**, so load stays fast. App-only (heavy/private): `ParakeetTDT` + `TranscriptionEngine` + model download/settings stay in the app target.
- **DD4 — Language.** Pass the pinned `languageCode` (shared settings) as `language` when set; omit for auto-detection.
- **DD5 — Monetization (future, M-K7).** Apple subscription via StoreKit (in-app purchase, Apple Pay):
  - **Basic — $2.99/month**: keyboard cloud dictation with usage limits (e.g. minutes/day or message caps).
  - **Pro — $4.99/month (max)**: unlimited / higher limits.
  - Onboarding gains a **pricing step** (pricing table + benefits, e.g. "dictate anywhere", "no 480 MB download", "same Parakeet model"); Settings gets a subscription row. A paid tier is required because OpenRouter bills per minute. Later options to evaluate: our own backend API as a proxy, or a secure key-distribution mechanism without a backend intermediary.

**New/changed files.**
- `OpenWhisperShared/Sources/OpenWhisperShared/OpenRouterSTTClient.swift` — `Sendable` struct with stored `apiKey` + optional `language` (ISO-639-1): `transcribe(wavData:) async throws -> String`; base64 JSON request to `https://openrouter.ai/api/v1/audio/transcriptions`, model `nvidia/parakeet-tdt-0.6b-v3`, 65 s timeout; error mapping (400 bad request, 401/402/403 auth, 429 rate limit, other → server, plus network/invalidResponse/emptyTranscription); optional attribution headers (`HTTP-Referer`, `X-OpenRouter-Title`).
- `OpenWhisperShared/Sources/OpenWhisperShared/SilencePadding.swift` — shared constants + helper mirroring `ParakeetTranscriber.prepareAudio` (0.5 s lead, 1.5 s trail, min 5 s).
- `OpenWhisperShared/Sources/OpenWhisperShared/WaveformBars.swift` — pure `bars(from:count:)` used by `LiveWaveform` (SwiftUI) and the extension's `WaveformView` (UIKit).
- `OpenWhisperShared` shared settings keys — `cloudApiKey` + `keyboardDictationEnabled` (extend `AppGroup`). **M-K1 adds the shared key names only**; actual Keychain storage + keychain-sharing entitlement land in M-K2 (Settings phase).
- `openWhisper/Services/Transcription/TranscriptionEngine.swift` — **moved from shared** into the app target (only used by `TranscriptionService`); `OpenWhisperShared/Package.swift` drops the `ParakeetTDT` dependency.
- `openWhisper/Views/Settings/SettingsKeyboardSection.swift` — secure API key field, enable toggle, privacy note ("audio is sent to your chosen provider"), link to OpenRouter keys page; later a subscription row (DD5).
- `OpenWhisperKeyboard/KeyboardViewController.swift` — rewrite (UI below).
- `OpenWhisperKeyboard/WaveformView.swift` — UIKit bars view (uses shared `WaveformBars`).
- `OpenWhisperKeyboard/KeyboardEngine.swift` — key layout + action model (typing page, symbols page).
- `OpenWhisperKeyboard/DictationController.swift` — records via the shared pipeline, live samples → bars, stop (≤60 s, padded) → `OpenRouterSTTClient` → `textDocumentProxy.insertText`.

**Keyboard UI (UIKit, `UIInputViewController`).**
- Top bar: globe (keyboard switching via `handleInputModeList`), title/status, mode toggle (typing ⇄ history), mic button.
- Typing: 3 QWERTY rows + shift; bottom row: globe · [123] · space · return · backspace. Symbols page ([123→ABC]).
- Dictating: replaces the keyboard area with a live waveform + elapsed time + red stop + cancel (✕); auto-stop at 60 s; on stop → "Transcribing…" spinner → insert text → back to typing.
- History: recent transcriptions list (SwiftData, shared store), tap to insert, back button (kept from the current build).
- States: no API key → mic disabled + "Set your API key in OpenWhisper"; no subscription entitlement (later) → paywall hint; no network → inline error (typed text preserved); empty/short result → ignore; extension suspended mid-record → stop and send.

**Milestones.**
1. **M-K1** — Shared plumbing: move audio capture + waveform bars + `SilencePadding` to shared; `OpenRouterSTTClient`; **move `TranscriptionEngine` to the app target; drop `ParakeetTDT` from `OpenWhisperShared`**; shared settings/Keychain keys. App regression check.
2. **M-K2** — Settings UI (Keychain API key + enable toggle + privacy copy).
3. **M-K3** — Keyboard typing mode (QWERTY + actions) — usable end-to-end without dictation.
4. **M-K4** — Dictation: mic → waveform → 60 s cap + padding → STT → insert; `NSMicrophoneUsageDescription` in the extension Info.plist; permission flow.
5. **M-K5** — History panel (keep browse/insert).
6. **M-K6** — Hardening: 60 s cap, error/offline/no-key UX, extension lifecycle (suspend → abort & send), iPhone/iPad layout, haptics.
7. **M-K7** — (future) Subscription (DD5): StoreKit tiers ($2.99 Basic w/ limits, $4.99 Pro), onboarding pricing step, Settings subscription row, entitlement gating.

**Risks / open questions.**
- Resolved: API key → **Keychain** (app-group sharing). Extension model code → **removed** (`TranscriptionEngine` moves to app target; `OpenWhisperShared` drops `ParakeetTDT`).
- Provider 60 s processing timeout → 60 s dictation cap + short clips; verify latency on device.
- Recording inside an extension must be validated on a physical device (mic permission + `AVAudioSession` in extension context; simulator unreliable).
- App Store: keyboard extensions that record + network need the mic usage string and review-safe copy; subscription review requirements (M-K7).
- Privacy: keyboard dictation sends audio to the provider — must be transparent (the app-level model stays local/private).
- Future: own backend API or backend-less secure key distribution (evaluate at M-K7, before shipping paid tiers).

---

## 5. Phases & milestones

| Phase | Status | Scope | Definition of done |
|---|---|---|---|
| **M0 — Spike** | **Done** | Package integrated (vendored), model download + transcription verified on a physical iPhone, audio pipeline fixed (WAV write via `.inputRanDry`) | Transcription works on device (incl. Polish) |
| **M1 — MVP app** | **Done** | Onboarding (3 steps, skip, video/screenshot placeholders, background download, resume/fail states); recording → transcription; history (SwiftData); delete / copy; auto-copy; Settings (ModelCardView, compute units, save-to-history, language picker); reusable components; clean file structure | Full cycle working on device |
| **M2 — App Group** | **Done** | Shared App Group container (`group.piszeprogramy.openWhisper`); model cache + SwiftData store moved; `OpenWhisperShared` package extracted | Store and model cache live in the group container (verified on simulator) |
| **Phase 1.5 — Keyboard** | Planned | `OpenWhisperKeyboard` (redesign, §4e): full QWERTY keyboard + **cloud dictation** via OpenRouter `nvidia/parakeet-tdt-0.6b-v3` + history insert panel; `OpenRouterSTTClient` + shared audio/waveform in `OpenWhisperShared`; API key in Settings; mic permission | Works in any app with text input; dictation inserts text without loading the model in-extension |
| **M4 — Release** | Planned | App icon, Polish/English UI, real video/screenshot assets, on-device testing, privacy policy, App Store (free) | App in review / on the store |
| **Phase 2 — Notepad** | Planned | Separate spec (TBD): notepad + LLM for on-the-fly transcription correction. **Extends to dictation quality:** if the corrections dictionary (D13) + LLM correction aren't enough for mixed-language / code-switched words, add **CTC vocabulary boosting** (context biasing): download a separate ~110M CTC keyword-spotter model (à la TypeWhisper's Parakeet plugin) and port `CtcKeywordSpotter` + `VocabularyRescorer` into the vendored decoder to bias it toward user dictionary terms. Stacked on top of D13 — the two compose (boost during decode, corrections on text after) | — |

---

## 6. Risks & mitigations

1. **Memory in the keyboard extension** — resolved by design: the ~480 MB model is never loaded in the extension. Dictation uses the external provider. The extension only records short clips (16 kHz mono buffer) and makes a network request; keep buffers small and cap recording length (jetsam safety + provider 60 s processing timeout).
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
4. Keyboard dictation: **external provider** (OpenRouter `nvidia/parakeet-tdt-0.6b-v3`) — the ~480 MB model is never loaded in the extension; recording + cloud transcription in-extension (no feasibility spike needed).
5. UI languages: **Polish + English** for now; all languages planned later.
6. App Store regions: **Global distribution** — EU, USA, UK (excluding India, Asia, Africa, South America).
7. Onboarding: 3 steps (Intro / Model / Privacy) with video + screenshot placeholders.

Open:
1. Onboarding show-once flag (testing mode shows it on every launch today).
2. Real video and screenshot assets for onboarding.
3. App icon.
4. Localization rollout (PL + EN first).
