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
ambientCG, Quaternius, Kenney (send a browser User-Agent, or it returns 403), download.blender.org and GitHub.
itch.io and Google Drive (where Quaternius hosts its packs) are **not** allowed.

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

## Conventions (fixed on day one; do not drift)

- Units: 1 Blender unit = 1 m. Blender is Z-up, Godot is Y-up. Blender +Y (forward) becomes Godot -Z
  (the glTF exporter's +Y-up conversion handles this; model facing +Y in Blender).
- Origin at the base of every asset (floor contact point, centred on X/Y).
- Grid cell 4 m. Wall height 4 m. Player eye height 1.6 m.
- Node names Godot code looks up: turret `Head`, `Muzzle`; container `Lid` + animation `Open`;
  door `Panel` + animation `Open`; weapons `Muzzle`. Emissive materials are prefixed `Neon`
  (e.g. `NeonCyan`, `NeonRed`) so Godot can swap in the animated neon shader.
- Palette: environment neon cyan `#22E5FF`, hostile red `#FF2D55` (enemies only), loot green `#39FF88`,
  exit violet `#B48CFF`.
- Textures: OpenGL normal maps (`NormalGL`), 2K for walls/floors, 1K for small props.
- Hard-surface models get bevelled edges + hardened (weighted) normals, UVs at real-world scale.

## Asset pipeline

1. CC0 only (Poly Haven, ambientCG, Quaternius, Kenney). No CC-BY, personal-use or unclear licences.
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
godot --path .                                         # play (title screen)
godot --path . -- --seed=123 --autostart               # reproduce a dungeon, skip title
godot --headless -s tools/gen_check.gd -- --count=400  # generator check (must print PASS; ~100 s with the art kit)
godot --headless -s tools/playthrough.gd -- --count=10 # bot walks spawn -> exit through real collision (enemies off)
godot --headless -s tools/combat_check.gd              # 48 rule checks (lock timer, LOS, weapons, enemies, loot, crates, scaling, sounds)
godot --headless -s tools/fight_bot.gd -- --count=8 --difficulty=2   # balance bot: plays full runs, mortal (slow: ~1 min/run)
tools/perf_probe.sh [seed]                             # draw calls / objects / triangles in play (FPS is software GL here)
tools/export_web.sh                                    # web export -> build/web (then: python3 -m http.server 8060 -d build/web)
tools/capture.sh [seed] [label]                        # capture tour -> captures/latest (old -> captures/prev)
python3 tools/compare.py                               # prev vs latest contact sheet + change score
python3 -I tools/fetch_textures.py                     # (re)fetch + pack ambientCG sets, logs licenses.csv
blender -b -P blender/scripts/build_kit.py -- assets/models   # rebuild kit_env.glb + door.glb
blender -b -P blender/scripts/build_props.py -- assets/models  # container.glb + portal.glb
blender -b -P blender/scripts/build_enemies.py -- assets/models  # turret / brawler / pursuer
blender -b -P blender/scripts/normalize_weapons.py -- assets_src/models/blaster-kit assets/models   # pistol / rifle
blender -b -P blender/scripts/normalize_pickups.py -- assets_src/models/polyhaven assets/models   # kit / ammo / health_cell
python3 -I tools/fetch_polyhaven.py medical_box ammo_box  # raw Poly Haven downloads (logs licenses.csv)
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
| `scripts/kit_art.gd` | `KitArt` (default kit): meshes from `kit_env.glb` by node name, `door_scene()` from `door.glb`, collision boxes |
| `scripts/kit_greybox.gd` | `KitGreybox`: greybox stand-ins with the same interface (`--greybox`) |
| `scripts/material_lib.gd` | `MaterialLib`: Blender material name -> Godot material (ambientCG ORM sets, tiling, tint; `Neon*` -> neon shader) |
| `blender/scripts/lib_hardsurface.py` | Blender helpers: bevelled cuboid parts, weighted normals, metre box-UVs, named materials, glb export |
| `blender/scripts/build_kit.py` | Environment kit + door |
| `tools/fetch_textures.py` | ambientCG fetch (CC0 check on the asset page) and ORM packing into `assets/textures/<id>/` |
| `scripts/player.gd` | `Player`: CharacterBody3D, WASD + mouse look, ADS (slow + narrow FOV), interact (nearest in range, no prompt) |
| `scripts/weapon_holder.gd` | `WeaponHolder`: hitscan from camera, first hit on WORLD or HOSTILE only |
| `scripts/door.gd` | `Door`: closed blocks WORLD layer; E opens, stays open |
| `scripts/exit_portal.gd` | `ExitPortal`: Area3D, player enters -> success |
| `scripts/game_ui.gd` | `GameUI`: title, HUD, end screen |
| `scripts/capture.gd` | `CaptureTour`: fixed views for `--capture=DIR` |
| `scripts/layers.gd` | Physics layer bits (WORLD, PLAYER, HOSTILE, PICKUP) |
| `scripts/enemies/enemy.gd` | `Enemy` base: LOS ray, lock timer -> instant damage, telegraph drive, hit/death fx, grid pathing via `main.nav_next_cell` |
| `scripts/enemies/turret.gd` `brawler.gd` `pursuer.gd` | The three hostiles (greybox visuals built in code; nodes `Head`/`Muzzle` on the turret) |
| `scripts/pickup.gd` | `Pickup`: kit / ammo / health payoff; stays on the floor if it would do nothing |
| `scripts/sfx.gd` | `Sfx`: static sound API (`play`, `play_at`, `loop_3d`, ambience); keys -> Kenney files; `Sfx.log` for tests |
| `scripts/loot_crate.gd` | `LootCrate`: container (E in 2 m, Lid/Open anim, payoff pops out and is taken if useful), green glow light |
| `scripts/map_view.gd` | `MapView`: Tab map (explored rooms, hostile rooms + counts, exit once found, walked corridors, doors, player) |
| `blender/scripts/build_props.py` `build_enemies.py` | Container, portal; turret/brawler/pursuer (node contract in each docstring) |
| `blender/scripts/normalize_weapons.py` | Kenney blasters -> pistol/rifle: palette-colour face classification into GunMetal/GunPaint/GunGrip, +Y, real size, grip origin, Muzzle, neon |
| `blender/scripts/normalize_pickups.py` | Poly Haven boxes -> kit/ammo (own textures kept, material `PH_*`), modelled health cell |
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
- Containers: 1-2 per room (1 in spawn), against a wall on a non-doorway edge cell, facing in. Payoffs: kit / ammo (+60) /
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

### Materials and lighting (tuned in Godot)
- Blender exports material *names* only (`export_image_format=NONE`); `MaterialLib` binds textures by name.
  Current sets: WallPanel=Metal046A, WallTrim=Metal028, DoorMetal=Metal038, Floor=DiamondPlate008A,
  Ceiling=MetalPlates015B, PropMetal=Metal029 (1K). Neon uses `assets/shaders/neon.gdshader` (unshaded HDR + slow shimmer).
- Keep metalness moderate (0.3-0.45 on large surfaces): there are no reflection probes in Compatibility, so very
  metallic surfaces go black. A dim procedural sky provides reflections only.
- Tonemapper is Filmic. ACES crushed the dark midtones and washed the neon to white.
- Lights: rooms of 4+ cells per side get 2 x 2 ceiling omnis, smaller rooms 1. The one nearest the centre casts shadows.
  One unshadowed omni per corridor. `main.gd` hides lights beyond range+10 m of the player; the renderable-light
  cap is raised to 96 as a backstop (Compatibility drops lights silently past the cap).
- Ceiling fixtures (`ceiling_light`) sit on every other cell; plain `ceiling` elsewhere.

### Kit piece frames (Godot space; the Blender kit must match)
- `floor`/`ceiling`: origin at cell centre; floor top y=0, ceiling underside y=4.
- `wall`, `doorframe`: origin at the edge midpoint on the floor, spans x -2..2, local -Z faces into the cell
  (Blender: +Y faces into the room), thickness extends toward +Z (outside).
- `pillar`: origin at the grid vertex (0.9 m footprint). `door_panel`: 2.4 x 3 m, origin at the bottom centre of the opening.
- Art-kit doorframes protrude 6 cm each side of the wall; collision boxes in `kit_art.gd` match.

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
