ALTER TABLE public.game ADD COLUMN night_open boolean NOT NULL DEFAULT false;
ALTER TABLE public.game ADD COLUMN night_round integer NOT NULL DEFAULT 0;
CREATE TABLE public.night_rounds (round integer PRIMARY KEY,status text NOT NULL CHECK(status IN ('open','closed','resolved','cancelled')),victim_id uuid REFERENCES public.players(id),saved boolean NOT NULL DEFAULT false);
GRANT ALL ON public.night_rounds TO service_role;
ALTER TABLE public.night_rounds ENABLE ROW LEVEL SECURITY;
CREATE TABLE public.night_actions (round integer NOT NULL REFERENCES public.night_rounds(round),player_id uuid NOT NULL REFERENCES public.players(id),target_id uuid NOT NULL REFERENCES public.players(id),role text NOT NULL CHECK(role IN ('mafia','doctor','detective')),result jsonb,PRIMARY KEY(round,player_id));
GRANT ALL ON public.night_actions TO service_role;
ALTER TABLE public.night_actions ENABLE ROW LEVEL SECURITY;
DO $copy$ BEGIN
EXECUTE replace(pg_get_functiondef('public.mafia_state(text,text)'::regprocedure),'FUNCTION public.mafia_state(', 'FUNCTION public._mafia_base_state(');
EXECUTE replace(pg_get_functiondef('public.mafia_admin(text,text,uuid,text)'::regprocedure),'FUNCTION public.mafia_admin(', 'FUNCTION public._mafia_base_admin(');
EXECUTE replace(pg_get_functiondef('public.mafia_vote(text,uuid)'::regprocedure), E'BEGIN\n  SELECT', E'BEGIN\n  PERFORM pg_advisory_xact_lock(4242);\n  SELECT');
END $copy$;
CREATE OR REPLACE FUNCTION public.mafia_night_action(p_token text,p_target uuid,p_round integer) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE g game; p players; t players;
BEGIN
 PERFORM pg_advisory_xact_lock(4242);
 SELECT * INTO g FROM game WHERE id=1;
 IF g.phase <> 'playing' OR NOT g.night_open OR p_round IS NULL OR g.night_round <> p_round THEN RETURN jsonb_build_object('ok',false,'error','Night choices are closed.'); END IF;
 SELECT * INTO p FROM players WHERE token=p_token;
 IF p.id IS NULL OR p.kicked OR NOT p.alive OR p.role IS NULL OR p.role NOT IN ('mafia','doctor','detective') THEN RETURN jsonb_build_object('ok',false,'error','You cannot act tonight.'); END IF;
 SELECT * INTO t FROM players WHERE id=p_target;
 IF t.id IS NULL OR t.kicked OR NOT t.alive OR t.role IS NULL OR (p.id=t.id AND p.role <> 'doctor') THEN RETURN jsonb_build_object('ok',false,'error','Invalid target.'); END IF;
 INSERT INTO night_actions(round,player_id,target_id,role) VALUES(p_round,p.id,t.id,p.role) ON CONFLICT DO NOTHING;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','You already chose this night.'); END IF;
 PERFORM _mafia_bump(); RETURN jsonb_build_object('ok',true);
END $$;
CREATE OR REPLACE FUNCTION public.mafia_night_admin(p_admin text,p_action text,p_target uuid,p_round integer) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE g game; n night_rounds; t players; protected boolean; a record;
BEGIN
 IF NOT _mafia_is_admin(p_admin) THEN RETURN jsonb_build_object('ok',false,'error','Not authorized.'); END IF;
 PERFORM pg_advisory_xact_lock(4242);
 SELECT * INTO g FROM game WHERE id=1;
 SELECT * INTO n FROM night_rounds WHERE round=g.night_round;
 IF g.phase <> 'playing' THEN RETURN jsonb_build_object('ok',false,'error','No game in progress.'); END IF;
 IF p_round IS NULL OR p_round <> g.night_round THEN RETURN jsonb_build_object('ok',false,'error','Night changed. Refresh and try again.'); END IF;
 IF p_action='startNight' THEN
   IF g.voting_open OR n.status IN ('open','closed') THEN RETURN jsonb_build_object('ok',false,'error','Finish the current vote or night first.'); END IF;
   INSERT INTO night_rounds(round,status) VALUES(g.night_round+1,'open');
   UPDATE game SET night_round=night_round+1,night_open=true WHERE id=1;
 ELSIF p_action='closeNight' THEN
   IF n.status IS DISTINCT FROM 'open' THEN RETURN jsonb_build_object('ok',false,'error','Night is not open.'); END IF;
   UPDATE night_rounds SET status='closed' WHERE round=g.night_round;
   UPDATE game SET night_open=false WHERE id=1;
 ELSIF p_action='reopenNight' THEN
   IF n.status IS DISTINCT FROM 'closed' THEN RETURN jsonb_build_object('ok',false,'error','Night cannot be reopened.'); END IF;
   UPDATE night_rounds SET status='open' WHERE round=g.night_round;
   UPDATE game SET night_open=true WHERE id=1;
 ELSIF p_action='cancelNight' THEN
   IF n.status IS NULL OR n.status NOT IN ('open','closed') THEN RETURN jsonb_build_object('ok',false,'error','No pending night.'); END IF;
   UPDATE night_rounds SET status='cancelled' WHERE round=g.night_round;
   UPDATE game SET night_open=false WHERE id=1;
 ELSIF p_action='resolveNight' THEN
   IF n.status IS DISTINCT FROM 'closed' THEN RETURN jsonb_build_object('ok',false,'error','Close choices before approving the night.'); END IF;
   IF p_target IS NOT NULL THEN
     SELECT * INTO t FROM players WHERE id=p_target;
     IF t.id IS NULL OR t.kicked OR NOT t.alive OR t.role IS NULL THEN RETURN jsonb_build_object('ok',false,'error','Invalid victim.'); END IF;
   END IF;
   protected := p_target IS NOT NULL AND EXISTS(SELECT 1 FROM night_actions na JOIN players pl ON pl.id=na.player_id WHERE na.round=g.night_round AND na.role='doctor' AND pl.alive AND NOT pl.kicked AND na.target_id=p_target);
   FOR a IN SELECT na.* FROM night_actions na JOIN players pl ON pl.id=na.player_id JOIN players target ON target.id=na.target_id WHERE na.round=g.night_round AND pl.alive AND NOT pl.kicked AND target.alive AND NOT target.kicked LOOP
     IF a.role='doctor' THEN
       UPDATE night_actions SET result=jsonb_build_object('saved',protected AND a.target_id=p_target,'attacked',p_target IS NOT NULL) WHERE round=a.round AND player_id=a.player_id;
     ELSIF a.role='detective' THEN
       UPDATE night_actions SET result=jsonb_build_object('isMafia',(SELECT role='mafia' FROM players WHERE id=a.target_id)) WHERE round=a.round AND player_id=a.player_id;
     END IF;
   END LOOP;
   UPDATE night_rounds SET status='resolved',victim_id=p_target,saved=protected WHERE round=g.night_round;
   IF p_target IS NOT NULL AND NOT protected THEN UPDATE players SET alive=false WHERE id=p_target; PERFORM _mafia_after_removal(t.role,false); END IF;
 ELSE RETURN jsonb_build_object('ok',false,'error','Unknown action.'); END IF;
 PERFORM _mafia_bump(); RETURN jsonb_build_object('ok',true);
END $$;
CREATE OR REPLACE FUNCTION public.mafia_state(p_token text,p_admin text) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE s jsonb; g game; p players; n night_rounds; own jsonb; feedback jsonb;
BEGIN
 s := _mafia_base_state(p_token,p_admin);
 SELECT * INTO g FROM game WHERE id=1;
 SELECT * INTO p FROM players WHERE token=p_token AND NOT kicked;
 SELECT * INTO n FROM night_rounds WHERE round=g.night_round;
 SELECT jsonb_build_object('targetId',a.target_id,'targetName',t.name) INTO own FROM night_actions a JOIN players t ON t.id=a.target_id WHERE a.round=g.night_round AND a.player_id=p.id;
 SELECT jsonb_build_object('round',a.round,'role',a.role,'targetName',t.name,'saved',a.result->'saved','attacked',a.result->'attacked','isMafia',a.result->'isMafia') INTO feedback FROM night_actions a JOIN night_rounds nr ON nr.round=a.round JOIN players t ON t.id=a.target_id WHERE a.player_id=p.id AND a.result IS NOT NULL AND nr.status='resolved' ORDER BY a.round DESC LIMIT 1;
 s := s || jsonb_build_object('night',jsonb_build_object('round',g.night_round,'open',g.night_open,'status',COALESCE(n.status,'idle'),'choice',own,'feedback',feedback));
 IF _mafia_is_admin(p_admin) THEN
 s := jsonb_set(s,'{admin}',(s->'admin') || jsonb_build_object('nightChoices',COALESCE((SELECT jsonb_agg(jsonb_build_object('playerId',a.player_id,'playerName',pl.name,'role',a.role,'targetId',a.target_id,'targetName',t.name,'active',pl.alive AND NOT pl.kicked AND t.alive AND NOT t.kicked) ORDER BY pl.joined_at) FROM night_actions a JOIN players pl ON pl.id=a.player_id JOIN players t ON t.id=a.target_id WHERE a.round=g.night_round),'[]'::jsonb),'nightOutcome',CASE WHEN n.status='resolved' THEN jsonb_build_object('victimName',(SELECT name FROM players WHERE id=n.victim_id),'saved',n.saved) END));
 END IF;
 RETURN s;
END $$;
CREATE OR REPLACE FUNCTION public.mafia_admin(p_admin text,p_action text,p_player uuid,p_value text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE g game; n night_rounds; r jsonb;
BEGIN
 IF NOT _mafia_is_admin(p_admin) THEN RETURN jsonb_build_object('ok',false,'error','Not authorized.'); END IF;
 PERFORM pg_advisory_xact_lock(4242);
 SELECT * INTO g FROM game WHERE id=1;
 SELECT * INTO n FROM night_rounds WHERE round=g.night_round;
 IF p_action IN ('startVote','eliminate','eliminateVoted') AND n.status IN ('open','closed') THEN RETURN jsonb_build_object('ok',false,'error','Resolve or cancel the night first.'); END IF;
 r := _mafia_base_admin(p_admin,p_action,p_player,p_value);
 IF r->>'ok'='true' AND p_action='reset' THEN
 DELETE FROM night_actions WHERE round>=0;
 DELETE FROM night_rounds WHERE round>=0;
 UPDATE game SET night_open=false WHERE id=1;
 END IF;
 IF (SELECT phase FROM game WHERE id=1)='ended' THEN
 UPDATE game SET night_open=false WHERE id=1;
 UPDATE night_rounds SET status='cancelled' WHERE round=g.night_round AND status IN ('open','closed');
 END IF;
 RETURN r;
END $$;
REVOKE ALL ON FUNCTION public._mafia_base_state(text,text),public._mafia_base_admin(text,text,uuid,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.mafia_night_action(text,uuid,integer),public.mafia_night_admin(text,text,uuid,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mafia_night_action(text,uuid,integer),public.mafia_night_admin(text,text,uuid,integer) TO anon,authenticated,service_role;