import { promptSpec, type CompileRequest } from "./prompt-engine";

const maxBodyBytes = 80_000;

export async function parseCompileRequest(request: Request): Promise<CompileRequest> {
  const contentType = request.headers.get("content-type")?.split(";", 1)[0]?.trim().toLowerCase();
  if (contentType !== "application/json") throw new Error("JSON_CONTENT_TYPE_REQUIRED");
  const declaredLength = Number(request.headers.get("content-length") ?? 0);
  if (declaredLength > maxBodyBytes) throw new Error("Request body is too large");
  const raw = await request.text();
  if (new TextEncoder().encode(raw).length > maxBodyBytes) throw new Error("Request body is too large");
  let payload: CompileRequest;
  try {
    payload = JSON.parse(raw) as CompileRequest;
  } catch {
    throw new Error("Invalid JSON body");
  }
  if (!payload || typeof payload.scenarioId !== "string" || !payload.scenarioId) throw new Error("scenarioId is required");
  if (payload.characters != null) {
    if (!Array.isArray(payload.characters) || payload.characters.length < 1 || payload.characters.length > 3) throw new Error("Select between one and three characters");
    if (new Set(payload.characters).size !== payload.characters.length) throw new Error("Duplicate characters are not allowed");
    if (payload.characters.some((id) => !promptSpec.characters.some((character) => character.id === id))) throw new Error("Unknown character");
  }
  if (payload.intimacyStage != null && (typeof payload.intimacyStage !== "string" || !promptSpec.intimacyStages.some((stage) => stage.id === payload.intimacyStage))) throw new Error("Unknown intimacy stage");
  if (payload.writingMode != null && !promptSpec.writingModes.some((mode) => mode.id === payload.writingMode)) throw new Error("Unknown writing mode");
  if (payload.quoteIndex != null && (!Number.isInteger(payload.quoteIndex) || payload.quoteIndex < 0)) throw new Error("Invalid quote index");
  if (payload.quoteIndex != null && payload.writingMode !== "signatureQuote") throw new Error("Invalid quote index for writing mode");
  if (payload.writingMode === "signatureQuote") {
    const selectedCharacters = payload.characters ?? ["joy"];
    if (selectedCharacters.some((id) => {
      const character = promptSpec.characters.find((item) => item.id === id);
      if (!character) return true;
      // Generative secondary mode (joy) writes an original line instead of quoting, so it has an
      // empty approved-quote bank by design — a quote index is meaningless rather than invalid.
      if (character.secondaryModeStyle === "generative") return false;
      return (payload.quoteIndex ?? 0) >= character.approvedQuotes.length;
    })) throw new Error("Invalid quote index");
  }
  if (payload.context == null || typeof payload.context !== "object" || Array.isArray(payload.context)) throw new Error("context must be an object");
  for (const value of Object.values(payload.context)) {
    const validPrimitive = typeof value === "string"
      || typeof value === "boolean"
      || (typeof value === "number" && Number.isFinite(value));
    const validStringArray = Array.isArray(value) && value.every((item) => typeof item === "string");
    if (!validPrimitive && !validStringArray) throw new Error("Invalid prompt context");
  }
  if (payload.overrides != null) {
    if (typeof payload.overrides !== "object" || Array.isArray(payload.overrides)) throw new Error("overrides must be an object");
    const allowedCharacters = new Set(["joy", "silas", "nova"]);
    const allowedFields = new Set(["personaPrompt", "characterPrompt", "intimacyPrompt", "globalRules", "scenePrompt", "systemPrompt", "userPrompt"]);
    for (const [character, values] of Object.entries(payload.overrides)) {
      if (!allowedCharacters.has(character) || values == null || typeof values !== "object" || Array.isArray(values)) throw new Error("Invalid prompt override");
      for (const [field, value] of Object.entries(values)) {
        if (!allowedFields.has(field) || typeof value !== "string" || value.length > 5_000) throw new Error("Invalid prompt override");
      }
    }
  }
  return payload;
}

export function enforceSameOriginRequest(request: Request, requireOrigin = false): void {
  const origin = request.headers.get("origin");
  if (requireOrigin && !origin) throw new Error("CROSS_ORIGIN");
  if (origin && origin !== new URL(request.url).origin) throw new Error("CROSS_ORIGIN");
}

export function apiError(error: unknown): Response {
  const message = error instanceof Error ? error.message : "Unexpected error";
  console.error("Prompt API request failed", error instanceof Error ? error.message : String(error));
  if (message === "RATE_LIMITED") return Response.json({ error: "10-minute run limit reached. Please try again later." }, { status: 429 });
  if (message === "DAILY_LIMITED") return Response.json({ error: "The shared daily model budget has been reached." }, { status: 429 });
  if (message === "CROSS_ORIGIN") return Response.json({ error: "Cross-origin model runs are not allowed." }, { status: 403 });
  if (message === "JSON_CONTENT_TYPE_REQUIRED") return Response.json({ error: "Content-Type must be application/json." }, { status: 415 });
  if (message === "Request body is too large") return Response.json({ error: message }, { status: 413 });
  if (message.includes("not configured")) return Response.json({ error: message }, { status: 503 });
  if (message.includes("required") || message.includes("Unknown") || message.includes("Select between") || message.includes("Duplicate characters") || message.includes("must be an object") || message === "Invalid JSON body" || message === "Invalid prompt context" || message.includes("Invalid prompt override") || message.includes("Invalid quote index")) return Response.json({ error: message }, { status: 400 });
  return Response.json({ error: "The prompt request could not be completed." }, { status: 502 });
}
