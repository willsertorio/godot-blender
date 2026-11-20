#!/usr/bin/env bash
# Assemble a game-viewer site into build/site: the pages (site/), the game's web export (play/), the gallery's models.
# Run from the repository root. Edit the CONFIG block for the project.
#   SKIP_GAME=1 scripts/build_site.sh     pages + models only, keeps build/site/play
#   python3 -m http.server 8070 -d build/site
set -euo pipefail

# ---- CONFIG ---------------------------------------------------------------------------------------------
SITE_SRC=site                         # the pages (from the skill's template/)
OUT=build/site
MODELS_DIR=assets/models              # where the game's .glb files are
MODELS="robot_a robot_b weapon_view set"   # glb names (no extension) shown in the gallery
EXTRA_TEXTURES=""                     # e.g. "assets/textures/*.jpg" when js/materials.js rebuilds materials from them
GODOT_PRESET="Web (site)"             # an export preset with the frame-stall fix in html/head_include
GLTF="${GLTF_TRANSFORM:-npx --yes @gltf-transform/cli@4.1.1}"
# ---------------------------------------------------------------------------------------------------------

mkdir -p "$OUT" && touch "$(dirname "$OUT")/.gdignore"      # Godot must not import the built site
find "$OUT" -mindepth 1 -maxdepth 1 ! -name play -exec rm -rf {} +
cp -r "$SITE_SRC"/. "$OUT"/ && rm -f "$OUT/README.md" "$OUT/.gdignore"

mkdir -p "$OUT/models" "$OUT/textures"
for n in $MODELS; do
  # meshopt only: `gltf-transform optimize` dedups materials, and glbs whose materials differ by name only
  # (materials rebuilt by name later) lose their names.
  $GLTF meshopt "$MODELS_DIR/$n.glb" "$OUT/models/$n.glb" >/dev/null
  [ -f "$MODELS_DIR/${n}_clips.json" ] && cp "$MODELS_DIR/${n}_clips.json" "$OUT/models/"
  [ -f "$MODELS_DIR/${n}_mask.png" ] && cp "$MODELS_DIR/${n}_mask.png" "$OUT/textures/"
done
for t in $EXTRA_TEXTURES; do cp $t "$OUT/textures/"; done
[ -f licenses.csv ] && cp licenses.csv "$OUT/"

if [ -z "${SKIP_GAME:-}" ] || [ ! -f "$OUT/play/index.pck" ]; then
  godot --headless --import >/dev/null 2>&1 || true
  rm -rf "$OUT/play" && mkdir -p "$OUT/play"
  godot --headless --export-release "$GODOT_PRESET" "$OUT/play/index.html"
fi

find "$OUT" \( -name '*.import' -o -name '*.translation' \) ! -path "$OUT/play/*" -delete
touch "$OUT/.nojekyll"
du -sh "$OUT" "$OUT/play" 2>/dev/null || true
