#!/bin/bash
# The balance bot plays the V2 game's level N times (default 5), one process per run, and prints each run and the tally.
#   tools/v2_bot.sh [N]
# Needs a display for the rooms' collision: runs under xvfb at low quality and a small window (software GL is slow).
cd "$(dirname "$0")/.."
n=${1:-5}
out=$(mktemp)
for i in $(seq 1 "$n"); do
  timeout 1500 xvfb-run -a godot --rendering-driver opengl3 --path . --resolution 480x270 -- --bot=1 --quality=low --no-sound 2>&1 | grep "^\[bot\]" | tee -a "$out"
done
echo "won $(grep -c 'WON' "$out") of $n   lost $(grep -c 'LOST' "$out")   stuck $(grep -c 'STUCK' "$out")"
rm -f "$out"
