# Showcase site

Static site published with GitHub Pages.

```
tools/build_site.sh                       # -> build/site (game export + gallery models + these pages)
SKIP_GAME=1 tools/build_site.sh           # pages and models only, keeps build/site/play
python3 -m http.server 8070 -d build/site # then http://localhost:8070
```

Publishing: `.github/workflows/pages.yml` runs the build on every push to `main`. One-time setup in the
repository: Settings -> Pages -> Source: GitHub Actions. The repository must be public on a free plan.

Layout: a documentation page with a left menu (OVERVIEW, PLAY, GDD, ASSETS, TRAJECTORY) and no other text.

| Path | What |
|---|---|
| `game.html` | PLAY: the "Web (site)" export (`play/`, V2 only) in an iframe |
| `gdd.html` | GDD: the design document as written (also `docs/gdd.md`) |
| `index.html` | OVERVIEW: the gameplay video (Descript embed) and the steps behind the game, from the designer's own account (first page) |
| `assets.html`, `js/gallery.js` | ASSETS: three.js viewer; the model list is `data/assets.json` (robots and guns open on Idle) |
| `js/materials.js` | The game's V2 materials ported from `scripts/v2/v2_assets.gd` and the `v2_*.gdshader` files |
| `data/materials.json` | Written by `godot --headless -s tools/dump_v2_materials.gd -- site/data/materials.json` (rerun after material changes) |
| `trajectory.html`, `js/trajectory.js` | TRAJECTORY: `data/trajectory.json` (`tools/trajectory_digest.py` on the exported transcript) |
| `vendor/three/` | three.js r170 (MIT) and the addons the viewer uses |

The gallery reads the game's own glbs (meshopt-compressed at build time; `optimize` would merge the
materials, which differ by name only). Assets added to the game need a row in `data/assets.json`.
