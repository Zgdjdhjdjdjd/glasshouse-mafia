import { useEffect, useState } from "react";
import { Moon, ShieldCheck, Search, Crosshair } from "lucide-react";
import { Button } from "@/components/ui/button";
import type { State } from "@/lib/game-client";
import { ROLE_INFO } from "@/lib/roles";

export type NightAct = (action: "startNight" | "closeNight" | "reopenNight" | "cancelNight" | "resolveNight", targetId?: string) => void;

export function PlayerNight({ state, submit }: { state: State; submit: (id: string) => void }) {
  const [choice, setChoice] = useState("");
  const [pending, setPending] = useState(false);
  useEffect(() => { setChoice(""); setPending(false); }, [state.night.round, state.night.choice]);
  const me = state.me;
  if (!me) return null;
  const { night } = state;
  const role = me.role;
  const eligible = me.alive && (role === "mafia" || role === "doctor" || role === "detective");
  const feedback = night.feedback;
  const title = role === "doctor" ? "Choose who to save" : role === "detective" ? "Investigate a player" : "Choose who to kill";
  const Icon = role === "doctor" ? ShieldCheck : role === "detective" ? Search : Crosshair;
  if (!night.open && night.status !== "closed" && !feedback) return null;
  return (
    <section className="glass p-5">
      <h2 className="flex items-center gap-2 font-semibold"><Moon className="size-4" />Night {night.round}</h2>
      {night.open ? eligible ? night.choice ? (
        <p className="mt-3 text-sm text-success">Your choice: {night.choice.targetName}. Waiting for admin approval.</p>
      ) : (
        <form className="mt-3 space-y-3" onSubmit={async (event) => { event.preventDefault(); if (!choice || pending) return; setPending(true); try { await submit(choice); } finally { setPending(false); } }}>
          <label className="flex items-center gap-2 text-sm" htmlFor="night-target"><Icon className="size-4" />{title}</label>
          <select id="night-target" className="w-full rounded-lg border border-input bg-popover px-3 py-3 text-sm" value={choice} onChange={(event) => setChoice(event.target.value)}>
            <option value="">Select player</option>
            {state.players.filter((player) => player.alive && (role === "doctor" || player.id !== me.id)).map((player) => <option key={player.id} value={player.id}>{player.name}{player.id === me.id ? " (you)" : ""}</option>)}
          </select>
          <Button className="glass-btn glass-btn-primary w-full" disabled={!choice || pending} type="submit">{pending ? "Submitting…" : "Submit night choice"}</Button>
        </form>
      ) : <p className="mt-3 text-sm text-muted-foreground">Waiting for the night to finish.</p> : night.status === "closed" ? <p className="mt-3 text-sm text-muted-foreground">Choices closed. Waiting for admin approval.</p> : null}
      {feedback && <div className="mt-4 border-t pt-3 text-sm">
        <p className="mb-1 text-muted-foreground">Private result · Night {feedback.round}</p>
        <p>{feedback.role === "detective" ? `${feedback.targetName} ${feedback.isMafia ? "is Mafia. Your guess was correct." : "is not Mafia. Your guess was incorrect."}` : feedback.saved ? `You saved ${feedback.targetName} from the Mafia.` : feedback.attacked ? `${feedback.targetName} was not the Mafia's target. You did not save the attacked player.` : "No attack was approved tonight."}</p>
      </div>}
    </section>
  );
}

export function AdminNight({ state, act }: { state: State; act: NightAct }) {
  const [victim, setVictim] = useState("");
  useEffect(() => setVictim(""), [state.night.round]);
  const admin = state.admin;
  if (!admin || state.game.phase !== "playing") return null;
  const { night } = state;
  const pending = night.status === "open" || night.status === "closed";
  const outcome = admin.nightOutcome;
  return (
    <section className="glass space-y-4 p-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 className="flex items-center gap-2 font-semibold"><Moon className="size-4" />{pending ? `Night ${night.round} · ${night.open ? "Choices open" : "Awaiting approval"}` : "Night actions"}</h2>
        {!pending && <Button className="glass-btn glass-btn-primary" disabled={state.game.votingOpen} onClick={() => act("startNight")}>START NIGHT</Button>}
      </div>
      {pending && <>
        <ul className="space-y-2 text-sm">
          {admin.players.filter((player) => player.alive && ["mafia", "doctor", "detective"].includes(player.role ?? "")).map((player) => {
            const choice = admin.nightChoices.find((entry) => entry.playerId === player.id);
            return <li key={player.id} className="flex flex-wrap justify-between gap-1 border-b pb-2"><span>{player.name} · {ROLE_INFO[player.role ?? ""]?.name}</span><span className={choice?.active ? "text-foreground" : "text-muted-foreground"}>{choice ? `${choice.targetName}${choice.active ? "" : " (unavailable)"}` : "Waiting…"}</span></li>;
          })}
        </ul>
        {night.open ? <Button className="glass-btn glass-btn-primary w-full" onClick={() => act("closeNight")}>CLOSE NIGHT CHOICES</Button> : <>
          <label className="block text-sm" htmlFor="admin-victim">Final Mafia target</label>
          <select id="admin-victim" className="w-full rounded-lg border border-input bg-popover px-3 py-3 text-sm" value={victim} onChange={(event) => setVictim(event.target.value)}>
            <option value="">No kill</option>
            {admin.players.filter((player) => player.alive && player.role).map((player) => <option key={player.id} value={player.id}>{player.name}</option>)}
          </select>
          <Button className="glass-btn glass-btn-primary w-full" onClick={() => { const name = admin.players.find((player) => player.id === victim)?.name; if (window.confirm(name ? `Approve attack on ${name}, apply Doctor protection, and release private results?` : "Approve no kill and release private results?")) act("resolveNight", victim || undefined); }}>APPROVE NIGHT</Button>
          <Button variant="secondary" className="glass-btn w-full" onClick={() => act("reopenNight")}>Reopen choices</Button>
        </>}
        <Button variant="ghost" className="glass-btn glass-btn-danger w-full" onClick={() => { if (window.confirm("Cancel this night without an attack or private results?")) act("cancelNight"); }}>Cancel night</Button>
      </>}
      {outcome && <p className="text-sm">{!outcome.victimName ? "Night approved: no kill." : outcome.saved ? `${outcome.victimName} was saved by the Doctor.` : `${outcome.victimName} was killed.`}</p>}
    </section>
  );
}