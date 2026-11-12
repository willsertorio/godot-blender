"""Render the open scene with Cycles: blender -b v2/scene.blend -P v2/scripts/render.py -- out.png [samples] [percent] [crop x0,y0,x1,y1] [view=pistol|rifle]"""
import sys
import bpy
a = sys.argv[sys.argv.index("--") + 1:]
view = next((v.split("=")[1] for v in a if v.startswith("view=")), None)     # view=pistol | view=rifle
a = [v for v in a if not v.startswith("view=")]
if view:
    for name, c in (("pistol", "Viewmodel"), ("rifle", "ViewmodelRifle")):
        if bpy.data.collections.get(c):
            bpy.data.collections[c].hide_render = name != view
sc = bpy.context.scene
sc.cycles.samples = int(a[1]) if len(a) > 1 else 96
sc.render.resolution_percentage = int(a[2]) if len(a) > 2 else 100
sc.render.threads_mode = "AUTO"
if len(a) > 3:      # optional crop: x0,y0,x1,y1 as fractions of the frame (origin bottom-left)
    x0, y0, x1, y1 = (float(v) for v in a[3].split(","))
    sc.render.use_border = sc.render.use_crop_to_border = True
    sc.render.border_min_x, sc.render.border_min_y, sc.render.border_max_x, sc.render.border_max_y = x0, y0, x1, y1
sc.render.filepath = a[0]
bpy.ops.render.render(write_still=True)
print("rendered", a[0])
