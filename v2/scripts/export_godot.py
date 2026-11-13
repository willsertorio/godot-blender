"""V2 -> Godot: exports v2/scene.blend to assets/models/v2/ (nothing is saved back to the .blend).

    v2/scripts/export_godot.sh        (= blender -b v2/scene.blend -P v2/scripts/export_godot.py -- <asset>, one asset
                                       per Blender process: several animated exports in one process crash Blender 4.2
                                       at the end of the third, and it also crashes on exit after some; the files
                                       are complete, the script checks that they were written)
    python3 -I v2/scripts/pack_textures_godot.py            # the texture sets, 1K, into assets/textures/v2/

  room.glb                                the room (static), in Blender's world placement (glTF Y-up)
  spider.glb / drone.glb / turret.glb     each robot where it stands in the room, joints + one baked "Scene" animation
  view_pistol.glb / view_rifle.glb        gun + rigged gloved arms under an empty "Eye" that stands for the camera
  <name>_clips.json                       {"fps", "clips": {name: [first, last]}} in timeline frames (time = frame / fps)
  materials.json                          material name -> what Godot needs to rebuild it (read off the node trees)
No images are exported: Godot rebuilds the materials from materials.json + assets/textures/v2 (scripts/v2/v2_assets.gd).
Gloves: UV0 = rest position x, y and UV1.x = rest z (normalised to the mesh's box, in materials.json), vertex colour
= (palm mask, tip mask): the Godot glove shader projects the fabrics from the rest position, as the Blender material does.
"""
import json
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import hands as H  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(REPO, "assets", "models", "v2")
os.makedirs(OUT, exist_ok=True)
sc = bpy.context.scene
FPS = sc.render.fps
for c in bpy.data.collections:
    c.hide_viewport = False
sc.frame_set(0)                                    # everything at rest
bpy.context.view_layer.update()
used, gloves = set(), {}
HAS_VCOL = "export_vertex_color" in bpy.ops.export_scene.gltf.get_rna_type().properties.keys()


TINY = 0.001


def export(name, objs, frames=None):
    # "hidden" is scale 0 in the .blend; Godot's importer chokes on a zero scale (the node comes in at scale 1 and its
    # scale track is lost), so hidden becomes a thousandth instead: Godot treats scale < 0.01 as off
    for o in objs:
        if max(abs(v) for v in o.scale) < TINY:
            o.scale = (TINY, TINY, TINY)
        ad = o.animation_data
        if ad and ad.action:
            for fc in ad.action.fcurves:
                if fc.data_path == "scale":
                    for kp in fc.keyframe_points:
                        if abs(kp.co[1]) < TINY:
                            kp.co[1] = TINY
                    fc.update()
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.hide_set(False)
        o.select_set(True)
        for s in getattr(o, "material_slots", []):
            if s.material:
                used.add(s.material)
    bpy.context.view_layer.objects.active = objs[0]
    kw = dict(filepath=os.path.join(OUT, name + ".glb"), export_format="GLB", use_selection=True, export_yup=True,
              export_apply=True, export_image_format="NONE", export_materials="EXPORT", export_extras=False,
              export_animations=bool(frames))
    if HAS_VCOL:
        kw["export_vertex_color"] = "ACTIVE"
    if frames:
        sc.frame_start, sc.frame_end = frames
        kw.update(export_animation_mode="SCENE", export_anim_scene_split_object=False, export_force_sampling=True,
                  export_frame_range=True, export_skins=True)
    faces = sum(len(o.data.polygons) for o in objs if o.type == "MESH")
    print(f"exporting {name}.glb: {len(objs)} objects, {faces} faces", flush=True)
    bpy.ops.export_scene.gltf(**kw)


def flash_frames(objs, first, last):
    """{flash object: [frames on which it is shown]} read from the baked scale keys. Godot's importer loses these
    one-frame spikes, so v2_assets.gd rebuilds the flashes' scale tracks from this list."""
    out = {}
    for o in objs:
        ad = o.animation_data
        if o.type == "MESH" and "Flash" in o.name and ad and ad.action:
            fc = ad.action.fcurves.find("scale", index=0)
            if fc:
                out[o.name] = [int(kp.co[0]) for kp in fc.keyframe_points if kp.co[1] > 0.5 and first <= kp.co[0] <= last]
    return out


def write_clips(name, clips, objs):
    first, last = min(c["start"] for c in clips.values()), max(c["end"] for c in clips.values())
    with open(os.path.join(OUT, name + "_clips.json"), "w") as f:
        # (the exported animation keeps the timeline's own times: frame / fps, whatever the first exported frame is)
        json.dump({"fps": FPS, "clips": {k: [c["start"], c["end"]] for k, c in clips.items()},
                   "loops": [k for k, c in clips.items() if c.get("loop")], "flashes": flash_frames(objs, first, last)}, f, indent=1)
    return first, last


WHAT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "materials"
cam = bpy.data.objects["PlayerCamera"]
cam_rest = cam.matrix_world.copy()
rclips = json.loads(sc["v2_clips_robots"])
ROBOTS = ("Spider", "Drone", "Turret")


def room_objects():
    return [o for o in bpy.data.collections["Room"].all_objects if o.type in ("MESH", "CURVE")]


def robot_objects(robot):
    return [o for o in bpy.data.collections["Robots"].all_objects if o.name.startswith(robot + "_") and o.type != "LIGHT"]


def view_objects(weapon):
    return [o for o in bpy.data.collections[H.COLL[weapon]].all_objects if o.type != "LIGHT" and not o.name.startswith("Fx")]


def prep_glove(ob):
    me = ob.data
    n = len(me.vertices)
    # read everything first: adding an attribute moves the others in memory (a stale reference crashes Blender)
    pos, pv, tv = [0.0] * (n * 3), [0.0] * n, [0.0] * n
    me.attributes["rest"].data.foreach_get("vector", pos)
    me.attributes["palm"].data.foreach_get("value", pv)
    me.attributes["tip"].data.foreach_get("value", tv)
    lo = [min(pos[i::3]) for i in range(3)]
    size = [max(max(pos[i::3]) - lo[i], 1e-6) for i in range(3)]
    rn = [(pos[k * 3 + i] - lo[i]) / size[i] for k in range(n) for i in range(3)]      # rest position, 0..1 in its box
    me.color_attributes.new("Masks", "FLOAT_COLOR", "POINT")
    me.color_attributes["Masks"].data.foreach_set("color", [v for k in range(n) for v in (pv[k], tv[k], 0.0, 1.0)])
    me.color_attributes.active_color = me.color_attributes["Masks"]
    me.color_attributes.render_color_index = me.color_attributes.find("Masks")
    # (the rest position goes into two UV sets: Godot keeps UVs at 16 bits, vertex colours only at 8)
    me.uv_layers.new(name="RestXY")
    me.uv_layers["RestXY"].data.foreach_set("uv", [v for lp in me.loops for v in (rn[lp.vertex_index * 3], rn[lp.vertex_index * 3 + 1])])
    me.uv_layers.new(name="RestZ")
    me.uv_layers["RestZ"].data.foreach_set("uv", [v for lp in me.loops for v in (rn[lp.vertex_index * 3 + 2], 0.0)])
    gloves[ob.name.replace(".", "_")] = {"min": lo, "size": size}



# ---------------------------------------------------------------------- materials, read off the node trees
def base_value(sock):
    """A socket's value before the wear overlay: the overlay mixes the original (a Value node on input A) with the
    worn value, so follow input A upstream. A texture counts as 1."""
    for _ in range(6):
        if not sock.is_linked:
            return sock.default_value
        node = sock.links[0].from_node
        if node.bl_idname == "ShaderNodeValue":
            return node.outputs[0].default_value
        if node.bl_idname == "ShaderNodeMix":
            sock = node.inputs[2]
        else:
            return 1.0
    return 0.0


def describe(m):
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF") if nt else None
    tex = [n for n in nt.nodes if n.bl_idname == "ShaderNodeTexImage" and n.image] if nt else []
    if bsdf is None:
        return {"type": "special"}
    if tex:
        d = {"type": "pbr"}
        col = next((n for n in tex if "_Color" in n.image.filepath), tex[0])
        d["set"] = os.path.basename(os.path.dirname(bpy.path.abspath(col.image.filepath)))
        mp = next((n for n in nt.nodes if n.bl_idname == "ShaderNodeMapping"), None)
        d["scale"] = round(1.0 / mp.inputs["Scale"].default_value[0], 5) if mp else 1.0
        mix = next((l.to_node for l in col.outputs["Color"].links if l.to_node.bl_idname == "ShaderNodeMix"), None)
        d["tint"] = [round(v, 4) for v in mix.inputs[7].default_value[:3]] if mix else [1, 1, 1]
        rt = next((n for n in tex if "_Roughness" in n.image.filepath), None)
        mr = next((l.to_node for l in rt.outputs["Color"].links if l.to_node.bl_idname == "ShaderNodeMapRange"), None) if rt else None
        d["rough"] = [round(mr.inputs["To Min"].default_value, 3), round(mr.inputs["To Max"].default_value, 3)] if mr else [0.5, 0.5]
        d["metallic"] = round(base_value(bsdf.inputs["Metallic"]), 3)
        nm = next((n for n in nt.nodes if n.bl_idname == "ShaderNodeNormalMap"), None)
        d["normal"] = round(nm.inputs["Strength"].default_value, 3) if nm else 1.0
        d["vcol"] = any(n.bl_idname == "ShaderNodeAttribute" and n.outputs["Color"].is_linked for n in nt.nodes)
        return d
    em = bsdf.inputs["Emission Color"].default_value
    return {"type": "plain", "color": [round(v, 4) for v in bsdf.inputs["Base Color"].default_value[:3]],
            "rough": round(bsdf.inputs["Roughness"].default_value, 3), "metallic": round(bsdf.inputs["Metallic"].default_value, 3),
            "emit": [round(v, 4) for v in em[:3]], "emit_strength": round(bsdf.inputs["Emission Strength"].default_value, 3),
            "alpha": round(bsdf.inputs["Alpha"].default_value, 3),
            "transmission": round(bsdf.inputs["Transmission Weight"].default_value, 3),
            "linked": bsdf.inputs["Base Color"].is_linked}



def robot_clips(robot):
    return {k.split(" ", 1)[1]: c for k, c in rclips.items() if k.startswith(robot + " ") and "Firefight" not in k}


def view_clips(weapon):
    return {k: c for k, c in json.loads(sc["v2_clips_" + weapon]).items() if k != "Firefight"}


if WHAT == "room":
    export("room", room_objects())
elif WHAT == "clips":                              # only the clip tables
    for r in ROBOTS:
        write_clips(r.lower(), robot_clips(r), robot_objects(r))
    for w in H.COLL:
        write_clips("view_" + w, view_clips(w), view_objects(w))
elif WHAT.capitalize() in ROBOTS:
    robot = WHAT.capitalize()
    objs = robot_objects(robot)
    write_clips(WHAT, robot_clips(robot), objs)
    first = min(c["start"] for c in rclips.values())      # (all three robots share one range)
    last = max(c["end"] for k, c in rclips.items() if "Firefight" not in k)
    export(WHAT, objs, (first, last))
elif WHAT in H.COLL:
    cname = H.COLL[WHAT]
    root = bpy.data.objects[cname]
    eye = bpy.data.objects.new("Eye", None)        # stands for the camera: the view's root keeps its keyed local motion
    bpy.data.collections[cname].objects.link(eye)
    eye.matrix_world = cam_rest
    root.parent = eye
    root.matrix_parent_inverse = Matrix.Identity(4)
    objs = view_objects(WHAT)
    for o in objs:
        if o.name.startswith("Glove."):
            prep_glove(o)
    export("view_" + WHAT, objs, write_clips("view_" + WHAT, view_clips(WHAT), objs))
else:                                              # materials.json
    objs = room_objects() + [o for r in ROBOTS for o in robot_objects(r)] + [o for w in H.COLL for o in view_objects(w)]
    for o in objs:
        if o.name.startswith("Glove."):
            prep_glove(o)
        for s_ in getattr(o, "material_slots", []):
            if s_.material:
                used.add(s_.material)
    mats = {m.name: describe(m) for m in sorted(used, key=lambda m_: m_.name)}
    import math
    with open(os.path.join(OUT, "materials.json"), "w") as f:
        json.dump({"materials": mats, "gloves": gloves,
                   "camera": {"fov_h": round(math.degrees(cam.data.angle_x), 2), "eye": list(cam_rest.translation)}}, f, indent=1)
    print("materials:", {k: v["type"] + (":" + v.get("set", "")) for k, v in mats.items()})
