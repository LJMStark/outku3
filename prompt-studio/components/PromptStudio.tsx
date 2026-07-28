"use client";

import Image from "next/image";
import { ChangeEvent, useEffect, useId, useMemo, useRef, useState } from "react";
import type { ApprovedQuote, CharacterId, CompiledPrompt, PromptContext, PromptOverrides, ValidationItem, WritingMode } from "@/lib/prompt-engine";

type DraftWritingMode = "auto" | WritingMode;

type Spec = {
  version: string;
  globalRules: string[];
  model: { fallbackModel: string; reasoningTokenHeadroom: number };
  writingModes: Array<{ id: WritingMode; displayName: string; displayNameZh: string; weight: number; temperatureOverride: number | null; instructionTemplate: string }>;
  characters: Array<{ id: CharacterId; displayName: string; displayNameZh: string; virtue: string; characterPrompt: string; personaPrompt: string; approvedQuotes: ApprovedQuote[] }>;
  intimacyStages: Array<{ id: string; displayName: string; displayNameZh: string; prompt: string }>;
  personaScenes: Scenario[];
  toolPrompts: Scenario[];
  nonActivePaths: Array<{ id: string; kind: string; titleZh: string; note: string }>;
};

type Scenario = {
  id: string;
  group: "character" | "hardware" | "tool";
  titleZh: string;
  titleEn: string;
  status: string;
  userPromptTemplate?: string;
  userPromptTemplates?: Record<string, string | undefined>;
  systemPromptTemplate?: string;
  variables: string[];
  parameters: { temperature: number; maxTokens: number };
  outputRules?: string[];
};

type Draft = {
  locale: "zh" | "en";
  scenarioId: string;
  characters: CharacterId[];
  editorCharacter: CharacterId;
  intimacyStage: string;
  writingMode: DraftWritingMode;
  context: PromptContext;
  overridesByScenario: Record<string, Partial<Record<CharacterId, PromptOverrides>>>;
};

type RunResult = CompiledPrompt & {
  rawOutput?: string;
  truncatedOutput?: string;
  asciiOutput?: string;
  validation?: ValidationItem[];
  actualModel?: string;
  fallbackUsed?: boolean;
  durationMs?: number;
  usage?: { prompt_tokens?: number; completion_tokens?: number; total_tokens?: number };
};

const storageKey = "kirole-prompt-studio-draft-v1";
const baseContext: PromptContext = {
  petName: "Kirole",
  activeTaskTitle: "完成产品演示",
  eventName: "15:00 · 客户评审",
  topTaskTitles: ["完成产品演示", "回复邮件", "阅读研究报告"],
  tasksCompleted: 3,
  tasksTotal: 6,
  nextAgendaItem: "15:00 · 客户评审",
  eventDigest: "09:30 Product sync; 11:00 Design review; 15:00 Client demo",
  deadlineTitles: ["Client demo"],
  focusMinutes: 135,
  usageDays: 21,
  isPostcard: false,
  profileContext: "A steady companion who values calm progress",
  workContext: "Preparing a product demonstration and closing three tasks",
  notes: "Prepare the final demo deck, verify the device flow, and send the decision log before 4pm.",
  text: "You turned a crowded afternoon into one clear step.",
  events: ["Product sync", "Design review", "Client demo"],
  categoryDefinitions: "1 Work, 2 Personal, 3 Health, 4 Social, 5 Deadline, 6 Other",
  timeContext: " starting their afternoon",
  taskContext: " who has completed 3 tasks today with 3 tasks remaining",
  moodContext: ". Their pet companion is feeling focused",
  sceneContext: ". Their E-ink companion display shows the 'Forest' scene",
  learnText: "Prefer dry, understated humor",
  recentTexts: ["One clear step is enough.", "Protect the quiet hour."],
};

const groupOrder = ["character", "hardware", "tool"] as const;

function defaultDraft(spec: Spec): Draft {
  return {
    locale: "zh",
    scenarioId: spec.personaScenes[0]?.id ?? spec.toolPrompts[0]?.id ?? "",
    characters: ["joy", "silas", "nova"],
    editorCharacter: "joy",
    intimacyStage: "familiar",
    writingMode: "auto",
    context: baseContext,
    overridesByScenario: {},
  };
}

function normalizeOverrides(spec: Spec, input: unknown): Draft["overridesByScenario"] {
  if (!input || typeof input !== "object" || Array.isArray(input)) return {};
  const allowedScenarios = new Set([...spec.personaScenes, ...spec.toolPrompts].map((item) => item.id));
  const allowedFields = new Set<keyof PromptOverrides>(["personaPrompt", "characterPrompt", "intimacyPrompt", "globalRules", "scenePrompt", "systemPrompt", "userPrompt"]);
  return Object.fromEntries(Object.entries(input).flatMap(([scenarioId, byCharacter]) => {
    if (!allowedScenarios.has(scenarioId)) return [];
    if (!byCharacter || typeof byCharacter !== "object" || Array.isArray(byCharacter)) return [];
    const characters = Object.fromEntries(Object.entries(byCharacter).flatMap(([characterId, fields]) => {
      if (!["joy", "silas", "nova"].includes(characterId) || !fields || typeof fields !== "object" || Array.isArray(fields)) return [];
      const safeFields = Object.fromEntries(Object.entries(fields).filter(([field, value]) => allowedFields.has(field as keyof PromptOverrides) && typeof value === "string" && value.length <= 5_000));
      return [[characterId, safeFields]];
    }));
    return [[scenarioId, characters]];
  }));
}

function normalizeContext(input: unknown): PromptContext {
  if (!input || typeof input !== "object" || Array.isArray(input)) return baseContext;
  const candidate = input as Record<string, unknown>;
  return Object.fromEntries(Object.entries(baseContext).map(([key, fallback]) => {
    const value = candidate[key];
    if (Array.isArray(fallback)) {
      return [key, Array.isArray(value)
        ? value.filter((item): item is string => typeof item === "string").slice(0, 20).map((item) => item.slice(0, 2_000))
        : fallback];
    }
    if (typeof fallback === "boolean") return [key, typeof value === "boolean" ? value : fallback];
    if (typeof fallback === "number") return [key, typeof value === "number" && Number.isFinite(value) ? value : fallback];
    return [key, typeof value === "string" ? value.slice(0, 5_000) : fallback];
  }));
}

function normalizeImportedDraft(spec: Spec, input: unknown): Draft {
  const fallback = defaultDraft(spec);
  if (!input || typeof input !== "object" || Array.isArray(input)) return fallback;
  const candidate = input as Partial<Draft>;
  const validCharacters = [...new Set((candidate.characters ?? []).filter((id): id is CharacterId => ["joy", "silas", "nova"].includes(id)))];
  const scenarioExists = [...spec.personaScenes, ...spec.toolPrompts].some((item) => item.id === candidate.scenarioId);
  return {
    locale: candidate.locale === "en" ? "en" : "zh",
    scenarioId: scenarioExists ? candidate.scenarioId! : fallback.scenarioId,
    characters: validCharacters.length ? validCharacters.slice(0, 3) : fallback.characters,
    editorCharacter: ["joy", "silas", "nova"].includes(candidate.editorCharacter ?? "") ? candidate.editorCharacter! : fallback.editorCharacter,
    intimacyStage: spec.intimacyStages.some((item) => item.id === candidate.intimacyStage) ? candidate.intimacyStage! : fallback.intimacyStage,
    writingMode: ["auto", "normal", "signatureQuote"].includes(candidate.writingMode ?? "") ? candidate.writingMode! : fallback.writingMode,
    context: normalizeContext(candidate.context),
    overridesByScenario: normalizeOverrides(spec, candidate.overridesByScenario),
  };
}

function text(locale: Draft["locale"], zh: string, en: string): string {
  return locale === "zh" ? zh : en;
}

function randomInteger(upperBound: number): number {
  if (!Number.isInteger(upperBound) || upperBound <= 0) return 0;
  const range = 2 ** 32;
  const limit = Math.floor(range / upperBound) * upperBound;
  const values = new Uint32Array(1);
  do {
    crypto.getRandomValues(values);
  } while (values[0] >= limit);
  return values[0] % upperBound;
}

function resolveWritingMode(mode: DraftWritingMode): WritingMode {
  if (mode !== "auto") return mode;
  return randomInteger(100) < 20 ? "signatureQuote" : "normal";
}

function activeToolTemplate(scenario: Scenario | undefined, context: PromptContext): [string, string] {
  const templates = scenario?.userPromptTemplates ?? {};
  if (scenario?.id === "screensaver") {
    const key = context.isPostcard ? "postcard" : "resting";
    return [key, templates[key] ?? ""];
  }
  if (scenario?.id === "daySummary") {
    const key = String(context.eventDigest ?? "").trim() ? "events" : "empty";
    return [key, templates[key] ?? ""];
  }
  const key = Object.keys(templates).find((item) => typeof templates[item] === "string") ?? "default";
  return [key, templates[key] ?? ""];
}

export function PromptStudio({ spec }: { spec: Spec }) {
  const [draft, setDraft] = useState<Draft>(() => defaultDraft(spec));
  const [hydrated, setHydrated] = useState(false);
  const [results, setResults] = useState<RunResult[]>([]);
  const [busy, setBusy] = useState<"compile" | "run" | null>(null);
  const [error, setError] = useState("");
  const [storageStatus, setStorageStatus] = useState<"loading" | "saved" | "error">("loading");
  const fileInput = useRef<HTMLInputElement>(null);
  const requestSequence = useRef(0);
  const activeRequest = useRef<AbortController | null>(null);
  const autoCompileTimer = useRef<number | null>(null);
  const lastExplicitDraftSignature = useRef<string | null>(null);
  const scenarios = useMemo(() => [...spec.personaScenes, ...spec.toolPrompts], [spec]);
  const scenario = scenarios.find((item) => item.id === draft.scenarioId) ?? scenarios[0];
  const isPersona = scenario?.group === "character";
  const currentCharacter = spec.characters.find((item) => item.id === draft.editorCharacter) ?? spec.characters[0];
  const currentIntimacy = spec.intimacyStages.find((item) => item.id === draft.intimacyStage) ?? spec.intimacyStages[0];
  const scenarioOverrides = draft.overridesByScenario[draft.scenarioId] ?? {};
  const overrideCharacter = isPersona ? draft.editorCharacter : "joy";
  const currentOverrides = scenarioOverrides[overrideCharacter] ?? {};
  const [toolTemplateKey, toolTemplate] = activeToolTemplate(scenario, draft.context);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      try {
        const saved = localStorage.getItem(storageKey);
        if (saved) setDraft(normalizeImportedDraft(spec, JSON.parse(saved)));
      } catch {
        try {
          localStorage.removeItem(storageKey);
        } catch {
          setStorageStatus("error");
        }
      }
      setHydrated(true);
    }, 0);
    return () => window.clearTimeout(timer);
  }, [spec]);

  useEffect(() => {
    if (!hydrated) return;
    const timer = window.setTimeout(() => {
      try {
        localStorage.setItem(storageKey, JSON.stringify(draft));
        setStorageStatus("saved");
      } catch {
        setStorageStatus("error");
        setError(text(draft.locale, "本机草稿空间不足，请先导出后再重置。", "Local draft storage is full. Export the draft, then reset it."));
      }
    }, 0);
    return () => window.clearTimeout(timer);
  }, [draft, hydrated]);

  useEffect(() => {
    document.documentElement.lang = draft.locale === "zh" ? "zh-CN" : "en";
  }, [draft.locale]);

  useEffect(() => () => activeRequest.current?.abort(), []);

  useEffect(() => {
    if (!hydrated || !scenario || busy) return;
    const draftSignature = JSON.stringify(draft);
    const timer = window.setTimeout(() => {
      autoCompileTimer.current = null;
      const followsExplicitRequest = lastExplicitDraftSignature.current === draftSignature;
      lastExplicitDraftSignature.current = null;
      if (followsExplicitRequest) return;
      void compile(false);
    }, 280);
    autoCompileTimer.current = timer;
    return () => {
      window.clearTimeout(timer);
      if (autoCompileTimer.current === timer) autoCompileTimer.current = null;
    };
    // compile is deliberately driven by the serialized draft.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [hydrated, draft, scenario?.id, busy]);

  async function request(path: string, signal: AbortSignal): Promise<RunResult[]> {
    const writingMode = isPersona ? resolveWritingMode(draft.writingMode) : undefined;
    const quoteCount = isPersona
      ? Math.min(...draft.characters.map((id) => spec.characters.find((item) => item.id === id)?.approvedQuotes.length ?? 0))
      : 0;
    const quoteIndex = writingMode === "signatureQuote" ? randomInteger(quoteCount) : undefined;
    const response = await fetch(path, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      signal,
      body: JSON.stringify({
        scenarioId: draft.scenarioId,
        characters: isPersona ? draft.characters : undefined,
        intimacyStage: draft.intimacyStage,
        writingMode,
        quoteIndex,
        context: draft.context,
        overrides: scenarioOverrides,
      }),
    });
    const payload = await response.json() as { results?: RunResult[]; error?: string };
    if (!response.ok) throw new Error(payload.error ?? `Request failed (${response.status})`);
    return payload.results ?? [];
  }

  async function execute(kind: "compile" | "run", path: string, explicit: boolean) {
    if (autoCompileTimer.current !== null) {
      window.clearTimeout(autoCompileTimer.current);
      autoCompileTimer.current = null;
    }
    if (explicit) lastExplicitDraftSignature.current = JSON.stringify(draft);
    const sequence = ++requestSequence.current;
    activeRequest.current?.abort();
    const controller = new AbortController();
    activeRequest.current = controller;
    if (explicit) setBusy(kind);
    setError("");
    try {
      const nextResults = await request(path, controller.signal);
      if (sequence === requestSequence.current) setResults(nextResults);
    } catch (caught) {
      if (sequence === requestSequence.current && !(caught instanceof DOMException && caught.name === "AbortError")) {
        setError(caught instanceof Error ? caught.message : `${kind} failed`);
      }
    } finally {
      if (sequence === requestSequence.current) {
        activeRequest.current = null;
        if (explicit) setBusy(null);
      }
    }
  }

  async function compile(explicit = true) { await execute("compile", "/api/compile", explicit); }

  async function run() { await execute("run", "/api/run", true); }

  function updateContext(key: string, value: PromptContext[string]) {
    setDraft((valueBefore) => ({ ...valueBefore, context: { ...valueBefore.context, [key]: value } }));
  }

  function updateOverride(key: keyof PromptOverrides, value: string) {
    setDraft((valueBefore) => ({
      ...valueBefore,
      overridesByScenario: {
        ...valueBefore.overridesByScenario,
        [valueBefore.scenarioId]: {
          ...valueBefore.overridesByScenario[valueBefore.scenarioId],
          [isPersona ? valueBefore.editorCharacter : "joy"]: {
            ...valueBefore.overridesByScenario[valueBefore.scenarioId]?.[isPersona ? valueBefore.editorCharacter : "joy"],
            [key]: value,
          },
        },
      },
    }));
  }

  function toggleCharacter(id: CharacterId) {
    setDraft((valueBefore) => {
      const selected = valueBefore.characters.includes(id)
        ? valueBefore.characters.filter((item) => item !== id)
        : [...valueBefore.characters, id].slice(0, 3);
      return { ...valueBefore, characters: selected.length ? selected : [id], editorCharacter: id };
    });
  }

  function exportDraft() {
    const blob = new Blob([JSON.stringify({ promptSpecVersion: spec.version, draft }, null, 2)], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = `kirole-prompt-draft-${new Date().toISOString().slice(0, 10)}.json`;
    anchor.click();
    URL.revokeObjectURL(url);
  }

  async function importDraft(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;
    try {
      if (file.size > 80_000) throw new Error("Draft is too large");
      const parsed = JSON.parse(await file.text()) as { draft?: Draft } | Draft;
      setDraft(normalizeImportedDraft(spec, "draft" in parsed && parsed.draft ? parsed.draft : parsed));
      setError("");
    } catch {
      setError(text(draft.locale, "无法读取这个草稿文件。", "Could not read that draft file."));
    }
    event.target.value = "";
  }

  function resetDraft() {
    if (!window.confirm(text(draft.locale, "清除本机草稿并恢复默认值？", "Clear the local draft and restore defaults?"))) return;
    try {
      localStorage.removeItem(storageKey);
    } catch {
      setStorageStatus("error");
      setError(text(draft.locale, "无法清除本机草稿，请检查浏览器存储权限。", "Could not clear the local draft. Check browser storage permissions."));
    }
    setDraft(defaultDraft(spec));
  }

  const labels: Record<string, [string, string]> = {
    activeTaskTitle: ["当前任务", "Active task"], eventName: ["当前日程", "Current event"], topTaskTitles: ["后续任务", "Tasks ahead"],
    nextAgendaItem: ["下一项日程", "Next agenda item"],
    eventDigest: ["今日日历", "Calendar digest"], deadlineTitles: ["死线项目", "Deadline items"], focusMinutes: ["专注分钟", "Focus minutes"],
    tasksCompleted: ["完成数", "Completed"], tasksTotal: ["任务总数", "Total tasks"], usageDays: ["使用天数", "Usage days"],
    notes: ["任务备注", "Task note"], workContext: ["近期工作", "Recent work"], profileContext: ["角色背景", "Profile context"],
    text: ["待翻译英文", "English to translate"], events: ["待分类事件", "Events to classify"], recentTexts: ["最近说过", "Recent outputs"],
    learnText: ["语气偏好", "Tone hint"], petName: ["称呼", "Companion name"], isPostcard: ["纪念明信片", "Milestone postcard"],
    timeContext: ["俳句时间", "Haiku time"], taskContext: ["俳句任务", "Haiku tasks"], moodContext: ["俳句心情", "Haiku mood"], sceneContext: ["俳句场景", "Haiku scene"],
  };

  return (
    <main className="studio-shell">
      <header className="topbar">
        <div className="brand-block">
          <span className="brand-mark" aria-hidden="true">K</span>
          <div><h1>Kirole Prompt Studio</h1><p>{text(draft.locale, "提示词实验台 · 改动只保存在此浏览器", "Prompt lab · Changes stay in this browser")}</p></div>
        </div>
        <div className="top-actions">
          <span className="version-chip">SPEC {spec.version}</span>
          <button className="quiet-button" onClick={() => setDraft((value) => ({ ...value, locale: value.locale === "zh" ? "en" : "zh" }))}>{draft.locale === "zh" ? "EN" : "中文"}</button>
          <button className="quiet-button" onClick={() => fileInput.current?.click()}>{text(draft.locale, "导入", "Import")}</button>
          <button className="quiet-button" onClick={exportDraft}>{text(draft.locale, "导出", "Export")}</button>
          <button className="quiet-button danger" onClick={resetDraft}>{text(draft.locale, "重置", "Reset")}</button>
          <input ref={fileInput} type="file" accept="application/json" hidden onChange={importDraft} />
        </div>
      </header>

      <div className="workbench">
        <aside className="scenario-rail">
          <div className="rail-heading"><span>01</span><strong>{text(draft.locale, "选择场景", "Choose scene")}</strong></div>
          {groupOrder.map((group) => {
            const groupItems = scenarios.filter((item) => item.group === group);
            if (!groupItems.length) return null;
            const groupLabel = group === "character" ? ["角色文案", "Character copy"] : group === "hardware" ? ["硬件面板", "Hardware panels"] : ["工具 Prompt", "Tool prompts"];
            return <section className="scenario-group" key={group}>
              <h2>{text(draft.locale, groupLabel[0], groupLabel[1])}<span>{String(groupItems.length).padStart(2, "0")}</span></h2>
              {groupItems.map((item) => <button key={item.id} className={`scenario-button ${draft.scenarioId === item.id ? "active" : ""}`} aria-pressed={draft.scenarioId === item.id} onClick={() => setDraft((value) => ({ ...value, scenarioId: item.id }))}>
                <span>{draft.locale === "zh" ? item.titleZh : item.titleEn}</span><small>{item.id}</small>
              </button>)}
            </section>;
          })}
          <details className="inactive-paths"><summary>{text(draft.locale, "非活动路径", "Non-active paths")}</summary>{spec.nonActivePaths.map((item) => <div key={item.id}><strong>{item.titleZh}</strong><p>{item.note}</p></div>)}</details>
        </aside>

        <section className="editor-panel">
          <div className="panel-heading"><div><span>02</span><p>{scenario ? (draft.locale === "zh" ? scenario.titleZh : scenario.titleEn) : ""}</p><h2>{text(draft.locale, "编辑提示词", "Edit prompts")}</h2></div><div className="parameter-strip"><span>T {scenario?.parameters.temperature}</span><span>{scenario?.parameters.maxTokens}+{spec.model.reasoningTokenHeadroom} TOK</span></div></div>

          {isPersona ? <>
            <div className="character-tabs" role="group" aria-label="Characters">
              {spec.characters.map((character) => <button key={character.id} className={`${draft.characters.includes(character.id) ? "selected" : ""} ${draft.editorCharacter === character.id ? "editing" : ""}`} onClick={() => toggleCharacter(character.id)}>
                <Image unoptimized src={`/characters/${character.id}-head.png`} alt="" width={42} height={42} /><span>{character.displayName}<small>{character.displayNameZh} · {character.virtue}</small></span><i>{draft.characters.includes(character.id) ? "ON" : "OFF"}</i>
              </button>)}
            </div>
            <label className="field compact"><span>{text(draft.locale, "关系阶段", "Relationship stage")}</span><select value={draft.intimacyStage} onChange={(event) => setDraft((value) => ({ ...value, intimacyStage: event.target.value }))}>{spec.intimacyStages.map((item) => <option key={item.id} value={item.id}>{draft.locale === "zh" ? item.displayNameZh : item.displayName}</option>)}</select></label>
            <fieldset className="mode-control">
              <legend>{text(draft.locale, "文案模式", "Writing mode")}</legend>
              <div>
                {(["auto", "normal", "signatureQuote"] as DraftWritingMode[]).map((mode) => {
                  const definition = spec.writingModes.find((item) => item.id === mode);
                  const label = mode === "auto"
                    ? text(draft.locale, "自动 80/20", "Auto 80/20")
                    : text(draft.locale, definition?.displayNameZh ?? mode, definition?.displayName ?? mode);
                  return <button type="button" key={mode} className={draft.writingMode === mode ? "active" : ""} aria-pressed={draft.writingMode === mode} onClick={() => setDraft((value) => ({ ...value, writingMode: mode }))}>{label}</button>;
                })}
              </div>
              <small>{text(draft.locale, "自动模式每次编译或运行重新抽取；需要验收金句时可直接强制。", "Auto rerolls on every compile or run; force quote mode for acceptance testing.")}</small>
            </fieldset>
            <details className="quote-bank"><summary>{text(draft.locale, `${currentCharacter.displayName} 已审核金句库`, `${currentCharacter.displayName} approved quote bank`)}</summary>{currentCharacter.approvedQuotes.map((quote) => <p key={`${quote.text}-${quote.source}`}><q>{quote.text}</q><span>{quote.source}</span></p>)}</details>
            <PromptField label={text(draft.locale, `${currentCharacter.displayName} 角色模板`, `${currentCharacter.displayName} persona`)} baseline={currentCharacter.personaPrompt} value={currentOverrides.personaPrompt ?? ""} onChange={(value) => updateOverride("personaPrompt", value)} />
            <PromptField label={text(draft.locale, "外形与身份", "Form and identity")} baseline={currentCharacter.characterPrompt} value={currentOverrides.characterPrompt ?? ""} onChange={(value) => updateOverride("characterPrompt", value)} />
            <PromptField label={text(draft.locale, "亲密度规则", "Intimacy rule")} baseline={currentIntimacy.prompt} value={currentOverrides.intimacyPrompt ?? ""} onChange={(value) => updateOverride("intimacyPrompt", value)} />
            <PromptField label={text(draft.locale, "全局追加规则", "Additional global rules")} baseline={spec.globalRules.join("\n")} value={currentOverrides.globalRules ?? ""} onChange={(value) => updateOverride("globalRules", value)} optional />
            <PromptField label={text(draft.locale, "场景指令覆盖", "Scene instruction override")} baseline={scenario?.userPromptTemplate ?? ""} value={currentOverrides.scenePrompt ?? ""} onChange={(value) => updateOverride("scenePrompt", value)} />
          </> : <>
            <PromptField label="System Prompt" baseline={scenario?.systemPromptTemplate ?? ""} value={currentOverrides.systemPrompt ?? ""} onChange={(value) => updateOverride("systemPrompt", value)} />
            <PromptField label={`User Prompt · ${toolTemplateKey.toUpperCase()}`} baseline={toolTemplate} value={currentOverrides.userPrompt ?? ""} onChange={(value) => updateOverride("userPrompt", value)} />
            <div className="rule-list"><strong>{text(draft.locale, "输出规则", "Output rules")}</strong>{scenario?.outputRules?.map((rule) => <span key={rule}>{rule}</span>)}</div>
          </>}
        </section>

        <aside className="context-panel">
          <div className="panel-heading small"><div><span>03</span><p>MOCK CONTEXT</p><h2>{text(draft.locale, "虚拟传参", "Mock inputs")}</h2></div><span className={`saved-state ${storageStatus}`} aria-live="polite">{storageStatus === "saved" ? text(draft.locale, "已存本机", "Saved locally") : storageStatus === "error" ? text(draft.locale, "未能保存", "Not saved") : text(draft.locale, "保存中…", "Saving…")}</span></div>
          <div className="context-scroll">
            <ContextField id="activeTaskTitle" value={draft.context.activeTaskTitle} labels={labels} locale={draft.locale} onChange={updateContext} />
            <ContextField id="eventName" value={draft.context.eventName} labels={labels} locale={draft.locale} onChange={updateContext} />
            <ContextField id="petName" value={draft.context.petName} labels={labels} locale={draft.locale} onChange={updateContext} />
            <ContextField id="topTaskTitles" value={draft.context.topTaskTitles} labels={labels} locale={draft.locale} onChange={updateContext} multiline />
            <ContextField id="nextAgendaItem" value={draft.context.nextAgendaItem} labels={labels} locale={draft.locale} onChange={updateContext} />
            <ContextField id="eventDigest" value={draft.context.eventDigest} labels={labels} locale={draft.locale} onChange={updateContext} multiline />
            <div className="field-pair"><ContextField id="tasksCompleted" value={draft.context.tasksCompleted} labels={labels} locale={draft.locale} onChange={updateContext} type="number" /><ContextField id="tasksTotal" value={draft.context.tasksTotal} labels={labels} locale={draft.locale} onChange={updateContext} type="number" /></div>
            <div className="field-pair"><ContextField id="focusMinutes" value={draft.context.focusMinutes} labels={labels} locale={draft.locale} onChange={updateContext} type="number" /><ContextField id="usageDays" value={draft.context.usageDays} labels={labels} locale={draft.locale} onChange={updateContext} type="number" /></div>
            <ContextField id="deadlineTitles" value={draft.context.deadlineTitles} labels={labels} locale={draft.locale} onChange={updateContext} multiline />
            <ContextField id="notes" value={draft.context.notes} labels={labels} locale={draft.locale} onChange={updateContext} multiline />
            <ContextField id="workContext" value={draft.context.workContext} labels={labels} locale={draft.locale} onChange={updateContext} multiline />
            <ContextField id="profileContext" value={draft.context.profileContext} labels={labels} locale={draft.locale} onChange={updateContext} multiline />
            <ContextField id="text" value={draft.context.text} labels={labels} locale={draft.locale} onChange={updateContext} multiline />
            <ContextField id="events" value={draft.context.events} labels={labels} locale={draft.locale} onChange={updateContext} multiline />
            <ContextField id="recentTexts" value={draft.context.recentTexts} labels={labels} locale={draft.locale} onChange={updateContext} multiline />
            <ContextField id="learnText" value={draft.context.learnText} labels={labels} locale={draft.locale} onChange={updateContext} />
            <ContextField id="timeContext" value={draft.context.timeContext} labels={labels} locale={draft.locale} onChange={updateContext} />
            <ContextField id="taskContext" value={draft.context.taskContext} labels={labels} locale={draft.locale} onChange={updateContext} multiline />
            <ContextField id="moodContext" value={draft.context.moodContext} labels={labels} locale={draft.locale} onChange={updateContext} />
            <ContextField id="sceneContext" value={draft.context.sceneContext} labels={labels} locale={draft.locale} onChange={updateContext} />
            <label className="toggle-field"><span>{text(draft.locale, "生成 3/7/21 天纪念明信片", "Generate 3/7/21-day postcard")}</span><input type="checkbox" checked={Boolean(draft.context.isPostcard)} onChange={(event) => updateContext("isPostcard", event.target.checked)} /></label>
          </div>
          <div className="run-bar"><button className="compile-button" onClick={() => void compile()} disabled={Boolean(busy)}>{busy === "compile" ? text(draft.locale, "编译中", "Compiling") : text(draft.locale, "编译", "Compile")}</button><button className="run-button" onClick={() => void run()} disabled={Boolean(busy)}>{busy === "run" ? text(draft.locale, "生成中…", "Generating…") : text(draft.locale, "运行模型", "Run model")}</button></div>
          {error && <p className="error-banner" role="alert">{error}</p>}
        </aside>
      </div>

      <section className="results-section">
        <div className="results-heading"><div><span>04</span><h2>{text(draft.locale, "编译结果与设备预览", "Compiled results and device preview")}</h2></div><p>{results.length} {text(draft.locale, "组结果", "result set(s)")}</p></div>
        <div className={`result-grid ${results.length === 1 ? "single" : ""}`}>{results.map((result) => <ResultCard key={result.characterId ?? result.scenarioId} result={result} locale={draft.locale} />)}</div>
      </section>
    </main>
  );
}

function PromptField({ label, baseline, value, onChange, optional = false }: { label: string; baseline: string; value: string; onChange: (value: string) => void; optional?: boolean }) {
  const inputId = useId();
  const effective = optional ? value : value || baseline;
  const changed = optional ? Boolean(value.trim()) : Boolean(value && value !== baseline);
  const delta = optional ? value.length : value.length - baseline.length;
  const diffBaseline = optional ? "" : baseline;
  return <div className="prompt-field"><div className="prompt-field-heading"><label htmlFor={inputId}><strong>{label}</strong></label><i className={changed ? "changed" : ""}>{changed ? `MODIFIED ${delta >= 0 ? "+" : ""}${delta}` : optional ? "OPTIONAL" : "DEFAULT"}</i></div><textarea id={inputId} value={effective} maxLength={5_000} placeholder={optional ? baseline : undefined} onChange={(event) => onChange(!optional && event.target.value === baseline ? "" : event.target.value)} spellCheck={false} /><small>{changed ? "Editing a browser-local override" : optional ? "Leave blank to add nothing" : "Matches versioned PromptSpec"}{changed && <button type="button" onClick={() => onChange("")}>Restore default</button>}</small>{changed && <PromptDiff baseline={diffBaseline} draft={effective} append={optional} />}</div>;
}

function PromptDiff({ baseline, draft, append = false }: { baseline: string; draft: string; append?: boolean }) {
  const before = Array.from(baseline);
  const after = Array.from(draft);
  let prefixLength = 0;
  while (prefixLength < before.length && prefixLength < after.length && before[prefixLength] === after[prefixLength]) prefixLength += 1;
  let suffixLength = 0;
  while (suffixLength < before.length - prefixLength && suffixLength < after.length - prefixLength && before[before.length - suffixLength - 1] === after[after.length - suffixLength - 1]) suffixLength += 1;
  const prefix = before.slice(0, prefixLength).join("");
  const suffix = suffixLength ? before.slice(-suffixLength).join("") : "";
  const removed = before.slice(prefixLength, before.length - suffixLength).join("");
  const added = after.slice(prefixLength, after.length - suffixLength).join("");
  return <details className="prompt-diff"><summary>{append ? "DIFF · APPENDED RULES" : "DIFF · BASELINE / DRAFT"}</summary><div><section><b>BASELINE</b><pre>{prefix}<del>{removed || "∅"}</del>{suffix}</pre></section><section><b>{append ? "APPEND" : "DRAFT"}</b><pre>{prefix}<ins>{added || "∅"}</ins>{suffix}</pre></section></div></details>;
}

function ContextField({ id, value, labels, locale, onChange, multiline = false, type = "text" }: { id: string; value: PromptContext[string]; labels: Record<string, [string, string]>; locale: Draft["locale"]; onChange: (id: string, value: PromptContext[string]) => void; multiline?: boolean; type?: string }) {
  const label = labels[id] ?? [id, id];
  const display = Array.isArray(value) ? value.join("\n") : String(value ?? "");
  const update = (next: string) => onChange(id, Array.isArray(value) ? next.split("\n").map((item) => item.trim()).filter(Boolean) : type === "number" ? Number(next) : next);
  return <label className="field"><span>{locale === "zh" ? label[0] : label[1]}<code>{id}</code></span>{multiline ? <textarea value={display} onChange={(event) => update(event.target.value)} /> : <input type={type} value={display} onChange={(event) => update(event.target.value)} />}</label>;
}

function ResultCard({ result, locale }: { result: RunResult; locale: Draft["locale"] }) {
  const raw = result.rawOutput ?? "";
  const preview = result.asciiOutput ?? "";
  return <article className={`result-card character-${result.characterId ?? "tool"}`}>
    <header>{result.characterId ? <Image unoptimized src={`/characters/${result.characterId}-head.png`} alt="" width={48} height={48} /> : <span className="tool-avatar">T</span>}<div><h3>{result.characterId?.toUpperCase() ?? "TOOL"}</h3><p>{result.actualModel ?? result.parameters.model}</p>{result.writingMode && <em>{result.writingMode === "signatureQuote" ? text(locale, "引用金句", "Signature quote") : text(locale, "正常语气", "Normal voice")}</em>}</div>{result.fallbackUsed && <b>FALLBACK</b>}</header>
    {result.approvedQuote && <div className="selected-quote"><span>{text(locale, "本次指定金句", "Approved quote for this run")}</span><q>{result.approvedQuote.text}</q><small>{result.approvedQuote.source}</small></div>}
    {raw ? <div className="device-preview"><div className="eink-screen">{result.characterId && <Image unoptimized src={`/characters/${result.characterId}-main.png`} alt="" width={112} height={112} />}<div className="bubble"><span>{preview}</span></div></div><div className="wire-lines"><span>RAW</span><code>{raw}</code><span>{result.outputMaxBytes}B</span><code>{result.truncatedOutput}</code><span>ASCII</span><code>{result.asciiOutput}</code></div></div> : <div className="empty-output">{text(locale, "提示词已编译。点击“运行模型”查看生成文案和设备预览。", "Prompt compiled. Run the model to see copy and device preview.")}</div>}
    {result.validation && <div className="validation-grid">{result.validation.map((item) => <span key={item.id} className={item.passed ? "pass" : "fail"}><i>{item.passed ? "PASS" : "FAIL"}</i>{locale === "zh" ? item.labelZh : item.labelEn}<small>{item.detail}</small></span>)}</div>}
    <details><summary>System Prompt <small>{new TextEncoder().encode(result.systemPrompt).length} B</small></summary><pre>{result.systemPrompt}</pre></details>
    <details><summary>User Prompt <small>{new TextEncoder().encode(result.userPrompt).length} B</small></summary><pre>{result.userPrompt}</pre></details>
    <details><summary>{text(locale, "清洗后的传参", "Sanitized inputs")}</summary><pre>{JSON.stringify(result.sanitizedInputs, null, 2)}</pre></details>
    <details className="model-parameters"><summary>MODEL PARAMETERS</summary><dl><div><dt>PRIMARY MODEL</dt><dd>{result.parameters.model}</dd></div><div><dt>FALLBACK MODEL</dt><dd>{result.parameters.fallbackModel}</dd></div><div><dt>REASONING</dt><dd>{result.parameters.reasoning.effort} · exclude {String(result.parameters.reasoning.exclude)}</dd></div><div><dt>REQUIRE PARAMS</dt><dd>{String(result.parameters.requireParameters)}</dd></div><div><dt>TIMEOUT</dt><dd>{result.parameters.requestTimeoutSeconds}s</dd></div></dl></details>
    <footer><span>T {result.parameters.temperature}</span><span>{result.parameters.contentMaxTokens}+{result.parameters.requestMaxTokens - result.parameters.contentMaxTokens} TOK</span>{result.durationMs != null && <span>{result.durationMs} MS</span>}{result.usage?.total_tokens != null && <span>{result.usage.total_tokens} USED</span>}</footer>
  </article>;
}
