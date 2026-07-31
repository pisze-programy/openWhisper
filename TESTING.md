# TESTING.md — OpenWhisper: on-device testing guide

> Working document. What to do, what to test, and what to expect when running
> **OpenWhisper** on a physical iPhone for the first time (M0 + M1 scaffold).

---

## 1. Project status

### Done (in this build)
- SwiftUI app, iOS 18.0+, 100% on-device processing (Parakeet TDT 0.6B v3 / Core ML)
- 2-step onboarding (shown on every launch — testing mode), with a video placeholder
- Model download from Hugging Face (~450 MB), resumable after killing the app
- Transcription history: add / copy (tap) / delete (swipe) / clear all
- Auto-copy to clipboard after transcription (toggle)
- Settings: model status + download/re-download, ANE/GPU/CPU, 10-min cap, "Save to history" (privacy)
- Recording: 16 kHz mono, auto-stop at 10 min, audio-session interruption handling (calls/Siri)
- "About" screen with licenses (Apache-2.0 / CC-BY-4.0)

### NOT in this build (intentionally — later phases)
- System keyboard extension (Phase 1.5)
- Real onboarding video (placeholder)
- App icon (empty — does not block testing)
- Notepad + LLM corrections (Phase 2)
- UI localization (English only)

---

## 2. Xcode setup (5 min)

1. Open `openWhisper.xcodeproj`.
2. Select **your iPhone** as the destination (iOS **18.0** or newer).
3. Signing is already configured (`Automatic`, team `3UKH2QRFKZ`).
   - If Xcode asks for a team — pick the same one (or yours).
   - On first build you may need to add your developer account: Xcode → Settings → Accounts.
4. **⌘R** (Run).
   - First build resolves the local package `Packages/parakeet-coreml-swift` (no download) + `swift-argument-parser` (one fetch — internet needed).
5. If transcription feels slow in Debug, switch the scheme to **Release** (Debug is intentionally slower).

---

## 3. First launch — what to expect

| Step | What you'll see |
|---|---|
| App start | Onboarding (step 1): title + tagline + black rounded rect "Demo video coming soon" (placeholder) |
| "Next" | Step 2: ~450 MB download explainer + **"Start Download"** button |
| Download | Progress bar with %; you can leave onboarding anytime (Skip/Finish) — the download continues and is resumable |
| After download | Status **"Model ready"**; Finish → history screen |
| First recording | Microphone permission prompt → "Allow" |
| First transcription | Short wait (model compiles to `.mlmodelc`, a few seconds); subsequent ones are fast |

Disk usage after download: **~1.1–1.3 GB** in Application Support (intentional — see Known limitations).

---

## 4. Test checklist

### 4.1 Onboarding
- [ ] Step 1 → Next → step 2 (step indicator works)
- [ ] **Skip** on both steps leads to the app
- [ ] **Start Download** kicks off the download with progress
- [ ] Kill the app mid-download → tapping **"Start Download"** again **resumes** (does not restart)
- [ ] No network → error message + **"Try Again"**; onboarding shows again on next launch

### 4.2 Model download & status
- [ ] **Settings** shows status: "Ready" (green badge) after download
- [ ] **Re-download** (be ready for another ~450 MB) — only if you want to test it
- [ ] Restart the app after download → model active immediately (cache), fast startup

### 4.3 Transcription (M0 — key)
- [ ] Short recording (PL) → correct text
- [ ] Longer recording (1–2 min) → complete text, no truncation
- [ ] Very short clip (<3 s) → **may return empty text** (known upstream bug — not a regression)
- [ ] Note: transcription time vs recording length (RTF), Polish quality, any weirdness
- [ ] Switching **Compute Units** in Settings (ANE→GPU→CPU) → takes effect from the next transcription (model reloads — brief wait)

### 4.4 History
- [ ] Transcription appears in the list (date + duration)
- [ ] **Tap** an item → text copied to clipboard (+ haptic) → paste in any app
- [ ] **Swipe** → item deleted
- [ ] **Clear All** → confirmation → empty list
- [ ] **Auto-copy ON**: text is in the clipboard right after transcription
- [ ] **"Save to history" OFF**: transcription is NOT persisted (privacy), but auto-copy still works

### 4.5 Recording states
- [ ] Mic button disabled when the model isn't ready + banner "download the model in Settings"
- [ ] While transcribing: "Transcribing…" spinner, mic blocked (single-flight — no two transcriptions at once)
- [ ] **10-min auto-stop**: recording stops and transcribes itself (optional test — 10 min)
- [ ] **Interruption** (incoming call / Siri while recording): recording stops and transcribes what was captured

### 4.6 Misc
- [ ] App works after a phone restart (model in cache)
- [ ] Airplane mode: transcription works offline (after the model is downloaded)

---

## 5. Known limitations (not bugs)

1. **Debug builds are slower** — vendored package without the forced `-O` (Release = full speed).
2. **Disk ~1.1–1.3 GB** — we do not delete the `.mlpackage` sources (`deleteSourceAfterCompile: false` is required, otherwise the model won't load after an app restart).
3. **Short clips <3 s** → empty transcription / 2–5 s tail may be hallucinated (upstream issue #1; a local patch is planned).
4. **No timeout** on a hung Core ML transcription (UI could stay on "Transcribing…" — extreme edge case).
5. **Background download** — resumable, but not a system background download (if you leave the app for a long time, come back and finish it manually).

---

## 6. What to bring back from testing (feedback)

- iPhone model + iOS version
- Results from section 4.3: sample PL text, recording time vs transcription time
- Any crash or memory warning during the first transcription
- Screenshots of the onboarding (glass look verification)
- Any error messages (shown in alerts — just describe them)

---

## 7. Useful references

- Model: `mweinbach1/parakeet-tdt-0.6b-v3-coreml` (CC-BY-4.0, NVIDIA) — downloaded on first launch
- Package: `Packages/parakeet-coreml-swift` (vendored fork, Apache-2.0 — `unsafeFlags` removed)
- Development plan: `PLAN.md` · Project overview: `README.md`
