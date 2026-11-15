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
- **Godot side**: pressing Play opens the **V2 lab** (`scenes/v2_lab.tscn`, `scripts/v2/`): three plain **studio** rooms
  side by side (11.6 m apart) joined by doorways, one robot in each (spider, drone, ceiling turret), each an **enemy**:
  it moves, aims, shoots the player and can be shot. The player holds the V2 guns. Keys: walk through the doors or
  `1 2 3` / Tab jump to a room, LMB fire (the machine gun fires for as long as it is held), RMB aim (held; LMB fires
  from the aim), `R` reload, `T` reload from empty, `F` inspect, `Q` switch gun, Shift sprint, Space jump,
  `C` aim as well (the user plays on a trackpad: no right button), `X` crouch (toggle; eye 1.0 m, capsule 1.15 m),
  `M` enemy <-> clip preview, `N` next clip (switches to preview), F3 performance, Esc frees the mouse.
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
- Not done yet: the turret does not travel (its cables); a browser build; the pistol has no cursor recoil (it
  shoots at the middle of the screen: the user called its firing good); no ricochet sound (nothing CC0 that fits
  was found); music (the user: not now).
  User decisions: realistic recorded sound, CC0, one consistent line, no music for now; no browser build of V2 for now (`tools/export_web.sh` is untested with the V2 lab);
  studio rooms in the lab, the concept room for the real game.

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
