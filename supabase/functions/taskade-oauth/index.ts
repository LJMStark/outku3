import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const TASKADE_TOKEN_URL = "https://www.taskade.com/oauth2/token";

serve(async (req) => {
  // 不带 CORS 头：本函数只服务原生 App（TaskadeAuthService 直连），浏览器跨域调用故意
  // 不支持——之前的 Allow-Origin: * 等于把 client_secret 兑换代理开放给任意网页。
  if (req.method === "OPTIONS") {
    return new Response("ok");
  }

  // 调用方必须持有本项目 anon key（App 侧一直在发 Bearer anonKey）。不校验用户 JWT：
  // 连接 Taskade 不要求登录（Skip 用户无 Supabase 会话），强上用户级校验会误伤他们。
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!anonKey) {
    return json({ error: "server_misconfigured" }, 500);
  }
  const bearer = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (bearer !== anonKey) {
    return json({ error: "unauthorized" }, 401);
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
    headers: { "Content-Type": "application/json" },
  });
}
