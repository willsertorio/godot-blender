#!/bin/bash
# The balance bot plays N generated dungeons (default 5) at a threat level (default 0), one process each, headless
# (the dungeon's collision is boxes made from its layout, so no display is needed), and prints each run and the tally.
#   tools/v2_bot.sh [N] [threat] [first seed]
cd "$(dirname "$0")/.."
n=${1:-5}
threat=${2:-0}
seed=${3:-1}
out=$(mktemp)
for i in $(seq 0 $((n - 1))); do
  timeout 900 godot --headless --path . -- --bot=1 --seed=$((seed + i)) --threat="$threat" --no-sound 2>&1 | grep "^\[bot\]" | tee -a "$out"
done
echo "threat $threat: won $(grep -c '\] WON' "$out") of $n   lost $(grep -c '\] LOST' "$out")   stuck $(grep -c '\] STUCK' "$out")"
rm -f "$out"
