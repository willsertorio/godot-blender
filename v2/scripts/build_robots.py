"""V2 concept scene, stage 3: the three robots, built in their rest poses with every moving part on a joint
(animated by anim_robots.py).

    blender -b -P v2/scripts/build_robots.py                    # into v2/scene.blend (rebuilds the Robots collection)
    xvfb-run -a blender -b -P v2/scripts/build_robots.py -- review /tmp/robots   # each robot alone, 3 views (EEVEE)

Same method as the pistol (build_pistol.Part: millimetres, extruded profiles, boolean cuts, bevels), bigger parts:
white armour plates with panel lines and vents over dark frames, joints, pistons, cables, red sensors.
  Spider  quadruped, body 0.9 m long standing 0.62 m off the floor, twin-barrel turret on its back
  Drone   central pod with a red eye, two ducted rotors on arms, gun under the nose
  Turret  ceiling mount, two-segment arm, armoured head with a shrouded twin gun and an ammo drum
Each robot is built around its own origin (+Y forward, +Z up) and placed with a matrix.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import v2lib as L  # noqa: E402
from build_pistol import Part  # noqa: E402

S = 0.001
I4 = Matrix.Identity(4)


def T(x, y, z):
    return Matrix.Translation(Vector((x, y, z)) * S)


def RX(d):
    return Matrix.Rotation(math.radians(d), 4, "X")


def RY(d):
    return Matrix.Rotation(math.radians(d), 4, "Y")


def RZ(d):
    return Matrix.Rotation(math.radians(d), 4, "Z")


def seg(p0, p1):
    """Local frame for a limb drawn in a vertical plane (x = out, z = up): origin p0, +X toward p1. -> (matrix, length)"""
    ang = math.atan2(p1[1] - p0[1], p1[0] - p0[0])
    return T(p0[0], 0, p0[1]) @ Matrix.Rotation(-ang, 4, "Y"), math.hypot(p1[0] - p0[0], p1[1] - p0[1])


def materials():
    names = ("RArmor", "RFrame", "RSteel", "RRubber", "REye", "RRed", "RBrass", "RLens", "RGlow", "RDisc")
    for n in names:
        if bpy.data.materials.get(n):
            bpy.data.materials.remove(bpy.data.materials[n])
    m = {}
    m["armor"] = L.pbr("RArmor", "PaintedPlaster017", scale=0.6, tint=(0.9, 0.91, 0.93), rough=(0.22, 0.42), normal=0.4,
                       grunge=0.18, grunge_scale=5, round_edges=0.002, edge_wear=0.7, wear_color=(0.16, 0.17, 0.18),
                       wear_radius=0.004, wear_noise=70, cavity=0.7, cavity_dist=0.03, wear_metal=0.8)
    m["frame"] = L.pbr("RFrame", "Metal032", scale=0.3, tint=(0.09, 0.095, 0.105), rough=(0.35, 0.6), metallic=0.7,
                       round_edges=0.0015, edge_wear=0.6, wear_color=(0.55, 0.55, 0.55), wear_radius=0.003, wear_noise=90,
                       cavity=0.4, cavity_dist=0.02)
    m["steel"] = L.pbr("RSteel", "Metal032", scale=0.2, tint=(0.62, 0.63, 0.65), rough=(0.15, 0.35), metallic=1.0,
                       round_edges=0.001)
    m["rubber"] = L.pbr("RRubber", "Rubber004", scale=0.1, bright=1.0, rough=(0.6, 0.9), normal=1.5)
    m["eye"] = L.plain("REye", (0, 0, 0), emit=(1.0, 0.06, 0.03), emit_strength=40.0)
    m["glow"] = L.plain("RGlow", (0, 0, 0), emit=(1.0, 0.25, 0.08), emit_strength=12.0)
    m["red"] = L.plain("RRed", (0.5, 0.03, 0.02), rough=0.35)
    m["brass"] = L.plain("RBrass", (0.75, 0.55, 0.22), rough=0.3, metallic=1.0)
    m["lens"] = L.plain("RLens", (0.02, 0.02, 0.025), rough=0.03, metallic=0.9)
    m["disc"] = L.plain("RDisc", (0.12, 0.12, 0.13), rough=0.4, alpha=0.3)        # spinning-prop blur
    return m


class Robot:
    """Parts hang from joints (empties named <Robot>_<Joint>): the animations move the joints, never the parts.
    `joint()` places one at a matrix in the robot's frame, under a parent joint; `add()` / `cable()` put a part at a
    matrix in the robot's frame and parent it to a joint. "Root" is the placement in the scene and is never animated."""

    def __init__(self, name, collection, M):
        self.name, self.coll, self.M, self.objs = name, collection, M, []
        self.joints = {}
        self.joint("Root", I4, None)

    def joint(self, name, local=I4, parent="Root"):
        e = bpy.data.objects.new(f"{self.name}_{name}", None)
        e.empty_display_type = "ARROWS"
        e.empty_display_size = 0.08
        e.rotation_mode = "QUATERNION"
        self.coll.objects.link(e)
        world = self.M @ local
        if parent:
            pe, pw = self.joints[parent]
            e.parent = pe
            e.matrix_basis = pw.inverted() @ world
        else:
            e.matrix_basis = world
        self.joints[name] = (e, world)
        return name

    def _attach(self, ob, world, joint):
        e, jw = self.joints[joint]
        ob.parent = e
        ob.matrix_parent_inverse = Matrix.Identity(4)
        ob.matrix_basis = jw.inverted() @ world

    def add(self, part, local=I4, joint="Root"):
        part.name = f"{self.name}_{part.name}"
        ob = part.finish(self.coll)
        self._attach(ob, self.M @ local, joint)
        self.objs.append(ob)
        return ob

    def cable(self, name, pts_mm, r_mm, mat, local=I4, joint="Root"):
        pts = [(self.M @ local @ (Vector(p) * S)) for p in pts_mm]
        ob = L.curve_tube(f"{self.name}_{name}", pts, r_mm * S, mat, collection=self.coll.name)
        self._attach(ob, Matrix.Identity(4), joint)            # (its points are already in world space)
        self.objs.append(ob)

    def flash(self, name, local, joint, size=1.6):
        """A muzzle flash (hidden by scale 0) with its light; `local` puts its origin at the muzzle, +Y along the barrel."""
        from build_pistol import make_flash
        fl, lo = make_flash(f"{self.name}_{name}", self.coll, None, (0, 0, 0), size)
        self._attach(fl, self.M @ local, joint)
        self._attach(lo, self.M @ local @ T(0, 60, 10), joint)
        fl.rotation_mode = "QUATERNION"
        fl.scale = (0, 0, 0)
        self.objs += [fl, lo]


def bolts(part, pts, axis, r=7, h=5):
    for p in pts:
        p = Vector(p)
        part.cyl(p, p + Vector(axis) * h, r, segs=6)


# ====================================================================== spider
BODY_Z = 540                                                     # spider: body centre above the floor (mm)
LEGS = ((300, 300, 42), (-300, 300, 138), (-300, -300, 222), (300, -300, 318))   # hip x, y and the leg's heading (deg)
LEG_PIVOT, LEG_KNEE, LEG_ANKLE, LEG_TOE = (30, 20), (400, 235), (735, -470), (800, -540)   # in the leg's plane (out, up)


def spider(coll, M, mats, turret_yaw=20):
    R = Robot("Spider", coll, M @ T(0, 0, BODY_Z))
    R.joint("Body")
    A, F, ST = mats["armor"], mats["frame"], mats["steel"]
    core = Part("Core", F, bevel=14, segs=2)
    core.box((-235, -385, -95), (235, 385, 70))
    for i in range(7):                                         # belly ribs
        core.box((-190, -300 + i * 100, -118), (190, -250 + i * 100, -95))
    core.cyl((0, -420, -20), (0, -385, -20), 60, segs=20)      # rear exhaust
    R.add(core, joint="Body")
    shell = Part("Shell", A, bevel=52, segs=6)
    shell.prism_x([(-405, -15), (-440, 55), (-345, 150), (140, 172), (350, 118), (438, 28), (405, -40)], -262, 262)
    c = shell.cut()                                            # panel lines
    c.box((-300, -112, 20), (300, -106, 220))
    c.box((-300, 196, 20), (300, 202, 220))
    c.box((-3, -445, 100), (3, -112, 230))
    c = shell.cut()                                            # vents on the rear deck
    for sx in (-1, 1):
        for i in range(5):
            c.box((sx * 130 - 70, -330 + i * 36, 120), (sx * 130 + 70, -314 + i * 36, 230))
    c = shell.cut()                                            # visor recess + turret well
    c.box((-175, 395, 5), (175, 470, 86))
    c = shell.cut()
    c.cyl((0, 30, 150), (0, 30, 240), 150, segs=40)
    R.add(shell, joint="Body")
    visor = Part("Visor", mats["lens"], bevel=3)
    visor.box((-172, 380, 8), (172, 402, 84))
    R.add(visor, joint="Body")
    eyes = Part("Eyes", mats["eye"], bevel=0)
    for sx in (-1, 1):
        eyes.box((sx * 95 - 55, 400, 34), (sx * 95 + 55, 406, 56))
    eyes.cyl((0, 400, 45), (0, 406, 45), 9, segs=12)
    R.add(eyes, joint="Body")
    skirts = Part("Skirts", A, bevel=10, segs=3)
    for sx in (-1, 1):
        skirts.prism_y([(sx * 258, -75), (sx * 292, -55), (sx * 292, 85), (sx * 258, 100)][::sx], -120, 150)
    c = skirts.cut()
    for sx in (-1, 1):
        for i in range(4):
            c.box((sx * 292 - 8, -80 + i * 50, -20), (sx * 292 + 8, -62 + i * 50, 60))
    R.add(skirts, joint="Body")
    lamps = Part("Lamps", mats["glow"], bevel=0)
    for sx in (-1, 1):
        lamps.box((sx * 293 - 2, 105, 20), (sx * 293 + 2, 135, 34))
        lamps.box((-120 * sx - 30, -441, 20), (-120 * sx + 30, -437, 34))
    R.add(lamps, joint="Body")
    # --- legs
    KNEE, ANKLE, TOE = LEG_KNEE, LEG_ANKLE, LEG_TOE
    for i, (hx, hy, ang) in enumerate(LEGS):
        LM = T(hx, hy, -5) @ RZ(ang)
        R.joint(f"Hip{i}", LM, "Body")                                           # swings the leg fore / aft
        R.joint(f"Thigh{i}", LM @ T(LEG_PIVOT[0], 0, LEG_PIVOT[1]), f"Hip{i}")   # lifts it (turns about its Y)
        R.joint(f"Shin{i}", LM @ T(KNEE[0], 0, KNEE[1]), f"Thigh{i}")
        R.joint(f"Foot{i}", LM @ T(ANKLE[0], 0, ANKLE[1]), f"Shin{i}")
        hip = Part(f"Hip{i}", F, bevel=8)
        hip.cyl((0, 0, -85), (0, 0, 80), 92, segs=28)
        hip.cyl((30, -75, 20), (30, 75, 20), 70, segs=24)
        R.add(hip, LM, f"Hip{i}")
        cap = Part(f"HipCap{i}", A, bevel=6, segs=3)          # domed pauldron over the hip
        cap.ellipsoid((0, 0, 62), (128, 128, 74))
        c = cap.cut()
        c.box((-200, -200, -80), (200, 200, 62))
        c = cap.cut()
        c.cyl((0, 0, 118), (0, 0, 160), 46, segs=24)
        R.add(cap, LM, f"Hip{i}")
        m, ln = seg(LEG_PIVOT, KNEE)
        th = Part(f"Thigh{i}", F, bevel=8)
        th.box((0, -60, -55), (ln, 60, 55))
        th.cyl((60, -58, -20), (60, 58, -20), 16, segs=10)
        R.add(th, LM @ m, f"Thigh{i}")
        ta = Part(f"ThighArmor{i}", A, bevel=30, segs=5)
        ta.prism_y([(30, -20), (60, 96), (ln - 110, 106), (ln - 20, 52), (ln - 34, -20)], -88, 88)
        c = ta.cut()
        c.box((ln * 0.5 - 3, -90, 20), (ln * 0.5 + 3, 90, 120))
        for k in range(3):
            c.box((90 + k * 34, -110, 30), (106 + k * 34, -76, 76))
            c.box((90 + k * 34, 76, 30), (106 + k * 34, 110, 76))
        R.add(ta, LM @ m, f"Thigh{i}")
        kn = Part(f"Knee{i}", ST, bevel=5)
        kn.cyl((KNEE[0], -104, KNEE[1]), (KNEE[0], 104, KNEE[1]), 80, segs=32)
        bolts(kn, [(KNEE[0] + 40 * math.cos(a), 98, KNEE[1] + 40 * math.sin(a)) for a in (0, 2.1, 4.2)], (0, 1, 0))
        bolts(kn, [(KNEE[0] + 40 * math.cos(a), -98, KNEE[1] + 40 * math.sin(a)) for a in (0, 2.1, 4.2)], (0, -1, 0))
        R.add(kn, LM, f"Shin{i}")
        kc = Part(f"KneeCap{i}", A, bevel=5, segs=2)           # armour dome over the front of the knee
        kc.ellipsoid((KNEE[0] + 18, 0, KNEE[1] + 22), (104, 96, 104))
        c = kc.cut()
        c.cyl((KNEE[0], -150, KNEE[1]), (KNEE[0], 150, KNEE[1]), 86, segs=32)
        c = kc.cut()
        c.box((KNEE[0] - 200, -150, KNEE[1] - 200), (KNEE[0] + 20, 150, KNEE[1] - 5), rx=0)
        R.add(kc, LM, f"Shin{i}")
        m, ln = seg(KNEE, ANKLE)
        sh = Part(f"Shin{i}", F, bevel=7)
        sh.prism_y([(0, -72), (0, 72), (ln * 0.55, 56), (ln, 24), (ln, -22), (ln * 0.55, -44)], -54, 54)
        R.add(sh, LM @ m, f"Shin{i}")
        sa = Part(f"ShinArmor{i}", A, bevel=26, segs=5)
        sa.prism_y([(70, 30), (56, 112), (ln * 0.52, 96), (ln * 0.8, 52), (ln * 0.66, 30)], -72, 72)
        c = sa.cut()
        c.box((ln * 0.3 - 3, -70, 10), (ln * 0.3 + 3, 70, 120))
        R.add(sa, LM @ m, f"Shin{i}")
        m, ln = seg(ANKLE, TOE)
        ft = Part(f"Foot{i}", ST, bevel=4)
        ft.cyl((0, -62, 0), (0, 62, 0), 44, segs=24)
        ft.prism_y([(-10, -40), (ln + 10, -30), (ln + 30, 0), (ln + 10, 30), (-10, 40)], -40, 40)
        R.add(ft, LM @ m, f"Foot{i}")
        pad = Part(f"FootPad{i}", mats["rubber"], bevel=5)
        pad.cyl((TOE[0] + 6, 0, TOE[1]), (TOE[0] + 6, 0, TOE[1] + 30), 66, segs=28)
        R.add(pad, LM, f"Foot{i}")
        m, ln = seg((150, -40), (KNEE[0] + 95, KNEE[1] - 190))       # hydraulic ram under the thigh
        ram = Part(f"Ram{i}", ST, bevel=2)
        ram.cyl((0, 0, 0), (ln * 0.55, 0, 0), 26, segs=16)
        ram.cyl((ln * 0.55, 0, 0), (ln, 0, 0), 14, segs=12)
        ram.cyl((0, -26, 0), (0, 26, 0), 16, segs=12)
        ram.cyl((ln, -26, 0), (ln, 26, 0), 14, segs=12)
        R.add(ram, LM @ m, f"Thigh{i}")
        R.cable(f"Hose{i}", [(60, 50, 40), (200, 70, 240), (KNEE[0] - 40, 60, KNEE[1] + 70), (KNEE[0] + 60, 50, KNEE[1] - 60)], 8,
                mats["rubber"], LM, f"Thigh{i}")
    # --- turret on the back
    TM = T(0, 30, 150) @ RZ(turret_yaw)
    R.joint("Turret", TM, "Body")                              # turns about its Z
    R.joint("Guns", TM @ T(0, 0, 125), "Turret")               # elevates about its X, recoils along its Y
    ring = Part("TurretRing", F, bevel=6)
    ring.cyl((0, 0, 0), (0, 0, 50), 140, segs=40)
    ring.box((-70, -60, 50), (70, 120, 150))
    R.add(ring, TM, "Turret")
    tb = Part("TurretBody", A, bevel=40, segs=5)
    tb.prism_x([(-150, 50), (-170, 120), (-110, 205), (60, 215), (150, 160), (160, 60)], -105, 105)
    c = tb.cut()
    c.box((-120, -40, 150), (120, -34, 260))
    c.box((40, 100, 90), (120, 200, 150))
    R.add(tb, TM, "Turret")
    gun = Part("Guns", F, bevel=3)
    for sx in (-1, 1):
        gun.box((sx * 150 - 38, -90, 80), (sx * 150 + 38, 150, 170))
        gun.cyl((sx * 150, 150, 125), (sx * 150, 560, 125), 17, segs=16)
        gun.cyl((sx * 150, 250, 125), (sx * 150, 430, 125), 27, segs=18)
        gun.cyl((sx * 150, 540, 125), (sx * 150, 610, 125), 25, segs=16)
        gun.cyl((sx * 105, 0, 125), (sx * 150, 0, 125), 30, segs=16)
    c = gun.cut()
    for sx in (-1, 1):
        c.cyl((sx * 150, 520, 125), (sx * 150, 620, 125), 11, segs=12)
        for k in range(3):
            c.box((sx * 150 - 40, 556 + k * 16, 119), (sx * 150 + 40, 564 + k * 16, 131))
    R.add(gun, TM, "Guns")
    for sx, nm in ((-1, "L"), (1, "R")):
        R.flash(f"Flash{nm}", TM @ T(sx * 150, 615, 125), "Guns")
    te = Part("TurretEye", mats["eye"], bevel=0)
    te.cyl((0, 154, 150), (0, 160, 150), 26, segs=20)
    R.add(te, TM, "Turret")
    tl = Part("TurretLens", mats["lens"], bevel=3)
    tl.cyl((0, 140, 150), (0, 156, 150), 40, segs=24)
    tl.box((70, -140, 110), (100, -60, 200))
    R.add(tl, TM, "Turret")
    return R


# ====================================================================== drone
PROP = {-1: "L", 1: "R"}


def drone(coll, M, mats):
    R = Robot("Drone", coll, M)
    R.joint("Body")                                            # the whole drone: hover, bank, fall
    R.joint("Gun", T(0, 0, -155), "Body")                      # recoils along its Y
    A, F, ST = mats["armor"], mats["frame"], mats["steel"]
    core = Part("Core", F, bevel=30, segs=4)
    core.prism_y([(-150, -30), (-120, -120), (120, -120), (150, -30), (150, 60), (-150, 60)], -230, 170)
    for sx in (-1, 1):
        core.box((sx * 140 - 10, -60, -10), (sx * 420, 60, 46))               # rotor arms
    core.box((-40, -330, 20), (40, -220, 80))                                   # tail boom
    R.add(core, joint="Body")
    shell = Part("Shell", A, bevel=5, segs=2)                 # rounded upper shell
    shell.ellipsoid((0, -30, 30), (188, 262, 150), segs=48, rings=24)
    c = shell.cut()
    c.box((-300, -400, -300), (300, 400, 4))
    c = shell.cut()
    c.cyl((0, 120, 20), (0, 320, 20), 118, segs=36)
    c = shell.cut()
    c.box((-200, -62, 60), (200, -56, 200))
    c.box((-3, -260, 120), (3, 190, 200))
    for sx in (-1, 1):
        for k in range(4):
            c.box((sx * 95 - 45, -220 + k * 30, 140), (sx * 95 + 45, -206 + k * 30, 200))
    R.add(shell, joint="Body")
    for sx in (-1, 1):
        ac = Part(f"ArmCover{sx}", A, bevel=12, segs=3)
        ac.box((min(sx * 190, sx * 400), -72, 30), (max(sx * 190, sx * 400), 72, 62))
        R.add(ac, joint="Body")
    face = Part("Face", F, bevel=8)
    face.cyl((0, 150, 20), (0, 214, 20), 112, segs=36)
    c = face.cut()
    c.cyl((0, 196, 20), (0, 230, 20), 84, segs=32)
    R.add(face, joint="Body")
    bezel = Part("Bezel", A, bevel=5)
    bezel.cyl((0, 186, 20), (0, 222, 20), 122, segs=40)
    c = bezel.cut()
    c.cyl((0, 170, 20), (0, 240, 20), 100, segs=36)
    R.add(bezel, joint="Body")
    eye = Part("Eye", mats["eye"], bevel=0)
    eye.cyl((0, 196, 20), (0, 202, 20), 46, segs=28)
    R.add(eye, joint="Body")
    lens = Part("EyeLens", mats["lens"], bevel=3)
    lens.cyl((0, 190, 20), (0, 198, 20), 84, segs=32)
    R.add(lens, joint="Body")
    for sx in (-1, 1):
        DM = T(sx * 560, 0, 70) @ RY(-sx * 7)
        R.joint(f"Prop{PROP[sx]}", DM, "Body")                 # spins about its Z
        duct = Part(f"Duct{sx}", A, bevel=15, segs=5)
        duct.cyl((0, 0, -58), (0, 0, 58), 300, segs=64)
        c = duct.cut()
        c.cyl((0, 0, -80), (0, 0, 80), 266, segs=64)
        R.add(duct, DM, "Body")
        band = Part(f"DuctBand{sx}", mats["red"], bevel=0)
        for a0 in (20, 140, 260):
            for k in range(8):
                a = math.radians(a0 + k * 5)
                band.box((300 * math.cos(a) - 6, 300 * math.sin(a) - 15, 14), (300 * math.cos(a) + 6, 300 * math.sin(a) + 15, 40),
                         rz=math.degrees(a))
        R.add(band, DM, "Body")
        hub = Part(f"Hub{sx}", F, bevel=5)
        hub.cyl((0, 0, -44), (0, 0, 44), 50, segs=24)
        for a in (0, 120, 240):
            hub.box((0, -9, -30), (270, 9, -14), rz=0)
        R.add(hub, DM, "Body")
        for a in (120, 240):
            st = Part(f"Strut{sx}_{a}", F, bevel=3)
            st.box((0, -9, -30), (270, 9, -14))
            R.add(st, DM @ RZ(a), "Body")
        for k in range(3):
            bl = Part(f"Blade{sx}_{k}", ST, bevel=1.5)
            bl.prism_x([(-34, 0), (-20, 5), (26, 3), (34, 0), (26, -2), (-20, -2)], 46, 258)
            R.add(bl, DM @ RZ(k * 120 + 25 * sx) @ T(0, 0, 14) @ RX(0) @ Matrix.Rotation(math.radians(14), 4, "X"), f"Prop{PROP[sx]}")
        cap = Part(f"HubCap{sx}", mats["red"], bevel=0)
        cap.ellipsoid((0, 0, 44), (44, 44, 26), segs=24, rings=12)
        R.add(cap, DM, f"Prop{PROP[sx]}")
        disc = Part(f"PropBlur{sx}", mats["disc"], bevel=0)
        disc.cyl((0, 0, 16), (0, 0, 22), 262, segs=64)
        R.add(disc, DM, "Body")
    gun = Part("Gun", F, bevel=4)
    gun.box((-48, -60, -190), (48, 120, -118))
    gun.cyl((0, 120, -155), (0, 400, -155), 15, segs=14)
    gun.cyl((0, 180, -155), (0, 300, -155), 24, segs=16)
    gun.cyl((0, 380, -155), (0, 430, -155), 22, segs=14)
    gun.cyl((0, 0, -120), (0, 0, -90), 40, segs=18)
    R.add(gun, joint="Gun")
    R.flash("Flash", T(0, 435, -155), "Gun", size=1.3)
    gl = Part("GunGlow", mats["glow"], bevel=0)
    gl.box((-49, 20, -160), (-47, 80, -148))
    gl.box((47, 20, -160), (49, 80, -148))
    R.add(gl, joint="Gun")
    ant = Part("Antenna", ST, bevel=0)
    ant.cyl((60, -200, 160), (75, -260, 420), 4, segs=8)
    ant.cyl((-60, -200, 160), (-60, -200, 250), 9, segs=10)
    R.add(ant, joint="Body")
    R.cable("HoseL", [(-150, -80, 50), (-260, -110, 100), (-400, -60, 70)], 9, mats["rubber"], joint="Body")
    R.cable("HoseR", [(150, -80, 50), (260, -110, 100), (400, -60, 70)], 9, mats["rubber"], joint="Body")
    return R


# ====================================================================== ceiling turret
ARM_SH, ARM_EL, ARM_WR = (0, -260), (560, -820), (1060, -700)      # ceiling turret: shoulder, elbow, wrist (forward, up)


def turret(coll, M, mats, aim_pitch=-22, drop=0):
    R = Robot("Turret", coll, M)                      # origin at the mount, arm in the local XZ plane (X = forward)
    A, F, ST = mats["armor"], mats["frame"], mats["steel"]
    if drop > 0:                                      # pylon from the ceiling down to the mount
        py = Part("Pylon", F, bevel=8)
        py.box((-90, -90, 0), (90, 90, drop))
        py.box((-260, -260, drop - 40), (260, 260, drop))
        for k in range(int(drop // 280)):
            py.box((-104, -104, 120 + k * 280), (104, 104, 170 + k * 280))
        for sx, sy in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
            py.cyl((sx * 80, sy * 80, drop * 0.45), (sx * 230, sy * 230, drop - 30), 16, segs=10)
        R.add(py)
        R.cable("PylonCable1", [(95, 30, drop), (118, 40, drop * 0.6), (110, 60, 60), (70, 90, -150)], 14, mats["rubber"])
        R.cable("PylonCable2", [(-95, -30, drop), (-120, -50, drop * 0.5), (-100, -80, 40), (-50, -95, -150)], 11, mats["rubber"])
    SH, EL, WR = ARM_SH, ARM_EL, ARM_WR
    HM = T(WR[0], 0, WR[1]) @ RY(-aim_pitch)
    R.joint("Yaw")                                             # the mount turns about its Z
    R.joint("Shoulder", T(SH[0], 0, SH[1]), "Yaw")             # the arm joints turn about their Y
    R.joint("Elbow", T(EL[0], 0, EL[1]), "Shoulder")
    R.joint("Head", HM, "Elbow")                               # elevates about its Y
    R.joint("Guns", HM, "Head")                                # recoil along its X
    base = Part("Mount", F, bevel=8)
    base.cyl((0, 0, -45), (0, 0, 0), 270, segs=48)
    bolts(base, [(230 * math.cos(a), 230 * math.sin(a), -45) for a in [k * math.tau / 10 for k in range(10)]], (0, 0, -1), r=12, h=10)
    base.cyl((0, 0, -200), (0, 0, -45), 150, segs=36)
    base.cyl((0, -170, -260), (0, 170, -260), 105, segs=32)
    R.add(base, joint="Yaw")
    collar = Part("Collar", A, bevel=20, segs=5)
    collar.cyl((0, 0, -170), (0, 0, -60), 190, segs=48)
    c = collar.cut()
    c.cyl((0, 0, -200), (0, 0, -30), 152, segs=40)
    for k in range(8):
        a = k * math.tau / 8
        c.box((176 * math.cos(a) - 30, 176 * math.sin(a) - 9, -150), (176 * math.cos(a) + 30, 176 * math.sin(a) + 9, -80),
              rz=math.degrees(a))
    R.add(collar, joint="Yaw")
    for name, p0, p1, w, h, jn in (("Upper", SH, EL, 130, 120, "Shoulder"), ("Fore", EL, WR, 110, 100, "Elbow")):
        m, ln = seg(p0, p1)
        beam = Part(name + "Arm", F, bevel=8)
        beam.box((0, -w / 2, -h / 2), (ln, w / 2, h / 2))
        for k in range(4):
            beam.box((ln * 0.2 + k * ln * 0.17, -w / 2 - 6, -h * 0.3), (ln * 0.2 + k * ln * 0.17 + 30, w / 2 + 6, h * 0.3))
        R.add(beam, m, jn)
        cov = Part(name + "Cover", A, bevel=22, segs=5)
        cov.prism_y([(70, h / 2 - 6), (90, h / 2 + 34), (ln - 110, h / 2 + 34), (ln - 80, h / 2 - 6)], -w / 2 - 14, w / 2 + 14)
        c = cov.cut()
        c.box((ln * 0.5 - 3, -200, 0), (ln * 0.5 + 3, 200, 200))
        R.add(cov, m, jn)
        ram = Part(name + "Ram", ST, bevel=2)
        ram.cyl((60, 0, -h / 2 - 30), (ln * 0.55, 0, -h / 2 - 30), 22, segs=16)
        ram.cyl((ln * 0.55, 0, -h / 2 - 30), (ln - 60, 0, -h / 2 - 30), 12, segs=12)
        R.add(ram, m, jn)
    for (x, z), r, w, jname, jn in ((EL, 100, 290, "ElbowJoint", "Shoulder"), (WR, 84, 250, "WristJoint", "Elbow")):
        joints = Part(jname, ST, bevel=5)
        joints.cyl((x, -w / 2, z), (x, w / 2, z), r, segs=32)
        bolts(joints, [(x + r * 0.6 * math.cos(a), w / 2, z + r * 0.6 * math.sin(a)) for a in (0.5, 2.6, 4.7)], (0, 1, 0), r=9)
        bolts(joints, [(x + r * 0.6 * math.cos(a), -w / 2, z + r * 0.6 * math.sin(a)) for a in (0.5, 2.6, 4.7)], (0, -1, 0), r=9)
        R.add(joints, joint=jn)
    R.cable("Cable1", [(60, 90, -200), (250, 120, -520), (540, 150, -700), (760, 120, -840), (1000, 110, -760)], 13, mats["rubber"], joint="Shoulder")
    R.cable("Cable2", [(40, -90, -200), (300, -130, -470), (560, -150, -900), (820, -110, -700), (1040, -100, -640)], 10, mats["rubber"], joint="Shoulder")
    # head: hangs from the wrist, aimed with aim_pitch (negative = down)
    hd = Part("HeadFrame", F, bevel=10)
    hd.box((-120, -120, -260), (330, 120, -30))
    hd.box((-40, -60, -60), (60, 60, 40))
    hd.cyl((60, 150, -150), (60, 262, -150), 118, segs=32)                    # ammo drum
    R.add(hd, HM, "Head")
    hs = Part("HeadShell", A, bevel=58, segs=6)
    hs.prism_y([(-160, -280), (-185, -120), (-120, -10), (250, 0), (380, -80), (400, -200), (340, -290)], -152, 152)
    c = hs.cut()
    c.box((90, -200, -140), (96, 200, 20))
    c.box((-200, -3, -60), (420, 3, 20))
    for sy in (-1, 1):
        for k in range(4):
            c.box((-110 + k * 42, sy * 152 - 10, -230), (-90 + k * 42, sy * 152 + 10, -150))
    c = hs.cut()
    c.box((330, -110, -260), (460, 110, -120))                                 # gun port
    c = hs.cut()
    c.cyl((60, 100, -150), (60, 300, -150), 124, segs=32)                      # drum cut-out
    R.add(hs, HM, "Head")
    gun = Part("Guns", F, bevel=3)
    gun.box((250, -100, -250), (400, 100, -130))
    for sy in (-1, 1):
        gun.cyl((380, sy * 48, -190), (860, sy * 48, -190), 18, segs=16)
        gun.cyl((430, sy * 48, -190), (700, sy * 48, -190), 36, segs=20)
        gun.cyl((830, sy * 48, -190), (910, sy * 48, -190), 28, segs=16)
    c = gun.cut()
    for sy in (-1, 1):
        c.cyl((800, sy * 48, -190), (920, sy * 48, -190), 12, segs=12)
        for k in range(6):
            c.box((450 + k * 40, sy * 48 - 50, -197), (474 + k * 40, sy * 48 + 50, -183))
            c.box((450 + k * 40, sy * 48 - 7, -240), (474 + k * 40, sy * 48 + 7, -140))
    R.add(gun, HM, "Guns")
    for sy, nm in ((1, "L"), (-1, "R")):
        R.flash(f"Flash{nm}", HM @ T(915, sy * 48, -190) @ RZ(-90), "Guns")
    eye = Part("Eye", mats["eye"], bevel=0)
    eye.cyl((386, 0, -62), (392, 0, -62), 30, segs=24)
    for sy in (-1, 1):
        eye.cyl((372, sy * 80, -70), (378, sy * 80, -70), 11, segs=12)
    R.add(eye, HM, "Head")
    lens = Part("EyeLens", mats["lens"], bevel=3)
    lens.cyl((360, 0, -62), (388, 0, -62), 46, segs=28)
    R.add(lens, HM, "Head")
    belt = Part("Belt", mats["brass"], bevel=0)
    for k in range(14):
        a = math.radians(-60 + k * 14)
        belt.cyl((60 + 150 * math.cos(a), 170, -150 + 150 * math.sin(a)), (60 + 150 * math.cos(a), 250, -150 + 150 * math.sin(a)), 9, segs=8)
    R.add(belt, HM, "Head")
    return R


def build(coll, placements=None):
    mats = materials()
    P = placements or {}
    out = []
    out.append(spider(coll, P.get("spider", I4), mats))
    out.append(drone(coll, P.get("drone", T(0, 0, 1500)), mats))
    out.append(turret(coll, P.get("turret", T(0, 0, 2200)), mats, drop=P.get("turret_drop", 0),
                      aim_pitch=P.get("turret_pitch", -22)))
    return out


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if argv and argv[0] == "review":
        prefix = argv[1]
        bpy.ops.wm.read_factory_settings(use_empty=True)
        sc = bpy.context.scene
        robots = build(L.coll("Robots"), {"spider": T(0, 0, 0), "drone": T(4000, 0, 800), "turret": T(8000, 0, 1500)})
        print("robots:", sum(len(r.objs) for r in robots), "objects,",
              sum(len(o.data.polygons) for r in robots for o in r.objs if o.type == "MESH"), "faces")
        sc.render.engine = "BLENDER_EEVEE_NEXT"
        sc.eevee.taa_render_samples = 16
        sc.render.resolution_x, sc.render.resolution_y = 800, 620
        w = bpy.data.worlds.new("w")
        w.use_nodes = True
        w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.42, 0.44, 0.47, 1)
        sc.world = w
        sun = bpy.data.objects.new("s", bpy.data.lights.new("s", "SUN"))
        sun.data.energy = 3.5
        sc.collection.objects.link(sun)
        cd = bpy.data.cameras.new("c")
        cd.type = "ORTHO"
        cam = bpy.data.objects.new("c", cd)
        sc.collection.objects.link(cam)
        sc.camera = cam
        for name, ctr, scale in (("spider", (0, 0, 0.45), 2.3), ("drone", (4, 0, 0.8), 1.9), ("turret", (8.5, 0, 0.9), 2.3)):
            cd.ortho_scale = scale
            for view, d in (("front", (0.45, 1, 0.3)), ("side", (1, -0.25, 0.2)), ("top", (0.25, -0.45, 1))):
                dv = Vector(d).normalized()
                cam.location = Vector(ctr) + dv * 8
                cam.rotation_euler = (-dv).to_track_quat("-Z", "Y").to_euler()
                sun.rotation_euler = ((-dv + Vector((0.3, 0.2, -0.7))).normalized()).to_track_quat("-Z", "Y").to_euler()
                sc.render.filepath = f"{prefix}_{name}_{view}.png"
                bpy.ops.render.render(write_still=True)
    else:
        bpy.ops.wm.open_mainfile(filepath=os.path.join(L.ROOT, "scene.blend"))
        old = bpy.data.collections.get("Robots")
        if old:
            for o in list(old.all_objects):
                bpy.data.objects.remove(o)
            bpy.data.collections.remove(old)
        coll = L.coll("Robots")
        # spider: on the floor left of centre, turned toward the player; drone: high on the right; turret: ceiling, left
        place = {
            "spider": Matrix.Translation((-1.5, 4.5, 0)) @ RZ(-145),
            "drone": Matrix.Translation((2.25, 4.4, 2.55)) @ Matrix.Rotation(math.radians(36), 4, (-0.906, 0.423, 0))
        @ RZ(152) @ RY(6),
            "turret": Matrix.Translation((-2.25, 4.9, 3.5)) @ RZ(-28),
            "turret_drop": 1700, "turret_pitch": -14,
        }
        robots = build(coll, place)
        bpy.ops.wm.save_mainfile(compress=True)
        print("robots built:", sum(len(r.objs) for r in robots), "objects")
