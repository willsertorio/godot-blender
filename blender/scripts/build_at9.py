"""AT-9 automated ceiling turret, modelled from scratch after blender/reference/turret_concept.png -> blender/at9.blend.

    blender -b -P blender/scripts/build_at9.py

Side profiles are traced from the sheet's SIDE VIEW (image px) and extruded along X; widths come from the
FRONT VIEW. The two views disagree on proportions (the front view's arm and body are much longer), so the
side view wins for heights / lengths. Scale: 4.0 mm per image px (ceiling plate top -> housing bottom =
280 px = 1.12 m).

Frame: origin at the ceiling mount point (top of the plate), Z up (the turret hangs down, -Z), the guns /
sensor face +Y. Hierarchy and pivots (every moving part pivots where it moves):
  AT9 (root empty, ceiling mount)
    CeilingBracket          static plate + bracket
    Yaw                     rotates about Z, pivot under the bracket (turntable)
      ArmUpper              pivot at the shoulder hub (rotation X)
        ArmLower            pivot at the elbow hub (rotation X)
          Pitch             pivot at the housing hub (rotation X: + = guns up), armoured housing
            SensorUnit      red eyes (NeonRed); EyeGlow = the emissive discs (scale to 0 = dark)
            GunPod_L / _R   gun receivers
              Barrels_L/_R  rotary barrel clusters, spin about their own Y axis
            AmmoDrum_L / _R drums under the pods (feed chutes)
  Empties: Muzzle_L, Muzzle_R (barrel tips, children of the barrel clusters' pods), Eye (sensor centre).
Materials: TurretArmor, TurretDark, TurretMetal, TurretBrass, NeonRed.
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "blender", "at9.blend")
REF = os.path.join(ROOT, "blender", "reference", "turret_concept.png")

K = 0.004                  # metres per image px
ORIGIN_PX = (994, 105)     # ceiling mount (top of the plate) in the side view
POD_X = 115 * K            # gun pods sit this far either side of the centre
BORE_Y = 312               # barrel axis height (side view px)

MATS = {
    "TurretArmor": dict(color=(0.40, 0.41, 0.35), metallic=0.25, rough=0.55),
    "TurretDark": dict(color=(0.11, 0.115, 0.11), metallic=0.3, rough=0.6),
    "TurretMetal": dict(color=(0.24, 0.245, 0.25), metallic=0.85, rough=0.35),
    "TurretBrass": dict(color=(0.78, 0.6, 0.3), metallic=1.0, rough=0.3),
    "NeonRed": dict(color=(1.0, 0x2D / 255, 0x55 / 255), emit=8.0),
}


def P(x, y):
    """Side-view image px -> turret frame (Y forward = image left, Z up)."""
    return Vector((0.0, (ORIGIN_PX[0] - x) * K, (ORIGIN_PX[1] - y) * K))


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


def coll(name, hidden=False):
    c = bpy.data.collections.get(name)
    if not c:
        c = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(c)
        if hidden:
            c.hide_viewport = c.hide_render = True
    return c


def finish(ob, material, bevel, parent, pivot, collection="AT9"):
    ob.data.materials.append(mat(material))
    coll(collection).objects.link(ob)
    if pivot is not None:
        ob.data.transform(Matrix.Translation(-pivot))
        ob.location = pivot
    if bevel > 0:
        bv = ob.modifiers.new("Bevel", "BEVEL")
        bv.width = bevel
        bv.segments = 2
        bv.limit_method = "ANGLE"
        bv.angle_limit = math.radians(35)
        bv.harden_normals = True
    for p in ob.data.polygons:
        p.use_smooth = True
    if parent is not None:
        bpy.context.view_layer.update()
        mw = ob.matrix_world.copy()
        ob.parent = parent
        ob.matrix_world = mw
    return ob


def _mesh(name, bm):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return bpy.data.objects.new(name, me)


def prism(name, pts, width, material, bevel=0.006, parent=None, pivot=None, x0=0.0):
    """Side profile (image px) extruded along X, centred on x0 (m)."""
    bm = bmesh.new()
    f = bm.faces.new([bm.verts.new(P(*p) + Vector((x0 - width / 2, 0, 0))) for p in pts])
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    bmesh.ops.translate(bm, vec=Vector((width, 0, 0)),
                        verts=[e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)])
    return finish(_mesh(name, bm), material, bevel, parent, pivot)


def cyl(name, a, b, r, material, segs=20, bevel=0.003, parent=None, pivot=None, r2=None):
    bm = bmesh.new()
    d = b - a
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r if r2 is None else r2,
                          depth=d.length, matrix=Matrix.Translation((a + b) / 2) @ rot)
    return finish(_mesh(name, bm), material, bevel, parent, pivot)


def box(name, lo, hi, material, bevel=0.005, parent=None, pivot=None, collection="AT9"):
    bm = bmesh.new()
    lo, hi = Vector(lo), Vector(hi)
    bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((lo + hi) / 2) @ Matrix.Diagonal((*(hi - lo), 1)))
    return finish(_mesh(name, bm), material, bevel, parent, pivot, collection)


def cut(target, cutter):
    for c in list(cutter.users_collection):
        c.objects.unlink(cutter)
    coll("Cutters", hidden=True).objects.link(cutter)
    cutter.display_type = "WIRE"
    bpy.context.view_layer.update()
    mw = cutter.matrix_world.copy()
    cutter.parent = target
    cutter.matrix_world = mw
    bo = target.modifiers.new(f"Cut_{cutter.name}", "BOOLEAN")
    bo.object = cutter
    bo.operation = "DIFFERENCE"
    bo.solver = "EXACT"


def empty(name, loc, parent, size=0.04, kind="PLAIN_AXES"):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = size
    e.empty_display_type = kind
    coll("AT9").objects.link(e)
    e.location = loc
    if parent is not None:
        bpy.context.view_layer.update()
        mw = e.matrix_world.copy()
        e.parent = parent
        e.matrix_world = mw
    return e


def X(v):
    return Vector((v, 0, 0))


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = "METRIC"
    sc.render.fps = 30
    root = empty("AT9", Vector(), None, 0.15)

    # ---- ceiling bracket (static) ---------------------------------------------------------------------
    br = prism("CeilingBracket", [(1032, 113), (1022, 180), (1010, 195), (975, 195), (963, 180), (953, 113)],
               90 * K, "TurretArmor", parent=root)
    box("CeilingPlate", P(1058, 115) + X(-64 * K), P(930, 105) + X(64 * K), "TurretDark", 0.004, parent=br)
    for i, x in enumerate((975, 1012)):  # bolt slots on the bracket faces
        for sx in (-1, 1):
            cut(br, box(f"BracketSlot{i}{'LR'[sx > 0]}", P(x - 4, 150) + X(sx * 45 * K - 0.01),
                        P(x + 4, 125) + X(sx * 45 * K + 0.01), "TurretDark", 0))
    cyl("BracketHub", P(992, 182) + X(-47 * K), P(992, 182) + X(47 * K), 9 * K, "TurretMetal", parent=br)

    # ---- yaw turntable, arm ------------------------------------------------------------------------------
    yaw = cyl("Yaw", P(990, 195), P(990, 207), 36 * K, "TurretDark", segs=28, parent=root, pivot=P(990, 195))
    box("ShoulderClevis", P(992, 214) + X(-34 * K), P(960, 203) + X(34 * K), "TurretArmor", parent=yaw)
    sh, el, pv = P(975, 216), P(1050, 300), P(950, 307)
    up = box("ArmUpper", Vector((-25 * K, -14 * K, 0)), Vector((25 * K, 14 * K, (sh - el).length)), "TurretArmor",
             parent=None, pivot=None)
    # orient the upper arm from the shoulder to the elbow
    d = (el - sh).normalized()
    up.matrix_world = Matrix.Translation(sh) @ Vector((0, 0, -1)).rotation_difference(d).to_matrix().to_4x4() \
        @ Matrix.Rotation(math.pi, 4, "X")
    bpy.context.view_layer.update()
    up.data.transform(Matrix.Translation((0, 0, 0)))
    mw = up.matrix_world.copy()
    up.parent = yaw
    up.matrix_world = mw
    cyl("ShoulderHub", sh + X(-31 * K), sh + X(31 * K), 17 * K, "TurretMetal", segs=24, parent=up)
    cyl("ShoulderCap", sh + X(-33 * K), sh + X(-30 * K), 11 * K, "TurretDark", segs=24, parent=up)
    lo = prism("ArmLower", [(1065, 284), (1065, 318), (1048, 340), (960, 336), (948, 326), (948, 288), (965, 282)],
               56 * K, "TurretArmor", parent=up, pivot=el)
    cyl("ElbowHub", el + X(-33 * K), el + X(33 * K), 22 * K, "TurretMetal", segs=24, parent=lo)
    cyl("ElbowCap", el + X(-35 * K), el + X(-32 * K), 14 * K, "TurretDark", segs=24, parent=lo)
    cut(lo, prism("ArmWindow", [(965, 296), (1030, 296), (1030, 326), (965, 326)], 70 * K, "TurretDark", 0))
    cyl("Hose", P(1010, 190) + X(20 * K), P(1060, 290) + X(20 * K), 3 * K, "TurretDark", segs=8, parent=up)

    # ---- pitch: armoured housing ---------------------------------------------------------------------------
    pitch = prism("Pitch", [(762, 262), (775, 245), (830, 203), (898, 203), (915, 215), (917, 255), (935, 262),
                            (942, 290), (942, 330), (925, 345), (905, 350), (890, 380), (800, 385), (775, 372),
                            (762, 345)], 150 * K, "TurretArmor", bevel=0.01, parent=lo, pivot=pv)
    cyl("PitchHub", pv + X(-40 * K), pv + X(40 * K), 25 * K, "TurretMetal", segs=28, parent=pitch)
    box("TopPlate", P(898, 214) + X(-62 * K), P(812, 200) + X(62 * K), "TurretArmor", 0.006, parent=pitch)
    for i in range(5):   # rear vents, both sides
        z = 290 + i * 9
        for sx in (-1, 1):
            cut(pitch, box(f"Vent{i}{'LR'[sx > 0]}", P(938, z + 3) + X(sx * 75 * K - 0.012),
                           P(918, z) + X(sx * 75 * K + 0.012), "TurretDark", 0))
    box("BellyGrille", P(880, 389) + X(-50 * K), P(810, 380) + X(50 * K), "TurretDark", 0.004, parent=pitch)
    for i in range(6):
        y = 815 + i * 11
        cut(pitch.children[-1], box(f"Grille{i}", P(y + 4, 392) + X(-0.18), P(y, 384) + X(0.18), "TurretDark", 0))

    # ---- sensor unit (eyes) -----------------------------------------------------------------------------------
    sens = prism("SensorUnit", [(762, 258), (812, 258), (812, 302), (762, 302)], 70 * K, "TurretDark",
                 bevel=0.006, parent=pitch)
    glow = None
    for i, (dx, z, r) in enumerate(((0, 275, 11), (-14, 294, 5), (14, 294, 5))):
        c = P(762, z) + X(dx * K)
        e = cyl(f"EyeGlow{i}", c + Vector((0, -0.002, 0)), c + Vector((0, 0.006, 0)), r * K, "NeonRed", segs=20,
                bevel=0, parent=sens)
        if glow is None:
            glow = e
        else:   # one EyeGlow object (scale it to dim / kill the eyes)
            bpy.ops.object.select_all(action="DESELECT")
    eyes = [o for o in sens.children if o.name.startswith("EyeGlow")]
    bpy.ops.object.select_all(action="DESELECT")
    for o in eyes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = eyes[0]
    bpy.ops.object.join()
    eg = bpy.context.view_layer.objects.active
    eg.name = "EyeGlow"
    # pivot of the glow at the big eye so scaling shrinks it in place
    ctr = P(762, 275)
    bpy.context.view_layer.update()
    local = eg.matrix_world.inverted() @ ctr
    eg.data.transform(Matrix.Translation(-local))
    eg.location += eg.matrix_world.to_3x3() @ local
    for dx, z, r in ((0, 275, 15), (-14, 294, 8), (14, 294, 8)):   # lens rims
        c = P(762, z) + X(dx * K)
        cyl(f"EyeRim{z}{dx}", c + Vector((0, -0.003, 0)), c + Vector((0, 0.004, 0)), r * K, "TurretMetal", segs=20,
            bevel=0, parent=sens)
    empty("Eye", P(758, 275), sens, 0.05)

    # ---- gun pods, rotary barrels, drums ---------------------------------------------------------------------
    for side, sx in (("L", -1), ("R", 1)):
        x = sx * POD_X
        pod = prism(f"GunPod_{side}", [(772, 272), (880, 272), (900, 285), (900, 340), (880, 352), (772, 352)],
                    70 * K, "TurretDark", bevel=0.008, parent=pitch, x0=x)
        box(f"PodArmor_{side}", P(880, 280) + X(x - 37 * K), P(800, 268) + X(x + 37 * K), "TurretArmor", 0.005,
            parent=pod)
        cyl(f"PodMount_{side}", P(850, 312) + X(sx * 70 * K), P(850, 312) + X(sx * 82 * K), 18 * K, "TurretMetal",
            parent=pod)
        axis_c = P(772, BORE_Y) + X(x)
        bar = cyl(f"Barrels_{side}", axis_c + Vector((0, -2 * K, 0)), axis_c + Vector((0, 12 * K, 0)), 18 * K,
                  "TurretMetal", segs=24, parent=pod, pivot=axis_c)
        for k in range(6):
            a = k * math.pi / 3
            off = Vector((math.cos(a) * 13 * K, 0, math.sin(a) * 13 * K))
            cyl(f"Barrel_{side}{k}", P(578, BORE_Y) + X(x) + off, P(772, BORE_Y) + X(x) + off, 4.2 * K, "TurretDark",
                segs=10, bevel=0.001, parent=bar)
        cyl(f"Spindle_{side}", P(590, BORE_Y) + X(x), P(772, BORE_Y) + X(x), 5 * K, "TurretMetal", segs=12, parent=bar)
        for y, w in ((580, 6), (602, 5), (672, 9)):
            cyl(f"Clamp_{side}{y}", P(y + w, BORE_Y) + X(x), P(y, BORE_Y) + X(x), 19.5 * K, "TurretMetal", segs=24,
                parent=bar)
        empty(f"Muzzle_{side}", P(574, BORE_Y) + X(x), pod, 0.05)
        drum = cyl(f"AmmoDrum_{side}", P(850, 382) + X(x - 20 * K), P(850, 382) + X(x + 20 * K), 32 * K, "TurretDark",
                   segs=32, parent=pitch, pivot=P(850, 382) + X(x))
        cyl(f"DrumCap_{side}", P(850, 382) + X(x + sx * 20 * K), P(850, 382) + X(x + sx * 23 * K), 22 * K,
            "TurretArmor", segs=28, parent=drum)
        box(f"Feed_{side}", P(862, 352) + X(x - 12 * K), P(838, 345) + X(x + 12 * K), "TurretBrass", 0.002,
            parent=drum)

    for ob in bpy.data.objects:
        if ob.type == "MESH":
            wn = ob.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL")
            wn.keep_sharp = True

    # ---- review setup ---------------------------------------------------------------------------------------
    img = bpy.data.images.load(REF)
    ref = bpy.data.objects.new("Reference", None)
    ref.empty_display_type = "IMAGE"
    ref.data = img
    ref.empty_display_size = img.size[0] * K
    ref.empty_image_offset = (-0.5, -0.5)
    ref.rotation_euler = (math.radians(90), 0, math.radians(-90))
    ref.location = Vector((-0.6, (ORIGIN_PX[0] - img.size[0] / 2) * K, (ORIGIN_PX[1] - img.size[1] / 2) * -K))
    ref.color[3] = 0.5
    coll("Reference", hidden=True).objects.link(ref)
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(-35))
    coll("Review").objects.link(sun)
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.4, 0.42, 0.46, 1)
    sc.world = world
    bpy.ops.wm.save_as_mainfile(filepath=OUT)
    print("saved", OUT)


build()
