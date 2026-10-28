export const ROLE_INFO: Record<string, { name: string; icon: string; team: string; desc: string }> = {
  mafia: { name: "Mafia", icon: "🔪", team: "Mafia", desc: "Work secretly with the other Mafia. Win when Mafia equal or outnumber everyone else." },
  joker: { name: "Joker", icon: "🃏", team: "Solo", desc: "Act suspicious. You win if the town eliminates you through a public vote." },
  detective: { name: "Detective", icon: "🔍", team: "Town", desc: "Investigate players to uncover the Mafia. Help the town eliminate all Mafia." },
  doctor: { name: "Doctor", icon: "🩺", team: "Town", desc: "Protect players from the Mafia. Help the town eliminate all Mafia." },
  civilian: { name: "Civilian", icon: "🏠", team: "Town", desc: "Find and vote out the Mafia. The town wins when all Mafia are eliminated." },
};

export const WINNER_TEXT: Record<string, string> = {
  town: "The Town wins! All Mafia have been eliminated.",
  mafia: "The Mafia wins! They now control the town.",
  joker: "The Joker wins! They were voted out by the town.",
};
