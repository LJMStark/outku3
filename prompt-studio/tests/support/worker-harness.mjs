import { registerHooks } from "node:module";

registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier === "cloudflare:workers") {
      const source = "export const env = new Proxy({}, { get: (_, key) => globalThis.__promptStudioTestEnv?.[key] });";
      return { shortCircuit: true, url: `data:text/javascript,${encodeURIComponent(source)}` };
    }
    return nextResolve(specifier, context);
  },
});

export const projectRoot = new URL("../../", import.meta.url);

export async function worker() {
  const workerUrl = new URL("../../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  return (await import(workerUrl.href)).default;
}

export function memoryD1() {
  const buckets = new Map();
  return {
    prepare(sql) {
      return {
        bind(...values) {
          return {
            async run() {
              if (/INSERT INTO usage_buckets[\s\S]*SELECT \?1/i.test(sql)) {
                const [key, expiresAt, updatedAt, prefix, upperBound, cutoff, maximum] = values;
                const recentCount = [...buckets.entries()]
                  .filter(([bucketKey, bucket]) => bucketKey >= prefix && bucketKey < upperBound && bucket.updatedAt > cutoff)
                  .reduce((total, [, bucket]) => total + bucket.count, 0);
                if (recentCount >= maximum) return { success: true, meta: { changes: 0 } };
                buckets.set(key, { count: 1, expiresAt, updatedAt });
                return { success: true, meta: { changes: 1 } };
              }
              if (/INSERT INTO usage_buckets/i.test(sql)) {
                const [key, amount, expiresAt, updatedAt] = values;
                const current = buckets.get(key);
                buckets.set(key, current && current.expiresAt > updatedAt
                  ? { count: current.count + amount, expiresAt: current.expiresAt, updatedAt }
                  : { count: amount, expiresAt, updatedAt });
              } else if (/DELETE FROM usage_buckets WHERE bucket_key =/i.test(sql)) {
                buckets.delete(values[0]);
              } else if (/DELETE FROM usage_buckets WHERE expires_at/i.test(sql)) {
                for (const [key, bucket] of buckets) {
                  if (bucket.expiresAt < values[0]) buckets.delete(key);
                }
              }
              return { success: true, meta: { changes: 1 } };
            },
            async first() {
              const bucket = buckets.get(values[0]);
              return bucket ? { count: bucket.count } : null;
            },
            async all() {
              const [prefix, upperBound, nowOrCutoff] = values;
              return {
                results: [...buckets.entries()]
                  .filter(([key, bucket]) => key >= prefix && key < upperBound
                    && (/updated_at\s*>/i.test(sql) ? bucket.updatedAt > nowOrCutoff : bucket.expiresAt > nowOrCutoff))
                  .map(([, bucket]) => ({ count: bucket.count })),
              };
            },
          };
        },
      };
    },
  };
}

export function environment(overrides = {}) {
  return {
    ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) },
    ...overrides,
  };
}

export function context() {
  return { waitUntil() {}, passThroughOnException() {} };
}

export async function runScenario(app, scenarioId, modelOutput, requestContext = {}, runtimeOverride) {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (input, init) => {
    const url = input instanceof Request ? input.url : String(input);
    if (url === "https://openrouter.ai/api/v1/chat/completions") {
      return Response.json({ choices: [{ message: { content: modelOutput } }] });
    }
    return originalFetch(input, init);
  };
  const runtime = runtimeOverride ?? {
    DB: memoryD1(),
    RATE_LIMIT_SALT: "test-salt",
    OPENROUTER_API_KEY: "test-key",
  };
  globalThis.__promptStudioTestEnv = runtime;
  try {
    return await app.fetch(new Request("http://localhost/api/run", {
      method: "POST",
      headers: { "content-type": "application/json", origin: "http://localhost" },
      body: JSON.stringify({ scenarioId, context: requestContext }),
    }), environment(runtime), context());
  } finally {
    globalThis.fetch = originalFetch;
    delete globalThis.__promptStudioTestEnv;
  }
}
