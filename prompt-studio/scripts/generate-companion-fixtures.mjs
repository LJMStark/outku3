import { createHash } from "node:crypto";
import { writeFile } from "node:fs/promises";
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

const characters = ["joy", "silas", "nova"];
const scenarios = [
  "morningGreeting",
  "companionPhrase",
  "taskEncouragement",
  "scheduleReminder",
  "settlementSummary",
  "smartReminder",
  "settlementQuoteCelebration",
  "settlementQuoteOverloaded",
];
const writingModes = ["normal", "signatureQuote"];
const compileContext = {
  petName: "Kirole",
  recentTexts: ["One clear step is enough."],
  nextAgendaItem: "Now · Client demo",
  activeTaskTitle: "Finish demo",
  topTaskTitles: ["Finish demo", "Reply to email"],
};

const workerUrl = new URL("../dist/server/index.js", import.meta.url);
workerUrl.searchParams.set("fixtures", `${Date.now()}`);
const app = (await import(workerUrl.href)).default;
const environment = { ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) } };
const executionContext = { waitUntil() {}, passThroughOnException() {} };
const fixtures = [];

for (const characterId of characters) {
  for (const writingMode of writingModes) {
    for (const scenarioId of scenarios) {
      const body = {
        scenarioId,
        characters: [characterId],
        intimacyStage: "familiar",
        writingMode,
        ...(writingMode === "signatureQuote" ? { quoteIndex: 0 } : {}),
        context: compileContext,
      };
      const response = await app.fetch(new Request("http://localhost/api/compile", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(body),
      }), environment, executionContext);
      if (!response.ok) throw new Error(`Failed to compile ${characterId}/${writingMode}/${scenarioId}: ${response.status}`);
      const [compiled] = (await response.json()).results;
      fixtures.push({
        characterId,
        scenarioId,
        writingMode,
        ...(writingMode === "signatureQuote" ? { quoteIndex: 0 } : {}),
        expectedSystemSHA256: createHash("sha256").update(compiled.systemPrompt).digest("hex"),
        expectedUserSHA256: createHash("sha256").update(compiled.userPrompt).digest("hex"),
      });
    }
  }
}

await writeFile(new URL("../tests/fixtures/companion-prompts.json", import.meta.url), `${JSON.stringify(fixtures, null, 2)}\n`);
