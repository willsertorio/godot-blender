"""First-person arms from Quaternius Universal Base Characters (CC0) -> assets/models/arms.glb.

    blender -b -P blender/scripts/build_arms.py -- assets_src/quaternius assets/models

Takes Superhero_Male_FullBody (UE-mannequin rig with full finger chains) and, per side:
  1. keeps only the forearm, hand and finger geometry (vertices whose strongest bone is
     lowerarm_* / hand_* / a finger bone), drops eyes, brows, the helper sphere
  2. shades it as kit: gloves on the hand (character normal map kept for knuckles and creases),
     a dark suit sleeve on the forearm, plus a cuff and a vambrace plate parented to the bones
  3. curls the fingers around a vertical grip and opposes the thumb, then bakes that pose in as
     the rest pose (bones stay, so the motion-design step can animate them)
  4. orients it for the view model: forearm toward +Y (barrel direction), palm facing the grip,
     origin at the centre of the closed fist (where the gun's grip goes)
Nodes: ArmR / ArmL (armature roots). Bones keep their UE names (hand_r, index_01_r, ...).
"""
import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Quaternion, Vector

args = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = args[0], args[1]
CHAR = os.path.join(SRC, "universal-base-characters", "Universal Base Characters[Standard]", "Base Characters",
                    "Godot - UE", "Superhero_Male_FullBody.gltf")
FINGERS = ["index", "middle", "ring", "pinky"]
# Curl per joint (degrees): knuckle, middle, tip. Pinky curls a touch more, index a touch less.
CURL = {"index": (62, 78, 50), "middle": (66, 82, 52), "ring": (70, 84, 52), "pinky": (74, 84, 50)}

COLORS = {
    "ArmGlove": ((0.018, 0.018, 0.02, 1), 0.0, 0.62),
    "ArmSuit": ((0.045, 0.05, 0.06, 1), 0.0, 0.85),
    "ArmPlate": ((0.07, 0.075, 0.085, 1), 0.5, 0.4),
    "ArmAccent": ((0.45, 0.16, 0.02, 1), 0.1, 0.55),
}


def material(name, normal_img=None):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    col, metal, rough = COLORS[name]
    bsdf.inputs["Base Color"].default_value = col
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = rough
    if normal_img is not None:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = normal_img
        tex.image.colorspace_settings.name = "Non-Color"
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(tex.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    return m


def cylinder(name, start, end, r0, r1, mat, segments=16):
    """Open-ended tapered tube from start to end (world space), as its own object."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    axis = (end - start)
    length = axis.length
    rot = axis.normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=r0, radius2=r1, depth=length,
                          matrix=Matrix.Translation((start + end) / 2) @ rot)
    for f in bm.faces:
        f.smooth = True
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    me.materials.append(mat)
    return ob


def box(name, centre, x_axis, y_axis, size, mat, bevel=0.01):
    """Bevelled box with its local axes given in world space."""
    z_axis = x_axis.cross(y_axis).normalized()
    basis = Matrix((x_axis.normalized(), y_axis.normalized(), z_axis)).transposed().to_4x4()
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation(centre) @ basis @ Matrix.Diagonal((*size, 1)))
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    me.materials.append(mat)
    m = ob.modifiers.new("Bevel", "BEVEL")
    m.width = bevel
    m.segments = 3
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.ops.object.modifier_apply(modifier="Bevel")
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def parent_to_bone(ob, arm, bone):
    mw = ob.matrix_world.copy()
    ob.parent = arm
    ob.parent_type = "BONE"
    ob.parent_bone = bone
    ob.matrix_world = mw


def build_side(s):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=CHAR)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    body = next(o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith("SuperHero"))
    for o in list(bpy.data.objects):
        if o not in (arm, body):
            bpy.data.objects.remove(o)
    normal_img = next((i for i in bpy.data.images if "Superhero_Male_Normal" in i.name), None)
    if normal_img is not None:
        normal_img.filepath_raw = bpy.path.abspath(normal_img.filepath)

    keep = {f"lowerarm_{s}", f"hand_{s}"} | {b.name for b in arm.data.bones
                                             if b.name.endswith("_" + s) and b.name.split("_")[0] in FINGERS + ["thumb"]}
    hand_bones = keep - {f"lowerarm_{s}"}
    names = {g.index: g.name for g in body.vertex_groups}
    dominant = []
    for v in body.data.vertices:
        best = max(v.groups, key=lambda g: g.weight, default=None)
        dominant.append(names.get(best.group) if best else None)

    # 1. cut
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    # Keep only the last ~18 cm of forearm: the view model never needs the elbow, and a long
    # sleeve runs straight into the lens when aiming.
    wrist0 = arm.matrix_world @ arm.data.bones[f"hand_{s}"].head_local
    far = [i for i, v in enumerate(bm.verts) if dominant[i] == f"lowerarm_{s}"
           and (body.matrix_world @ v.co - wrist0).length > 0.16]
    bmesh.ops.delete(bm, geom=[bm.verts[i] for i, n in enumerate(dominant) if n not in keep or i in set(far)], context="VERTS")
    # Close the cut end of the sleeve.
    bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=0)
    bm.to_mesh(body.data)
    bm.free()
    # 2. gloves / sleeve
    body.data.materials.clear()
    body.data.materials.append(material("ArmSuit", normal_img))
    body.data.materials.append(material("ArmGlove", normal_img))
    dominant = []
    for v in body.data.vertices:
        best = max(v.groups, key=lambda g: g.weight, default=None)
        dominant.append(names.get(best.group) if best else None)
    for p in body.data.polygons:
        n_hand = sum(1 for vi in p.vertices if dominant[vi] in hand_bones)
        p.material_index = 1 if n_hand * 2 >= len(p.vertices) else 0

    # 3. grip pose. Rest pose: arms out along -X (right) / +X (left), palms down (-Z).
    fdir = Vector((-1, 0, 0)) if s == "r" else Vector((1, 0, 0))
    curl_axis = fdir.cross(Vector((0, 0, -1)))  # rotating fingers about this moves them toward the palm
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")
    aw = arm.matrix_world.to_3x3()

    def rotate(bone, world_axis, deg):
        pb = arm.pose.bones[bone]
        pb.rotation_mode = "QUATERNION"
        local_axis = (aw @ pb.bone.matrix_local.to_3x3()).inverted() @ world_axis
        pb.rotation_quaternion = Quaternion(local_axis.normalized(), math.radians(deg)) @ pb.rotation_quaternion

    for f in FINGERS:
        for seg, deg in zip(("01", "02", "03"), CURL[f]):
            rotate(f"{f}_{seg}_{s}", curl_axis, deg)
    # Thumb: swing under the palm toward the fingers (about the forearm axis), then curl its tip.
    # (Rotating about the forearm axis by a negative angle (right hand) swings the thumb
    # toward the palm side, across the grip; positive would lift it into a thumbs-up.)
    k = -1 if s == "r" else 1
    rotate(f"thumb_01_{s}", fdir, 52 * k)
    rotate(f"thumb_02_{s}", fdir, 30 * k)
    rotate(f"thumb_03_{s}", fdir, 22 * k)
    # Wrist: tilt the hand 35 deg toward the grip's top (about the palm normal). Once the hand is
    # aligned with the gun, this drops the forearm down toward the bottom of the screen.
    rotate(f"hand_{s}", Vector((0, 0, 1)), -60 if s == "r" else 60)
    bpy.context.view_layer.update()

    # Bake: posed mesh, posed skeleton becomes the rest pose.
    bpy.ops.object.mode_set(mode="OBJECT")
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

    # Fist centre: middle of the curled middle finger and the thumb tip.
    def head(b):
        return arm.matrix_world @ arm.data.bones[b].head_local
    def tail(b):
        return arm.matrix_world @ arm.data.bones[b].tail_local
    ring_pts = [head(f"middle_01_{s}"), head(f"middle_02_{s}"), head(f"middle_03_{s}"), tail(f"middle_03_{s}"),
                head(f"index_02_{s}"), head(f"ring_02_{s}")]
    fist = sum(ring_pts, Vector()) / len(ring_pts)

    # 4. armour, in posed world space, parented to bones
    wrist = head(f"hand_{s}")
    elbow = head(f"lowerarm_{s}")
    fore = (wrist - elbow).normalized()
    back = Vector((0, 0, 1))  # back of the hand (palms were down)
    side = fore.cross(back).normalized()
    cuff = cylinder("Cuff", wrist - fore * 0.055, wrist + fore * 0.005, 0.047, 0.044, material("ArmAccent"))
    cuff2 = cylinder("CuffBand", wrist - fore * 0.075, wrist - fore * 0.05, 0.05, 0.05, material("ArmPlate"))
    plate = box("Vambrace", wrist - fore * 0.12 + back * 0.04, fore, side,
                Vector((0.1, 0.065, 0.02)), material("ArmPlate"), bevel=0.008)
    stripe = box("VambraceStripe", wrist - fore * 0.12 + back * 0.051, fore, side,
                 Vector((0.08, 0.012, 0.004)), material("ArmAccent"), bevel=0.0015)
    for o in (cuff, cuff2):
        parent_to_bone(o, arm, f"hand_{s}")
    for o in (plate, stripe):
        parent_to_bone(o, arm, f"lowerarm_{s}")

    # 5. view-model orientation: hand -> +Y, palm (-Z) -> faces the grip (-X right / +X left).
    hand_dir = (head(f"middle_01_{s}") - head(f"hand_{s}")).normalized()
    hand_dir = (hand_dir - hand_dir.project(Vector((0, 0, 1)))).normalized()  # keep it in the palm plane
    a1, a2 = hand_dir, Vector((0, 0, -1))
    b1, b2 = Vector((0, 1, 0)), Vector((-1, 0, 0)) if s == "r" else Vector((1, 0, 0))
    A = Matrix((a1, a2, a1.cross(a2))).transposed()
    B = Matrix((b1, b2, b1.cross(b2))).transposed()
    R = (B @ A.inverted()).to_4x4()
    arm.matrix_world = Matrix.Translation(-(R @ fist)) @ R @ arm.matrix_world
    arm.name = "ArmR" if s == "r" else "ArmL"
    bpy.context.view_layer.update()
    print(f"  {arm.name}: verts {len(body.data.vertices)}")
    return arm


def export(path, root):
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for c in root.children_recursive:
        c.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=False, export_skins=True, export_animations=False,
                              export_image_format="JPEG", export_jpeg_quality=90)
    print("exported", path)


os.makedirs(OUT, exist_ok=True)
for side in ("r", "l"):
    a = build_side(side)
    export(os.path.join(OUT, f"arm_{side}.glb"), a)
