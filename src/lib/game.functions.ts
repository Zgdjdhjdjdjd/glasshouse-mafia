import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import {
  assignRoles,
  checkVictory,
  MAX_PLAYERS,
  MIN_PLAYERS,
  tallyVotes,
  type MafiaRule,
  type Role,
} from "./game-logic";

async function db() {
  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  return supabaseAdmin;
}

async function hmac(key: string, msg: string) {
  const k = await crypto.subtle.importKey("raw", new TextEncoder().encode(key), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(msg));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, "0")).join("");
}
function safeEq(a: string, b: string) {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}
async function expectedAdminToken() {
  const code = process.env["ADMIN_CODE"];
  if (!code) throw new Error("Admin code is not configured on the server");
  return hmac(code, "mafia-admin-session-v1");
}
async function isAdmin(token?: string | null) {
  if (!token) return false;
  return safeEq(token, await expectedAdminToken());
}

type GameRow = {
  phase: string; voting_open: boolean; vote_round: number; last_result: any;
  result_used: boolean; winner: string | null; reveal_roles: boolean; mafia_rule: string; version: number;
};

async function getGame(): Promise<GameRow> {
  const { data, error } = await (await db()).from("game").select("*").eq("id", 1).single();
  if (error) throw new Error(error.message);
  return data as GameRow;
}
async function updateGame(patch: Partial<GameRow>) {
  const g = await getGame();
  const { error } = await (await db()).from("game").update({ ...patch, version: g.version + 1 }).eq("id", 1);
  if (error) throw new Error(error.message);
}
async function bump() {
  await updateGame({});
}

/** After elimination/kick, check victory and update game. */
async function afterRemoval(eliminated?: { role: Role; byVote: boolean }) {
  const g = await getGame();
  if (g.phase !== "playing") return bump();
  const { data } = await (await db()).from("players").select("role").eq("alive", true).eq("kicked", false);
  const alive = (data ?? []).map((p) => p.role as Role).filter(Boolean);
  const w = checkVictory(alive, g.mafia_rule as MafiaRule, eliminated);
  if (w) await updateGame({ phase: "ended", winner: w, voting_open: false });
  else await bump();
}

const tokenSchema = z.string().min(16).max(100);

export const getState = createServerFn({ method: "POST" })
  .inputValidator((d) => z.object({ token: tokenSchema.nullable(), adminToken: z.string().max(200).nullable() }).parse(d))
  .handler(async ({ data }) => {
    const sb = await db();
    const g = await getGame();
    const { data: rows } = await sb.from("players").select("*").order("joined_at");
    const all = rows ?? [];
    const active = all.filter((p) => !p.kicked);
    const meRow = data.token ? all.find((p) => p.token === data.token) : undefined;
    let hasVoted = false;
    if (meRow && g.voting_open) {
      const { data: v } = await sb.from("votes").select("voter_id").eq("round", g.vote_round).eq("voter_id", meRow.id);
      hasVoted = (v ?? []).length > 0;
    }
    const nameOf = (id: string) => all.find((p) => p.id === id)?.name ?? "?";
    const showRoles = g.reveal_roles;
    const players = active.map((p) => ({
      id: p.id,
      name: p.name,
      alive: p.alive,
      revealedRole: showRoles && !p.alive ? p.role : null,
    }));
    const lastResult = g.last_result && !g.voting_open
      ? {
          totals: Object.entries(g.last_result.totals as Record<string, number>).map(([id, n]) => ({ id, name: nameOf(id), votes: n })),
          top: (g.last_result.top as string[]).map((id) => ({ id, name: nameOf(id) })),
          used: g.result_used,
        }
      : null;

    let admin = null as null | {
      players: { id: string; name: string; role: string | null; alive: boolean }[];
      counters: Record<Role, number>;
      liveTotals: { id: string; name: string; votes: number }[];
      votesCast: number;
      eligibleVoters: number;
    };
    if (await isAdmin(data.adminToken)) {
      const counters: Record<Role, number> = { mafia: 0, civilian: 0, detective: 0, doctor: 0, joker: 0 };
      for (const p of active) if (p.alive && p.role) counters[p.role as Role]++;
      let liveTotals: { id: string; name: string; votes: number }[] = [];
      let votesCast = 0;
      if (g.voting_open) {
        const { data: v } = await sb.from("votes").select("target_id").eq("round", g.vote_round);
        const t = tallyVotes(v ?? []);
        votesCast = (v ?? []).length;
        liveTotals = active.filter((p) => p.alive).map((p) => ({ id: p.id, name: p.name, votes: t.totals[p.id] ?? 0 }));
      }
      admin = {
        players: active.map((p) => ({ id: p.id, name: p.name, role: p.role, alive: p.alive })),
        counters,
        liveTotals,
        votesCast,
        eligibleVoters: active.filter((p) => p.alive).length,
      };
    }

    return {
      game: {
        phase: g.phase, votingOpen: g.voting_open, voteRound: g.vote_round, winner: g.winner,
        revealRoles: g.reveal_roles, mafiaRule: g.mafia_rule, version: g.version,
      },
      players,
      me: meRow
        ? { id: meRow.id, name: meRow.name, alive: meRow.alive, kicked: meRow.kicked, role: g.phase !== "lobby" && !meRow.kicked ? meRow.role : null, hasVoted }
        : null,
      lastResult,
      admin,
    };
  });

export const joinRoom = createServerFn({ method: "POST" })
  .inputValidator((d) => z.object({ token: tokenSchema, name: z.string().trim().min(1).max(24) }).parse(d))
  .handler(async ({ data }) => {
    const sb = await db();
    const { data: existing } = await sb.from("players").select("*").eq("token", data.token).maybeSingle();
    if (existing) {
      if (existing.kicked) return { ok: false, error: "You were removed from this room." };
      return { ok: true };
    }
    const { data: active } = await sb.from("players").select("name").eq("kicked", false);
    if ((active ?? []).length >= MAX_PLAYERS) return { ok: false, error: "The room is full (23/23)." };
    if ((active ?? []).some((p) => p.name.toLowerCase() === data.name.toLowerCase()))
      return { ok: false, error: "That name is already taken." };
    const g = await getGame();
    // Late joiners during a game get no role and join as spectators.
    const { error } = await sb.from("players").insert({ token: data.token, name: data.name, alive: g.phase === "lobby" });
    if (error) return { ok: false, error: "Could not join. Try again." };
    await bump();
    return { ok: true };
  });

export const castVote = createServerFn({ method: "POST" })
  .inputValidator((d) => z.object({ token: tokenSchema, targetId: z.string().uuid() }).parse(d))
  .handler(async ({ data }) => {
    const sb = await db();
    const g = await getGame();
    if (!g.voting_open || g.phase !== "playing") return { ok: false, error: "Voting is closed." };
    const { data: me } = await sb.from("players").select("*").eq("token", data.token).maybeSingle();
    if (!me || me.kicked || !me.alive || !me.role) return { ok: false, error: "You can't vote." };
    if (me.id === data.targetId) return { ok: false, error: "You can't vote for yourself." };
    const { data: t } = await sb.from("players").select("*").eq("id", data.targetId).maybeSingle();
    if (!t || t.kicked || !t.alive) return { ok: false, error: "Invalid candidate." };
    const { error } = await sb.from("votes").insert({ round: g.vote_round, voter_id: me.id, target_id: t.id });
    if (error) return { ok: false, error: "You already voted this round." };
    await bump();
    return { ok: true };
  });

export const adminUnlock = createServerFn({ method: "POST" })
  .inputValidator((d) => z.object({ code: z.string().min(1).max(200) }).parse(d))
  .handler(async ({ data }) => {
    const code = process.env["ADMIN_CODE"] ?? "";
    await new Promise((r) => setTimeout(r, 400));
    if (!code || !safeEq(data.code, code)) return { ok: false as const, error: "Wrong code." };
    return { ok: true as const, adminToken: await expectedAdminToken() };
  });

export const adminAction = createServerFn({ method: "POST" })
  .inputValidator((d) =>
    z.object({
      adminToken: z.string().max(200),
      action: z.enum(["start", "reset", "startVote", "endVote", "eliminate", "eliminateVoted", "kick", "setReveal", "setMafiaRule"]),
      playerId: z.string().uuid().optional(),
      value: z.string().optional(),
    }).parse(d),
  )
  .handler(async ({ data }) => {
    if (!(await isAdmin(data.adminToken))) return { ok: false, error: "Not authorized." };
    const sb = await db();
    const g = await getGame();

    switch (data.action) {
      case "start": {
        if (g.phase !== "lobby") return { ok: false, error: "Game already started." };
        const { data: ps } = await sb.from("players").select("id").eq("kicked", false);
        const list = ps ?? [];
        if (list.length < MIN_PLAYERS) return { ok: false, error: `Need at least ${MIN_PLAYERS} players.` };
        const roles = assignRoles(list.length);
        for (let i = 0; i < list.length; i++) {
          await sb.from("players").update({ role: roles[i]!, alive: true }).eq("id", list[i]!.id);
        }
        await updateGame({ phase: "playing", voting_open: false, last_result: null, result_used: false, winner: null });
        return { ok: true };
      }
      case "reset": {
        await sb.from("votes").delete().gte("round", 0);
        await sb.from("players").update({ role: null, alive: true }).eq("kicked", false);
        await updateGame({ phase: "lobby", voting_open: false, last_result: null, result_used: false, winner: null, vote_round: 0 });
        return { ok: true };
      }
      case "startVote": {
        if (g.phase !== "playing") return { ok: false, error: "No game in progress." };
        await updateGame({ voting_open: true, vote_round: g.vote_round + 1, last_result: null, result_used: false });
        return { ok: true };
      }
      case "endVote": {
        if (!g.voting_open) return { ok: false, error: "Voting is not open." };
        const { data: v } = await sb.from("votes").select("target_id").eq("round", g.vote_round);
        const t = tallyVotes(v ?? []);
        await updateGame({ voting_open: false, last_result: { totals: t.totals, top: t.top } });
        return { ok: true };
      }
      case "eliminate":
      case "eliminateVoted": {
        if (g.phase !== "playing") return { ok: false, error: "No game in progress." };
        let id = data.playerId;
        const byVote = data.action === "eliminateVoted";
        if (byVote) {
          const top = (g.last_result?.top ?? []) as string[];
          if (g.voting_open || g.result_used || top.length !== 1) return { ok: false, error: "No single vote winner to eliminate." };
          id = top[0];
        }
        if (!id) return { ok: false, error: "No player selected." };
        const { data: p } = await sb.from("players").select("*").eq("id", id).maybeSingle();
        if (!p || p.kicked || !p.alive) return { ok: false, error: "Player is not alive." };
        await sb.from("players").update({ alive: false }).eq("id", id);
        if (g.voting_open) await sb.from("votes").delete().eq("round", g.vote_round).or(`voter_id.eq.${id},target_id.eq.${id}`);
        if (byVote) await (await db()).from("game").update({ result_used: true }).eq("id", 1);
        await afterRemoval(p.role ? { role: p.role as Role, byVote } : undefined);
        return { ok: true };
      }
      case "kick": {
        if (!data.playerId) return { ok: false, error: "No player selected." };
        const { data: p } = await sb.from("players").select("*").eq("id", data.playerId).maybeSingle();
        if (!p || p.kicked) return { ok: false, error: "Player not found." };
        await sb.from("players").update({ kicked: true, alive: false }).eq("id", p.id);
        await sb.from("votes").delete().or(`voter_id.eq.${p.id},target_id.eq.${p.id}`);
        await afterRemoval(p.role ? { role: p.role as Role, byVote: false } : undefined);
        return { ok: true };
      }
      case "setReveal":
        await updateGame({ reveal_roles: data.value === "true" });
        return { ok: true };
      case "setMafiaRule":
        if (data.value !== "gte" && data.value !== "gt") return { ok: false, error: "Invalid rule." };
        await updateGame({ mafia_rule: data.value });
        return { ok: true };
    }
  });
