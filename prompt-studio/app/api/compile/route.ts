import { apiError, parseCompileRequest } from "@/lib/api";
import { compilePrompts } from "@/lib/prompt-engine";

export async function POST(request: Request) {
  try {
    const payload = await parseCompileRequest(request);
    return Response.json({ results: compilePrompts(payload) }, { headers: { "Cache-Control": "no-store", "X-Robots-Tag": "noindex" } });
  } catch (error) {
    return apiError(error);
  }
}
