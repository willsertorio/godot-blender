#!/usr/bin/env bash
# V2 lab screenshot tour -> captures/v2 (rooms, robot shots, gun clips). Slow here: software GL.
cd "$(dirname "$0")/.."
rm -rf captures/v2 && mkdir -p captures/v2
timeout "${1:-420}" xvfb-run -a -s "-screen 0 1280x720x24" \
  godot --rendering-driver opengl3 --resolution 1280x720 --path . -- --capture="$PWD/captures/v2" 2>&1 \
  | grep -E '^\[capture|SCRIPT|^   at:' | grep -v "must be normalized" | sort | uniq -c | head -30
ls captures/v2
