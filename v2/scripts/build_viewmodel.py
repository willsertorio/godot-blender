"""V2 concept scene: the two weapon views (pistol, machine gun), each held in two gloved, rigged arms.

    blender -b -P v2/scripts/build_viewmodel.py -- show=rifle     (run after build_room.py; rebuilds both views)

Everything is built in "gun space" (barrel +Y, up +Z, metres) and then placed in front of the player camera through
the view's root empty. Collections: Viewmodel (pistol) and ViewmodelRifle (machine gun); only one is shown at a time
(`show=rifle|pistol` here, `view=...` in render.py, or the two collection check boxes in Blender's outliner).
- Guns: build_pistol.py, build_rifle.py; their ANCHORS place the hands.
- Arms, gloves, pads, poses: hands.py. The arms stay rigged (armature ArmRig.<side>.<weapon>), in the hold pose.
"""
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(__file__))
import v2lib as L  # noqa: E402
import hands as H  # noqa: E402
import build_pistol  # noqa: E402
import build_rifle  # noqa: E402

SHOW = next((a.split("=")[1] for a in sys.argv if a.startswith("show=")), "rifle")
GUNS = {"pistol": (build_pistol, H.pistol_hold), "rifle": (build_rifle, H.rifle_hold)}

bpy.ops.wm.open_mainfile(filepath=os.path.join(L.ROOT, "scene.blend"))
for cname in H.COLL.values():
    old = bpy.data.collections.get(cname)
    if old:
        for o in list(old.all_objects):
            bpy.data.objects.remove(o)
        bpy.data.collections.remove(old)
for block in (bpy.data.armatures, bpy.data.meshes):          # data of the removed objects
    for d in list(block):
        if d.users == 0:
            block.remove(d)
mats = H.materials()

for weapon, (gun, hold) in GUNS.items():
    coll = L.coll(H.COLL[weapon])
    coll.hide_render = coll.hide_viewport = False              # (hidden collections are not evaluated)
    root = bpy.data.objects.new(H.COLL[weapon], None)
    root.empty_display_size = 0.05
    coll.objects.link(root)
    gun.build(coll, root)
    hands = H.Hands(coll, root, weapon, mats)
    hands.hold(hold(gun.ANCHORS, H.cam_in_gun(weapon)))
    root.matrix_world = H.view_matrix(weapon, bpy.data.objects["PlayerCamera"])
    print(f"{weapon} view built:", len(coll.all_objects), "objects")

for weapon, cname in H.COLL.items():                           # one view at a time
    bpy.data.collections[cname].hide_render = bpy.data.collections[cname].hide_viewport = weapon != SHOW
bpy.ops.wm.save_mainfile()
