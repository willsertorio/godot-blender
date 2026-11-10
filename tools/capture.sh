#!/usr/bin/env bash
# Capture tour: opens the game with a fixed seed under a virtual display and saves
# the fixed set of views to captures/<label>/. The previous run is kept as
# captures/prev so tools/compare.py can diff them.
#
#   tools/capture.sh                 # seed 123 -> captures/latest (previous -> captures/prev)
#   tools/capture.sh 77              # another seed
#   tools/capture.sh 77 seed77       # custom output label (no rotation)
set -euo pipefail
cd "$(dirname "$0")/.."
SEED="${1:-123}"
LABEL="${2:-latest}"
OUT="captures/$LABEL"
if [ "$LABEL" = "latest" ] && [ -d captures/latest ]; then
  rm -rf captures/prev && mv captures/latest captures/prev
fi
rm -rf "$OUT" && mkdir -p "$OUT"
godot --headless --editor --quit >/dev/null 2>&1 || true   # make sure imports are current
xvfb-run -a -s "-screen 0 1280x720x24" \
  godot --rendering-driver opengl3 --resolution 1280x720 --path . -- --seed="$SEED" --capture="$PWD/$OUT" 2>&1 \
  | grep -E '^\[|ERROR|SCRIPT' || true
ls "$OUT"
