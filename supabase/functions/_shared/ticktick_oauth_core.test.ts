import assert from "node:assert/strict";
import test from "node:test";

import {
  buildAuthorizationURL,
  buildReturnURL,
  decryptToken,
  encryptToken,
  providerConfiguration,
  randomSecret,
  tokenAAD,
  uniqueQueryParameter,
} from "./ticktick_oauth_core.ts";

const env = {
  TICKTICK_CLIENT_ID: "server-client",
  TICKTICK_CLIENT_SECRET: "server-secret",
  TICKTICK_CALLBACK_BASE_URL: "https://project.example",
};

test("provider endpoints and scope are server-owned and region-bound", () => {
  const config = providerConfiguration("international", env);
  const state = randomSecret();
  const authorization = buildAuthorizationURL(config, state);

  assert.equal(authorization.host, "ticktick.com");
  assert.equal(authorization.searchParams.get("client_id"), "server-client");
  assert.equal(authorization.searchParams.get("scope"), "tasks:read");
  assert.equal(
    authorization.searchParams.get("redirect_uri"),
    "https://project.example/functions/v1/ticktick-oauth-callback/international",
  );
  assert.throws(() => providerConfiguration("china", env), /unsupported_region/);
});

test("return URL contains only opaque result fields", () => {
  const url = buildReturnURL("https://kirole.example", "attempt-id", "failed", "denied");
  assert.deepEqual(
    [...url.searchParams.keys()].sort(),
    ["attempt_id", "reason", "status"],
  );
  assert.equal(url.searchParams.get("reason"), "denied");
});

test("callback rejects duplicate or oversized parameters", () => {
  const duplicate = new URL("https://example.test/callback?state=a&state=b");
  const oversized = new URL(`https://example.test/callback?code=${"x".repeat(2049)}`);
  assert.equal(uniqueQueryParameter(duplicate, "state", 43), null);
  assert.equal(uniqueQueryParameter(oversized, "code", 2048), null);
});

test("AES-GCM ciphertext is bound to transaction AAD", async () => {
  const key = randomSecret();
  const aad = tokenAAD("attempt", "user", "international", 1);
  const encrypted = await encryptToken("access-token", key, 1, aad);

  assert.notEqual(encrypted.ciphertext, "access-token");
  assert.equal(await decryptToken(encrypted, key, aad), "access-token");
  await assert.rejects(
    decryptToken(encrypted, key, tokenAAD("other", "user", "international", 1)),
  );
});
