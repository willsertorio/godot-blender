"""Export the from-scratch assets (XM9, XM-R4 + gloves, AT-9, FR-2, SD-4) for Godot.

    blender -b -P blender/scripts/export_new_assets.py -- assets/models

For each .blend: the asset's root hierarchy (plus the free left glove for the guns) -> assets/models/<name>.glb
with the whole timeline baked into ONE animation ("Timeline", sampled every frame), and
assets/models/<name>_clips.json = {clip: [first_frame, last_frame]} at 30 fps; Godot (AnimUtil.split_clips)
cuts the named clips out of it. Review-only objects (reference image, cameras, light, boolean cutters) and the
scripted Blender casings (CasingFX*) are left out; the game spawns its own casings from casing_9mm.glb /
casing_556.glb (exported here from each gun's Parts collection, centred on the origin, along +Y).
Live modifiers (bevels, booleans) are applied by the exporter; the gloves stay skinned.
"""
import json
import os
import sys

import bpy

OUT = sys.argv[sys.argv.index("--") + 1]
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ASSETS = {
    "xm9": {"roots": ["XM9", "Glove.L"], "clips": {"Fire": [1, 24], "Reload": [31, 72]}, "casing": "casing_9mm"},
    "xmr4": {"roots": ["XMR4"], "clips": {"Fire": [1, 24], "Reload": [31, 90]}, "casing": "casing_556"},
    "at9": {"roots": ["AT9"], "clips": {"Idle": [1, 60], "Shoot": [67, 90], "Aim": [97, 144], "Death": [151, 195]}},
    "fr2": {"roots": ["FR2"], "clips": {"Idle": [1, 60], "Shoot": [67, 90], "Fly": [97, 156], "Death": [163, 207]}},
    "sd4": {"roots": ["SD4Rig"], "clips": {"Idle": [1, 60], "Shoot": [67, 90], "Walk": [97, 126], "Run": [133, 152],
                                           "Death": [159, 203]}},
}
SKIP_COLLECTIONS = {"Cutters", "Reference", "Review", "Parts"}


def export(name, spec):
    bpy.ops.wm.open_mainfile(filepath=os.path.join(ROOT, "blender", f"{name}.blend"))
    sc = bpy.context.scene
    sc.frame_set(1)
    keep = set()
    for r in spec["roots"]:
        ob = bpy.data.objects.get(r)
        if ob is None:
            continue
        keep.add(ob)
        keep.update(ob.children_recursive)
    keep = {o for o in keep if not o.name.startswith("CasingFX")
            and not any(c.name in SKIP_COLLECTIONS for c in o.users_collection)}
    for vl in bpy.context.view_layer.layer_collection.children:
        vl.exclude = False
        vl.hide_viewport = False
    for c in bpy.data.collections:
        c.hide_viewport = False
    bpy.ops.object.select_all(action="DESELECT")
    for o in keep:
        o.hide_set(False)
        o.hide_viewport = False
        o.select_set(True)
    path = os.path.join(OUT, f"{name}.glb")
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=True,
        export_animations=True, export_animation_mode="SCENE", export_anim_scene_split_object=False,
        export_force_sampling=True, export_frame_range=True, export_skins=True, export_image_format="NONE",
        export_materials="EXPORT", export_extras=False)
    bpy.data.actions  # noqa: B018
    with open(os.path.join(OUT, f"{name}_clips.json"), "w") as f:
        json.dump({"fps": sc.render.fps, "first_frame": sc.frame_start, "clips": spec["clips"]}, f, indent=1)
    print("exported", path, len(keep), "objects")
    if "casing" in spec and bpy.data.objects.get("Casing"):
        cas = bpy.data.objects["Casing"]
        for c in list(cas.users_collection):
            c.objects.unlink(cas)
        sc.collection.objects.link(cas)
        me = cas.data
        centre = sum((v.co for v in me.vertices), cas.location * 0) / len(me.vertices)
        for v in me.vertices:
            v.co -= centre
        cas.location = (0, 0, 0)
        cas.parent = None
        bpy.ops.object.select_all(action="DESELECT")
        cas.select_set(True)
        cpath = os.path.join(OUT, f"{spec['casing']}.glb")
        bpy.ops.export_scene.gltf(filepath=cpath, export_format="GLB", use_selection=True, export_yup=True,
                                  export_apply=True, export_animations=False, export_image_format="NONE")
        print("exported", cpath)


for n, s in ASSETS.items():
    export(n, s)
