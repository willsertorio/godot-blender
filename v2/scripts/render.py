"""Render the open scene with Cycles: blender -b v2/scene.blend -P v2/scripts/render.py -- out.png [samples] [percent]"""
import sys
import bpy
a = sys.argv[sys.argv.index("--") + 1:]
sc = bpy.context.scene
sc.cycles.samples = int(a[1]) if len(a) > 1 else 96
sc.render.resolution_percentage = int(a[2]) if len(a) > 2 else 100
sc.render.threads_mode = "AUTO"
sc.render.filepath = a[0]
bpy.ops.render.render(write_still=True)
print("rendered", a[0])
