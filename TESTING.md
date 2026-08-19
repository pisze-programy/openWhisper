# Test plan — M-K1 (refactor: shared package / keyboard without ParakeetTDT)

> **Test goal:** M-K1 is a pure refactor — code moved into `OpenWhisperShared` (audio, waveform, errors),
> and `TranscriptionEngine` moved into the app target. **Behavior must be IDENTICAL to the pre-refactor build.**
> Pass criterion for every step: same result as on the build before the refactor.
> Mark each step ✅ / ❌ and add notes (especially for ❌: what happened, logs, error message).

## Phase 0 — Setup

| # | Step (what you do) | Expected result | Result |
|---|---|---|---|
| 0.1 | Build and install on the phone from Xcode (Device) | Build with no errors, app installs and launches | |
| 0.2 | Check version (Settings → About) | `1.0 (1)` — unchanged from the previous build | |

## Phase 1 — App launch

| # | Step | Expected result | Result |
|---|---|---|---|
| 1.1 | Launch the app | Starts without a crash, no loading loop | |
| 1.2 | Initial screen | History (if onboarding completed) OR onboarding (3 steps, if not) | |
| 1.3 | Model status (Settings → Model) | Status `Ready` / "Saved on this device" — model already downloaded (no re-download) | |
| 1.4 | If status ≠ Ready | Download the model — progress bar, then `Ready` | |

## Phase 2 — Recording and transcription (critical: `AudioCapturePipeline` now in shared)

| # | Step | Expected result | Result |
|---|---|---|---|
| 2.1 | Press and hold the microphone button | Red "Listening…" state, **waveform animates** (bars react to voice), timer counts | |
| 2.2 | Release after ~3–5 s of speech | "Transcribing…", then the text appears in history | |
| 2.3 | Dictate in Polish | Polish characters, punctuation and capitalization (as before) | |
| 2.4 | Dictate in English | English recognized (auto-detection) | |
| 2.5 | Record ~1 s of silence and release | Toast "No speech detected", nothing added to history | |
| 2.6 | Short 2–4 s clip of speech | Text transcribed (no cut-off start/end) | |
| 2.7 | Record 10 s, interrupt mid-way with a call/Siri | Recording stops and transcribes what was captured | |

## Phase 3 — History and clipboard

| # | Step | Expected result | Result |
|---|---|---|---|
| 3.1 | After transcription | New entry at the top of the list | |
| 3.2 | Tap an entry | "Copied!" + text in the clipboard (auto-copy defaults ON) | |
| 3.3 | Paste into Notes/Messages | Pasted text is correct (diacritics OK) | |
| 3.4 | Swipe left on an entry | Delete appears | |
| 3.5 | Delete an entry | Disappears from the list, no crash | |
| 3.6 | Swipe through several entries | Each entry deletes individually; there is **no** "Clear all" action in the UI | |

## Phase 4 — Settings

| # | Step | Expected result | Result |
|---|---|---|---|
| 4.1 | Turn off "Auto-copy to clipboard" → record | Entry in history, but NOT in clipboard | |
| 4.2 | Turn off "Save transcriptions to history" → record | No new entry in history | |
| 4.3 | Set "Compute units" to GPU → record | Transcription works on GPU | |
| 4.4 | Set "Compute units" to CPU → record | Transcription works on CPU (slower — OK) | |
| 4.5 | Set language to "Polish" → record in Polish | Works as before | |
| 4.6 | Add a correction (e.g. "hallo" → "hello") → record the word | Correction applied in the text | |
| 4.7 | "Show onboarding again" → save | Onboarding shows again | |

## Phase 5 — Keyboard extension (regression)

| # | Step | Expected result | Result |
|---|---|---|---|
| 5.1 | Settings → General → Keyboard → Keyboards → Add New Keyboard | "OpenWhisper" appears in the keyboard list | |
| 5.2 | Add the OpenWhisper keyboard | Adds without error | |
| 5.3 | Open Notes/Messages, long-press 🌐 → select OpenWhisper | Switches to the OpenWhisper keyboard | |
| 5.4 | Keyboard is shown | Header "OpenWhisper" + "Tap a transcription to insert it" | |
| 5.5 | History list | Recent transcriptions visible (from the app) | |
| 5.6 | Tap a transcription | Text is inserted into the active text field | |
| 5.7 | No history | Message "No transcriptions yet — dictate in OpenWhisper first" | |
| 5.8 | Switch back to the system keyboard | Works (system keyboard returns) | |

## Phase 6 — Stability and memory

| # | Step | Expected result | Result |
|---|---|---|---|
| 6.1 | Record and transcribe 10× in a row | No crashes, no growing lag, ~same pace as before the refactor | |
| 6.2 | Use the keyboard after a longer pause (return to it) | Loads without hanging for seconds | |
| 6.3 | Close the app while recording | No crash, no runaway background recording | |
| 6.4 | (Optional) Console/Xcode — logs | No new `error:`/crashes related to audio/transcription — see Appendix A on where to check | |

---

## Summary

| Area | Result (✅/❌) | Notes |
|---|---|---|
| App launch | | |
| Recording + transcription (PL/EN) | | |
| Waveform (animation) | | |
| History + clipboard | | |
| Settings (toggles, compute units, corrections) | | |
| Keyboard extension (list + insert) | | |
| Stability (10× series, returning to keyboard) | | |

> If anything is ❌, describe exactly: what you did, what you saw, the message/log, and whether it happens every time.

---

## Appendix A — Troubleshooting: where to find logs and crashes

> **Key fact:** the keyboard extension runs in **its own process**, separate from the host app (Messages/Notes) and from the OpenWhisper app. The Xcode debug console only shows the process you are running — so extension problems usually **do not appear** in the Xcode console. Use the sources below.

### A.1 Crash logs on the Mac (easiest, device connected to Xcode)

1. **Xcode → Window → Devices and Simulators**.
2. Select your iPhone in the left sidebar.
3. Click **View Device Logs** (right side).
4. Find the newest entries. Look under these process names (they may not be obvious):
   - `OpenWhisperKeyboard` — the extension itself
   - `Messages` / `MobileSMS` — the host app (if it died with the keyboard)
   - `SpringBoard` / `FrontBoard` — the system returning you to the home screen
   - `JetsamEvent` — memory kills
   - `openWhisper` — the main app
5. Right-click an entry → **Export** to save the `.ips` file, then share it with the team.

**What to read in the crash entry:**
| Field / value | Meaning |
|---|---|
| `Termination Reason: … 0x8badf00d` | Watchdog kill — the process didn't finish launching/responding in time (e.g. main thread blocked) |
| `Termination Reason: … 0xdead10cc` | Deadlock / file-protection lock |
| `Namespace JETSAM` | Killed for memory pressure |
| `Exception Type: SIGTRAP` / `EXC_BREAKPOINT` | Swift runtime trap (e.g. MainActor isolation violation) |
| `Exception Type: EXC_CRASH (SIGKILL)` | Killed by the system (watchdog/jetsam) |
| `Exception Type: NSException` | Objective-C exception (e.g. Core Data store failure) |
| `CoreData: error: Store failed to load` + `Code=134100/134110/134504` | SwiftData/Core Data store problem (schema mismatch, concurrent migrators, disk) |
| `Cannot use staged migration with an unknown model version` | Store incompatible with the current model schema |
| `Swift runtime failure: … main actor-isolated` / `_mainActorTrapped` | MainActor isolation problem in the extension |

### A.2 Crash reports on the phone

1. **Settings → Privacy & Security → Analytics & Improvements → Analytics Data**.
2. Look for files ending in `.ips` (sorted by date):
   - `OpenWhisperKeyboard-*.ips`
   - `Messages-*.ips`
   - `JetsamEvent-*.ips`
   - `SpringBoard-*.ips`
   - `openWhisper-*.ips`
3. Tap one to read it (or air-drop / mail it).

> Note: watchdog (`0x8badf00d`) and jetsam kills often **do not show up** in Analytics Data. If nothing is listed but the app still returns to the home screen, treat it as a launch-time hang → check A.1 and A.3.

### A.3 Unified log (os.Logger) — where the keyboard now writes

The keyboard logs via `os.Logger` (`subsystem: pl.piszeprogramy.openwhisper.keyboard`, `category: keyboard`).

> **Important:** the macOS `log` CLI reads only the **Mac's own** logs — it has **no `--device` option**. For a physical iPhone use **Console.app** (GUI) or **sysdiagnose** (CLI) below. The `log` CLI does work for the **simulator**.
> Device names can contain shell-special characters (commas, slashes, `!`, parentheses, spaces) — when a CLI needs a device identifier, use the **UDID** (safe, e.g. `00008120-000C71C03C03C01E`), found in Xcode → Window → Devices and Simulators.

**Option 1 — Console.app (GUI, recommended for device logs):**
1. Connect the iPhone and unlock it (trust this computer if prompted).
2. Open **Console.app** (in `/Applications/Utilities`).
3. Select the **iPhone** in the left sidebar.
4. In the menu: **Action → Include Info Messages** and **Action → Include Debug Messages** (otherwise `os.Logger` info/debug lines are hidden).
5. Search for `OpenWhisperKeyboard` or the subsystem `pl.piszeprogramy.openwhisper.keyboard`. Stream live while you reproduce.
6. To keep a copy: select the lines → **File → Export** (or **Save a Copy As…**).

**Option 2 — Crash reports (the decisive source for a launch-time crash):**
- **Xcode → Window → Devices and Simulators → select iPhone → View Device Logs** → look for `OpenWhisperKeyboard` / `Messages` / `SpringBoard` / `JetsamEvent` → right-click → **Export** (`.ips`).
- Or on the phone: **Settings → Privacy & Security → Analytics & Improvements → Analytics Data** → open the matching `*.ips` and share it (AirDrop/Mail).

**Option 3 — sysdiagnose (CLI, everything in one archive):**
```bash
# Full diagnostics from the device (logs + crash reports) as a ZIP; takes a few minutes:
xcrun devicectl diagnose -d 00008120-000C71C03C03C01E --archive-destination /tmp/iphone-diag
```
Then search the extracted archive for `OpenWhisperKeyboard`, `0x8badf00d`, `JetsamEvent`, `CoreData`, `_mainActorTrapped`.

**Option 4 — Simulator (the `log` CLI works here):**
```bash
xcrun simctl spawn booted log show --last 30m --predicate 'process == "OpenWhisperKeyboard"'
```

**What to look for:** `Loading history from …`, `SwiftData container unavailable`, `History fetch failed`, `CoreData: error: Store failed to load`, codes `134100/134110/134504`, `Cannot use staged migration`, `0x8badf00d`, `JetsamEvent`, `_mainActorTrapped`, `Swift runtime failure`.

> **If the device logs are empty** while the crash still happens, the keyboard is dying **before** our `os.Logger` lines run (i.e. during launch/`viewDidLoad`). That is a **launch-time crash** — the definitive source is the crash report in Option 2 / A.1 (`.ips`), not the unified log.

### A.6 Keyboard-specific: after rebuilding, force iOS to pick up the new extension

iOS caches the old keyboard binary. After deploying a new build that changes the extension, do this before re-testing:
1. **Settings → General → Keyboard → Keyboards → Edit → remove OpenWhisper**.
2. Re-add it (Settings → General → Keyboard → Keyboards → Add New Keyboard → OpenWhisper).
3. If it still behaves like the old build, **delete the app from the phone and reinstall** (this also clears the group-container store — the model must be re-downloaded).
4. Only then reproduce and capture logs.

### A.4 Debugging the extension directly from Xcode (console + breakpoints)

1. In Xcode, select the **OpenWhisperKeyboard** scheme (not `openWhisper`).
2. Choose a host app to run it in: **Scheme → Edit Scheme → Run → Info → Executable → Ask on Launch** (or pick Messages/Notes).
3. Run. Xcode launches the keyboard inside the chosen app and attaches the debugger — the Xcode console and breakpoints now work for the extension process.

### A.5 What to include in a bug report

When something fails, attach (in order of usefulness):
1. The exported `.ips` crash log, or a screenshot of the **Termination Reason** / **Exception Type**.
2. The exact repro steps (which app, which field, keyboard selected how).
3. Whether the OpenWhisper app was **running in the background**, **swiped away**, or **not launched** during the repro (relevant to shared-store contention).
4. Any unified-log lines matching the predicates above.
5. A screen recording is a bonus.
