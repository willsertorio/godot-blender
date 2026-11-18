# Project Firewall — game design document

## Concept

Project Firewall — a first-person corridor shooter in which the player infiltrates a procedurally assembled dataspace, clears hostile constructs, loots containers for health and ammunition, and reaches the exit portal in the final room before their health runs out.

Minimalist neon cyberspace seen through a first-person view: dark walls traced with glowing grid lines, geometric enemies in a single hostile colour, and luminous pickups standing out against the floor.

A session is one generated dungeon of eight to twelve rooms. It ends when the player steps into the exit portal — a success — or when their health reaches zero — a failure — and either way the end screen shows a score and offers another, harder run.

## The core mechanic

The generated dungeon. Every run builds a fresh dataspace from a random arrangement of rooms joined by corridors and doors, then scatters hostile constructs, loot and one exit portal through it. The player clears room by room, spending health and ammunition to do it, and loots containers and fallen enemies to survive long enough to reach the exit. Having no two runs share a layout is the hook, and the opposition and the payout both scale with every mission completed.

## 1. Core gameplay loop

1. Player reads the title screen and presses its single button to generate a dungeon and enter play.
2. Player walks the generated rooms and corridors, counting each new room against a total of eight to twelve.
3. Player shoots hostile constructs with the pistol or the rifle, spending health and ammunition to clear each room.
4. Player loots containers and fallen enemies for restored health, carried health kits and rifle ammunition.
5. Player opens the doors between rooms and reads the map to pick a route toward the exit portal in the final room.
6. Player's run ends one of two ways: reaching the exit portal marks the mission complete, and losing all health ends the run in failure.
7. Player reads the score and enemies killed, then plays again against a harder dungeon or stops; the game has no final ending, only a difficulty that keeps climbing with each completed mission.

## 2. Controls

- **Keyboard** — WASD move in four directions, R reload the rifle, E interact with doors and containers, Q spend a carried health kit, 1 and 2 switch between the pistol and the rifle, Tab toggle the map.
- **Mouse** — move to look, left button fire, right button aim down sights; the view locks to the mouse while playing.
- Aiming down sights slows movement as well as tightening the shot, and nothing on screen teaches it — the one effect the player has to discover.

## 3. Mechanics and rules

**Movement.** The player walks the dungeon on a flat grid, stopped only by walls and closed doors. Aiming down sights slows the walk.

**Weapons.** The pistol fires single shots and never runs out of ammunition; the rifle fires automatically but drains a finite reserve that must be found, and only the rifle reloads.

**Aiming down sights.** It tightens the shot's spread and narrows the view, and it slows movement while held.

**Line of sight.** A shot hits only the first hostile along a clear line, and walls break both eyes and bullets. Hostiles attack under the same rule, so without a clear line no damage passes in either direction.

**Doors.** Some corridor chokepoints hold a door that blocks movement, bullets and sight until the player opens it with the interact key while standing close enough, and an opened door stays open.

**Loot.** Interact on a closed container opens it onto one of three payoffs — a carried health kit, rifle ammunition, or immediate health — and some fallen enemies drop the same.

**Health kits.** The player can carry up to three kits and spends one on command to heal; picking up another refills a slot. Health and ammunition also restore instantly on pickup.

**Enemies.** Three kinds of hostile constructs differ by motion and range: a stationary turret that shoots from across a room, a fast brawler that closes to melee, and a hovering pursuer in between.

**Exit.** The exit portal waits in the final room and stepping into it ends the run in success; reaching zero health ends it in failure.

**Difficulty.** Every completed mission makes the next dungeon's hostiles tougher and more numerous and thins the health kits on offer, and the climb resets when the game is reloaded because nothing is saved.

## 4. Experience pillars

### Onboarding

The title screen lists every control in two short lines and offers a single button, so a player is inside a dungeon on one click with no choices to make. What the game never teaches is that aiming down sights also slows movement, and how close the player must stand before the interact key will answer — the second shows no prompt and is only felt by trial.

### Enemies

Three hostiles, differentiated by motion and range, and none of them is a projectile to dodge: each damages the player the instant line of sight is clear and its timer elapses, so the only defences are killing first, breaking the sight line or putting a door between. The game never lets a shot be dodged, which is the gap a richer enemy aims to fix.

### Rewards and power-ups

Score is awarded only for killing hostiles, and the three types pay by the danger they pose, so the game pays for aggression and nothing else. Loot pays the two resources a run spends — health and rifle ammunition — restored on the spot or stocked as carryable kits. There are no power-ups that strengthen the player mid-run; every reward restores or scores rather than upgrades.

### Progression

Nothing carries between sessions except difficulty: complete a mission and the next dungeon raises hostile health and numbers while it thins the kits, then resets when the page reloads. There is no currency, no unlocks and no player growth, so the pull across runs is a higher score on a harder layout, not a build. Difficulty climbs only with missions completed, not with how well any one was fought, so a player who scrapes through faces the same next dungeon as one who dominated it.

## 5. Interface and HUD

### In play

- **Health** — whether this is the room to fall back, spend a kit, or push through.
- **Ammo and reserve** — whether the rifle can still carry the next room or the pistol must.
- **Health kit count** — whether to spend a kit now or save it for the exit room.
- **Which weapon is active** — whether the trigger is the one that runs dry or the one that never does.
- **Room count and exit proximity** — how deep into the dungeon the player is and whether the goal is near.
- **Crosshair** — where the next shot will land and when a hostile is lined up.
- **Damage flash** — that health was just lost and the player should break line of sight now.
- **The objective line** — what the run is actually for at the moment the player decides where to go next.
- **Map toggle** — which rooms are explored, which hold hostiles, and where the exit sits once its room is found — the whole routing decision.

### Menus

- **Title screen** — every control in two short lines plus one launch button, because there is nothing to pick before a run.
- **End screen** — win or loss, the score, enemies killed and rooms explored, and a play-again button; the decision is another, harder run or stop. The score is a single kill total, so reaching the exit and staying alive are counted but never valued.
- **No pause control** — the only way to stop mid-run is to leave the tab, and the game never tells the player that.
