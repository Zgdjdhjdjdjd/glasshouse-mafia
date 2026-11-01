ALTER TABLE public.night_rounds ADD COLUMN retaliation_id uuid REFERENCES public.players(id);
DO $change$
DECLARE body text;
BEGIN
 body:=pg_get_functiondef('public._mafia_base_admin(text,text,uuid,text)'::regprocedure);
 body:=replace(body,'cnt < 6','cnt < 7');
 body:=replace(body,'Need at least 6 players.','Need at least 7 players.');
 body:=replace(body,'WHEN s.rn = 6 THEN ''doctor'' ELSE ''civilian''', 'WHEN s.rn = 6 THEN ''doctor'' WHEN s.rn = 7 THEN ''grandma'' ELSE ''civilian''');
 EXECUTE body;
 body:=pg_get_functiondef('public._mafia_base_state(text,text)'::regprocedure);
 body:=replace(body,'''joker'', (SELECT count(*) FROM players WHERE NOT kicked AND alive AND role = ''joker'')', '''grandma'', (SELECT count(*) FROM players WHERE NOT kicked AND alive AND role = ''grandma''), ''joker'', (SELECT count(*) FROM players WHERE NOT kicked AND alive AND role = ''joker'')');
 EXECUTE body;
 body:=pg_get_functiondef('public.mafia_night_admin(text,text,uuid,integer)'::regprocedure);
 body:=replace(body,'protected := p_target IS NOT NULL AND EXISTS(', 'protected := p_target IS NOT NULL AND (t.role = ''grandma'' OR EXISTS(');
 body:=replace(body,'na.target_id=p_target);','na.target_id=p_target));');
 body:=replace(body,'''saved'',protected AND a.target_id=p_target', '''saved'',protected AND t.role IS DISTINCT FROM ''grandma'' AND a.target_id=p_target');
 EXECUTE body;
 body:=pg_get_functiondef('public.mafia_state(text,text)'::regprocedure);
 body:=replace(body,'''saved'',n.saved)', '''saved'',n.saved,''grandmaRetaliated'',n.retaliation_id IS NOT NULL,''retaliationName'',(SELECT name FROM players WHERE id=n.retaliation_id))');
 EXECUTE body;
END $change$;
CREATE OR REPLACE FUNCTION public.mafia_join(p_token text,p_name text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE ex players; n text:=btrim(p_name); g game;
BEGIN
 IF p_token IS NULL OR length(p_token)<16 OR length(p_token)>100 THEN RETURN jsonb_build_object('ok',false,'error','Invalid session.'); END IF;
 IF n IS NULL OR length(n)<1 OR length(n)>24 THEN RETURN jsonb_build_object('ok',false,'error','Name must be 1–24 characters.'); END IF;
 PERFORM pg_advisory_xact_lock(4242);
 SELECT * INTO ex FROM players WHERE token=p_token;
 IF ex.id IS NOT NULL AND NOT ex.kicked THEN RETURN jsonb_build_object('ok',true); END IF;
 IF (SELECT count(*) FROM players WHERE NOT kicked)>=23 THEN RETURN jsonb_build_object('ok',false,'error','The room is full (23/23).'); END IF;
 IF EXISTS(SELECT 1 FROM players WHERE NOT kicked AND lower(name)=lower(n)) THEN RETURN jsonb_build_object('ok',false,'error','That name is already taken.'); END IF;
 SELECT * INTO g FROM game WHERE id=1;
 IF ex.id IS NOT NULL THEN UPDATE players SET token='retired:'||gen_random_uuid()::text WHERE id=ex.id; END IF;
 INSERT INTO players(token,name,alive) VALUES(p_token,n,g.phase='lobby');
 PERFORM _mafia_bump(); RETURN jsonb_build_object('ok',true);
END $$;
CREATE FUNCTION public.mafia_approve_night(p_admin text,p_round integer,p_target uuid,p_retaliation uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE g game; victim players; attacker players; r jsonb;
BEGIN
 IF NOT _mafia_is_admin(p_admin) THEN RETURN jsonb_build_object('ok',false,'error','Not authorized.'); END IF;
 PERFORM pg_advisory_xact_lock(4242);
 SELECT * INTO g FROM game WHERE id=1;
 IF g.phase<>'playing' OR p_round IS DISTINCT FROM g.night_round OR NOT EXISTS(SELECT 1 FROM night_rounds WHERE round=p_round AND status='closed') THEN RETURN jsonb_build_object('ok',false,'error','Close the current night before approving.'); END IF;
 SELECT * INTO victim FROM players WHERE id=p_target;
 IF victim.role='grandma' AND victim.alive AND NOT victim.kicked THEN
   SELECT * INTO attacker FROM players WHERE id=p_retaliation AND role='mafia' AND alive AND NOT kicked;
   IF attacker.id IS NULL THEN RETURN jsonb_build_object('ok',false,'error','Choose a living Mafia for Grandma to shoot.'); END IF;
   IF EXISTS(SELECT 1 FROM night_actions a JOIN players p ON p.id=a.player_id WHERE a.round=p_round AND a.role='mafia' AND a.target_id=p_target AND p.alive AND NOT p.kicked) AND NOT EXISTS(SELECT 1 FROM night_actions WHERE round=p_round AND player_id=p_retaliation AND target_id=p_target AND role='mafia') THEN RETURN jsonb_build_object('ok',false,'error','Choose one of the Mafia who targeted Grandma.'); END IF;
 ELSIF p_retaliation IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'error','Retaliation is only for attacks on Grandma.'); END IF;
 PERFORM set_config('mafia.grandma_approval','approved',true);
 r:=mafia_night_admin(p_admin,'resolveNight',p_target,p_round);
 IF r->>'ok'='true' AND attacker.id IS NOT NULL THEN
   UPDATE players SET alive=false WHERE id=attacker.id;
   UPDATE night_rounds SET retaliation_id=attacker.id WHERE round=p_round;
   PERFORM _mafia_after_removal('mafia',false);
 END IF;
 RETURN r;
END $$;
DO $guard$
DECLARE body text;
BEGIN
 body:=pg_get_functiondef('public.mafia_night_admin(text,text,uuid,integer)'::regprocedure);
 body:=replace(body,'protected := p_target', 'IF t.role=''grandma'' AND current_setting(''mafia.grandma_approval'',true) IS DISTINCT FROM ''approved'' THEN RETURN jsonb_build_object(''ok'',false,''error'',''Use Grandma approval and select her attacker.''); END IF; protected := p_target');
 EXECUTE body;
END $guard$;
REVOKE ALL ON FUNCTION public.mafia_approve_night(text,integer,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mafia_approve_night(text,integer,uuid,uuid) TO anon,authenticated,service_role;