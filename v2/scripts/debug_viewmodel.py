"""Quick EEVEE views of the Viewmodel collection only (gun space): blender -b v2/scene.blend -P v2/scripts/debug_viewmodel.py -- out_prefix"""
import sys
import bpy
from mathutils import Vector
out = sys.argv[sys.argv.index("--") + 1]
sc = bpy.context.scene
sc.render.engine = "BLENDER_EEVEE_NEXT"
sc.eevee.taa_render_samples = 8
import os
VIEW = os.environ.get("DBG_VIEW", "Viewmodel")
for c in sc.collection.children:
    c.hide_render = c.name != VIEW
w = sc.world
w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.45, 0.47, 0.5, 1)
sun = bpy.data.objects.new("dbgsun", bpy.data.lights.new("dbgsun", "SUN"))
sun.data.energy = 3
sc.collection.objects.link(sun)
M = bpy.data.objects[VIEW].matrix_world
cd = bpy.data.cameras.new("dbg")
cd.type = "ORTHO"
import os
cd.ortho_scale = float(os.environ.get("DBG_SCALE", 0.5))
cam = bpy.data.objects.new("dbg", cd)
sc.collection.objects.link(cam)
sc.camera = cam
sc.render.resolution_x, sc.render.resolution_y = 700, 700
c = Vector([float(v) for v in os.environ.get("DBG_C", "0.0,-0.08,-0.06").split(",")])
for name, d in (("back", (0, -1, 0.25)), ("right", (1, 0, 0.1)), ("left", (-1, 0, 0.1)), ("top", (0, -0.05, 1)), ("below", (0.2, 0.3, -1)), ("front", (0.2, 1, 0.2))):
    dv = Vector(d).normalized()
    cam.matrix_world = M @ ((-dv).to_track_quat("-Z", "Z").to_matrix().to_4x4())
    cam.matrix_world.translation = M @ (c + dv * 1.5)
    sun.rotation_euler = cam.matrix_world.to_euler()
    sc.render.filepath = f"{out}_{name}.png"
    bpy.ops.render.render(write_still=True)
