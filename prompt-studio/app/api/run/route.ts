import { apiError, enforceSameOriginRequest, parseCompileRequest } from "@/lib/api";
import { asciiForEInk, compilePrompts, outputMaxBytes, promptSpec, utf8Prefix, utf8Truncate, validateOutput, type CompiledPrompt } from "@/lib/prompt-engine";
import { enforceRunLimit, takeGlobalModelCalls } from "@/lib/rate-limit";
import { getRuntimeEnv } from "@/lib/runtime-env";

type OpenRouterResponse = {
  choices?: Array<{ message?: { content?: string | null } }>;
  usage?: { prompt_tokens?: number; completion_tokens?: number; total_tokens?: number };
};

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
  const maxBytes = outputMaxBytes(compiled);
  const truncatedOutput = utf8Truncate(response.content, maxBytes);
  return {
    ...compiled,
    parameters: { ...compiled.parameters, model: primaryModel },
    rawOutput: response.content,
    truncatedOutput,
    asciiOutput: utf8Prefix(asciiForEInk(truncatedOutput), maxBytes),
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
    const apiKey = runtime.OPENROUTER_API_KEY ?? runtime.OPENAI_API_KEY;
    if (!apiKey) throw new Error("OpenRouter is not configured");
    const fallbackAPIKey = runtime.FALLBACK_API_KEY ?? apiKey;
    const payload = await parseCompileRequest(request);
    const compiled = compilePrompts(payload);
    await enforceRunLimit(request);
    await takeGlobalModelCalls(compiled.length);
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
