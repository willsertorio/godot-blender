"""Export the from-scratch assets (XM9, XM-R4 + gloves, AT-9, FR-2, SD-4) for Godot.

    blender -b -P blender/scripts/export_new_assets.py -- assets/models

For each .blend: the asset's root hierarchy (plus the free left glove for the guns) -> assets/models/<name>.glb
with the whole timeline baked into ONE animation ("Timeline", sampled every frame), and
assets/models/<name>_clips.json = {clip: [first_frame, last_frame]} at 30 fps; Godot (AnimUtil.split_clips)
cuts the named clips out of it. Review-only objects (reference image, cameras, light, boolean cutters) and the
scripted Blender casings (CasingFX*) are left out; the game spawns its own casings from casing_9mm.glb /
casing_556.glb (exported here from each gun's Parts collection, centred on the origin, along +Y).
Live modifiers (bevels, booleans) are applied here; the gloves stay skinned.
Each asset also gets a baked mask, assets/models/<name>_mask.png (one UV atlas over all its parts, Smart UV):
  R = ambient occlusion (crevices, parts shadowing each other, the gun on the gloves)
  G = edge mask (convex edges within a few mm: where paint wears off)
baked with Cycles from an emission shader built on the AO node (normal + "inside"). MaterialLib's military
shader reads it through UV1. Set ASSETS=xm9,at9 to export only some; MASK_SIZE (default 2048), BAKE_SAMPLES (16).
"""
import json
import os
import sys

import bpy

OUT = sys.argv[sys.argv.index("--") + 1]
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ASSETS = {
    "xm9": {"roots": ["XM9", "Glove.L"], "clips": {"Fire": [1, 24], "Reload": [31, 72]}, "casing": "casing_9mm",
            "ao": 0.03, "edge": 0.0035},
    "xmr4": {"roots": ["XMR4"], "clips": {"Fire": [1, 24], "Reload": [31, 90]}, "casing": "casing_556",
             "ao": 0.04, "edge": 0.004},
    "at9": {"roots": ["AT9"], "clips": {"Idle": [1, 60], "Shoot": [67, 90], "Aim": [97, 144], "Death": [151, 195]},
            "ao": 0.25, "edge": 0.02},
    "fr2": {"roots": ["FR2"], "clips": {"Idle": [1, 60], "Shoot": [67, 90], "Fly": [97, 156], "Death": [163, 207]},
            "ao": 0.25, "edge": 0.02},
    "sd4": {"roots": ["SD4Rig"], "clips": {"Idle": [1, 60], "Shoot": [67, 90], "Walk": [97, 126], "Run": [133, 152],
                                           "Death": [159, 203]}, "ao": 0.2, "edge": 0.018},
}
SKIP_COLLECTIONS = {"Cutters", "Reference", "Review", "Parts"}


def bake_mask(name, spec, meshes):
    """Apply modifiers (not armatures), unwrap every part into one atlas, bake AO (R) + edge (G) -> <name>_mask.png."""
    import math
    import time
    t0 = time.time()
    sc = bpy.context.scene
    vl = bpy.context.view_layer
    for o in meshes:
        if o.data.users > 1:
            o.data = o.data.copy()
        vl.objects.active = o
        for m in list(o.modifiers):
            if m.type == "ARMATURE":
                continue
            try:
                with bpy.context.temp_override(object=o, active_object=o, selected_objects=[o]):
                    bpy.ops.object.modifier_apply(modifier=m.name)
            except RuntimeError as e:
                print("  could not apply", o.name, m.name, e)
                o.modifiers.remove(m)
    meshes = [o for o in meshes if len(o.data.polygons) > 0]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
        while o.data.uv_layers:
            o.data.uv_layers.remove(o.data.uv_layers[0])
        o.data.uv_layers.new(name="UVMap")
    vl.objects.active = meshes[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.003, area_weight=0.0, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    size = int(os.environ.get("MASK_SIZE", 2048))
    img = bpy.data.images.new(f"{name}_mask", size, size, alpha=False)
    img.colorspace_settings.name = "Non-Color"
    bm = bpy.data.materials.new("BakeMask")
    bm.use_nodes = True
    nt = bm.node_tree
    nt.nodes.clear()
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.samples = 16
    ao.inputs["Distance"].default_value = spec.get("ao", 0.25)
    edge = nt.nodes.new("ShaderNodeAmbientOcclusion")
    edge.samples = 16
    edge.inside = True
    edge.inputs["Distance"].default_value = spec.get("edge", 0.02)
    inv = nt.nodes.new("ShaderNodeMath")
    inv.operation = "SUBTRACT"
    inv.inputs[0].default_value = 1.0
    nt.links.new(edge.outputs["AO"], inv.inputs[1])
    comb = nt.nodes.new("ShaderNodeCombineColor")
    nt.links.new(ao.outputs["AO"], comb.inputs[0])
    nt.links.new(inv.outputs[0], comb.inputs[1])
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(comb.outputs[0], em.inputs["Color"])
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.nodes.active = tex
    saved = {}
    for o in meshes:
        saved[o.name] = [(sl.material, [p.material_index for p in o.data.polygons]) for sl in o.material_slots][:1] and \
            ([sl.material for sl in o.material_slots], [p.material_index for p in o.data.polygons])
        for sl in o.material_slots:
            sl.material = bm
        if not o.material_slots:
            o.data.materials.append(bm)
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = int(os.environ.get("BAKE_SAMPLES", 16))
    sc.cycles.use_denoising = False
    sc.render.bake.margin = 6
    sc.render.bake.use_clear = True
    bpy.ops.object.bake(type="EMIT")
    img.filepath_raw = os.path.join(OUT, f"{name}_mask.png")
    img.file_format = "PNG"
    img.save()
    for o in meshes:
        mats, _ = saved[o.name]
        for sl, m in zip(o.material_slots, mats):
            sl.material = m
    print(f"baked {name}_mask.png: {len(meshes)} parts, {size}px, {time.time() - t0:.0f}s")


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
    for o in keep:
        o.hide_set(False)
        o.hide_viewport = False
    bake_mask(name, spec, [o for o in keep if o.type == "MESH" and not o.name.startswith("MuzzleFlash")])
    bpy.ops.object.select_all(action="DESELECT")
    for o in keep:
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


ONLY = [a for a in os.environ.get("ASSETS", "").split(",") if a]
for n, s in ASSETS.items():
    if not ONLY or n in ONLY:
        export(n, s)
