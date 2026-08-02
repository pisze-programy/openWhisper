# OpenWhisper macOS — Implementation Plan (v1)

Goal: a macOS menu-bar dictation app that mirrors the iOS OpenWhisper experience —
press-and-hold a global hotkey to record, transcribe on-device with Parakeet TDT v3,
optionally rewrite with an LLM, auto-copy to clipboard, and auto-paste into the
active input. Reuses the existing iOS codebase (ParakeetTDT, OpenWhisperShared,
views, prompts, LLM formatting).

Target: macOS 26 Tahoe. Accessory app (LSUIElement, no Dock icon), menu-bar icon,
full main window with Onboarding → History → Settings.

---

## Locked decisions

| Area | Decision |
|---|---|
| Hotkey | `NSEvent` global monitor (pattern from `sergey` repo). Hold right **⌘+⌥** = record start, release = stop, **ESC** = cancel. No KeyboardShortcuts dependency |
| Recording | In-memory `[Float]` buffer (pattern from `sergey`), no WAV file; feed `TranscriptionEngine.transcribe(samples:)` directly |
| Compute/STT | Same Parakeet TDT v3 model + `TranscriptionEngine`, `ModelDownloadManager` (reused) |
| LLM formatting | Reuse `TextFormattingService` / `OpenRouterFormattingClient` / `Prompts/*` + style picker (Formal/Casual/Very Casual/Excited) |
| Window | Full window reusing iOS views (Onboarding / History / Settings). Menu-bar click opens it. "Show Onboarding again" in Settings |
| Menu bar dropdown | Show History · Settings · STT Formatting Style (nested) · Copy Last Translation · Show Onboarding · Quit |
| Overlay | Non-activating `NSPanel`, on the active monitor, **status-only** (Listening / Warming up / Transcribing / Polishing / Copied / error). Bubble in/out animation per DESIGN.md (circle → rounded rect, fade-out) |
| Auto-paste | Port `TextInsertionService` from `sergey`: clipboard always → AX insert → CGEvent typed chunks. Needs **Accessibility** permission (onboarding + Settings toggle "Auto-paste") |
| Auto-copy | From `SettingsStore.autoCopy` (default on) |
| Auto-login | `SMAppService.mainApp` registered automatically on first launch; toggle/disable in Settings |
| History | Local-only on Mac. No iCloud sync in v1 (**v2**). No `inserted` flag, no "Copy with Timestamp" |
| Permissions | Microphone (`AVCaptureDevice`), Accessibility (`AXIsProcessTrusted`), deep-links to System Settings |
| STT master toggle | Not added (app is STT-centric) |
| Copy-with-timestamp / inserted flag | Not added (explicitly dropped) |

**Rejected from `sergey`** (by user decision): `inserted`/`copied` history flag,
"Copy with Timestamp", master STT toggle, live preview in overlay.

---

## Phase 1 — Cross-platform shared package

Owner: **Agent builder-shared-package**

- `OpenWhisperShared/Package.swift`: add `.macOS(.v26)` platform; add local
  `ParakeetTDT` package dependency (needed by `SettingsStore`).
- `MicRecordButton.swift` + `RecordingSurface.swift`: change
  `#available(iOS 26.0, *)` → `#available(iOS 26.0, macOS 26.0, *)` (Liquid Glass on Tahoe).
- Promote platform-neutral services to `OpenWhisperShared` as `public`
  (git move — no duplication), keeping `@MainActor @Observable`:
  - `TranscriptionEngine`, `ModelDownloadManager`, `SettingsStore`,
    `ToastCenter`, `SettingsRouter`, `CorrectionsStore`, `TextFormattingService`,
    `OpenRouterFormattingClient`, `Prompts/*`, `SilencePadding`
- Verify OpenWhisperShared compiles for macOS (`xcodebuild` on shared scheme).

## Phase 2 — macOS services (folder `openWhisperMac/`)

Owner: **Agent builder-macos-services**

Ports (pattern: `sergey` repo where noted), all `@MainActor @Observable`:

- **`MacRecorder`** — in-memory recording. Port `AudioRecordingService` from
  `sergey`: `AVAudioEngine` + `AVAudioConverter` → 16 kHz mono `[Float]`, buffer
  queue with lock. Add: `inputGain` + silence auto-stop from `SettingsStore`
  (mirror `AudioCapturePipeline` logic on the samples). Mic permission via
  `AVCaptureDevice.requestAccess(for: .audio)`. API: `start()`, `stop() -> [Float]`,
  `cancel()`, `liveSamples`, `isRecording`.
- **`MacTranscriptionService`** — model lifecycle state machine
  (`ModelState`: idle/loading/ready/failed), `preloadModel()`/`warmUp()`,
  `waitForModelReady(timeout: 120s)`, `transcribe(samples:) -> String`
  delegating to reused `TranscriptionEngine`. No background tasks (model stays resident).
- **`TextInsertionService`** — port from `sergey`: always fill clipboard first,
  then AX insert (focused element role AXTextField/AXTextArea/AXComboBox/AXSearchField,
  set `kAXSelectedTextAttribute`), then CGEvent typed chunks (20 chars + pause).
  Returns whether insertion succeeded.
- **`MacClipboardService`** — `NSPasteboard.general` set string.
- **`PermissionManager`** — microphone + accessibility statuses, `openSettings`
  deep-links (`x-apple.systempreferences:...`), refresh.
- **`HotkeyManager`** — `NSEvent.addGlobalMonitorForEvents` + local monitor;
  flagsChanged tracking of right ⌘+⌥ (hold → start, release → stop), ESC (keyCode 53) → cancel.
- **`DictationOrchestrator`** — status machine
  (idle/listening/processing/done/error + "polishing"), ties recorder → STT →
  LLM formatting → clipboard/insert → history. Captures `frontmostApplication`
  PID **before** overlay shows (for auto-paste). Fires overlay state changes.

## Phase 3 — App shell + overlay (folder `openWhisperMac/`)

Owner: **Agent builder-macos-app-shell**

- **`OpenWhisperMacApp.swift`** (`@main`):
  - `.menuBarExtra` — icon: wave (normal/dark/tinted variants, pulsing/red while
    recording). Menu: Show History · Settings · STT Formatting Style (nested
    picker, writes `SettingsStore.formattingStyle`) · Copy Last Translation ·
    Show Onboarding · Quit.
  - `.window("OpenWhisper")` — reused `RootView` (Onboarding → History/Settings).
  - `Settings { SettingsView() }` scene; `.commands` for Settings.
- **`StatusOverlayPanel`** — port `NSPanel` from `sergey`:
  `[.borderless, .nonactivatingPanel]`, `.floating`, joins all spaces,
  clear background, `NSHostingView`. Position: **bottom-center of the active
  monitor** (mouse-location screen). Status-only SwiftUI pill (Listening /
  Warming up / Transcribing / Polishing / Copied / error), gray/white per DESIGN.md.
  Bubble animation: small central circle → fluid rounded-rect expansion, reverse
  on hide with fade-out.
- **Entitlements** (`openWhisperMac.entitlements`): app-sandbox,
  application-groups (`group.piszeprogramy.openWhisper`), network.client,
  accessibility (automation).
- **Info.plist / generated**: `NSMicrophoneUsageDescription`,
  `NSAccessibilityUsageDescription`, LSUIElement = true.
- **Auto-login**: `SMAppService.mainApp.register()` on first launch; Settings
  toggle to register/unregister.

## Phase 4 — De-iOS shared views

Owner: **Agent builder-shared-views**

- Make these compile for both platforms and move to `OpenWhisperShared` (public),
  per DESIGN.md "never duplicate UI between targets":
  - `RootView`, `HistoryView`, `HistoryRow`, `FirstNoteEmptyState`
  - `SettingsView` + all sections (`SettingsModelSection`, `SettingsKeyboardSection`,
    `SettingsFormattingSection`, `SettingsLanguageSection`, `SettingsDictionarySection`,
    `SettingsAISection` if separate)
  - `OnboardingView` + pages (`OnboardingIntroView`, `OnboardingStylesView`,
    `OnboardingModelView`, `OnboardingPrivacyView`)
- Wrap iOS-only APIs: `UIImpactFeedbackGenerator` and `UIPageControl.appearance()`
  behind `#if canImport(UIKit)` / `#if os(iOS)`.
- Add macOS-specific onboarding section for **Accessibility** permission
  (microphone already covered) with "Open System Settings" buttons + 2s status refresh.

## Phase 5 — Target wiring + build verification

Owner: **Agent builder-macos-target**

- Add `openWhisperMac` target to `openWhisper.xcodeproj/project.pbxproj`
  (PBXNativeTarget, product `openWhisperMac.app`, `fileSystemSynchronizedGroups`
  = `openWhisperMac`, frameworks: OpenWhisperShared + ParakeetTDT).
- Add macOS build configs (SDKROOT macosx, deployment 26.0).
- Build: `xcodebuild -scheme openWhisperMac -destination 'platform=macOS'`.
- Manual smoke test: hotkey hold → overlay "Listening" → release → transcribing →
  polish → clipboard + auto-paste into active field; history row saved; menu-bar
  style change respected.

---

## Reused from iOS (no new work)

- `TranscriptionEngine`, `ModelDownloadManager`, `SettingsStore`
- `TextFormattingService`, `OpenRouterFormattingClient`, `Prompts/*`, `TranscriptionStyle`
- `TranscriptionItem` (SwiftData), history store, `CorrectionsStore`
- Views: onboarding/history/settings (after Phase 4 de-iOS)
- App icons (wave, normal/dark/tinted) — menu-bar + app icon variants

## Reference patterns (external repo `sergey`)

- `AudioRecordingService.swift` — in-memory recording
- `ParakeetTranscriptionService.swift` — ModelState machine + waitForModelReady
- `TextInsertionService.swift` — clipboard→AX→CGEvent chain
- `HotkeyManager.swift` — NSEvent press-and-hold + ESC
- `StatusOverlayPanel.swift` — NSPanel overlay
- `PermissionManager.swift` / `OnboardingView.swift` — permissions UX
