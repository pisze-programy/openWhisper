export interface Env {
  USAGE_KV: KVNamespace;
}

interface TrackEvent {
  feature: "format" | "formatAndTranslate" | "translateOnly";
  ok: boolean;
  latencyMs: number;
  chars: number;
  style?: string;
  sourceLanguage?: string;
  targetLanguage?: string;
}

interface TrackPayload {
  app?: string;
  installId: string;
  ts?: string;
  events: TrackEvent[];
}

const FEATURES = new Set(["format", "formatAndTranslate", "translateOnly"]);
const ALLOWED_APPS = new Set(["openwhisper-macos", "openwhisper-ios"]);

// Abuse guard: generous per-install and per-IP caps per UTC day.
const MAX_EVENTS_PER_REQUEST = 20;
const MAX_EVENTS_PER_INSTALL_DAY = 2000;
const MAX_EVENTS_PER_IP_DAY = 5000;
const MAX_BODY_BYTES = 16_000;

const DAY_MS = 24 * 60 * 60 * 1000;

function todayKey(): string {
  return new Date().toISOString().slice(0, 10);
}

function utcDayStart(now: Date): Date {
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
}

function isInstallId(value: string): boolean {
  return /^[A-Za-z0-9-]{8,64}$/.test(value);
}

function validEvent(e: unknown): e is TrackEvent {
  if (typeof e !== "object" || e === null) return false;
  const ev = e as TrackEvent;
  return (
    typeof ev.feature === "string" &&
    FEATURES.has(ev.feature) &&
    typeof ev.ok === "boolean" &&
    Number.isInteger(ev.latencyMs) &&
    ev.latencyMs >= 0 &&
    ev.latencyMs < 3_600_000 &&
    Number.isInteger(ev.chars) &&
    ev.chars >= 0 &&
    (ev.style === undefined || typeof ev.style === "string") &&
    (ev.sourceLanguage === undefined || typeof ev.sourceLanguage === "string") &&
    (ev.targetLanguage === undefined || typeof ev.targetLanguage === "string")
  );
}

function jsonError(message: string, status: number): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { "content-type": "application/json" },
  });
}

// Increments a KV counter, respecting the optional `max` cap. Returns the new
// value (or Infinity once the cap is exceeded).
async function increment(
  env: Env,
  key: string,
  max: number,
  ttlSeconds: number,
): Promise<number> {
  const raw = await env.USAGE_KV.get(key);
  const current = raw === null ? 0 : parseInt(raw, 10) || 0;
  const next = current + 1;
  await env.USAGE_KV.put(key, String(next), { expirationTtl: ttlSeconds });
  return next;
}

// Adds an event to the per-install-per-day aggregate. Reads the current JSON,
// merges, writes back. Races are acceptable for analytics (best-effort).
async function recordDay(env: Env, installId: string, events: TrackEvent[]): Promise<void> {
  const date = todayKey();
  const key = `d:${installId}:${date}`;
  const raw = await env.USAGE_KV.get(key);
  let agg = raw ? (JSON.parse(raw) as DayAgg) : { date, n: 0, ok: 0, fail: 0, chars: 0, byFeature: {} };
  agg.n += events.length;
  for (const e of events) {
    if (e.ok) agg.ok += 1;
    else agg.fail += 1;
    agg.chars += e.chars;
    const bucket = (agg.byFeature[e.feature] ??= { n: 0, ok: 0, fail: 0 });
    bucket.n += 1;
    if (e.ok) bucket.ok += 1;
    else bucket.fail += 1;
  }
  await env.USAGE_KV.put(key, JSON.stringify(agg));
}

// Prunes daily aggregates and rate-limit counters older than `days` days so the
// KV namespace does not grow without bound. Runs on the cron trigger. Keys are
// `prefix:<id>:<YYYY-MM-DD>`; the date is always the last path component.
async function pruneOldKeys(env: Env, days = 90): Promise<void> {
  const cutoff = new Date(Date.now() - days * DAY_MS).toISOString().slice(0, 10);
  for (const prefix of ["d:", "rl:"]) {
    let cursor: string | undefined;
    for (;;) {
      const list = await env.USAGE_KV.list(prefix ? { prefix, cursor } : { cursor });
      const stale = list.keys.filter((k) => {
        const date = k.name.split(":").at(-1) ?? "";
        return date <= cutoff;
      });
      if (stale.length > 0) {
        await Promise.all(stale.map((k) => env.USAGE_KV.delete(k.name)));
      }
      if (list.list_complete) break;
      cursor = list.cursor;
    }
  }
}

interface DayAgg {
  date: string;
  n: number;
  ok: number;
  fail: number;
  chars: number;
  byFeature: Record<string, { n: number; ok: number; fail: number }>;
}

async function handleTrack(request: Request, env: Env): Promise<Response> {
  const body = await request.arrayBuffer();
  if (body.byteLength > MAX_BODY_BYTES) {
    return jsonError("payload too large", 413);
  }

  let payload: TrackPayload;
  try {
    payload = JSON.parse(new TextDecoder().decode(body)) as TrackPayload;
  } catch {
    return jsonError("invalid JSON", 400);
  }

  if (!isInstallId(payload.installId ?? "")) {
    return jsonError("invalid installId", 400);
  }
  if (!Array.isArray(payload.events) || payload.events.length === 0 || payload.events.length > MAX_EVENTS_PER_REQUEST) {
    return jsonError("events must be an array of 1..20 items", 400);
  }
  if (!payload.events.every(validEvent)) {
    return jsonError("invalid event", 400);
  }
  if (payload.app !== undefined && !ALLOWED_APPS.has(payload.app)) {
    return jsonError("unknown app", 400);
  }

  const now = new Date();
  const ttlSeconds = Math.ceil((utcDayStart(now).getTime() + DAY_MS - now.getTime()) / 1000);

  // Per-install daily cap.
  const installCount = await increment(
    env,
    `rl:${payload.installId}:${todayKey()}`,
    MAX_EVENTS_PER_INSTALL_DAY,
    ttlSeconds,
  );
  if (installCount > MAX_EVENTS_PER_INSTALL_DAY) {
    return jsonError("daily limit reached", 429);
  }

  // Per-IP daily cap (best-effort; Cloudflare may strip the header in some setups).
  const ip = request.headers.get("cf-connecting-ip") ?? "unknown";
  const ipCount = await increment(env, `rl:ip:${ip}:${todayKey()}`, MAX_EVENTS_PER_IP_DAY, ttlSeconds);
  if (ipCount > MAX_EVENTS_PER_IP_DAY) {
    return jsonError("daily limit reached", 429);
  }

  await recordDay(env, payload.installId, payload.events);
  return new Response(null, { status: 204 });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204 });
    }
    const url = new URL(request.url);
    if (url.pathname === "/v1/track" && request.method === "POST") {
      return handleTrack(request, env);
    }
    if (url.pathname === "/health") {
      return new Response("ok", { status: 200 });
    }
    return jsonError("not found", 404);
  },

  // Daily cleanup of expired aggregates and rate-limit counters.
  async scheduled(_event: unknown, env: Env): Promise<void> {
    await pruneOldKeys(env);
  },
};
