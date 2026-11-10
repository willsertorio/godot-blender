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
assets/shaders/      Godot shaders (neon, portal, post)
assets_src/          raw downloads (git-ignored; re-fetch with the fetch script)
blender/scripts/     Blender Python: fetch, normalize, model, export
scenes/              Godot scenes
scripts/             GDScript
tools/               capture command, generator check
captures/            screenshot output (git-ignored)
licenses.csv         asset licence log
```

## Commands

(Filled in as they are built: run, capture, generator check, web export.)

## How we work

- Judge visuals in Godot captures, never Blender renders. The browser build is what counts.
- One change, then capture, check, and move to the next. Commit after each working milestone.
- GDD gaps are intentional; do not "fix" them: no pause, no interact prompt, ADS slowdown untaught,
  enemies undodgeable.

## Status

- [x] 1. Environment check, scaffold
- [ ] 2. Asset plan (awaiting approval)
- [ ] 3. Greybox loop
- [ ] 4. Environment art
- [ ] 5. Combat
- [ ] 6. Economy and flow
- [ ] 7. HUD and map
- [ ] 8. Hero art pass
- [ ] 9. Web export
