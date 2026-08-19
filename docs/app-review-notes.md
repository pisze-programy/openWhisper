# OpenWhisper — App Review Notes (macOS)

_Last updated: August 19, 2026_

These notes are provided in App Store Connect under **App Review Information →
Notes** to preempt questions about the app's more sensitive behaviors.

## In one paragraph
OpenWhisper is a menu-bar speech-to-text app. The user holds a global hotkey
(right ⌘+⌥), speaks, releases, and the transcribed text is inserted into the
frontmost app. Speech-to-text runs fully on-device. Optional AI formatting and
translation send only the transcript text to OpenRouter using the user's own
API key. Anonymous, opt-in usage analytics report counters only.

## Accessibility API (inserting text)
The app uses the macOS Accessibility API **only to insert transcribed text** into
the frontmost app's focused text field, and to verify that the insert landed.
It reads the focused input's value/selection (and its text-bearing ancestors
while locating the editable field) for that verification. It does not read other
content, enumerate windows, capture the screen, or log keystrokes.
The user grants Accessibility explicitly in onboarding; without it the app does
not attempt insertion and the transcript stays on the clipboard (Auto-Copy, on
by default).

## Global hotkey
The app installs a global event monitor to detect the dictation hotkey (right
⌘+⌥) and two "hold-and-tap" chord shortcuts (right ⌥+⇧ to cycle formatting style,
right ⌘+⇧ to cycle translation target). It reacts only to those modifier chords
and Escape. It does not record or transmit keystrokes; no content is logged.

## Menu-bar app (no Dock icon)
OpenWhisper is an `LSUIElement` agent app: it lives in the menu bar so dictation
hotkeys work from anywhere without stealing focus. The main window opens from
the menu bar icon.

## On-device transcription
Speech-to-text uses the Parakeet TDT model (via the FluidAudio engine) running
locally on Apple Silicon. The model (~480 MB) is downloaded from Hugging Face on
first use, then runs offline. No microphone audio ever leaves the device.

## AI formatting and translation (opt-in)
Formatting/translation are off by default (style = "None"). When the user
selects a style or a translation target, the **transcript text** is sent to
OpenRouter (openrouter.ai) using an API key the user provides in Settings.
Audio is never sent. This is disclosed in the microphone permission string and
during onboarding.

## Analytics (opt-in)
The app reports anonymous usage counters (feature used, language, success,
latency) to a Cloudflare Worker, keyed by a random per-install ID. No audio or
transcript text. Users can disable it in Settings.

## Sandbox
The app is sandboxed (App Sandbox, hardened runtime). Entitlements are limited
to: network client, audio input, and the app group used for local shared data.

## Login item
"Launch at login" uses the standard `SMAppService.mainApp` API — no bundled
helper or login-item XPC is installed.
