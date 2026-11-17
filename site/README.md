# Showcase site

Static site published with GitHub Pages: play the game, see every V2 model in 3D, read the GDD, follow the making of.

```
tools/build_site.sh                       # -> build/site (game export + gallery models + these pages)
SKIP_GAME=1 tools/build_site.sh           # pages and models only, keeps build/site/play
python3 -m http.server 8070 -d build/site # then http://localhost:8070
```

Publishing: `.github/workflows/pages.yml` runs the build on every push to `main`. One-time setup in the
repository: Settings -> Pages -> Source: GitHub Actions. The repository must be public on a free plan.

| Path | What |
|---|---|
| `index.html` | Home + the game in an iframe (loads only on click; `play/` is the "Web (site)" export preset: V2 only) |
| `design.html` | The GDD as written (also `docs/gdd.md`) with "as built" notes per section |
| `assets.html`, `js/gallery.js` | three.js gallery; the list is `data/assets.json` |
| `js/materials.js` | The game's V2 materials ported from `scripts/v2/v2_assets.gd` and the `v2_*.gdshader` files |
| `data/materials.json` | Written by `godot --headless -s tools/dump_v2_materials.gd -- site/data/materials.json` (rerun after material changes) |
| `making-of.html`, `js/making-of.js` | Timeline + the conversation from `data/trajectory.json` (`tools/trajectory_digest.py`) |
| `img/` | Web copies of `v2/renders/` and of game captures (`--game-capture`) |
| `vendor/three/` | three.js r170 (MIT) and the addons the gallery uses |

The gallery reads the game's own glbs (meshopt-compressed at build time; `optimize` would merge the
materials, which differ by name only). Assets added to the game need a row in `data/assets.json`.
