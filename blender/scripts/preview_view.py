"""Render what the player sees of a gun, straight from Blender (before anything goes to Godot).

    xvfb-run -a blender -b blender/xmr4.blend -P blender/scripts/preview_view.py -- rifle 1,60 captures/blender

Camera = the viewmodel camera in lib_arm.VIEWS[gun] (position + angle of the gun in front of the eye; 54 deg
vertical FOV like Godot's ViewmodelRig, 16:9). A floor 1.6 m below the eye and a far wall give scale.
Writes <out>/<gun>_view_f<frame>.png.
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import lib_arm  # noqa: E402

args = sys.argv[sys.argv.index("--") + 1:]
gun, frames, out = args[0], [int(f) for f in args[1].split(",")], args[2]
os.makedirs(out, exist_ok=True)
sc = bpy.context.scene
for c in ("Reference", "Review"):
    if bpy.data.collections.get(c):
        bpy.data.collections[c].hide_render = True
sc.render.engine = "BLENDER_EEVEE_NEXT"
sc.eevee.taa_render_samples = 8
sc.render.resolution_x, sc.render.resolution_y = 1280, 720
cm = lib_arm.camera_matrix(gun)
right, fwd, up = (cm.to_3x3().col[i].normalized() for i in range(3))
eye = cm.translation
cd = bpy.data.cameras.new("GameView")
cd.sensor_fit = "VERTICAL"
cd.angle_y = math.radians(54)
cd.clip_start = 0.01
cam = bpy.data.objects.new("GameView", cd)
sc.collection.objects.link(cam)
cam.matrix_world = Matrix.Translation(eye) @ Matrix((right, up, -fwd)).transposed().to_4x4()
sc.camera = cam
# Context: floor 1.6 m below the eye, a wall 12 m ahead.
mat = bpy.data.materials.new("PreviewGround")
mat.use_nodes = True
mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.18, 0.19, 0.21, 1)
for name, loc, rot, size in (("PreviewFloor", eye + Vector((0, 6, -1.6)), (0, 0, 0), 30),
                             ("PreviewWall", eye + fwd * 12, (math.radians(90), 0, 0), 30)):
    bpy.ops.mesh.primitive_plane_add(size=size, location=loc, rotation=rot)
    bpy.context.active_object.name = name
    bpy.context.active_object.data.materials.append(mat)
world = sc.world or bpy.data.worlds.new("World")
sc.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.35, 0.37, 0.4, 1)
if not any(o.type == "LIGHT" for o in bpy.data.objects):
    sun = bpy.data.objects.new("PreviewSun", bpy.data.lights.new("PreviewSun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(-30))
    sc.collection.objects.link(sun)
for f in frames:
    sc.frame_set(f)
    sc.render.filepath = os.path.join(out, f"{gun}_view_f{f:02d}.png")
    bpy.ops.render.render(write_still=True)
    print("rendered", sc.render.filepath)
