import { getRuntimeEnv } from "./runtime-env";

async function sha256(value: string): Promise<string> {
  const data = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function clientAddress(request: Request): string {
  return request.headers.get("cf-connecting-ip")
    ?? request.headers.get("x-forwarded-for")?.split(",")[0]?.trim()
    ?? "local";
}

const runLimitWindowMs = 10 * 60 * 1000;
const runLimitMaximum = 10;

export function rollingWindowBounds(now: number): { cutoff: number; expiresAt: number } {
  return { cutoff: now - runLimitWindowMs, expiresAt: now + runLimitWindowMs };
}

async function incrementBucket(key: string, amount: number, expiresAt: number): Promise<number> {
  const runtime = await getRuntimeEnv();
  const db = runtime.DB;
  if (!db) throw new Error("Usage counter is not configured");
  const now = Date.now();
  await db.prepare(`
    INSERT INTO usage_buckets (bucket_key, count, expires_at, updated_at)
    VALUES (?1, ?2, ?3, ?4)
    ON CONFLICT(bucket_key) DO UPDATE SET
      count = CASE WHEN usage_buckets.expires_at <= ?4 THEN ?2 ELSE usage_buckets.count + ?2 END,
      expires_at = CASE WHEN usage_buckets.expires_at <= ?4 THEN ?3 ELSE usage_buckets.expires_at END,
      updated_at = ?4
  `).bind(key, amount, expiresAt, now).run();
  const row = await db.prepare("SELECT count FROM usage_buckets WHERE bucket_key = ?1").bind(key).first<{ count: number }>();
  return row?.count ?? amount;
}

export async function enforceRunLimit(request: Request): Promise<void> {
  const runtime = await getRuntimeEnv();
  const db = runtime.DB;
  if (!db) throw new Error("Usage counter is not configured");
  const salt = runtime.RATE_LIMIT_SALT ?? runtime.OPENROUTER_API_KEY ?? runtime.OPENAI_API_KEY;
  if (!salt) throw new Error("Rate-limit salt is not configured");
  const now = Date.now();
  const { cutoff, expiresAt } = rollingWindowBounds(now);
  const ipHash = await sha256(`${salt}:${clientAddress(request)}`);
  const prefix = `ip:${ipHash}:`;
  const requestKey = `${prefix}${now.toString().padStart(13, "0")}:${crypto.randomUUID()}`;
  const result = await db.prepare(`
    INSERT INTO usage_buckets (bucket_key, count, expires_at, updated_at)
    SELECT ?1, 1, ?2, ?3
    WHERE (
      SELECT COALESCE(SUM(count), 0)
      FROM usage_buckets
      WHERE bucket_key >= ?4 AND bucket_key < ?5 AND updated_at > ?6
    ) < ?7
  `).bind(requestKey, expiresAt, now, prefix, `${prefix}\uffff`, cutoff, runLimitMaximum).run();
  if ((result.meta.changes ?? 0) === 0) throw new Error("RATE_LIMITED");

  await db.prepare("DELETE FROM usage_buckets WHERE expires_at <= ?1").bind(now).run().catch(() => undefined);
}

export async function takeGlobalModelCalls(amount: number): Promise<void> {
  const now = new Date();
  const day = now.toISOString().slice(0, 10);
  const expiresAt = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 3);
  const count = await incrementBucket(`global:${day}`, amount, expiresAt);
  if (count > 300) throw new Error("DAILY_LIMITED");
}
