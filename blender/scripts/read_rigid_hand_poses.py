"""Read hand-tuned poses of the rigid hand from blender/hands_<gun>.blend -> blender/source/rigid_hand_poses.json.

    blender -b -P blender/scripts/read_rigid_hand_poses.py
    blender -b -P blender/scripts/pose_rigid_hand.py -- assets/models   # rebuild with them

Every piece of the HandModel collection (HandModelR_* / HandModelL_*) is stored with its local
location + rotation; pose_rigid_hand.py applies them over the automatic grip solver.
The gun mesh (Gun collection, *Body) may be moved / turned / scaled to fit the hands: its transform is
stored as "GunBody" and travels in rigid_<gun>.glb as an empty that WeaponHolder applies to the gun
mesh + Muzzle while the hand-model style is active.
"""
import json
import os

import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "blender", "source", "rigid_hand_poses.json")
poses = json.load(open(OUT)) if os.path.exists(OUT) else {}
for gun in ("pistol", "rifle"):
    path = os.path.join(ROOT, "blender", f"hands_{gun}.blend")
    if not os.path.exists(path):
        continue
    bpy.ops.wm.open_mainfile(filepath=path)
    per = {}
    for o in bpy.data.objects:
        name = o.name.split(".")[0]
        if not name.startswith("HandModel") or name == "HandModel":
            continue
        side = name[len("HandModel")]  # R / L
        q = o.matrix_basis.to_quaternion()
        per.setdefault("HandModel" + side, {})[o.name] = {
            "loc": [round(x, 6) for x in o.matrix_basis.translation],
            "rot": [round(x, 6) for x in q]}
    body = next((o for o in bpy.data.objects if o.type == "MESH" and o.name.endswith("Body")
                 and o.users_collection and o.users_collection[0].name == "Gun"), None)
    if body is not None:
        m = body.matrix_world
        per["GunBody"] = {"loc": [round(x, 6) for x in m.translation],
                          "rot": [round(x, 6) for x in m.to_quaternion()],
                          "scale": [round(x, 6) for x in m.to_scale()]}
    poses[gun] = per
    print(gun, {k: len(v) for k, v in per.items()})
json.dump(poses, open(OUT, "w"), indent=1)
print("wrote", OUT)
