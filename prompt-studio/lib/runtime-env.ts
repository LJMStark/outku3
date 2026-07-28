export type RuntimeEnv = {
  DB?: D1Database;
  RATE_LIMIT_SALT?: string;
  OPENROUTER_API_KEY?: string;
  OPENAI_API_KEY?: string;
  FALLBACK_API_KEY?: string;
  OPENAI_MODEL?: string;
};

export async function getRuntimeEnv(): Promise<RuntimeEnv> {
  const workersRuntime = await import("cloudflare:workers");
  return workersRuntime.env as unknown as RuntimeEnv;
}
