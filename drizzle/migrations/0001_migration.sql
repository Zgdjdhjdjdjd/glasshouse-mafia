CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

CREATE TABLE public.admin_config (id int PRIMARY KEY DEFAULT 1 CHECK (id = 1), code_hash text NOT NULL);
GRANT ALL ON public.admin_config TO service_role;
ALTER TABLE public.admin_config ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.admin_sessions (token text PRIMARY KEY, created_at timestamptz NOT NULL DEFAULT now());
GRANT ALL ON public.admin_sessions TO service_role;
ALTER TABLE public.admin_sessions ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public._mafia_hash(t text) RETURNS text LANGUAGE sql IMMUTABLE SET search_path = public, extensions
AS $$ SELECT encode(extensions.digest(t, 'sha256'), 'hex') $$;

CREATE OR REPLACE FUNCTION public._mafia_is_admin(p_admin text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions
AS $$ SELECT p_admin IS NOT NULL AND EXISTS (SELECT 1 FROM admin_sessions WHERE token = _mafia_hash(p_admin)) $$;

CREATE OR REPLACE FUNCTION public._mafia_bump() RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$ UPDATE game SET version = version + 1 WHERE id = 1 $$;

CREATE OR REPLACE FUNCTION public._mafia_after_removal(p_role text, p_byvote boolean) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE g game; m int; o int; w text := NULL;
BEGIN
  SELECT * INTO g FROM game WHERE id = 1;
  IF g.phase = 'playing' THEN
    SELECT count(*) FILTER (WHERE role = 'mafia'), count(*) FILTER (WHERE role <> 'mafia')
      INTO m, o FROM players WHERE alive AND NOT kicked AND role IS NOT NULL;
    IF p_role = 'joker' AND p_byvote THEN w := 'joker';
    ELSIF m = 0 THEN w := 'town';
    ELSIF (g.mafia_rule = 'gte' AND m >= o) OR (g.mafia_rule = 'gt' AND m > o) THEN w := 'mafia';
    END IF;
    IF w IS NOT NULL THEN UPDATE game SET phase = 'ended', winner = w, voting_open = false WHERE id = 1; END IF;
  END IF;
  PERFORM _mafia_bump();
END $$;

CREATE OR REPLACE FUNCTION public.mafia_set_admin_code(p_code text) RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public, extensions
AS $$
  INSERT INTO admin_config (id, code_hash) VALUES (1, _mafia_hash(p_code))
  ON CONFLICT (id) DO UPDATE SET code_hash = excluded.code_hash;
  DELETE FROM admin_sessions;
$$;

CREATE OR REPLACE FUNCTION public.mafia_admin_unlock(p_code text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $$
DECLARE t text;
BEGIN
  PERFORM pg_sleep(0.4);
  IF p_code IS NULL OR NOT EXISTS (SELECT 1 FROM admin_config WHERE code_hash = _mafia_hash(p_code)) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Wrong code.');
  END IF;
  t := encode(extensions.gen_random_bytes(32), 'hex');
  INSERT INTO admin_sessions (token) VALUES (_mafia_hash(t));
  RETURN jsonb_build_object('ok', true, 'adminToken', t);
END $$;

CREATE OR REPLACE FUNCTION public.mafia_state(p_token text, p_admin text) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE g game; me players; has_voted boolean := false; res jsonb := NULL; adm jsonb := NULL;
BEGIN
  SELECT * INTO g FROM game WHERE id = 1;
  IF p_token IS NOT NULL THEN SELECT * INTO me FROM players WHERE token = p_token; END IF;
  IF me.id IS NOT NULL AND g.voting_open THEN
    has_voted := EXISTS (SELECT 1 FROM votes WHERE round = g.vote_round AND voter_id = me.id);
  END IF;
  IF g.last_result IS NOT NULL AND NOT g.voting_open THEN
    res := jsonb_build_object(
      'totals', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', k, 'name', COALESCE((SELECT name FROM players WHERE id::text = k), '?'), 'votes', v::int))
                 FROM jsonb_each_text(g.last_result->'totals') AS e(k, v)), '[]'::jsonb),
      'top', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', x, 'name', COALESCE((SELECT name FROM players WHERE id::text = x), '?')))
                 FROM jsonb_array_elements_text(g.last_result->'top') AS t(x)), '[]'::jsonb),
      'used', g.result_used);
  END IF;
  IF _mafia_is_admin(p_admin) THEN
    adm := jsonb_build_object(
      'players', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', id, 'name', name, 'role', role, 'alive', alive) ORDER BY joined_at) FROM players WHERE NOT kicked), '[]'::jsonb),
      'counters', jsonb_build_object(
        'mafia', (SELECT count(*) FROM players WHERE NOT kicked AND alive AND role = 'mafia'),
        'civilian', (SELECT count(*) FROM players WHERE NOT kicked AND alive AND role = 'civilian'),
        'detective', (SELECT count(*) FROM players WHERE NOT kicked AND alive AND role = 'detective'),
        'doctor', (SELECT count(*) FROM players WHERE NOT kicked AND alive AND role = 'doctor'),
        'joker', (SELECT count(*) FROM players WHERE NOT kicked AND alive AND role = 'joker')),
      'liveTotals', CASE WHEN g.voting_open THEN COALESCE((SELECT jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name,
            'votes', (SELECT count(*) FROM votes v WHERE v.round = g.vote_round AND v.target_id = p.id)) ORDER BY p.joined_at)
          FROM players p WHERE NOT p.kicked AND p.alive), '[]'::jsonb) ELSE '[]'::jsonb END,
      'votesCast', CASE WHEN g.voting_open THEN (SELECT count(*) FROM votes WHERE round = g.vote_round) ELSE 0 END,
      'eligibleVoters', (SELECT count(*) FROM players WHERE NOT kicked AND alive AND role IS NOT NULL));
  END IF;
  RETURN jsonb_build_object(
    'game', jsonb_build_object('phase', g.phase, 'votingOpen', g.voting_open, 'voteRound', g.vote_round, 'winner', g.winner,
      'revealRoles', g.reveal_roles, 'mafiaRule', g.mafia_rule, 'version', g.version),
    'players', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', id, 'name', name, 'alive', alive,
        'revealedRole', CASE WHEN g.reveal_roles AND NOT alive THEN role END) ORDER BY joined_at) FROM players WHERE NOT kicked), '[]'::jsonb),
    'me', CASE WHEN me.id IS NULL THEN NULL ELSE jsonb_build_object('id', me.id, 'name', me.name, 'alive', me.alive, 'kicked', me.kicked,
        'role', CASE WHEN g.phase <> 'lobby' AND NOT me.kicked THEN me.role END, 'hasVoted', has_voted) END,
    'lastResult', res,
    'admin', adm);
END $$;

CREATE OR REPLACE FUNCTION public.mafia_join(p_token text, p_name text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE ex players; n text := btrim(p_name); g game;
BEGIN
  IF p_token IS NULL OR length(p_token) < 16 OR length(p_token) > 100 THEN RETURN jsonb_build_object('ok', false, 'error', 'Invalid session.'); END IF;
  IF n IS NULL OR length(n) < 1 OR length(n) > 24 THEN RETURN jsonb_build_object('ok', false, 'error', 'Name must be 1–24 characters.'); END IF;
  PERFORM pg_advisory_xact_lock(4242);
  SELECT * INTO ex FROM players WHERE token = p_token;
  IF ex.id IS NOT NULL THEN
    IF ex.kicked THEN RETURN jsonb_build_object('ok', false, 'error', 'You were removed from this room.'); END IF;
    RETURN jsonb_build_object('ok', true);
  END IF;
  IF (SELECT count(*) FROM players WHERE NOT kicked) >= 23 THEN RETURN jsonb_build_object('ok', false, 'error', 'The room is full (23/23).'); END IF;
  IF EXISTS (SELECT 1 FROM players WHERE NOT kicked AND lower(name) = lower(n)) THEN RETURN jsonb_build_object('ok', false, 'error', 'That name is already taken.'); END IF;
  SELECT * INTO g FROM game WHERE id = 1;
  INSERT INTO players (token, name, alive) VALUES (p_token, n, g.phase = 'lobby');
  PERFORM _mafia_bump();
  RETURN jsonb_build_object('ok', true);
END $$;

CREATE OR REPLACE FUNCTION public.mafia_vote(p_token text, p_target uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE g game; me players; t players;
BEGIN
  SELECT * INTO g FROM game WHERE id = 1;
  IF NOT g.voting_open OR g.phase <> 'playing' THEN RETURN jsonb_build_object('ok', false, 'error', 'Voting is closed.'); END IF;
  SELECT * INTO me FROM players WHERE token = p_token;
  IF me.id IS NULL OR me.kicked OR NOT me.alive OR me.role IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'You can''t vote.'); END IF;
  IF me.id = p_target THEN RETURN jsonb_build_object('ok', false, 'error', 'You can''t vote for yourself.'); END IF;
  SELECT * INTO t FROM players WHERE id = p_target;
  IF t.id IS NULL OR t.kicked OR NOT t.alive THEN RETURN jsonb_build_object('ok', false, 'error', 'Invalid candidate.'); END IF;
  INSERT INTO votes (round, voter_id, target_id) VALUES (g.vote_round, me.id, t.id) ON CONFLICT DO NOTHING;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'You already voted this round.'); END IF;
  PERFORM _mafia_bump();
  RETURN jsonb_build_object('ok', true);
END $$;

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

REVOKE ALL ON FUNCTION public._mafia_hash(text), public._mafia_is_admin(text), public._mafia_bump(), public._mafia_after_removal(text, boolean), public.mafia_set_admin_code(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mafia_set_admin_code(text) TO service_role;
REVOKE ALL ON FUNCTION public.mafia_state(text, text), public.mafia_join(text, text), public.mafia_vote(text, uuid), public.mafia_admin_unlock(text), public.mafia_admin(text, text, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mafia_state(text, text), public.mafia_join(text, text), public.mafia_vote(text, uuid), public.mafia_admin_unlock(text), public.mafia_admin(text, text, uuid, text) TO anon, authenticated, service_role;