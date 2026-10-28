import { describe, expect, it } from "vitest";
import { assignRoles, checkVictory, tallyVotes } from "./game-logic";

describe("roles", () => {
  it("23 players: 3 mafia, 1 joker, 1 detective, 1 doctor, 17 civilians", () => {
    const r = assignRoles(23);
    const c = (x: string) => r.filter((y) => y === x).length;
    expect([c("mafia"), c("joker"), c("detective"), c("doctor"), c("civilian")]).toEqual([3, 1, 1, 1, 17]);
  });
  it("refuses fewer than 6 players", () => expect(() => assignRoles(5)).toThrow());
});

describe("victory", () => {
  it("town wins when no mafia alive", () => expect(checkVictory(["civilian", "doctor"], "gte")).toBe("town"));
  it("mafia wins when equal to others (default rule)", () =>
    expect(checkVictory(["mafia", "civilian"], "gte")).toBe("mafia"));
  it("strict rule: equal is not a win", () => expect(checkVictory(["mafia", "civilian"], "gt")).toBe(null));
  it("joker wins only by public vote", () => {
    const alive = ["mafia", "civilian", "civilian", "civilian"] as const;
    expect(checkVictory([...alive], "gte", { role: "joker", byVote: true })).toBe("joker");
    expect(checkVictory([...alive], "gte", { role: "joker", byVote: false })).toBe(null);
  });
});

describe("tally", () => {
  it("reports ties", () => {
    expect(tallyVotes([{ target_id: "a" }, { target_id: "b" }]).top).toEqual(["a", "b"]);
  });
});
