import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

const USER_A = "00000000-0000-4000-8000-000000000001";
const USER_B = "00000000-0000-4000-8000-000000000002";

Deno.test("TickTick OAuth migration preserves delivery, ownership, terminal cleanup, and idempotency", async () => {
  const database = new PGlite();
  try {
    await database.exec(`
      CREATE ROLE anon;
      CREATE ROLE authenticated;
      CREATE ROLE service_role;
      CREATE SCHEMA auth;
      CREATE TABLE auth.users (id UUID PRIMARY KEY);
      CREATE FUNCTION auth.uid() RETURNS UUID LANGUAGE SQL STABLE
        AS $$ SELECT NULL::UUID $$;
    `);
    const migration = await Deno.readTextFile(
      new URL("../migrations/202608130001_ticktick_oauth.sql", import.meta.url),
    );
    await database.exec(migration);
    await database.query("INSERT INTO auth.users (id) VALUES ($1), ($2)", [USER_A, USER_B]);

    const ready = await makeReadyAttempt(database, "a", "b");
    await database.query(
      "UPDATE private.ticktick_oauth_attempts SET expires_at = NOW() - INTERVAL '1 second' WHERE id = $1",
      [ready.attemptID],
    );
    await database.query("SELECT public.cleanup_ticktick_oauth_attempts()");
    const deliveryWindow = await database.query<{ status: string; has_token: boolean }>(
      "SELECT status, token_ciphertext IS NOT NULL AS has_token FROM private.ticktick_oauth_attempts WHERE id = $1",
      [ready.attemptID],
    );
    assertEquals(deliveryWindow.rows[0], { status: "ready", has_token: true });

    const crossUser = await database.query(
      "SELECT * FROM public.claim_ticktick_oauth_token($1, $2, $3)",
      [USER_B, ready.attemptID, hash("b")],
    );
    assertEquals(crossUser.rows.length, 0);

    for (let count = 0; count < 5; count += 1) {
      await database.query(
        "SELECT * FROM public.claim_ticktick_oauth_token($1, $2, $3)",
        [USER_A, ready.attemptID, hash("wrong")],
      );
    }
    const locked = await database.query<{ attempt_status: string; connection_status: string }>(
      `SELECT attempts.status AS attempt_status, connections.status AS connection_status
         FROM private.ticktick_oauth_attempts attempts
         JOIN public.provider_connections connections ON connections.id = attempts.connection_id
        WHERE attempts.id = $1`,
      [ready.attemptID],
    );
    assertEquals(locked.rows[0], { attempt_status: "failed", connection_status: "disconnected" });

    const cancelled = await startAttempt(database, "c", "d");
    const firstCancel = await cancelAttempt(database, cancelled, hash("d"));
    const repeatedCancel = await cancelAttempt(database, cancelled, hash("d"));
    assert(firstCancel);
    assert(repeatedCancel);

    const acknowledged = await makeReadyAttempt(database, "e", "f");
    const claim = await database.query<{ delivery_id: string }>(
      "SELECT * FROM public.claim_ticktick_oauth_token($1, $2, $3)",
      [USER_A, acknowledged.attemptID, hash("f")],
    );
    const deliveryID = claim.rows[0]?.delivery_id;
    assert(deliveryID);
    const firstAck = await acknowledge(database, acknowledged.attemptID, hash("f"), deliveryID);
    const repeatedAck = await acknowledge(database, acknowledged.attemptID, hash("f"), deliveryID);
    assert(firstAck);
    assert(repeatedAck);
    const completed = await database.query<{
      attempt_status: string;
      connection_status: string;
      token_cleared: boolean;
    }>(
      `SELECT attempts.status AS attempt_status, connections.status AS connection_status,
              attempts.token_ciphertext IS NULL AS token_cleared
         FROM private.ticktick_oauth_attempts attempts
         JOIN public.provider_connections connections ON connections.id = attempts.connection_id
        WHERE attempts.id = $1`,
      [acknowledged.attemptID],
    );
    assertEquals(completed.rows[0], {
      attempt_status: "complete",
      connection_status: "active",
      token_cleared: true,
    });

    const privileges = await database.query<{
      anon_can_start: boolean;
      user_can_read_private: boolean;
      user_can_insert_connection: boolean;
    }>(`
      SELECT
        has_function_privilege(
          'anon',
          'public.start_ticktick_oauth_attempt(uuid,text,text,text)',
          'EXECUTE'
        ) AS anon_can_start,
        has_table_privilege(
          'authenticated',
          'private.ticktick_oauth_attempts',
          'SELECT'
        ) AS user_can_read_private,
        has_table_privilege(
          'authenticated',
          'public.provider_connections',
          'INSERT'
        ) AS user_can_insert_connection
    `);
    assertEquals(privileges.rows[0], {
      anon_can_start: false,
      user_can_read_private: false,
      user_can_insert_connection: false,
    });

    await database.query(
      "UPDATE private.ticktick_oauth_attempts SET created_at = NOW() - INTERVAL '2 days'",
    );
    const staleExchange = await startAttempt(database, "g", "h");
    await database.query(
      "SELECT * FROM public.consume_ticktick_oauth_callback($1, 'international')",
      [hash("g")],
    );
    await database.query(
      "UPDATE private.ticktick_oauth_attempts SET expires_at = NOW() - INTERVAL '1 second' WHERE id = $1",
      [staleExchange],
    );
    await database.query("SELECT public.cleanup_ticktick_oauth_attempts()");
    assertEquals(await attemptStatus(database, staleExchange), "expired");

    const expiredDelivery = await makeReadyAttempt(database, "i", "j");
    await database.query(
      "UPDATE private.ticktick_oauth_attempts SET delivery_expires_at = NOW() - INTERVAL '1 second' WHERE id = $1",
      [expiredDelivery.attemptID],
    );
    await database.query("SELECT public.cleanup_ticktick_oauth_attempts()");
    assertEquals(await attemptAndConnectionStatus(database, expiredDelivery.attemptID), {
      attempt_status: "expired",
      connection_status: "disconnected",
    });

    const failedExchange = await makeReadyAttempt(database, "k", "l");
    await database.query(
      "SELECT public.fail_ticktick_oauth_attempt($1, 'exchange_failed')",
      [failedExchange.attemptID],
    );
    assertEquals(await attemptAndConnectionStatus(database, failedExchange.attemptID), {
      attempt_status: "failed",
      connection_status: "disconnected",
    });
  } finally {
    await database.close();
  }
});

async function startAttempt(database: PGlite, state: string, claim: string): Promise<string> {
  const result = await database.query<{ attempt_id: string }>(
    "SELECT * FROM public.start_ticktick_oauth_attempt($1, 'international', $2, $3)",
    [USER_A, hash(state), hash(claim)],
  );
  return result.rows[0].attempt_id;
}

async function makeReadyAttempt(
  database: PGlite,
  state: string,
  claim: string,
): Promise<{ attemptID: string; connectionID: string }> {
  const attemptID = await startAttempt(database, state, claim);
  await database.query(
    "SELECT * FROM public.consume_ticktick_oauth_callback($1, 'international')",
    [hash(state)],
  );
  const connectionID = crypto.randomUUID();
  const finished = await database.query<{ finish_ticktick_oauth_exchange: boolean }>(
    `SELECT public.finish_ticktick_oauth_exchange(
       $1, $2, 'ciphertext', 'iv', 1::SMALLINT, 'tasks:read', NULL::TIMESTAMPTZ
     )`,
    [attemptID, connectionID],
  );
  assert(finished.rows[0].finish_ticktick_oauth_exchange);
  return { attemptID, connectionID };
}

async function cancelAttempt(database: PGlite, attemptID: string, claimHash: string): Promise<boolean> {
  const result = await database.query<{ cancel_ticktick_oauth_attempt: boolean }>(
    "SELECT public.cancel_ticktick_oauth_attempt($1, $2, $3)",
    [USER_A, attemptID, claimHash],
  );
  return result.rows[0].cancel_ticktick_oauth_attempt;
}

async function acknowledge(
  database: PGlite,
  attemptID: string,
  claimHash: string,
  deliveryID: string,
): Promise<boolean> {
  const result = await database.query<{ ack_ticktick_oauth_token: boolean }>(
    "SELECT public.ack_ticktick_oauth_token($1, $2, $3, $4)",
    [USER_A, attemptID, claimHash, deliveryID],
  );
  return result.rows[0].ack_ticktick_oauth_token;
}

function hash(seed: string): string {
  const hexadecimal = Array.from(seed, (character) => character.charCodeAt(0).toString(16)).join("");
  return hexadecimal.repeat(64).slice(0, 64);
}

async function attemptStatus(database: PGlite, attemptID: string): Promise<string> {
  const result = await database.query<{ status: string }>(
    "SELECT status FROM private.ticktick_oauth_attempts WHERE id = $1",
    [attemptID],
  );
  return result.rows[0].status;
}

async function attemptAndConnectionStatus(
  database: PGlite,
  attemptID: string,
): Promise<{ attempt_status: string; connection_status: string }> {
  const result = await database.query<{ attempt_status: string; connection_status: string }>(
    `SELECT attempts.status AS attempt_status, connections.status AS connection_status
       FROM private.ticktick_oauth_attempts attempts
       JOIN public.provider_connections connections ON connections.id = attempts.connection_id
      WHERE attempts.id = $1`,
    [attemptID],
  );
  return result.rows[0];
}
