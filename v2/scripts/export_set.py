"""The environment set for the game: v2/scripts/set_*.py built at the game's detail -> assets/models/v2/set.glb.

    blender -b -P v2/scripts/export_set.py [-- --only=a,b] [--no-ao]

What the game gets, and why it is not simply the .blend's objects:
  - every asset is an empty (its name) with ONE MESH PER MATERIAL under it: the dungeon merges pieces by material
    (V2Dungeon._meshes), and a prop is a handful of draw calls instead of fifty;
  - the bevels are single chamfers (the renders have two segments) and round things have fewer sides (setlib.GAME);
  - the wear the Blender materials find with Cycles-only nodes is written into the meshes, in the vertex colour:
    R = ambient occlusion (baked per face corner), G = 1 on the chamfers (the edges the paint wears off first).
    assets/shaders/v2_set.gdshader reads it. Colours are per face corner, so a flat face next to a chamfer stays 0;
  - a loot crate's lid parts are under an empty `Crate_Lid` at the hinge, so the game can turn it;
  - nothing in the same plane as anything else of another material (it flickers in the game): the assets are
    built that way, and the game-only pieces (set_structure.py, the last section) are the ones that tile.
No images are exported: the game makes its materials from their names (V2Assets)."""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import setlib as S  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
only = []
for a in argv:
    if a.startswith("--only="):
        only = a[7:].split(",")
BAKE = "--no-ao" not in argv
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "models", "v2", "set.glb"))
NO_AO = ("ECyan", "EOrange", "ELed", "ELight", "ECoreGlow", "EScreen", "EPanelScreen", "EPortal", "ETankGlass", "ELiquid", "ECable", "EInk")

S.GAME[0] = True
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = S.studio(16)
import set_structure, set_cover, set_equipment, set_pickups  # noqa: E401,E402,F401

sc.world.light_settings.distance = 0.35
sc.cycles.samples = 24
sc.cycles.use_denoising = False
out_coll = bpy.data.collections.new("Export")
sc.collection.children.link(out_coll)


def chamfered(ob):
    """The part's mesh with its bevel modifier done as one chamfer, and the vertex colour: G = 1 on the chamfers."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    col = bm.loops.layers.color.new("Col")
    for f in bm.faces:
        for lp in f.loops:
            lp[col] = (1, 0, 1, 1)
    bev = next((md for md in ob.modifiers if md.type == "BEVEL"), None)
    if bev is not None and bev.width > 0:
        edges = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > bev.angle_limit]
        if edges:
            res = bmesh.ops.bevel(bm, geom=edges, offset=bev.width, offset_type="OFFSET", segments=1, profile=0.5, affect="EDGES", clamp_overlap=True)
            for f in res["faces"]:
                for lp in f.loops:
                    lp[col] = (1, 1, 1, 1)
    return bm


def plain(ob, deps):
    """A curve or a text as a mesh, vertex colour: no edges."""
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(deps))
    bm = bmesh.new()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    col = bm.loops.layers.color.new("Col")
    for f in bm.faces:
        for lp in f.loops:
            lp[col] = (1, 0, 1, 1)
    return bm


def export_asset(name, root, opts, at):
    deps = bpy.context.evaluated_depsgraph_get()
    lid = opts.get("lid")
    top = bpy.data.objects.new(name, None)
    out_coll.objects.link(top)
    top.location = at
    groups = {}                                            # (group, material) -> bmesh, in the asset's own frame
    inv = root.matrix_world.inverted()
    for ob in root.children_recursive:
        if ob.type not in ("MESH", "CURVE", "FONT") or not ob.data.materials:
            continue
        part = chamfered(ob) if ob.type == "MESH" else plain(ob, deps)
        bmesh.ops.transform(part, matrix=inv @ ob.matrix_world, verts=part.verts)
        if os.environ.get("SET_PARTS"):
            print("[part] %-16s %-28s %5d" % (name, ob.name, sum(len(f.verts) - 2 for f in part.faces)))
        group = "Crate_Lid" if (lid and "_lid" in ob.name.replace(" ", "_")) else ""
        key = (group, ob.data.materials[0].name)
        tmp = bpy.data.meshes.new("tmp")
        part.to_mesh(tmp)
        part.free()
        if key not in groups:
            groups[key] = bmesh.new()
            groups[key].loops.layers.color.new("Col")
        groups[key].from_mesh(tmp)                         # (from_mesh adds to what is there)
        bpy.data.meshes.remove(tmp)
    tris = 0
    made = []
    parents = {"": top}
    if lid:
        hinge = bpy.data.objects.new("Crate_Lid", None)
        out_coll.objects.link(hinge)
        hinge.parent = top
        hinge.location = lid
        parents["Crate_Lid"] = hinge
    for (group, mat_name), bm in groups.items():
        if group:
            bmesh.ops.translate(bm, verts=bm.verts, vec=-Vector(lid))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        me = bpy.data.meshes.new("%s__%s%s" % (name, group + "__" if group else "", mat_name))
        bm.to_mesh(me)
        tris += sum(len(f.verts) - 2 for f in bm.faces)
        bm.free()
        me.materials.append(bpy.data.materials[mat_name])
        for p in me.polygons:
            p.use_smooth = True
        me.set_sharp_from_angle(angle=math.radians(35))
        ob = bpy.data.objects.new(me.name, me)
        out_coll.objects.link(ob)
        ob.parent = parents[group]
        wn = ob.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL")
        wn.keep_sharp = True
        made.append(ob)
    return top, made, tris


def bake_ao(objs):
    """Ambient occlusion into the red of each mesh's vertex colour (the asset's other parts shade it)."""
    for ob in objs:
        me = ob.data
        if any(me.materials[0].name.startswith(n) for n in NO_AO):
            continue
        ao = me.color_attributes.new("AO", "BYTE_COLOR", "CORNER")
        me.color_attributes.active_color = ao
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.bake(type="AO", target="VERTEX_COLORS")
        col = me.color_attributes["Col"]
        # (a big flat face keeps 1: its corners often touch another part, which reads as shade, and the shade is
        # then smeared across the whole face: one field of a floor tile came out grey, the other white)
        for poly in me.polygons:
            big = poly.area > 0.02
            for i in poly.loop_indices:
                c = col.data[i].color
                col.data[i].color = (1.0 if big else ao.data[i].color[0], c[1], c[2], 1.0)
        me.color_attributes.remove(me.color_attributes["AO"])
    for ob in objs:
        ob.data.color_attributes.active_color = ob.data.color_attributes["Col"]
        ob.data.color_attributes.render_color_index = ob.data.color_attributes.find("Col")


x = 0.0
tops = []
total = 0
for name, (fn, opts) in S.ASSETS.items():
    if only and name not in only:
        continue
    root = S.begin(name, at=(x, 0, 100.0))                 # (built out of the way, exported at the origin row)
    fn()
    bpy.context.view_layer.update()
    top, made, tris = export_asset(name, root, opts, (x, 0, 0))
    for ob in list(root.children_recursive) + [root]:      # the source parts are done with
        bpy.data.objects.remove(ob, do_unlink=True)
    bpy.context.view_layer.update()
    if BAKE:
        for o in out_coll.objects:                         # only this asset shades itself
            o.hide_render = o not in made
        bake_ao(made)
    lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    for ob in made:
        for v in ob.data.vertices:
            w = ob.matrix_world @ v.co - Vector((x, 0, 0))
            lo, hi = Vector(map(min, lo, w)), Vector(map(max, hi, w))
    print("[export] %-18s %6d triangles, %2d meshes, x %.2f..%.2f  y %.2f..%.2f  z %.2f..%.2f" % (name, tris, len(made), lo.x, hi.x, lo.y, hi.y, lo.z, hi.z))
    total += tris
    tops.append(top)
    x += 8.0

for o in out_coll.objects:
    o.hide_render = False
bpy.ops.object.select_all(action="DESELECT")
for o in out_coll.objects:
    o.select_set(True)
bpy.context.view_layer.objects.active = tops[0]
kw = dict(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True, export_apply=True, export_image_format="NONE",
          export_materials="EXPORT", export_animations=False)
if "export_vertex_color" in bpy.ops.export_scene.gltf.get_rna_type().properties.keys():
    kw["export_vertex_color"] = "ACTIVE"
    kw["export_all_vertex_colors"] = False
if not only:
    bpy.ops.export_scene.gltf(**kw)
    print("[export] %d assets, %d triangles -> %s (%.1f MB)" % (len(tops), total, OUT, os.path.getsize(OUT) / 1e6))
else:
    kw["filepath"] = OUT.replace("set.glb", "set_test.glb")
    bpy.ops.export_scene.gltf(**kw)
    print("[export] test: %d assets, %d triangles -> %s" % (len(tops), total, kw["filepath"]))
