#!/usr/bin/env bash
# The raw CC0 recordings of the V2 sounds -> assets_src/audio_v2/ (git-ignored). Then: python3 -I tools/build_v2_audio.py
# All from opengameart.org (the host must be allowed for the session; pages and licences are in licenses.csv).
# Needs py7zr for the two .7z archives (pip install py7zr).
set -e
cd "$(dirname "$0")/.."
B=https://opengameart.org/sites/default/files
mkdir -p assets_src/audio_v2/firearms assets_src/audio_v2/oga
cd assets_src/audio_v2/firearms
[ -d "Prepared SFX Library" ] || { curl -sS -o firearms.7z "$B/Prepared%20SFX%20Library.7z"; python3 -I -c "import py7zr; py7zr.SevenZipFile('firearms.7z').extractall('.')"; rm firearms.7z; }
cd ../oga
for f in sfx_100_v2.zip 25-CC0-bang-sfx.zip sfx_breaking_and_falling.zip swishes.zip metal_steps_48k24b.7z \
  fan_interval.wav roboticsqueeze.flac lightclunk2.wav rattle1.wav clink1_0.wav clink2.wav clink3.wav \
  reload.wav assaultriflereload1_0.wav clipload1.wav clipload2.wav equipmentclicks.wav spark.wav continuousspark.wav; do
  [ -s "$f" ] || curl -sS -o "$f" "$B/$f"
done
for z in *.zip; do d="${z%.zip}"; mkdir -p "$d"; (cd "$d" && unzip -oq "../$z"); done
python3 -I -c "
import py7zr, os
for z in ("metal_steps_48k24b.7z",):
    d = z[:-3]; os.makedirs(d, exist_ok=True); py7zr.SevenZipFile(z).extractall(d)"
echo "raw sounds in assets_src/audio_v2"
