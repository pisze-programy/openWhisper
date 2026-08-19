# OpenWhisper — Pre-release Plan (macOS App Store)

Status: **draft — decisions per stage are made as we go (add / keep / skip).**

## Decisions locked so far

- **First submission:** macOS only. iOS follows in a later cycle.
- **AI formatting & translation backend:** **BYOK stays** — user keeps their own OpenRouter key, stored **in Keychain** (not UserDefaults). **No LLM on the Worker.**
- **Analytics:** lightweight Cloudflare Worker endpoint collecting **counters only** (feature, language, outcome, latency), keyed by an **install UUID**. No transcript text ever leaves via analytics.
- **Prompts:** built client-side (`PromptComposer`), as today.
- **Keyboard extension + widget:** stay OUT of the submitted archive (not embedded). iOS clean-up deferred to Stage 5.

## Process

- One stage at a time. After each stage: `git commit`, then STOP for review.
- Each checkbox may be added, kept, or skipped by explicit decision.

---

## Stage 0 — Plan

- [x] Review the codebase for App Store readiness (done: entitlements, build configs, network flows, data storage, permissions).
- [x] Write this plan file.

## Stage 1 — Keychain + lightweight usage analytics (revised 2026-08-19)

> Decision: **no LLM proxy on the Worker.** Formatting/translation keep calling OpenRouter directly with the user's own key (BYOK), now stored in the Keychain. The Worker only collects anonymized counters.

### Keychain (OpenWhisperShared)
- [x] `KeychainStore` — generic-password read/write/delete wrapper (`Security` framework).
- [x] `OpenRouterApiKeyStore` — API key in Keychain, auto-migrates the legacy UserDefaults/App Group value.
- [x] `InstallID` — stable random UUID in Keychain (survives app updates), used for analytics.
- [x] Wire `TextFormattingService` + `SettingsView`/`SettingsKeyboardSection` to the Keychain store.
- [x] Settings toggle `usageAnalyticsEnabled` (default ON, user-visible disclosure).

### Worker (new `server/` directory)
- [x] Wrangler Worker, `POST /v1/track` — validates payload (size caps, enums), **stores no content**.
- [x] Rate limiting per install ID + per IP (KV).
- [x] Daily aggregation counters in KV (feature × outcome × language) + DAU install-ID set.
- [x] `wrangler.toml`, `README.md` (deploy steps: `wrangler kv namespace create`, `wrangler deploy`).
- [x] Analytics client `UsageAnalytics` — fire-and-forget counters from the app (feature, language, ok/fail, latency, chars). Never content.

### Open decisions for this stage
- [x] ~~DeviceCheck token vs. install-UUID only~~ → **install-UUID only** (decided; no paid-billing exposure since no LLM proxying).
- [x] ~~Prompts client-side vs. server-side~~ → **client-side** (decided).

## Stage 2 — Sandbox + privacy manifest (hard blockers)

- [ ] Enable App Sandbox (`com.apple.security.app-sandbox=true`) in `Release-Store` entitlements + add `application-groups` (team-prefixed).
- [ ] Verify at runtime in sandbox: Accessibility insert/paste (`TextInsertionService`), global hotkey monitor (`HotkeyManager`), `CGEvent` paste, `SMAppService.mainApp` login item.
- [ ] FluidAudio model cache (~460 MB + silero-vad) → sandbox container / App Group; check if FluidAudio exposes a custom cache directory API; else confirm re-download on first launch.
- [ ] `RecoveryAudioStore` → container path + `isExcludedFromBackup` (currently raw audio backs up to iCloud/Time Machine).
- [ ] `PrivacyInfo.xcprivacy` for the macOS app: required-reason APIs (UserDefaults CA92.1, file timestamps, boot time if used), `NSPrivacyTracking=false`.
- [ ] Verify/add privacy manifests for `FluidAudio` and `parakeet-coreml` SPM packages (or App Store warnings).
- [ ] `DeviceSessionID`: remove broken iCloud KV sync (no entitlement) + stop sending `session_id` to OpenRouter; replace with Keychain install UUID.

## Stage 3 — Privacy disclosure & copy

- [ ] Update `NSMicrophoneUsageDescription`: audio stays on device; transcript text may go to the cloud for optional formatting/translation (off by default).
- [ ] Update macOS onboarding/setup copy to match the actual data flow.
- [ ] Fill `NSHumanReadableCopyright`.
- [ ] Draft privacy policy (URL): transcript text → Worker/OpenRouter, per-device usage analytics, no accounts, how to delete data.
- [ ] Draft App Review notes: Accessibility insert-only, global hotkey (no keylogging), menu-bar `LSUIElement` app, runtime model download (~460 MB), sandbox.

## Stage 4 — App Store Connect (human + prep)

- [ ] App record for `piszeprogramy.openWhisper.mac`.
- [ ] Screenshots (macOS 26 sizes) + previews.
- [ ] Description, promo text, keywords (drafts kept in this repo).
- [ ] App Privacy label: User Content (transcripts when cloud formatting/translation enabled), Usage Data (per-device analytics), Diagnostics (none).
- [ ] Export compliance: HTTPS only via URLSession → no-encryption declaration.
- [ ] EULA (Apple standard), support URL, copyright.
- [ ] App ID capabilities: App Group, DeviceCheck; distribution cert + provisioning.
- [ ] Bump build (`CURRENT_PROJECT_VERSION`), TestFlight beta before submission.

## Stage 5 — Cleanup & quality (non-blocking, mostly iOS)

- [ ] iOS: remove unused `UIBackgroundModes=audio` + `NSSupportsLiveActivities` (resident dictation is dead code).
- [ ] Widget: invalid `IPHONEOS_DEPLOYMENT_TARGET=26.5`, empty `AppIcon.appiconset` — decide keep-out-of-archive vs. fix.
- [ ] Keyboard: `RequestsOpenAccess=true` + microphone string mismatch — stays out of archive.
- [ ] Unit/UI tests for core flows (STT → format → insert).
- [ ] Final secret scan (no `sk-` values in repo).

---

## Review findings (source for the checklist)

### Blockers
| # | Finding | Reference |
|---|---|---|
| B1 | macOS app not sandboxed; `app-sandbox=false` used by `Release-Store` too. MAS requires sandbox. | `openWhisperMac/Info.entitlements:5`; `project.pbxproj:485` |
| B2 | No `PrivacyInfo.xcprivacy` anywhere (required since May 2024). | repo-wide |
| B3 | OpenRouter key in plaintext UserDefaults/App Group, not Keychain. | `SettingsView.swift:243`, `SettingsKeyboardSection.swift:27`, `AppGroup.swift:6` |
| B4 | iOS `UIBackgroundModes=audio` + `NSSupportsLiveActivities` declared but unused (dead `ResidentDictation`). iOS-only; fix before iOS submission. | `Info-Additions.plist:16-21` |

### High risk
| # | Finding | Reference |
|---|---|---|
| H1 | Transcript text (format/translate) + full WAV (keyboard STT) + persistent `session_id` sent to OpenRouter; must be disclosed in privacy label & policy. | `OpenRouterFormattingClient.swift`, `OpenRouterSTTClient.swift`, `DeviceSessionID.swift` |
| H2 | `NSEvent.addGlobalMonitorForEvents` + AX reads of focused field look keylogging-adjacent; prepare review notes. | `HotkeyManager.swift:40`, `TextInsertionService.swift:162-164` |
| H3 | `DeviceSessionID` uses `NSUbiquitousKeyValueStore` but no iCloud entitlement → sync silently broken. | `DeviceSessionID.swift:48-55`, `openWhisper.entitlements` |
| H4 | macOS has no App Group entitlement yet reads the App Group suite → mismatch. | `openWhisperMac/Info.entitlements`, `TextFormattingService.swift:106-111` |

### Medium / polish
| # | Finding | Reference |
|---|---|---|
| M1 | `RecoveryAudioStore` not excluded from backup. | `openWhisperMac/Services/RecoveryAudioStore.swift:17-20` |
| M2 | Widget `IPHONEOS_DEPLOYMENT_TARGET=26.5`, empty appiconset. | `project.pbxproj:521`, widget `AppIcon.appiconset` |
| M3 | Extensions not embedded in the iOS app (empty "Embed App Extensions"). | `project.pbxproj:21-30` |
| M4 | `NSHumanReadableCopyright` empty. | `openWhisperMac/Info.plist:27-28` |
| M5 | Mic string "Audio is processed on your device and never leaves it" vs. cloud formatting/translation. | `openWhisperMac/Info.plist:30`, iOS pbxproj:748/788/828 |
| M6 | Keyboard mic string claims cloud audio; active path is on-device. | `OpenWhisperKeyboard/Info.plist:22` |
| M7 | App name "OpenWhisper" — check for existing names/trademarks on the store. | — |
| M8 | No unit/UI tests. | repo-wide |

### Verified OK
- macOS + iOS app icons complete; entitlements minimal; no hardcoded secrets; no analytics SDKs; HTTPS only; ATS not weakened; model weights downloaded from HuggingFace at user request; README discloses public-vs-store media behavior accurately; `SMAppService.mainApp` login item is MAS-compatible.

### Notes / limitations
- FluidAudio (remote SPM 0.15.5) is not vendored — its runtime network behavior and whether it ships a privacy manifest must be checked at build time.
- App Store Connect steps (Stage 4) need the paid developer account.
