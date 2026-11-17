#!/usr/bin/env bash
# The browser build of V2, as the site has it: the "Web (site)" preset -> build/site/play.
#   tools/web_build.sh       then: python3 -m http.server 8070 -d build/site/play   (or: node tools/web_run.js OUT ...)
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/site/play && touch build/.gdignore
godot --headless --import >/dev/null 2>&1 || true
godot --headless --export-release "Web (site)" build/site/play/index.html 2>&1 | grep -E "ERROR|error" | grep -v ALSA || true
ls -la build/site/play/index.pck | awk '{printf "index.pck %.0f MB\n", $5 / 1048576}'
