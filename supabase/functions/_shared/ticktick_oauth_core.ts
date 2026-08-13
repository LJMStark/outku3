export type TickTickRegion = "international";

export type ProviderConfiguration = {
  region: TickTickRegion;
  clientId: string;
  clientSecret: string;
  authorizationEndpoint: string;
  tokenEndpoint: string;
  apiBaseURL: string;
  redirectURI: string;
  scope: "tasks:read";
};

export type EncryptedToken = {
  ciphertext: string;
  iv: string;
  keyVersion: number;
};

const BASE64URL_32_BYTES = /^[A-Za-z0-9_-]{43}$/;

export function providerConfiguration(
  region: string,
  env: Record<string, string | undefined>,
): ProviderConfiguration {
  if (region !== "international") {
    throw new Error("unsupported_region");
  }
  const clientId = required(env.TICKTICK_CLIENT_ID, "missing_client_id");
  const clientSecret = required(env.TICKTICK_CLIENT_SECRET, "missing_client_secret");
  const callbackBaseURL = required(env.TICKTICK_CALLBACK_BASE_URL, "missing_callback_base_url");
  const callback = new URL("/functions/v1/ticktick-oauth-callback/international", callbackBaseURL);
  if (callback.protocol !== "https:") throw new Error("invalid_callback_url");

  return {
    region: "international",
    clientId,
    clientSecret,
    authorizationEndpoint: "https://ticktick.com/oauth/authorize",
    tokenEndpoint: "https://ticktick.com/oauth/token",
    apiBaseURL: "https://api.ticktick.com/open/v1",
    redirectURI: callback.toString(),
    scope: "tasks:read",
  };
}

export function buildAuthorizationURL(config: ProviderConfiguration, state: string): URL {
  assertSecret(state, "invalid_state");
  const url = new URL(config.authorizationEndpoint);
  url.searchParams.set("scope", config.scope);
  url.searchParams.set("client_id", config.clientId);
  url.searchParams.set("state", state);
  url.searchParams.set("redirect_uri", config.redirectURI);
  url.searchParams.set("response_type", "code");
  return url;
}

export function buildReturnURL(
  baseURL: string,
  attemptID: string,
  status: "ready" | "failed",
  reason?: "denied" | "expired" | "server_error",
): URL {
  const url = new URL("/oauth/ticktick-return", baseURL);
  if (url.protocol !== "https:") throw new Error("invalid_return_url");
  url.searchParams.set("attempt_id", attemptID);
  url.searchParams.set("status", status);
  if (status === "failed" && reason) url.searchParams.set("reason", reason);
  return url;
}

export function uniqueQueryParameter(url: URL, name: string, maxLength: number): string | null {
  const values = url.searchParams.getAll(name);
  if (values.length !== 1) return null;
  const value = values[0];
  if (!value || value.length > maxLength) return null;
  return value;
}

export function assertSecret(value: string, errorCode = "invalid_secret"): void {
  if (!BASE64URL_32_BYTES.test(value)) throw new Error(errorCode);
}

export function randomSecret(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return base64URLEncode(bytes);
}

export async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export async function encryptToken(
  token: string,
  keyBase64URL: string,
  keyVersion: number,
  aad: string,
): Promise<EncryptedToken> {
  const keyBytes = base64URLDecode(keyBase64URL);
  if (keyBytes.byteLength !== 32) throw new Error("invalid_encryption_key");
  const key = await crypto.subtle.importKey("raw", toArrayBuffer(keyBytes), "AES-GCM", false, ["encrypt"]);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encrypted = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv, additionalData: new TextEncoder().encode(aad) },
    key,
    new TextEncoder().encode(token),
  );
  return {
    ciphertext: base64URLEncode(new Uint8Array(encrypted)),
    iv: base64URLEncode(iv),
    keyVersion,
  };
}

export async function decryptToken(
  encrypted: EncryptedToken,
  keyBase64URL: string,
  aad: string,
): Promise<string> {
  const keyBytes = base64URLDecode(keyBase64URL);
  if (keyBytes.byteLength !== 32) throw new Error("invalid_encryption_key");
  const key = await crypto.subtle.importKey("raw", toArrayBuffer(keyBytes), "AES-GCM", false, ["decrypt"]);
  const plaintext = await crypto.subtle.decrypt(
    {
      name: "AES-GCM",
      iv: toArrayBuffer(base64URLDecode(encrypted.iv)),
      additionalData: new TextEncoder().encode(aad),
    },
    key,
    toArrayBuffer(base64URLDecode(encrypted.ciphertext)),
  );
  return new TextDecoder().decode(plaintext);
}

export function tokenAAD(
  attemptID: string,
  userID: string,
  region: string,
  keyVersion: number,
): string {
  return `${attemptID}:${userID}:${region}:${keyVersion}`;
}

function required(value: string | undefined, errorCode: string): string {
  if (!value?.trim()) throw new Error(errorCode);
  return value.trim();
}

function base64URLEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function base64URLDecode(value: string): Uint8Array {
  const padded = value.replaceAll("-", "+").replaceAll("_", "/") + "===".slice((value.length + 3) % 4);
  const binary = atob(padded);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
}
