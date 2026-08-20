# OpenWhisper — App Privacy Label Answers (macOS)

_Last updated: August 19, 2026_

Answers for the App Store Connect **App Privacy** questionnaire for
`pl.piszeprogramy.openwhisper.macos`. These must match the bundled
`PrivacyInfo.xcprivacy`.

## Data Not Collected

- **Contact Info** — none.
- **Health & Fitness** — none.
- **Financial Info** — none.
- **Location** — none.
- **Sensitive Info** — none.
- **Purchases** — none (free app, no IAP).
- **Browsing History** — none.
- **Search History** — none.
- **Other User Content** — collected, see below.

## Data Collected

### 1. User Content — "Other User Content"

- **Linked to identity:** No
- **Used for tracking:** No
- **Purposes:** App Functionality

> Explanation for the reviewer: when the user enables AI formatting or
> translation, the transcript text is sent to OpenRouter (openrouter.ai) using
> an **API key the user provides**. This is opt-in (style = "None" by default).
> Audio is never sent. The app itself does not retain this text.

### 2. Usage Data — "Other Usage Data"

- **Linked to identity:** No
- **Used for tracking:** No
- **Purposes:** Analytics

> Counters only: feature (format/translate), language, success/failure,
> latency, character count. No audio, no transcript text.

### 3. Identifiers — "Device ID"

- **Linked to identity:** No
- **Used for tracking:** No
- **Purposes:** Analytics

> A random, per-install UUID stored in the Keychain, used to aggregate the
> usage counters above. Not an Apple device identifier and not linked to the
> user.

## Tracking / Data Linked

- **Tracking:** No — the app does not track users across apps or websites.
- **Data linked to identity:** No.
- **Data used for tracking:** No.

## Notes

- The privacy label matches the app's `PrivacyInfo.xcprivacy`
  (`openWhisperMac/PrivacyInfo.xcprivacy`): `NSPrivacyTracking=false`, and the
  three declared collected-data types above, all not-linked.
- The analytics toggle ("Share anonymous usage stats") defaults to OFF (true
  opt-in) and can be enabled in Settings; the worker receives only counters
  (see `docs/privacy-policy.md`).
