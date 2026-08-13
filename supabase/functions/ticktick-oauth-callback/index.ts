import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

import {
  buildReturnURL,
  encryptToken,
  providerConfiguration,
  sha256,
  tokenAAD,
  uniqueQueryParameter,
} from "../_shared/ticktick_oauth_core.ts";
import {
  json,
  redirect,
  requiredEnvironment,
  serviceClient,
} from "../_shared/ticktick_edge.ts";

serve(async (req) => {
  if (req.method !== "GET") return json({ error: "method_not_allowed" }, 405);
  if (req.url.length > 4096) return json({ error: "request_too_large" }, 414);

  const url = new URL(req.url);
  const path = url.pathname.split("/").filter(Boolean);
  const region = path.at(-2) === "ticktick-oauth-callback" && path.at(-1) === "international"
    ? "international"
    : "";
  if (!region) return json({ error: "unsupported_region" }, 404);
  if (url.searchParams.getAll("state").length !== 1
      || url.searchParams.getAll("code").length > 1
      || url.searchParams.getAll("error").length > 1) {
    return json({ error: "duplicate_parameter" }, 400);
  }
  const state = uniqueQueryParameter(url, "state", 43);
  if (!state || !/^[A-Za-z0-9_-]{43}$/.test(state)) {
    return json({ error: "invalid_state" }, 400);
  }

  const database = serviceClient();
  const { data, error } = await database.rpc("consume_ticktick_oauth_callback", {
    p_state_hash: await sha256(state),
    p_region: region,
  });
  if (error) return json({ error: "callback_failed" }, 500);
  const attempt = data?.[0];
  if (!attempt) return json({ error: "invalid_or_expired_state" }, 410);

  try {
    const providerError = uniqueQueryParameter(url, "error", 128);
    const code = uniqueQueryParameter(url, "code", 2048);
    if (providerError && code) {
      await failAttempt(database, attempt.attempt_id, "ambiguous_callback");
      return redirect(returnURL(attempt.attempt_id, "failed", "server_error"));
    }
    if (providerError) {
      await failAttempt(database, attempt.attempt_id, "provider_denied");
      return redirect(returnURL(attempt.attempt_id, "failed", "denied"));
    }
    if (!code) {
      await failAttempt(database, attempt.attempt_id, "missing_code");
      return redirect(returnURL(attempt.attempt_id, "failed", "server_error"));
    }

    const config = providerConfiguration(region, environment());
    const token = await exchangeCode(config, code);
    await validateToken(config.apiBaseURL, token.accessToken);

    const keyVersion = Number(requiredEnvironment("TICKTICK_TOKEN_KEY_VERSION"));
    if (!Number.isInteger(keyVersion) || keyVersion < 1 || keyVersion > 32767) {
      throw new Error("invalid_key_version");
    }
    const connectionID = crypto.randomUUID();
    const encrypted = await encryptToken(
      token.accessToken,
      requiredEnvironment(`TICKTICK_TOKEN_ENCRYPTION_KEY_V${keyVersion}`),
      keyVersion,
      tokenAAD(attempt.attempt_id, attempt.owner_user_id, region, keyVersion),
    );
    const { data: finished, error: finishError } = await database.rpc(
      "finish_ticktick_oauth_exchange",
      {
        p_attempt_id: attempt.attempt_id,
        p_connection_id: connectionID,
        p_token_ciphertext: encrypted.ciphertext,
        p_token_iv: encrypted.iv,
        p_token_key_version: encrypted.keyVersion,
        p_granted_scope: token.scope ?? config.scope,
        p_token_expires_at: token.expiresAt,
      },
    );
    if (finishError || finished !== true) throw new Error("finish_failed");
    return redirect(returnURL(attempt.attempt_id, "ready"));
  } catch {
    await failAttempt(database, attempt.attempt_id, "exchange_failed");
    return redirect(returnURL(attempt.attempt_id, "failed", "server_error"));
  }
});

type TokenResult = {
  accessToken: string;
  scope: string | null;
  expiresAt: string | null;
};

async function exchangeCode(
  config: ReturnType<typeof providerConfiguration>,
  code: string,
): Promise<TokenResult> {
  const body = new URLSearchParams({
    grant_type: "authorization_code",
    code,
    scope: config.scope,
    redirect_uri: config.redirectURI,
  });
  const response = await fetch(config.tokenEndpoint, {
    method: "POST",
    redirect: "error",
    signal: AbortSignal.timeout(10_000),
    headers: {
      "Authorization": `Basic ${btoa(`${config.clientId}:${config.clientSecret}`)}`,
      "Content-Type": "application/x-www-form-urlencoded",
      "Accept": "application/json",
    },
    body,
  });
  if (!response.ok) throw new Error("provider_exchange_rejected");
  const payload = await response.json();
  if (!payload || typeof payload.access_token !== "string" || !payload.access_token) {
    throw new Error("invalid_token_response");
  }
  const expiresIn = typeof payload.expires_in === "number" && payload.expires_in > 0
    ? payload.expires_in
    : null;
  return {
    accessToken: payload.access_token,
    scope: typeof payload.scope === "string" ? payload.scope : null,
    expiresAt: expiresIn ? new Date(Date.now() + expiresIn * 1000).toISOString() : null,
  };
}

async function validateToken(apiBaseURL: string, accessToken: string): Promise<void> {
  const url = new URL(`${apiBaseURL}/project`);
  if (url.protocol !== "https:" || url.host !== "api.ticktick.com") throw new Error("invalid_api_host");
  const response = await fetch(url, {
    redirect: "error",
    signal: AbortSignal.timeout(10_000),
    headers: { Authorization: `Bearer ${accessToken}`, Accept: "application/json" },
  });
  if (!response.ok) throw new Error("token_validation_failed");
}

async function failAttempt(database: any, attemptID: string, code: string): Promise<void> {
  await database.rpc("fail_ticktick_oauth_attempt", {
    p_attempt_id: attemptID,
    p_error_code: code,
  });
}

function returnURL(
  attemptID: string,
  status: "ready" | "failed",
  reason?: "denied" | "expired" | "server_error",
): URL {
  return buildReturnURL(requiredEnvironment("TICKTICK_APP_RETURN_BASE_URL"), attemptID, status, reason);
}

function environment(): Record<string, string | undefined> {
  return {
    TICKTICK_CLIENT_ID: Deno.env.get("TICKTICK_CLIENT_ID"),
    TICKTICK_CLIENT_SECRET: Deno.env.get("TICKTICK_CLIENT_SECRET"),
    TICKTICK_CALLBACK_BASE_URL: Deno.env.get("TICKTICK_CALLBACK_BASE_URL"),
  };
}
