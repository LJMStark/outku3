import { createClient } from "https://esm.sh/@supabase/supabase-js@2.112.3";

export const NO_STORE_HEADERS = {
  "Cache-Control": "no-store",
  "Pragma": "no-cache",
  "Referrer-Policy": "no-referrer",
  "Content-Security-Policy": "default-src 'none'",
  "X-Content-Type-Options": "nosniff",
};

export function json(data: unknown, status = 200): Response {
  return new Response(status === 204 ? null : JSON.stringify(data), {
    status,
    headers: { ...NO_STORE_HEADERS, "Content-Type": "application/json; charset=utf-8" },
  });
}

export function redirect(location: URL): Response {
  return new Response(null, {
    status: 303,
    headers: { ...NO_STORE_HEADERS, Location: location.toString() },
  });
}

export function requiredEnvironment(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`missing_${name.toLowerCase()}`);
  return value;
}

export function env(name: string): string | undefined {
  return Deno.env.get(name);
}

export function serviceClient() {
  return createClient(
    requiredEnvironment("SUPABASE_URL"),
    requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY"),
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}

export async function authenticatedUser(req: Request): Promise<{ id: string } | null> {
  const header = req.headers.get("Authorization") ?? "";
  const match = /^Bearer ([^\s]+)$/.exec(header);
  if (!match) return null;
  const client = createClient(
    requiredEnvironment("SUPABASE_URL"),
    requiredEnvironment("SUPABASE_ANON_KEY"),
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
  const { data, error } = await client.auth.getUser(match[1]);
  if (error || !data.user) return null;
  return { id: data.user.id };
}

export async function readSmallJSON(req: Request): Promise<Record<string, unknown>> {
  const declaredLength = Number(req.headers.get("Content-Length") ?? "0");
  if (declaredLength > 4096) throw new Error("request_too_large");
  const text = await req.text();
  if (new TextEncoder().encode(text).byteLength > 4096) throw new Error("request_too_large");
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    throw new Error("invalid_json");
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("invalid_json");
  return value as Record<string, unknown>;
}

export function requireExactKeys(
  body: Record<string, unknown>,
  required: string[],
): void {
  const expected = new Set(["action", ...required]);
  if (Object.keys(body).some((key) => !expected.has(key))) throw new Error("unexpected_parameter");
  for (const key of required) {
    if (typeof body[key] !== "string" || !(body[key] as string).trim()) {
      throw new Error("missing_parameter");
    }
  }
}

export function isUUID(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}
