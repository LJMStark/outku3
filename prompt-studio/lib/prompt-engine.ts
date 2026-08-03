import promptSpecJson from "./prompt-spec.json";

export type CharacterId = "joy" | "silas" | "nova";
export type Locale = "zh" | "en";
export type WritingMode = "normal" | "signatureQuote";

export type ApprovedQuote = {
  text: string;
  source: string;
  /** Emotional tones this line fits. The App filters the bank by the current Mode B moment's
   *  tones (`modeBMomentTones`) so a celebration never draws a consolation line. Studio surfaces
   *  them for review; the filtering itself is App-side because quote-style Mode B skips the LLM. */
  tones: string[];
};

export type PromptContext = Record<string, string | number | boolean | string[]>;

export interface PromptOverrides {
  personaPrompt?: string;
  characterPrompt?: string;
  intimacyPrompt?: string;
  globalRules?: string;
  scenePrompt?: string;
  systemPrompt?: string;
  userPrompt?: string;
}

export interface CompileRequest {
  scenarioId: string;
  characters?: CharacterId[];
  intimacyStage?: string;
  writingMode?: WritingMode;
  quoteIndex?: number;
  context?: PromptContext;
  overrides?: Partial<Record<CharacterId, PromptOverrides>>;
}

export interface ValidationItem {
  id: string;
  labelZh: string;
  labelEn: string;
  passed: boolean;
  detail: string;
}

export interface CompiledPrompt {
  scenarioId: string;
  scenarioKind: "persona" | "tool";
  characterId?: CharacterId;
  writingMode?: WritingMode;
  approvedQuote?: ApprovedQuote;
  outputMaxBytes: number;
  systemPrompt: string;
  userPrompt: string;
  sanitizedInputs: PromptContext;
  parameters: {
    model: string;
    fallbackModel: string;
    temperature: number;
    contentMaxTokens: number;
    requestMaxTokens: number;
    reasoning: { effort: string; exclude: boolean };
    requireParameters: boolean;
    requestTimeoutSeconds: number;
  };
}

type VariableDefinition = string | {
  id?: string;
  key?: string;
  name?: string;
  default?: string | number | boolean | string[];
  maxLen?: number;
  maxLength?: number;
  userControlled?: boolean;
};

type CharacterDefinition = {
  id: CharacterId;
  displayName: string;
  virtue: string;
  characterPrompt: string;
  personaPrompt: string;
  approvedQuotes: ApprovedQuote[];
  wordLimits?: { default?: number; primaryMode?: number; secondaryMode?: number } | number;
  /** How Mode B is fulfilled: "quote" recites an approvedQuotes entry verbatim (deterministic,
   *  temperature 0); "generative" has the LLM write an original quotable line in the character's
   *  own voice, so approvedQuotes is empty by design. */
  secondaryModeStyle?: "quote" | "generative";
};

type WritingModeDefinition = {
  id: WritingMode;
  displayName: string;
  displayNameZh: string;
  weight: number;
  temperatureOverride: number | null;
  instructionTemplate: string;
  /** Mode B variant for characters whose secondaryModeStyle is "generative" (joy writes an
   *  original quotable line instead of reciting an approved quotation). */
  generativeInstructionTemplate?: string | null;
};

type ScenarioDefinition = {
  id: string;
  group: string;
  titleZh: string;
  titleEn: string;
  status: string;
  userPromptTemplate?: string;
  userPromptTemplates?: Record<string, string | undefined> | string[];
  systemPromptTemplate?: string;
  variables?: VariableDefinition[];
  parameters: { temperature: number; maxTokens: number };
  outputMaxBytes?: number;
  outputRules?: string[];
};

type PromptSpec = {
  schemaVersion: number;
  version: string;
  securityInstruction: string;
  eventCategoryDefinitions: string;
  model: {
    primaryModel?: string;
    model?: string;
    fallbackModel: string;
    reasoning: { effort: string; exclude: boolean };
    requireParameters: boolean;
    reasoningTokenHeadroom: number;
    requestTimeoutSeconds: number;
  };
  limits: Record<string, number | string>;
  globalRules: string[];
  writingModes: WritingModeDefinition[];
  companionSystemTemplate: string;
  characters: CharacterDefinition[];
  intimacyStages: Array<{ id: string; prompt?: string; intimacyPrompt?: string }>;
  personaScenes: ScenarioDefinition[];
  toolPrompts: ScenarioDefinition[];
  nonActivePaths: unknown[];
  /** Mode B moment id -> acceptable emotional tones. Consumed by the App when narrowing the
   *  approved-quote bank; mirrored here so Studio can display and validate the same mapping. */
  modeBMomentTones: Record<string, string[]>;
};

export const promptSpec = promptSpecJson as unknown as PromptSpec;

export function sanitize(raw: string, maxLen = 200): string {
  return raw
    .replaceAll("```", "ʼʼʼ")
    .replaceAll("<|", "<\u200B|")
    .replaceAll("|>", "|\u200B>")
    .replaceAll("</", "<\u200B/")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .join(" ")
    .slice(0, maxLen);
}

export function userContent(raw: string, maxLen = 200): string {
  return `<user_content>${sanitize(raw, maxLen)}</user_content>`;
}

function keyOf(variable: VariableDefinition): string {
  return typeof variable === "string" ? variable : variable.id ?? variable.key ?? variable.name ?? "";
}

const inputMaxLengths: Record<string, number> = {
  activeTaskTitle: 80,
  taskTitle: 120,
  taskNotes: 300,
  eventName: 80,
  notes: 300,
  text: 500,
  eventDigest: 400,
  profileContext: 300,
  workContext: 300,
  learnText: 300,
  recentTexts: 120,
  topTaskTitles: 60,
  deadlineTitles: 120,
  events: 120,
  sceneContext: 50,
};

function maxLenOf(variable: VariableDefinition): number {
  const key = keyOf(variable);
  return typeof variable === "string"
    ? inputMaxLengths[key] ?? 200
    : variable.maxLen ?? variable.maxLength ?? inputMaxLengths[key] ?? 200;
}

function defaultsFor(scenario: ScenarioDefinition): PromptContext {
  return Object.fromEntries(
    (scenario.variables ?? [])
      .map((variable) => [keyOf(variable), typeof variable === "string" ? "" : variable.default ?? ""])
      .filter(([key]) => Boolean(key)),
  );
}

function stringify(value: PromptContext[string]): string {
  if (Array.isArray(value)) return value.join("; ");
  return String(value ?? "");
}

function prepareInputs(scenario: ScenarioDefinition, context: PromptContext): PromptContext {
  const merged = { ...defaultsFor(scenario), ...context };
  const definitions = new Map((scenario.variables ?? []).map((item) => [keyOf(item), item]));
  return Object.fromEntries(
    Object.entries(merged).map(([key, value]) => {
      const definition = definitions.get(key);
      if (!definition || (typeof definition !== "string" && definition.userControlled === false) || typeof value === "number" || typeof value === "boolean") {
        return [key, value];
      }
      if (Array.isArray(value)) {
        const capped = key === "topTaskTitles" || key === "recentTexts"
          ? value.slice(0, 3)
          : key === "deadlineTitles"
            ? value.slice(0, 3)
            : key === "events"
              ? value.slice(0, Number(promptSpec.limits.scheduleEventCount))
            : value;
        return [key, capped.map((item) => sanitize(item, maxLenOf(definition)))];
      }
      if (scenario.id === "haiku" && ["timeContext", "taskContext", "moodContext", "sceneContext"].includes(key)) {
        const fragment = sanitize(String(value), 500);
        return [key, /^\s/.test(String(value)) ? ` ${fragment}` : fragment];
      }
      return [key, sanitize(String(value), maxLenOf(definition))];
    }),
  );
}

function templateValues(inputs: PromptContext): Record<string, string> {
  const raw = Object.fromEntries(Object.entries(inputs).map(([key, value]) => [key, stringify(value)]));
  const wrapped = Object.fromEntries(
    Object.entries(inputs).map(([key, value]) => [`${key}Wrapped`, userContent(stringify(value), 2000)]),
  );
  return { ...raw, ...wrapped };
}

function render(template: string, values: Record<string, string>): string {
  return template
    .replace(/\{\{\s*([\w.]+)\s*\}\}/g, (_, key: string) => values[key] ?? "")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function writingModeInstruction(mode: WritingMode, quote?: ApprovedQuote): string {
  const definition = promptSpec.writingModes.find((item) => item.id === mode);
  if (!definition) throw new Error(`Unknown writing mode: ${mode}`);
  if (mode === "normal") return definition.instructionTemplate;
  // Generative Mode B (joy): no approved quote exists — the model writes an original quotable
  // line in the character's own voice. Mirrors OpenAIService.writingModePrompt(for:).
  if (!quote) {
    const generative = definition.generativeInstructionTemplate;
    if (!generative) throw new Error("Generative signature mode requires generativeInstructionTemplate");
    return generative;
  }
  return render(definition.instructionTemplate, {
    quoteText: quote.text,
    quoteSource: quote.source,
  });
}

function scheduleDigest(inputs: PromptContext): string {
  const lines: string[] = [];
  const tasks = Array.isArray(inputs.topTaskTitles)
    ? inputs.topTaskTitles
    : stringify(inputs.topTaskTitles ?? "").split(/\n|;/).filter(Boolean);
  if (tasks.length) lines.push(`Tasks ahead: ${tasks.slice(0, 3).map((item) => userContent(item, 60)).join(", ")}`);
  const total = Number(inputs.tasksTotal ?? inputs.totalTasksToday ?? 0);
  const completed = Number(inputs.tasksCompleted ?? inputs.tasksCompletedToday ?? 0);
  if (total > 0) lines.push(`Done: ${completed} of ${total}`);
  const next = stringify(inputs.nextAgendaItem ?? "");
  if (next) lines.push(`Next: ${userContent(next, 80)}`);
  return lines.length ? lines.join("\n") : "Schedule: nothing visible";
}

function chooseToolUserTemplate(scenario: ScenarioDefinition, inputs: PromptContext): string {
  if (typeof scenario.userPromptTemplates === "string") return scenario.userPromptTemplates;
  if (Array.isArray(scenario.userPromptTemplates)) return scenario.userPromptTemplates[0] ?? "";
  if (scenario.userPromptTemplates) {
    const requested = stringify(inputs.variant ?? inputs.mode ?? "");
    if (requested && scenario.userPromptTemplates[requested]) return scenario.userPromptTemplates[requested];
    if (inputs.isPostcard === true && scenario.userPromptTemplates.postcard) return scenario.userPromptTemplates.postcard;
    if (inputs.isPostcard === false && scenario.userPromptTemplates.resting) return scenario.userPromptTemplates.resting;
    if (scenario.id === "daySummary") {
      return stringify(inputs.eventDigest ?? "").trim()
        ? scenario.userPromptTemplates.events ?? ""
        : scenario.userPromptTemplates.empty ?? "";
    }
    return Object.values(scenario.userPromptTemplates).find((value): value is string => typeof value === "string") ?? "";
  }
  return scenario.userPromptTemplate ?? "";
}

function systemWithSecurity(body: string): string {
  return body.startsWith(promptSpec.securityInstruction)
    ? body
    : `${promptSpec.securityInstruction}\n\n${body}`;
}

export function scenarioById(id: string): { kind: "persona" | "tool"; scenario: ScenarioDefinition } | undefined {
  const persona = promptSpec.personaScenes.find((item) => item.id === id);
  if (persona) return { kind: "persona", scenario: persona };
  const tool = promptSpec.toolPrompts.find((item) => item.id === id);
  return tool ? { kind: "tool", scenario: tool } : undefined;
}

function toolValues(scenario: ScenarioDefinition, inputs: PromptContext): Record<string, string> {
  const events = Array.isArray(inputs.events)
    ? inputs.events.slice(0, Number(promptSpec.limits.scheduleEventCount))
    : stringify(inputs.events ?? "").split(/\n|;/).map((item) => item.trim()).filter(Boolean)
        .slice(0, Number(promptSpec.limits.scheduleEventCount));
  const deadlines = (Array.isArray(inputs.deadlineTitles)
    ? inputs.deadlineTitles
    : stringify(inputs.deadlineTitles ?? "").split(/\n|;/).map((item) => item.trim()).filter(Boolean)).slice(0, 3);
  const focusMinutes = Number(inputs.focusMinutes ?? 0);
  const hours = Math.floor(focusMinutes / 60);
  const remainingMinutes = focusMinutes % 60;
  const focusLabel = hours > 0
    ? `${hours}h${remainingMinutes > 0 ? ` ${remainingMinutes}m` : ""}`
    : `${focusMinutes}m`;
  const eventDigest = stringify(inputs.eventDigest ?? inputs.events ?? "")
    .split(";")
    .map((item) => item.trim())
    .filter(Boolean)
    .slice(0, 8)
    .join("; ");
  const eventFacts = eventDigest ? `Today's events: ${eventDigest}` : "No events were scheduled today.";
  const categoryDefinitions = promptSpec.eventCategoryDefinitions;

  return {
    ...templateValues(inputs),
    notes: userContent(stringify(inputs.notes ?? ""), 300),
    taskTitle: userContent(stringify(inputs.taskTitle ?? ""), 120),
    taskNotes: userContent(stringify(inputs.taskNotes ?? ""), 300),
    text: userContent(stringify(inputs.text ?? ""), 500),
    profileContext: userContent(stringify(inputs.profileContext ?? ""), 300),
    workContext: userContent(stringify(inputs.workContext ?? ""), 300),
    eventDigest,
    eventFacts,
    deadlineFacts: deadlines.length ? `Deadline items: ${deadlines.join("; ")}` : "",
    focusFacts: focusMinutes > 0 ? `\nTotal focus time: ${focusLabel}.` : "",
    deadlineInstruction: deadlines.length ? "\nYou MUST mention the deadline item(s) listed in the facts." : "",
    focusInstruction: focusMinutes > 120 ? "\nYou MUST state the total focus time exactly as given in the facts." : "",
    numberedEvents: numberedEventList(scenario, events, inputs),
    categoryDefinitions,
  };
}

// eventSupportText prefixes each event with its category number: the six writing rules are
// dispatched by category, so the model needs it inline. Must stay byte-identical to the Swift
// builder (OpenAIService+EventSupportText.compileEventSupportTextPrompt) or the cross-runtime
// golden fixtures diverge. Other tools (eventClassification) send the bare numbered list.
function numberedEventList(
  scenario: ScenarioDefinition,
  events: string[],
  inputs: PromptContext,
): string {
  if (scenario.id !== "eventSupportText") {
    return `<user_content>${events.map((item, index) => `${index + 1}. ${sanitize(item, 120)}`).join("\n")}</user_content>`;
  }
  const categories = (Array.isArray(inputs.eventCategories)
    ? inputs.eventCategories
    : stringify(inputs.eventCategories ?? "").split(/[,\s]+/).filter(Boolean)
  ).map((item) => Number(item));
  // Day-density hint for categories 5 and 6 only. Mirrors Swift
  // OpenAIService.densityHint(for:) — the golden fixtures compare compiled prompts byte for byte,
  // so the tag text and the categories it applies to must match exactly.
  const isDayPacked = inputs.isDayPacked === true || stringify(inputs.isDayPacked ?? "") === "true";
  // Category 5 (Wellness) only — the one category whose client rule reads the schedule. Rest (6)
  // grants permission regardless of how the day went, so it gets no hint.
  const densityHint = (category: number) =>
    category === 5 ? (isDayPacked ? ", packed day" : ", open day") : "";
  // Absent category falls back to 3 (Administrative & Routine) — the same "uncategorized shows as
  // admin" decision the App applies in EventCategoryService before reaching this prompt.
  const lines = events.map((item, index) => {
    const category = categories[index] ?? 3;
    return `${index + 1}. [category ${category}${densityHint(category)}] ${sanitize(item, 120)}`;
  });
  return `<user_content>${lines.join("\n")}</user_content>`;
}

function buildToolUserPrompt(scenario: ScenarioDefinition, inputs: PromptContext, values: Record<string, string>): string {
  if (scenario.id === "haiku") {
    return userContent(render(chooseToolUserTemplate(scenario, inputs), values), 1_000);
  }
  if (scenario.id === "daySummary") {
    const eventsText = values.eventDigest
      ? `Today's events: ${values.eventDigest}`
      : "No events scheduled today.";
    return userContent(eventsText, 400);
  }
  if (scenario.id === "settlementReview") {
    const rendered = render(chooseToolUserTemplate(scenario, inputs), values);
    return userContent(rendered, 500);
  }
  return render(chooseToolUserTemplate(scenario, inputs), values);
}

export function compilePrompts(request: CompileRequest): CompiledPrompt[] {
  const found = scenarioById(request.scenarioId);
  if (!found) throw new Error(`Unknown scenario: ${request.scenarioId}`);
  const inputs = prepareInputs(found.scenario, request.context ?? {});
  const usesPersona = found.kind === "persona" || found.scenario.id === "taskLibraryPhaseText";
  const characters = usesPersona ? request.characters?.slice(0, 3) ?? ["joy"] : [undefined];

  return characters.map((characterId) => {
    const character = characterId ? promptSpec.characters.find((item) => item.id === characterId) : undefined;
    const writingMode = found.kind === "persona" ? request.writingMode ?? "normal" : undefined;
    const approvedQuote = writingMode === "signatureQuote"
      ? character?.approvedQuotes[request.quoteIndex ?? 0]
      : undefined;
    const intimacy = promptSpec.intimacyStages.find((item) => item.id === (request.intimacyStage ?? "familiar"));
    const overrides = characterId ? request.overrides?.[characterId] ?? {} : request.overrides?.joy ?? {};
    const values = {
      ...(found.kind === "tool" ? toolValues(found.scenario, inputs) : templateValues(inputs)),
      securityInstruction: promptSpec.securityInstruction,
      characterPrompt: overrides.characterPrompt ?? character?.characterPrompt ?? "",
      intimacyPrompt: overrides.intimacyPrompt ?? intimacy?.prompt ?? intimacy?.intimacyPrompt ?? "",
      personaPrompt: overrides.personaPrompt ?? character?.personaPrompt ?? "",
      writingModePrompt: writingMode ? writingModeInstruction(writingMode, approvedQuote) : "",
      globalRules: overrides.globalRules ?? "",
      schedule: scheduleDigest(inputs),
      petName: userContent(stringify(inputs.petName ?? character?.displayName ?? "Kirole"), 50),
      toneHint: inputs.learnText ? `\nTone hint: ${userContent(stringify(inputs.learnText), 300)}` : "",
      recentTexts: Array.isArray(inputs.recentTexts)
        ? inputs.recentTexts.slice(0, 3).map((item) => userContent(item, 120)).join(" / ")
        : stringify(inputs.recentTexts ?? "").trim()
          ? userContent(stringify(inputs.recentTexts), 360)
          : "",
    };

    let defaultSystem: string;
    if (found.kind === "persona") {
      defaultSystem = render(promptSpec.companionSystemTemplate, values);
    } else if (found.scenario.id === "taskLibraryPhaseText") {
      defaultSystem = [values.characterPrompt, values.intimacyPrompt, values.personaPrompt]
        .join("\n") + `\n\n${render(found.scenario.systemPromptTemplate ?? "", values)}`;
    } else {
      defaultSystem = render(found.scenario.systemPromptTemplate ?? "", values);
    }
    if (overrides.globalRules?.trim()) defaultSystem += `\n\n${overrides.globalRules.trim()}`;
    let defaultUser = found.kind === "persona"
      ? render(found.scenario.userPromptTemplate ?? "", {
          ...values,
          activeTaskTitle: userContent(stringify(inputs.activeTaskTitle ?? "a task"), 80),
          eventName: userContent((stringify(inputs.eventName).trim() || stringify(inputs.nextAgendaItem ?? "an event")).replace(/^Now · /, ""), 80),
        })
      : buildToolUserPrompt(found.scenario, inputs, values);
    if (found.kind === "persona" && values.recentTexts) {
      defaultUser = `ALREADY SAID (never repeat): ${values.recentTexts}\n\n${defaultUser}`;
    }
    const systemBody = overrides.systemPrompt ?? defaultSystem;
    const systemPrompt = systemWithSecurity(systemBody);
    const userPrompt = overrides.userPrompt ?? overrides.scenePrompt ?? defaultUser;
    const primaryModel = promptSpec.model.primaryModel ?? promptSpec.model.model ?? "openai/gpt-oss-120b";
    const modeTemperature = writingMode
      ? promptSpec.writingModes.find((item) => item.id === writingMode)?.temperatureOverride
      : null;

    return {
      scenarioId: request.scenarioId,
      scenarioKind: found.kind,
      characterId,
      writingMode,
      approvedQuote,
      outputMaxBytes: found.scenario.outputMaxBytes
        ?? Number(promptSpec.limits.defaultHardwareBytes),
      systemPrompt,
      userPrompt,
      sanitizedInputs: inputs,
      parameters: {
        model: primaryModel,
        fallbackModel: promptSpec.model.fallbackModel,
        temperature: modeTemperature ?? found.scenario.parameters.temperature,
        contentMaxTokens: found.scenario.parameters.maxTokens,
        requestMaxTokens: found.scenario.parameters.maxTokens + promptSpec.model.reasoningTokenHeadroom,
        reasoning: promptSpec.model.reasoning,
        requireParameters: promptSpec.model.requireParameters,
        requestTimeoutSeconds: promptSpec.model.requestTimeoutSeconds,
      },
    };
  });
}

export function utf8Truncate(text: string, maxBytes = 120): string {
  const encoder = new TextEncoder();
  if (encoder.encode(text).length <= maxBytes) return text;
  const result = utf8Prefix(text, maxBytes);
  let lastSentenceEnd = "";
  const sentenceEnders = new Set([".", "!", "?", "。", "！", "？"]);
  let prefix = "";
  for (const character of graphemes(result)) {
    prefix += character;
    if (sentenceEnders.has(character)) lastSentenceEnd = prefix;
  }
  return lastSentenceEnd || result;
}

export function utf8Prefix(text: string, maxBytes: number): string {
  const encoder = new TextEncoder();
  if (encoder.encode(text).length <= maxBytes) return text;
  let result = "";
  for (const character of graphemes(text)) {
    if (encoder.encode(result + character).length > maxBytes) break;
    result += character;
  }
  return result;
}

const graphemeSegmenter = new Intl.Segmenter(undefined, { granularity: "grapheme" });

function graphemes(text: string): string[] {
  return Array.from(graphemeSegmenter.segment(text), ({ segment }) => segment);
}

export function outputMaxBytes(compiled: CompiledPrompt): number {
  return compiled.outputMaxBytes;
}

type NumberedEventSupportLine = { index: number; text: string };

function expectedEventSupportCount(compiled: CompiledPrompt): number {
  if (compiled.scenarioId === "taskLibraryPhaseText") return 3;
  const source = compiled.sanitizedInputs.events;
  return Array.isArray(source)
    ? source.length
    : stringify(source ?? "").split(/\n|;/).map((item) => item.trim()).filter(Boolean).length;
}

function parseEventSupportLines(compiled: CompiledPrompt, output: string): {
  lines: NumberedEventSupportLine[];
  expectedCount: number;
  formatPassed: boolean;
} {
  const expectedCount = expectedEventSupportCount(compiled);
  const byIndex = new Map<number, string>();
  let formatPassed = true;
  for (const rawLine of output.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line) continue;
    const separator = line.indexOf("|");
    if (separator < 0) {
      formatPassed = false;
      continue;
    }
    const rawIndex = line.slice(0, separator).trim();
    if (!/^\d+$/.test(rawIndex)) {
      formatPassed = false;
      continue;
    }
    const index = Number(rawIndex);
    const text = line.slice(separator + 1).trim();
    if (index < 1 || index > expectedCount || byIndex.has(index) || !text) {
      formatPassed = false;
      continue;
    }
    byIndex.set(index, text);
  }
  return {
    lines: [...byIndex.entries()]
      .sort(([left], [right]) => left - right)
      .map(([index, text]) => ({ index, text })),
    expectedCount,
    formatPassed,
  };
}

export function deviceOutputs(compiled: CompiledPrompt, output: string): {
  truncatedOutput: string;
  asciiOutput: string;
} {
  const maxBytes = outputMaxBytes(compiled);
  if (!["eventSupportText", "taskLibraryPhaseText"].includes(compiled.scenarioId)) {
    const truncatedOutput = utf8Truncate(output, maxBytes);
    return {
      truncatedOutput,
      asciiOutput: utf8Prefix(asciiForEInk(truncatedOutput), maxBytes),
    };
  }

  const { lines } = parseEventSupportLines(compiled, output);
  const truncatedLines = lines.map(({ index, text }) => ({
    index,
    text: utf8Truncate(text, maxBytes),
  }));
  return {
    truncatedOutput: truncatedLines.map(({ index, text }) => `${index}|${text}`).join("\n"),
    // The App's wire path sanitizes first, then clamps the final ASCII bytes. Use the original
    // per-line text here; truncating raw UTF-8 first loses expanding mappings at the boundary.
    asciiOutput: lines
      .map(({ index, text }) => `${index}|${utf8Prefix(asciiForEInk(text), maxBytes)}`)
      .join("\n"),
  };
}

const asciiMap: Record<string, string> = {
  "\t": " ", "\n": " ", "\r": " ",
  " ": " ", " ": " ", " ": " ", " ": " ", " ": " ", " ": " ", " ": " ", " ": " ", " ": " ", " ": " ", " ": " ", " ": " ", " ": " ", " ": " ", " ": " ", "　": " ",
  "​": "", "‌": "", "‍": "", "⁠": "", "﻿": "", "‎": "", "‏": "", "‪": "", "‫": "", "‬": "", "‭": "", "‮": "", "⁦": "", "⁧": "", "⁨": "", "⁩": "",
  "‘": "'", "’": "'", "‚": "'", "‛": "'", "′": "'",
  "“": "\"", "”": "\"", "„": "\"", "‟": "\"", "″": "\"",
  "‐": "-", "‑": "-", "‒": "-", "–": "-", "—": "-", "―": "-", "−": "-",
  "…": "...",
  "•": "*", "·": "*", "◦": "*", "‣": "*", "⁃": "*", "∙": "*", "・": "*",
  "×": "x", "÷": "/",
  "←": "<-", "→": "->",
  "™": "(tm)", "©": "(c)", "®": "(r)",
  "°": "", "℃": "C", "℉": "F",
  "、": ",", "。": ".",
};

const asciiLigatureMap: Record<string, string> = {
  "ß": "ss", "ẞ": "SS", "æ": "ae", "Æ": "AE", "œ": "oe", "Œ": "OE",
  "ø": "o", "Ø": "O", "đ": "d", "Đ": "D", "ł": "l", "Ł": "L",
  "ð": "d", "Ð": "D", "þ": "th", "Þ": "Th", "ı": "i",
};

export function asciiForEInk(text: string): string {
  if (/^[\x20-\x7E]*$/.test(text)) return text;
  let output = "";
  for (const character of text) {
    const value = character.codePointAt(0) ?? 0;
    if (value >= 0x20 && value <= 0x7e) {
      output += character;
    } else if (Object.hasOwn(asciiMap, character)) {
      output += asciiMap[character];
    } else if (value >= 0xff01 && value <= 0xff5e) {
      output += String.fromCodePoint(value - 0xfee0);
    } else if (Object.hasOwn(asciiLigatureMap, character)) {
      output += asciiLigatureMap[character];
    } else {
      output += [...character.normalize("NFD")]
        .filter((decomposed) => /^[\x20-\x7E]$/.test(decomposed))
        .join("");
    }
  }
  return output;
}

function wordCount(text: string): number {
  return text.trim() ? text.trim().split(/\s+/).length : 0;
}

function wordLimitFor(
  character: CharacterDefinition | undefined,
  writingMode: WritingMode | undefined,
): number {
  if (typeof character?.wordLimits === "number") return character.wordLimits;
  if (writingMode === "signatureQuote") {
    return character?.wordLimits?.secondaryMode ?? character?.wordLimits?.default ?? 20;
  }
  return character?.wordLimits?.primaryMode
    ?? character?.wordLimits?.default
    ?? (character?.id === "joy" ? 25 : 20);
}

export function validateOutput(compiled: CompiledPrompt, output: string): ValidationItem[] {
  const trimmed = output.trim();
  const containsCJK = /[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]/u.test(output);
  if (compiled.scenarioId === "translation") {
    return [{
      id: "chinese",
      labelZh: "中文输出",
      labelEn: "Chinese output",
      passed: /[\u3400-\u9fff]/u.test(output),
      detail: "CJK scan",
    }];
  }
  if (compiled.scenarioId === "eventClassification") {
    const source = compiled.sanitizedInputs.events;
    const values = trimmed.split(",").map((value) => value.trim()).filter(Boolean);
    const formatPassed = values.length > 0 && values.every((value) => /^[1-6]$/.test(value));
    const expected = Array.isArray(source) ? source.length : stringify(source ?? "").split(/\n|;/).filter(Boolean).length;
    return [
      { id: "format", labelZh: "分类格式", labelEn: "Category format", passed: formatPassed, detail: trimmed || "empty" },
      { id: "count", labelZh: "分类数量", labelEn: "Category count", passed: formatPassed && values.length === expected, detail: `${formatPassed ? values.length : -1} / ${expected}` },
    ];
  }
  if (["eventSupportText", "taskLibraryPhaseText"].includes(compiled.scenarioId)) {
    const { lines, expectedCount, formatPassed } = parseEventSupportLines(compiled, output);
    const numberingPassed = formatPassed && lines.length === expectedCount
      && lines.every((line, index) => line.index === index + 1);
    const maxBytes = outputMaxBytes(compiled);
    const encoder = new TextEncoder();
    const byteDetails = lines.map(({ index, text }) => `${index}: ${encoder.encode(text).length} / ${maxBytes} B`);
    const unsafeASCII = lines.filter(({ text }) => asciiForEInk(text) !== text).map(({ index }) => index);
    // One sentence, and NOT wrapped in quote marks: support text is the App speaking plainly, so
    // `"Sentence."` means the model quoted itself. Inner apostrophes stay legal ("Bet you can't
    // clear this...") — only the first and last characters are checked. Mirrors Swift
    // EventSupportTextService.isExactlyOneCompleteSentence; Studio must not pass what the App rejects.
    const invalidSentences = lines
      .filter(({ text }) => !/^[^.!?]*[.!?]+$/.test(text) || /^["']|["']$/.test(text))
      .map(({ index }) => index);
    const unusableLines = lines.filter(({ text }) => {
      const sanitized = asciiForEInk(text).trim();
      return /^\[error\]/i.test(sanitized) || !/[A-Za-z0-9]/.test(sanitized);
    }).map(({ index }) => index);
    return [
      { id: "numbering", labelZh: "编号完整", labelEn: "Complete numbering", passed: numberingPassed, detail: lines.map(({ index }) => index).join(", ") || "empty" },
      { id: "count", labelZh: "输出数量", labelEn: "Output count", passed: lines.length === expectedCount, detail: `${lines.length} / ${expectedCount}` },
      { id: "english", labelZh: "仅英文", labelEn: "English only", passed: lines.every(({ text }) => !/[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]/u.test(text)), detail: "CJK scan per line" },
      { id: "punctuation", labelZh: "逐条结尾标点", labelEn: "End punctuation per line", passed: lines.every(({ text }) => /[.!?…][\"']?$/.test(text)), detail: "per-line scan" },
      { id: "sentence", labelZh: "逐条一句话", labelEn: "One sentence per line", passed: invalidSentences.length === 0, detail: invalidSentences.length ? `invalid: ${invalidSentences.join(", ")}` : "one sentence each" },
      { id: "usable", labelZh: "逐条可用文案", labelEn: "Usable text per line", passed: unusableLines.length === 0, detail: unusableLines.length ? `invalid: ${unusableLines.join(", ")}` : "readable" },
      { id: "bytes", labelZh: `逐条 ${maxBytes} 字节`, labelEn: `${maxBytes} bytes per line`, passed: lines.every(({ text }) => encoder.encode(text).length <= maxBytes), detail: byteDetails.join("; ") || "no parsed lines" },
      { id: "ascii", labelZh: "逐条硬件 ASCII", labelEn: "Hardware ASCII per line", passed: unsafeASCII.length === 0, detail: unsafeASCII.length ? `transformed: ${unsafeASCII.join(", ")}` : "wire-safe" },
    ];
  }

  const character = compiled.characterId
    ? promptSpec.characters.find((item) => item.id === compiled.characterId)
    : undefined;
  const wordLimit = wordLimitFor(character, compiled.writingMode);
  const bytes = new TextEncoder().encode(output).length;
  const maxBytes = outputMaxBytes(compiled);
  const checks: ValidationItem[] = [];
  const addEnglish = () => checks.push({ id: "english", labelZh: "仅英文", labelEn: "English only", passed: !containsCJK, detail: "CJK scan" });
  const expectedApprovedQuote = compiled.writingMode === "signatureQuote" && compiled.approvedQuote
    ? `"${compiled.approvedQuote.text}" - ${compiled.approvedQuote.source}`
    : undefined;
  const addPunctuation = () => checks.push({
    id: "punctuation",
    labelZh: "结尾标点",
    labelEn: "End punctuation",
    passed: expectedApprovedQuote ? trimmed === expectedApprovedQuote : /[.!?…][\"']?$/.test(trimmed),
    detail: expectedApprovedQuote ? "approved quote attribution" : (trimmed.slice(-1) || "empty"),
  });
  const addHardware = () => {
    const asciiOutput = asciiForEInk(output);
    checks.push(
      { id: "bytes", labelZh: `${maxBytes} 字节`, labelEn: `${maxBytes} bytes`, passed: bytes <= maxBytes, detail: `${bytes} / ${maxBytes} B` },
      { id: "ascii", labelZh: "硬件 ASCII", labelEn: "Hardware ASCII", passed: asciiOutput === output, detail: asciiOutput === output ? "wire-safe" : "transformed" },
    );
  };

  if (compiled.scenarioId === "haiku") {
    addEnglish();
    const lineCount = output.split(/\r?\n/).filter((line) => line.trim()).length;
    checks.push({ id: "lines", labelZh: "三行俳句", labelEn: "Three lines", passed: lineCount === 3, detail: `${lineCount} / 3` });
    return checks;
  }
  if (compiled.scenarioId === "screensaver") {
    addEnglish();
    checks.push(
      { id: "line", labelZh: "单行", labelEn: "One line", passed: !/[\r\n]/.test(output), detail: /[\r\n]/.test(output) ? "multiple lines" : "one line" },
      { id: "characters", labelZh: "60 字符", labelEn: "60 characters", passed: [...output].length < 60, detail: `${[...output].length} / 60` },
    );
    addHardware();
    return checks;
  }
  if (compiled.scenarioId === "taskOverview") {
    checks.push({ id: "line", labelZh: "单行", labelEn: "One line", passed: !/[\r\n]/.test(output), detail: /[\r\n]/.test(output) ? "multiple lines" : "one line" });
    addHardware();
    return checks;
  }

  addEnglish();
  addPunctuation();
  if (character) {
    checks.push({ id: "words", labelZh: "词数限制", labelEn: "Word budget", passed: wordCount(output) <= wordLimit, detail: `${wordCount(output)} / ${wordLimit}` });
  }
  if (compiled.writingMode === "signatureQuote" && compiled.approvedQuote) {
    // Wire-safe ASCII, matching Swift CompanionWritingSelection.deterministicOutput:
    // "text" - source  (plain hyphen-minus, no trailing period).
    const expected = expectedApprovedQuote!;
    checks.push({
      id: "approvedQuote",
      labelZh: "指定金句与出处",
      labelEn: "Approved quote and source",
      passed: trimmed === expected,
      detail: expected,
    });
  }
  addHardware();

  if (compiled.scenarioId === "settlementReview") {
    const deadlines = compiled.sanitizedInputs.deadlineTitles;
    if (Array.isArray(deadlines) && deadlines.length) {
      checks.push({
        id: "deadline",
        labelZh: "提及死线",
        labelEn: "Deadline mention",
        passed: deadlines.some((title) => output.toLowerCase().includes(title.toLowerCase())),
        detail: deadlines.join(", "),
      });
    }
    const focusMinutes = Number(compiled.sanitizedInputs.focusMinutes ?? 0);
    if (focusMinutes > 120) {
      const hours = Math.floor(focusMinutes / 60);
      const minutes = focusMinutes % 60;
      const focusLabel = `${hours}h${minutes > 0 ? ` ${minutes}m` : ""}`;
      checks.push({
        id: "focus",
        labelZh: "提及专注时长",
        labelEn: "Focus duration",
        passed: output.toLowerCase().includes(focusLabel.toLowerCase()),
        detail: focusLabel,
      });
    }
  }
  return checks;
}
