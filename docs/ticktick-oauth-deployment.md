# TickTick OAuth deployment

This integration uses a server-side authorization-code exchange because TickTick requires a
provider `client_secret` and does not document PKCE for native apps. The server chooses the public
client ID and all provider endpoints; the App never receives the authorization code or contains
the provider secret.

## Security boundary

- `ticktick-oauth` requires a valid Kirole Supabase user JWT for `start`, `claim`, `ack`, and
  `disconnect`. The public anon key is sent only as the Supabase API key; it is not user identity.
- `ticktick-oauth-callback` is public because TickTick cannot supply a Kirole JWT. It accepts one
  32-byte state value, consumes it once in PostgreSQL, and uses fixed server-side provider values.
- The access token is encrypted with AES-256-GCM and bound to the attempt, user, region, and key
  version. It is retained only for the ten-minute delivery window.
- The App first persists the delivery in a ThisDeviceOnly Keychain item. It then sends `ack`; the
  server activates the connection and clears the token ciphertext.
- The browser handoff URL contains only an opaque attempt ID and a fixed result code. It never
  contains a provider code, state, claim secret, or token.
- Initial scope is `tasks:read`. TickTick write access remains disabled.

## Deployment order

1. Apply `supabase/migrations/202608130001_ticktick_oauth.sql` with the database owner account.
2. Configure the Edge runtime secrets below. Do not put them in Xcode, `Secrets.xcconfig`, the
   website bundle, or source control.
3. Deploy `ticktick-oauth` with JWT verification enabled and `ticktick-oauth-callback` with JWT
   verification disabled, as declared in `supabase/config.toml`.
4. Register this exact TickTick callback URL, without a wildcard or redirect:
   `https://<supabase-host>/functions/v1/ticktick-oauth-callback/international`.
5. Publish `website/.well-known/apple-app-site-association` as `application/json`, with no redirect,
   and publish `website/oauth/ticktick-return/index.html` over HTTPS.
6. Configure the reverse proxy not to log query strings for the callback and return paths. Add
   shared IP rate limiting for the public callback (recommended: 30 requests per minute per IP)
   and authenticated start endpoint (recommended: 60 requests per minute per IP). The database
   separately enforces the stricter per-user start limits.
7. Run the acceptance checks below. Only then set `TICKTICK_OAUTH_ENABLED = 1` in the release
   `Config/Secrets.xcconfig` and rebuild.

## Edge runtime secrets

| Name | Purpose |
| --- | --- |
| `SUPABASE_URL` | Internal Supabase project URL |
| `SUPABASE_ANON_KEY` | Used only to validate the caller's user JWT |
| `SUPABASE_SERVICE_ROLE_KEY` | Calls the service-role-only OAuth transaction functions |
| `TICKTICK_CLIENT_ID` | International TickTick server application ID |
| `TICKTICK_CLIENT_SECRET` | International TickTick server application secret |
| `TICKTICK_CALLBACK_BASE_URL` | Public Supabase base URL used to construct the fixed callback |
| `TICKTICK_APP_RETURN_BASE_URL` | `https://kirole.681023.xyz` |
| `TICKTICK_TOKEN_KEY_VERSION` | Current positive integer key version, initially `1` |
| `TICKTICK_TOKEN_ENCRYPTION_KEY_V1` | 32 random bytes encoded as unpadded base64url |

Generate the encryption key with a cryptographically secure secret manager. Keep the previous key
version available for at least ten minutes during rotation, then remove it after all deliveries
using that version have expired.

## Scheduled cleanup

Run `SELECT public.cleanup_ticktick_oauth_attempts();` at least once per minute with a database role
allowed to execute the function. The function clears expired ciphertext and removes completed or
failed attempt metadata after 24 hours. The Edge service also clears ciphertext immediately on ack
or disconnect. Deployment is incomplete until the scheduler is installed and an operator has
queried its job table and observed at least one successful run; do not enable the App release gate
based only on a migration applying successfully.

## Local verification

Run these before deploying:

```bash
cd KirolePackage && swift test
cd ..
npx -y deno check --lock=deno.lock \
  supabase/functions/ticktick-oauth/index.ts \
  supabase/functions/ticktick-oauth-callback/index.ts
node --test supabase/functions/_shared/ticktick_oauth_core.test.ts
npx -y deno test --allow-read supabase/tests/ticktick_oauth_integration.ts
```

The integration test boots an embedded PostgreSQL-compatible runtime, applies the real migration,
and exercises ownership, delivery TTL, terminal cleanup, cancel/ack idempotency, and grants. It is
not a substitute for running the same checks against the deployed Supabase project.

## Acceptance checks

- Missing JWT and an anon-key-only request both return 401.
- A signed-in user can start authorization; unknown fields such as `client_id`, `scope`,
  `redirect_uri`, or endpoint URLs are rejected.
- Replaying the provider callback does not exchange the code twice.
- A different Kirole user cannot claim or disconnect the connection.
- Losing the first claim response permits an idempotent re-claim; saving to Keychain then acking
  removes the ciphertext and makes the connection active.
- Cancelled, expired, wrong-state, wrong-region, and provider-error flows contain no sensitive
  values in the handoff URL or logs.
- A real TickTick account can list projects and tasks, reconnect into a new connection namespace,
  and disconnect locally. A 401 requires reauthorization because no refresh flow is documented.

## Explicitly out of scope

The China Dida service stays disabled until its separate application registration, exact OAuth
endpoints, callback, credentials, and real-account behavior are verified. The server does not guess
its contract from TickTick host names. TickTick currently documents no revocation endpoint, so
Kirole disconnect removes its own token and metadata but must not claim to revoke authorization on
TickTick's servers.
