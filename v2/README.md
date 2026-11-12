# V2: Blender concept scene

A detailed static scene built and rendered in Blender first (the concept for V2), after
`reference/scene_concept.png`. Godot ignores this folder (`.gdignore`).

```
blender -b -P v2/scripts/build_room.py                                   # stage 1: room + lighting -> v2/scene.blend
blender -b v2/scene.blend -P v2/scripts/render.py -- out.png 96 100      # Cycles render (samples, size %); ~5 min at 1280x720 on 4 CPU cores
```

- `scripts/v2lib.py`: scanned CC0 materials box-projected in object space (tint, roughness range, per-part tint
  attribute, grunge), bmesh builders with bevel + weighted normals, cable curves, Cycles settings (AgX).
- Textures: ambientCG CC0 sets in `textures/` (rows in `licenses.csv`).
- Stages: 1 room + lighting (done), 2 pistol + gloved hands, 3 robots, then effects.
