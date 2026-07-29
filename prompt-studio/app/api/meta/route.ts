import promptSpecSource from "@/lib/prompt-spec.json";
import promptSpecRaw from "@/lib/prompt-spec.json?raw";

export const dynamic = "force-dynamic";

async function sourceHash(): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(promptSpecRaw));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export async function GET() {
  return Response.json({
    version: promptSpecSource.version,
    schemaVersion: promptSpecSource.schemaVersion,
    contentHash: await sourceHash(),
    // secondaryModeStyle tells a client whether Mode B is quote-based (offer the approved-quote
    // picker) or generative (no picker — the model writes the line). joy is generative, so its
    // approvedQuotes bank is intentionally empty and quoteIndex does not apply.
    characters: promptSpecSource.characters.map(({ id, displayName, displayNameZh, virtue, wordLimits, approvedQuotes, secondaryModeStyle }) => ({ id, displayName, displayNameZh, virtue, wordLimits, approvedQuotes, secondaryModeStyle })),
    writingModes: promptSpecSource.writingModes,
    personaScenes: promptSpecSource.personaScenes.map(({ id, group, titleZh, titleEn, status, variables, parameters, outputMaxBytes }) => ({ id, group, titleZh, titleEn, status, variables, parameters, outputMaxBytes })),
    toolPrompts: promptSpecSource.toolPrompts.map(({ id, group, titleZh, titleEn, status, variables, parameters, outputMaxBytes, outputRules }) => ({ id, group, titleZh, titleEn, status, variables, parameters, outputMaxBytes, outputRules })),
    nonActivePaths: promptSpecSource.nonActivePaths,
    // Mode B moment -> acceptable tones. Exposed so a reviewer can see which approved lines are
    // eligible for which moment; the filtering itself runs App-side (quote Mode B skips the LLM).
    modeBMomentTones: promptSpecSource.modeBMomentTones,
    model: {
      provider: promptSpecSource.model.provider,
      primaryModel: `env:${promptSpecSource.model.primaryModelEnvironmentKey}`,
      fallbackModel: promptSpecSource.model.fallbackModel,
      reasoning: promptSpecSource.model.reasoning,
      reasoningTokenHeadroom: promptSpecSource.model.reasoningTokenHeadroom,
      requireParameters: promptSpecSource.model.requireParameters,
      requestTimeoutSeconds: promptSpecSource.model.requestTimeoutSeconds,
    },
    limits: promptSpecSource.limits,
  }, { headers: { "Cache-Control": "public, max-age=300", "X-Robots-Tag": "noindex" } });
}
