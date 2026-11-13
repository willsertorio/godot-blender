"""Rig check for the weapon views: opens the left hand of the pistol view and lifts it off the gun, palm toward the
eye, then renders from the player camera. Nothing is saved.

    blender -b v2/scene.blend -P v2/scripts/pose_test.py -- out.png [samples] [percent] [back]   (back = back of the hand)
"""
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
import hands as H  # noqa: E402

a = sys.argv[sys.argv.index("--") + 1:]
BACK = "back" in a
for name, c in H.COLL.items():
    bpy.data.collections[c].hide_render = bpy.data.collections[c].hide_viewport = name != "pistol"
CAM = H.cam_in_gun("pistol")
rig = bpy.data.objects["ArmRig.L.pistol"]
rig.animation_data_clear()                     # (the baked clips would put the hold pose back at render time)
H.pose(rig, "L",
       curls={2: (8, 14, 8), 3: (10, 16, 9), 4: (14, 20, 10), 5: (20, 26, 12)},
       F_t=Vector((0.1, 0.25, 1.0)), A_hint=Vector((-1.0 if BACK else 1.0, 0.0, 0.0)),
       anchor_fn=lambda pb, w0, k, F, A, pn: w0.lerp(k[3], 0.55) + pn * 0.014,
       anchor_target=Vector((-0.17, 0.02, -0.03)),
       shoulder=CAM + Vector((-0.1, -0.04, -0.3)), pole=(-0.7, 0.0, -1.0),
       thumb_dirs=[(x * (-1 if BACK else 1), y, z) for x, y, z in ((-0.8, 0.1, 0.45), (-0.7, 0.05, 0.7), (-0.55, 0.0, 0.85))])
sc = bpy.context.scene
sc.cycles.samples = int(a[1]) if len(a) > 1 else 48
sc.render.resolution_percentage = int(a[2]) if len(a) > 2 else 100
sc.render.filepath = a[0]
bpy.ops.render.render(write_still=True)
print("rendered", a[0])
