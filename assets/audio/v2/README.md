# V2 sounds

Real recordings, all CC0, cut and levelled by `tools/build_v2_audio.py` from the raw downloads in
`assets_src/audio_v2/` (`tools/fetch_v2_audio.sh` gets them; sources and licences: `licenses.csv`, rows "V2 sounds").
Files are `<key>_NN.ogg`; a key plays one of its files at random with a little pitch scatter. The mix (volume per
key) is `SOUNDS` in `scripts/v2/v2_sfx.gd`. To change a sound, change its recipe in the build script and run it.

The guns come from The Free Firearm Sound Library (real firearms, recorded outdoors at 24 bit / 96 kHz). Everything
else was chosen from its name, length and spectrum, not by ear (the build machine has no sound): if one is wrong,
it is a one-line swap in the build script.

| key | what it is | source recording |
|---|---|---|
| `pistol_shot` | one pistol round (stereo, in the head) | Walther PPQ 9 mm, near |
| `rifle_shot` | one machine gun round, cut short: twelve a second | AR-15 5.56, near |
| `rifle_tail` | the burst dying away when the trigger is let go | the same shot's decay |
| `casing` | a brass case on the floor | small metal clinks |
| `pistol_mag_out` / `pistol_mag_in` / `slide` | the pistol's reload | a real handgun reload, cut in three |
| `rifle_mag_out` / `rifle_mag_in` / `bolt` | the machine gun's reload | an airsoft rifle reload, cut in three; magazine clicks |
| `handling` | the gun shifting in the hands: draw, aim, inspect | equipment clicks, a rattle |
| `impact_concrete` | a round into a wall or floor | stone and rock hits |
| `impact_metal` | a round on a wreck or on armour | metal hits |
| `flyby` | a robot's round passing the head | short swishes |
| `step` / `jump` / `land` | boots on a hard floor | footsteps on stone; a low thud for the landing |
| `crouch` | gear as the player drops or rises | a rattle, a light clunk |
| `hurt` / `down` | the player is hit / goes down | dull blows |
| `spider_shot` / `drone_shot` / `turret_shot` | the robots' guns, at their muzzles | Tikka .30-06 / Carl Gustav M45 9 mm / AK-47, a few metres off |
| `spider_step` | a metal foot coming down | metal footsteps on concrete |
| `servo` | a joint driven round | a motor whine, an octave down |
| `drone_rotor` | LOOP, pitch bent by the game | a small fan, pitched up |
| `robot_hit` | a round that hurt a robot | heavier metal hits, pitched down |
| `robot_break` | a robot destroyed | metal falling + a bang |
| `power_down` | motors running down | the fan with its pitch sliding down |
| `crash` | a heavy machine hitting the floor | metal falling, pitched down, + a low thud |
| `explosion` | the drone blowing up | firework bangs and cannon shots, layered |
| `zap` | electric sparks | a small Tesla coil |
