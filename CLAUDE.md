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
  The pistol still shoots at the middle of the screen.
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
- Sound: `scripts/v2/v2_sfx.gd` (`V2Sfx`): one table, a key per interaction (33; `assets/audio/v2/README.md`),
  `play(key[, place])`, `loop` / `drive` for the drone's rotors, `V2Sfx.heard` / `log` for the checks,
  `-- --no-sound`. Everything goes through one bus (`V2Sfx.bus`): a short room reverb, then +3 dB into a hard
  limiter (the machine gun's rounds pile up).
  Files: `assets/audio/v2/<key>_NN.ogg` (103, 1.7 MB), **all CC0, from opengameart.org**: the guns from The Free
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
  fire; C aims and the view zooms, fire while aiming; the gun on its own camera; X crouches; a sprint ends when
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
- Not done yet: a browser build of V2; the pistol has no cursor recoil (it shoots at the middle of the screen: the
  user called its firing good); music (the user: not now); V1 (its Quaternius art, enemies and UI) still runs with `-- --v1`;
  its generator is what the V2 game builds on.
  User decisions: realistic recorded sound, CC0, one consistent line, no music for now; no browser build of V2 for now (`tools/export_web.sh` is untested with V2);
  studio rooms in the lab; the game has PLAY and LAB and is the generated dungeon of the GDD in a new modular kit (the concept room is not in it);
  wrecks are electrical (no fire); the pistol wears the machine gun's colours; footsteps quiet and dull, in step
  with the walk; a drone shot down goes down in a straight line; the dead turret is heavy; no reload at a run;
  going down = a fall onto the side, the gun on the floor, the robots coming to look, then the options;
  the map's detail is modelled in Blender (not ready-made packs); robots tougher and more aggressive from the start;
  no notes on the interface for now; "the gameplay feels really good".

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
- Kit: `v2/scripts/build_kit.py` -> `v2/kit.blend` + `assets/models/v2/kit.glb`, 51 pieces. The first set: `Floor`,
  `CFloor`, `Ceiling`, `CeilingBeams`, `CCeiling`, `Wall`, `WallScreen`, `WallPipes`, `CWall`, `WallDoor`, `Tank`,
  `Console`, `Block`, `Locker`, `Column`. The second set (**user: the map was too simple and empty; modelled in
  Blender, not ready-made packs**): room walls `WallVent` `WallCables` `WallWindow` `WallStripe` `WallPanels`
  `WallPilaster` `WallValves`; corridor walls `CWallPipes` `CWallPanel` `CWallVent`; floors `FloorHazard`
  `FloorPlates` `FloorLines` `FloorDrain`; ceilings `CeilingDuct` `CeilingPipes` `CeilingVent` `CCeilingDuct`; what
  stands in rooms `CrateStack` `Barrels` `Pallet` `Barrier` `ServerRack` `RackPair` `Generator` `Shelf` `Workbench`
  `Cabinet` `ChargeDock` `PipeRiser` `CoreUnit` `Cart`; small things `Cone` `Toolbox` `Canisters` `CableReel`.
  Rooms 5.2 m high (the turret's pylon ends there), corridors 3.4 m, doorways 2.4 x 2.6 m (every robot fits).
  Materials by name: the concept room's and the robots', plus `V2Assets.SPECIAL` paints (`PaintGrey`, `PaintBlue`,
  `PaintOrange`, `PaintGreen`, `Cardboard`, `CoreGlow`, `Seam`). `Part.tube` / `Part.cone` for pipes and cones.
  `xvfb-run -a godot --rendering-driver opengl3 --resolution 480x360 --path . -s tools/v2_kit_sheet.gd -- DIR [skip]`
  = a picture of every piece in the game's materials (look at new pieces there before placing them).
- `scripts/v2/v2_dungeon.gd` (`V2Dungeon`): an area per room and per corridor. **Themes** (`THEMES`: lab, storage,
  server, power, workshop; dealt so that all five come up before one repeats): a room's theme picks its walls, the
  fittings of the ceiling cells between the lights, floor accents, the cover at the inner corners of its cells
  (one of three patterns) and the equipment along `FILL` (60 %) of its free wall cells, with small things beside
  some; a striped frame on the floor in front of every doorway and under the exit; a turret's cells keep a plain
  ceiling. Each area is **two merged meshes** (`_meshes`: the shell, and what stands in it, which casts shadows),
  one surface per material, so furniture costs no draw calls. Lights: their cull mask = the area's render layer;
  areas within 13 m of each other get different layers, 9 of them (a mesh takes 8 lights). **Collision as boxes
  made from the layout** (walls, doorway sides and lintels, floors, ceilings, `DECO_BOX` per standing piece): it
  exists headless, so every check and the bot run headless. Doors (leaves slide into the lining, lamp amber ->
  green). `path(a, b)` = cells through open doorways; `arena(area, margin)`; `update()` hides areas more than 34 m
  away and lets the player's area's lights reach the gun.
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
  (`roll_payoff`: med kits thin out with the threat level). A wreck does not block the player.
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
- **Balance, measured with the bot** (`tools/v2_bot.sh N threat first_seed`: headless, the clock four times as
  fast, about 1.5 minutes a dungeon; three batches side by side on this container's four cores; **the container
  only runs while a command of the session is running: wait for a batch with a blocking loop, not by coming back
  later**). Seeds 10 to 18, with the robots above: **threat 0: 9 wins in 9** (the bot's lowest health after a room
  23 to 70; 70 to 87 % of its rounds hitting), **threat 2: 6 in 9, threat 4: 3 in 9** (threat 2 was measured with
  the climb at 1.5 robots and 8 % a level, where threat 4 gave 2 in 9; it is a little gentler now).
  History: with the first robots (100 / 60 / 110 health, 0.6 kept) it was 11 in 12, 9 in 9, 7 in 9, and 5 in 9 at
  threat 6, and the user found the game too easy.
  **What went wrong on the way (it cost four tuning rounds):** the bot aimed the camera at a robot while the
  machine gun's rounds leave along the barrel, which climbs in a burst; it fired whole magazines over robots'
  heads (186 rounds for one kill in one room) and its 1-in-6 results were read as "too many robots". It now pulls
  against the climb as a player follows the cursor (`PULL`), and prints its hit rate: look at that number before
  believing a loss. And 6 to 8 runs a level are noise (the same settings gave 6 of 8 and 3 of 8).
  The bot clears every room (a player may walk past rooms), aims better than a trackpad allows and uses no cover:
  read its numbers as how the threat levels compare, not as how hard it feels.
- Cost of a room view (the capture prints it): 410 to 570 draw calls, 270 to 310 thousand triangles (two merged
  meshes an area; the robots, doors and crates are the rest). Frame rate on a real GPU: not measured (F3 in the game).
- Map (`scripts/v2/v2_map.gd`, Tab; the game goes on): rooms entered, robots still working in each (red number),
  corridors walked, doorways (amber shut / green open / grey no door), the exit once its room was entered, the
  player. Scaled to the whole dungeon, so the empty part of the panel says how much is left.
- HUD / screens (`scripts/v2/v2_ui.gd`; headings in Kenney Future: no K or X): health, med kits, gun + rounds, one
  line (THREAT, ROOMS n / N, hostiles here, the exit), "ROOM n OF N" on entering a new room, a note line, cursor,
  hurt flash with a bar on the side the hit came from, F3 = frame rate. No prompts, no pause: Esc frees the mouse
  and shows RESUME / TITLE. End screen: score, robots destroyed, rooms seen, time, the next threat level; AGAIN / TITLE.
- Props: `v2/scripts/build_props.py` -> `props.glb` (crate with `Crate_Lid`, `AmmoBox`, `HealthCell`, `MedKit` (one green cross on each face: user),
  `ExitGate`: the exit portal, standing free in the middle of the deepest room; its field is `v2_field.gdshader`).
- Checks, bot, pictures (`scripts/v2/v2_game_bot.gd`), all headless except the pictures:
  `godot --headless --path . -- --game-test` (seed 7): the generator over 40 seeds (8-12 rooms, every cell reachable,
  exit deepest, more robots at threat 3), walls stop rays, magazines, a crate, a med kit, no regeneration, a door
  (shut it blocks the way and the paths), wrecks stay, a robot follows the player out of its room, the turret's
  rail, the walk through every room (ROOMS counts), the exit raises the threat level, going down does not, the
  fall and the dropped gun, the robots coming to look without firing, sounds;
  `tools/v2_bot.sh [N] [threat] [seed]`; `xvfb-run -a godot --rendering-driver opengl3 --path . --
  --game-capture=DIR [--seed=N]`; `... -- --title-capture=FILE.png`. With `--part=NAME` the capture is one of:
  `death` (frames of going down), `marks` (bullet holes on a wall and the floor), `flicker` (at every doorway and
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

## The environment set (waiting for the user's approval; not in the game yet)

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
- Sizes chosen for the sheet (to settle when the set goes into the game's 4 m grid): wall panel 2 x 3 m, floor tile
  1 x 2 m, ceiling panel 2 x 2 m, corridor section 4 x 3.4 x 4 m, doorway opening 2.4 x 2.6 m, column 3.4 m high
  (its height is a parameter). The med kit follows the reference (red case, white cross), not the green cross of
  the round before: ask.

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
  enemies undodgeable.

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
