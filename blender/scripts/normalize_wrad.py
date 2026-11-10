"""WRAD ARMS by wriks (CC0) -> assets/models/arms_wrad.glb.

    blender -b -P blender/scripts/normalize_wrad.py -- assets_src/wrad/arms.glb assets/models

The pack ships a full first-person rig (both arms, shoulders, finger chains, IK targets, a
`socket` bone in each palm). We only: scale it to metres (shoulder -> wrist ~0.55 m), move the
origin to the `head` bone (so Godot can parent the rig straight to the camera), drop Blender's
helper sphere, rename the material to `WradArm`, and embed the pale skin texture.
Posing (IK onto the gun grips, finger curls) happens in Godot: scripts/view_arms.gd.
"""
import os
import sys

import bpy
from mathutils import Matrix, Vector

args = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = args[0], args[1]
ARM_LENGTH = 0.55  # metres, shoulder joint -> wrist

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
for o in list(bpy.data.objects):
    if o.type == "MESH" and not o.data.materials:
        bpy.data.objects.remove(o)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
bones = arm.data.bones
length = (bones["wrist.r"].head_local - bones["bicep.r"].head_local).length
k = ARM_LENGTH / length
head = arm.matrix_world @ bones["head"].head_local
arm.matrix_world = Matrix.Scale(k, 4) @ Matrix.Translation(-head) @ arm.matrix_world
bpy.context.view_layer.objects.active = arm
bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True)
for c in arm.children:
    c.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
arm.name = "WradArms"
for m in bpy.data.materials:
    m.name = "WradArm"
print(f"scale {k:.4f}; wrist.r at {tuple(round(x, 3) for x in bones['wrist.r'].head_local)}")
bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True)
for c in arm.children:
    c.select_set(True)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "arms_wrad.glb"), export_format="GLB", use_selection=True,
                          export_yup=True, export_skins=True, export_animations=False, export_image_format="AUTO")
print("exported", os.path.join(OUT, "arms_wrad.glb"))
