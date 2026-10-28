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
- All game logic lives in SECURITY DEFINER Postgres functions (mafia_state/join/vote/admin_unlock/admin); the browser calls them via src/lib/game-client.ts with the publishable key and the direct backend URL, so the app runs on any host (Vercel) with no server env vars.
- players/votes/admin tables have RLS with no policies; only the `game` row is publicly readable and in realtime; clients refetch state when it changes (plus a 4s poll).
- Admin code is stored only as a sha256 hash (set via service-role-only mafia_set_admin_code); unlocking issues a random session token stored hashed in admin_sessions.
- src/lib/game-logic.ts holds constants and reference rules with tests; the database functions are the source of truth.
- Private night actions/results live in locked night tables and SECURITY DEFINER RPCs; a monotonic night round and shared advisory lock serialize submissions, admin transitions, and resolution without host server dependencies.
- Night controls live in src/components/night-actions.tsx and consume token-scoped state; never expose other players' choices or feedback outside the admin response.
