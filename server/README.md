# OpenWhisper usage analytics Worker

Collects **anonymous usage counters only** from the OpenWhisper apps. It never
receives transcript text, audio, or any user content. Payloads contain an
install ID (random UUID, per-install), the feature used, language codes, style,
outcome, latency and character count.

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| POST | `/v1/track` | Accepts a batch of counters (validated, rate-limited) |
| GET | `/health` | Liveness probe |

`POST /v1/track` body:

```json
{
  "app": "openwhisper-macos",
  "installId": "9F0A4D63-…",
  "ts": "2026-08-19T12:00:00Z",
  "events": [
    {
      "feature": "format",
      "ok": true,
      "latencyMs": 812,
      "chars": 214,
      "style": "formal",
      "sourceLanguage": "pl",
      "targetLanguage": null
    }
  ]
}
```

Responses: `204` on success, `400` invalid payload, `413` too large, `429` daily
cap hit, `404` unknown route.

## Storage

- **Rate limiting:** `rl:<installId>:<YYYY-MM-DD>` and `rl:ip:<ip>:<YYYY-MM-DD>`
  counters (best-effort; per-install 2000 events/day, per-IP 5000/day).
- **Aggregates:** `d:<installId>:<YYYY-MM-DD>` JSON with per-day totals and
  per-feature breakdown. Keys expire via the daily cron (90-day retention).

## Deploy

Prerequisites: `npm install` in this directory, a Cloudflare account with
Workers enabled.

```sh
npm install
npx wrangler login

# One-time: create the KV namespace and paste the returned ids into wrangler.toml
npx wrangler kv namespace create USAGE_KV

npm run deploy   # or: npx wrangler deploy
```

After deploying, point the app at the worker. The app keeps the endpoint in one
place:

- `OpenWhisperShared/Sources/OpenWhisperShared/UsageAnalytics.swift` → `endpoint`

## Local dev

```sh
npm run dev
curl -X POST http://localhost:8787/v1/track \
  -H 'content-type: application/json' \
  -d '{"app":"openwhisper-macos","installId":"test-00000000","events":[{"feature":"format","ok":true,"latencyMs":100,"chars":10}]}'
```

## Notes

- No transcript text is ever stored — only counters.
- The worker has no API key of its own; it only stores aggregate numbers.
