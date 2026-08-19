# OpenWhisper macOS — Implementation Plan (v1.3)

Goal: a macOS menu-bar dictation app that mirrors the iOS OpenWhisper experience —
press-and-hold a global hotkey to record, transcribe on-device, optionally rewrite
with an LLM, auto-copy to clipboard, and auto-paste into the active input. Reuses
the existing iOS codebase (STT runtime, OpenWhisperShared, prompts, LLM formatting)
and improves iOS in the same iteration.

Target: macOS 26 Tahoe. Accessory app (LSUIElement, no Dock icon), menu-bar icon,
full main window with Onboarding → History → Settings.

**v1.3 — editorial rules:** the only product/repo name is **OpenWhisper**. Files are
named by **purpose** (architectural role), never by the reference source. No external
app or repo is mentioned in code, comments, filenames, docs, or commits. Prompts and
text-processing are our own wording inspired by proven, battle-tested dictation-app
patterns — never copied verbatim.

---

## Locked decisions

| Area | Decision |
|---|---|
| Hotkey | `NSEvent` global monitor. Hold right **⌘+⌥** = record start, release = stop, **ESC** = cancel (second Esc optional to confirm). No KeyboardShortcuts dependency |
| Recording | In-memory `[Float]` buffer; feed STT directly. No WAV file in the hot path |
| STT runtime | **macOS: `FluidAudio`** (FluidInference, proven fast on Apple Silicon). **iOS: `parakeet-coreml-swift`** (existing, works). Both behind shared `TranscriptionProviding` + `ModelProviding` abstractions — the rest of the app never sees the difference |
| LLM formatting | Reuse `TextFormattingService` / `OpenRouterFormattingClient`. **Free on Mac** in v1; designed so a future paid gate can be added |
| Prompt architecture | One `PromptComposer` building structured prompts: task instruction + **input boundary** (anti-prompt-injection) + **detected-language hint** + **output requirements** + optional fine-tuning. The 4 styles (Formal/Casual/Very Casual/Excited) become tones in this structure. Temperature per style (0.0–0.4) |
| Window model | **One main window with a native sidebar** (`NSSplitViewController`): History · Settings. Menu-bar click opens it. Activation policy accessory↔regular on window open/close |
| Onboarding | **Separate Setup window** (hidden title bar): Intro → Permissions (mic + accessibility) → Model download → Finish |
| Menu bar dropdown | Show History · Settings · STT Formatting Style (nested) · Copy Last Translation · Show Onboarding · Quit |
| Overlay | Non-activating `NSPanel`, bottom-center of the active monitor, **status-only** (Listening / Warming up / Transcribing / Polishing / Copied / error). Bubble in/out animation per DESIGN.md (circle → rounded rect, fade-out) |
| Auto-paste | Verified synthetic paste (clipboard → Cmd+V) as primary with paste verification; AX insert with verification for non-terminal/Firefox apps. **Default OFF**; when AX missing → clipboard-only + overlay hint |
| Auto-copy | `SettingsStore.autoCopy` (default on). Text always stays in the clipboard |
| Preserve clipboard | Toggle in Settings, **default OFF** (consistent with iOS autoCopy) |
| Auto-enter | **Never.** No simulated Return/send after insertion |
| Auto-login | `SMAppService.mainApp` on first launch; toggle in Settings |
| History | Local-only. No iCloud sync in v1. No `inserted` flag, no "Copy with Timestamp" |
| Permissions | Microphone (`AVCaptureDevice`), Accessibility (`AXIsProcessTrusted`), deep-links |
| STT master toggle | Not added (app is STT-centric) |
| Record section in main window | **Hidden on macOS** — dictation is hotkey-only |
| Service architecture | Shared views/logic depend on **protocols** (`TranscriptionProviding`, `RecorderProviding`, `ClipboardProviding`, `ModelProviding`) in `OpenWhisperShared`; iOS and macOS provide implementations |
| Audio ducking | **v1**: CoreAudio `VirtualMainVolume`, default level 0.2, restored at session end. No AppleScript |
| Sound feedback | **v1**: bundled/system/custom sounds for start/success/error; start cue after first audio buffer; skipped for Bluetooth input |
| Short/quiet clips | **v1**: `ShortSpeechClassifier` thresholds + "Transcribe short/quiet clips aggressively" (default on) |
| Model auto-unload | **v1**: Never/Immediate/2m/5m/10m/30m/1h |
| Require second Esc | **v1** (default off → one Esc cancels) |
| Skip AI for short dictations | **v1**: skip LLM polish below N words (0–10, default 0 = off) |

**Rejected (user decisions):** `inserted`/`copied` flag, "Copy with Timestamp", master
STT toggle, live preview in overlay, **auto-enter after paste**, **snippets** (not on
iPhone, not on macOS — no snippet feature).
**Deferred to v2:** workflows (app/website/hotkey templates), prompt actions palette,
LLM fallback chain, Memory service, media pause (private API, non-App-Store),
API server + CLI, history retention / save-audio-with-history, dictionary training
wizard, target-app correction learning, spoken feedback (TTS), live streaming preview,
Watch support (Parakeet is ~480 MB — watch can only be a remote control; separate project).

---

## Phase 0 — STT verification (DONE)

Owner: **Agent builder-macos-services** — **completed on 2026-08-02.**

- macOS runtime is **`FluidAudio`** (FluidInference) — verified working on this Mac
  (arm64, Xcode 26.6): package builds in ~17 s; model already cached at
  `~/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3` (461 MB,
  compiled); cache load 0.32 s; 5 s Polish clip transcribed in 0.18 s at 0.92
  confidence. API confirmed: `AsrModels.loadFromCache(version: .v3)` +
  `AsrManager(config: .default)` + `TdtDecoderState.make()` +
  `transcribe(url:decoderState:language:)`.
- iOS runtime stays `parakeet-coreml-swift`. Both sit behind `TranscriptionProviding`
  + `ModelProviding`; nothing else in the app depends on the backend.

## Phase 1 — Cross-platform shared package (text + audio processing)

Owner: **Agent builder-shared-package**

- `OpenWhisperShared/Package.swift`: add `.macOS(.v26)` platform; add local
  `ParakeetTDT` dependency where required.
- `MicRecordButton.swift` / `RecordingSurface.swift`: `#available(iOS 26.0, macOS 26.0, *)`.
- Guard iOS-only files in shared with `#if canImport(...)` (`DictationActivityAttributes`
  = ActivityKit, any `UIKit` import).
- Promote to shared (public, git move, no duplication): `TranscriptionEngine`,
  `ModelDownloadManager`, `SettingsStore`, `ToastCenter`, `SettingsRouter`,
  `CorrectionsStore`, `TextFormattingService`, `OpenRouterFormattingClient`,
  `Prompts/*`, `SilencePadding`.
- **Abstraction protocols:** `TranscriptionProviding`, `RecorderProviding`,
  `ClipboardProviding`, `ModelProviding`.
- **New shared text-processing engine (used by iOS and macOS alike):**
  - `PromptComposer` — structured prompts: task + input boundary + language hint +
    output requirements + fine-tuning; the 4 styles map to tones; per-style temperature.
  - `DictationInputBoundary` — wraps dictated text so the LLM treats it as source
    text (no prompt injection), and sanitizes the response (strips scaffold, collapses
    blank lines/blocks).
  - `PostProcessingPipeline` — priority-ordered: (100) number normalization →
    (200) speech punctuation → (300) LLM polish → (600) corrections. No snippet step.
    Non-LLM step failures are logged and swallowed; the LLM step is the only one that
    rethrows.
  - `SpeechPunctuationService` + `PunctuationStrategyResolver` — per-engine/language
    strategy (`nativeOnly`/`automatic`/`fallbackOnly`; Parakeet emits punctuation
    natively, so default = `automatic`), CJK-aware spacing, whole-phrase rules loaded
    from per-language JSON (en/de/it/ja first, pl added; others fall back to spacing).
  - `NumberWordNormalizer` — **all 25 OpenWhisper languages** (infrastructure first:
    en/de/fr/es/nl/zh/ja + pl, then the remaining languages).
  - `SpeechGainNormalizer` — AGC: target RMS 0.1, gain clamp 1…20, hard clamp ±1.
  - `SilencePadder` — <0.75 s → pad to 0.75 s; else +0.3 s tail silence.
  - `ShortSpeechClassifier` — 0.04 s floor; peak 0.003 / 0.006; aggressive flag.
  - `CorrectionsStore` — boundary-aware matching (word-boundary vs substring),
    learned corrections, atomic training commit (kept in shared).
- Verify OpenWhisperShared compiles for macOS **and** iOS.

## Phase 1.5 — Refactor iOS onto the shared foundation

Owner: **Agent builder-shared-package** (paired with iOS app changes)

- Replace iOS `Prompts/*`, `SpeechPunctuation`, `NumberNormalizer` and the manual
  chain in `HistoryView.transcribe()` with the shared `PostProcessingPipeline` +
  `PromptComposer` + `DictationInputBoundary`.
- Add iOS Settings: "Whisper Mode" (AGC) toggle alongside the existing mic-gain
  slider (unifies the double-gain path); short/quiet aggressive toggle.
- **Quality gate:** iOS builds, existing behavior preserved, transcription text not
  worse — verified by a manual pass over representative recordings.

## Phase 2 — macOS services (folder `openWhisperMac/`)

Owner: **Agent builder-macos-services**

- **`MacRecorder`** — in-memory `[Float]` (AVAudioEngine + AVAudioConverter → 16 kHz
  mono), locked buffer. TypeWhisper-grade capture processing: mono-downmix tap,
  `SpeechGainNormalizer`, voice processing for the 3-channel built-in mic, StopPolicy
  grace (50 ms / +60 ms), engine crash **recovery** (`AVAudioEngineConfigurationChange`
  observer, debounce 0.15 s, quiescence 1 s, burst limit 4-in-5 s, backoff
  0.15/0.30/0.50, buffer preserved) + streaming recovery WAV store (16 kHz/16-bit,
  "Recover Last Recording" in menu). Conforms to `RecorderProviding`.
- **`MacTranscriptionService`** — model lifecycle state machine (idle/loading/ready/
  failed), `preloadModel()`/`warmUp()`, `waitForModelReady(120 s)`, `transcribe(samples:)`
  delegating to the shared `TranscriptionEngine` (macOS runtime behind
  `TranscriptionProviding`). Auto-unload per setting. No background tasks — model
  stays resident. Conforms to `TranscriptionProviding`.
- **`TextInsertionService`** — verified synthetic paste: fill clipboard → simulate
  Cmd+V → poll focused AX state (up to 10×/50 ms) to verify the text landed; unverified
  → leave text on clipboard as fallback. Clipboard snapshot/restore with per-app
  delays (terminal 900 ms, rich-text 1500 ms, default 350 ms). Transient pasteboard
  markers (`org.nspasteboard.TransientType`, `org.nspasteboard.AutoGeneratedType`,
  `com.openwhisper.SpeechTranscription`). Bundle-ID handling: terminals + Firefox →
  synthetic paste; others → AX with verification. Focused-role set includes
  `AXWebArea`. `virtualKeyCode(for:)` via TIS for non-QWERTY layouts. No auto-enter.
- **`AudioDuckingService`** — CoreAudio `VirtualMainVolume`, default 0.2, restored on
  session end; applied after the start cue sound finishes.
- **`FeedbackSoundService`** — bundled/system/custom sounds for start/success/error;
  start cue gated on first audio buffer; skipped for Bluetooth input.
- **`MacClipboardService`** — `NSPasteboard.general`; conforms to `ClipboardProviding`.
- **`PermissionManager`** — mic + accessibility statuses, deep-links, AX prompt +
  System Settings open, refresh.
- **`HotkeyManager`** — `NSEvent` global + local monitors; right ⌘+⌥ hold/release;
  ESC (optional second-Esc confirm).
- **`DictationOrchestrator`** — status machine (idle/listening/processing/done/error +
  "polishing"): recorder → `SpeechGainNormalizer` → `SilencePadder` →
  `ShortSpeechClassifier` → STT → `PostProcessingPipeline` → clipboard/insert →
  history. Captures frontmost PID before the overlay shows. Drives overlay state.

## Phase 3 — App shell + overlay (folder `openWhisperMac/`)

Owner: **Agent builder-macos-app-shell**

- **`OpenWhisperMacApp.swift`** (`@main`):
  - `.menuBarExtra` — wave icon (normal/dark/tinted, pulsing/red while recording).
    Menu: Show History · Settings · STT Formatting Style (nested) · Copy Last
    Translation · Show Onboarding · Quit.
  - **One `Window("OpenWhisper")`** — `MacRootView` = `NSSplitViewController` sidebar:
    History · Settings sections; detail panel swaps views. Activation policy
    accessory↔regular on open/close so the window shows in Cmd+Tab.
  - **Separate `Window("Setup")`** — onboarding (hidden title bar, dark):
    Intro → Permissions (mic + accessibility, deep-link buttons + 2 s status refresh)
    → Model download → Finish.
  - `.commands` for Settings.
- **`StatusOverlayPanel`** — `NSPanel` `[.borderless, .nonactivatingPanel]`, `.floating`,
  joins all spaces, clear background, `NSHostingView`. Bottom-center of the active
  monitor. Status-only pill (Listening / Warming up / Transcribing / Polishing /
  Copied / error), gray/white per DESIGN.md; bubble in/out animation per DESIGN.md.
- **Entitlements** (`openWhisperMac.entitlements`): app-sandbox, application-groups
  (`group.pl.piszeprogramy.openWhisper`), network.client, accessibility (automation).
- **Info.plist**: `NSMicrophoneUsageDescription`, `NSAccessibilityUsageDescription`,
  LSUIElement = true.
- **Auto-login**: `SMAppService.mainApp.register()` on first launch; Settings toggle.

## Phase 4 — macOS app-aware formatting + RTF pasteboard

Owner: **Agent builder-macos-services** (view additions)

- `OutputFormatResolver` — auto-detect output format by bundle-ID (Pages/Word/TextEdit
  → rich text; Obsidian/Notion/marktext/Typora/Bear → markdown; Mail/Outlook → HTML;
  Xcode/VSCode/iTerm/Terminal → code; browsers by URL host: docs.google.com → rich
  text, mail.google.com → HTML, else plain text).
- `AppFormatterService` — markdown/HTML conversion (bullets → lists, escaping).
- `PasteboardContentFormatter` — markdown → **RTF** pasteboard payload so pasted text
  keeps bold/italic/code/lists. Mac-only (iOS pastes plain text).
- Settings tab: "Formatting" sections (style tones, temperature display, output
  format auto-detection, AGC, aggressive short clips).

## Phase 5 — Target wiring + build verification

Owner: **Agent builder-macos-target**

- Add `openWhisperMac` target to `openWhisper.xcodeproj/project.pbxproj`
  (PBXNativeTarget, product `openWhisperMac.app`, `fileSystemSynchronizedGroups` =
  `openWhisperMac`, frameworks: OpenWhisperShared + STT runtime).
- macOS build configs (SDKROOT macosx, deployment 26.0).
- Build: `xcodebuild -scheme openWhisperMac -destination 'platform=macOS'`.
- **Also build the iOS scheme** — shared changes must not break iOS, keyboard, or widget.
- Manual smoke test: hotkey hold → overlay "Listening" → release → transcribing →
  polish → clipboard + auto-paste into active field (including a terminal and a
  browser); history row saved; menu-bar style change respected; onboarding setup flow;
  ducking; sounds; recovery. iOS parity pass on iPhone.

---

## Shared vs per-platform

**In `OpenWhisperShared` (identical on iOS and macOS):** models/types
(`TranscriptionItem`, `TranscriptionStyle` + tones, `Language`, `SettingsStore`,
errors), STT engine + model manager (behind protocols), `PromptComposer`,
`DictationInputBoundary`, `TextFormattingService`, `OpenRouterFormattingClient`,
`Prompts/*`, `PostProcessingPipeline`, `SpeechPunctuationService` + resolver,
`NumberWordNormalizer`, `CorrectionsStore`, `SpeechGainNormalizer`, `SilencePadder`,
`ShortSpeechClassifier`, `AudioCapturePipeline`, `ToastCenter`, `SettingsRouter`,
`AppGroup`, `AppTheme`.

**Not in shared (platform-specific):** full screens (iOS NavigationStack vs Mac
sidebar + Setup window), iOS `AudioRecorder`/`ResidentDictation`/Live Activity/
keyboard/widget/`ClipboardService`/haptics; macOS `MacRecorder` (+ recovery +
recovery store), `MacTranscriptionService`, `TextInsertionService`,
`MacClipboardService`, `AudioDuckingService`, `FeedbackSoundService`, `HotkeyManager`,
`StatusOverlayPanel`, `DictationOrchestrator`, `PermissionManager`, `MacRootView`,
`SetupWindow`, app-aware formatting, RTF pasteboard.

## Reused from iOS (no new work)

`TranscriptionEngine`, `ModelDownloadManager`, `SettingsStore`, `TextFormattingService`,
`OpenRouterFormattingClient`, `Prompts/*`, `TranscriptionStyle`, `TranscriptionItem`
(SwiftData), history store, `CorrectionsStore`, onboarding/history/settings views
(after Phase 1.5), app icons.

## v2 backlog

Workflows (templates + app/website/hotkey triggers + output formats + temperature),
prompt actions palette (translate/email/list/action-items/reply/table/draft-email/
JSON/meeting-notes presets) + prompt wizard, LLM fallback chain + Apple Intelligence
provider, Memory service (LLM fact extraction, prompt injection), media pause
(private MediaRemote, non-App-Store), API server + CLI, history retention /
save-audio-with-history, dictionary training wizard, target-app correction learning
(edit-diff), spoken feedback (TTS), live streaming preview, Watch (remote control
only — separate project).
