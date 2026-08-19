# OpenWhisper Privacy Policy

_Last updated: August 19, 2026_

OpenWhisper is a speech-to-text app for macOS and iPhone made by pisze-programy.
This policy explains what data the app processes, where it goes, and how you can
control it. "OpenWhisper" means the OpenWhisper app on any platform.

## The short version

- **Speech is transcribed on your device.** Your microphone audio is processed
  locally by an on-device speech model and is not uploaded by OpenWhisper.
- **Transcript text stays local by default.** Nothing you dictate leaves your
  device unless you turn on **AI formatting** or **translation**.
- **AI formatting and translation are opt-in.** When enabled, the transcript
  text is sent to **OpenRouter**, a third-party AI provider, using your own
  OpenRouter API key. This happens only when you choose to use those features.
- **Anonymous usage analytics are opt-in.** We may receive usage counters only
  — never your audio or transcript text.
- **No account, no sign-up.** We have no way to contact you or to identify you
  personally.

## What we process and where it goes

### 1. Microphone audio — on-device only
When you dictate, OpenWhisper records your speech from the microphone. The audio
is transcribed to text locally using a speech model that runs on your device.
Your audio is not uploaded to OpenWhisper servers or to OpenRouter.

### 2. Transcript text — stays on your device by default
Your transcribed text is kept locally (for example in your on-device history,
which you can clear at any time). It is not transmitted anywhere unless you
enable AI formatting or translation.

### 3. AI formatting and translation — sent to OpenRouter only when you turn them on
If you enable **AI formatting** (rewriting your text in a selected style) or
**translation**, the transcript text is sent to **OpenRouter**
(https://openrouter.ai) using an API key that you provide yourself in the app's
Settings. OpenRouter routes the request to one of its supported AI models. This
is your choice: leave formatting set to "None" and no text is ever sent.

Because the request uses **your own** API key, it is billed to you and appears
in your OpenRouter account's usage. Please also see OpenRouter's own privacy
policy and terms for how they handle the text you send them.

### 4. Anonymous usage analytics — opt-in, counters only
If you leave the "Share anonymous usage stats" setting enabled, the app reports
basic usage counters to our analytics service (a Cloudflare Worker). These
counters include things like the feature used (formatting vs. translation), the
language, whether the request succeeded, and response latency. They are tied to
a random, per-install identifier that cannot be traced back to you. **No audio
and no transcript text is ever included.** You can disable this at any time in
Settings; disabling it stops all reporting immediately.

### 5. Speech model download
On first use the app downloads a speech model (~460 MB) from Hugging Face so
that transcription can run on your device. This is a one-time download.

## Storage and security

- The OpenRouter API key you provide is stored in your system's **Keychain**,
  not in plain text on disk.
- History is stored locally on your device. You can delete individual entries
  or clear your history from the app at any time.
- No OpenWhisper server stores your audio, transcript text, or API key.

## Data deletion

Because we do not collect accounts and our analytics store only anonymous
counters, there is nothing to delete on our side. Your local data — history,
recovery audio, and settings — is fully under your control and can be removed by
clearing the app's data or uninstalling the app.

## Third-party services

When you use AI formatting or translation, OpenRouter receives your transcript
text and your API key authorizes the request. OpenRouter's privacy policy is
available at https://openrouter.ai/privacy. When you download the speech model,
Hugging Face processes the download request. We are not responsible for the
practices of these third parties.

## Changes to this policy

We may update this policy from time to time. When we do, we will revise the
"last updated" date above.

## Contact

For questions about this policy, open an issue at
https://github.com/pisze-programy/openWhisper.
