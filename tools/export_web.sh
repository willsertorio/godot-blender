#!/usr/bin/env bash
# Web export (Godot 4.3, Compatibility, no threads -> any static server works, no special headers).
#   tools/export_web.sh            -> build/web/index.html (+ .pck/.wasm/.js)
#   python3 -m http.server 8060 -d build/web   then open http://localhost:8060
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -I tools/set_texture_imports.py
godot --headless --editor --quit >/dev/null 2>&1 || true
rm -rf build/web && mkdir -p build/web
godot --headless --export-release "Web" build/web/index.html
ls -la build/web
