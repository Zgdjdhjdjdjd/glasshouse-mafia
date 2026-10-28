CREATE TABLE public.game (
  id int PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  phase text NOT NULL DEFAULT 'lobby',
  voting_open boolean NOT NULL DEFAULT false,
  vote_round int NOT NULL DEFAULT 0,
  last_result jsonb,
  result_used boolean NOT NULL DEFAULT false,
  winner text,
  reveal_roles boolean NOT NULL DEFAULT false,
  mafia_rule text NOT NULL DEFAULT 'gte',
  version int NOT NULL DEFAULT 0
);
INSERT INTO public.game (id) VALUES (1);
GRANT SELECT ON public.game TO anon, authenticated;
GRANT ALL ON public.game TO service_role;
ALTER TABLE public.game ENABLE ROW LEVEL SECURITY;
CREATE POLICY "public read game" ON public.game FOR SELECT TO anon, authenticated USING (true);

CREATE TABLE public.players (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  token text NOT NULL UNIQUE,
  name text NOT NULL,
  role text,
  alive boolean NOT NULL DEFAULT true,
  kicked boolean NOT NULL DEFAULT false,
  joined_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.players TO service_role;
ALTER TABLE public.players ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.votes (
  round int NOT NULL,
  voter_id uuid NOT NULL REFERENCES public.players(id) ON DELETE CASCADE,
  target_id uuid NOT NULL REFERENCES public.players(id) ON DELETE CASCADE,
  PRIMARY KEY (round, voter_id)
);
GRANT ALL ON public.votes TO service_role;
ALTER TABLE public.votes ENABLE ROW LEVEL SECURITY;

ALTER PUBLICATION supabase_realtime ADD TABLE public.game;