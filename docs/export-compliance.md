# OpenWhisper — Export Compliance (macOS)

_Last updated: August 19, 2026_

Answers for the App Store Connect **Export Compliance** questionnaire for
`pl.piszeprogramy.openwhisper.macos`.

## Answer

**No** — the app does not use encryption that requires an exemption.

## Justification

- All network traffic uses standard `URLSession` over **HTTPS only**
  (OpenRouter, Hugging Face, the analytics Worker).
- No use of `CommonCrypto`, `CryptoKit`, `SecKey`, or any custom encryption.
  (`Security` framework is used only for Keychain storage of the user's own
  API key — standard Keychain behavior, not "encryption" requiring an export
  license.)
- No file encryption, no DRM, no E2E-messaging features.
- The app does not implement or call into a cryptographic library directly.

## If prompted about "contains encryption"

Select: **"No — the app does not use encryption other than the standard HTTPS
provided by the system (URLSession)."**

## Automating the answer (no questionnaire on every upload)

The macOS and iOS Info.plist set **`ITSAppUsesNonExemptEncryption` = `false`**,
which tells App Store Connect the app only uses exempt encryption (standard
HTTPS/TLS). Once the key is present in the build, App Store Connect no longer
asks the Export Compliance questionnaire on upload.

- macOS: `openWhisperMac/Info.plist`
- iOS: `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` in `project.pbxproj`

## Reference

- All outbound URLs: `openrouter.ai/api/v1/...`, `huggingface.co/...`,
  `openwhisper-usage.dev-4cb.workers.dev/v1/track`.
- App Transport Security is not weakened (`NSAppTransportSecurity` absent;
  HTTPS-only).
