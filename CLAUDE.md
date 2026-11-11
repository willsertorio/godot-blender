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
