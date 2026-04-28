import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const TASKADE_TOKEN_URL = "https://www.taskade.com/oauth2/token";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS });
  }

  const clientId = Deno.env.get("TASKADE_CLIENT_ID");
  const clientSecret = Deno.env.get("TASKADE_CLIENT_SECRET");
  if (!clientId || !clientSecret) {
    return json({ error: "server_misconfigured" }, 500);
  }

  let body: { action?: string; code?: string; redirect_uri?: string; refresh_token?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const { action } = body;

  if (action === "exchange") {
    const { code, redirect_uri } = body;
    if (!code || !redirect_uri) {
      return json({ error: "missing_params: code and redirect_uri required" }, 400);
    }

    const params = new URLSearchParams({
      grant_type: "authorization_code",
      code,
      client_id: clientId,
      client_secret: clientSecret,
      redirect_uri,
    });

    const upstream = await fetch(TASKADE_TOKEN_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: params.toString(),
    });

    const data = await upstream.json();
    return json(data, upstream.status);
  }

  if (action === "refresh") {
    const { refresh_token } = body;
    if (!refresh_token) {
      return json({ error: "missing_params: refresh_token required" }, 400);
    }

    const params = new URLSearchParams({
      grant_type: "refresh_token",
      refresh_token,
      client_id: clientId,
      client_secret: clientSecret,
    });

    const upstream = await fetch(TASKADE_TOKEN_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: params.toString(),
    });

    const data = await upstream.json();
    return json(data, upstream.status);
  }

  return json({ error: "unknown_action: use 'exchange' or 'refresh'" }, 400);
});

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
