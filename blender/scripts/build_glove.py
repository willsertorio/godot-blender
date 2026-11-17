"""HG-7 armored glove + sleeve, modelled and rigged from scratch after blender/reference/glove_concept.png
-> blender/glove.blend (right + left hand, rest pose, reference image behind the right hand).

    blender -b -P blender/scripts/build_glove.py

Traced from the sheet's back-of-hand view (image px), thickness from its side view. Scale: 0.68 mm per
pixel (wrist -> middle fingertip 16.6 cm, palm 9.5 cm): the sheet's hand is chunky, and this keeps the
fingers able to close around the XM9's short grip.

Hand frame (right hand): wrist centre at the origin, fingers +Y, back of the hand +Z, palm -Z, thumb -X.
The left hand is the mirror (thumb +X).
Parts: fabric glove (hand body + 3 rounded segments per finger / thumb, overlapping at the joints so a
bend never opens a gap), grey hard-shell plates (back plate, knuckle hexes, lower guard, finger and thumb
plates), cuff with two cyan glow rings, and the sleeved arm: forearm, padded elbow, upper arm (~60 cm in
all, so the arm always runs off-screen instead of ending in a cut).
Rig "Glove.R" / "Glove.L": upperarm -> forearm -> hand -> <finger>1..3 and thumb1..3 (the pose scripts aim the
upper arm at the player's shoulder with a two-bone solve). Rigid skinning: every vertex
belongs 100 % to one bone, so plates never bend. Finger bones are rolled so that curling toward the palm
is a positive rotation about the bone's X axis (thumb: toward the palm / index).
Materials: GloveFabric, GlovePlate, GloveCuff, NeonCyan, ArmSuit.
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "blender", "glove.blend")
REF = os.path.join(ROOT, "blender", "reference", "glove_concept.png")

K = 0.00068          # metres per image pixel
WRIST = (359, 305)   # wrist centre in the back-of-hand view (image px)
FOREARM = 0.26   # wrist -> elbow
UPPER = 0.32     # elbow -> shoulder

MATS = {
    "GloveFabric": dict(color=(0.07, 0.075, 0.08), metallic=0.0, rough=0.85),
    "GlovePlate": dict(color=(0.33, 0.35, 0.37), metallic=0.3, rough=0.45),
    "GloveCuff": dict(color=(0.045, 0.047, 0.05), metallic=0.1, rough=0.7),
    "ArmSuit": dict(color=(0.085, 0.09, 0.11), metallic=0.0, rough=0.9),
    "NeonCyan": dict(color=(0x22 / 255, 0xE5 / 255, 1.0), emit=8.0),
}

# Fingers: base (knuckle) and tip in the back view, width (px); segment split of base->tip.
FINGERS = {
    "index": ((300, 180), 76, 30),
    "middle": ((346, 176), 61, 32),
    "ring": ((392, 178), 72, 30),
    "pinky": ((430, 188), 104, 26),
}
SPLIT = (0.45, 0.30, 0.25)
THUMB = [(300, 282), (272, 238), (253, 205), (238, 178)]  # CMC, MCP, IP, tip
THUMB_W = (36, 29, 26)
FINGER_T = 0.019     # finger thickness (m)
FINGER_Z = -0.002    # finger centre height
BODY_Z = (-0.019, 0.014)


def mat(name):
    m = bpy.data.materials.get(name)
    if m:
        return m
    s = MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    if "emit" in s:
        b.inputs["Base Color"].default_value = (0, 0, 0, 1)
        b.inputs["Emission Color"].default_value = (*s["color"], 1)
        b.inputs["Emission Strength"].default_value = s["emit"]
    else:
        b.inputs["Base Color"].default_value = (*s["color"], 1)
        b.inputs["Metallic"].default_value = s["metallic"]
        b.inputs["Roughness"].default_value = s["rough"]
    m.diffuse_color = (*s["color"], 1)
    return m


class Hand:
    def __init__(self, side):
        self.side = side            # "R" / "L"
        self.sx = 1 if side == "R" else -1
        self.parts = []             # (object, bone)

    def P(self, x, y, z=0.0):
        """Back-view image px -> hand frame (m)."""
        return Vector(((WRIST[0] - x) * K * -self.sx, (WRIST[1] - y) * K, z))

    # ---- geometry helpers (each returns an object that is later joined) ----------------------------
    def _obj(self, name, bm, material, bone, bevel=0.0, segs=3, limit="ANGLE"):
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        me.materials.append(mat(material))
        if bevel > 0:
            bv = ob.modifiers.new("Bevel", "BEVEL")
            bv.width = bevel
            bv.segments = segs
            bv.limit_method = limit
            bv.angle_limit = math.radians(40)
        bpy.context.view_layer.objects.active = ob
        for o in bpy.context.selected_objects:
            o.select_set(False)
        ob.select_set(True)
        for m in list(ob.modifiers):
            bpy.ops.object.modifier_apply(modifier=m.name)
        for p in me.polygons:
            p.use_smooth = True
        self.parts.append((ob, bone))
        return ob

    def prism(self, name, pts, z0, z1, material, bone, bevel=0.002, segs=2):
        bm = bmesh.new()
        f = bm.faces.new([bm.verts.new(self.P(x, y, z0)) for x, y in pts])
        ext = bmesh.ops.extrude_face_region(bm, geom=[f])
        bmesh.ops.translate(bm, vec=Vector((0, 0, z1 - z0)),
                            verts=[e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)])
        return self._obj(name, bm, material, bone, bevel, segs)

    def rbox(self, name, a, b, width, thick, material, bone, up=Vector((0, 0, 1)), ext0=0.0, ext1=0.0,
             round_=0.45, offset=Vector()):
        """Rounded box from a to b (extended by ext0 / ext1), width across, thickness along `up`."""
        d = (b - a).normalized()
        a2, b2 = a - d * ext0, b + d * ext1
        x = d.cross(up).normalized()
        z = x.cross(d).normalized()
        m = Matrix((x, d, z)).transposed().to_4x4()
        m.translation = (a2 + b2) / 2 + offset
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0, matrix=m @ Matrix.Diagonal((width, (b2 - a2).length, thick, 1)))
        return self._obj(name, bm, material, bone, bevel=min(width, thick) * round_, segs=3, limit="NONE")

    def tube(self, name, y0, y1, r0, r1, z, material, bone, segs=24, cap=True, bevel=0.0):
        """Elliptic tube along -Y (cuff / sleeve): radii (x, z) from y0 to y1."""
        bm = bmesh.new()
        rings = []
        for y, (rx, rz) in ((y0, r0), (y1, r1)):
            rings.append([bm.verts.new((rx * math.cos(2 * math.pi * i / segs), y, z + rz * math.sin(2 * math.pi * i / segs)))
                          for i in range(segs)])
        for i in range(segs):
            j = (i + 1) % segs
            bm.faces.new([rings[0][i], rings[0][j], rings[1][j], rings[1][i]])
        if cap:
            bm.faces.new(rings[0][::-1])
            bm.faces.new(rings[1])
        return self._obj(name, bm, material, bone, bevel=bevel, segs=2)

    # ---- the glove ---------------------------------------------------------------------------------
    def build(self):
        s = self.side
        z0, z1 = BODY_Z
        self.prism(f"Body.{s}", [(303, 305), (296, 290), (292, 250), (292, 205), (296, 185), (310, 176), (330, 172),
                                 (362, 170), (380, 172), (410, 175), (426, 184), (432, 200), (430, 245), (424, 285),
                                 (417, 305)], z0, z1, "GloveFabric", "hand", bevel=0.0085, segs=4)
        # Plates on the back of the hand.
        self.prism(f"BackPlate.{s}", [(300, 194), (318, 184), (412, 184), (428, 196), (426, 236), (410, 246),
                                      (318, 246), (300, 236)], z1 - 0.003, z1 + 0.004, "GlovePlate", "hand", 0.0022)
        self.prism(f"LowerGuard.{s}", [(320, 256), (402, 256), (410, 276), (400, 297), (324, 297), (314, 276)],
                   z1 - 0.004, z1 + 0.003, "GlovePlate", "hand", 0.0022)
        self.bones = {"upperarm": (Vector((0, -FOREARM - UPPER, FINGER_Z)), Vector((0, -FOREARM, FINGER_Z)), Vector((0, 0, -1))),
                      "forearm": (Vector((0, -FOREARM, FINGER_Z)), Vector((0, 0, FINGER_Z)), Vector((0, 0, -1)))}
        mid = self.P(*FINGERS["middle"][0], FINGER_Z)
        self.bones["hand"] = (Vector((0, 0, FINGER_Z)), mid, Vector((0, 0, -1)))
        for f, ((bx, by), tip_y, w) in FINGERS.items():
            base, tip = self.P(bx, by, FINGER_Z), self.P(bx, tip_y, FINGER_Z)
            wm = w * K
            hx = self.prism(f"Knuckle_{f}.{s}", [(bx - w * 0.42, by + 6), (bx - w * 0.3, by - 4), (bx + w * 0.3, by - 4),
                                                 (bx + w * 0.42, by + 6), (bx + w * 0.3, by + 15), (bx - w * 0.3, by + 15)],
                            z1 - 0.002, z1 + 0.006, "GlovePlate", "hand", 0.0018)
            joints = [base]
            acc = 0.0
            for frac in SPLIT:
                acc += frac
                joints.append(base.lerp(tip, acc))
            for j in range(3):
                a, b = joints[j], joints[j + 1]
                bone = f"{f}{j + 1}"
                taper = 1.0 - 0.07 * j
                self.rbox(f"{bone}.{s}", a, b, wm * taper, FINGER_T * taper, "GloveFabric", bone,
                          ext0=wm * 0.32, ext1=wm * (0.32 if j < 2 else 0.05))
                if j < 2:  # plates on the proximal + middle segments
                    seg = (b - a)
                    pa, pb = a + seg * 0.18, b - seg * 0.18
                    self.rbox(f"{bone}Plate.{s}", pa, pb, wm * 0.72 * taper, 0.005, "GlovePlate", bone,
                              offset=Vector((0, 0, FINGER_T * taper * 0.5 + 0.0012)), round_=0.35)
                self.bones[bone] = (a, b, Vector((0, 0, -1)))
        # Thumb: angled, sits toward the palm, its back faces out (-X, +Z for the right hand).
        th = [self.P(x, y, -0.006) for x, y in THUMB]
        out = Vector((-0.7 * self.sx, 0, 0.7)).normalized()
        flex = Vector((0.7 * self.sx, 0, -0.7)).normalized()
        for j in range(3):
            a, b = th[j], th[j + 1]
            w = THUMB_W[j] * K
            bone = f"thumb{j + 1}"
            self.rbox(f"{bone}.{s}", a, b, w, w * 0.85, "GloveFabric", bone, up=out,
                      ext0=w * (0.15 if j == 0 else 0.3), ext1=w * (0.3 if j < 2 else 0.05))
            if j < 2:
                seg = b - a
                self.rbox(f"{bone}Plate.{s}", a + seg * 0.2, b - seg * 0.2, w * 0.7, 0.005, "GlovePlate", bone, up=out,
                          offset=out * (w * 0.85 * 0.5 + 0.0012), round_=0.35)
            self.bones[bone] = (a, b, flex)
        # Cuff with two cyan glow rings, then the sleeve to mid-forearm.
        self.tube(f"Cuff.{s}", 0.006, -0.034, (0.041, 0.026), (0.042, 0.027), FINGER_Z, "GloveCuff", "forearm", bevel=0.003)
        for i, y in enumerate((-0.006, -0.026)):
            self.tube(f"CuffGlow{i}.{s}", y + 0.0012, y - 0.0012, (0.0422, 0.0272), (0.0422, 0.0272), FINGER_Z,
                      "NeonCyan", "forearm", cap=False)
        self.tube(f"Sleeve.{s}", -0.028, -FOREARM - 0.03, (0.038, 0.024), (0.046, 0.034), FINGER_Z, "ArmSuit",
                  "forearm", segs=20)
        # Padded elbow (moves with the upper arm; the forearm tube ends inside it, so a bend never opens a gap)
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=1.0,
                                  matrix=Matrix.Translation((0, -FOREARM, FINGER_Z)) @ Matrix.Diagonal((0.05, 0.05, 0.042, 1)))
        self._obj(f"Elbow.{s}", bm, "ArmSuit", "upperarm")
        self.tube(f"UpperArm.{s}", -FOREARM - 0.01, -FOREARM - UPPER, (0.047, 0.038), (0.056, 0.047), FINGER_Z, "ArmSuit",
                  "upperarm", segs=20)

    def rig(self):
        s = self.side
        arm = bpy.data.armatures.new(f"Glove.{s}")
        ob = bpy.data.objects.new(f"Glove.{s}", arm)
        bpy.context.scene.collection.objects.link(ob)
        bpy.context.view_layer.objects.active = ob
        for o in bpy.context.selected_objects:
            o.select_set(False)
        ob.select_set(True)
        bpy.ops.object.mode_set(mode="EDIT")
        eb = {}
        for name, (h, t, roll_to) in self.bones.items():
            b = arm.edit_bones.new(name)
            b.head, b.tail = h, t
            b.align_roll(roll_to)
            eb[name] = b
        eb["forearm"].parent = eb["upperarm"]
        eb["hand"].parent = eb["forearm"]
        for f in list(FINGERS) + ["thumb"]:
            eb[f"{f}1"].parent = eb["hand"]
            eb[f"{f}2"].parent = eb[f"{f}1"]
            eb[f"{f}3"].parent = eb[f"{f}2"]
            eb[f"{f}2"].use_connect = eb[f"{f}3"].use_connect = False
        bpy.ops.object.mode_set(mode="OBJECT")
        arm.display_type = "STICK"
        # Rigid skinning, then one mesh.
        for p, bone in self.parts:
            vg = p.vertex_groups.new(name=bone)
            vg.add(list(range(len(p.data.vertices))), 1.0, "REPLACE")
        for o in bpy.context.selected_objects:
            o.select_set(False)
        for p, _ in self.parts:
            p.select_set(True)
        body = self.parts[0][0]
        bpy.context.view_layer.objects.active = body
        bpy.ops.object.join()
        body.name = body.data.name = f"GloveMesh.{s}"
        body.parent = ob
        mod = body.modifiers.new("Armature", "ARMATURE")
        mod.object = ob
        wn = body.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL")
        wn.keep_sharp = True
        return ob


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = "METRIC"
    sc.render.fps = 30
    rigs = []
    for side, x in (("R", 0.0), ("L", -0.16)):
        h = Hand(side)
        h.build()
        rig = h.rig()
        rig.location.x = x
        rigs.append(rig)
    # Reference behind the right hand (top view = back of the hand), for checking the trace.
    img = bpy.data.images.load(REF)
    ref = bpy.data.objects.new("Reference", None)
    ref.empty_display_type = "IMAGE"
    ref.data = img
    w = img.size[0] * K
    ref.empty_display_size = w
    ref.empty_image_offset = (-0.5, -0.5)
    ref.location = Vector(((img.size[0] / 2 - WRIST[0]) * K, (WRIST[1] - img.size[1] / 2) * K, -0.05))
    ref.color[3] = 0.5
    rc = bpy.data.collections.new("Reference")
    sc.collection.children.link(rc)
    rc.objects.link(ref)
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(35), math.radians(-20), math.radians(30))
    sc.collection.objects.link(sun)
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.4, 0.42, 0.46, 1)
    sc.world = world
    bpy.ops.wm.save_as_mainfile(filepath=OUT)
    print("saved", OUT)


build()
