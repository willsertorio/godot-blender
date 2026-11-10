"""Bake WRAD ARMS hold poses onto each gun -> assets/models/arms_<weapon>.glb.

    blender -b -P blender/scripts/pose_wrad.py -- assets/models

Space: the camera frame (rig `head` bone at the origin, looking +Y = Godot -Z). The gun is placed at
its hip offset; grip markers (handle centre, finger direction, palm direction) come from GRIPS
(Godot weapon frame). For each hand: measure the hand frame from the rig (F = wrist -> middle
knuckle, A = knuckle line, N = palm normal found by curling the fingers), solve the wrist pose that
puts the knuckles around the handle, reach it with Blender IK (bicep -> forearm) + copy-rotation on
the wrist, curl the fingers, then bake that pose as the rest pose. Hands with no grip hang down out
of view. In Godot the arms are parented to the gun model at -hip, so they move with it.
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

OUT = sys.argv[sys.argv.index("--") + 1]
ARMS = os.path.join(OUT, "arms_wrad.glb")
C = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))  # Godot -> Blender axes

# Godot weapon frame: -Z barrel, +Y up. hip = gun position in the camera frame (WeaponHolder).
GUNS = {
    "pistol": {"hip": Vector((0.16, -0.15, -0.4)),
               "r": {"pos": Vector((0, 0.028, 0.004)), "fingers": Vector((0, -0.25, -1)), "knuckles": Vector((0, -1, 0.3)), "curl": 1.0},
               "l": None},
    "rifle": {"hip": Vector((0.18, -0.2, -0.44)),
              "r": {"pos": Vector((0, 0.012, 0.0)), "fingers": Vector((0, -0.2, -1)), "knuckles": Vector((0, -1, 0.25)), "curl": 1.0},
              "l": {"pos": Vector((0, -0.03, -0.3)), "fingers": Vector((0.5, 0, -1)), "knuckles": Vector((-1, 0, -0.5)), "curl": 1.0,
                    # Off-screen cheat: shoulder moved toward the gun so the arm reaches the handguard.
                    "shoulder": Vector((0.2, -0.04, -0.3))}},
}
KNUCKLE_GAP = 0.024
CURL = (55.0, 75.0, 50.0)
FINGERS = ["index", "middle", "ring", "pinky"]


def g2b(v):
    return C @ v


def curl_fingers(arm, side, amount):
    for f in FINGERS:
        for j in range(3):
            pb = arm.pose.bones[f"finger_{f}{j + 1}.{side}"]
            pb.rotation_mode = "QUATERNION"
            a = CURL[j] * amount * (0.8 if f == "index" else 1.0)
            pb.rotation_quaternion = Quaternion((1, 0, 0), -math.radians(a))
    for j, a in enumerate((15.0, 25.0, 20.0)):
        pb = arm.pose.bones[f"finger_thumb{j + 1}.{side}"]
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion((1, 0, 0), -math.radians(a * amount))


def hand_frame(arm, side):
    """Rest-pose hand frame: F = wrist -> middle knuckle, A = index -> pinky knuckle line
    (orthogonalised), plus the palm direction P (where the curled fingertips go) and the knuckle
    centre relative to the wrist."""
    bones = arm.data.bones
    mw = arm.matrix_world
    w = mw @ bones[f"wrist.{side}"].head_local
    m = mw @ bones[f"finger_middle1.{side}"].head_local
    i = mw @ bones[f"finger_index1.{side}"].head_local
    p = mw @ bones[f"finger_pinky1.{side}"].head_local
    r = mw @ bones[f"finger_ring1.{side}"].head_local
    f = (m - w).normalized()
    a = p - i
    a = (a - f * a.dot(f)).normalized()
    tip_rest = mw @ bones[f"finger_middle3.{side}"].tail_local
    curl_fingers(arm, side, 1.0)
    bpy.context.view_layer.update()
    tip_curl = mw @ arm.pose.bones[f"finger_middle3.{side}"].tail
    c = tip_curl - tip_rest
    c = c - f * c.dot(f) - a * c.dot(a)
    print(f"  palm test {side}: curl moved tip {c.length * 100:.1f} cm")
    for f_ in FINGERS + ["thumb"]:
        for j in range(3):
            arm.pose.bones[f"finger_{f_}{j + 1}.{side}"].rotation_quaternion = Quaternion()
    basis = Matrix((f, a, f.cross(a))).transposed()
    return basis, (i + m + r + p) / 4 - w, c.normalized()


def _cut_to_hands(body, arm, keep_back=0.07):
    """Hands-only variant: drop arm geometry more than keep_back metres behind each wrist."""
    import bmesh
    names = {g.index: g.name for g in body.vertex_groups}
    wr = {sd: arm.matrix_world @ arm.data.bones[f"wrist.{sd}"].head_local for sd in ("r", "l")}
    fdir = {sd: (arm.matrix_world @ arm.data.bones[f"finger_middle1.{sd}"].head_local - wr[sd]).normalized() for sd in ("r", "l")}
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    dl = body.data.vertices
    kill = []
    for i, v in enumerate(dl):
        best = max(v.groups, key=lambda g: g.weight, default=None)
        n = names.get(best.group, "") if best else ""
        sd = n[-1] if n[-2:] in (".r", ".l") else None
        if sd is None:
            kill.append(bm.verts[i])
            continue
        if (body.matrix_world @ v.co - wr[sd]).dot(fdir[sd]) < -keep_back:
            kill.append(bm.verts[i])
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=0)
    bm.to_mesh(body.data)
    bm.free()


def _split_materials(body, drop_sides):
    """Gloves on the hands, sleeves on the arms (MaterialLib binds ArmGlove / ArmSuit to the
    fabric shader); arms with no grip on this weapon are removed."""
    import bmesh
    names = {g.index: g.name for g in body.vertex_groups}
    dom = []
    for v in body.data.vertices:
        best = max(v.groups, key=lambda g: g.weight, default=None)
        dom.append(names.get(best.group, "") if best else "")
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    kill = [bm.verts[i] for i, n in enumerate(dom) if any(n.endswith("." + sd) for sd in drop_sides)]
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    bm.to_mesh(body.data)
    bm.free()
    dom = []
    for v in body.data.vertices:
        best = max(v.groups, key=lambda g: g.weight, default=None)
        dom.append(names.get(best.group, "") if best else "")
    body.data.materials.clear()
    for n in ("ArmSuit", "ArmGlove"):
        m = bpy.data.materials.get(n) or bpy.data.materials.new(n)
        body.data.materials.append(m)
    for poly in body.data.polygons:
        hand = sum(1 for vi in poly.vertices if dom[vi].startswith(("wrist", "finger", "socket")))
        poly.material_index = 1 if hand * 2 >= len(poly.vertices) else 0


def build(weapon, hands_only=False):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=ARMS)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    body = next(o for o in bpy.data.objects if o.type == "MESH")
    spec = GUNS[weapon]
    hip = g2b(spec["hip"])
    _split_materials(body, [sd for sd in ("r", "l") if spec[sd] is None])
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")
    for side in ("r", "l"):
        g = spec[side]
        if g is None:
            # Hang the arm down out of view: rotate the bicep down and back.
            pb = arm.pose.bones[f"bicep.{side}"]
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = Quaternion((0, 0, 1), math.radians(70 if side == "l" else -70))
            continue
        if "shoulder" in g:
            pb = arm.pose.bones[f"shoulder.{side}"]
            pb.matrix = Matrix.Translation(g2b(g["shoulder"])) @ pb.matrix
            bpy.context.view_layer.update()
        basis, knuckle, palm = hand_frame(arm, side)
        f_t = g2b(g["fingers"]).normalized()
        a_t = g2b(g["knuckles"])
        a_t = (a_t - f_t * a_t.dot(f_t)).normalized()
        R = Matrix((f_t, a_t, f_t.cross(a_t))).transposed() @ basis.inverted()
        grip = hip + g2b(g["pos"])
        knuckle_t = grip - (R @ palm) * KNUCKLE_GAP
        wrist_t = knuckle_t - R @ knuckle
        wrest = (arm.matrix_world.to_3x3() @ arm.data.bones[f"wrist.{side}"].matrix_local.to_3x3())
        tgt = bpy.data.objects.new(f"tgt_{side}", None)
        bpy.context.scene.collection.objects.link(tgt)
        tgt.matrix_world = Matrix.Translation(wrist_t) @ (R @ wrest).to_4x4()
        pole = bpy.data.objects.new(f"pole_{side}", None)
        bpy.context.scene.collection.objects.link(pole)
        sx = 1 if side == "r" else -1
        pole.location = wrist_t + Vector((0.45 * sx, -0.25, -0.35))
        ik = arm.pose.bones[f"forearm.{side}"].constraints.new("IK")
        ik.target = tgt
        ik.pole_target = pole
        ik.pole_angle = math.radians(-90)
        ik.chain_count = 2
        cr = arm.pose.bones[f"wrist.{side}"].constraints.new("COPY_ROTATION")
        cr.target = tgt
        curl_fingers(arm, side, g["curl"])
    bpy.context.view_layer.update()
    bpy.ops.pose.select_all(action="SELECT")
    bpy.ops.pose.visual_transform_apply()
    for pb in arm.pose.bones:
        for c in list(pb.constraints):
            pb.constraints.remove(c)
    bpy.ops.object.mode_set(mode="OBJECT")
    # Report how close each wrist got.
    for side in ("r", "l"):
        t = bpy.data.objects.get(f"tgt_{side}")
        if t:
            got = arm.matrix_world @ arm.pose.bones[f"wrist.{side}"].head
            print(f"  {weapon}.{side}: wrist error {(got - t.matrix_world.translation).length * 100:.1f} cm")
    if hands_only:
        _cut_to_hands(body, arm)
    # Bake pose -> rest (mesh first, then skeleton), keep skinning.
    mod = next(m for m in body.modifiers if m.type == "ARMATURE")
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    m2 = body.modifiers.new("Armature", "ARMATURE")
    m2.object = arm
    for o in list(bpy.data.objects):
        if o.type == "EMPTY":
            bpy.data.objects.remove(o)
    arm.name = "Arms"
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    body.select_set(True)
    path = os.path.join(OUT, f"{'hands' if hands_only else 'arms'}_{weapon}.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_skins=True, export_animations=False, export_image_format="AUTO")
    print("exported", path)


for w in GUNS:
    build(w)
    build(w, hands_only=True)
