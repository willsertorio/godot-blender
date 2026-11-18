# Project Firewall: working notes

A first-person corridor shooter vertical slice. The GDD lives in the original brief; this file records the
conventions, commands and code map so a new session can pick up where the last one stopped.

## Toolchain (this cloud container)

| Tool | Version | Path |
|---|---|---|
| Godot | 4.3-stable (official) | `/opt/godot/Godot_v4.3-stable_linux.x86_64`, symlinked as `godot` |
| Godot export templates | 4.3.stable | `~/.local/share/godot/export_templates/4.3.stable/` |
| Blender | 4.2.23 LTS (official linux-x64) | `/opt/blender-4.2.23-linux-x64/blender`, symlinked as `blender` |

None of this is in the base image. A fresh container needs them reinstalled (see "Reinstall" below).
Network: the session runs on the personal cloud environment `godot-blender`, which allows Poly Haven,
ambientCG, Quaternius, Kenney (send a browser User-Agent, or it returns 403), download.blender.org, GitHub,
itch.io + quaternius.itch.io and itch's file host `itchio-mirror.cb031a832f44726753d6267436f3b414.r2.cloudflarestorage.com`.
`opengameart.org` is allowed too (the V2 sounds); in one session a safety check refused shell fetches from it until
the user said in the chat that the session may fetch.
Blender's viewport renderer (thumbnails) needs `libegl1` (`apt-get install -y libegl1`) and `xvfb-run`.

### Reinstall
```
mkdir -p /opt/godot && cd /opt/godot
curl -sSLO https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip && unzip -o Godot_v4.3-stable_linux.x86_64.zip
curl -sSLO https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_export_templates.tpz
mkdir -p ~/.local/share/godot/export_templates && unzip -o Godot_v4.3-stable_export_templates.tpz && mv templates ~/.local/share/godot/export_templates/4.3.stable
cd /opt && curl -sSL https://download.blender.org/release/Blender4.2/blender-4.2.23-linux-x64.tar.xz | tar xJ
ln -sf /opt/godot/Godot_v4.3-stable_linux.x86_64 /usr/local/bin/godot
ln -sf /opt/blender-4.2.23-linux-x64/blender /usr/local/bin/blender
```

## Art direction (since the polish pass)

Everything visible comes from two CC0 Quaternius packs, in their own colours (the GDD's single-hostile-red
rule no longer applies to the environment):
- **Modular Sci-Fi MegaKit** (levels, doors, columns, props) and **Sci-Fi Essentials Kit** (guns, enemies,
  chest, pickups, decor). Raw packs: `assets_src/quaternius/` (git-ignored). Fetch: the free itch.io flow
  (`/download_url` -> download page -> `/file/<upload_id>` returns a signed R2 URL); the glTFs expect their
  textures next to them, so copy each pack's `Textures/` into every glTF folder before importing.
- `blender/scripts/normalize_quaternius.py` re-frames every piece (walls: cell -X edge -> our edge frame;
  guns: barrel -X -> +Y, grip origin, `Muzzle`; rigs kept with their actions), drops untextured helper
  spheres, merges duplicate materials (`MI_Trim_01.003` -> `MI_Trim_01`), exports glbs **without images** and
  writes `assets/models/q_materials.json` (material -> textures). `MaterialLib` builds each material once from
  that table + `assets/textures/quaternius/` (no per-glb texture copies).
- `tools/pack_quaternius_textures.py`: trim-sheet base colours 2K, everything else 1K, JPEG (PNG if alpha).
- Glow: the free glTFs drop emissive; `MaterialLib.EMISSIVE` restores it from the packs' emissive masks
  (multiply operator; the default ADD operator makes the whole surface glow). Enemy glow/beams `#FF4A2B`.
- Walls are 5 m (bottom strip + 3 m wall + 2 m top band); wall geometry reaches 0.45 m into the cell
  (`DungeonGen.WALL_DEPTH`). Rooms pick one wall style (astra / band / window) and one floor (A/B/C).
- Player arms: **WRAD ARMS** by wriks (CC0, https://wriks.itch.io/wrad-arms; raw in `assets_src/wrad/`).
  `normalize_wrad.py` scales it to metres (arm 0.55 m) with the `head` bone at the origin -> `arms_wrad.glb`.
  `pose_wrad.py` bakes a hold pose per gun -> `arms_pistol.glb` / `arms_rifle.glb`: in camera space with the gun
  at its hip offset, each grip gives a handle point, finger direction and knuckle line (index -> pinky); the hand
  frame is measured from the bones, Blender IK (pole for the elbow) + copy-rotation put the wrist there, fingers
  curl (negative rotation about the bone X axis on this rig), and the pose is baked as rest. Arms without a grip
  are cut from that weapon's mesh. Off-screen cheat: the left shoulder is moved forward for the rifle handguard.
  Hands use material ArmGlove, arms ArmSuit (fabric shader). In Godot the arms are children of the gun at -hip
  (`WeaponHolder._attach_arms`), so recoil/sway/reload move both; the reload drops the left arm by rotating `bicep.l`.
  The .blend in the pack is from a newer Blender (unreadable by 4.2); use its .glb.
- Hand styles (H cycles in game, `--arms=hands|full|none`): **hands** (default) = `build_hands.py`: gloves grown
  from metaballs around each handle (handle measured from the gun mesh: box -> centre, PCA axis, cross-section),
  fingers follow the cross-section so they always wrap it; parented to the gun at the origin. **full** = WRAD arms
  (`pose_wrad.py`). Pack-with-hands option (Quaternius Animated Guns / Sci-Fi Gun Pack) is blocked: Google Drive
  returns "Quota exceeded" to this container; download in a browser and drop into `incoming/` to try it.
- Viewmodel (`scripts/viewmodel_rig.gd`): weapon + arms render on layer 5 through their own camera
  (FOV 54, near 1 cm, SubViewport overlay under the HUD) with a key + rim light that only light that layer.
  Tracers start where the muzzle appears on screen (`WeaponHolder._muzzle_in_world`).
  Gun maps stay 2K; gun meshes are smooth-shaded by angle (35 deg).
- Lab gloves/sleeves: `assets/shaders/fabric.gdshader` = tint + ambientCG `Leather031` (glove) / `Fabric045` (sleeve)
  detail tiled over the character normal map (`MaterialLib.FABRIC`). Hand poses: `[pos, rot (deg or Basis), scale]`;
  tune with the pose tour (`--lab --poses=FILE.json --capture=DIR`, see `CaptureTour.run_poses`).
- Motion (all procedural, `WeaponHolder._animate` + `Player._update_head`): recoil = two springs (position, rotation)
  plus a camera view punch, sub-stepped at 1/240 s (explicit springs explode on long frames); look sway; figure-8
  walk bob (bigger running), breathing when still, landing dip; sprint pose (Shift, forward only, blocked 0.35 s
  after firing), crouch (Cmd/Ctrl/C, eye 1.05 m, capsule 1.25 m), jump (Space, 5 m/s, gravity 15).
  Rifle reload timeline: tilt in, support hand leaves with the mag (0.15-0.48), returns, slam + mag-in sound at 0.7.
- Dead enemies leave wrecks (death clip held on its last frame, glow dimmed, drones fall); group `wrecks`.
- Lab: Esc pauses (Resume / Quit; mouse freed). The real game keeps the GDD's no-pause rule.
  Lab targets respawn beside their wreck 3 s after a kill.
- Test room: the default when pressing Play (one room, three frozen targets, invulnerable); `--game` for the full game;
  `CAPTURE_ARGS=--lab tools/capture.sh 1 lab` captures hip / ADS / fire / low views of both guns.
- Exit portal: `build_props.py` gate + MegaKit `Platform_Round1` pad; field = `portal.gdshader`.
- Enemies (rigs + clips, names via `AnimUtil.play(prefix)`): Turret = `Enemy_Trilobite` (whole model yaws;
  Look while locking, AttackAuto on fire), Brawler = `Enemy_QuadShell` (Run, Charge, Attack), Pursuer =
  `Enemy_EyeDrone` (model faces +Z: `model_yaw = PI`; Charging while locking). Hit on damage, TurnOff/BackFlip
  wreck on death. Chest = `Prop_Chest` (Open clip).
- Lights: no OmniLights on props (they push room meshes past the 8-lights-per-object limit). Room lights 2.0,
  corridor 1.3, ambient 0.6 neutral, exposure 1.0, glow 0.35 @ 1.3.

## Graphics pass (lab; from-scratch assets)

- Renderer settings (`project.godot`): MSAA 4x (also on the viewmodel SubViewport), anisotropic 16x, 4096 shadow
  atlases with soft filtering. `--quality=low` (`?quality=low` on the web) turns off MSAA, the extra shadows, shafts, dust.
- Environment (`main.gd _setup_environment`): CC0 HDRI `assets/sky/bank_vault_1k.hdr` for reflections + half of the
  ambient (its mean luminance is 0.74 and warm, so a cool fill supplies the other half), ACES tonemap, exposure 1.08, glow.
- Every room light casts soft shadows and has a light shaft + dust (`DungeonBuilder._light_shaft`, `shaft.gdshader`).
  Shafts / dust are alpha-blended, never additive: in Compatibility an additive material is drawn again at full
  strength by the extra pass of every shadowed light in range (it rendered as solid white cones).
- `assets/shaders/military.gdshader` (all `MaterialLib.MILITARY` rows: guns, gloves, sleeves, enemies): triplanar PBR in
  object space + baked mask through UV1 (`assets/models/<name>_mask.png`: R = AO, G = convex-edge mask, baked by
  `export_new_assets.py` with Cycles, Smart-UV atlas over all parts) -> paint worn to steel on edges, dirt in crevices,
  scratches / smudges from `textures/military/_detail/imperfections.png`. The sRGB -> linear conversion of the base
  colour is explicit in the shader (the `source_color` hint did not convert the VRAM-compressed sets);
  `MaterialLib.MIL_LOOK` holds the per-set brightness / metal / roughness, `MIL_WEAR` the wear; enemy materials are
  x0.42 (they stand under the room lights). `MaterialLib.rebind_tree(root, glb_path)` picks up the mask.
- Viewmodel lights: key 2.6 (shadowed: the gun shadows itself and the hands), rim 1.8, fill 0.5.
- Review: `CAPTURE_ARGS="--lab --gfx" tools/capture.sh 1 gfx` then `python3 -I tools/gfx_sheet.py` (before / after sheet
  against `captures/gfx_before`).
- Not verified here: frame rate on a real GPU / in the browser (software GL in this container).

## V2 (current work): Blender scene -> Godot lab

V1 (everything else in this file) is frozen at commit `d4507b9` (`VERSIONS.md`); it still runs with `-- --v1`.
- **Blender side**: `v2/` (Godot ignores it). `v2/scene.blend` = room + three robots + two weapon views (pistol, machine
  gun) with rigged gloved arms, all animated, plus effects. Commands, method and what was learned: `v2/README.md`.
- **Godot side**: pressing Play opens the **title** (`scenes/v2_title.tscn`): PLAY = the V2 game, a generated dungeon
  (`scenes/v2_game.tscn`, see "V2 game" below), LAB = the V2 lab; Backspace in the lab goes back to the title.
  Options for the lab or the game on the command line skip the title (`v2_title.gd`: `--lab`, the lab's tests and
  `--capture=`; `--play`, `--game-test`, `--bot=N`, `--game-capture=DIR`).
  The **V2 lab** (`scenes/v2_lab.tscn`, `scripts/v2/`): three plain **studio** rooms
  side by side (11.6 m apart) joined by doorways, one robot in each (spider, drone, ceiling turret), each an **enemy**:
  it moves, aims, shoots the player and can be shot. The player holds the V2 guns. Keys: walk through the doors or
  `1 2 3` / Tab jump to a room, LMB fire (the machine gun fires for as long as it is held), RMB aim (held; LMB fires
  from the aim), `R` reload, `T` reload from empty, `F` inspect, `Q` switch gun, Shift sprint, Space jump,
  `C` aim as well (the user plays on a trackpad: no right button), `X` crouch (toggle; eye 1.0 m, capsule 1.15 m),
  `M` enemy <-> clip preview, `N` next clip (switches to preview), F3 performance, Esc frees the mouse.
- `scripts/v2/v2_world.gd` (`V2World`): what the lab, the game and the title are built from: the row of rooms
  (`_room_shell`: shell, collision, floor box, lights), render layers, door frames, `_environment`. All three extend it.
- Rooms: the studio is `v2/scripts/build_studio.py` -> `v2/studio.blend` + `assets/models/v2/studio.glb` (the size of
  the concept room, same doorways, a metre grid on the floor = `v2_grid.gdshader`, three blocks for cover outside the
  robots' arenas, its materials are `V2Assets.SPECIAL` entries). **User decision: the lab is a test studio; the
  detailed concept room (`room.glb`, from `scene.blend`) is kept for the real game** and still loads with `-- --concept`.
- Export: `v2/scripts/export_godot.sh` (one Blender process per asset; several animated exports in one process crash
  Blender 4.2) -> `assets/models/v2/*.glb` + `<name>_clips.json` + `<name>_mask.png` + `materials.json`, textures 1K
  -> `assets/textures/v2/`. Then `godot --headless --import` (this registers new `class_name`s too; `--editor --quit`
  did not) and keep `animation/fps=24` in the six `.glb.import` files (the default 30 resamples the 24 fps keys).
  The export also: bakes each asset's wear mask (Smart-UV atlas, Cycles, ~2.5 min: R = ambient occlusion,
  G = convex edges), adds `CamKick` under `Eye` (the camera's keyed offset in each gun clip), takes one subdivision
  level off the gloves (32k -> 8k faces each), and writes the gloves' rest position and rest normal into
  UV / UV2 / vertex colour (`prep_glove`).
- Clips the game drives by hand (frames from the clip tables): machine gun `Fire` / `ADSFire` = 5 rounds of climb,
  then 5 that repeat exactly (`"fire": {"loop": [12, 22]}` in `view_rifle_clips.json`: while the button is held the
  player jumps back from frame 22 to 12; letting go blends to Idle or back to the aim); `ADS` is parked at its aimed
  frame while RMB is down; `Sprint`'s running part (two strides) repeats while sprinting and is left at once when
  the player stops; the spider's `Turn` (stepping round on the spot, 60 deg/s to the left; played backwards = right).
- `scripts/v2/v2_assets.gd` (`V2Assets`): rebuilds every material by name from `materials.json` (StandardMaterial3D with
  object-space triplanar = Blender's box projection), cuts the baked "Scene" animation into clips
  (`AnimUtil.split_clips`; clip frames are **timeline** frames: the export keeps time = frame / fps), rebuilds the
  flashes' one-frame scale keys from the `flashes` list (the importer drops them) and lists when each flash fires
  (`flash_events`: shots come from these times, not from watching the flash meshes). `apply(root, asset)`: with an
  asset name, painted parts (`WEAR` table) get `v2_worn.gdshader` and that asset's mask.
- Shaders: `v2_worn` (paint worn to metal on edges, dirt in crevices, scratches, from the baked mask), `v2_glove`
  (knit / leather / tips by vertex-colour masks, projected from the rest pose), `v2_hazard` (the black / yellow
  stripes), `v2_flash` (muzzle flame from the UVs).
- **Colour space (measured, it cost a pass)**: the Compatibility renderer takes `ALBEDO` / `EMISSION` as sRGB and
  converts after the fragment function; the `source_color` hint converts nothing (textures and uniforms arrive as
  stored). Blender's numbers are linear. So: a `Color` given to a StandardMaterial3D goes through
  `Color.linear_to_srgb()` (`V2Assets._c`), and a custom shader that multiplies Blender tints must do it in linear
  itself: `pow(tex, 2.2) * tint`, then `ALBEDO = pow(col, 1 / 2.2)`. Applying linear tints to the stored values
  made the gloves blue and twice too bright.
- `v2_player.gd`: Camera3D with `fov 80` + `KEEP_WIDTH` (the Blender camera); each view glb hangs from it through its
  `Eye` node: `scene.transform = Rx(90 deg) * Eye^-1`; the camera follows `CamKick` (recoil, bob from the clips).
  The machine gun's rounds leave **along its barrel** and the HUD's cursor is where the barrel points (it climbs
  and jumps with the recoil; `aim_dir`, `aim_dot`). In Blender the gun is held toed in (barrel 6 degrees left of and
  4 above the line of sight), so tracers to the screen's middle looked bent: the whole view is turned about the eye
  until the barrel is parallel to the line of sight (`fix`, found from the Idle clip; faded out while aiming).
  **The pistol's cursor kicks too** (`_pistol_off`): its view is not turned (its barrel rests 9.5 degrees off the
  line of sight, and its picture stays as made); its aim is the line of sight turned by what the barrel is off its
  place of rest (the Idle clip's mean at the hip, the aimed pose at the eye: `rest`, `rest_aim`). The first 1.2
  degrees do not count (breathing, the walk's bob: a round at rest goes to the middle of the screen, as before).
  The muzzle flips 8.6 degrees in a shot and is back after 0.25 s, so only a second round at the gun's fastest
  (0.2 s) goes high, by about a degree. **The round takes the aim of the moment the trigger was pulled**
  (`_shot_dir`, set in `act`, **in the world's frame**: in the camera's frame it was turned up by the camera's own
  recoil by the time the flash came): the clip's flash comes a frame or two later, when the muzzle is already
  rising (the check caught it: the round left 7.8 degrees high). No aim offset while the gun is busy with something else or
  for 0.25 s after (`_settle`).
  The gun and arms are drawn by **their own camera** (`view_cam`, `GUN_LAYER`) into a transparent SubViewport laid
  over the world, under the HUD: a wall cannot cut into the gun, and the world camera zooms while aiming
  (`AIM_ZOOM` 0.78, mouse slowed to match) without the gun growing. Same world: the lab lets the lights of the
  room the player is in reach `GUN_LAYER` (`_gun_lights`). No glow or fog on that picture (halos on transparency).
  The aim is held on a still clip (`AimHold`, cut from ADS by `V2Assets.sub_clip`) and lowered by `AimOut`: never
  park a running clip by seeking it every frame.
  Health 100, regenerates after 4 s without a hit; at 0 the player is "down" for a moment, then revived in place.
  Damage: pistol 34, machine gun 12 a round.
- `v2_robot.gd` (`V2Robot`): states ROAM / ENGAGE / AIM / SHOOT / DEAD (+ PREVIEW = clip cycle). Numbers in `SPEC`
  (health, damage, spread, speeds, arena). The aim point lags the player by 0.3 s, so moving makes them miss. Spider
  and drone stay inside an obstacle-free rectangle of their room (`arena`).
  **Aiming is a servo on the barrel**: each frame the direction the muzzle really points (-Z of its flash node, clip
  and all) is compared with the direction to the target and the aim joints are turned by the difference: spider =
  `AimYaw` above its turret + `AimPitch` above its guns (nodes inserted at setup, the clips' tracks re-pointed
  through them: `_insert_aim`), drone = body pitch + the node's heading, turret = arm heading + `AimPitch` above
  the head. A round leaves along the barrel, wherever it points: a shot is never bent.
  The spider turns by stepping (`_step_round`, the Turn clip at the speed of the turn), not by sliding. A hit
  pushes: body knocked back and tipped on springs (`_springs`, `PUSH`), spider / drone shoved, the turret's arm
  swung aside; at 0 health: burst, Death clip, a smoking wreck (lowered onto the floor by the gap measured at
  setup: `_measure_wreck`), back after 6 s.
  Every joint that carries meshes has its own hit box (`_part_boxes`): a round strikes a part, alive or wrecked,
  and that joint and the ones it hangs from swing on springs (`_knock_joint`, `_flop`, `FLOP_LIVE` / `FLOP_DEAD`:
  a live joint twitches, a wreck's flops, the dead turret's arm swings like a pendulum). Not rigid-body physics:
  angular springs on the clip's pose. The robots' clips are advanced by the robot (`ap.advance` in `_process`,
  manual mode) so that aim and knocks go on top of the same frame's pose.
  The drone, shot down, flies on out of control for 2-3 s (`_spin_out`: faster and faster, turning at random,
  bouncing off the walls, spinning, shedding sparks), then falls (Death clip) and **explodes** where it lands
  (`V2Fx.explosion`; `BLAST`: up to 40 damage within 3.5 m). `v2_fx.gd` (`V2Fx`): tracers, impact sparks / chips / dust / scorch
  marks, smoke, flash lights.
- Sound: `scripts/v2/v2_sfx.gd` (`V2Sfx`): one table, a key per interaction (46; `assets/audio/v2/README.md`),
  `play(key[, place])`, `loop` / `drive` for the drone's rotors, `V2Sfx.heard` / `log` for the checks,
  `-- --no-sound`. **Robots' guns, third pass (user: "more aggressive")**: the crack squeezed harder and lifted
  at 2 to 6 kHz, less room, 3 dB up in the mix. Making the low layers louder was tried first and measured: in a
  file brought to the same loudness that leaves 1 to 3 dB less of the crack, heavier and duller, the opposite.
  Everything goes through one bus (`V2Sfx.bus`): a short room reverb, then +3 dB into a hard
  limiter (the machine gun's rounds pile up).
  Files: `assets/audio/v2/<key>_NN.wav` (117 one-shots, 8 MB: the built Vorbis files decoded again, see "V2 in
  the browser") and `<key>_NN.ogg` (the three loops), **all CC0, from opengameart.org**: the guns from The Free
  Firearm Sound Library (pistol = Walther PPQ, machine gun = AR-15, spider = Tikka .30-06, drone = Carl Gustav M45,
  turret = AK-47), the rest from foley packs (rubberduck, Thimras, Fantozzi, BMacZero, qubodup and others).
  `tools/fetch_v2_audio.sh` downloads the raw files to `assets_src/audio_v2/` (git-ignored; needs `py7zr`),
  `python3 -I tools/build_v2_audio.py` builds every file (`--report` prints loudness / peak / decay / energy per
  band of what is there), then `godot --headless --import` and keep `loop=true` in `drone_rotor_01.ogg.import`.
  **The guns are designed from the recordings (`gun()` in the build script), second pass**: a raw shot of the
  library is a dry 15-25 ms crack with nothing under 200 Hz (measured), which played as a thin pop. A game shot =
  the first 0.1 s of a real shot (after that come the field's echoes, which compression turns into a second bang)
  + the same shot one and two octaves down + a small 50 Hz thump (synthetic) + the slide / bolt from a reload
  recording, the crack squeezed by a look-ahead compressor (not soft clipping: tanh on the crack filled 4-20 kHz
  with fizz), then a synthetic room (`room_ir`), then eq. Robots' guns: mono, more room; use single mid-distance
  shots and rounds cut from the NEAR bursts (the mid bursts are a tangle of shots and echoes).
  **Levels are by loudness, not peak**: every file is brought to -20 dB (K-weighted, loudest 200 ms; `finish()`),
  so the dB column of `V2Sfx.SOUNDS` is the mix against the pistol (0). The peak-based first mix was upside
  down (slide 7 dB over the shot, servo 5 dB under it). Mind laptop speakers (the user's): nothing may depend on
  energy under 80 Hz (the first explosion redesign was all sub), and a servo at 8 kHz is piercing.
  **Nothing was judged by ear** (no sound here): designed against the numbers, foley picked by name, length and
  spectrum. A derived sound whose source licence cannot be checked is not CC0 for this project (one "machine
  shutting down" was dropped for that). A generative sound model was asked for and not used: the model hosts
  (huggingface.co) are outside this environment's network, and such a model's output has no clear CC0 status.
  `python3 -I tools/audition_v2_audio.py` -> `captures/v2/audition.ogg`: 45 s of every sound in a scene, mixed
  from the table as the game mixes it (for listening without starting the game, and for before / after).
  Timed sounds of the gun clips are `V2Player.CUES` (seconds into each clip, from anim_*.py).
- Wrecks (`V2Fx.smoke_column`, `sparkle`, `arc`; `V2Robot._shorts`): **user decision: electrical, not fire**. One
  thin grey thread of smoke (mid grey: light grey vanished against the white studio), and short circuits from a
  random part: blue streaks (blue, not white, for the same reason), a jagged arc, a blue-white glare, a zap;
  often just after death, then every 1-3 s; a wreck that is shot may spark. No flames, embers, fire light or
  fire loop. The drone's explosion keeps its fireball but leaves a small grey cloud.
- Light (`v2_lab.gd _environment`, tuned against `v2/renders/stage3_scene.png` zone by zone with
  `--capture=DIR --only=tone`): half of it is one DirectionalLight3D straight down (the luminous ceiling: bright
  floor, dimmer walls) and it casts the only shadows (one orthogonal pass; the room shell casts none); six omni
  lights per room without shadows, two spot lights under the mezzanine (spots: a mesh takes 8 lights of each kind,
  and the omnis are at 8 with the gun's fill and a muzzle flash); ambient 0.16; thin fog (at 0.012 it lifted every dark surface to mid grey); ACES.
  Each room is on its own render layer and its omni lights only reach that layer (`_layer`; the gun's layer follows
  the room the player is in): side by side, a room's big meshes would be in range of more than the 8 lights a mesh
  can take in Compatibility.
- Doorways: `export_godot.py cut_doorways` cuts an opening (1.3 x 2.25 m at Blender y = 10.2) through both side walls
  of `room.glb` and takes out the left wall's old door at y = 9; `v2_lab.gd` adds the steel lining / frame
  (`_door_frame`), a threshold, and closed leaves in the two outer doorways.
  The floor's collision is one flat box per room, not the tile mesh. Learned the hard way: a capsule stops dead
  against a 6 mm lip (the bevel left at the foot of a cut skirting plate), so openings are cut below the floor line.
- Checks (run after touching the player, robots or HUD):
  `godot --headless --path . -- --enemy-test` (each robot moves / aims, stays in its arena, fires, hurts a standing
  player, is pushed by a hit and comes back on its springs, is destroyed by the player's rounds and returns; the
  spider turns half round with its standing feet still; the player goes down and is revived; prints PASS / FAIL;
  headless has no meshes, so walls do not block anything in this test);
  `xvfb-run -a godot --rendering-driver opengl3 --path . -- --gun-test` (real events: machine gun held 2.5 s = no gap
  between rounds, stops on release; rounds leave along the barrel, cursor in the middle at rest and climbing in
  fire; the pistol's cursor in the middle at rest, up in a shot, back after it, its round along the line of sight;
  C aims and the view zooms, fire while aiming; the gun on its own camera; X crouches; a sprint ends when
  the player stops; the gun's and the player's sound keys were played);
  `xvfb-run -a godot --rendering-driver opengl3 --path . -- --input-test` (real mouse / key events through the
  viewport: look, fire, aim, reload, inspect, camera kick). The capture tour drives the player by code, so it passed
  while a HUD ColorRect at screen centre (mouse filter STOP by default) was swallowing every mouse event: HUD
  controls are `MOUSE_FILTER_IGNORE`, and the player reads the mouse in `_input`.
- Captures: `tools/capture_v2.sh` -> `captures/v2/` (everything), or
  `--capture=DIR --only=tone,rooms,doors,guns,look,ai,wreck,fx,panel` for parts (`tone` = the Blender camera's frame;
  `look` = materials close up; `ai` = each robot moving, firing, wrecked (prints how far the wreck's lowest point is
  above the floor and where its barrels point); on request only: `wreck` = burst, smoke, a short circuit, `fx` = hits on a wall,
  `panel` = 12 consecutive frames of the machine gun, to look for flicker, `adsfire` = 215 frames at 1/60 s of
  aiming and firing with real input (it caught the one-frame hand), `wall` = each gun nose against a wall and the
  view crouched behind cover, `spin` = the drone shot down, flying, crashing, burning).
  Scratch tools worth rewriting when needed: a "pops" script (step every clip in half frames and print the largest
  bone move / turn: it found the hand flips) and a clip strip (frames of one clip side by side).
- Performance: `F3` in the lab shows fps / frame time / draw calls / triangles / objects / video memory / adapter;
  `-- --perf` prints that line for 12 s and quits; `-- --quality=low` = no shadows, glow or MSAA (exposed up to match).
  Measured here (counts do not depend on the GPU; fps here is llvmpipe, ~8 whatever is drawn): studio rooms
  232 draw calls, 224k triangles, 166 MB; the concept room (`--concept`) 334 / 706k / 192 MB (249 / 629k / 160 MB
  at low quality). History: shadow-casting omni lights were
  the cost (two per room = 1,935 draw calls, 7.8 M triangles), and the gloves were 65k of each view's faces.
  The user's M1 gave 77 fps at 1280x720 before the enemies and the look work; not measured since.
- Learned in the feedback round:
  a forearm twist that wraps at +-180 degrees flips the forearm bones between two keys, and the game, interpolating
  between them, shows the hand turned half round for a frame (it was in eight clips): `hands.pose` keeps the twist
  continuous (`TWIST_REF`, reset by the baker per clip);
  a looping clip of n frames must last n frames, not n - 1 (`V2Assets.clips`): one frame short, a walking foot
  jumped 3 cm every cycle;
  an object stored hidden (scale 0) has no rotation in its matrix: the ceiling turret's muzzle flames, turned a
  quarter to lie along the barrels, pointed sideways (read `rotation_quaternion`, set the mode before placing);
  two faces in one plane, or 0.25 mm apart on a gun 0.5 m from the eye, flicker (the machine gun's screen):
  keep 0.6 mm or more between layers;
  explicit springs (the hit push) are stepped at 8 ms whatever the frame time.
  Two clips the game blends between must describe a shared pose with the same bone turns: aimed fire starts from
  the aim, and its forearm twist was a full turn from the aim clip's, so the blend swung the hand through half a
  turn for single frames (`Baker.clip(seed=...)` starts a clip from another clip's twist).
  `Object.get_meta(name, null)` still errors when the meta is missing: test `has_meta`.
  Set an AnimationPlayer's `speed_scale` before `play()` / `seek()`, not after: a clip started while the speed is
  still negative (the spider's right turn plays its clip backwards) ends on the spot. A spider killed in mid-turn
  stood frozen; the sound check caught it one run in five ("crash" never played).
- Learned: "hidden by scale 0" breaks Godot's glTF import (node comes in at scale 1): export hides at 0.001.
  A fine weave seen at arm's length beats against the pixel grid even with mipmaps: the glove fabrics are sampled
  with a mip bias. A directional light with shadows on came out about half as bright again as without.
- Not done yet: a browser build of V2; music in the game itself (the user wants it in the menu only); V1 (its Quaternius art, enemies and UI) still runs with `-- --v1`;
  its generator is what the V2 game builds on.
  User decisions: realistic recorded sound, CC0, one consistent line, no music for now; no browser build of V2 for now (`tools/export_web.sh` is untested with V2);
  studio rooms in the lab; the game has PLAY and LAB and is the generated dungeon of the GDD in a new modular kit (the concept room is not in it);
  wrecks are electrical (no fire); the pistol wears the machine gun's colours; footsteps quiet and dull, in step
  with the walk; a drone shot down goes down in a straight line; the dead turret is heavy; no reload at a run;
  going down = a fall onto the side, the gun on the floor, the robots coming to look, then the options;
  the map's detail is modelled in Blender from the user's 24 reference sheets (the environment set, approved and in the game);
  robots tougher and more aggressive from the start; their guns sound more aggressive; the turret is a gatling
  (wind-up, 15 to 20 rounds); wrecks are solid; the training dummy is destroyed by the last round; a run opens
  with fades and the gun's draw and inspect; the menu's music is Exploration Theme;
  the interface is the user's UI concept (ammunition on the HUD, not on the guns); "the gameplay feels really good".

## V2 game: the generated dungeon (`scripts/v2/v2_game.gd`)

**User decisions (this replaces the hand-built four-sector level):** the game follows the GDD's loop: every run a
fresh dungeon of 8 to 12 rooms joined by corridors and doors, robots, loot and one exit portal scattered through
it; ROOMS n / N; a map; score; AGAIN after a win = a harder dungeon, with no end. The title keeps PLAY and LAB.
A new modular kit only (the detailed concept room is no longer in the game; it is the title's backdrop and still
the lab's `--concept`). Free doors (E opens any door at any time). Spiders and drones chase; turrets stay.
- Layout: `scripts/dungeon_gen.gd` (`DungeonGen`, V1's, unchanged: pure data from seed + difficulty; 4 m cells;
  rooms 3..6 cells a side; corridors 1 cell wide; a tree from the spawn room; the exit in the deepest room; doors on
  about half the doorways; `enemy_spawns` turret / brawler / pursuer = our turret / spider / drone; `loot_spawns`;
  `deco_spawns`). `-- --seed=N` gives the same dungeon again; `-- --threat=N` starts at that threat level.
- Kit: **the environment set** (`assets/models/v2/set.glb`, 44 pieces; see "The environment set" below). The kit
  before it (`v2/scripts/build_kit.py` -> `kit.glb`, 51 pieces, and `build_props.py` -> `props.glb`) is no longer
  loaded by the game: the user found its pieces poorly designed. Its files stay in the repository.
  Rooms 5.2 m high (the turret's pylon ends there), corridors 3.4 m, doorways 2.4 x 2.6 m (every robot fits).
  `xvfb-run -a godot --rendering-driver opengl3 --resolution 480x360 --path . -s tools/v2_kit_sheet.gd -- DIR 0 set.glb`
  = a picture of every piece in the game's materials (look at new pieces there before placing them).
- `scripts/v2/v2_dungeon.gd` (`V2Dungeon`): an area per room and per corridor, built from the set. A room cell =
  eight floor tiles (1 x 2 m: `floor_plain`, now and then `floor_grating`, `floor_hazard` in front of every doorway
  and under the exit) and four ceiling panels (2 x 2 m: `ceiling_plain`, one `ceiling_light` on a lit cell, now and
  then `ceiling_services`; a turret's cells stay plain). A wall edge = two columns of `wall_plinth` (0.4 m) + a
  3 m panel (`wall_plain` / `wall_screen` / `wall_service`, dealt by the theme) + `wall_upper` (1.8 m), set back by
  `FACE`. A doorway = `door_frame` + `door_surround` on each side of the wall, two `wall_upper` above, the leaves
  `door_leaf_l` / `door_leaf_r` as nodes (they slide by `LEAF_SLIDE`; lamp amber -> green). A corridor cell = one
  `corridor` section, shortened where it meets a room's wall. **Themes** (`THEMES`: lab, storage, server, power,
  workshop; dealt so that all five come up before one repeats): a room's theme picks its wall panels, how often
  the ceiling carries services, what stands at the inner corners of its cells (`stand`) and the equipment along
  `FILL` (60 %) of its free wall cells (`along`); a tank's liquid has the room's colour (`TANKS`). Each area is
  **two merged meshes** (`_meshes`: the shell, and what stands in it, which casts shadows), one surface per
  material, so furniture costs no draw calls. Lights: their cull mask = the area's render layer; areas within 13 m
  of each other get different layers, 9 of them (a mesh takes 8 lights). **Collision as boxes made from the
  layout** (walls, doorway sides and lintels, floors, ceilings, `DECO_BOX` per standing piece): it exists headless,
  so every check and the bot run headless. `path(a, b)` = cells through open doorways; `arena(area, margin)`;
  `update()` hides areas more than `SEEN` (28 m) away and lets the player's area's lights reach the gun.
  `V2_TRIS=1` in the environment prints each area's triangles and pieces.
- **What stands against a wall may be 1.3 m deep at most** (`_against` asserts it): the specimen tank, 1.5 m deep
  plus its gap, reached to 15 cm from the middle of its cell, where the robots and the bot walk; the bot hung in
  seed 18 for the whole of its 15 minutes. Tanks stand free (the `stand` lists) now. Found by the balance run:
  **a bot run that takes several times longer than the others is stuck, not slow** (`V2_BOT_STUCK=1` prints where
  it stands and what box is in front of it; `V2_STAND=1` prints every piece placed; both on stderr: a headless
  run that is killed loses what it printed to stdout).
- Dressing (**user: denser big rooms, some grime, a colour per theme, corridor variants: "ok"**): a theme has an
  `accent` (the paint of the line round the room: a strip on `wall_plinth` and one at the foot of `wall_upper`,
  material `EAccent`, recoloured per theme by `V2Assets.accent`: lab teal, storage ochre, server blue, power red,
  workshop green), a `light` (a slight tint of its lamps) and `small` things (crate, drum) that `_beside` puts next
  to cover shallow enough to keep the pair within 1.2 m of its cell corner, and `_against` now and then beside a
  piece along a wall; rooms of 5 x 5 cells and more always have something in their middle and a few pieces off the
  pattern; `FILL` 0.7. Corridors: `CORRIDORS` = `corridor` (wire tray, rail), `corridor_b` (a display, a duct),
  `corridor_c` (three pipes with a valve): one kind per corridor, one cell in five another.
- Light of the dungeon (`v2_game.gd`: `_environment(0.38, 0.25, 22.0)` = ambient, the light straight down, how far
  it casts shadows; room lamps 0.25): **more even light than the lab's**. With the lab's numbers a prop's side
  turned away from the two or three lamps of its room was nearly black (white drums looked dark grey: it read as
  wrong materials, and it was the light), and the floor under the lamps bleached, so what is walked on has its own
  paint a tone under the walls' (`EPaintFloor`).
- Robots (all children of the game node: world frame): placed on the middle of a cell; **spider and drone go from
  cell middle to cell middle along rows and columns** (`V2Robot.grid`, `_spot`: columns and tanks stand at the cells'
  corners, so they are never walked through). One that has seen the player (or heard a door open within 16 m) and
  lost them follows along `V2Dungeon.path` (`V2Robot.follow`, state TRAVEL; a drone comes down to 1.7 m in
  corridors and doorways; it stops and fights when it sees the player within 11 m; `arrived` -> the game gives it the
  arena of the area it stands in, a corridor too). The turret hangs on a rail of at most 4.8 m. Robots more than
  48 m away sleep. The robots of a room keep off each other's firing positions (`others`).
- Rules (`V2Player.rules`): pistol 15 rounds, unlimited magazines; machine gun 30 + 60 carried (max 240);
  no health regeneration; med kits (H, +40, max 3); E = nearest shut door or crate within 2.4 m; going down ends the
  run. Crates give what the generator says (ammunition +60 / health +35 / a med kit); 35 % of wrecks leave something
  (`roll_payoff`: med kits thin out with the threat level), dropped beside the wreck on the player's side.
  **Wrecks are solid (user: "make all dead robots solid, so the character has to jump through them")**: when a
  spider's or a drone's wreck has come to rest it gets one box (`V2Robot._wreck_solid`: the footprint of its part
  boxes x 0.8, so leg tips stick out of it; `WRECK_TOP` 0.55 m high: a jump reaches 0.83 m, and one can stand on
  it), not while the player stands in it; rounds that strike the box strike the wreck (meta `wreck`). **The
  turret's wreck is not solid**: it hangs from the ceiling with its head at the player's, which shut the middle of
  its cell to the player and the bot (the game check hung there), and nobody jumps over that. The bot jumps when
  it has stood still for 0.25 s (`V2Player.bot_jump`).
  **No reload at a run** (R is ignored while Shift + forward, the automatic reload waits, and a reload under way
  holds the player to a walk): user decision, lab too.
- **Going down** (user's direction): the player falls onto their side (`V2Player._fallen_view`: 0.8 s, eye to
  0.17 m, rolled 83 degrees away from where the round came from, a small bounce), the gun leaves the hands and
  lands on the floor in front (`_drop_gun`: a copy of the view's gun without the arms, in the world; the view is
  switched off), the robots that can get there within `GATHER` cells come and stand round the player, in front of
  their eyes first (`RING`), guns on them, without firing (`V2Robot.watch`, state WATCH: free of the cell grid for
  the last stretch; a drone comes down to 1.25 m; turrets turn their heads); the options fade in once the first has
  stood there 1.6 s (`DEATH_WAIT`: 3.4 s at the earliest, 9 s at the latest).
- **Threat level** (`missions`, static: missions completed in this sitting; TITLE resets it), applied by the game
  (the generator always runs at threat 0: its own scaling, +0.5 robots a room and +20 % health a level, is not used,
  and its extra robots reshuffle the loot, so two levels of a seed could not be compared): one more robot in the
  dungeon per level (`MORE`: rooms two or more from the start first, the biggest first, until the generator's
  places are used up), robots' health +6 % per level without end (`HP_PER_THREAT`), med kits rarer in crates and
  wrecks (`_kit_weight`: 4 at threat 0, 1 from threat 4), a kill worth +25 % per level. A seed's dungeon is the
  same at every level but for those (kept that way on purpose: the crates' second random draw is on its own
  stream). Score = kills only.
- **Robots of the dungeon** (**user, after playing: "more health and more aggressive from the start"**): `TOUGH` =
  spider 150, drone 85, turret 170 health (about the lab's), aim lag 0.14 / 0.2 / 0.2 s, pauses between bursts
  divided by 1.35; `CROWD` = 0.75 of the generator's robots kept, at most 4 in a room, 2 in a room next to the
  start (11 to 22 a dungeon at threat 0); a robot within `HEAR` (24 m) of the player's gunfire is alerted and comes
  through the doorways, and one that loses sight of the player follows after 1.2 s.
- **The turret is a gatling (user: "play a sound like a rolling gatling gun before firing, and make it fire
  longer, like 15-20 shots instead of 2-3")**: on target it winds up for `SPIN_UP` (0.85 s, sound `turret_spin_up`;
  it goes on turning with the player meanwhile), then plays the firing part of its Shoot clip (4 rounds, frames
  4 to 20 of the clip: `GATLING`) at twice the speed 4 or 5 times over = **16 or 20 rounds at 11 a second**, then
  `turret_spin_down` + `turret_tail` and its pause. A round does 2.5 (it was 7 for 4 rounds; a whole burst on
  target was 28 and is 40 to 50, spread 0.8 degrees, and it sweeps after a moving player). Losing the player
  during the wind-up runs the barrels down again. Pictures and the count: `--game-capture=DIR --part=wrecks
  --match=turret`.
- **Balance, measured with the bot** (`tools/v2_bot.sh N threat first_seed`: headless, the clock four times as
  fast, about 1.5 minutes a dungeon; three batches side by side on this container's four cores; **the container
  only runs while a command of the session is running: wait for a batch with a blocking loop, not by coming back
  later**). Seeds 10 to 18, with the robots above: **threat 0: 9 wins in 9** (the bot's lowest health after a room
  23 to 70; 70 to 87 % of its rounds hitting), **threat 2: 6 in 9, threat 4: 3 in 9** (threat 2 was measured with
  the climb at 1.5 robots and 8 % a level, where threat 4 gave 2 in 9; it is a little gentler now).
  **On the environment set, dressed** (same seeds, the pistol's kick in): **threat 0: 8 in 9, threat 2: 7 in 9,
  threat 4: 3 in 9**: the same within what nine runs can tell (the lowest health after a room at threat 0: 48 to
  65). Seed 17 is lost at threat 0 and 2 with 36 to 52 % of the rounds hitting where the others have 70 to 93 %:
  somewhere in it the bot fires at a robot it sees and cannot hit (not looked into).
  **With the gatling turret and solid wrecks** (same seeds): **threat 0: 9 in 9, threat 2: 8 in 9, threat 4: 7 in
  9** (it was 3 in 9): the turret's wind-up gives the bot 0.85 s to shoot first and a round does 2.5, so the top
  levels are easier for the bot than before. Not retuned (the user has not played it yet); if it plays too
  easy: `SPEC.turret.damage` 3 to 3.5, or `SPIN_UP` shorter. No run was stuck on a wreck.
  History: with the first robots (100 / 60 / 110 health, 0.6 kept) it was 11 in 12, 9 in 9, 7 in 9, and 5 in 9 at
  threat 6, and the user found the game too easy.
  **What went wrong on the way (it cost four tuning rounds):** the bot aimed the camera at a robot while the
  machine gun's rounds leave along the barrel, which climbs in a burst; it fired whole magazines over robots'
  heads (186 rounds for one kill in one room) and its 1-in-6 results were read as "too many robots". It now pulls
  against the climb as a player follows the cursor (`PULL`), and prints its hit rate: look at that number before
  believing a loss. And 6 to 8 runs a level are noise (the same settings gave 6 of 8 and 3 of 8).
  The bot clears every room (a player may walk past rooms), aims better than a trackpad allows and uses no cover:
  read its numbers as how the threat levels compare, not as how hard it feels.
- Cost of a room view (the capture prints it; `--part=rooms` prints it for every room): 300 to 850 thousand
  triangles, 100 to 620 draw calls (the old kit: 270 to 310 thousand). A room's shell is 110 to 290 thousand
  triangles (225 floor tiles of 292, service wall panels of 4,900), what stands in it 16 to 136 thousand; all of an
  area is drawn as soon as a corner of it is in view. Frame rate on a real GPU: **not measured** (F3 in the game);
  if it is too low: fewer service panels, tiles of 2 x 2 m, `SEEN` lower.
- **Frame rate on the user's M1: 50 fps** (full screen, 252 draw calls, 472k triangles), measured after the set went
  in. The window on a Retina display is 2560 x 1600 pixels, four times the 1280 x 720 of the 77 fps measured
  earlier, so the cost was taken to be pixels, not triangles (24 million triangles a second is little for that
  GPU). Done for it: the 3D picture is drawn with at most 1080 rows and stretched (`V2World.RENDER_ROWS`,
  `_render_setup`; **F4** steps through 1080 / 900 / 720 / the window's own; the HUD keeps the window's pixels;
  `scaling_3d_scale` does work in Compatibility 4.3, checked); `v2_set.gdshader` does four texture lookups a pixel
  instead of six (no roughness map, streaks from the broad-patch lookup, only colour and normal anisotropic); the
  directional shadow is filtered with 5 samples instead of 13. **F3 now also shows** the 3D picture's size and,
  where the driver reports them, the time spent drawing on the CPU and the GPU and in the game's code: read those
  before cutting anything else. Not measured again yet (the user's next run).
- Map (`scripts/v2/v2_map.gd`, Tab; the game goes on): rooms entered, robots still working in each (red number),
  corridors walked, doorways (amber shut / green open / grey no door), the exit once its room was entered, the
  player. Scaled to the whole dungeon, so the empty part of the panel says how much is left.
- **UI: the user's concept** (`v2/reference/ui/README.md` = the spec, `screens/*.png` = the targets at 1440 x 810,
  `tokens.json`; "use it as a starting point and use your best judgement in case you need to cover a corner case").
  Kit: `assets/ui/fonts` (Barlow, Barlow Condensed: **SIL OFL, not CC0: the user's choice**, `OFL.txt` beside them),
  `assets/ui/icons` (white SVGs, tinted; mipmaps on in their `.import`), `assets/ui/shaders` (`screen_blur`,
  `damage_vignette`, `scanlines`), `scripts/v2/ui_palette.gd` (`UIPalette`: the concept's own file, colours and
  boxes). `V2Ui` (`v2_ui.gd`): `font(weight, size, tracking em)` (tabular figures), `text`, `icon`, `keycap`,
  `panel`, `row` / `column`, `at(control, ax, ay, x, y)` (pins and grows away from the edge), `full`, `button`.
  **Canvas 1440 x 810, aspect expand** (`V2World._render_setup` sets the window's content scale; V1 keeps the
  project's 1280 x 720): a 16:10 screen shows more height, no black bars (the arms hold: checked at 1440 x 900).
  Layers: gun 1 (V2Player), hit blur + glow 2, HUD 4, map 5, end screens + Esc menu 6.
  - HUD (`v2_hud.gd`, `V2Hud`): room panel (ROOM nn / tt = rooms entered; hostiles here or "Room clear. Find the
    exit portal."; exit not located / n rooms away along the room tree / in this room), THREAT and [TAB] MAP
    chips, health (number, 20 segments, cyan, orange at 40 and under with the border, the blinking cross and
    "LOW · BREAK LINE OF SIGHT"; lost segments linger as a ghost 0.4 s, healed ones sweep in white), three kit
    slots, weapon tiles, cursor (ring + dot at `aim_dot`; orange with brackets when the next round would strike a
    live robot; four ticks on a hit; smaller while aiming, and the panels fade to 40 %), **E OPEN DOOR / OPEN
    CRATE only within reach** (`game.in_reach`: the concept adds this prompt on purpose, to teach the range; it
    replaces the GDD's "no interact prompt" for V2), a hit = blur 3 -> 0 in 0.5 s + orange glow on the side it
    came from + a 90 degree arc toward it. A pickup: a chip at the foot of the screen (`say`).
    **Ammunition is on the HUD** (**user, mid-task: "no need for that [screens on the guns], let's show
    ammunition in the HUD"**): a readout above the tiles in the concept's weapon-screen styling: magazine /
    reserve + a bar, orange at a quarter, RELOAD with a filling bar, "1 · PISTOL" when the machine gun is out of
    everything; the pistol reads "15 / infinity" (this game's pistol has magazines).
    Answers to what the concept left open: the kit key cap says H (Q switches gun here); in a corridor the lines
    speak of the corridor; the cursor rides on the barrel, the prompt stays by the middle.
  - Map (`v2_map.gd`): the white board with the plan from the layout (entered rooms graphite, numbered in the
    order found (`game.order`); the current one cyan with the arrow; the rest dashed with "?"; corridors solid
    between two entered rooms, else dashed; shut doors as bars; orange badges = robots alive in an entered room;
    the exit's sign once found), ROUTE and KEY cards. In a corridor the arrow stands in a cyan disc. The HUD is
    hidden while it is open.
  - End screens (`v2_end.gd`, `V2End`): Mission complete (grey page, split title that jumps every 3.2 s, SCORE /
    HOSTILES / ROOMS, THREAT nn -> nn, ENTER DATASPACE nn / STOP HERE) and Signal lost (the view blurred 4.5 and
    washed, dark edges, an orange band, scan lines; RE-ASSEMBLE = a new dungeon at the same threat / STOP HERE).
    Enter = the first button. Signal lost comes after the fall and the robots gathering, as before.
  - Title (`v2_title.gd`): the white page, PROJECT / FIREWALL, PRESS ENTER; any key or a click starts a run.
    **How a run opens (user's direction; second round: "the letters all fade into white, and the same white
    fades out into the game, more slowly")**: the title's letters fade into the page's own white (1.3 s, the music
    going down with it), the game comes up under the same white (`V2World.open_from`, set by the title;
    `V2Game._opening`), the white lifts off the room in 3 s
    (**the sheet is one node hung from the tree's root, `V2World.cover` / `V2World.veil`, layer 100, and lives
    through the change of scene**: with a veil in each scene the engine drew its grey clear colour for the frames
    between them, while the dungeon was built, and the user saw "a gray screen, then white"; `again()` covers
    the same way; `_opening` fades the sheet out and frees it) with no gun and no HUD (a run started
    from an end screen opens out of that screen's grey in 1.4 s), then the gun comes up (Draw) and is turned over
    once (Inspect; only on the run that has the training), and only then the keys and the mouse answer
    (`V2Player.locked`) and the HUD fades in: about 9 s from the key to control. Not for the bot, the checks or
    the pictures.
    Frames of it: `-- --title --open-capture=DIR` (`V2World.film`: every frame as a jpg with its milliseconds).
    **No menu: the lab is on L** (not shown), `--lab` as before. Esc in the game: a small glass card, RESUME /
    STOP HERE ("the run keeps going").
  - F3 (frame rate) sits under the room panel. Pictures of all of it: `--game-capture=DIR --part=ui` at
    `--resolution 1440x810` (HudExplore, HudCombat, HudLow, HudLowMagazine, HudReload, HudHeal, HudPickup, Map,
    Failure; Mission complete is the tour's `13_won`), `--title --title-capture=FILE`.
  - Learned: `set_anchors_preset` on a control already in the tree keeps its (zero) size: use
    `set_anchors_and_offsets_preset` (everything pinned to the right or the bottom was off screen); the blur
    shader's `textureLod` on the screen texture works in Compatibility on the desktop **and gives black in the
    browser** (see "V2 in the browser"); a Button's own icon is drawn at the
    texture's size (the words and icon are children of the button); headless `--play` prints nothing useful.
- **Training in the first room** (**user's five points**: a dummy target (a spider on a yellow-striped box); aim
  with the pistol and shoot it; switch to the rifle, aim and shoot it; a med kit from a crate; E opens a door and
  the game starts). `v2_game.gd`: `training` (the first run of a sitting: static `trained`; never for the bot, the
  checks or the pictures; `-- --no-training` skips it, `-- --training` forces it), `train_step` 0..3,
  `TRAIN_HITS` [3, 6]. Before `build`: `dungeon.locked_room` = the spawn room (**every doorway of it gets a door,
  shut and locked**: `doors[i].locked`, `unlock()`; E there says "Locked · finish the training" and no prompt
  offers it), `dungeon.keep_clear` (nothing is stood round the dummy), the room's crate is made to hold a kit.
  `_training_spot` = **the middle of the room** (user: "in the center of the training room, not in the corner";
  it was a cell near a wall); **the player appears in front of the cage's door, facing the dummy** (user;
  `_training_start`, `start_at` / `start_yaw`: 6 m from it, less in a small room, along a row or column, with
  the way the generator would have had them look beyond the cage; `keep_clear` round both opens the line).
  **Robots go round the cage (user)**: `V2Robot.no_go` (static: squares [middle, half side], here the cage and
  0.85 m for the robot; emptied by every scene's `_ready`): in `_move` a target inside is moved to the edge, and
  where the straight way crosses the square the robot heads for a corner of it first (`_round`, the corner kept
  in `_via` until reached: choosing afresh every frame, it turned back and forth between two corners; and the
  square it plans with must be the one its place is kept out of, or it stands at the edge for ever); the
  row-then-column rule is dropped for a leg that would lead in. `V2Dungeon.blocked` = cells no path leads through
  (the cage's, in a room with an odd number of cells). Check: the training test sends a spider and a drone past
  it four ways each (`_cage_check`); `_training_build` = a dark plinth with two `floor_hazard` tiles on it, the spider on top and **the cage round
  it** (user: "give the impression that the dummy robot is caged", from their reference picture, "use this as
  inspiration but make more spaced bars": `training_cage` of the set, 3.2 x 3.2 x 2.6 m, `set_cover.py`: white
  corner posts with grey shoes and lifting eyes, a base frame with hazard stripes, a framed door toward the
  player with hinges, a bolt, a control box and cables, two thin bars 0.84 m apart in the door, four a side, the
  X brace on the back only, an open top so the room's light reaches the robot). Its posts stop everything; its
  bars are boxes on physics layer `V2World.CAGE` (4), which only the player's body collides with: **every ray
  that is a round or a look uses `V2World.SHOTS`** (the player's rounds, the HUD's cursor, the robots' sight and
  rounds), so rounds go through the bars
  (`V2Robot.dummy`: it stands in the preview's Idle, a hit jars it on its springs and emits `struck`, it is not
  in `robots`, so no count, no score, no hostile line). **It suffers (user: "more reactive to the shots he's taking, like he's alive. make him 'suffer'"; then
  "different animations", "longer and less twitchy")**: `V2Robot._dummy_tick`. Calm, its head follows the player
  round the room. Struck, it plays one of **five reactions** (`REACTIONS`, never the same twice running, about
  3.5 s each): cower (leans back, steps uneasily, head aside), stagger (thrown to a side, sways there and back),
  buckle (the start of the Death clip: its legs give, then a 1.2 s blend back up), rear (front up, down, a slow
  shake of the head), turn (steps round away from the shot, stands, steps back). **Every pose is a target the body
  follows smoothly** (`_rx_tilt`, `_rx_pos`, the head at a limited rate, clips changed with long blends,
  `_ease_to`): the first version drove it with random impulses every tenth of a second, which the user found
  twitchy. Struck again while a reaction lasts (the machine gun), it does not start over: deeper, held longer.
  Wounds stay: it heaves as it breathes, lists a little, smokes from the third, shorts now and then from the
  fourth. Pictures of all five: `-- --training --game-capture=DIR --part=reactions`.
  **Feet planted (user, with a screenshot: "the spider is kind of 'floating' when shot. make it more grounded")**:
  a push, a tilt, a swinging joint and the reactions all move the root or the body, and the legs (children of the
  body: `Spider_Hip/Thigh/Shin/Foot0..3`) went along as one rigid piece, feet in the air. `V2Robot._feet_read`
  (right after the clip has posed it: where each foot is in the root's frame) and `_feet_plant` (at the end of
  `_pose`): each leg is solved again, the hip turned about the upright, thigh and shin bent in the leg's plane
  with the knee on the side the clip has it, until the foot is where the clip alone would have it. **For every
  live spider, not only the dummy.** The training test measures it: 0.0 mm off through four reactions, 39 mm in
  the buckle, where the legs fold as far as they go.
  **The last round of the rifle step destroys it** (user;
  `V2Robot.finish_off`: the usual burst, Death clip and smoking wreck, solid, on its pad: `floor_y`). A hit counts only **aimed** (`player._aimed` > 0.6) and
  with the step's gun; otherwise a chip says why. The kit step ends when the player holds a kit, then the doors
  unlock; a door of the room opening ends the training: the rounds fired are given back, the clock starts, and
  **while it lasts the robots beyond hear nothing** (`_robots_tick`). HUD: a card top middle (`V2Hud._training`:
  "TRAINING n / 4", the step with its key caps, the hit count). **While the training lasts the HUD is the card,
  the cursor, the E prompt and the pickup chip only (user); the room panel, chips, health, kits, weapon tiles and
  ammunition fade in when it ends** (`V2Hud._rest`).
  Check: `godot --headless --path . -- --training-test [--seed=N]`; pictures: `-- --training
  --game-capture=DIR --part=train`. `V2Player.bot_aim` holds the aim for the checks.
  Also fixed on the way: `keep_clear` holds the player's spawn point too (the middle of a room with an even
  number of cells is a cell corner, where cover is stood: nothing guarded it); **the pistol's round goes where
  the cursor was when the trigger was pulled, in the world's frame** (`_shot_dir`): taken in the camera's frame
  it was turned up with the camera's own recoil by the time the flash came.
- **Menu music** (**user: "we need to add some music in the menu; when game starts, we only hear the lab
  sounds, no more music"**; this replaces "no music for now" for the menu only). `scripts/v2/v2_music.gd`
  (`V2Music`): starts on the title, fades out when a run or the lab starts (the player node hangs from the tree's
  root, so it fades across the change of scene); the game has the room tone as before, the title no longer has.
  **The track: Exploration Theme** (Cleyton Kauffman, CC0, opengameart.org; 2:14, loops seamlessly), **chosen by
  the user** out of three candidates ("first music is fine"); the other two and the M key that stepped through
  them are gone. `tools/build_v2_music.sh` (raw file in `assets_src/music_v2/`, URL in the script) ->
  `assets/audio/v2/music/menu_exploration_theme.ogg` at -23 LUFS; `loop=true` in its `.import`. Level
  `V2Music.LEVEL` (-5 dB).
- Props (from the set): loot crates `loot_crate` (health), `loot_crate_olive` (ammunition), `loot_crate_green` (a
  med kit), lid under `Crate_Lid` (found with `find_child("Crate_Lid*")`: Blender numbers the duplicates), the
  lid's cyan lamp goes dark when opened; what a crate or a wreck leaves: `ammo_box`, `medkit_white` (health),
  `medkit` (a med kit: red case, white cross, as in the user's reference); `exit_portal`, standing free in the
  middle of the deepest room, its field `v2_portal.gdshader`.
- Checks, bot, pictures (`scripts/v2/v2_game_bot.gd`), all headless except the pictures:
  `godot --headless --path . -- --game-test` (seed 7): the generator over 40 seeds (8-12 rooms, every cell reachable,
  exit deepest, more robots at threat 3), walls stop rays, magazines, a crate, a med kit, no regeneration, a door
  (shut it blocks the way and the paths), wrecks stay, a robot follows the player out of its room, the turret's
  rail, a wreck stops a walk and a jump goes over it, the walk through every room with a wreck in every robot's
  place (ROOMS counts), the exit raises the threat level, going down does not, the
  fall and the dropped gun, the robots coming to look without firing, sounds;
  `tools/v2_bot.sh [N] [threat] [seed]`; `xvfb-run -a godot --rendering-driver opengl3 --path . --
  --game-capture=DIR [--seed=N]`; `... -- --title-capture=FILE.png`. With `--part=NAME` the capture is one of:
  `drones` (the robots by kind, and each drone: where, drawn or not, a picture of the first three; headless it
  prints the count alone: the user asked whether drones appear; seeds 7 and 33 have 6 and 9, all drawn),
  `wrecks` (with `--training`: the dummy destroyed, a spider's and a drone's wreck with their boxes drawn in
  orange, a turret's burst; `--match=turret` = the turret alone),
  `rooms` (every room, or `--match=2,5`, from two corners without gun or HUD: 40 s for two rooms; the quick look
  at the set and the light), `death` (frames of going down), `marks` (bullet holes on a wall and the floor), `flicker` (at every doorway and
  in every room three frames: on arriving, 8 frames later, 1 mm aside; `python3 -I tools/flicker_diff.py DIR`
  lists the views where most pixels changed and writes them with those pixels marked; ~10 minutes; robots and the
  exit's field show up in the first comparison, edges of thin lines in the second: look at the marked pictures).
- Learned here: bare metal the size of a duct or a shelf comes out near black indoors: the second set uses
  `PaintGrey` for those; a check that passes with "0 could come" proves nothing: the going-down check puts two
  robots back first; the title routes `--only=` to the lab, so the game's capture parts are `--part=`;
  a wall of the kit may reach 0.12 m into the cell at most; a large flat metallic surface (the
  first locker, the first door leaves) comes out black indoors (it mirrors the dark HDRI): paint it; a ray along
  the seam between two collision boxes passes between them (the door check aims through one leaf); an `await`ed
  bot function that errors never returns: guard freed pickups with `is_instance_valid` before every use.
- **Flicker (user: "lights flicker, under an open door"), what it was**: two faces of different materials in one
  plane. The doorway's dark lining was flush with the opening cut in the white wall slab, the sill lay level with
  the corridor's grating (and the two are lit by different areas' lights), an open leaf's end showed its armour
  and its edge strip in one plane, and **a corridor's side walls ran to the end of their cell, so their end faces
  lay in the plane of the room wall's face: a strip 0.3 m wide beside every doorway** (found last, in the marked
  pictures; a first guess, the open leaf's shadow, was wrong: check a fix with `--match=TEXT`, which limits the
  flicker capture to the views whose name has TEXT in it, 1 minute). Now the lining stands 3 cm proud (`LIN`),
  the sill is a raised plate, the leaves go fully into the lining, a corridor wall next to a room is shortened by
  the wall's thickness (`_area`); the walkway grating and the wall panels are calmed (`V2Assets.CALM`: a polished,
  strongly normal-mapped metal throws single bright pixels that crawl), the floor joints are 3.6 cm of dull grey
  (2.4 cm of near-black was thinner than a pixel a few rooms off). It was not the lights: the engine pairs lights
  with meshes by cull mask (read in the 4.3 source), no mesh has more than 6, and nothing flashes on changing area.
  Rule for the kit: never two materials in one plane; flat things on the floor at 0.008 or higher.
- Bullet marks (`V2Fx.scorch`, `assets/shaders/v2_bullet_hole.gdshader`): a quad of ~0.36 m drawn by a shader: the
  hole, a crater shaded as a hollow (its normal leans to the middle), paint flaked off round it, cracks, soot;
  8 variants (seeds) and a random turn; lit, on the render layer of the room (`V2Fx.layer_at`, set by the scene:
  each room's lights reach only its layer). Explosions keep the soft soot patch. Marks behind what stands 3 cm or
  more proud of a wall (kick plates, boxes) are hidden: the collision is the wall's plane.
- Footsteps (`V2Player._footsteps`): they fall when the view's bob is at its lowest: every 0.5 s in the Walk clip,
  0.35 s in Sprint; by the clock at the same pace while another clip plays. (By distance, 0.8 m, they came twice as
  fast as the walk the view shows: the user heard it.)
- Sound of the game: `door`, `crate`, `pickup`, `dry` (an empty gun), `heal`, `exit_hum` (loop on the portal),
  `exit`, `ui`, `room_tone` (a very low ventilation loop, `V2Sfx.ambience`; title too), `ricochet`.
- Static state survives a scene change (`V2Fx._marks`, `V2Sfx.root`, the game's `missions`): every scene's `_ready`
  sets the roots and calls `V2Fx.reset()`.

## V2 in the browser (the user tested it: Chrome, M1, in an iframe, 30 to 40 fps)

- Build: `tools/web_build.sh` = the "Web (site)" preset of `export_presets.cfg` (V2 only, pck 77 MB) ->
  `build/site/play` (the site of the branch `claude/epic-dijkstra-kge96s` embeds it). Run it here:
  `node tools/web_run.js OUT --args="--play --seed=33 --no-training --perf-log" --steps="wait:70,shot:game"`
  (headless Chromium on SwiftShader: a frame of the game takes seconds to draw, so a screenshot needs minutes,
  but the page's own thread is measured truly). `--probe=10` counts and times every WebGL call and each frame's
  callback. The game's arguments go into the page's `GODOT_CONFIG.args` after a `--`.
- **What made it slow (measured with the probe, it was not the game's code):** at the end of every frame
  Emscripten's shell copies its offscreen framebuffer to the canvas and first asks WebGL
  `getParameter(SCISSOR_TEST)`. The browser answers that by waiting for the GPU process to work through the whole
  frame, so the page's one thread stood still: here 2,600 ms of a 2,610 ms frame callback, on the user's M1 the
  "33 ms of game code" that F3 showed (that figure was the engine's process step, which holds the draw and the
  swap). `tools/web/head_include.html` (the preset's `html/head_include`: after editing it, copy it into
  `export_presets.cfg` again, escaped) answers the question on the page: it changes only through `enable` /
  `disable`. After: 13 ms a frame callback here, 4 ms of it in 11,800 WebGL calls (607 draws), 3 ms scripts.
- F3 (and `-- --perf-log`, which prints it every second): `V2World.took(system, since)` brackets the game's own
  code: robots (and of it clips, pose), player, hud, game, dungeon, fx (making effects), sound, map; then the
  engine's process step, what of it is not the game's code, the physics step, nodes, robots awake.
- **Pointer lock** (the game opened on the Esc card): a browser grants the lock only right after a click or a
  key, and the game asked for it 9 s later, at the end of the opening. Now the title asks on the key that starts
  the run (`V2Title._start`), `again()` on the button's click; on web the game never asks on its own. If the
  lock is not held when control is given, or is lost and the player has never had it, a **CLICK TO PLAY** card
  shows (`V2Game._click`), and any click or key takes the lock; the Esc card needs `_had_mouse`. (Chrome does not
  pass the Esc that leaves the lock to the page: the card shows because the lock is gone.)
- **The hit's blur** (the view went black at every hit): `textureLod` on a screen texture with mipmaps returns
  black in the browser. `screen_blur.gdshader` is a two-pass Gaussian now (`dir`; 8 samples a side, `sigma =
  0.74 * 2^amount` pixels, which matches the old look to 1.5 to 3.5 of 255 rms): `V2Hud._blur_h`, a
  `BackBufferCopy`, `V2Hud.blur`. `-- --blur-demo=N` holds it at N; pictures: `--game-capture=DIR --part=blur`.
- **Title -> game** (it took long and looked stuck). `-- --timing` prints where the start goes (`V2World.mark`,
  and every frame over 80 ms). What was done:
  the dungeon is built over frames (`V2Dungeon.build_staged`: a frame is let through every `SLICE` 30 ms) under
  the title's white sheet with a bar on it (`V2World.progress`: "BUILDING DATASPACE"; the robots are made in
  slices too); **the merge of the areas' meshes is 1.7 s in the browser instead of 12.8 s** (desktop 1.05 s
  instead of 2.2 s): `SurfaceTool.append_from` for every placed piece ran vertex by vertex, 7.5 million vertices
  a dungeon, and such helpers are six times slower in WASM. Now a piece is turned once for each way it faces
  (`_turned`: 150 a dungeon) and placing it is a shift and an append of whole arrays, done by the engine
  (`Transform3D * PackedVector3Array`; the indices travel as triples in a PackedVector3Array so that adding the
  vertex count is a shift too; `bytes_to_var` makes that array from the index bytes without a loop). Checked
  against the old merge: vertices, normals, colours, UVs and indices are the same to 0.1 mm; the tangents of
  parts without UVs are not turned (nothing reads them: `v2_set.gdshader` sets its own, the plain materials have
  no normal map; a part with UVs still goes through `append_from`). `V2_OLD_MERGE=1` turns every part the old
  way (for a picture comparison: `--part=rooms --match=2` both ways differ only where two runs of one differ).
  While the title shows, `V2World.preload_run` loads the set, the robots and the guns' glbs (one a frame,
  instantiated once so their materials are built) and the sounds: in the game robots then take 0.2 s instead of
  0.4 and the player 0.04 instead of 0.4. Before the white lifts, `V2Game._warm_up` draws for four frames,
  in front of the camera, one of each robot, the props, every `V2Fx` effect, the gun and the hit's blur and
  glow: the shaders compile under the sheet and not at the first shot. Not for the bot, the checks or the
  pictures (they build at once: `V2Dungeon.build`).
  Measured here in the browser, from the key to the room appearing: build 2.1 s, robots 1.0 s, warm-up 7.8 s
  (software GL draws those frames slowly; on a GPU it is the shader compiles: not measured).
- **What a shot costs (measured with `--game-capture=x --part=bench`: every effect and sound made 20 times,
  ms a call, three rounds; run it in the browser build too).** The user asked for pools of effect nodes and sound
  players. They are in (`V2Fx._take` / `_rest` / `_put`: particles, tracers, glares, arcs and lights at rest are
  hidden and used again, `settle()` after the warm-up; `V2Sfx._voice`: 40 players of each kind, the one with
  least left to play is cut off), and they were not where the time went: **a sound cost 1.3 ms in the browser
  (0.5 ms on the desktop) because the engine sets up a Vorbis decoder for every play of an .ogg**, even where the
  browser plays a ready sample, and an impact, a burst, an explosion are mostly their sounds. So the one-shots
  are 16-bit WAV now, decoded from the same Vorbis files (`tools/build_v2_audio.py` does it after encoding;
  `--wav` converts what is there; +7 MB in the pck: 83 MB). Browser: a sound 1.3 -> 0.4 ms, an impact 1.8 -> 0.5,
  a robot's burst 9 -> 3.5, an explosion 14 -> 4; desktop: 0.5 -> 0.03, 0.8 -> 0.13, 4 -> 0.45, 5 -> 0.55.
  What is left of a sound in the browser is the engine's WebAudio code (nine nodes made for every sound);
  keeping those assemblies for the next sound (a patch of the exported index.js) gave 20 % more and was not
  kept. A placed sound further than its distance + 4 m from the camera is not started.
- Robots: one that roams where it is not drawn is moved every third frame (`V2Robot.every`, by all the time
  since); a wreck at rest (`settled()`) is not moved while it is not drawn (all wrecks were, for ever). With the
  WAV sounds the three robots awake at the start cost 1.0 ms a frame in the browser (1.7 to 2.7 before: their
  steps' sounds). `--perf-log` shows "robots: look / move / sounds / springs / feet / flashes / clips / pose".
- **Draw calls** (`--game-capture=x --part=draws [--match=2,5]`: a view's count with one thing after another
  taken away; `V2_DRAWS_REST=1` lists what is left). A view of 500: HUD 48, gun 58, robots 120 to 170 (a spider
  is 63 surfaces, and was drawn again into the shadow map), what stands in the areas 18 + 15 more in the shadow
  map for each area in the light's reach, crates 10 + 10 each. **Shadows are drawn as one mesh a joint**
  (`V2World.shade_joints`, `shade_material`, `casts`: a `SHADOWS_ONLY` mesh of the same triangles, the meshes
  that are seen cast none; robots 24 / 7 / 8 instead of 63 / 35 / 25, a crate 2, the cage, the portal):
  190 / 431 / 502 draw calls in three views became 182 / 388 / 430. Same picture: with it on and off
  (`V2_SHADE_OFF=1`) a view differs in a few specks at shadow edges. The same for each area's furniture
  (one shadow mesh instead of 15 surfaces) was tried and not kept: 13 draw calls fewer a view for 43 MB more
  video memory (the copy of the geometry). Not done: the HUD's and the gun's own draw calls, merging robot
  parts across materials.
- From the site branch: on web the sounds play on Master (a bus added at runtime is silent in Godot 4.3's web
  sample playback: no room reverb, no limiter), no point lights on shots / hits / bursts (`V2Fx.LIGHTS`), the 3D
  picture starts at 900 rows with 2x MSAA.

## The environment set (approved by the user; it is what the game is built from)

**User, after the themed kit: "the elements in the map are poorly designed", go back to Blender, more realistic,
from references.** The 24 reference sheets are in `v2/reference/set/` (01 to 24: three wall panels, the doorway,
three floor tiles, two ceiling panels, a corridor section, a column, crate, drum, barrier, specimen tank, server
rack, power core, console, locker, shelving, workbench, charging dock, pipe riser, exit portal, loot crates and med
kits, ammunition box).
- `v2/scripts/setlib.py`: on top of `v2lib`: `Part` (boxes, cylinders, plates cut to an outline: `plate_xz/xy/yz`,
  `band_xz` for arches, `louvres`, `grid_*`, `bolt`), `pipe` (straight runs with round elbows), `cable`, `ring`,
  `handle`, `valve_wheel`, `text`, outlines (`chamfer`, `rounded`, `rect`), placements `T(loc, rx, ry, rz)`; the
  set's materials by short name (`mat("white")` ...: the robots' worn paint and steel, plus hazard stripes, a
  display, the portal's field, perforated sheet, card); the studio (`studio`, `shoot`: one asset alone, two views).
- `v2/scripts/set_structure.py`, `set_cover.py`, `set_equipment.py`, `set_pickups.py`: one function per asset,
  registered with `@asset(name, views=..., res=..., hide=...)`; 33 assets with their variants.
- `blender -b -P v2/scripts/build_set.py [-- --only=a,b] [--render]` -> `v2/set.blend` (all, 8 m apart) and
  `v2/renders/set/<name>_a.png`, `_b.png` (git-ignored); `python3 -I v2/scripts/set_sheet.py` -> the sheets
  `v2/renders/set_sheet_<n>.jpg`. One asset builds and renders in a few seconds: look at each against its reference.
- Learned: `Vector.slerp` returns unit vectors (the first pipe elbows were a metre wide); the shader's bevel must
  reach further than the parts' modelled bevels or it finds no edge to wear (pointiness does not work on boxes:
  every vertex is a corner); two bars laid over each other in one plane render black where they meet (a cross is
  one outline); a concave outline as one face can fill wrongly (arches are bands of quads); a part seen from below
  needs the studio's lights below, one seen from above needs less light or its colours bleach.
- Sizes: wall panel 2 x 3 m, floor tile 1 x 2 m, ceiling panel 2 x 2 m, corridor section 4 x 3.4 x 4 m, doorway
  opening 2.4 x 2.6 m, column 3.4 m high (`column_tall`: 5.2 m, the rooms' height). The med kit follows the
  reference (red case, white cross), not the green cross of the round before (the user approved the sheet).
- **Into the game**: `blender -b -P v2/scripts/export_set.py [-- --no-ao] [--only=a,b]` (45 s; `--only` writes
  `set_test.glb`; `SET_PARTS=1` prints the triangles of every part) -> `assets/models/v2/set.glb`, then
  `godot --headless --import`. What the export does: builds the assets with `setlib.GAME[0]` set (round things
  with half the sides, coarser pipes and cables, the tiling pieces without notches, clips and brackets); bevel
  modifiers become one chamfer; **the wear goes into the vertex colour** (R = ambient occlusion baked with Cycles
  to the face corners, forced to 1 on faces over 0.02 m2, where it smeared; G = 1 on the chamfer faces); one mesh
  per material per asset (`<asset>__<material>`), a loot crate's lid under `Crate_Lid`; no images.
  Game-only pieces (`@asset(..., game=True)`, the end of `set_structure.py`): `wall_upper`, `wall_plinth`,
  `ceiling_plain`, `door_frame`, `door_leaf_l`, `door_leaf_r`, `door_surround`, `column_tall`.
- Materials in the game (`V2Assets.SET_PAINT`, `SET_PLAIN`, `_set_material`): painted ones = `v2_set.gdshader`
  (the painted-plaster set, **one projection per triangle** chosen in the vertex shader (`flat` varying), paint
  worn off where the vertex colour's G says, dirt where R is low, smudges and streaks from the imperfections map,
  grime up to 0.3 m from the floor, `stripes` for the hazard paint); displays = `v2_screen.gdshader`; the portal's
  field = `v2_portal.gdshader`; the rest StandardMaterial3D. A material used for what is walked on is `floor` in
  the set's scripts (`EPaintFloor`): the same paint in Blender, a tone darker in the game.
- Flicker test on the set (339 frames, seed 33): **no two surfaces fighting for a plane anywhere**. What the test
  marks now: the wall displays (they are animated: the "after arriving" comparison), and edges and fine wear in
  the "1 mm aside" comparison (1 mm at 1.5 m is half a pixel: every sharp edge changes; only patches count). The
  hazard stripes were hard-edged and crawled from across a room: their edges are a pixel wide now (`fwidth`).
- Learned bringing it in: vertex colours survive `SurfaceTool.append_from` (checked, when the props looked wrong:
  it was the light, see "Light of the dungeon"); look at a piece in the dungeon, not only alone on the kit sheet,
  whose sun lights every side; the capture tour takes 6 minutes, `--part=rooms --match=N` 40 seconds.

## Conventions (fixed on day one; do not drift)

- Units: 1 Blender unit = 1 m. Blender is Z-up, Godot is Y-up. Blender +Y (forward) becomes Godot -Z
  (the glTF exporter's +Y-up conversion handles this; model facing +Y in Blender).
- Origin at the base of every asset (floor contact point, centred on X/Y).
- Grid cell 4 m. Wall height 4 m. Player eye height 1.6 m.
- Node names Godot code looks up: turret `Head`, `Muzzle`; container `Lid` + animation `Open`;
  door `Panel` + animation `Open`; weapons `Muzzle`. Emissive materials are prefixed `Neon`
  (e.g. `NeonCyan`, `NeonRed`) so Godot can swap in the animated neon shader.
- Palette: Quaternius pack colours for the world. HUD keeps cyan `#22E5FF`, loot green `#39FF88`, exit violet
  `#B48CFF`; hostile glow `#FF4A2B`.
- Textures: the packs' own maps (see Art direction for sizes).
- Hard-surface models get bevelled edges + hardened (weighted) normals, UVs at real-world scale.

## Asset pipeline

1. CC0 only (currently Quaternius + Kenney). No CC-BY, personal-use or unclear licences.
2. If nothing fits, model it in Blender via a Python script in `blender/scripts/`.
3. Everything passes through Blender (normalize scale/axes/origin/names/materials) and is exported as `.glb`
   into `assets/models/`. Never import a downloaded model into Godot directly.
4. Every asset and texture gets a row in `licenses.csv` (`name,source,url,license,date`). Client deliverable: keep it exact.

Run Blender scripts headless: `blender -b -P blender/scripts/<script>.py -- <args>`

## Layout

```
project.godot        Godot 4.3, GL Compatibility renderer (web-exportable)
assets/models/       normalized .glb output from Blender (committed)
assets/textures/     PBR texture sets used by Godot (committed)
assets/shaders/      Godot shaders (neon, portal, UI grid, vignette)
assets/audio/        Kenney CC0 sounds (.ogg)
assets/fonts/        Kenney Future (CC0)
build/               web export output (git-ignored)
assets_src/          raw downloads (git-ignored; re-fetch with the fetch script)
blender/scripts/     Blender Python: fetch, normalize, model, export
scenes/              Godot scenes
scripts/             GDScript
tools/               capture, checks (gen, playthrough, combat, fight bot), fetchers, export
captures/            screenshot output (git-ignored)
licenses.csv         asset licence log
```

## Commands

```
godot --path .                                         # TEST ROOM (polish-phase default: one room, frozen targets)
godot --path . -- --game                               # full game (title screen + dungeon runs)
godot --path . -- --seed=123 --autostart               # reproduce a dungeon, skip title
godot --headless -s tools/gen_check.gd -- --count=400  # generator check (must print PASS; ~100 s with the art kit)
godot --headless -s tools/playthrough.gd -- --count=10 # bot walks spawn -> exit through real collision (enemies off)
godot --headless -s tools/motion_check.gd              # lab: run/crouch/jump, recoil settles, reload, wrecks, pause
godot --headless -s tools/combat_check.gd              # 48 rule checks (lock timer, LOS, weapons, enemies, loot, crates, scaling, sounds)
godot --headless -s tools/fight_bot.gd -- --count=8 --difficulty=2   # balance bot: plays full runs, mortal (slow: ~1 min/run)
tools/perf_probe.sh [seed]                             # draw calls / objects / triangles in play (FPS is software GL here)
tools/export_web.sh                                    # web export -> build/web (then: python3 -m http.server 8060 -d build/web)
tools/capture.sh [seed] [label]                        # capture tour -> captures/latest (old -> captures/prev)
python3 tools/compare.py                               # prev vs latest contact sheet + change score
blender -b -P blender/scripts/normalize_quaternius.py -- assets_src/quaternius assets/models  # all pack assets + q_materials.json
python3 -I tools/pack_quaternius_textures.py           # resize/recompress the copied pack textures (run right after)
blender -b -P blender/scripts/build_props.py -- assets/models  # portal.glb
blender -b -P blender/scripts/normalize_wrad.py -- assets_src/wrad/arms.glb assets/models   # arms_wrad.glb
blender -b -P blender/scripts/pose_wrad.py -- assets/models   # arms_pistol.glb + arms_rifle.glb (hold poses)
blender -b -P blender/scripts/build_hands.py -- assets/models  # hands_pistol.glb + hands_rifle.glb (default hand style)
blender -b -P blender/scripts/pose_rigid_hand.py -- assets/models  # rigid_<gun>.glb: user's rigid hand posed on each grip (not in game yet)
blender -b -P blender/scripts/read_rigid_hand_poses.py      # after tuning in blender/hands_<gun>.blend: save the pose for pose_rigid_hand.py
blender -b -P blender/scripts/make_hands_blend.py            # blender/hands_<gun>.blend: gun + both hand styles + game camera, for review
blender -b -P blender/scripts/build_xm9.py               # blender/xm9.blend: XM9 pistol modelled from blender/reference/pistol_concept.png (review in Blender; not in game yet)
blender -b blender/xm9.blend -P blender/scripts/anim_xm9.py # XM9 Fire (f1-24) + Reload (f31-72) clips, timeline markers; keeps edits made in the .blend
blender -b -P blender/scripts/build_glove.py             # blender/glove.blend: HG-7 armored glove + sleeved arm to the shoulder (upperarm/forearm/hand rig), R + L; lib_arm.py aims the arm at the player's shoulder
blender -b blender/xm9.blend -P blender/scripts/pose_glove_xm9.py  # gloves into xm9.blend: right hand on the grip (measured; index on the trigger, thumb along the left side), left parked
blender -b blender/xm9.blend -P blender/scripts/anim_xm9_hands.py  # left-hand reload keys (palm carries the magazine in, overhand slide release); run after the two above
blender -b -P blender/scripts/build_xmr4.py              # blender/xmr4.blend: XM-R4 rifle from blender/reference/rifle_concept.png (0.82 mm/px, 88 cm)
blender -b blender/xmr4.blend -P blender/scripts/pose_glove_xmr4.py  # gloves on the rifle: right on the pistol grip, left under the handguard
blender -b blender/xmr4.blend -P blender/scripts/anim_xmr4.py # XM-R4 Fire (f1-24, 3-round burst) + Reload with the left hand (f31-90)
blender -b -P blender/scripts/export_new_assets.py -- assets/models  # the 5 from-scratch assets -> glb + clips json + baked AO/edge mask (~2.5 min each; ASSETS=xm9,at9 for some)
blender -b -P blender/scripts/build_at9.py && blender -b blender/at9.blend -P blender/scripts/anim_at9.py  # AT-9 ceiling turret: Idle 1-60, Shoot 67-90, Aim 97-144, Death 151-195
blender -b -P blender/scripts/build_fr2.py && blender -b blender/fr2.blend -P blender/scripts/anim_fr2.py  # FR-2 drone: Idle 1-60, Shoot 67-90, Fly 97-156, Death 163-207
blender -b -P blender/scripts/build_sd4.py && blender -b blender/sd4.blend -P blender/scripts/anim_sd4.py  # SD-4 spider (rig SD4Rig): Idle 1-60, Shoot 67-90, Walk 97-126 (0.6 m/s), Run 133-152 (1.5 m/s), Death 159-203
python3 -I tools/set_texture_imports.py                # force VRAM compression + mipmaps on 3D textures (run after adding textures)
```
Add `--greybox` to any run or capture to build with the greybox kit instead of the Blender kit.
Browser builds take the same options as a URL query: `?seed=123&autostart=1`.
Run `godot --headless --editor --quit` once after adding/changing assets so imports exist.
The ALSA `ERR_CANT_OPEN` error in container logs is the missing audio device; harmless.

## Code map

| File | Role |
|---|---|
| `scenes/main.tscn` + `scripts/main.gd` | Game flow (title, run, end, again), input map, seed/args, run stats, difficulty, environment |
| `scripts/dungeon_gen.gd` | `DungeonGen`: pure-data layout from (seed, difficulty): rooms, corridors, doorways, doors, pillars, spawns, exit |
| `scripts/dungeon_builder.gd` | `DungeonBuilder`: layout -> nodes. Per-area merged meshes (Compatibility = max 8 lights per object), box collision, doors, lights, portal |
| `scripts/kit_q.gd` | `KitQuaternius` (default kit): pieces from `q_kit.glb` by node name + variant (wall style, floor), `door_scene()` from `q_door.glb`, collision boxes |
| `scripts/anim_util.gd` | `AnimUtil`: play pack clips by prefix, loops cyclic ones |
| `scripts/kit_greybox.gd` | `KitGreybox`: greybox stand-ins with the same interface (`--greybox`) |
| `scripts/material_lib.gd` | `MaterialLib`: material name -> Godot material (Quaternius table + emissive masks; `Neon*` -> neon shader; `PortalField`) |
| `blender/scripts/lib_hardsurface.py` | Blender helpers: bevelled cuboid parts, weighted normals, metre box-UVs, named materials, glb export |
| `blender/scripts/normalize_quaternius.py` | Quaternius packs -> our glbs + material table (see Art direction) |
| `blender/scripts/normalize_wrad.py` `pose_wrad.py` | WRAD ARMS -> per-weapon posed arms |
| `tools/pack_quaternius_textures.py` | Texture budget for the web build |
| `scripts/player.gd` | `Player`: CharacterBody3D, WASD + mouse look, ADS (slow + narrow FOV), interact (nearest in range, no prompt) |
| `scripts/weapon_holder.gd` | `WeaponHolder`: hitscan from camera, first hit on WORLD or HOSTILE only |
| `scripts/door.gd` | `Door`: closed blocks WORLD layer; E opens, stays open |
| `scripts/exit_portal.gd` | `ExitPortal`: Area3D, player enters -> success |
| `scripts/game_ui.gd` | `GameUI`: title, HUD, end screen |
| `scripts/capture.gd` | `CaptureTour`: fixed views for `--capture=DIR` |
| `scripts/layers.gd` | Physics layer bits (WORLD, PLAYER, HOSTILE, PICKUP) |
| `scripts/enemies/enemy.gd` | `Enemy` base: LOS ray, lock timer -> instant damage, telegraph drive, hit/death fx, grid pathing via `main.nav_next_cell` |
| `scripts/enemies/turret.gd` `brawler.gd` `pursuer.gd` | The three hostiles (Quaternius rigs; greybox fallback built in code) |
| `scripts/pickup.gd` | `Pickup`: kit / ammo / health payoff; stays on the floor if it would do nothing |
| `scripts/sfx.gd` | `Sfx`: static sound API (`play`, `play_at`, `loop_3d`, ambience); keys -> Kenney files; `Sfx.log` for tests |
| `scripts/loot_crate.gd` | `LootCrate`: container (E in 2 m, Lid/Open anim, payoff pops out and is taken if useful), green glow light |
| `scripts/map_view.gd` | `MapView`: Tab map (explored rooms, hostile rooms + counts, exit once found, walked corridors, doors, player) |
| `blender/scripts/build_props.py` | Exit portal gate |
| `tools/fight_bot.gd` | Balance bot (reaction 0.45 s, aim error, no cover; rifle/pistol/reload/kits/crates) |

### HUD and flow
- HUD: health bar + number, 3 kit slots, weapon panel (slots, mag / reserve, drawn infinity sign, reload bar), ROOMS n / N,
  exit signal (5 bars by walking distance; metres once the portal was seen or its room entered), objective line,
  crosshair (red on a lined-up hostile, hit marker), damage flash + low-health vignette. Tab toggles the map (no pause).
- Fonts: Kenney Future for headings only. It draws K and X like H, so never use it for text with those letters;
  body text uses the engine default font. Browsers have no system font fallback: avoid non-Latin glyphs (that is why
  the infinity sign is drawn).
- End screen: win/loss, score (kills only: turret 100, pursuer 150, brawler 200), kills, rooms explored, next threat level.

### Economy and difficulty
- Containers: 1-2 per room (1 in spawn), against a wall on a non-doorway edge cell, facing in. Decor: 1-3
  shallow props per room on other free wall cells (DECO_KINDS), with collision. Payoffs: kit / ammo (+60) /
  health (+35); kit weight 4 -> 1 with difficulty (34 % -> 10 % of containers at d0 -> d4).
- Difficulty per completed mission: +0.5 hostiles per room, +20 % hostile HP. Bot results (8 runs each, no cover):
  d0 8/8, d1 8/8, d2 8/8, d3 3/8, d4 3/8 wins.

### Performance (web)
- Build: index.pck 55.8 MB + index.wasm 35.4 MB (8 MB gzipped). Textures are the bulk: 2K albedo + normal (BC5) per set,
  ORM at half resolution. Further cuts if needed: 1K normals (-21 MB) or Basis Universal.
- Per frame in play (seed 123): ~210-270 draw calls, ~180-230 k triangles, <= 10 lights (one shadowed omni per nearby room).
  Room shells don't cast shadows (only pillars, doors, props, enemies); area meshes cut at 64 m, props at 48 m.
- No threads in the web export (works on any static server, no COOP/COEP headers). Audio starts on the title click.
- FPS can't be measured in this container (SwiftShader / llvmpipe). Real-GPU frame rate is unverified.

### Combat rules (tuning lives in each script's `_init` / WEAPONS)
| | HP | Damage | Lock (s) | Range (m) | Score | Telegraph |
|---|---|---|---|---|---|---|
| Turret | 70 | 13 | 1.5 | 34 | 100 | Red targeting beam from `Muzzle`, thickens + flickers; head neon charges; rising hum |
| Brawler | 50 | 16 melee | 0.55 | 2 (reach) | 200 | Red floor ring = reach, closes in while locking; spikes flare; hum |
| Pursuer | 55 | 9 | 1.05 | 22 | 150 | Pulsing red core + targeting beam; hovers at 2.1 m, holds 6-11 m |
- Lock fills only with clear LOS (ray eye -> player chest on WORLD|PLAYER) and in range; damage re-checks LOS. LOS loss drains it 3x faster.
- HP x (1 + 0.3 x difficulty). Drops: 35 % per kill, payoff table `main.roll_payoff` (kit weight falls with difficulty).
- Pistol 25 dmg, 0.24 s, semi, infinite. Rifle 12 dmg, 0.095 s, auto, 30 mag, reserve 60 start / 240 max, 1.5 s reload (R).
- ADS: spread hip 0.022/0.035 -> 0.003/0.009, FOV x0.62, walk x0.45. Kits: max 3, Q heals 40 (refused at full health).
- Capture/test hooks: `Enemy.frozen` + `capture_frac`, `Player.invulnerable`, `WeaponHolder.hold_fx`, `main.enemies_enabled`.
- Effects are real-time tweens. In the container's software GL a frame takes ~0.1 s, so capture short effects with `shot(name, 1)`.

### Audio
- 31 Kenney CC0 sounds (Sci-Fi, Impact, Interface packs) in `assets/audio/`, one `licenses.csv` row each.
  Raw packs in `assets_src/audio/` (git-ignored). The kenney.nl download needs the page's cookie + Referer
  (`/download-link/<id>` returns a signed URL).
- `Sfx` is not an autoload (tool scripts run with `-s` can't see autoloads); it creates its own node on first use.
- The container has no audio device (dummy driver), so sounds are verified via `Sfx.log` in combat_check, not by ear.

### Dungeon rules
- Cells are 4 m. Rooms are 3..6 cells per side and never touch (1-cell margin). Corridors are straight and 1 cell wide,
  2..4 cells long. The room graph is a tree from spawn (room 0), and the exit room is the deepest one.
- Walls on floor/empty edges. Doorframes (2.4 x 3 m opening) on room/corridor edges. Doors on the child-room end of about
  half the corridors (always on the first corridor out of spawn). Pillars at the 4 inset vertices of rooms 5x5 and up.
- Difficulty (missions completed): +1 hostile per room per level; health-kit loot weight falls 4 -> 1.

### Materials and lighting
See "Art direction" above. Tonemapper stays Filmic; there are no reflection probes in Compatibility, and the
renderable-light cap is raised to 96 with distance culling in `main.gd` (Compatibility drops lights past the cap).

### Kit piece frames (Godot space; the Blender kit must match)
- `floor`/`ceiling`: origin at cell centre; floor top y=0, ceiling underside y=5 (Quaternius kit).
- `wall`, `doorframe`: origin at the edge midpoint on the floor, spans x -2..2, local -Z faces into the cell
  (Blender: +Y faces into the room), thickness extends toward +Z (outside).
- `pillar`: origin at the grid vertex (Column_Hollow, 1.2 m). Doorframe: opening 2.46 x 3.5 m, frame 4.86 x 5 x 0.5 m;
  door = PanelL/PanelR (4.2 x 4.05 m), slid apart 1.9 m each by `Door.gd`. Collision boxes in `kit_q.gd`.

## How we work

- Judge visuals in Godot captures, never Blender renders. The browser build is what counts.
- Never call methods on (or compare against) a node that may have been freed: in the release build that can segfault, and a
  freed object can compare equal to null. Use `is_instance_valid()`. GDScript lambdas capture locals by value.
- One change, then capture, check, and move to the next. Commit after each working milestone.
- GDD gaps are intentional; do not "fix" them: no pause, no interact prompt, ADS slowdown untaught,
  enemies undodgeable. (V2: the user's UI concept adds the interact prompt and dims the HUD while aiming.)

## Status

- [x] 1. Environment check, scaffold
- [x] 2. Asset plan (approved: model the room/corridor kit, door, pillars, enemies, container, health cell, portal;
      Kenney Blaster Kit for the pistol and rifle; Poly Haven `medical_box` and `ammo_box` for pickups; ambientCG textures)
- [x] 3. Greybox loop (generator, controller, doors, pistol, portal, title/end screens, gen check, playthrough bot, capture)
- [x] 4. Environment art (modelled kit + door, ambientCG materials, neon shader, lighting/post pass)
- [x] 5. Combat + sound (rifle, switching, 3 enemies with telegraphs, damage, deaths, drops, kits, 31 sounds)
- [x] 6. Economy and flow (containers, payoffs, kits, score, end screen, play again, difficulty curve, balance bot)
- [x] 7. HUD and map
- [x] 8. Hero art pass (enemies, weapons, container, pickups, portal)
- [x] 9. Web export (tools/export_web.sh; tested in Chromium via Playwright)

Polish (user's plan): [x] 1 art direction (Quaternius packs, arms)  [ ] 2 motion design  [ ] 3 sound  [ ] 4 UI
