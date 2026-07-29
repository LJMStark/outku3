import { apiError, enforceSameOriginRequest, parseCompileRequest } from "@/lib/api";
import { compilePrompts, deviceOutputs, promptSpec, validateOutput, type ApprovedQuote, type CompiledPrompt } from "@/lib/prompt-engine";
import { enforceRunLimit, takeGlobalModelCalls } from "@/lib/rate-limit";
import { getRuntimeEnv } from "@/lib/runtime-env";

type OpenRouterResponse = {
  choices?: Array<{ message?: { content?: string | null } }>;
  usage?: { prompt_tokens?: number; completion_tokens?: number; total_tokens?: number };
};

/// A quote-style Mode B turn is deterministic: the approved line IS the output, so no model call.
/// Everything else — including joy's generative Mode B, which has no approved quote — goes upstream.
/// Typed as a predicate on the negative branch so the caller's `compiled.approvedQuote` access is
/// narrowed by the compiler rather than by assumption.
function isDeterministicQuoteTurn(
  compiled: CompiledPrompt,
): compiled is CompiledPrompt & { approvedQuote: ApprovedQuote } {
  return compiled.writingMode === "signatureQuote" && compiled.approvedQuote != null;
}

function needsModelCall(compiled: CompiledPrompt): boolean {
  return !isDeterministicQuoteTurn(compiled);
}

async function sendPrompt(compiled: CompiledPrompt, model: string, apiKey: string, referer: string, requestSignal: AbortSignal) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), compiled.parameters.requestTimeoutSeconds * 1000);
  const abortFromRequest = () => controller.abort(requestSignal.reason);
  if (requestSignal.aborted) abortFromRequest();
  requestSignal.addEventListener("abort", abortFromRequest, { once: true });
  try {
    const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
        "HTTP-Referer": referer,
        "X-Title": "Kirole Prompt Studio",
      },
      body: JSON.stringify({
        model,
        messages: [
          { role: "system", content: compiled.systemPrompt },
          { role: "user", content: compiled.userPrompt },
        ],
        temperature: compiled.parameters.temperature,
        max_tokens: compiled.parameters.requestMaxTokens,
        reasoning: compiled.parameters.reasoning,
        provider: { require_parameters: compiled.parameters.requireParameters },
      }),
      signal: controller.signal,
    });
    if (!response.ok) throw new Error(`OpenRouter request failed (${response.status})`);
    const payload = await response.json() as OpenRouterResponse;
    const content = payload.choices?.[0]?.message?.content?.trim();
    if (!content) throw new Error("OpenRouter returned an empty response");
    return { content, usage: payload.usage };
  } finally {
    clearTimeout(timeout);
    requestSignal.removeEventListener("abort", abortFromRequest);
  }
}

async function runCompiled(
  compiled: CompiledPrompt,
  primaryAPIKey: string,
  fallbackAPIKey: string,
  primaryModel: string,
  referer: string,
  requestSignal: AbortSignal,
) {
  const startedAt = Date.now();
  if (isDeterministicQuoteTurn(compiled)) {
    // Format must stay identical to Swift `CompanionWritingSelection.deterministicOutput` and to
    // the `approvedQuote` validation check below: `"text" - source` (client 2026-07-28 spec).
    const content = `"${compiled.approvedQuote.text}" - ${compiled.approvedQuote.source}`;
    const outputs = deviceOutputs(compiled, content);
    return {
      ...compiled,
      parameters: { ...compiled.parameters, model: primaryModel },
      rawOutput: content,
      ...outputs,
      validation: validateOutput(compiled, content),
      actualModel: "deterministic/approved-quote",
      fallbackUsed: false,
      durationMs: Date.now() - startedAt,
      usage: undefined,
    };
  }
  let actualModel = primaryModel;
  let fallbackUsed = false;
  let response;
  try {
    response = await sendPrompt(compiled, primaryModel, primaryAPIKey, referer, requestSignal);
  } catch (primaryError) {
    if (requestSignal.aborted) throw primaryError;
    if (primaryModel === promptSpec.model.fallbackModel) throw primaryError;
    await takeGlobalModelCalls(1);
    actualModel = promptSpec.model.fallbackModel;
    fallbackUsed = true;
    response = await sendPrompt(compiled, actualModel, fallbackAPIKey, referer, requestSignal);
  }
  const outputs = deviceOutputs(compiled, response.content);
  return {
    ...compiled,
    parameters: { ...compiled.parameters, model: primaryModel },
    rawOutput: response.content,
    ...outputs,
    validation: validateOutput(compiled, response.content),
    actualModel,
    fallbackUsed,
    durationMs: Date.now() - startedAt,
    usage: response.usage,
  };
}

async function runWithConcurrencyLimit(
  compiled: CompiledPrompt[],
  primaryAPIKey: string,
  fallbackAPIKey: string,
  primaryModel: string,
  referer: string,
  requestSignal: AbortSignal,
) {
  const results: Awaited<ReturnType<typeof runCompiled>>[] = [];
  for (let index = 0; index < compiled.length; index += 2) {
    const batch = compiled.slice(index, index + 2);
    results.push(...await Promise.all(batch.map((item) =>
      runCompiled(item, primaryAPIKey, fallbackAPIKey, primaryModel, referer, requestSignal)
    )));
  }
  return results;
}

export async function POST(request: Request) {
  try {
    enforceSameOriginRequest(request, true);
    const runtime = await getRuntimeEnv();
    const payload = await parseCompileRequest(request);
    const compiled = compilePrompts(payload);
    await enforceRunLimit(request);
    const modelCallCount = compiled.filter(needsModelCall).length;
    const apiKey = runtime.OPENROUTER_API_KEY ?? runtime.OPENAI_API_KEY ?? "";
    if (modelCallCount > 0 && !apiKey) throw new Error("OpenRouter is not configured");
    const fallbackAPIKey = runtime.FALLBACK_API_KEY ?? apiKey;
    if (modelCallCount > 0) await takeGlobalModelCalls(modelCallCount);
    const primaryModel = runtime.OPENAI_MODEL || "openai/gpt-oss-120b";
    const referer = new URL(request.url).origin;
    const results = await runWithConcurrencyLimit(
      compiled,
      apiKey,
      fallbackAPIKey,
      primaryModel,
      referer,
      request.signal,
    );
    return Response.json({ results }, { headers: { "Cache-Control": "no-store", "X-Robots-Tag": "noindex" } });
  } catch (error) {
    return apiError(error);
  }
}
