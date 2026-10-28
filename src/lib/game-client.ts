import { createClient } from "@supabase/supabase-js";

// Public (publishable) connection details — safe to ship to browsers.
// Hardcoded with the direct backend address so the app works on any host (e.g. Vercel)
// without extra environment variables. All game rules and secrecy are enforced by
// database functions; the players/votes tables are not readable with this key.
const URL = "https://qpcosfjsvqkvbcmyhtfo.supabase.co";
const KEY = "sb_publishable_oyBQ3_lRguUJceFzMIUHog_KfDOHBDo";

export const gameDb = createClient(URL, KEY, {
  auth: { persistSession: false, autoRefreshToken: false, storage: undefined },
  global: {
    fetch: (input, init) => {
      const h = new Headers(init?.headers);
      if (h.get("Authorization") === `Bearer ${KEY}`) h.delete("Authorization");
      h.set("apikey", KEY);
      return fetch(input, { ...init, headers: h });
    },
  },
});

export type Result = { ok: boolean; error?: string; adminToken?: string };

export type State = {
  game: { phase: string; votingOpen: boolean; voteRound: number; winner: string | null; revealRoles: boolean; mafiaRule: string; version: number };
  players: { id: string; name: string; alive: boolean; revealedRole: string | null }[];
  me: { id: string; name: string; alive: boolean; kicked: boolean; role: string | null; hasVoted: boolean } | null;
  lastResult: { totals: { id: string; name: string; votes: number }[]; top: { id: string; name: string }[]; used: boolean } | null;
  admin: null | {
    players: { id: string; name: string; role: string | null; alive: boolean }[];
    counters: Record<"mafia" | "civilian" | "detective" | "doctor" | "joker", number>;
    liveTotals: { id: string; name: string; votes: number }[];
    votesCast: number;
    eligibleVoters: number;
  };
};

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await gameDb.rpc(fn as never, args as never);
  if (error) throw new Error(error.message);
  return data as T;
}

export const api = {
  state: (token: string | null, adminToken: string | null) => rpc<State>("mafia_state", { p_token: token, p_admin: adminToken }),
  join: (token: string, name: string) => rpc<Result>("mafia_join", { p_token: token, p_name: name }),
  vote: (token: string, targetId: string) => rpc<Result>("mafia_vote", { p_token: token, p_target: targetId }),
  unlock: (code: string) => rpc<Result>("mafia_admin_unlock", { p_code: code }),
  admin: (adminToken: string, action: string, playerId?: string, value?: string) =>
    rpc<Result>("mafia_admin", { p_admin: adminToken, p_action: action, p_player: playerId ?? null, p_value: value ?? null }),
};
