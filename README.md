# Glasshouse Mafia

PROJECT: SIMPLE MAFIA GAME



Build a simple, functional multiplayer Mafia game website with an Apple-inspired Liquid Glass / glassmorphism design.



IMPORTANT: Keep the application as simple as possible. Do not add unnecessary features, pages, accounts, animations, or complicated systems. Prioritize working functionality, privacy, and reliability.



1. DESIGN



- Apple-inspired glassmorphism.

- Black background with translucent glass panels.

- White text, subtle reflections, rounded buttons.

- Clean, premium, mobile-friendly interface.

- Lightweight animations.

- Responsive on phones, tablets, and computers.



2. ONE ROOM AND LOBBY



There must be only ONE shared game room.



- Players enter their chosen display names and join.

- Maximum capacity: 23 players.

- Show the live list of joined players.

- Display the player count, such as 12/23.

- Players wait in the lobby until the admin starts the game.

- Require at least 6 players to start.

- Prevent duplicate active entries when someone refreshes or reconnects.

- No room codes, multiple rooms, chat, match history, or unnecessary features.



3. ADMIN ACCESS



I am the sole administrator.



- Provide a secret admin code configured securely on the server.

- I enter the code to unlock administrator controls.

- Only the admin can start or reset the game, view everyone's roles, manage voting, eliminate players, and kick players.

- Keep the admin session authenticated after unlocking.

- Never expose the admin code in frontend code or public settings.

- Enforce administrator permissions on the server.



Do not build a complicated account system.



4. CHARACTER ASSIGNMENT



When the admin presses START GAME, randomly assign the following roles:



Character| Quantity

Mafia| 3

Joker| 1

Detective| 1

Doctor| 1

Civilians| All remaining players



At maximum capacity, the game contains 3 Mafia, 1 Joker, 1 Detective, 1 Doctor, and 17 Civilians.



Requirements:



- Assign roles randomly on the server.

- Each player receives exactly one role.

- Players cannot choose or reroll their roles.

- Keep assignments unchanged after refreshes or reconnects.

- Do not start with fewer than 6 players.

- If the game has already started, do not assign new roles automatically when someone joins.



5. PRIVATE CHARACTER CARDS



After the admin starts the game, each player sees a REVEAL MY CARD button.



When pressed, display:



- Character name.

- Character icon.

- Team.

- Short description and objective.



Players must only be able to see their own character.



The admin must have a private table showing every player's name, assigned role, and alive or eliminated status.



Never send all character assignments to ordinary players' browsers. Protect role information using server-side authorization.



6. ADMIN DASHBOARD



Keep the dashboard simple and accessible at any time.



Display a private table containing:



Player| Character| Status| Action

Player name| Assigned role| Alive/Eliminated| Manage



The admin must be able to:



- View every player's assigned role.

- View who is alive or eliminated.

- See the number of living Mafia, Civilians, Detectives, Doctors, and Jokers.

- Start and end voting.

- View live voting totals.

- Eliminate a player manually.

- Kick a player.

- Reset the game.



Update the dashboard immediately whenever the game state changes.



7. VOTING SYSTEM



Add a START VOTE button that only the admin can use.



When the admin starts voting:



- All eligible living players see a voting screen.

- Display the names of eligible players.

- Each player may vote for one eligible player.

- Each player can submit only one vote per voting round.

- Players cannot see other players' votes.

- The admin can see live vote totals for every candidate.

- The admin can end voting at any time.

- When voting ends, display the final totals and announce the candidate with the most votes.

- If there is a tie, announce the tie without automatically eliminating anyone.

- Voting does not automatically eliminate anyone. The admin decides whether to eliminate the selected player.



The admin must be able to start another voting round whenever needed.



Eliminated players cannot vote.



8. ELIMINATING PLAYERS



The admin can manually eliminate any living player or choose to eliminate the player selected by voting.



- Ask for confirmation before elimination.

- Update the player's status immediately.

- Remove them from the living-player count.

- Prevent eliminated players from voting.

- Update all role counters.

- Check the victory conditions immediately.

- Do not reveal the eliminated player's role publicly unless the admin has enabled role revelation.



Elimination and kicking are different actions. Eliminating a player leaves them in the room as an eliminated spectator. Kicking removes them from the room.



9. KICK PLAYER



The admin must have a KICK PLAYER button next to every player's name.



- Only the admin can kick players.

- Ask for confirmation before kicking.

- Remove the player from the room immediately.

- Update the player count and dashboard.

- Revoke their access to the current room.

- Prevent the kicked player from rejoining through the same session.

- If kicked during a game, mark them as eliminated for game calculations and update the living-role counters.

- If kicked during voting, invalidate their vote and update the live totals.

- Recheck victory conditions after a kick.

- Never reveal the kicked player's secret character to other players.



The kick action must be enforced on the server, not just by hiding the player on the screen.



10. LIVE ROLE COUNTERS



Show the admin a live counter for the number of living players in each role.



Example:



Character| Alive

Mafia| 3

Civilians| 10

Detective| 1

Doctor| 1

Joker| 1



Update these numbers whenever a player is eliminated or kicked.



Count only living players. Keep eliminated players' original role assignments in the private admin table for reference, but do not count them as alive.



Ordinary players must never see these private counters.



11. VICTORY CONDITIONS



Check for victory after every elimination or kick.



Town victory: All Mafia members have been eliminated.



Mafia victory: The number of living Mafia members is equal to or greater than the total number of all other living players combined.



Joker victory: The Joker wins if eliminated through a completed public vote, according to the Joker's special objective.



The Joker does not win merely by being kicked or eliminated at night.



When the game ends:



- Announce the winning side.

- Stop further voting.

- Display a simple game-over screen.

- Allow the admin to reset the game.



Keep the Mafia victory condition configurable in the settings, using the equal-or-greater rule as the default.



12. RESET GAME



Provide a RESET GAME button for the admin.



- Ask for confirmation.

- Clear all role assignments, votes, eliminations, and temporary game state.

- Return all remaining room members to the waiting lobby.

- Keep the room open.

- Allow the admin to start a fresh game.

- Ensure the reset is synchronized across all connected devices.



13. SIMPLE TECHNICAL IMPLEMENTATION



Use the simplest reliable technology supported by the app-building platform.



- One shared backend.

- One persistent database.

- Real-time updates across devices.

- Server-side role assignment.

- Server-side voting and vote counting.

- Server-side elimination and victory checks.

- Secure administrator authorization.

- Protected secret role assignments.

- Reconnection support.

- Persistent game state after refreshes.



Do not use local browser storage as the shared database or simulate multiplayer using frontend-only code.



Use database access rules and server-side validation to prevent unauthorized access to roles, votes, and administrative controls.



14. REQUIRED SCREENS



Build only these main screens:



1. Join Screen: Enter a display name and join the room.

2. Lobby: View joined player names and wait for the admin.

3. Character Screen: Reveal your own secret card.

4. Admin Dashboard: Manage players, see roles and live counters, control voting, eliminate or kick players, and reset the game.

5. Voting Screen: Select a candidate and submit a vote.

6. Results Screen: View final voting results or the winner.



Keep navigation simple and consistent.



15. FINAL INSTRUCTIONS



Build only what is specified above.



Do not add chat, multiple rooms, complicated registration, match history, unnecessary settings, elaborate animations, or additional roles.



Prioritize:



1. Correct role assignment.

2. Privacy of secret characters.

3. Reliable multiplayer synchronization.

4. Functional admin controls.

5. Accurate live voting and role counters.

6. Correct victory detection.

7. Simple Apple-inspired glassmorphism.



Build the simplest working version first. Test the complete flow from joining the lobby to assigning characters, voting, eliminating or kicking players, detecting victory, and resetting the game.



Do not claim that features work until they have been implemented and tested. Clearly identify any external database, deployment, or server configuration that is still required.

It should work perfectly fine when deployed on vercel

This project was built with [Lovable](https://lovable.dev).

## Build with Lovable

Continue developing this project in the [Lovable editor](https://lovable.dev/projects/bd2ae7b2-5725-4650-a73d-d772ce8a4a90).

- **Ship faster**: describe what you want to build and Lovable handles the code.
- **Stay in sync**: every change made in Lovable is committed straight to this repository.
- **Full ownership**: this code is yours. Push to `main` on GitHub and your changes sync back into Lovable, ready for your next prompt.

## Development

Prefer working locally? You need Node.js and npm — [install with nvm](https://github.com/nvm-sh/nvm#installing-and-updating).

```sh
git clone <this-repository-url>
cd <repository-name>
npm i
npm run dev
```
