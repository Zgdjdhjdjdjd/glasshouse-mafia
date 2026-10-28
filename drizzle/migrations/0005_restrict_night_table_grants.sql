REVOKE ALL ON TABLE public.night_actions, public.night_rounds FROM anon, authenticated;
GRANT ALL ON TABLE public.night_actions, public.night_rounds TO service_role;