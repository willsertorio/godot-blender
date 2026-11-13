"""Render one baked clip as numbered frames (Cycles, small and quick, for GIF previews).

    blender -b v2/scene.blend -P v2/scripts/render_anim.py -- <weapon> <Clip> <out_dir> [samples=24] [width=480] [step=1] [frames=a,b,c]

Then: ffmpeg -framerate <24/step> -i out_dir/f_%04d.png -vf "split[a][b];[a]palettegen[p];[b][p]paletteuse" clip.gif
(tools: v2/scripts/make_gifs.sh does both for every clip)
"""
import json
import os
import sys

import bpy

a = sys.argv[sys.argv.index("--") + 1:]
weapon, clip, out = a[0], a[1], a[2]
opt = dict(v.split("=") for v in a[3:])
sc = bpy.context.scene
c = json.loads(sc["v2_clips_" + weapon])[clip]
for name, cname in (("pistol", "Viewmodel"), ("rifle", "ViewmodelRifle")):
    bpy.data.collections[cname].hide_render = name != weapon
width = int(opt.get("width", 480))
sc.render.resolution_percentage = round(100 * width / sc.render.resolution_x)
sc.cycles.samples = int(opt.get("samples", 24))
sc.cycles.use_adaptive_sampling = True
sc.cycles.max_bounces = 4
sc.render.use_persistent_data = True
step = int(opt.get("step", 1))
frames = [int(v) for v in opt["frames"].split(",")] if "frames" in opt else range(c["start"], c["end"] + 1, step)
os.makedirs(out, exist_ok=True)
for i, f in enumerate(frames):
    sc.frame_set(f)
    sc.render.filepath = os.path.join(out, f"f_{i:04d}.png")
    bpy.ops.render.render(write_still=True)
print("rendered", clip, len(list(frames)), "frames")
