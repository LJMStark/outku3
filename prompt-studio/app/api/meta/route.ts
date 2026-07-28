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
    characters: promptSpecSource.characters.map(({ id, displayName, displayNameZh, virtue, wordLimits }) => ({ id, displayName, displayNameZh, virtue, wordLimits })),
    personaScenes: promptSpecSource.personaScenes.map(({ id, group, titleZh, titleEn, status, variables, parameters, outputMaxBytes }) => ({ id, group, titleZh, titleEn, status, variables, parameters, outputMaxBytes })),
    toolPrompts: promptSpecSource.toolPrompts.map(({ id, group, titleZh, titleEn, status, variables, parameters, outputMaxBytes, outputRules }) => ({ id, group, titleZh, titleEn, status, variables, parameters, outputMaxBytes, outputRules })),
    nonActivePaths: promptSpecSource.nonActivePaths,
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
