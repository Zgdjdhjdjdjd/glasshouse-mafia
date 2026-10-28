CREATE OR REPLACE FUNCTION public.mafia_admin(p_admin text, p_action text, p_player uuid, p_value text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE g game; p players; cnt int; tally jsonb; top jsonb; tid uuid; byvote boolean;
BEGIN
  IF NOT _mafia_is_admin(p_admin) THEN RETURN jsonb_build_object('ok', false, 'error', 'Not authorized.'); END IF;
  PERFORM pg_advisory_xact_lock(4242);
  SELECT * INTO g FROM game WHERE id = 1;

  IF p_action = 'start' THEN
    IF g.phase <> 'lobby' THEN RETURN jsonb_build_object('ok', false, 'error', 'Game already started.'); END IF;
    SELECT count(*) INTO cnt FROM players WHERE NOT kicked;
    IF cnt < 6 THEN RETURN jsonb_build_object('ok', false, 'error', 'Need at least 6 players.'); END IF;
    WITH shuffled AS (SELECT id, row_number() OVER (ORDER BY gen_random_uuid()) AS rn FROM players WHERE NOT kicked)
    UPDATE players pl SET alive = true, role = CASE WHEN s.rn <= 3 THEN 'mafia' WHEN s.rn = 4 THEN 'joker'
      WHEN s.rn = 5 THEN 'detective' WHEN s.rn = 6 THEN 'doctor' ELSE 'civilian' END
      FROM shuffled s WHERE pl.id = s.id;
    UPDATE game SET phase = 'playing', voting_open = false, last_result = NULL, result_used = false, winner = NULL WHERE id = 1;

  ELSIF p_action = 'reset' THEN
    DELETE FROM votes WHERE round >= 0;
    UPDATE players SET role = NULL, alive = true WHERE NOT kicked;
    UPDATE game SET phase = 'lobby', voting_open = false, last_result = NULL, result_used = false, winner = NULL, vote_round = 0 WHERE id = 1;

  ELSIF p_action = 'startVote' THEN
    IF g.phase <> 'playing' THEN RETURN jsonb_build_object('ok', false, 'error', 'No game in progress.'); END IF;
    UPDATE game SET voting_open = true, vote_round = g.vote_round + 1, last_result = NULL, result_used = false WHERE id = 1;

  ELSIF p_action = 'endVote' THEN
    IF NOT g.voting_open THEN RETURN jsonb_build_object('ok', false, 'error', 'Voting is not open.'); END IF;
    SELECT COALESCE(jsonb_object_agg(target_id::text, c), '{}'::jsonb) INTO tally
      FROM (SELECT target_id, count(*) c FROM votes WHERE round = g.vote_round GROUP BY target_id) s;
    SELECT COALESCE(jsonb_agg(target_id::text), '[]'::jsonb) INTO top FROM (
      SELECT target_id FROM votes WHERE round = g.vote_round GROUP BY target_id
      HAVING count(*) = (SELECT max(c) FROM (SELECT count(*) c FROM votes WHERE round = g.vote_round GROUP BY target_id) m)) s;
    UPDATE game SET voting_open = false, last_result = jsonb_build_object('totals', tally, 'top', top) WHERE id = 1;

  ELSIF p_action IN ('eliminate', 'eliminateVoted') THEN
    IF g.phase <> 'playing' THEN RETURN jsonb_build_object('ok', false, 'error', 'No game in progress.'); END IF;
    byvote := p_action = 'eliminateVoted';
    tid := p_player;
    IF byvote THEN
      IF g.voting_open OR g.result_used OR jsonb_array_length(COALESCE(g.last_result->'top', '[]')) <> 1 THEN
        RETURN jsonb_build_object('ok', false, 'error', 'No single vote winner to eliminate.');
      END IF;
      tid := (g.last_result->'top'->>0)::uuid;
    END IF;
    SELECT * INTO p FROM players WHERE id = tid;
    IF p.id IS NULL OR p.kicked OR NOT p.alive THEN RETURN jsonb_build_object('ok', false, 'error', 'Player is not alive.'); END IF;
    UPDATE players SET alive = false WHERE id = tid;
    IF g.voting_open THEN DELETE FROM votes WHERE round = g.vote_round AND (voter_id = tid OR target_id = tid); END IF;
    IF byvote THEN UPDATE game SET result_used = true WHERE id = 1; END IF;
    PERFORM _mafia_after_removal(p.role, byvote);
    RETURN jsonb_build_object('ok', true);

  ELSIF p_action = 'kick' THEN
    SELECT * INTO p FROM players WHERE id = p_player;
    IF p.id IS NULL OR p.kicked THEN RETURN jsonb_build_object('ok', false, 'error', 'Player not found.'); END IF;
    UPDATE players SET kicked = true, alive = false WHERE id = p.id;
    DELETE FROM votes WHERE voter_id = p.id OR target_id = p.id;
    PERFORM _mafia_after_removal(p.role, false);
    RETURN jsonb_build_object('ok', true);

  ELSIF p_action = 'setReveal' THEN
    UPDATE game SET reveal_roles = (p_value = 'true') WHERE id = 1;
  ELSIF p_action = 'setMafiaRule' THEN
    IF p_value NOT IN ('gte', 'gt') THEN RETURN jsonb_build_object('ok', false, 'error', 'Invalid rule.'); END IF;
    UPDATE game SET mafia_rule = p_value WHERE id = 1;
  ELSE
    RETURN jsonb_build_object('ok', false, 'error', 'Unknown action.');
  END IF;
  PERFORM _mafia_bump();
  RETURN jsonb_build_object('ok', true);
END $$;