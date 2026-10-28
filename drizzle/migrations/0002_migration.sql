CREATE OR REPLACE FUNCTION public.mafia_set_admin_code(p_code text) RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public, extensions
AS $$
  INSERT INTO admin_config (id, code_hash) VALUES (1, _mafia_hash(p_code))
  ON CONFLICT (id) DO UPDATE SET code_hash = excluded.code_hash;
  DELETE FROM admin_sessions WHERE created_at IS NOT NULL;
$$;
REVOKE ALL ON FUNCTION public.mafia_set_admin_code(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mafia_set_admin_code(text) TO service_role;
CREATE OR REPLACE FUNCTION public.mafia_admin(p_admin text, p_action text, p_player uuid, p_value text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $f$ BEGIN RETURN public._mafia_admin_impl(p_admin, p_action, p_player, p_value); END $f$;