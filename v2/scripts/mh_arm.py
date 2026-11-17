"""Human arms for the V2 concept, from the MakeHuman base mesh (CC0): mesh + skeleton + skin weights.

build_arm("R" | "L") -> (armature object, mesh object) in the MakeHuman rest pose, converted to metres, Z up.
Only the arm is kept (upper arm -> fingertips). Bones: upperarm01/02, lowerarm01/02, wrist, metacarpal1-4,
finger<1-5>-<1-3> (finger1 = thumb, 2 = index ... 5 = pinky), named without the side suffix.
Source files: v2/source/makehuman/ (base.obj, default.mhskel, default_weights.mhw).
"""
import json
import os

import bpy
from mathutils import Vector

SRC = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "source", "makehuman"))
_data = {}


def _load():
    if _data:
        return _data
    verts, faces = [], []
    group = ""
    with open(os.path.join(SRC, "base.obj")) as f:
        for line in f:
            if line.startswith("v "):
                x, y, z = (float(t) for t in line.split()[1:4])
                verts.append(Vector((x, -z, y)) * 0.1)          # decimetres, Y up -> metres, Z up
            elif line.startswith("g "):
                group = line.split()[1]
            elif line.startswith("f ") and not group.startswith(("helper", "joint")):
                faces.append([int(t.split("/")[0]) - 1 for t in line.split()[1:]])
    sk = json.load(open(os.path.join(SRC, "default.mhskel")))
    joints = {k: sum((verts[i] for i in idx), Vector()) / len(idx) for k, idx in sk["joints"].items()}
    weights = json.load(open(os.path.join(SRC, "default_weights.mhw")))["weights"]
    _data.update(verts=verts, faces=faces, bones=sk["bones"], joints=joints, weights=weights)
    return _data


def bone_names():
    names = ["upperarm01", "upperarm02", "lowerarm01", "lowerarm02", "wrist"] + [f"metacarpal{i}" for i in range(1, 5)]
    names += [f"finger{f}-{j}" for f in range(1, 6) for j in range(1, 4)]
    return names


def build_arm(side, collection):
    d = _load()
    names = bone_names()
    vw = {}                                   # vertex -> {bone: weight}
    for b in names:
        for vi, wgt in d["weights"].get(f"{b}.{side}", []):
            vw.setdefault(vi, {})[b] = wgt
    # drop the shoulder / torso flap: keep vertices that belong to the arm below the first upper-arm bone
    keep = sorted(v for v, ws in vw.items() if sum(w for b, w in ws.items() if b != "upperarm01") > 0.35)
    remap = {v: i for i, v in enumerate(keep)}
    faces = [[remap[v] for v in f] for f in d["faces"] if all(v in remap for v in f)]
    me = bpy.data.meshes.new(f"Arm.{side}")
    me.from_pydata([d["verts"][v] for v in keep], [], faces)
    me.update()
    ob = bpy.data.objects.new(f"Arm.{side}", me)
    collection.objects.link(ob)
    for b in names:
        ob.vertex_groups.new(name=b)
    for v in keep:
        tot = sum(vw[v].values())
        for b, wgt in vw[v].items():
            ob.vertex_groups[b].add([remap[v]], wgt / tot, "REPLACE")
    for p in me.polygons:
        p.use_smooth = True
    arm = bpy.data.armatures.new(f"ArmRig.{side}")
    rig = bpy.data.objects.new(f"ArmRig.{side}", arm)
    collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for b in names:
        spec = d["bones"][f"{b}.{side}"]
        eb = arm.edit_bones.new(b)
        eb.head, eb.tail = d["joints"][spec["head"]], d["joints"][spec["tail"]]
        par = (spec["parent"] or "").replace(f".{side}", "")
        if par in arm.edit_bones:
            eb.parent = arm.edit_bones[par]
    bpy.ops.object.mode_set(mode="OBJECT")
    ob.parent = rig
    mod = ob.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    return rig, ob
