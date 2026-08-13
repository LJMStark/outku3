-- TickTick OAuth: authenticated, user-bound, one-time token delivery.
-- The provider access token is encrypted by the Edge Function before it reaches this schema.

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS public.provider_connections (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    provider TEXT NOT NULL CHECK (provider = 'ticktick'),
    region TEXT NOT NULL CHECK (region = 'international'),
    status TEXT NOT NULL CHECK (status IN ('pending_delivery', 'active', 'reauth_required', 'disconnected')),
    scope TEXT,
    connected_at TIMESTAMPTZ,
    last_validated_at TIMESTAMPTZ,
    disconnected_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS provider_connections_one_active_ticktick
    ON public.provider_connections (user_id, provider)
    WHERE status = 'active';

ALTER TABLE public.provider_connections ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.provider_connections FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.provider_connections TO authenticated;
DROP POLICY IF EXISTS "Users can view own provider connections" ON public.provider_connections;
CREATE POLICY "Users can view own provider connections" ON public.provider_connections
    FOR SELECT USING (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS private.ticktick_oauth_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    region TEXT NOT NULL CHECK (region = 'international'),
    state_hash TEXT UNIQUE,
    claim_secret_hash TEXT NOT NULL,
    status TEXT NOT NULL CHECK (
        status IN ('pending', 'exchanging', 'ready', 'delivering', 'complete', 'failed', 'expired', 'cancelled')
    ),
    expires_at TIMESTAMPTZ NOT NULL,
    callback_consumed_at TIMESTAMPTZ,
    connection_id UUID REFERENCES public.provider_connections(id) ON DELETE SET NULL,
    token_ciphertext TEXT,
    token_iv TEXT,
    token_key_version SMALLINT,
    token_expires_at TIMESTAMPTZ,
    granted_scope TEXT,
    delivery_id UUID,
    delivery_expires_at TIMESTAMPTZ,
    lease_expires_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    acknowledged_at TIMESTAMPTZ,
    failed_claim_count SMALLINT NOT NULL DEFAULT 0,
    error_code TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

REVOKE ALL ON ALL TABLES IN SCHEMA private FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA private FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.start_ticktick_oauth_attempt(
    p_user_id UUID,
    p_region TEXT,
    p_state_hash TEXT,
    p_claim_secret_hash TEXT
)
RETURNS TABLE(attempt_id UUID, attempt_expires_at TIMESTAMPTZ)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $$
DECLARE
    v_attempt_id UUID;
    v_expires_at TIMESTAMPTZ := NOW() + INTERVAL '10 minutes';
    v_minute_count INTEGER;
    v_day_count INTEGER;
BEGIN
    -- Serialize all start/rate-limit decisions for one Kirole user across devices and Edge
    -- instances. The two-key form avoids the signed-int range issues of hashtextextended.
    PERFORM pg_advisory_xact_lock(hashtext('ticktick_oauth_start'), hashtext(p_user_id::TEXT));

    IF p_region <> 'international' THEN
        RAISE EXCEPTION 'unsupported_region' USING ERRCODE = '22023';
    END IF;
    IF p_state_hash !~ '^[0-9a-f]{64}$' OR p_claim_secret_hash !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'invalid_secret_hash' USING ERRCODE = '22023';
    END IF;

    SELECT COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '1 minute'),
           COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '1 day')
      INTO v_minute_count, v_day_count
      FROM private.ticktick_oauth_attempts
     WHERE user_id = p_user_id;
    IF v_minute_count >= 5 OR v_day_count >= 20 THEN
        RAISE EXCEPTION 'rate_limited' USING ERRCODE = 'P0001';
    END IF;

    -- Synchronize with callback consume/finish before reading connection_id. Without this row
    -- lock, a concurrent finish could create a pending connection after the subquery below ran.
    PERFORM 1
      FROM private.ticktick_oauth_attempts
     WHERE user_id = p_user_id
       AND status IN ('pending', 'exchanging', 'ready', 'delivering')
     FOR UPDATE;

    UPDATE public.provider_connections
       SET status = 'disconnected', disconnected_at = NOW(), updated_at = NOW()
     WHERE id IN (
        SELECT connection_id FROM private.ticktick_oauth_attempts
         WHERE user_id = p_user_id AND status IN ('pending', 'exchanging', 'ready', 'delivering')
     ) AND status = 'pending_delivery';

    UPDATE private.ticktick_oauth_attempts
       SET status = 'cancelled', state_hash = NULL, token_ciphertext = NULL,
           token_iv = NULL, updated_at = NOW()
     WHERE user_id = p_user_id
       AND status IN ('pending', 'exchanging', 'ready', 'delivering');

    INSERT INTO private.ticktick_oauth_attempts (
        user_id, region, state_hash, claim_secret_hash, status, expires_at
    ) VALUES (
        p_user_id, p_region, p_state_hash, p_claim_secret_hash, 'pending', v_expires_at
    ) RETURNING id INTO v_attempt_id;

    RETURN QUERY SELECT v_attempt_id, v_expires_at;
END;
$$;

CREATE OR REPLACE FUNCTION public.consume_ticktick_oauth_callback(
    p_state_hash TEXT,
    p_region TEXT
)
RETURNS TABLE(attempt_id UUID, owner_user_id UUID, attempt_region TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $$
BEGIN
    RETURN QUERY
    UPDATE private.ticktick_oauth_attempts
       SET status = 'exchanging', callback_consumed_at = NOW(), state_hash = NULL,
           updated_at = NOW()
     WHERE state_hash = p_state_hash
       AND region = p_region
       AND status = 'pending'
       AND expires_at > NOW()
    RETURNING id, user_id, region;
END;
$$;

CREATE OR REPLACE FUNCTION public.finish_ticktick_oauth_exchange(
    p_attempt_id UUID,
    p_connection_id UUID,
    p_token_ciphertext TEXT,
    p_token_iv TEXT,
    p_token_key_version SMALLINT,
    p_granted_scope TEXT,
    p_token_expires_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $$
DECLARE
    v_user_id UUID;
    v_region TEXT;
BEGIN
    SELECT user_id, region INTO v_user_id, v_region
      FROM private.ticktick_oauth_attempts
     WHERE id = p_attempt_id AND status = 'exchanging'
     FOR UPDATE;
    IF NOT FOUND THEN RETURN FALSE; END IF;

    INSERT INTO public.provider_connections (
        id, user_id, provider, region, status, scope
    ) VALUES (
        p_connection_id, v_user_id, 'ticktick', v_region, 'pending_delivery', p_granted_scope
    );

    UPDATE private.ticktick_oauth_attempts
       SET status = 'ready', connection_id = p_connection_id,
           token_ciphertext = p_token_ciphertext, token_iv = p_token_iv,
           token_key_version = p_token_key_version, token_expires_at = p_token_expires_at,
           granted_scope = p_granted_scope, delivery_expires_at = NOW() + INTERVAL '10 minutes',
           updated_at = NOW()
     WHERE id = p_attempt_id;
    RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.fail_ticktick_oauth_attempt(
    p_attempt_id UUID,
    p_error_code TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $$
DECLARE
    v_connection_id UUID;
BEGIN
    SELECT connection_id INTO v_connection_id
      FROM private.ticktick_oauth_attempts
     WHERE id = p_attempt_id
       AND status IN ('pending', 'exchanging', 'ready', 'delivering')
     FOR UPDATE;
    IF NOT FOUND THEN RETURN; END IF;

    UPDATE public.provider_connections
       SET status = 'disconnected', disconnected_at = NOW(), updated_at = NOW()
     WHERE id = v_connection_id AND status = 'pending_delivery';

    UPDATE private.ticktick_oauth_attempts
       SET status = 'failed', error_code = LEFT(p_error_code, 64), state_hash = NULL,
           token_ciphertext = NULL, token_iv = NULL, updated_at = NOW()
     WHERE id = p_attempt_id
       AND status IN ('pending', 'exchanging', 'ready', 'delivering');
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_ticktick_oauth_token(
    p_user_id UUID,
    p_attempt_id UUID,
    p_claim_secret_hash TEXT
)
RETURNS TABLE(
    delivery_id UUID,
    connection_id UUID,
    attempt_region TEXT,
    token_ciphertext TEXT,
    token_iv TEXT,
    token_key_version SMALLINT,
    granted_scope TEXT,
    token_expires_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $$
DECLARE
    v_attempt private.ticktick_oauth_attempts%ROWTYPE;
    v_delivery_id UUID;
BEGIN
    SELECT * INTO v_attempt
      FROM private.ticktick_oauth_attempts
     WHERE id = p_attempt_id AND user_id = p_user_id
     FOR UPDATE;
    IF NOT FOUND THEN RETURN; END IF;
    IF v_attempt.status NOT IN ('ready', 'delivering') THEN RETURN; END IF;

    IF v_attempt.claim_secret_hash <> p_claim_secret_hash THEN
        UPDATE private.ticktick_oauth_attempts AS attempts
           SET failed_claim_count = failed_claim_count + 1,
               status = CASE WHEN failed_claim_count + 1 >= 5 THEN 'failed' ELSE status END,
               error_code = CASE WHEN failed_claim_count + 1 >= 5 THEN 'claim_locked' ELSE error_code END,
               token_ciphertext = CASE WHEN failed_claim_count + 1 >= 5 THEN NULL ELSE attempts.token_ciphertext END,
               token_iv = CASE WHEN failed_claim_count + 1 >= 5 THEN NULL ELSE attempts.token_iv END,
               updated_at = NOW()
         WHERE id = p_attempt_id;
        IF v_attempt.failed_claim_count + 1 >= 5 THEN
            UPDATE public.provider_connections
               SET status = 'disconnected', disconnected_at = NOW(), updated_at = NOW()
             WHERE id = v_attempt.connection_id AND status = 'pending_delivery';
        END IF;
        RETURN;
    END IF;

    IF v_attempt.delivery_expires_at IS NULL OR v_attempt.delivery_expires_at <= NOW() THEN
        UPDATE public.provider_connections
           SET status = 'disconnected', disconnected_at = NOW(), updated_at = NOW()
         WHERE id = v_attempt.connection_id AND status = 'pending_delivery';
        UPDATE private.ticktick_oauth_attempts
           SET status = 'expired', token_ciphertext = NULL, token_iv = NULL, updated_at = NOW()
         WHERE id = p_attempt_id AND status IN ('ready', 'delivering');
        RETURN;
    END IF;

    IF v_attempt.status = 'ready'
       OR (v_attempt.status = 'delivering' AND v_attempt.lease_expires_at <= NOW()) THEN
        v_delivery_id := COALESCE(v_attempt.delivery_id, gen_random_uuid());
        UPDATE private.ticktick_oauth_attempts
           SET status = 'delivering', delivery_id = v_delivery_id,
               delivered_at = COALESCE(delivered_at, NOW()),
               lease_expires_at = NOW() + INTERVAL '60 seconds', updated_at = NOW()
         WHERE id = p_attempt_id;
    ELSIF v_attempt.status = 'delivering' THEN
        v_delivery_id := v_attempt.delivery_id;
    ELSE
        RETURN;
    END IF;

    RETURN QUERY
    SELECT v_delivery_id, v_attempt.connection_id, v_attempt.region,
           v_attempt.token_ciphertext, v_attempt.token_iv, v_attempt.token_key_version,
           v_attempt.granted_scope, v_attempt.token_expires_at;
END;
$$;

CREATE OR REPLACE FUNCTION public.ack_ticktick_oauth_token(
    p_user_id UUID,
    p_attempt_id UUID,
    p_claim_secret_hash TEXT,
    p_delivery_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $$
DECLARE
    v_attempt private.ticktick_oauth_attempts%ROWTYPE;
BEGIN
    SELECT * INTO v_attempt
      FROM private.ticktick_oauth_attempts
     WHERE id = p_attempt_id AND user_id = p_user_id
     FOR UPDATE;
    IF NOT FOUND
       OR v_attempt.claim_secret_hash <> p_claim_secret_hash
       OR v_attempt.delivery_id <> p_delivery_id THEN
        RETURN FALSE;
    END IF;
    IF v_attempt.status = 'complete' THEN RETURN TRUE; END IF;
    IF v_attempt.status <> 'delivering' THEN RETURN FALSE; END IF;
    IF v_attempt.delivery_expires_at IS NULL OR v_attempt.delivery_expires_at <= NOW() THEN
        UPDATE public.provider_connections
           SET status = 'disconnected', disconnected_at = NOW(), updated_at = NOW()
         WHERE id = v_attempt.connection_id AND status = 'pending_delivery';
        UPDATE private.ticktick_oauth_attempts
           SET status = 'expired', token_ciphertext = NULL, token_iv = NULL,
               updated_at = NOW()
         WHERE id = p_attempt_id;
        RETURN FALSE;
    END IF;

    UPDATE public.provider_connections
       SET status = 'disconnected', disconnected_at = NOW(), updated_at = NOW()
     WHERE user_id = p_user_id AND provider = 'ticktick' AND status = 'active'
       AND id <> v_attempt.connection_id;
    UPDATE public.provider_connections
       SET status = 'active', connected_at = NOW(), updated_at = NOW()
     WHERE id = v_attempt.connection_id AND user_id = p_user_id AND status = 'pending_delivery';
    UPDATE private.ticktick_oauth_attempts
       SET status = 'complete', acknowledged_at = NOW(), state_hash = NULL,
           token_ciphertext = NULL, token_iv = NULL, updated_at = NOW()
     WHERE id = p_attempt_id;
    RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.disconnect_ticktick_connection(
    p_user_id UUID,
    p_connection_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $$
BEGIN
    PERFORM 1
      FROM private.ticktick_oauth_attempts
     WHERE user_id = p_user_id
       AND (connection_id = p_connection_id OR status IN ('pending', 'exchanging', 'ready', 'delivering'))
     FOR UPDATE;

    UPDATE public.provider_connections
       SET status = 'disconnected', disconnected_at = NOW(), updated_at = NOW()
     WHERE id = p_connection_id AND user_id = p_user_id AND provider = 'ticktick';
    IF NOT FOUND THEN RETURN FALSE; END IF;

    UPDATE private.ticktick_oauth_attempts
       SET status = CASE WHEN status = 'complete' THEN status ELSE 'cancelled' END,
           state_hash = NULL, token_ciphertext = NULL, token_iv = NULL, updated_at = NOW()
     WHERE user_id = p_user_id
       AND (connection_id = p_connection_id OR status IN ('pending', 'exchanging', 'ready', 'delivering'));
    RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_ticktick_oauth_attempt(
    p_user_id UUID,
    p_attempt_id UUID,
    p_claim_secret_hash TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $$
DECLARE
    v_connection_id UUID;
    v_status TEXT;
BEGIN
    SELECT connection_id, status INTO v_connection_id, v_status
      FROM private.ticktick_oauth_attempts
     WHERE id = p_attempt_id AND user_id = p_user_id
       AND claim_secret_hash = p_claim_secret_hash
     FOR UPDATE;
    IF NOT FOUND THEN RETURN FALSE; END IF;
    IF v_status IN ('cancelled', 'failed', 'expired') THEN
        UPDATE public.provider_connections
           SET status = 'disconnected', disconnected_at = NOW(), updated_at = NOW()
         WHERE id = v_connection_id AND user_id = p_user_id AND status = 'pending_delivery';
        RETURN TRUE;
    END IF;
    IF v_status NOT IN ('pending', 'exchanging', 'ready', 'delivering') THEN
        RETURN FALSE;
    END IF;

    UPDATE public.provider_connections
       SET status = 'disconnected', disconnected_at = NOW(), updated_at = NOW()
     WHERE id = v_connection_id AND user_id = p_user_id AND status = 'pending_delivery';
    UPDATE private.ticktick_oauth_attempts
       SET status = 'cancelled', state_hash = NULL, token_ciphertext = NULL,
           token_iv = NULL, updated_at = NOW()
     WHERE id = p_attempt_id;
    RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.cleanup_ticktick_oauth_attempts()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    -- Lock the exact attempts that will expire before reading their connection IDs. This
    -- serializes cleanup with callback finish and prevents orphaned pending connections.
    PERFORM 1
      FROM private.ticktick_oauth_attempts
     WHERE (status IN ('pending', 'exchanging') AND expires_at <= NOW())
        OR (status IN ('ready', 'delivering') AND delivery_expires_at <= NOW())
     FOR UPDATE;

    UPDATE public.provider_connections
       SET status = 'disconnected', disconnected_at = NOW(), updated_at = NOW()
     WHERE id IN (
        SELECT connection_id FROM private.ticktick_oauth_attempts
         WHERE (status IN ('pending', 'exchanging') AND expires_at <= NOW())
            OR (status IN ('ready', 'delivering') AND delivery_expires_at <= NOW())
     ) AND status = 'pending_delivery';

    UPDATE private.ticktick_oauth_attempts
       SET status = CASE WHEN status IN ('pending', 'exchanging', 'ready', 'delivering') THEN 'expired' ELSE status END,
           state_hash = NULL, token_ciphertext = NULL, token_iv = NULL, updated_at = NOW()
     WHERE status IN ('pending', 'exchanging', 'ready', 'delivering')
       AND (
          (status IN ('pending', 'exchanging') AND expires_at <= NOW())
          OR (status IN ('ready', 'delivering') AND delivery_expires_at <= NOW())
       );
    GET DIAGNOSTICS v_count = ROW_COUNT;
    DELETE FROM private.ticktick_oauth_attempts
     WHERE created_at < NOW() - INTERVAL '24 hours'
       AND status IN ('complete', 'failed', 'expired', 'cancelled');
    RETURN v_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.start_ticktick_oauth_attempt(UUID, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.consume_ticktick_oauth_callback(TEXT, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.finish_ticktick_oauth_exchange(UUID, UUID, TEXT, TEXT, SMALLINT, TEXT, TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.fail_ticktick_oauth_attempt(UUID, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.claim_ticktick_oauth_token(UUID, UUID, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.ack_ticktick_oauth_token(UUID, UUID, TEXT, UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.disconnect_ticktick_connection(UUID, UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.cancel_ticktick_oauth_attempt(UUID, UUID, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.cleanup_ticktick_oauth_attempts() FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.start_ticktick_oauth_attempt(UUID, TEXT, TEXT, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.consume_ticktick_oauth_callback(TEXT, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.finish_ticktick_oauth_exchange(UUID, UUID, TEXT, TEXT, SMALLINT, TEXT, TIMESTAMPTZ) TO service_role;
GRANT EXECUTE ON FUNCTION public.fail_ticktick_oauth_attempt(UUID, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_ticktick_oauth_token(UUID, UUID, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.ack_ticktick_oauth_token(UUID, UUID, TEXT, UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.disconnect_ticktick_connection(UUID, UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.cancel_ticktick_oauth_attempt(UUID, UUID, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.cleanup_ticktick_oauth_attempts() TO service_role;
