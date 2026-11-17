#!/usr/bin/env bash
# The menu music (CC0, opengameart.org): raw files -> assets/audio/v2/music/*.ogg, all at the same loudness.
#   tools/build_v2_music.sh        (the raw files must be in assets_src/music_v2/, see the URLs below)
# Raw files (git-ignored):
#   exploration_theme/   https://opengameart.org/sites/default/files/exploration_theme.zip   (unzipped into unz/)
# It is brought to -23 LUFS (integrated: quiet, under the game's sounds) and encoded as Vorbis q4; it loops
# seamlessly as it comes. (A piece that ends: build it with "fade": two seconds in and out.)
# The two candidates the user did not take: The Budding of Consciousness (Yoiyami), Solar Sail (vitalezzz).
# Then: godot --headless --import, and loop=true in each music/*.ogg.import.
set -euo pipefail
cd "$(dirname "$0")/.."
src=assets_src/music_v2
out=assets/audio/v2/music
mkdir -p "$out"
build() {  # name, source file, extra filter ("" for none)
  local i gain dur
  i=$(ffmpeg -hide_banner -nostats -i "$2" -af ebur128 -f null - 2>&1 | grep -A 4 "Integrated loudness" | grep "I:" | awk '{print $2}')
  gain=$(python3 -I -c "print(round(-23.0 - ($i), 2))")
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$2")
  local filter="volume=${gain}dB"
  if [ "$3" = "fade" ]; then
    filter="$filter,afade=t=in:d=2,afade=t=out:st=$(python3 -I -c "print(round($dur - 2.0, 2))"):d=2"
  fi
  ffmpeg -hide_banner -loglevel error -y -i "$2" -af "$filter,alimiter=limit=0.89" -ar 44100 -c:a libvorbis -q:a 4 "$out/$1.ogg"
  echo "$1: $i LUFS -> gain $gain dB, $(du -k "$out/$1.ogg" | cut -f1) kB, ${dur%.*} s"
}
build menu_exploration_theme "$src/exploration_theme/unz/Exploration Theme/Exploration Theme.wav" ""
