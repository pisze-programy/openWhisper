# Development Plan — OpenWhisper

An iOS app for fully on-device speech-to-text, with a transcription history, clipboard support and a system keyboard extension. Open source, free.

---

## 1. Goal

An iPhone app with three pillars: a **free, private on-device dictation**, a **full Apple-style notepad**, and a **paid cloud tier** (keyboard dictation + LLM polish). Published to the App Store.

**Free tier (offline, private):**
- on-device voice transcription with the **Parakeet TDT 0.6B v3** model (Core ML) via the **parakeet-coreml-swift** package — no cloud, no account;
- a **notepad** (Apple Notes style): categories/tabs + documents, transcriptions saved as notes;
- **transcription history** (add / delete / copy) — the incoming voice queue feeding the notepad;
- **auto-copy** to the clipboard after recording;
- the **keyboard extension is NOT free**: free users see a pricing/paywall screen.

**Paid tier (subscription, online only):**
- **keyboard dictation** — cloud STT via OpenRouter (`nvidia/parakeet-tdt-0.6b-v3`), inserts text into any app;
- **LLM polish with styles** (formal, casual, optimistic, …) — a cloud LLM (OpenRouter) reformats transcriptions in the app **and** in the keyboard.

Offline, free users get raw local transcription only (no LLM polish, no keyboard).

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
- **D2 [Done]. App Group** (`group.pl.piszeprogramy.openwhisper`): shared container for the model cache and history database → the keyboard extension will use the same model and history instead of re-downloading ~480 MB.
- **D3 [Done]. Model download via the low-level path**: `ModelDownloader(cacheDirectory:)` → `ParakeetTranscriber(modelsRoot:cacheDirectory:)` with **`deleteSourceAfterCompile: false`** (required — the package's `resolveModel` only looks inside `modelsRoot`; deleting the `.mlpackage` sources after the first compile breaks every later launch). Download is persisted and **resumable** (survives app kill via the package's per-file size check); custom progress UI. Cache and the SwiftData store live in the App Group container via the `OpenWhisperShared` package.
- **D4 [Done]. History in SwiftData**, store file inside the app group container (readable from the extension).
- **D5 [Planned — Phase 1.5]. Keyboard extension (redesigned)**: a **full keyboard** (QWERTY typing) plus **cloud dictation** — record → transcribe via an **external STT provider** (OpenRouter `nvidia/parakeet-tdt-0.6b-v3`) → insert text into the active field via `UITextDocumentProxy`. The ~480 MB model is **never loaded in the extension** (jetsam kills the process); the original "transcribe-in-extension" spike is abandoned. **The keyboard never browses history** — it only writes to the shared history store when saving a dictation (respecting the app's `saveToHistory`/`autoCopy` settings). See §4e.
- **D6 [Done]. Auto-copy to clipboard** after transcription — toggle in settings.
- **D7 [Done]. Recording rules**: no minimum duration (a 1 s clip may come back empty — acceptable); **maximum recording duration 10 minutes** (auto-stops); **auto-stop on silence** (default 5 s of continuous silence stops the recording early — VAD via RMS on the live 16 kHz samples in the shared `AudioCapturePipeline`; toggle + timeout stored in settings, mirrored to the App Group so the keyboard honors it too; main cost-saver for cloud dictation); **single-flight processing lock** (never two transcriptions at once; recording is blocked while one runs). Audio-session interruptions (calls/Siri) stop the recording and transcribe what was captured. Local patch for bug #1 (short-clip hallucination) kept until the upstream fix lands.
- **D8 [Done]. Target**: minimum **iOS 18.0** (current public iOS is 26.6, headroom is fine).
- **D9 [Done]. Licenses**: model attribution (NVIDIA + mweinbach1, CC-BY-4.0) in the README and in-app ("About" screen). Code is Apache-2.0.
- **D10 [Done]. Storage & persistence — local only** (see §4a): history, settings and the model cache live in **Application Support** (non-purgeable). No cloud sync — history stays on the device by design (privacy). iOS deletes the sandbox on app uninstall, so data does not survive deletion (accepted trade-off for local-only).
- **D11 [Done]. Onboarding & model gating** (see §4c): onboarding is **mandatory** — during the testing phase it appears **on every launch** (later: show-once). Transcription is **blocked until the model is downloaded**; the UI always guides the user ("download the model in Settings") instead of failing silently.
- **D12 [Done]. Audio level normalization** (à la TypeWhisper `MicrophoneBoostProcessor`): `AudioNormalizer` boosts quiet mic input to `targetRMS = 0.1` (gain 1–20, clamped) before transcription — fixes distorted words from the raw `.measurement`-mode capture.
- **D13 [Done]. Corrections dictionary**: user-editable "heard as → should be" map (`CorrectionsStore`), applied as whole-word case-insensitive regex on new transcriptions. Cheap post-process layer; the heavy **CTC vocabulary boosting** (context biasing) is deferred to Phase 2 (see §5).
- **D14 [Everything stays public — final].** The **entire app ships in the public repo (Apache-2.0), including the paid-tier features** (keyboard, cloud STT, LLM polish, subscription). Rationale: competition isn't a near-term risk worth sacrificing the open-source story for; the moat is UX + the business spec, not the code itself. **Only business-sensitive artifacts stay private**: `playbook.md` (unit economics / strategy — gitignored) and credentials. The repo and app carry a **sponsor / paid-tier CTA** (GitHub Sponsors + subscription row). Revisit (privatize the repo, split the paid app) only if/when the paid tier generates meaningful revenue — the owner can dual-license or take the repo private then.

---

## 4. Architecture (current)

```
openWhisper.xcodeproj
├── openWhisper (app, SwiftUI, iOS 18+)
│   ├── Services/
│   │   ├── Audio/                 AudioRecorder, AudioCapturePipeline, RecorderError
│   │   ├── Transcription/         TranscriptionService, TranscriptionEngine, TranscriptionError
│   │   ├── LLM/                   (Phase 2) LLMPolishService, style presets, OpenRouter client
│   │   ├── Paywall/               (paid tier) SubscriptionManager, entitlement flags
│   │   └── (singletons)           ModelDownloadManager, ModelStatus, SettingsStore, ClipboardService
│   └── Views/
│       ├── Components/            GlassCard, StatusBadge, ToggleRow, NavigationRow, SectionHeader,
│       │                          EmptyState, ModelCardView, VideoPlaceholder
│       ├── Onboarding/            OnboardingView (paging), IntroView, ModelView, PrivacyView
│       ├── Notepad/               (Phase 2) NotepadRootView (categories/tabs), NoteEditorView, NoteListView
│       ├── History/               HistoryView, HistoryRow (the voice queue feeding the notepad)
│       ├── Settings/              SettingsView, SettingsModelSection, SettingsLanguageSection,
│       │                          SettingsLLMSection (styles), SettingsSubscriptionSection
│       ├── About/                 AboutView
│       └── RootView.swift
├── OpenWhisperShared (local SPM package)   — AppGroup, ModelLocations, TranscriptionItem, Language
└── Packages/parakeet-coreml-swift (vendored)

Planned (redesign, Phase 1.5):
└── OpenWhisperKeyboard — full keyboard + cloud dictation (OpenRouter) + LLM polish (paid)
```

**Note on history vs notepad:** `HistoryView` stays as the *incoming voice queue* (latest transcriptions). The notepad is a separate layer on top: categories/tabs + documents where transcriptions get saved/edited. History and notes are both backed by the same SwiftData store.

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
| Upcoming | Notepad (free) / LLM polish styles (paid) | Phase 2 — see §5 |
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
| 300 | **LLM polish (styles)** | Paid, Phase 2 (spec below) | Cloud LLM (OpenRouter) rewrites the transcript into a selected style (formal / casual / optimistic / …). **Free tier skips this step** — raw local transcription only. |
| 500 | **Snippets** | ❌ Rejected | Text shortcuts — out of scope. |
| 600 | **Corrections dictionary** | ✅ D13 | "heard as → should be", user-editable, whole-word case-insensitive (optionally exact-case). |
| — | **Audio level normalization** | ✅ D12 | `AudioNormalizer` boost before decode (TypeWhisper `MicrophoneBoostProcessor`). |
| — | **CTC vocabulary boosting** | Phase 2 | Context biasing of the decoder with user/prompt terms (TypeWhisper `CtcKeywordSpotter` + `VocabularyRescorer`). |

**Prompt / context boosting (planned, Phase 2):** a user-provided *prompt* (e.g. the topic or expected terms) is parsed into boosting terms and fed to the decoder context-bias step — exactly TypeWhisper's `configureBoostingIfNeeded(prompt:dictionaryTermHints:)` (terms from the prompt when no explicit dictionary hints are set). The prompt also feeds the LLM correction step (step 300) as context.

#### LLM polish (priority 300, Phase 2 — paid tier)

**What it does:** turns a raw transcript into a clean, nicely formatted note — the "magic" users see in competitors (Wispr Flow). Runs on a **cloud LLM via OpenRouter** (the same provider serving Parakeet for the paid keyboard).

**Empty-state CTA (do it with the LLM polish work):** the first-launch empty state in `HistoryView` already shows "Try saying:" example prompts that start a recording. When LLM polish ships, extend it:
- Add **more example options** (additional prompts) and, most importantly,
- **advertise the formatting capability**: next to an example like *"Let me draft a quick email to my client…"* show a hint such as *"We'll pick the best format for your message"* / *"Format it for you"* — making it clear the user can record e.g. an email and have it **automatically formatted to a chosen style (formal/casual/…)** by the LLM.
- The message should be explicit: speech-to-text **plus** automatic style formatting (no extra steps).

**When it runs:** after number normalization + speech punctuation, before the corrections dictionary — it fixes an already lexically clean transcript.

**Styles (selectable, each = a prompt preset):**
| Style | Effect (prompt intent) |
|---|---|
| Formal | Professional, polished, complete sentences |
| Casual | Natural spoken tone, relaxed phrasing |
| Optimistic | Positive framing, energetic |
| Concise | Short, to the point |
| (extensible) | New presets added as data — no code changes |

**Availability:**
- **Paid tier:** styles selectable per note (in the app) and per dictation (in the keyboard). Online only.
- **Free tier / offline:** step 300 is **skipped** — the transcript is used raw (steps 100/200/600 still apply).
- On failure/empty output → fall back to the raw transcript (never block or lose the transcription).

**Provider:** OpenRouter chat/completions, a cheap-but-good model (e.g. a small instruction-tuned model); the exact model slug and prompt template live with the client. Attribution headers (`HTTP-Referer`, `X-OpenRouter-Title`) set.

**Prompt template (draft):**
```
Rewrite this transcript into {style} Polish/English. Fix obvious transcription
errors; keep the meaning and all information; do not invent facts. Preserve the
speaker's words. Output only the rewritten text.
Transcript: <text>
```

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
- **DD5 — Monetization (future, paid tier).** Apple subscription via StoreKit (in-app purchase, Apple Pay):
  - **Free tier** — everything local & offline: on-device dictation, notepad, history, corrections dictionary. No LLM polish, no keyboard (the keyboard shows a pricing/paywall screen).
  - **Basic — $2.99/month**: keyboard cloud dictation + LLM polish with styles; usage limits (e.g. 30k words/month).
  - **Pro — $4.99/month**: keyboard + LLM polish with higher limits (e.g. 120k words/month).
  - Onboarding gains a **pricing step** (pricing table + benefits); Settings gets a subscription row; the keyboard and the LLM-polish button are entitlement-gated (free users see the paywall).
  - Note: our unit economics (see the private `playbook.md`) put cloud COGS at ~15–25% of revenue; the free tier costs ~$0 to serve (local model).
- **DD6 — Notepad = free, LLM polish = paid.** The Apple-style notepad (categories/tabs, documents) is a **free** feature; the LLM style polishing is **paid** and gated by the subscription. Offline/free users can still dictate into the notepad (raw text).
- **DD7 — Reformat existing text (keyboard, FUTURE — not now).** A keyboard action that **reformats the input's existing text** with the same paid LLM style presets (formal / casual / optimistic / …). **Selection is supported**: `textDocumentProxy.selectedText` is readable, so a selected range is reformatted; otherwise fall back to the whole context (`documentContextBeforeInput` + `documentContextAfterInput`, nudged via `adjustTextPosition(byCharacterOffset: 0)` to refresh the proxy cache after a paste). Replace pattern (validated against the MIT-licensed `translatekb` repo): with a selection → `insertText` overwrites it in one shot; without → move cursor to the end, `deleteBackward` × (before+after count), `insertText`. Styles follow the **Tone-prompt pattern**: enum with `displayName` + SF `symbol` + a short per-style instruction; the full LLM chat template is ours (their CloudLLMToneAdapter is an unimplemented stub). Gated to the paid tier (text leaves the device to OpenRouter), with a **length cap** on the reformatted input (token-cost/abuse control). Same error/fallback rules as dictation (on failure, leave the text untouched). Ships after the LLM polish service exists (Phase 2) — see milestone note.

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

**Keyboard UI (UIKit, `UIInputViewController`) — DICTATION-ONLY (no typing keys).**
- Surface: header (title/status/language hint) + a large **mic button** + a **return-to-keyboard button** (SF Symbol `keyboard.chevron.compact.down` → opens the input switcher via `handleInputModeList`, so the user picks the default keyboard). **The system globe is hidden** (`needsInputModeSwitchKey = false`). No QWERTY/letters/symbols keys.
- Dictating: replaces the keyboard area with a live waveform + elapsed time + red stop + cancel (✕); auto-stop at 60 s + silence auto-stop (shared setting); on stop → "Transcribing…" spinner → insert text → back to the main surface.
- Save behavior: respects the app's shared settings (`autoCopy` → copy to clipboard; `saveToHistory` → write a `TranscriptionItem` into the shared SwiftData store so the app shows the entry). **The keyboard never browses/selects history — it only writes to it when saving a dictation.**
- States: no API key → mic disabled + "Set your API key in OpenWhisper"; no subscription entitlement (later) → paywall hint; no network → inline error (typed text preserved); empty/short result → ignore; extension suspended mid-record → stop and send.

**Milestones.**
1. **M-K1** — Shared plumbing: move audio capture + waveform bars + `SilencePadding` to shared; `OpenRouterSTTClient`; **move `TranscriptionEngine` to the app target; drop `ParakeetTDT` from `OpenWhisperShared`**; shared settings/Keychain keys. App regression check. ✅ done
2. **M-K2** — Settings UI (Keychain API key + enable toggle + privacy copy).
3. **M-K3** — ✅ done → **superseded**: the keyboard is dictation-only (typing keys removed).
4. **M-K4** — Dictation: mic → waveform → 60 s cap + padding → STT → insert; save-to-history write + auto-copy; `NSMicrophoneUsageDescription` in the extension Info.plist; permission flow.
5. **M-K5** — Hardening: 60 s cap, error/offline/no-key UX, extension lifecycle (suspend → abort & send), iPhone/iPad layout, haptics.
6. **M-K6** — (future) Paid tier (DD5): StoreKit tiers ($2.99 Basic / $4.99 Pro with word limits), **entitlement gating** (keyboard + LLM polish show the paywall for free users), onboarding pricing step, Settings subscription row.
7. **M-K7 (future, not now) — Reformat text (DD7):** keyboard action that reformats the input's existing content with the paid LLM style presets — **selection supported**, falls back to whole context; length cap + paid gate. Blocks on the LLM polish service from Phase 2.

**Risks / open questions.**
- Resolved: API key → **Keychain** (app-group sharing). Extension model code → **removed** (`TranscriptionEngine` moves to app target; `OpenWhisperShared` drops `ParakeetTDT`).
- Provider 60 s processing timeout → 60 s dictation cap + short clips; verify latency on device.
- Recording inside an extension must be validated on a physical device (mic permission + `AVAudioSession` in extension context; simulator unreliable).
- App Store: keyboard extensions that record + network need the mic usage string and review-safe copy; subscription review requirements (M-K7).
- Privacy: keyboard dictation sends audio to the provider — must be transparent (the app-level model stays local/private).
- Future: own backend API or backend-less secure key distribution (evaluate at M-K7, before shipping paid tiers).

### §4f. Future — macOS app (OPTIONAL, parked)

> **Status: parked vision, not a commitment.** Revisit after the keyboard phase + paid tier ship. Decide then whether to build, how, or reject (see open questions).

**Why it's interesting:** the local model already runs on Apple silicon (verified — CLI + M5 Max benchmarks), so a native Mac app is technically cheap to enable. The competitor (Wispr Flow) ships Mac + Windows with sync, so the category expects it eventually.

**Vision (Mac-native UX, not a port):**
- **Menu bar app** (`MenuBarExtra`) — lives in the menu bar, no full-screen app;
- **Global keyboard shortcut** → transcribe from anywhere (Parakeet locally);
- **Notes window** + Settings window (SwiftUI `Window` / `Settings` scenes);
- Shares `OpenWhisperShared` + `ParakeetTDT` with the iOS app.

**Key structural work (when we get there):**
1. Extend `OpenWhisperShared` platforms to `[.iOS("18.0"), .macOS("15.0")]` (content is already cross-platform: audio, SwiftData, networking).
2. Extract a third package **`OpenWhisperEngine`** (TranscriptionEngine + ParakeetTDT) linked only by app targets (iOS + macOS) — keeps the keyboard Parakeet-free (per DD3).
3. Add a native macOS target; share SwiftUI views (`History`, `Settings`, notepad) with `#if os(macOS)` where needed; platform-specific audio/permissions (no `AVAudioSession`; TCC mic prompt).

**Open questions (decide later — may also reject):**
1. **Sync: CloudKit vs own account vs none.** CloudKit syncs via the user's Apple ID with **no custom backend/account** (attractive) but moves data through iCloud (dilutes the "100% local/private" story). Own account = backend + auth + GDPR (big cost). No sync = each device local (weak value for a Mac app).
2. Does the value justify it? A Mac app without sync is weak; with sync it's a multi-month project. Revisit after the paid tier proves demand.
3. Mac App Store vs direct distribution / notarization / sandbox for the menu bar app.

**Decision rule:** only start this if (a) the paid tier is live and showing traction, and (b) we accept one of the sync paths. Otherwise reject/park indefinitely.

---

## 5. Phases & milestones

| Phase | Status | Scope | Definition of done |
|---|---|---|---|
| **M0 — Spike** | **Done** | Package integrated (vendored), model download + transcription verified on a physical iPhone, audio pipeline fixed (WAV write via `.inputRanDry`) | Transcription works on device (incl. Polish) |
| **M1 — MVP app** | **Done** | Onboarding (3 steps, skip, video/screenshot placeholders, background download, resume/fail states); recording → transcription; history (SwiftData); delete / copy; auto-copy; Settings (ModelCardView, compute units, save-to-history, language picker); reusable components; clean file structure | Full cycle working on device |
| **M2 — App Group** | **Done** | Shared App Group container (`group.pl.piszeprogramy.openwhisper`); model cache + SwiftData store moved; `OpenWhisperShared` package extracted | Store and model cache live in the group container (verified on simulator) |
| **Phase 1.5 — Keyboard** | Planned | `OpenWhisperKeyboard` (redesign, §4e): full QWERTY keyboard + **cloud dictation** via OpenRouter `nvidia/parakeet-tdt-0.6b-v3` + save-to-history write (no history browsing in the keyboard); `OpenRouterSTTClient` + shared audio/waveform in `OpenWhisperShared`; API key in Settings; mic permission | Works in any app with text input; dictation inserts text without loading the model in-extension |
| **M4 — Release** | Planned | App icon, Polish/English UI, real video/screenshot assets, on-device testing, privacy policy, App Store (free) | App in review / on the store |
| **Phase 2 — Notepad + LLM polish** | Planned | **Notepad (free):** Apple-style categories/tabs + documents; transcriptions saved as notes; HistoryView stays as the incoming voice queue. **LLM polish (paid):** cloud LLM (OpenRouter) rewrites transcriptions into selectable styles (formal / casual / optimistic / …) — in the app and the keyboard; **incl. the Empty-State CTA** (see §4d) advertising "speech-to-text + auto formatting". **Paid tier:** StoreKit subscription ($2.99 Basic / $4.99 Pro, word limits), paywall in the keyboard + LLM-polish gate, onboarding pricing step. **Extends to dictation quality:** if the corrections dictionary (D13) + LLM polish aren't enough for mixed-language / code-switched words, add **CTC vocabulary boosting** (context biasing): download a separate ~110M CTC keyword-spotter model (à la TypeWhisper's Parakeet plugin) and port `CtcKeywordSpotter` + `VocabularyRescorer` into the vendored decoder to bias it toward user dictionary terms. Stacked on top of D13 — the two compose (boost during decode, corrections on text after) | Notepad works free & offline; paid tier gates keyboard + LLM polish; StoreKit wired |

---

## 6. Risks & mitigations

1. **Memory in the keyboard extension** — resolved by design: the ~480 MB model is never loaded in the extension. Dictation uses the external provider. The extension only records short clips (16 kHz mono buffer) and makes a network request; keep buffers small and cap recording length (jetsam safety + provider 60 s processing timeout).
2. **Short-clip bug (issue #1)** — empty result for very short clips is acceptable; hallucinated tail on 2–5 s clips mitigated by a local patch/fork until the upstream fix lands (we control the vendored copy).
3. **480 MB download** — progress UI, resumability, cache in Application Support (non-purgeable). After an app reinstall the model must be re-downloaded (no sandbox location survives deletion) — documented in the UI.
4. **Disk usage** — sources are kept (`deleteSourceAfterCompile: false`): ~1.1–1.3 GB after download + compile. Acceptable for MVP; can be optimized later.
5. **App Store review** — external model download: attribution screen, privacy policy, CC-BY-4.0 compliance (commercial use allowed, attribution required).
6. **Vendored package drift** — `Packages/parakeet-coreml-swift` is a fork (unsafeFlags removed); re-sync from upstream on new releases; the short-clip bug (#1) can be patched here directly if needed.
7. **GPU-in-background console flood (log noise, not correctness)** — when the user releases the mic and immediately switches apps, the GPU transcription attempt runs while the app is backgrounded; iOS forbids GPU/Metal work in the background, so **every encoder/decoder chunk logs** `IOGPUMetalError: Insufficient Permission (to submit GPU work from background)` — 100+ lines per backgrounded transcription. The result is still recovered via the **CPU fallback** (which now re-checks the current `applicationState`, not a stale capture), and `warmGPUShaders` skips when not active — so it's **cosmetic but noisy**. Mitigations to evaluate in hardening: (a) re-check `applicationState` immediately before starting the GPU inference to shrink the race window, (b) cancel the GPU path early when the app backgrounds (observe `scenePhase`), (c) accept the noise and document it.

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
