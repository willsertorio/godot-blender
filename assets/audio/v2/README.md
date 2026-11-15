# V2 sounds

Put the realistic library's files here as `<key>_<anything>.ogg` (or `.wav`); any number per key, one is picked
at random each time. A key with no file here plays its stand-in from V1's Kenney set (`scripts/v2/v2_sfx.gd`,
`SOUNDS`), or nothing where the table has no stand-in. Every file needs its row in `licenses.csv` (CC0 only).
Aim for one loudness across the set (about -16 LUFS for the loud ones, peaks under -1 dB), mono for the sounds
played at a place in the room, 44.1 or 48 kHz.

| key | what it is | played |
|---|---|---|
| `pistol_shot` | one pistol round, close, indoors | in the head |
| `rifle_shot` | one machine gun round (12 a second: short tail, or it turns to mud) | in the head |
| `casing` | a brass case landing on a hard floor | in the head, quiet |
| `mag_out` / `mag_in` | magazine released / seated | in the head |
| `slide` | pistol slide running forward | in the head |
| `bolt` | machine gun charging handle / bolt | in the head |
| `handling` | the gun shifting in gloved hands: draw, aim, inspect | in the head, quiet |
| `impact_concrete` | a round into a wall or floor | at the hit |
| `impact_metal` | a round on a robot's armour | at the hit |
| `ricochet` | a round whining off (one hit in seven) | at the hit |
| `flyby` | a round passing the head | in the head |
| `step` | a boot on a hard floor | in the head |
| `jump` / `land` | push off / landing | in the head |
| `crouch` | clothing and gear as the player drops or rises | in the head, quiet |
| `hurt` | the player is hit | in the head |
| `down` | the player goes down | in the head |
| `spider_shot` / `drone_shot` / `turret_shot` | the robots' guns (heavier than the player's; the drone's lighter) | at the muzzle |
| `spider_step` | a metal foot coming down | at the spider |
| `servo` | a short servo run: a turret swinging, the spider stepping round | at the robot |
| `drone_rotor` | LOOP: two small rotors (the game bends its pitch) | on the drone |
| `robot_hit` | a round that hurt a robot: a heavier clang than `impact_metal` | at the hit |
| `robot_break` | a robot destroyed: a crack and breaking metal | at the robot |
| `power_down` | motors running down | at the robot |
| `crash` | a heavy machine hitting the floor | at the wreck |
| `explosion` | the drone blowing up where it lands | at the wreck |
| `zap` | electric sparks | at the sparks |
| `fire` | LOOP: a small fire crackling | on the wreck |
| `power_up` | a robot coming back | at the robot |
