---
name: game-viewer
description: Build a documentation-style showcase site for a game project (Godot + Blender or similar) — Overview with video and a step-by-step workflow, a playable web build, the GDD, a three.js 3D viewer of the game's models with their animation clips, and the development conversation (trajectory) — in the Project Firewall style (dark docs layout, icon menu, Funnel Display / Geist / JetBrains Mono), and publish it to GitHub Pages. Use when asked for a game viewer, showcase site, portfolio page or "a page like Project Firewall's" for a game.
---

# Game viewer

A static site that presents a game to a client: what it is and how it was made, the game itself, its design document,
every asset in 3D, and the conversation that built it. Reference implementation: Project Firewall
(`willsertorio/godot-blender`, branch `claude/epic-dijkstra-kge96s`, folder `site/`; live on its `gh-pages` branch).

## What the user wants from it (learned on Project Firewall)

- **A documentation page, not a marketing site.** Left menu, content column, no hero, no cards, no footer, and
  **no text you wrote**: only the user's own material (their GDD, their account of the process, their messages).
  When you think a label or explanation is needed, ask first.
- Menu, in this order: **Overview, Play, GDD, Assets, Trajectory**. Overview is the first page (`index.html`).
  The video goes at the top of Overview, not in its own tab (a VIDEO tab next to PLAY read as odd).
- Show screenshots before pushing; send a zip or push only when asked. Polish text with the user before building.
- Keep client names out of a public site ("the client") unless the user says otherwise; the repo is public.

## Pages (template/ has each one)

| Page | File | Content |
|---|---|---|
| Overview | `index.html` | `h1.home` "Overview", the video embed, `p.lead` intro (link to earlier versions if any), then `ol.steps`: per step `h2`, `.shots` (3 pictures: one wide, two below), then `h3` blocks in the order **Goal** (one sentence), **Steps**, **Learnings**, **Tools** (libraries, assets and their licences). Optional `img.strip` = frames of an animation. |
| Play | `game.html` | `<iframe src="play/index.html">` filling the content area, 16:9. Loads at once (no "load" button). |
| GDD | `gdd.html` | The GDD verbatim; `h1` = its title, one `<section id>` per section. No commentary. |
| Assets | `assets.html` | Model list (groups separated by `<hr>`) + viewer: Textured / Clay / Wireframe, Player's view / Orbit for first-person weapon views, clip buttons, speed, scrubber. List in `data/assets.json`. |
| Trajectory | `trajectory.html` | Every message the user typed, numbered with UTC date; click to open Claude's reply and the steps (tool calls). `data/trajectory.json`. |

## Workflow

1. **Gather**: the GDD text (ask if it is not in the repo), the game's models (`.glb`), the video embed URL, the
   user's account of the process (a transcript is fine: turn it into the Overview steps, then polish together),
   the session transcript for Trajectory (see below).
2. **Copy** `template/` to `site/` in the repo, add `site/.gdignore` (Godot must not import the site), fill the
   `{{...}}` placeholders. Vendor three.js (no CDN dependency):
   `npm install three@0.170.0` in a scratch dir, then copy `build/three.module.min.js`, `LICENSE`, and from
   `examples/jsm/`: `controls/OrbitControls.js`, `loaders/GLTFLoader.js`, `utils/BufferGeometryUtils.js`,
   `utils/SkeletonUtils.js`, `environments/RoomEnvironment.js`, `libs/meshopt_decoder.module.js` into
   `site/vendor/three/` (addons under `addons/`, same subfolders). Fonts: `site/fonts/` (see references/style.md).
3. **Assets list**: `data/assets.json` (format: references/assets-example.json). Item kinds: `robot`/any animated
   model (`clip` = default clip, use **Idle**), `view` (a first-person gun-with-hands glb: opens in Player's view;
   `eye`/`kick` = camera node names, `fov_h` = horizontal FOV), `piece` (one node of a multi-asset glb: `node`;
   recentred; `below: true` for ceiling pieces seen from under), `scene` (a whole environment). Robots and guns
   open on Idle.
4. **Materials**: if the game's glbs carry their materials, nothing to do. If the engine rebuilds materials by name
   (no images in the glbs, custom shaders), port that to `site/js/materials.js` (example:
   references/materials-example.js, ported from Godot shaders with `onBeforeCompile`) and dump the engine's tables
   to `site/data/materials.json` (example: references/dump_materials-example.gd). Without `materials.json` the viewer
   shows the glTF materials as they are.
5. **Game build**: the browser export with the fixes in references/godot-web.md (export preset with the frame-stall
   fix, size trimming, sound bus, pointer lock, screen-texture blur). If another session owns the game code, give it
   a brief and build from its branch; do not edit its scripts in parallel.
6. **Trajectory**: `python3 -I scripts/trajectory_digest.py SESSION.jsonl [SESSION_DIR] -o site/data/trajectory.json`
   (keeps typed prompts incl. mid-turn ones, Claude's visible replies, one-line tool calls; scrubs e-mails, tokens,
   signed URLs). A session cannot read another session's container: the owning session must export its transcript
   (`~/.claude/projects/<cwd>/<session>.jsonl`) to a branch, with the user's consent there. Review it for private
   details before publishing; the repo is public.
7. **Build**: copy `scripts/build_site.sh` to the repo, set its CONFIG, run it. Check every page in headless
   Chromium (desktop 1440 x 900 and phone 390 x 844, `deviceScaleFactor: 2` for pictures you send; no horizontal
   scroll; lazy images need a scroll before a full-page shot). Send screenshots.
8. **Publish**: `scripts/publish_gh_pages.sh "Site build ..."` (prebuilt files on `gh-pages`; include the commit
   attribution lines in the message). The user turns Pages on once: Settings -> Pages -> Deploy from a branch ->
   `gh-pages` / root. This container cannot reach `*.github.io`; ask the user to check the live page.

## Style (details and tokens: references/style.md)

Dark: page `#141414`, menu `#1B1B1B`, lines `#2A2A2A`, text `#E8E8E8` / `#A3A3A3`, accent cyan `#3FD0E8`, selected
row `#2B2B2B` with 8 px radius. Menu: Lucide line icons (18 px, stroke 1.6) + sentence-case labels, Geist 15 px.
Type: **Funnel Display 500, -0.02em** for headlines (home H1 72, H1 64, H2 40, H3 26.5); **Geist** for body
(16/1.6, lead 18/1.65, links 15); **JetBrains Mono uppercase 0.14em** for labels (11 px) and kickers (12 px cyan).
Sizes step down at 991 / 767 / 479 px. All fonts self-hosted (woff2 + OFL file + a `licenses.csv` row).

## Pitfalls already paid for (references/lessons.md has the rest)

- `gltf-transform optimize` merges materials that differ by name only: use `gltf-transform meshopt`.
- An embed whose recording is 16:10 inside a 16:9 frame shows black bars: match `aspect-ratio` to the recording.
- Sticky/fixed menus break full-page screenshots; check the real page, not only the stitched shot.
- `.steps li` styles leak into nested lists: use `.steps > li`.
