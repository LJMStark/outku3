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

async function compileScenario(body, label) {
  const response = await app.fetch(new Request("http://localhost/api/compile", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  }), environment, executionContext);
  if (!response.ok) throw new Error(`Failed to compile ${label}: ${response.status}`);
  return (await response.json()).results[0];
}

function promptHashes(compiled) {
  return {
    expectedSystemSHA256: createHash("sha256").update(compiled.systemPrompt).digest("hex"),
    expectedUserSHA256: createHash("sha256").update(compiled.userPrompt).digest("hex"),
  };
}

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
      const compiled = await compileScenario(body, `${characterId}/${writingMode}/${scenarioId}`);
      fixtures.push({
        characterId,
        scenarioId,
        writingMode,
        ...(writingMode === "signatureQuote" ? { quoteIndex: 0 } : {}),
        ...promptHashes(compiled),
      });
    }
  }
}

await writeFile(new URL("../tests/fixtures/companion-prompts.json", import.meta.url), `${JSON.stringify(fixtures, null, 2)}\n`);

// Tool prompts (no character / writing mode). Contexts MUST stay identical to the two consumers of
// the fixture file — tests/rendered-html.test.mjs `contexts` and the Swift
// PromptSpecConsistencyTests.compilationForToolFixture switch — or the cross-runtime hash compare
// is meaningless: it would compare two different prompts rather than two runtimes.
const categoryDefinitions = [
  "1 = Deep Work (focused solo output: coding, writing, design, data analysis)",
  "2 = Meetings & Synced (meetings, calls, syncs, standups, interviews, 1:1s)",
  "3 = Administrative & Routine (email, forms, paperwork, errands, chores)",
  "4 = Critical Deadlines (launches, contract/payment due dates, submissions)",
  "5 = Bio-Habits & Wellness (stretch, hydrate, vitamins, sleep wind-down, workout)",
  "6 = Rest & Recharge (nap, lunch, reading, pets, games, personal downtime)",
].join("\n");
const toolContexts = {
  haiku: {
    timeContext: " in the afternoon",
    taskContext: " who has completed 2 task(s) today with 3 task(s) remaining",
    moodContext: ". Their pet companion is feeling focused",
    sceneContext: ". Their E-ink companion display shows the 'Forest' scene. Use imagery from this scene in the haiku",
  },
  screensaver: { isPostcard: true, usageDays: 21, profileContext: "Calm companion", workContext: "Launch prep" },
  taskOverview: { notes: "Ship the final demo" },
  daySummary: { eventDigest: "09:00 Product sync; 10:00 Client demo" },
  settlementReview: {
    eventDigest: "15:00 Client demo",
    deadlineTitles: ["Client demo"],
    focusMinutes: 240,
    tasksCompleted: 3,
    tasksTotal: 6,
  },
  // eventCategories are strings: the compile API rejects number arrays in context.
  eventSupportText: { events: ["Product sync", "Client deadline", "Stretch break"], eventCategories: ["2", "4", "5"], isDayPacked: true },
  eventClassification: { events: ["Product sync", "Client deadline"], categoryDefinitions },
  translation: { text: "Protect the quiet hour." },
};

const metaResponse = await app.fetch(
  new Request("http://localhost/api/meta"),
  environment,
  executionContext,
);
if (!metaResponse.ok) throw new Error(`Failed to read prompt meta: ${metaResponse.status}`);
const toolIds = (await metaResponse.json()).toolPrompts.map((tool) => tool.id);
const toolFixtures = [];

for (const scenarioId of toolIds) {
  const context = toolContexts[scenarioId];
  if (!context) throw new Error(`Missing fixture context for tool prompt: ${scenarioId}`);
  const compiled = await compileScenario(
    { scenarioId, context },
    `tool ${scenarioId}`,
  );
  toolFixtures.push({
    scenarioId,
    ...promptHashes(compiled),
  });
}

await writeFile(new URL("../tests/fixtures/tool-prompts.json", import.meta.url), `${JSON.stringify(toolFixtures, null, 2)}\n`);
