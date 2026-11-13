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
blender -b v2/scene.blend -P v2/scripts/anim_pistol.py                    # bake the pistol clips onto the timeline (after build_viewmodel.py; saves); only=Fire,Reload nosave to try
blender -b v2/scene.blend -P v2/scripts/anim_rifle.py                     # bake the machine gun clips after them (frames 601+; saves). Always: build_viewmodel -> anim_pistol -> anim_rifle
v2/scripts/make_gifs.sh pistol 16 480                                     # GIF of every clip of pistol | rifle -> v2/renders/anim/ (Cycles, ~10 s a frame, ~35 min); ONLY=Fire,Draw for some
blender -b v2/scene.blend -P v2/scripts/anim_robots.py                    # bake the robots' sections (frames 1201+; run after build_robots.py; saves)
blender -b v2/scene.blend -P v2/scripts/anim_fx.py                        # effects for every shot, the deaths and the Firefight (run LAST; saves)
blender -b v2/scene.blend -P v2/scripts/render.py -- out.png 96 100 view=pistol frame=1637   # the Firefight still
blender -b v2/scene.blend -P v2/scripts/pose_test.py -- out.png 40 80 [back]   # rig check: left hand open, off the pistol
blender -b v2/scene.blend -P v2/scripts/debug_viewmodel.py -- /tmp/vm    # quick views of one viewmodel only (DBG_SCALE, DBG_C, DBG_VIEW=ViewmodelRifle)
blender -b v2/scene.blend -P v2/scripts/render.py -- out.png 96 100 view=rifle   # Cycles render (samples, size %, view=pistol|rifle); ~5 min at 1280x720 on 4 CPU cores
```

- `scripts/v2lib.py`: scanned CC0 materials box-projected in object space (tint, roughness range, per-part tint
  attribute, grunge), bmesh builders with bevel + weighted normals, cable curves, Cycles settings (AgX).
- Textures: ambientCG CC0 sets in `textures/` (rows in `licenses.csv`).
- `scripts/mh_arm.py`: arms from the MakeHuman base mesh + skeleton + weights (CC0, `source/makehuman/`).
- `scripts/hands.py`: the arms stay **rigged** (armatures `ArmRig.<R|L>.<pistol|rifle>`, gloves `Glove.<side>.<weapon>`).
  The glove is made in the rest pose (subdivided, thickness, masks) and then skinned; `hands.pose(rig, side, **spec)`
  sets a whole pose from the rest pose (finger curls, hand target frame + anchor, two-bone arm solve, thumb), so it
  can be called per frame; pads are frozen in the hold pose and parented to their bone, cuffs to `lowerarm02`.
  Hold poses: `pistol_hold()`, `rifle_hold()`; `PLACE` = where each gun sits in the camera frame.
  Glove and sleeve fabrics are projected from the point attribute `rest` (rest positions), not object space, or the
  weave would slide over the moving hand (`coord_attr` in `v2lib.pbr` / `layered`).
  Materials made by an earlier run are removed first (they would be reused unchanged).
- Animation (`scripts/anim_lib.py`, `anim_pistol.py`, `anim_rifle.py`): 24 fps, clips one after another on the
  timeline with a marker each. Each view owns 600 frames (`anim_lib.WINDOW`); ranges are in the scene properties
  `v2_clips_pistol` / `v2_clips_rifle`. Show the matching collection (Viewmodel / ViewmodelRifle) when scrubbing.
  - Pistol: Idle 1-72 (loop), Walk 81-104 (loop), Sprint 113-159, Fire 168-179, ADS 188-236, Draw 245-264,
    Reload 273-308 (from empty), Inspect 317-388.
  - Machine gun (markers "MG ..."): Idle 601-696 (loop), Walk 705-728 (loop), Sprint 737-785, Fire 794-819 (8-round
    burst, 2 frames a round), ADS 828-877 (aim, 6-round burst, lower), Draw 886-911, ReloadTactical 920-965,
    ReloadEmpty 974-1028 (handle locked back, slap on the bolt catch), Inspect 1037-1113.
  A clip is a function of time returning a state (gun placement in the eye's frame, camera offset, part matrices, a
  pose spec per hand); the baker re-solves both arms on every frame from shoulders fixed to the eye and writes a key
  per frame. The view roots are children of `PlayerCamera`, so camera bob / view punch carries the gun; the camera's
  keys of the other view are kept when one view is re-baked.
  Parts that move: pistol `P_Slide` (+ everything parented to it), `P_Trigger`, `P_Magazine` (+ base, top round);
  machine gun `R_ChargingHandle` (cycles with every shot: the ejection port is on the far side), `R_Trigger`,
  `R_Magazine` (+ base, light). Hidden by scale 0 until used: `P_Magazine2`, `P_Casing`, `P_Flash`, `R_Casing0-4`,
  `R_Flash`, lights `P_FlashLight` / `R_FlashLight` (`props()` in the gun scripts).
  Left-hand poses besides the holds: away (out of frame); pistol: magazine on the palm, flat palm seating it;
  machine gun: on the magazine below the well (the same magazine goes out of frame and comes back), flat palm on
  the bolt catch. The right hands never leave the grips, and the index fingers stay along the frame (the trigger
  side is hidden from the eye); only the trigger blades move.
  A reload has to lift and tilt the gun (pistol: up 8 cm, pitch 24, roll 30) or it happens below the frame.
- Grip poses (`hands.py`): finger curl angles alone do not know where a grip's corners are; with them the trigger
  hand's fingers cut straight through the grip and came out of its left panel (hidden from the eye, obvious in
  Inspect / Reload). Now `pose(wrap=...)` aims each finger bone at a point round the grip (front-strap line +
  half width, in the finger's own bending plane), `index_pts` puts the index on the trigger, `thumb_roll` turns the
  thumb's broad side out. Trigger hand: middle knuckle anchored on the right panel 21 mm behind the front strap,
  palm turned in. Support hands: pistol = over the trigger hand's fingers (first bone across the front); machine gun
  = first bone across the front face of the magazine well. `wrap` fades by `weight` when poses are mixed and carries
  a `frame` when the grip moves (magazine in the hand). Check a grip from the side, not only from the eye:
  scratch-style ortho close-ups of one view (`debug_viewmodel.py`) show penetration at once.
- Glove fabrics: the fingers are leather all the way round (thumb from its second bone); knit only on the back of
  the hand. Knit finger backs showed as light patches on the joints of the grip hand whenever the gun was turned.
- Robots (`build_robots.py`, `anim_robots.py`): every moving part hangs from a joint, an empty named
  `<Robot>_<Joint>` (`Robot.joint/add/cable/flash`); only joints are keyed, so the clips are plain node animation.
  Spider: Body, Hip/Thigh/Shin/Foot 0-3, Turret, Guns. Drone: Body, PropL/R, Gun. Turret: Yaw, Shoulder, Elbow,
  Head, Guns. The robots play together in sections (markers "Robots ..."; per-robot ranges in `v2_clips_robots`):
  Idle 1201-1272, Shoot 1281-1320, Move 1329-1400 (Spider Walk = 24-frame loop at 0.6 m/s, in place; Drone Fly;
  Turret Aim), Run 1409-1468 (Spider Run = 15-frame loop at 1.5 m/s, in place), Death 1477-1552.
  The motion is deliberately broad (user's direction: juicier, exaggerated, dramatic): anticipation before an
  action, every stop overshoots and settles (`steps`), recoil is a damped swing (`imp`) that reaches the outer
  joints a few hundredths of a second later, deaths have a stagger / spasm / spiral before the fall and a bounce.
  Spider legs are solved from ankle targets (hip swing + two-bone solve in the leg's plane, knee up), so the feet
  stay planted while the body moves. Lights going out = the emissive parts keyed to scale 0. Rebuilding the robots
  drops their animation: build_robots -> anim_robots.
- Effects (`anim_fx.py`, timing shared through `fx_plan.py`): tracers (two frames per round), impact sparks with a
  two-frame light, dust / smoke puffs, debris chips, scorch marks, muzzle smoke. All plain meshes with keyed
  transform and object colour (materials `FxGlow`, `FxTracerGlow`, `FxSmoke`, `FxDebris`, `FxScorch` read Object Info
  colour / alpha), handed out from pools and hidden by scale 0. The player's effects are in that weapon view's
  collection, the robots' in `FX`. Positions are sampled from the baked scene at each shot's frame; the guns'
  Fire / ADS rounds land where a ray from the eye hits.
  Firefight = frames 1601-1672, every view and robot firing; frame 1637 has them all firing at once (the still).
  The gun is turned toward the spider there and its rounds hit the spider and the floor at its feet.
  Order after any rebuild: build_viewmodel -> anim_pistol -> anim_rifle -> (build_robots ->) anim_robots -> anim_fx.
  Learned: a tracer at spark strength burns out to a thick white bar (own material, strength 7, 5 mm);
  a tracer passing within ~1.5 m of the eye fills the frame (cut it short); smoke as one mesh of merged balls
  shows hard seams (several single soft balls instead); dark smoke needs a third of the alpha of pale dust.
- Pads: the knuckle guard lies along the real knuckle line and wholly behind it (reaching past the knuckles, it cut
  through the finger bases of an open hand); finger pads are fitted in the rest pose, fingers apart (fitted on the
  closed hand they also wrapped onto the neighbouring finger).
- `scripts/pose_test.py`: rig check (opens the pistol's left hand, palm or `back` toward the eye; saves nothing).
  Known from it: the palm is plain leather.
- `scripts/build_pistol.py` (`Part`: mm, profiles + boolean cuts + bevels) is reused by `build_robots.py`.
- `v2lib.pbr` options: `round_edges`, `edge_wear` (+ `wear_radius`, `wear_noise`, `wear_metal`), `cavity`, `wrinkle`.
- Glove fabrics (knit back, leather palm, grippy tips) are one material, `v2lib.layered`: the edges come from the point
  attributes `palm` / `tip` written by `bake_arm`, so they are smooth lines with a sewn seam (groove + stitches),
  whatever the mesh. Assigning the fabrics per face gave a zigzag edge.
- Robots: curved shells are `Part.ellipsoid` cut to shape; the drone leans 36 deg toward the camera so both rotors read.
- Two weapon views share `PlayerCamera`: collection `Viewmodel` (pistol) and `ViewmodelRifle` (machine gun, after
  `reference/scene_concept_rifle.png`). One is hidden; switch with the two collection check boxes in the outliner,
  `show=` (build) or `view=` (render). `build_viewmodel.py` always rebuilds both. The rifle (`build_rifle.py`) reuses the pistol's grip / trigger proportions moved by (Y -32, Z -64) mm,
  so `trigger_hand()` fits both; the support hand lies on the magazine well. Its rear body is `Part.loft`
  (superellipse rings, Catmull-Rom) in two shells over a dark core that shows through the panel gaps and vents.
  Whether the trigger hand shows under the gun depends on the gun's proportions, not on where it is placed: the
  angle between sight and grip against the width of the sight is fixed by the model. So the body is slim (60 mm
  receiver) and the sight wide and low (52 mm hood, 75 mm above the bore); a taller gun hid the hand at any distance.
  Parts that overlap a curved shell (screen on the pod) need a flat seat cut into every shell under them.
- `scene.blend` is saved compressed (`save_mainfile(compress=True)` in every script): uncompressed it passed
  GitHub's 100 MB file limit once the animation and effects were in (119 MB -> 20 MB). Blender opens it as usual.
- Stages: 1 room + lighting, 2 weapon views + gloved hands, 3 robots, 4 animation + effects (all done in Blender); next: Godot.
