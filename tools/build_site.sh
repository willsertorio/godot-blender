#!/usr/bin/env bash
# Build the showcase site into build/site (GitHub Pages serves this folder; see .github/workflows/pages.yml).
#   tools/build_site.sh            everything: game export + gallery models + pages
#   SKIP_GAME=1 tools/build_site.sh   pages and models only (keeps an existing build/site/play)
# Needs: godot 4.3 + export templates (game), node/npx (gltf-transform), python3.
#   python3 -m http.server 8070 -d build/site   then open http://localhost:8070
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=build/site
GLTF="${GLTF_TRANSFORM:-npx --yes @gltf-transform/cli@4.1.1}"

mkdir -p "$OUT" && touch build/.gdignore   # Godot must not import the built site
# keep the game export between page-only builds
find "$OUT" -mindepth 1 -maxdepth 1 ! -name play -exec rm -rf {} +
cp -r site/. "$OUT"/ && rm -f "$OUT/README.md" "$OUT/.gdignore"

# fonts: the game's UI fonts (SIL OFL 1.1, licence file alongside)
mkdir -p "$OUT/fonts"
cp assets/ui/fonts/*.ttf assets/ui/fonts/OFL.txt "$OUT/fonts/"

# gallery: the game's own V2 glbs, meshopt-compressed (geometry and animation untouched otherwise)
mkdir -p "$OUT/models" "$OUT/textures"
for n in spider drone turret view_pistol view_rifle set room; do
  # (meshopt only: "optimize" would merge the materials, which differ by name alone in these files)
  $GLTF meshopt "assets/models/v2/$n.glb" "$OUT/models/$n.glb" >/dev/null
  [ -f "assets/models/v2/${n}_clips.json" ] && cp "assets/models/v2/${n}_clips.json" "$OUT/models/"
  [ -f "assets/models/v2/${n}_mask.png" ] && cp "assets/models/v2/${n}_mask.png" "$OUT/textures/"
done
cp assets/textures/v2/*.jpg "$OUT/textures/"
cp assets/textures/military/_detail/imperfections.png "$OUT/textures/"
cp licenses.csv "$OUT/"

# the game
if [ -z "${SKIP_GAME:-}" ] || [ ! -f "$OUT/play/index.pck" ]; then
  godot --headless --import >/dev/null 2>&1 || true
  rm -rf "$OUT/play" && mkdir -p "$OUT/play"
  godot --headless --export-release "Web (site)" "$OUT/play/index.html"
fi

touch "$OUT/.nojekyll"
du -sh "$OUT" "$OUT/play" "$OUT/models" "$OUT/textures"
