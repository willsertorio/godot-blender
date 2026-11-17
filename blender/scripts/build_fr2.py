"""FR-2 flying recon drone, modelled from scratch after blender/reference/drone_concept.png -> blender/fr2.blend.

    blender -b -P blender/scripts/build_fr2.py

Traced from the concept's front view (X / Z, 2.57 mm per image px: 1.3 m across the rotor rings) and side
view (length 2.6 mm/px along Y; heights fitted to the front view: 3.23 mm/px, the sheet draws its views at
different scales). The hull is the intersection of the side-profile prism and the front-profile prism (a
live Boolean INTERSECT), so it matches both views; vents and panel details are live cutters / plates.

Frame: origin at the chassis centre of mass, Z up, the optical sensor (eye) facing +Y.
Hierarchy (pivot = object origin):
  FR2 (empty, root: Godot moves this)
    Chassis           armored core, origin at the centre (body motion of every clip is keyed here)
      Eye             optical sensing unit (dark housing), pivot at the lens centre
        EyeLens       red lens, material NeonRed (Godot's neon shader drives the glow)
      RearVent        rear propulsion vent block
      RotorArmL / R   static struts from the hull to the rings
      RotorL / R      ring housings, pivot at the ring centre; rest tilt 45 deg forward about X
        PropL / R     4-blade propellers + hub, spin about the ring axis (local Z)
      GunL / R        under-barrel rotary gun housings (static)
        GunBarrelsL/R six-barrel clusters, spin about the barrel axis (local Y)
          Muzzle_L/R  empties at the barrel tips (MuzzleFlashL / R hang under them, see anim_fr2.py)
      EyeMarker       empty at the lens centre
Materials (flat colours from the sheet): DroneArmor, DroneArmorLight, DroneDark, DroneMetal, NeonRed.
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "blender", "fr2.blend")
REF = os.path.join(ROOT, "blender", "reference", "drone_concept.png")

KF = 0.00257                 # front view: metres per px (X, Z)
FRONT_C = (303, 290)         # front view: body centre line x, chassis centre y
KS_Y = 0.0026                # side view: metres per px along the length
SIDE_CX = 900                # side view: x of the centre of mass
SIDE_Z0, SIDE_Y0, SIDE_KZ = 0.249, 205, 0.00323   # side view heights: Z = SIDE_Z0 - (y - SIDE_Y0) * SIDE_KZ
ROTOR_TILT = math.radians(-45)   # ring axis tipped 45 deg forward (+Y) from vertical

MATS = {
    "DroneArmor": dict(color=(0.40, 0.40, 0.36), metallic=0.25, rough=0.55),
    "DroneArmorLight": dict(color=(0.55, 0.55, 0.50), metallic=0.2, rough=0.5),
    "DroneDark": dict(color=(0.10, 0.10, 0.10), metallic=0.3, rough=0.6),
    "DroneMetal": dict(color=(0.24, 0.24, 0.25), metallic=0.85, rough=0.35),
    "NeonRed": dict(color=(1.0, 0x2D / 255, 0x55 / 255), emit=8.0),
}


def F(x, y):
    """Front-view px -> (X, Z)."""
    return ((x - FRONT_C[0]) * KF, (FRONT_C[1] - y) * KF)


def S(x, y):
    """Side-view px -> (Y, Z) (nose to the left in the sheet = +Y)."""
    return ((SIDE_CX - x) * KS_Y, SIDE_Z0 - (y - SIDE_Y0) * SIDE_KZ)


def mat(name):
    m = bpy.data.materials.get(name)
    if m:
        return m
    s = MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    if "emit" in s:
        b.inputs["Base Color"].default_value = (*s["color"], 1)
        b.inputs["Emission Color"].default_value = (*s["color"], 1)
        b.inputs["Emission Strength"].default_value = s["emit"]
    else:
        b.inputs["Base Color"].default_value = (*s["color"], 1)
        b.inputs["Metallic"].default_value = s["metallic"]
        b.inputs["Roughness"].default_value = s["rough"]
    m.diffuse_color = (*s["color"], 1)
    return m


def coll(name, hidden=False):
    c = bpy.data.collections.get(name)
    if not c:
        c = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(c)
        if hidden:
            c.hide_viewport = True
            c.hide_render = True
    return c


def obj(name, bm, material, parent=None, pivot=None, bevel=0.004, segs=2, collection="FR2"):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    coll(collection).objects.link(ob)
    me.materials.append(mat(material))
    if pivot is not None:
        me.transform(Matrix.Translation(-Vector(pivot)))
        ob.location = pivot
    if bevel > 0:
        bv = ob.modifiers.new("Bevel", "BEVEL")
        bv.width = bevel
        bv.segments = segs
        bv.limit_method = "ANGLE"
        bv.angle_limit = math.radians(35)
        bv.harden_normals = True
    for p in me.polygons:
        p.use_smooth = True
    if parent is not None:
        parent_keep(ob, parent)
    return ob


def parent_keep(ob, parent):
    bpy.context.view_layer.update()
    mw = ob.matrix_world.copy()
    ob.parent = parent
    ob.matrix_world = mw


def prism_side(name, pts, x0, x1, material, **kw):
    """Side-view profile (px) extruded across X from x0 to x1 (m)."""
    bm = bmesh.new()
    vs = [bm.verts.new((x0, *S(x, y))) for x, y in pts]
    f = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    bmesh.ops.translate(bm, vec=(x1 - x0, 0, 0), verts=[e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)])
    return obj(name, bm, material, **kw)


def prism_front(name, pts, y0, y1, material, dx=0.0, **kw):
    """Front-view profile (px) extruded along Y from y0 to y1 (m)."""
    bm = bmesh.new()
    vs = []
    for x, y in pts:
        X, Z = F(x, y)
        vs.append(bm.verts.new((X + dx, y0, Z)))
    f = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    bmesh.ops.translate(bm, vec=(0, y1 - y0, 0), verts=[e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)])
    return obj(name, bm, material, **kw)


def box(name, lo, hi, material, rot=None, **kw):
    bm = bmesh.new()
    lo, hi = Vector(lo), Vector(hi)
    r = Matrix.Identity(4) if rot is None else rot.to_4x4()
    bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((lo + hi) / 2) @ r @ Matrix.Diagonal((*(hi - lo), 1)))
    return obj(name, bm, material, **kw)


def cyl(name, a, b, r, material, segs=24, r2=None, **kw):
    a, b = Vector(a), Vector(b)
    bm = bmesh.new()
    d = b - a
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r if r2 is None else r2,
                          depth=d.length, matrix=Matrix.Translation((a + b) / 2) @ rot)
    return obj(name, bm, material, **kw)


def ring(name, ro, ri, depth, material, m, segs=40, **kw):
    """Annulus (outer ro, inner ri, axial depth) in a frame m (axis = m's Z)."""
    bm = bmesh.new()
    loops = []
    for r, z in ((ro, -depth / 2), (ro, depth / 2), (ri, depth / 2), (ri, -depth / 2)):
        loops.append([bm.verts.new(m @ Vector((r * math.cos(2 * math.pi * i / segs), r * math.sin(2 * math.pi * i / segs), z)))
                      for i in range(segs)])
    for k in range(4):
        a, b = loops[k], loops[(k + 1) % 4]
        for i in range(segs):
            j = (i + 1) % segs
            bm.faces.new([a[i], a[j], b[j], b[i]])
    return obj(name, bm, material, **kw)


def cut(target, cutter, op="DIFFERENCE"):
    for c in list(cutter.users_collection):
        c.objects.unlink(cutter)
    coll("Cutters", hidden=True).objects.link(cutter)
    cutter.display_type = "WIRE"
    parent_keep(cutter, target)
    bo = target.modifiers.new(f"{op.title()}_{cutter.name}", "BOOLEAN")
    bo.object = cutter
    bo.operation = op
    bo.solver = "EXACT"
    # keep the bevel after the booleans
    bev = target.modifiers.get("Bevel")
    if bev:
        bpy.context.view_layer.objects.active = target
        while target.modifiers[-1] != bev:
            bpy.ops.object.modifier_move_down(modifier=bev.name)
    return bo


def empty(name, loc, parent, size=0.03):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = size
    e.empty_display_type = "ARROWS"
    coll("FR2").objects.link(e)
    e.location = loc
    if parent is not None:
        parent_keep(e, parent)
    return e


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = "METRIC"
    sc.render.fps = 30
    root = bpy.data.objects.new("FR2", None)
    root.empty_display_size = 0.3
    coll("FR2").objects.link(root)

    # ---- Chassis: side profile ∩ front profile ---------------------------------------------------------
    side = [(712, 276), (722, 268), (800, 236), (848, 205), (995, 208), (1001, 224), (1075, 235), (1088, 250),
            (1088, 340), (1030, 352), (870, 368), (760, 366), (722, 352), (712, 330)]
    chassis = prism_side("Chassis", side, -0.3, 0.3, "DroneArmor", parent=root, pivot=Vector(), bevel=0.012, segs=3)
    front = [(232, 203), (250, 193), (358, 193), (380, 203), (388, 250), (386, 330), (372, 350), (346, 353),
             (343, 398), (282, 398), (279, 353), (238, 350), (222, 330), (220, 250)]
    cut(chassis, prism_front("HullFront", front, -0.7, 0.7, "DroneArmor", bevel=0), op="INTERSECT")
    # Side vents (slatted recesses on the front corners) and a top intake slot.
    for sx in (-1, 1):
        x0 = 241 if sx < 0 else 345
        v = prism_front(f"VentCut{'LR'[sx > 0]}", [(x0, 298), (x0 + 25, 298), (x0 + 25, 340), (x0, 340)], 0.30, 0.62,
                        "DroneDark", bevel=0)
        cut(chassis, v)
        for k in range(4):
            yk = 304 + k * 9
            X0, Z0 = F(x0 + 1, yk)
            X1, Z1 = F(x0 + 24, yk + 3)
            box(f"VentSlat{'LR'[sx > 0]}{k}", (min(X0, X1), 0.33, min(Z0, Z1)), (max(X0, X1), 0.45, max(Z0, Z1)),
                "DroneDark", parent=chassis, bevel=0.001)
    cut(chassis, prism_front("IntakeCut", [(270, 226), (343, 226), (343, 234), (270, 234)], 0.0, 0.7, "DroneDark", bevel=0))
    nose_y = S(712, 300)[0]

    # ---- Eye: dark housing + red lens -----------------------------------------------------------------------
    ex, ez = F(305, 300)
    eye_c = Vector((ex, nose_y + 0.035, ez))
    eye = prism_front("Eye", [(281, 280), (334, 280), (338, 290), (338, 352), (330, 358), (285, 358), (277, 352),
                              (277, 290)], nose_y - 0.03, nose_y + 0.03, "DroneDark", parent=chassis, pivot=eye_c,
                      bevel=0.004)
    cyl("EyeLens", eye_c + Vector((0, -0.01, 0)), eye_c + Vector((0, 0.012, 0)), 17 * KF, "NeonRed", segs=32,
        parent=eye, bevel=0.003)
    cyl("EyeRim", eye_c + Vector((0, -0.006, 0)), eye_c + Vector((0, 0.006, 0)), 20 * KF, "DroneMetal", segs=32,
        parent=eye, bevel=0.002)
    lx, lz = F(305, 335)
    box("EyeSlot", (lx - 0.045, nose_y + 0.02, lz - 0.012), (lx + 0.045, nose_y + 0.034, lz + 0.012), "DroneMetal",
        parent=eye, bevel=0.002)
    empty("EyeMarker", eye_c + Vector((0, 0.012, 0)), chassis)

    # ---- Rear vent ------------------------------------------------------------------------------------------
    vy0, _ = S(1088, 300)
    vy1, _ = S(1105, 300)
    _, vz0 = S(0, 340)
    _, vz1 = S(0, 262)
    vent = box("RearVent", (-0.12, vy1, vz0), (0.12, vy0 + 0.02, vz1), "DroneDark", parent=chassis, bevel=0.008)
    for k in range(5):
        z = vz0 + (vz1 - vz0) * (k + 0.5) / 5
        box(f"RearVentSlat{k}", (-0.11, vy1 - 0.012, z - 0.006), (0.11, vy1 + 0.002, z + 0.006), "DroneMetal",
            parent=vent, bevel=0.001)

    # ---- Rotors (rings tilt about X at their centre), props spin about the ring axis -------------------------
    for sx in (-1, 1):
        sd = "LR"[sx > 0]
        rx, rz = F(303 + sx * 171, 213)
        centre = Vector((rx, -0.1, rz))
        tilt = Matrix.Rotation(ROTOR_TILT, 4, "X")
        arm_from = Vector((sx * 0.19, -0.1, rz))
        box(f"RotorArm{sd}", (min(arm_from.x, centre.x - sx * 0.19), -0.13, rz - 0.022),
            (max(arm_from.x, centre.x - sx * 0.19), -0.07, rz + 0.022), "DroneMetal", parent=chassis, bevel=0.006)
        rot_ob = ring(f"Rotor{sd}", 0.215, 0.178, 0.065, "DroneArmor", Matrix.Translation(centre) @ tilt,
                      parent=chassis, pivot=centre, bevel=0.006)
        # motor spoke from the arm side of the rim to the hub
        spoke_m = Matrix.Translation(centre) @ tilt
        a = spoke_m @ Vector((-sx * 0.18, 0, -0.012))
        b = spoke_m @ Vector((0, 0, -0.012))
        cyl(f"RotorSpoke{sd}", a, b, 0.011, "DroneMetal", segs=10, parent=rot_ob, bevel=0.002)
        cyl(f"RotorMotor{sd}", spoke_m @ Vector((0, 0, -0.035)), spoke_m @ Vector((0, 0, -0.005)), 0.03, "DroneDark",
            segs=20, parent=rot_ob, bevel=0.003)
        # propeller: hub cone + 4 pitched blades, in the ring frame
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=20, radius1=0.028, radius2=0.004, depth=0.06,
                              matrix=Matrix.Translation((0, 0, 0.022)))
        for k in range(4):
            ang = k * math.pi / 2
            blade = (Matrix.Rotation(ang, 4, "Z") @ Matrix.Translation((0.095, 0, 0.004)) @
                     Matrix.Rotation(math.radians(22), 4, "X") @ Matrix.Diagonal((0.15, 0.034, 0.006, 1)))
            bmesh.ops.create_cube(bm, size=1.0, matrix=blade)
        bm.transform(Matrix.Translation(centre) @ tilt)
        prop = obj(f"Prop{sd}", bm, "DroneMetal", parent=rot_ob, pivot=centre, bevel=0.002)
        prop.rotation_mode = "XYZ"
        # tilt the ring + prop frames so local Z = ring axis (bake the tilt into the objects, not the meshes)
        for ob in (rot_ob, prop):
            ob.data.transform(tilt.inverted())
        rot_ob.rotation_euler = (ROTOR_TILT, 0, 0)
        bpy.context.view_layer.update()
        prop.matrix_world = Matrix.Translation(centre) @ tilt

    # ---- Under-barrel rotary guns ---------------------------------------------------------------------------
    for sx in (-1, 1):
        sd = "LR"[sx > 0]
        gx = sx * 0.155
        gz = F(0, 385)[1] - 0.05   # the side view hangs the guns lower than the front view does
        gun = cyl(f"Gun{sd}", (gx, 0.08, gz), (gx, 0.36, gz), 0.046, "DroneDark", segs=24, parent=chassis, bevel=0.005)
        box(f"GunMount{sd}", (gx - 0.03, 0.12, gz), (gx + 0.03, 0.3, gz + 0.07), "DroneMetal", parent=gun, bevel=0.004)
        axis_c = Vector((gx, 0.36, gz))
        bm = bmesh.new()
        for k in range(6):
            a = k * math.pi / 3
            off = Vector((math.cos(a) * 0.017, 0, math.sin(a) * 0.017))
            m = Matrix.Translation(axis_c + off + Vector((0, 0.15, 0))) @ Matrix.Rotation(-math.pi / 2, 4, "X")
            bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=0.0065, radius2=0.0065, depth=0.3, matrix=m)
        for yy in (0.08, 0.26):
            m = Matrix.Translation(axis_c + Vector((0, yy, 0))) @ Matrix.Rotation(-math.pi / 2, 4, "X")
            bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=0.029, radius2=0.029, depth=0.018, matrix=m)
        barrels = obj(f"GunBarrels{sd}", bm, "DroneMetal", parent=gun, pivot=axis_c, bevel=0.0015)
        barrels.rotation_mode = "XYZ"
        empty(f"Muzzle_{sd}", axis_c + Vector((0, 0.305, 0)), barrels)

    for ob in bpy.data.objects:
        if ob.type == "MESH":
            wn = ob.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL")
            wn.keep_sharp = True

    # ---- Review: reference image on the side, light, world -------------------------------------------------------
    img = bpy.data.images.load(REF)
    ref = bpy.data.objects.new("Reference", None)
    ref.empty_display_type = "IMAGE"
    ref.data = img
    ref.empty_display_size = img.size[0] * KS_Y
    ref.empty_image_offset = (-0.5, -0.5)
    ref.rotation_euler = (math.radians(90), 0, math.radians(90))
    ref.location = (-0.8, (SIDE_CX - img.size[0] / 2) * KS_Y * -1 + 0.0, 0)
    ref.color[3] = 0.4
    coll("Reference").objects.link(ref)
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), math.radians(15), math.radians(35))
    coll("Review").objects.link(sun)
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.4, 0.42, 0.46, 1)
    sc.world = world
    bpy.ops.wm.save_as_mainfile(filepath=OUT)
    print("saved", OUT)


build()
