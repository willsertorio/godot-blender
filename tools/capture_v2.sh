#!/usr/bin/env bash
# V2 lab screenshot tour -> captures/v2 (rooms, robot clips, doorways walked through, gun clips, materials close up,
# the robots as enemies). Slow here (software GL): ~25 min. Usage: tools/capture_v2.sh [timeout s] [sections]
#   sections = comma list of tone,rooms,doors,guns,look,ai,wreck (default: all but wreck), e.g. tools/capture_v2.sh 600 tone,look
cd "$(dirname "$0")/.."
rm -rf captures/v2 && mkdir -p captures/v2
timeout "${1:-1800}" xvfb-run -a -s "-screen 0 1280x720x24" \
  godot --rendering-driver opengl3 --resolution 1280x720 --path . -- --capture="$PWD/captures/v2" ${2:+--only=$2} 2>&1 \
  | grep -E '^\[capture|SCRIPT|^   at:' | grep -v "must be normalized" | sort | uniq -c | head -30
ls captures/v2
