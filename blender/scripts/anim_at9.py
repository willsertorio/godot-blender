"""AT-9 turret clips (runs on the saved blender/at9.blend; keeps edits made in the file).

    blender -b blender/at9.blend -P blender/scripts/anim_at9.py

30 fps, one action per object ("<object>_Anim"), timeline markers per clip:
  Idle    f1-60    (loop) slow yaw scan +-12 deg, pitch drift, arm breathing, eye flicker
  Shoot   f67-90   barrels spin up (f67-73), burst f73-86: alternating muzzle flashes L/R, housing kicks back
                   on every shot, eyes flare; barrels stop on a multiple of 60 deg (looks like rest)
  Aim     f97-144  yaw sweep 0 -> +45 -> 0 -> -45 -> 0, pitch 0 -> -25 (down) -> +15 (up) -> 0
  Death   f151-195 eyes flicker out, drums (f156) then gun pods (f158) break off and fall to the floor
                   (5 m below the ceiling mount: Z = -5), housing drops nose-down and swings, arm sags
Procedural drive in Godot (pivots, rotation axis in the parent's frame):
  Yaw (Z, any angle) -> ArmUpper / ArmLower (X, the arm; small) -> Pitch (X: + = guns up; use -35..+20 deg)
  Barrels_L / Barrels_R (local Y = barrel axis), EyeGlow (scale 0 = eyes off), MuzzleFlash_L/_R (scale 0/1).
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

FPS = 30
CLIPS = {"Idle": (1, 60), "Shoot": (67, 90), "Aim": (97, 144), "Death": (151, 195)}
FLOOR_Z = -5.0
G = 9.8
sc = bpy.context.scene
sc.render.fps = FPS
sc.frame_start, sc.frame_end = 1, 195
O = bpy.data.objects
d = math.radians


def clear(ob):
    if ob.animation_data:
        ob.animation_data_clear()


def keys(ob, path, index, frames, interp="BEZIER", easing="AUTO"):
    if ob.animation_data is None:
        ob.animation_data_create()
    if ob.animation_data.action is None:
        ob.animation_data.action = bpy.data.actions.new(f"{ob.name}_Anim")
    fc = ob.animation_data.action.fcurves.find(path, index=index) or ob.animation_data.action.fcurves.new(path, index=index)
    for k in frames:
        kp = fc.keyframe_points.insert(k[0], k[1], options={"FAST"})
        kp.interpolation = k[2] if len(k) > 2 else interp
        kp.easing = k[3] if len(k) > 3 else easing
        if kp.interpolation == "BACK":
            kp.back = 1.6
    fc.update()


def flash_mesh(size):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, segments=10, radius1=0.05 * size, radius2=0.008 * size, depth=0.22 * size,
                          matrix=Matrix.Translation((0, 0.11 * size, 0)) @ Matrix.Rotation(-math.pi / 2, 4, "X"))
    for a in (0, math.pi / 2, math.pi / 4, -math.pi / 4):
        r = Matrix.Rotation(a, 4, "Y")
        pts = [r @ Vector((math.cos(i * math.pi / 5) * (0.12 if i % 2 == 0 else 0.035) * size * 0.5, 0.02 * size,
                           math.sin(i * math.pi / 5) * (0.12 if i % 2 == 0 else 0.035) * size)) for i in range(10)]
        bm.faces.new([bm.verts.new(p) for p in pts])
    me = bpy.data.meshes.new("TurretFlash")
    bm.to_mesh(me)
    bm.free()
    m = bpy.data.materials.get("TurretFlash") or bpy.data.materials.new("TurretFlash")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0, 0, 0, 1)
    b.inputs["Emission Color"].default_value = (1.0, 0.75, 0.35, 1)
    b.inputs["Emission Strength"].default_value = 25.0
    m.diffuse_color = (1.0, 0.75, 0.35, 1)
    me.materials.append(m)
    return me


yaw, up, lo, pitch, eg = O["Yaw"], O["ArmUpper"], O["ArmLower"], O["Pitch"], O["EyeGlow"]
bars = {s: O[f"Barrels_{s}"] for s in "LR"}
pods = {s: O[f"GunPod_{s}"] for s in "LR"}
drums = {s: O[f"AmmoDrum_{s}"] for s in "LR"}
for ob in [yaw, up, lo, pitch, eg, *bars.values(), *pods.values(), *drums.values()]:
    clear(ob)
    ob.rotation_mode = "XYZ"
sc.frame_set(1)
rest = {ob.name: (ob.location.copy(), ob.rotation_euler.copy(), ob.scale.copy()) for ob in
        [yaw, up, lo, pitch, eg, *bars.values(), *pods.values(), *drums.values()]}


def rk(ob, idx, frames, **kw):   # rotation keys as deltas from rest (degrees)
    r0 = rest[ob.name][1][idx]
    keys(ob, "rotation_euler", idx, [(f, r0 + d(v), *rest_args) for f, v, *rest_args in frames], **kw)


def lk(ob, idx, frames, **kw):   # location keys as deltas from rest (m, parent frame)
    l0 = rest[ob.name][0][idx]
    keys(ob, "location", idx, [(f, l0 + v, *rest_args) for f, v, *rest_args in frames], **kw)


def sk(ob, frames):              # uniform scale keys (constant)
    for i in range(3):
        keys(ob, "scale", i, [(f, v, "CONSTANT") for f, v in frames])


# Muzzle flashes (children of the muzzle empties, hidden = scale 0).
flashes = {}
for s in "LR":
    fl = O.get(f"MuzzleFlash_{s}")
    if fl is None:
        fl = O.new(f"MuzzleFlash_{s}", flash_mesh(1.6))
        O["AT9"].users_collection[0].objects.link(fl)
        fl.parent = O[f"Muzzle_{s}"]
    clear(fl)
    fl.location = (0, 0, 0)
    flashes[s] = fl

# ---- Idle (1-60, loops) ----------------------------------------------------------------------------------------
rk(yaw, 2, [(1, 0), (16, 12), (31, 0), (46, -12), (60, 0)])
rk(pitch, 0, [(1, 0), (21, -3), (41, 2), (60, 0)])
rk(lo, 0, [(1, 0), (31, 1.5), (60, 0)])
sk(eg, [(1, 1.0), (20, 1.0), (21, 0.7), (23, 1.0), (41, 1.0), (42, 0.85), (44, 1.0), (60, 1.0)])
for s in "LR":
    sk(flashes[s], [(1, 0.0)])
    rk(bars[s], 1, [(1, 0, "CONSTANT")])

# ---- Shoot (67-90) ------------------------------------------------------------------------------------------------
a, S0, S1 = 67, 67, 90
for ob, idx in ((yaw, 2), (pitch, 0), (lo, 0)):
    rk(ob, idx, [(S0, 0), (S1, 0)])
lk(pitch, 1, [(S0, 0.0)])
ang, w = 0.0, 0.0
frames = []
for f in range(S0, S1 + 1):
    frames.append((f, ang))
    w = min(32.0, w + 32.0 / 6) if f < 86 else max(0.0, w - 32.0 / 4)
    ang += w / FPS
step = math.pi / 3
frames[-1] = (S1, round(frames[-1][1] / step) * step)
for s in "LR":
    keys(bars[s], "rotation_euler", 1, [(f, rest[bars[s].name][1][1] + v, "LINEAR") for f, v in frames[:-1]]
         + [(S1, rest[bars[s].name][1][1] + frames[-1][1], "CONSTANT")])
kick = []
for f in range(73, 87):
    kick.append((f, -0.03 if f % 2 == 1 else -0.008, "LINEAR"))
lk(pitch, 1, kick + [(87, 0.0), (S1, 0.0)])
for s, parity in (("L", 1), ("R", 0)):
    seq = [(S0, 0.0)] + [(f, 1.0 if f % 2 == parity else 0.0) for f in range(73, 87)] + [(87, 0.0)]
    sk(flashes[s], seq)
    keys(flashes[s], "rotation_euler", 1, [(f, d((f * 47) % 90), "CONSTANT") for f in range(73, 87)])
sk(eg, [(S0, 1.0), (70, 1.35), (88, 1.35), (S1, 1.0)])

# ---- Aim (97-144) -----------------------------------------------------------------------------------------------------
A0, A1 = 97, 144
for s in "LR":
    rk(bars[s], 1, [(A0, 0, "CONSTANT")])
rk(yaw, 2, [(A0, 0), (109, 45), (121, 0), (133, -45), (A1, 0)])
rk(pitch, 0, [(A0, 0), (103, 0), (115, -25), (127, 15), (139, 0), (A1, 0)])
rk(lo, 0, [(A0, 0), (A1, 0)])
lk(pitch, 1, [(A0, 0.0)])
sk(eg, [(A0, 1.0)])

# ---- Death (151-195) ------------------------------------------------------------------------------------------------
D0 = 151
rk(yaw, 2, [(D0, 0), (153, 9, "BACK", "EASE_OUT"), (160, 4), (170, 6)])
rk(lo, 0, [(D0, 0), (156, 0, "BACK", "EASE_OUT"), (162, -18), (175, -16)])
rk(up, 0, [(D0, 0), (157, 0, "BACK", "EASE_OUT"), (164, 8), (178, 6)])
rk(pitch, 0, [(D0, 0), (156, 0, "QUAD", "EASE_IN"), (160, -62), (165, -44), (170, -56), (176, -48), (184, -52)])
rk(pitch, 2, [(D0, 0), (158, 0), (164, 9), (172, -5), (182, 3)])
lk(pitch, 1, [(D0, 0.0)])
sk(eg, [(D0, 1.0), (152, 0.4), (153, 1.0), (155, 0.2), (156, 0.8), (158, 0.0)])
for s in "LR":
    rk(bars[s], 1, [(D0, 0, "CONSTANT")])
    rk(bars[s], 1, [(D0 + 1, 0), (158, 160, "QUAD", "EASE_OUT"), (175, 300)])   # spins down as it falls


def fall(ob, start, v0, spin, radius):
    """Detach `ob` at frame `start`: free fall with spin, bounce once on the floor, settle. Keys are written
    in the parent's frame on every frame, so the motion is straight down in the world whatever the parent does."""
    sc.frame_set(start)
    m0 = ob.matrix_world.copy()
    p0, q0 = m0.to_translation(), m0.to_quaternion()
    # rest keys before the break
    for f in (D0, start - 1):
        sc.frame_set(f)
        ob.keyframe_insert("location", frame=f)
        ob.keyframe_insert("rotation_euler", frame=f)
    pz, vz = p0.z, v0.z
    pxy = Vector((p0.x, p0.y))
    vxy = Vector((v0.x, v0.y))
    ang = Vector((0, 0, 0))
    wv = Vector(spin)
    prev = None
    for f in range(start, 196):
        dt = 1 / FPS
        if f > start:
            vz -= G * dt
            pz += vz * dt
            pxy += vxy * dt
            ang += wv * dt
            if pz < FLOOR_Z + radius:
                pz = FLOOR_Z + radius
                vz = -vz * 0.3 if abs(vz) > 1.0 else 0.0
                vxy *= 0.5
                wv *= 0.4
        sc.frame_set(f)
        from mathutils import Euler
        q = Euler(ang).to_quaternion() @ q0
        world = Matrix.Translation((pxy.x, pxy.y, pz)) @ q.to_matrix().to_4x4() @ Matrix.Diagonal(m0.to_scale()).to_4x4()
        ob.matrix_world = world
        e = ob.rotation_euler.copy()
        if prev is not None:
            e.make_compatible(prev)
            ob.rotation_euler = e
        prev = e
        ob.keyframe_insert("location", frame=f)
        ob.keyframe_insert("rotation_euler", frame=f)


for ob in (*pods.values(), *drums.values()):   # earlier clips: parts at rest
    for f in (1, A1):
        sc.frame_set(f)
        ob.location, ob.rotation_euler = rest[ob.name][0], rest[ob.name][1]
        ob.keyframe_insert("location", frame=f)
        ob.keyframe_insert("rotation_euler", frame=f)
fall(drums["L"], 156, Vector((-0.4, 0.3, 0.2)), (4, 0, 2), 0.13)
fall(drums["R"], 156, Vector((0.5, 0.1, 0.1)), (-3, 1, -2), 0.13)
fall(pods["L"], 158, Vector((-0.7, 0.6, 0.5)), (2.5, 1.5, 3.0), 0.16)
fall(pods["R"], 159, Vector((0.8, 0.4, 0.4)), (-2.0, -2.0, 1.5), 0.16)

for name, (f0, f1) in CLIPS.items():
    mk = sc.timeline_markers.get(name) or sc.timeline_markers.new(name, frame=f0)
    mk.frame = f0
sc.frame_set(1)
bpy.ops.wm.save_mainfile()
print("animated", bpy.data.filepath, CLIPS)
