export type Role = "mafia" | "joker" | "detective" | "doctor" | "civilian";
export const MIN_PLAYERS = 6;
export const MAX_PLAYERS = 23;

export function secureRandomInt(max: number): number {
  const buf = new Uint32Array(1);
  crypto.getRandomValues(buf);
  return buf[0]! % max;
}

/** Returns one role per player, in random order. */
export function assignRoles(count: number, rand: (max: number) => number = secureRandomInt): Role[] {
  if (count < MIN_PLAYERS) throw new Error(`Need at least ${MIN_PLAYERS} players`);
  if (count > MAX_PLAYERS) throw new Error(`Maximum ${MAX_PLAYERS} players`);
  const roles: Role[] = ["mafia", "mafia", "mafia", "joker", "detective", "doctor"];
  while (roles.length < count) roles.push("civilian");
  for (let i = roles.length - 1; i > 0; i--) {
    const j = rand(i + 1);
    [roles[i], roles[j]] = [roles[j]!, roles[i]!];
  }
  return roles;
}

export type MafiaRule = "gte" | "gt";
export type Winner = "town" | "mafia" | "joker" | null;

export function checkVictory(
  aliveRoles: Role[],
  rule: MafiaRule,
  eliminated?: { role: Role; byVote: boolean },
): Winner {
  if (eliminated && eliminated.role === "joker" && eliminated.byVote) return "joker";
  const mafia = aliveRoles.filter((r) => r === "mafia").length;
  const others = aliveRoles.length - mafia;
  if (mafia === 0) return "town";
  if (rule === "gte" ? mafia >= others : mafia > others) return "mafia";
  return null;
}

export function tallyVotes(votes: { target_id: string }[]) {
  const totals: Record<string, number> = {};
  for (const v of votes) totals[v.target_id] = (totals[v.target_id] ?? 0) + 1;
  const max = Math.max(0, ...Object.values(totals));
  const top = max > 0 ? Object.keys(totals).filter((k) => totals[k] === max) : [];
  return { totals, max, top };
}
