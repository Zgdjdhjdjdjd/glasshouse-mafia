import { createFileRoute } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import { useCallback, useEffect, useRef, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { adminAction, adminUnlock, castVote, getState, joinRoom } from "@/lib/game.functions";
import { ROLE_INFO, WINNER_TEXT } from "@/lib/roles";
import { MAX_PLAYERS, MIN_PLAYERS } from "@/lib/game-logic";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "Mafia — Join the Room" },
      { name: "description", content: "A simple live multiplayer Mafia game for up to 23 players." },
      { property: "og:title", content: "Mafia — Join the Room" },
      { property: "og:description", content: "A simple live multiplayer Mafia game for up to 23 players." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: Game,
});

type State = Awaited<ReturnType<typeof getState>>;

function getToken() {
  let t = localStorage.getItem("mafia_token");
  if (!t) {
    t = crypto.randomUUID() + crypto.randomUUID();
    localStorage.setItem("mafia_token", t);
  }
  return t;
}

function Game() {
  const fetchState = useServerFn(getState);
  const join = useServerFn(joinRoom);
  const vote = useServerFn(castVote);
  const unlock = useServerFn(adminUnlock);
  const act = useServerFn(adminAction);

  const [token, setToken] = useState<string | null>(null);
  const [adminToken, setAdminToken] = useState<string | null>(null);
  const [state, setState] = useState<State | null>(null);
  const [showAdmin, setShowAdmin] = useState(false);
  const [err, setErr] = useState("");
  const busy = useRef(false);

  useEffect(() => {
    setToken(getToken());
    setAdminToken(localStorage.getItem("mafia_admin"));
  }, []);

  const refresh = useCallback(async () => {
    if (!token) return;
    try {
      const s = await fetchState({ data: { token, adminToken } });
      setState(s);
      if (adminToken && !s.admin) {
        localStorage.removeItem("mafia_admin");
        setAdminToken(null);
      }
    } catch {
      /* keep last state; retry on next tick */
    }
  }, [token, adminToken, fetchState]);

  useEffect(() => {
    if (!token) return;
    refresh();
    const ch = supabase
      .channel(`game-${Math.random().toString(36).slice(2)}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "game" }, () => refresh())
      .subscribe();
    const iv = setInterval(refresh, 4000);
    return () => {
      supabase.removeChannel(ch);
      clearInterval(iv);
    };
  }, [token, refresh]);

  const run = async (fn: () => Promise<{ ok: boolean; error?: string } | undefined>) => {
    if (busy.current) return;
    busy.current = true;
    setErr("");
    try {
      const r = await fn();
      if (r && !r.ok) setErr(r.error ?? "Something went wrong.");
      await refresh();
    } catch {
      setErr("Connection problem. Please try again.");
    } finally {
      busy.current = false;
    }
  };

  const admin = state?.admin;
  const me = state?.me;

  return (
    <main className="mx-auto flex min-h-screen max-w-3xl flex-col gap-4 px-4 py-6">
      <header className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold tracking-tight">Mafia</h1>
        {admin ? (
          <button className="glass-btn text-sm" onClick={() => setShowAdmin((v) => !v)}>
            {showAdmin ? "Player view" : "Admin dashboard"}
          </button>
        ) : (
          <AdminUnlock
            onUnlock={async (code) => {
              const r = await unlock({ data: { code } });
              if (r.ok) {
                localStorage.setItem("mafia_admin", r.adminToken);
                setAdminToken(r.adminToken);
                setShowAdmin(true);
                return null;
              }
              return r.error;
            }}
          />
        )}
      </header>

      {err && <div className="glass px-4 py-3 text-sm text-destructive">{err}</div>}

      {!state ? (
        <div className="glass p-6 text-center text-muted-foreground">Connecting…</div>
      ) : admin && showAdmin ? (
        <AdminDashboard state={state} act={(action, playerId, value) => run(() => act({ data: { adminToken: adminToken!, action, playerId, value } }))} />
      ) : !me || me.kicked ? (
        me?.kicked ? (
          <div className="glass p-6 text-center">You were removed from this room by the admin.</div>
        ) : admin ? (
          <div className="glass p-6 text-center text-muted-foreground">You're the admin. Open the dashboard to manage the game.</div>
        ) : (
          <JoinScreen count={state.players.length} onJoin={(name) => run(() => join({ data: { token: token!, name } }))} />
        )
      ) : (
        <PlayerView state={state} onVote={(targetId) => run(() => vote({ data: { token: token!, targetId } }))} />
      )}
    </main>
  );
}

function AdminUnlock({ onUnlock }: { onUnlock: (code: string) => Promise<string | null | undefined> }) {
  const [open, setOpen] = useState(false);
  const [code, setCode] = useState("");
  const [msg, setMsg] = useState("");
  if (!open)
    return (
      <button className="glass-btn text-sm" onClick={() => setOpen(true)}>
        Admin
      </button>
    );
  return (
    <form
      className="flex items-center gap-2"
      onSubmit={async (e) => {
        e.preventDefault();
        setMsg("");
        const r = await onUnlock(code);
        if (r) setMsg(r);
      }}
    >
      <input
        type="password"
        autoFocus
        value={code}
        onChange={(e) => setCode(e.target.value)}
        placeholder={msg || "Admin code"}
        className="w-32 rounded-full border border-input bg-muted px-4 py-2 text-sm outline-none placeholder:text-muted-foreground focus:border-ring"
      />
      <button className="glass-btn glass-btn-primary text-sm">Unlock</button>
    </form>
  );
}

function JoinScreen({ count, onJoin }: { count: number; onJoin: (name: string) => void }) {
  const [name, setName] = useState("");
  return (
    <section className="glass fade-in mx-auto mt-10 w-full max-w-sm p-6">
      <h2 className="text-xl font-semibold">Join the room</h2>
      <p className="mt-1 text-sm text-muted-foreground">{count}/{MAX_PLAYERS} players</p>
      <form
        className="mt-5 flex flex-col gap-3"
        onSubmit={(e) => {
          e.preventDefault();
          if (name.trim()) onJoin(name.trim());
        }}
      >
        <input
          value={name}
          maxLength={24}
          onChange={(e) => setName(e.target.value)}
          placeholder="Your display name"
          className="rounded-full border border-input bg-muted px-5 py-3 outline-none placeholder:text-muted-foreground focus:border-ring"
        />
        <button className="glass-btn glass-btn-primary" disabled={!name.trim() || count >= MAX_PLAYERS}>
          Join
        </button>
      </form>
    </section>
  );
}

function PlayerList({ state }: { state: State }) {
  return (
    <section className="glass p-5">
      <div className="mb-3 flex items-center justify-between">
        <h2 className="font-semibold">Players</h2>
        <span className="text-sm text-muted-foreground">{state.players.length}/{MAX_PLAYERS}</span>
      </div>
      <ul className="grid grid-cols-2 gap-2 sm:grid-cols-3">
        {state.players.map((p) => (
          <li key={p.id} className={`rounded-xl bg-muted px-3 py-2 text-sm ${p.alive ? "" : "text-muted-foreground line-through"}`}>
            {p.name}
            {p.id === state.me?.id && " (you)"}
            {p.revealedRole && <span className="ml-1 no-underline">· {ROLE_INFO[p.revealedRole]?.name}</span>}
          </li>
        ))}
      </ul>
    </section>
  );
}

function PlayerView({ state, onVote }: { state: State; onVote: (id: string) => void }) {
  const { game, me } = state;
  const [revealed, setRevealed] = useState(false);
  const [choice, setChoice] = useState<string | null>(null);
  useEffect(() => setChoice(null), [game.voteRound]);

  if (!me) return null;

  if (game.phase === "lobby")
    return (
      <div className="flex flex-col gap-4 fade-in">
        <section className="glass p-6 text-center">
          <h2 className="text-xl font-semibold">Waiting for the admin</h2>
          <p className="mt-1 text-sm text-muted-foreground">
            The game starts when the admin is ready (minimum {MIN_PLAYERS} players).
          </p>
        </section>
        <PlayerList state={state} />
      </div>
    );

  const info = me.role ? ROLE_INFO[me.role] : null;

  return (
    <div className="flex flex-col gap-4 fade-in">
      {game.phase === "ended" && game.winner && (
        <section className="glass p-6 text-center">
          <p className="text-sm uppercase tracking-widest text-muted-foreground">Game over</p>
          <h2 className="mt-2 text-2xl font-semibold">{WINNER_TEXT[game.winner]}</h2>
          <p className="mt-2 text-sm text-muted-foreground">Waiting for the admin to reset.</p>
        </section>
      )}

      {game.votingOpen && game.phase === "playing" && (
        <section className="glass p-5">
          <h2 className="font-semibold">Vote — round {game.voteRound}</h2>
          {!me.alive || !me.role ? (
            <p className="mt-2 text-sm text-muted-foreground">You can't vote this round.</p>
          ) : me.hasVoted ? (
            <p className="mt-2 text-sm text-success">Your vote is in. Waiting for results…</p>
          ) : (
            <>
              <div className="mt-3 grid grid-cols-2 gap-2 sm:grid-cols-3">
                {state.players.filter((p) => p.alive && p.id !== me.id).map((p) => (
                  <button
                    key={p.id}
                    onClick={() => setChoice(p.id)}
                    className={`glass-btn text-sm ${choice === p.id ? "glass-btn-primary" : ""}`}
                  >
                    {p.name}
                  </button>
                ))}
              </div>
              <button className="glass-btn glass-btn-primary mt-4 w-full" disabled={!choice} onClick={() => choice && onVote(choice)}>
                Submit vote
              </button>
            </>
          )}
        </section>
      )}

      {state.lastResult && <VoteResults result={state.lastResult} />}

      <section className="glass p-6 text-center">
        {!me.role ? (
          <p className="text-muted-foreground">A game is in progress. You'll join the next one.</p>
        ) : !revealed ? (
          <button className="glass-btn glass-btn-primary" onClick={() => setRevealed(true)}>
            REVEAL MY CARD
          </button>
        ) : (
          info && (
            <div className="fade-in">
              <div className="text-6xl">{info.icon}</div>
              <h2 className="mt-3 text-2xl font-semibold">{info.name}</h2>
              <p className="text-sm text-muted-foreground">Team: {info.team}</p>
              <p className="mx-auto mt-3 max-w-sm text-sm">{info.desc}</p>
              {!me.alive && <p className="mt-3 text-sm text-destructive">You have been eliminated.</p>}
              <button className="glass-btn mt-4 text-sm" onClick={() => setRevealed(false)}>Hide card</button>
            </div>
          )
        )}
      </section>

      <PlayerList state={state} />
    </div>
  );
}

function VoteResults({ result }: { result: NonNullable<State["lastResult"]> }) {
  const sorted = [...result.totals].sort((a, b) => b.votes - a.votes);
  return (
    <section className="glass p-5">
      <h2 className="font-semibold">Vote results</h2>
      <p className="mt-1 text-lg">
        {result.top.length === 0
          ? "No votes were cast."
          : result.top.length === 1
            ? `Most votes: ${result.top[0].name}`
            : `Tie between ${result.top.map((t) => t.name).join(", ")}`}
      </p>
      <ul className="mt-3 space-y-1 text-sm">
        {sorted.map((t) => (
          <li key={t.id} className="flex justify-between rounded-lg bg-muted px-3 py-1.5">
            <span>{t.name}</span>
            <span>{t.votes}</span>
          </li>
        ))}
      </ul>
    </section>
  );
}

type Act = (action: "start" | "reset" | "startVote" | "endVote" | "eliminate" | "eliminateVoted" | "kick" | "setReveal" | "setMafiaRule", playerId?: string, value?: string) => void;

function AdminDashboard({ state, act }: { state: State; act: Act }) {
  const a = state.admin!;
  const { game } = state;
  const confirmAct = (msg: string, ...args: Parameters<Act>) => {
    if (window.confirm(msg)) act(...args);
  };
  return (
    <div className="flex flex-col gap-4 fade-in">
      <section className="glass flex flex-wrap items-center gap-2 p-4">
        <span className="mr-auto text-sm text-muted-foreground">
          {game.phase === "lobby" ? "Lobby" : game.phase === "playing" ? (game.votingOpen ? "Voting open" : "Game in progress") : "Game over"} · {a.players.length}/{MAX_PLAYERS}
        </span>
        {game.phase === "lobby" && (
          <button className="glass-btn glass-btn-primary" disabled={a.players.length < MIN_PLAYERS} onClick={() => act("start")}>
            START GAME
          </button>
        )}
        {game.phase === "playing" && !game.votingOpen && (
          <button className="glass-btn glass-btn-primary" onClick={() => act("startVote")}>START VOTE</button>
        )}
        {game.votingOpen && (
          <button className="glass-btn glass-btn-primary" onClick={() => act("endVote")}>END VOTE</button>
        )}
        <button className="glass-btn glass-btn-danger" onClick={() => confirmAct("Reset the game? All roles, votes and eliminations will be cleared.", "reset")}>
          RESET GAME
        </button>
      </section>

      {game.phase === "lobby" && a.players.length < MIN_PLAYERS && (
        <p className="text-center text-sm text-muted-foreground">Need at least {MIN_PLAYERS} players to start.</p>
      )}

      {game.phase === "ended" && game.winner && (
        <section className="glass p-5 text-center text-xl font-semibold">{WINNER_TEXT[game.winner]}</section>
      )}

      {game.votingOpen && (
        <section className="glass p-5">
          <h2 className="font-semibold">Live votes — round {game.voteRound}</h2>
          <p className="text-sm text-muted-foreground">{a.votesCast} of {a.eligibleVoters} voted</p>
          <ul className="mt-3 space-y-1 text-sm">
            {[...a.liveTotals].sort((x, y) => y.votes - x.votes).map((t) => (
              <li key={t.id} className="flex justify-between rounded-lg bg-muted px-3 py-1.5">
                <span>{t.name}</span>
                <span>{t.votes}</span>
              </li>
            ))}
          </ul>
        </section>
      )}

      {state.lastResult && (
        <>
          <VoteResults result={state.lastResult} />
          {game.phase === "playing" && state.lastResult.top.length === 1 && !state.lastResult.used && (
            <button
              className="glass-btn glass-btn-danger"
              onClick={() => confirmAct(`Eliminate ${state.lastResult!.top[0].name} by vote?`, "eliminateVoted")}
            >
              Eliminate {state.lastResult.top[0].name} (voted out)
            </button>
          )}
        </>
      )}

      {game.phase !== "lobby" && (
        <section className="glass p-5">
          <h2 className="mb-3 font-semibold">Alive by role</h2>
          <div className="grid grid-cols-5 gap-2 text-center">
            {(["mafia", "civilian", "detective", "doctor", "joker"] as const).map((r) => (
              <div key={r} className="rounded-xl bg-muted py-2">
                <div className="text-xl">{ROLE_INFO[r].icon}</div>
                <div className="text-lg font-semibold">{a.counters[r]}</div>
                <div className="text-[10px] text-muted-foreground sm:text-xs">{ROLE_INFO[r].name}</div>
              </div>
            ))}
          </div>
        </section>
      )}

      <section className="glass overflow-x-auto p-5">
        <table className="w-full text-sm">
          <thead className="text-left text-muted-foreground">
            <tr>
              <th className="pb-2">Player</th>
              <th className="pb-2">Character</th>
              <th className="pb-2">Status</th>
              <th className="pb-2 text-right">Action</th>
            </tr>
          </thead>
          <tbody>
            {a.players.map((p) => (
              <tr key={p.id} className="border-t">
                <td className="py-2">{p.name}</td>
                <td>{p.role ? `${ROLE_INFO[p.role].icon} ${ROLE_INFO[p.role].name}` : "—"}</td>
                <td className={p.alive ? "text-success" : "text-destructive"}>{p.alive ? "Alive" : "Eliminated"}</td>
                <td className="py-2 text-right">
                  <div className="flex justify-end gap-1">
                    {game.phase === "playing" && p.alive && p.role && (
                      <button className="glass-btn px-3 py-1 text-xs" onClick={() => confirmAct(`Eliminate ${p.name}?`, "eliminate", p.id)}>
                        Eliminate
                      </button>
                    )}
                    <button className="glass-btn glass-btn-danger px-3 py-1 text-xs" onClick={() => confirmAct(`Kick ${p.name} from the room?`, "kick", p.id)}>
                      KICK PLAYER
                    </button>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>

      <section className="glass flex flex-col gap-3 p-5 text-sm">
        <h2 className="font-semibold">Settings</h2>
        <label className="flex items-center justify-between gap-3">
          Reveal eliminated players' roles publicly
          <input type="checkbox" checked={game.revealRoles} onChange={(e) => act("setReveal", undefined, String(e.target.checked))} />
        </label>
        <label className="flex items-center justify-between gap-3">
          Mafia wins when
          <select
            value={game.mafiaRule}
            onChange={(e) => act("setMafiaRule", undefined, e.target.value)}
            className="rounded-full border border-input bg-popover px-3 py-1"
          >
            <option value="gte">Mafia ≥ others</option>
            <option value="gt">Mafia &gt; others</option>
          </select>
        </label>
      </section>
    </div>
  );
}
