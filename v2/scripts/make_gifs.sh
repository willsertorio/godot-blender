#!/bin/bash
# GIF preview of every baked clip of a weapon view: tools/.. v2/scripts/make_gifs.sh pistol [samples] [width]
# Frames are rendered with Cycles (small, few samples); long clips take every second frame (12 fps).
set -e
cd "$(dirname "$0")/../.."
W=${1:-pistol}; SAMPLES=${2:-16}; WIDTH=${3:-480}
TMP=${TMPDIR:-/tmp}/v2_gif_$W
OUT=v2/renders/anim
mkdir -p "$OUT"
CLIPS="Fire:1 Draw:1 Reload:1 Walk:1 Sprint:2 Idle:2 ADS:2 Inspect:2"
[ "$W" = rifle ] && CLIPS="Fire:1 Draw:1 ReloadTactical:1 ReloadEmpty:1 Walk:1 Sprint:2 Idle:2 ADS:2 Inspect:2"
for spec in $CLIPS; do
  clip=${spec%%:*}; step=${spec##*:}
  if [ -n "$ONLY" ] && [[ ",$ONLY," != *",$clip,"* ]]; then continue; fi
  rm -rf "$TMP/$clip"
  blender -b v2/scene.blend -P v2/scripts/render_anim.py -- "$W" "$clip" "$TMP/$clip" samples=$SAMPLES width=$WIDTH step=$step 2>&1 | grep -E "rendered|Error|Traceback" || true
  ffmpeg -loglevel error -y -framerate $((24 / step)) -i "$TMP/$clip/f_%04d.png" \
    -vf "split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" "$OUT/${W}_$(echo "$clip" | tr 'A-Z' 'a-z').gif"
  echo "gif $clip done"
done
