import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const NOTION_TOKEN_URL = "https://api.notion.com/v1/oauth/token";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS });
  }

  const clientId = Deno.env.get("NOTION_CLIENT_ID");
  const clientSecret = Deno.env.get("NOTION_CLIENT_SECRET");
  if (!clientId || !clientSecret) {
    return json({ error: "server_misconfigured" }, 500);
  }

  let body: { code?: string; redirect_uri?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const { code, redirect_uri } = body;
  if (!code || !redirect_uri) {
    return json({ error: "missing_params: code and redirect_uri required" }, 400);
  }

  const credentials = btoa(`${clientId}:${clientSecret}`);
  const upstream = await fetch(NOTION_TOKEN_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Basic ${credentials}`,
    },
    body: JSON.stringify({ grant_type: "authorization_code", code, redirect_uri }),
  });

  const data = await upstream.json();
  return json(data, upstream.status);
});

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
