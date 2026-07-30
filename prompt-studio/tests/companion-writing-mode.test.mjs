import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  context,
  environment,
  memoryD1,
  projectRoot,
  worker,
} from "./support/worker-harness.mjs";

test("compile exposes deterministic normal and signature-quote modes", async () => {
  const app = await worker();
  const normalResponse = await app.fetch(new Request("http://localhost/api/compile", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      scenarioId: "companionPhrase",
      characters: ["silas"],
      writingMode: "normal",
      context: {},
    }),
  }), environment(), context());
  const quoteResponse = await app.fetch(new Request("http://localhost/api/compile", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      scenarioId: "companionPhrase",
      characters: ["silas"],
      writingMode: "signatureQuote",
      quoteIndex: 1,
      context: {},
    }),
  }), environment(), context());

  assert.equal(normalResponse.status, 200);
  assert.equal(quoteResponse.status, 200);
  const [normal] = (await normalResponse.json()).results;
  const [signature] = (await quoteResponse.json()).results;
  assert.equal(normal.writingMode, "normal");
  assert.equal(normal.approvedQuote, undefined);
  assert.equal(normal.parameters.temperature, 0.9);
  assert.match(normal.systemPrompt, /MODE: NORMAL/);
  assert.equal(signature.writingMode, "signatureQuote");
  assert.equal(signature.parameters.temperature, 0);
  // Derived from the spec, not pinned: silas's approved bank was expanded (client 2026-07-28),
  // and hardcoding a quote here means every future bank edit fails an unrelated mode assertion.
  const spec = JSON.parse(await readFile(new URL("lib/prompt-spec.json", projectRoot), "utf8"));
  const expectedQuote = spec.characters.find(({ id }) => id === "silas").approvedQuotes[1];
  assert.equal(signature.approvedQuote.source, expectedQuote.source);
  assert.match(signature.systemPrompt, /MODE: SIGNATURE QUOTE/);
  assert.ok(signature.systemPrompt.includes(expectedQuote.text));
});

test("compile rejects unknown writing modes and invalid quote indexes", async () => {
  const app = await worker();
  for (const body of [
    { scenarioId: "companionPhrase", characters: ["joy"], writingMode: "sometimes", context: {} },
    { scenarioId: "companionPhrase", characters: ["joy"], writingMode: "signatureQuote", quoteIndex: -1, context: {} },
    { scenarioId: "companionPhrase", characters: ["joy"], writingMode: "signatureQuote", quoteIndex: 1.5, context: {} },
  ]) {
    const response = await app.fetch(new Request("http://localhost/api/compile", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    }), environment(), context());
    assert.equal(response.status, 400);
  }
});

test("signature-quote runs are deterministic and do not call OpenRouter", async () => {
  const app = await worker();
  const originalFetch = globalThis.fetch;
  let openRouterCalled = false;
  globalThis.fetch = async (input, init) => {
    if (String(input) === "https://openrouter.ai/api/v1/chat/completions") openRouterCalled = true;
    return originalFetch(input, init);
  };
  const runtime = { DB: memoryD1(), RATE_LIMIT_SALT: "test-salt" };
  globalThis.__promptStudioTestEnv = runtime;
  try {
    const response = await app.fetch(new Request("http://localhost/api/run", {
      method: "POST",
      headers: { "content-type": "application/json", origin: "http://localhost" },
      body: JSON.stringify({
        scenarioId: "companionPhrase",
        characters: ["silas"],
        writingMode: "signatureQuote",
        quoteIndex: 1,
        context: { deadlineTitles: ["Client demo"], focusMinutes: 135 },
      }),
    }), environment(runtime), context());
    assert.equal(response.status, 200);
    const [result] = (await response.json()).results;
    assert.equal(result.parameters.temperature, 0);
    assert.equal(result.actualModel, "deterministic/approved-quote");
    // Format is the client's `"text" - source` (v2.10.0); derived from the spec so a bank edit
    // does not fail this test. The passing `approvedQuote` check below is what pins runtime
    // output and validator expectation to the same format.
    const runSpec = JSON.parse(await readFile(new URL("lib/prompt-spec.json", projectRoot), "utf8"));
    const runQuote = runSpec.characters.find(({ id }) => id === "silas").approvedQuotes[1];
    assert.equal(result.rawOutput, `"${runQuote.text}" - ${runQuote.source}`);
    assert.equal(result.validation.find((item) => item.id === "approvedQuote")?.passed, true);
    assert.equal(result.validation.find((item) => item.id === "punctuation")?.passed, true);
    assert.equal(result.validation.some((item) => item.id === "deadline" || item.id === "focus"), false);
    assert.equal(openRouterCalled, false);
  } finally {
    globalThis.fetch = originalFetch;
    delete globalThis.__promptStudioTestEnv;
  }
});

test("Joy generative signature runs pass model preflight and the shared daily budget", async () => {
  const app = await worker();
  const originalFetch = globalThis.fetch;
  let upstreamCalls = 0;
  globalThis.fetch = async (input, init) => {
    if (String(input) === "https://openrouter.ai/api/v1/chat/completions") {
      upstreamCalls += 1;
      return Response.json({ choices: [{ message: { content: "A small finish can still hold a little sunlight." } }] });
    }
    return originalFetch(input, init);
  };
  const request = () => new Request("http://localhost/api/run", {
    method: "POST",
    headers: { "content-type": "application/json", origin: "http://localhost" },
    body: JSON.stringify({
      scenarioId: "companionPhrase",
      characters: ["joy"],
      writingMode: "signatureQuote",
      context: {},
    }),
  });

  try {
    const missingKeyRuntime = { DB: memoryD1(), RATE_LIMIT_SALT: "joy-signature-no-key" };
    globalThis.__promptStudioTestEnv = missingKeyRuntime;
    const missingKey = await app.fetch(request(), environment(missingKeyRuntime), context());
    assert.equal(missingKey.status, 503);
    assert.equal(upstreamCalls, 0);

    const fullBudgetDB = memoryD1();
    const now = Date.now();
    const day = new Date(now).toISOString().slice(0, 10);
    await fullBudgetDB.prepare("INSERT INTO usage_buckets VALUES (?1, ?2, ?3, ?4)")
      .bind(`global:${day}`, 300, now + 3 * 24 * 60 * 60 * 1000, now)
      .run();
    const fullBudgetRuntime = {
      DB: fullBudgetDB,
      RATE_LIMIT_SALT: "joy-signature-full-budget",
      OPENROUTER_API_KEY: "test-key",
    };
    globalThis.__promptStudioTestEnv = fullBudgetRuntime;
    const fullBudget = await app.fetch(request(), environment(fullBudgetRuntime), context());
    assert.equal(fullBudget.status, 429);
    assert.equal(upstreamCalls, 0);

    const configuredRuntime = {
      DB: memoryD1(),
      RATE_LIMIT_SALT: "joy-signature-configured",
      OPENROUTER_API_KEY: "test-key",
    };
    globalThis.__promptStudioTestEnv = configuredRuntime;
    const generated = await app.fetch(request(), environment(configuredRuntime), context());
    assert.equal(generated.status, 200);
    const [result] = (await generated.json()).results;
    assert.equal(result.rawOutput, "A small finish can still hold a little sunlight.");
    assert.equal(result.actualModel, "openai/gpt-oss-120b");
    assert.equal(upstreamCalls, 1);
  } finally {
    globalThis.fetch = originalFetch;
    delete globalThis.__promptStudioTestEnv;
  }
});
