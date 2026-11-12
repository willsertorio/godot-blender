# V2: Blender concept scene

A detailed static scene built and rendered in Blender first (the concept for V2), after
`reference/scene_concept.png`. Godot ignores this folder (`.gdignore`).

```
blender -b -P v2/scripts/build_room.py                                   # stage 1: room + lighting -> v2/scene.blend
blender -b -P v2/scripts/build_viewmodel.py                              # stage 2: pistol + gloved hands (run after build_room.py)
xvfb-run -a blender -b -P v2/scripts/build_pistol.py -- /tmp/pistol       # the pistol alone: 4 review views
blender -b -P v2/scripts/build_robots.py                                 # stage 3: spider, drone, ceiling turret (rebuilds the Robots collection)
xvfb-run -a blender -b -P v2/scripts/build_robots.py -- review /tmp/rob   # each robot alone, 3 views
blender -b v2/scene.blend -P v2/scripts/debug_viewmodel.py -- /tmp/vm    # quick views of the viewmodel only (DBG_SCALE, DBG_C)
blender -b v2/scene.blend -P v2/scripts/render.py -- out.png 96 100      # Cycles render (samples, size %); ~5 min at 1280x720 on 4 CPU cores
```

- `scripts/v2lib.py`: scanned CC0 materials box-projected in object space (tint, roughness range, per-part tint
  attribute, grunge), bmesh builders with bevel + weighted normals, cable curves, Cycles settings (AgX).
- Textures: ambientCG CC0 sets in `textures/` (rows in `licenses.csv`).
- `scripts/mh_arm.py`: arms from the MakeHuman base mesh + skeleton + weights (CC0, `source/makehuman/`).
  `build_viewmodel.py` poses them on the pistol (finger curls, hand target frame, two-bone arm solve), bakes them and
  adds glove pads and cuffs. Materials made by an earlier run are removed first (they would be reused unchanged).
- `scripts/build_pistol.py` (`Part`: mm, profiles + boolean cuts + bevels) is reused by `build_robots.py`.
- `v2lib.pbr` options: `round_edges`, `edge_wear` (+ `wear_radius`, `wear_noise`, `wear_metal`), `cavity`, `wrinkle`.
- Stages: 1 room + lighting, 2 pistol + gloved hands, 3 robots (all done, first versions); next: effects + polish.
