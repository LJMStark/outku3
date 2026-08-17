-- Account deletion for Guideline 5.1.1(v). The signed-in user can remove their
-- auth row; pets, sync_state, and provider_connections cascade from auth.users.

CREATE OR REPLACE FUNCTION public.delete_own_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    uid uuid := auth.uid();
BEGIN
    IF uid IS NULL THEN
        RAISE EXCEPTION 'not authenticated';
    END IF;

    DELETE FROM public.pets WHERE user_id = uid;
    DELETE FROM public.sync_state WHERE user_id = uid;
    IF to_regclass('public.provider_connections') IS NOT NULL THEN
        DELETE FROM public.provider_connections WHERE user_id = uid;
    END IF;
    DELETE FROM auth.users WHERE id = uid;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_own_account() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_own_account() TO authenticated;
