# V2: Blender concept scene

A detailed static scene built and rendered in Blender first (the concept for V2), after
`reference/scene_concept.png`. Godot ignores this folder (`.gdignore`).

```
blender -b -P v2/scripts/build_room.py                                   # stage 1: room + lighting -> v2/scene.blend
blender -b -P v2/scripts/build_viewmodel.py -- show=rifle                # both weapon views, gloved hands (run after build_room.py); show=pistol|rifle = the one left visible
xvfb-run -a blender -b -P v2/scripts/build_rifle.py -- /tmp/rifle         # the machine gun alone: 4 review views
xvfb-run -a blender -b -P v2/scripts/build_pistol.py -- /tmp/pistol       # the pistol alone: 4 review views
blender -b -P v2/scripts/build_robots.py                                 # stage 3: spider, drone, ceiling turret (rebuilds the Robots collection)
xvfb-run -a blender -b -P v2/scripts/build_robots.py -- review /tmp/rob   # each robot alone, 3 views
blender -b v2/scene.blend -P v2/scripts/debug_viewmodel.py -- /tmp/vm    # quick views of one viewmodel only (DBG_SCALE, DBG_C, DBG_VIEW=ViewmodelRifle)
blender -b v2/scene.blend -P v2/scripts/render.py -- out.png 96 100 view=rifle   # Cycles render (samples, size %, view=pistol|rifle); ~5 min at 1280x720 on 4 CPU cores
```

- `scripts/v2lib.py`: scanned CC0 materials box-projected in object space (tint, roughness range, per-part tint
  attribute, grunge), bmesh builders with bevel + weighted normals, cable curves, Cycles settings (AgX).
- Textures: ambientCG CC0 sets in `textures/` (rows in `licenses.csv`).
- `scripts/mh_arm.py`: arms from the MakeHuman base mesh + skeleton + weights (CC0, `source/makehuman/`).
  `build_viewmodel.py` poses them on the pistol (finger curls, hand target frame, two-bone arm solve), bakes them and
  adds glove pads and cuffs. Materials made by an earlier run are removed first (they would be reused unchanged).
- `scripts/build_pistol.py` (`Part`: mm, profiles + boolean cuts + bevels) is reused by `build_robots.py`.
- `v2lib.pbr` options: `round_edges`, `edge_wear` (+ `wear_radius`, `wear_noise`, `wear_metal`), `cavity`, `wrinkle`.
- Glove fabrics (knit back, leather palm, grippy tips) are one material, `v2lib.layered`: the edges come from the point
  attributes `palm` / `tip` written by `bake_arm`, so they are smooth lines with a sewn seam (groove + stitches),
  whatever the mesh. Assigning the fabrics per face gave a zigzag edge.
- Robots: curved shells are `Part.ellipsoid` cut to shape; the drone leans 36 deg toward the camera so both rotors read.
- Two weapon views share `PlayerCamera`: collection `Viewmodel` (pistol) and `ViewmodelRifle` (machine gun, after
  `reference/scene_concept_rifle.png`). One is hidden; switch with the two collection check boxes in the outliner,
  `show=` (build) or `view=` (render). `build_viewmodel.py` always rebuilds both (`PLACE` = where each gun sits in the
  camera frame). The rifle (`build_rifle.py`) reuses the pistol's grip / trigger proportions moved by (Y -32, Z -64) mm,
  so `trigger_hand()` fits both; the support hand lies on the magazine well. Its rear body is `Part.loft`
  (superellipse rings, Catmull-Rom) in two shells over a dark core that shows through the panel gaps and vents.
  Whether the trigger hand shows under the gun depends on the gun's proportions, not on where it is placed: the
  angle between sight and grip against the width of the sight is fixed by the model. So the body is slim (60 mm
  receiver) and the sight wide and low (52 mm hood, 75 mm above the bore); a taller gun hid the hand at any distance.
  Parts that overlap a curved shell (screen on the pod) need a flat seat cut into every shell under them.
- Stages: 1 room + lighting, 2 pistol + gloved hands, 3 robots (done, robots and gloves polished once); next: effects.
