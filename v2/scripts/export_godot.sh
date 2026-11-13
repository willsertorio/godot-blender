#!/bin/bash
# V2 -> Godot: every asset in its own Blender process (see export_godot.py), then the textures.
cd "$(dirname "$0")/../.."
for what in materials room spider drone turret pistol rifle; do
  out=assets/models/v2/$what.glb
  [ "$what" = materials ] && out=assets/models/v2/materials.json
  [ "$what" = pistol ] || [ "$what" = rifle ] && out=assets/models/v2/view_$what.glb
  rm -f "$out"
  blender -b v2/scene.blend -P v2/scripts/export_godot.py -- $what 2>&1 | grep -E "^exporting|^materials|Error|Traceback" | cut -c1-160
  [ -s "$out" ] && echo "  ok $out $(du -h "$out" | cut -f1)" || echo "  MISSING $out"
done
python3 -I v2/scripts/pack_textures_godot.py > /dev/null && echo "textures ok"
