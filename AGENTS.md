<!-- LOVABLE:BEGIN -->
> [!IMPORTANT]
> This project is connected to [Lovable](https://lovable.dev). Avoid rewriting
> published git history — force pushing, or rebasing/amending/squashing commits
> that are already pushed — as it rewrites history on Lovable's side and the
> user will likely lose their project history.
>
> Commits you push to the connected branch sync back to Lovable and show up in
> the editor, so keep the branch in a working state.
<!-- LOVABLE:END -->

## Mafia game architecture
- All game reads/writes go through server functions in src/lib/game.functions.ts using the service-role client; players/votes tables have RLS with no policies so roles never reach browsers directly.
- Only the `game` row is publicly readable and in realtime; clients refetch personalized state when its `version` changes (plus a 4s poll fallback).
- Admin auth is an HMAC of the ADMIN_CODE secret, verified on every admin call; players are identified by a random token in localStorage.
- Pure rules (role assignment, victory, tally) live in src/lib/game-logic.ts with tests beside it.
