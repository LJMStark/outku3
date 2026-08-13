import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

import {
  assertSecret,
  buildAuthorizationURL,
  decryptToken,
  providerConfiguration,
  randomSecret,
  sha256,
  tokenAAD,
} from "../_shared/ticktick_oauth_core.ts";
import {
  authenticatedUser,
  isUUID,
  json,
  readSmallJSON,
  requireExactKeys,
  requiredEnvironment,
  serviceClient,
} from "../_shared/ticktick_edge.ts";

serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  try {
    const user = await authenticatedUser(req);
    if (!user) return json({ error: "unauthorized" }, 401);
    const body = await readSmallJSON(req);
    const action = typeof body.action === "string" ? body.action : "";

    switch (action) {
      case "start":
        return await start(user.id, body);
      case "claim":
        return await claim(user.id, body);
      case "ack":
        return await acknowledge(user.id, body);
      case "cancel":
        return await cancel(user.id, body);
      case "disconnect":
        return await disconnect(user.id, body);
      default:
        return json({ error: "unknown_action" }, 400);
    }
  } catch (error) {
    const code = error instanceof Error ? error.message : "request_failed";
    if (code === "request_too_large") return json({ error: code }, 413);
    if ([
      "invalid_json",
      "missing_parameter",
      "unexpected_parameter",
      "invalid_claim_secret",
      "unsupported_region",
    ].includes(code)) {
      return json({ error: code }, 400);
    }
    return json({ error: "server_error" }, 500);
  }
});

async function start(userID: string, body: Record<string, unknown>): Promise<Response> {
  requireExactKeys(body, ["region"]);
  const region = body.region as string;
  const config = providerConfiguration(region, environment());
  const state = randomSecret();
  const claimSecret = randomSecret();
  const database = serviceClient();
  const { data, error } = await database.rpc("start_ticktick_oauth_attempt", {
    p_user_id: userID,
    p_region: region,
    p_state_hash: await sha256(state),
    p_claim_secret_hash: await sha256(claimSecret),
  });
  if (error) {
    if (error.message?.includes("rate_limited")) return json({ error: "rate_limited" }, 429);
    throw new Error("start_failed");
  }
  const row = data?.[0];
  if (!row?.attempt_id || !row?.attempt_expires_at) throw new Error("start_failed");
  return json({
    attempt_id: row.attempt_id,
    claim_secret: claimSecret,
    authorization_url: buildAuthorizationURL(config, state).toString(),
    expires_at: row.attempt_expires_at,
  });
}

async function claim(userID: string, body: Record<string, unknown>): Promise<Response> {
  requireExactKeys(body, ["attempt_id", "claim_secret"]);
  const attemptID = body.attempt_id as string;
  const claimSecret = body.claim_secret as string;
  if (!isUUID(attemptID)) return json({ error: "invalid_attempt" }, 400);
  assertSecret(claimSecret, "invalid_claim_secret");

  const database = serviceClient();
  const { data, error } = await database.rpc("claim_ticktick_oauth_token", {
    p_user_id: userID,
    p_attempt_id: attemptID,
    p_claim_secret_hash: await sha256(claimSecret),
  });
  if (error) throw new Error("claim_failed");
  const row = data?.[0];
  // Deliberately avoid distinguishing another user's transaction from a transaction that is
  // still pending. Both responses reveal no ownership information.
  if (!row) return json({ status: "pending" }, 202);

  const keyVersion = Number(row.token_key_version);
  const key = encryptionKey(keyVersion);
  const accessToken = await decryptToken(
    {
      ciphertext: row.token_ciphertext,
      iv: row.token_iv,
      keyVersion,
    },
    key,
    tokenAAD(attemptID, userID, row.attempt_region, keyVersion),
  );
  return json({
    delivery_id: row.delivery_id,
    connection_id: row.connection_id,
    region: row.attempt_region,
    access_token: accessToken,
    scope: row.granted_scope ?? null,
    expires_at: row.token_expires_at ?? null,
  });
}

async function acknowledge(userID: string, body: Record<string, unknown>): Promise<Response> {
  requireExactKeys(body, ["attempt_id", "claim_secret", "delivery_id"]);
  const attemptID = body.attempt_id as string;
  const claimSecret = body.claim_secret as string;
  const deliveryID = body.delivery_id as string;
  if (!isUUID(attemptID) || !isUUID(deliveryID)) return json({ error: "invalid_delivery" }, 400);
  assertSecret(claimSecret, "invalid_claim_secret");

  const database = serviceClient();
  const { data, error } = await database.rpc("ack_ticktick_oauth_token", {
    p_user_id: userID,
    p_attempt_id: attemptID,
    p_claim_secret_hash: await sha256(claimSecret),
    p_delivery_id: deliveryID,
  });
  if (error) throw new Error("ack_failed");
  if (data !== true) return json({ error: "delivery_conflict" }, 409);
  return json({}, 204);
}

async function disconnect(userID: string, body: Record<string, unknown>): Promise<Response> {
  requireExactKeys(body, ["connection_id"]);
  const connectionID = body.connection_id as string;
  if (!isUUID(connectionID)) return json({ error: "invalid_connection" }, 400);
  const database = serviceClient();
  const { data, error } = await database.rpc("disconnect_ticktick_connection", {
    p_user_id: userID,
    p_connection_id: connectionID,
  });
  if (error) throw new Error("disconnect_failed");
  if (data !== true) return json({ error: "not_found" }, 404);
  return json({}, 204);
}

async function cancel(userID: string, body: Record<string, unknown>): Promise<Response> {
  requireExactKeys(body, ["attempt_id", "claim_secret"]);
  const attemptID = body.attempt_id as string;
  const claimSecret = body.claim_secret as string;
  if (!isUUID(attemptID)) return json({ error: "invalid_attempt" }, 400);
  assertSecret(claimSecret, "invalid_claim_secret");
  const database = serviceClient();
  const { data, error } = await database.rpc("cancel_ticktick_oauth_attempt", {
    p_user_id: userID,
    p_attempt_id: attemptID,
    p_claim_secret_hash: await sha256(claimSecret),
  });
  if (error) throw new Error("cancel_failed");
  if (data !== true) return json({ error: "authorization_conflict" }, 409);
  return json({}, 204);
}

function environment(): Record<string, string | undefined> {
  return {
    TICKTICK_CLIENT_ID: Deno.env.get("TICKTICK_CLIENT_ID"),
    TICKTICK_CLIENT_SECRET: Deno.env.get("TICKTICK_CLIENT_SECRET"),
    TICKTICK_CALLBACK_BASE_URL: Deno.env.get("TICKTICK_CALLBACK_BASE_URL"),
  };
}

function encryptionKey(version: number): string {
  const configuredVersion = Number(requiredEnvironment("TICKTICK_TOKEN_KEY_VERSION"));
  if (!Number.isInteger(version) || version < 1 || version > configuredVersion) {
    throw new Error("unknown_key_version");
  }
  return requiredEnvironment(`TICKTICK_TOKEN_ENCRYPTION_KEY_V${version}`);
}
