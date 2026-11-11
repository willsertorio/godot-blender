"""FR-2 clips (runs on the saved blender/fr2.blend; re-runnable, keeps edits made to the model).

    blender -b blender/fr2.blend -P blender/scripts/anim_fr2.py

30 fps, one action per object ("<object>_Anim"), timeline markers at each clip start:
  Idle   f1-60    loop: hover bob + gentle sway, rotor tilt corrections (L/R out of phase), props 72 deg/frame
                  (12 turns per loop, seamless), eye pulses
  Shoot  f67-90   barrels spin up (f67-70) and fire f69-84 (flashes alternate L / R every frame), chassis
                  pitches back + recoils 5-6 cm with jitter, eye flares, settles by f90
  Fly    f97-156  loop: banking figure-eight around the origin (x +-25 cm, y +-12 cm), rolls into the turn,
                  nose down 10 deg, yaws with the heading, rotors tip 15 deg further forward with differential
                  tilt, props 108 deg/frame (18 turns per loop). Godot adds the real travel.
  Death  f163-207 hit jolt, eye flickers out, left prop flies off, right rotor ring breaks away tumbling,
                  chassis spins (~540 deg), noses down and drops 2 m, bounces once on f200-207
Animated: Chassis (body motion; FR2 root stays still), RotorL/R (tilt, rest -45 deg about X), PropL/R (spin,
local Z), GunBarrelsL/R (spin, local Y), MuzzleFlashL/R (scale 0/1, under Muzzle_L/R), NeonRed emission (eye).
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

FPS = 30
CLIPS = {"Idle": (1, 60), "Shoot": (67, 90), "Fly": (97, 156), "Death": (163, 207)}
TILT = math.radians(-45)
d = math.radians

sc = bpy.context.scene
sc.render.fps = FPS
sc.frame_start, sc.frame_end = 1, CLIPS["Death"][1]
O = bpy.data.objects


def key(ob, path, index, frame, value, interp="BEZIER", easing="AUTO"):
    if ob.animation_data is None:
        ob.animation_data_create()
    if ob.animation_data.action is None:
        ob.animation_data.action = bpy.data.actions.new(f"{ob.name}_Anim")
    fc = ob.animation_data.action.fcurves.find(path, index=index) or ob.animation_data.action.fcurves.new(path, index=index)
    kp = fc.keyframe_points.insert(frame, value, options={"FAST"})
    kp.interpolation = interp
    kp.easing = easing
    if interp == "BACK":
        kp.back = 1.3
    return kp


def flash_mesh():
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, segments=10, radius1=0.035, radius2=0.004, depth=0.14,
                          matrix=Matrix.Translation((0, 0.07, 0)) @ Matrix.Rotation(-math.pi / 2, 4, "X"))
    for a in (0, math.pi / 2, math.pi / 4, -math.pi / 4):
        r = Matrix.Rotation(a, 4, "Y")
        pts = [r @ Vector((math.cos(i * math.pi / 5) * (0.08 if i % 2 == 0 else 0.022) * 0.5, 0.01,
                           math.sin(i * math.pi / 5) * (0.08 if i % 2 == 0 else 0.022))) for i in range(10)]
        bm.faces.new([bm.verts.new(p) for p in pts])
    me = bpy.data.meshes.new("DroneMuzzleFlash")
    bm.to_mesh(me)
    bm.free()
    m = bpy.data.materials.get("DroneFlash") or bpy.data.materials.new("DroneFlash")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0, 0, 0, 1)
    b.inputs["Emission Color"].default_value = (1.0, 0.55, 0.25, 1)
    b.inputs["Emission Strength"].default_value = 30.0
    m.diffuse_color = (1.0, 0.55, 0.25, 1)
    me.materials.append(m)
    return me


# ---- reset ------------------------------------------------------------------------------------------------
chassis = O["Chassis"]
rot = {s: O[f"Rotor{s}"] for s in "LR"}
prop = {s: O[f"Prop{s}"] for s in "LR"}
barrels = {s: O[f"GunBarrels{s}"] for s in "LR"}
flash = {}
for s in "LR":
    f = O.get(f"MuzzleFlash{s}")
    if f is None:
        f = O.new(f"MuzzleFlash{s}", flash_mesh())
        chassis.users_collection[0].objects.link(f)
        f.parent = O[f"Muzzle_{s}"]
    flash[s] = f
eye_mat = bpy.data.materials["NeonRed"]
eye_node = eye_mat.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"]
for ob in [chassis, *rot.values(), *prop.values(), *barrels.values(), *flash.values()]:
    ob.animation_data_clear()
    ob.rotation_mode = "XYZ"
eye_mat.node_tree.animation_data_clear()
chassis.location = (0, 0, 0)
chassis.rotation_euler = (0, 0, 0)
for s in "LR":
    rot[s].rotation_euler = (TILT, 0, 0)
    prop[s].rotation_euler = (0, 0, 0)
    prop[s].location = (0, 0, 0)
    barrels[s].rotation_euler = (0, 0, 0)
    flash[s].location = (0, 0, 0)
    flash[s].scale = (0, 0, 0)
rot_rest = {s: rot[s].location.copy() for s in "LR"}


def eye(frame, strength, interp="BEZIER"):
    eye_node.default_value = strength
    eye_node.keyframe_insert("default_value", frame=frame)
    fc = eye_mat.node_tree.animation_data.action.fcurves[0]
    for kp in fc.keyframe_points:
        if int(kp.co.x) == frame:
            kp.interpolation = interp


def chassis_pose(frame, loc=(0, 0, 0), rot_deg=(0, 0, 0), interp="BEZIER", easing="AUTO"):
    for i in range(3):
        key(chassis, "location", i, frame, loc[i], interp, easing)
        key(chassis, "rotation_euler", i, frame, d(rot_deg[i]), interp, easing)


def spin(ob, axis, f0, f1, deg_per_frame, start=0.0):
    key(ob, "rotation_euler", axis, f0, start, "LINEAR")
    key(ob, "rotation_euler", axis, f1, start + d(deg_per_frame) * (f1 - f0), "LINEAR")


def flash_off(frame):
    for s in "LR":
        for i in range(3):
            key(flash[s], "scale", i, frame, 0.0, "CONSTANT")


# ---- Idle --------------------------------------------------------------------------------------------------
a, b = CLIPS["Idle"]
for f in list(range(a, b + 1, 2)) + [b]:
    t = (f - a) / 60.0
    tw = 2 * math.pi * t
    chassis_pose(f, (0, 0, 0.035 * math.sin(tw)),
                 (1.5 * math.sin(tw + 1), 1.2 * math.sin(2 * tw), 2.0 * math.sin(tw + 0.5)), "LINEAR")
    key(rot["L"], "rotation_euler", 0, f, TILT + d(4) * math.sin(tw), "LINEAR")
    key(rot["R"], "rotation_euler", 0, f, TILT + d(4) * math.sin(tw + math.pi), "LINEAR")
    eye(f, 8 + 4 * math.sin(2 * tw), "LINEAR")
for s in "LR":
    spin(prop[s], 2, a, b, 72 if s == "L" else -72)
    key(barrels[s], "rotation_euler", 1, a, 0.0, "CONSTANT")
flash_off(a)

# ---- Shoot -------------------------------------------------------------------------------------------------
a, b = CLIPS["Shoot"]
chassis_pose(a, interp="EXPO", easing="EASE_OUT")
chassis_pose(a + 3, (0, -0.05, 0.01), (5, 0, 0))
for k, f in enumerate(range(a + 5, a + 18, 2)):
    jit = 1 if k % 2 else -1
    chassis_pose(f, (0.004 * jit, -0.055 - 0.004 * (k % 2), 0.01 + 0.004 * jit), (4.5 + 0.8 * jit, 0.6 * jit, 0.5 * jit))
chassis_pose(a + 17, (0, -0.06, 0.01), (5, 0, 0), "BACK", "EASE_OUT")
chassis_pose(b, (0, 0, 0), (0, 0, 0))
for s in "LR":
    key(rot[s], "rotation_euler", 0, a, TILT)
    key(rot[s], "rotation_euler", 0, a + 4, TILT + d(6))
    key(rot[s], "rotation_euler", 0, a + 17, TILT + d(6))
    key(rot[s], "rotation_euler", 0, b, TILT)
    spin(prop[s], 2, a, b, 72 if s == "L" else -72)
    sign = 1 if s == "L" else -1
    key(barrels[s], "rotation_euler", 1, a, 0.0, "QUAD", "EASE_IN")
    key(barrels[s], "rotation_euler", 1, a + 3, sign * d(120), "LINEAR")
    key(barrels[s], "rotation_euler", 1, a + 17, sign * d(120 + 14 * 60), "QUAD", "EASE_OUT")
    key(barrels[s], "rotation_euler", 1, b, sign * d(120 + 14 * 60 + 150))
flash_off(a)
for k, f in enumerate(range(a + 2, a + 18)):
    s = "L" if k % 2 == 0 else "R"
    o = "R" if s == "L" else "L"
    for i in range(3):
        key(flash[s], "scale", i, f, 1.0 + 0.25 * ((k * 7) % 3) / 2, "CONSTANT")
        key(flash[o], "scale", i, f, 0.0, "CONSTANT")
    key(flash[s], "rotation_euler", 1, f, d((k * 37) % 90), "CONSTANT")
flash_off(a + 18)
eye(a, 8)
eye(a + 2, 30)
eye(a + 17, 30)
eye(b, 8)

# ---- Fly ---------------------------------------------------------------------------------------------------
a, b = CLIPS["Fly"]
for f in list(range(a, b + 1, 2)) + [b]:
    t = (f - a) / 60.0
    tw = 2 * math.pi * t
    chassis_pose(f, (0.25 * math.sin(tw), 0.12 * math.sin(2 * tw), 0.06 * math.sin(2 * tw + 0.7)),
                 (-10 + 3 * math.sin(2 * tw), -20 * math.sin(tw), 12 * math.cos(tw)), "LINEAR")
    key(rot["L"], "rotation_euler", 0, f, TILT - d(15) + d(6) * math.sin(tw), "LINEAR")
    key(rot["R"], "rotation_euler", 0, f, TILT - d(15) - d(6) * math.sin(tw), "LINEAR")
for s in "LR":
    spin(prop[s], 2, a, b, 108 if s == "L" else -108)
    key(barrels[s], "rotation_euler", 1, a, 0.0, "CONSTANT")
flash_off(a)
eye(a, 10, "CONSTANT")

# ---- Death -------------------------------------------------------------------------------------------------
a, b = CLIPS["Death"]
chassis_pose(a, interp="EXPO", easing="EASE_OUT")
chassis_pose(a + 3, (0.03, -0.02, 0.05), (-8, 6, 12))
chassis_pose(a + 10, (0.12, -0.06, -0.15), (-15, 22, 110), "QUAD", "EASE_IN")
chassis_pose(a + 37, (0.3, -0.2, -2.0), (-35, 40, 540), "QUAD", "EASE_OUT")
chassis_pose(a + 40, (0.32, -0.21, -1.88), (-28, 38, 552), "QUAD", "EASE_IN")
chassis_pose(b, (0.33, -0.22, -2.0), (-35, 38, 560))
# left prop flies off (in its rotor's frame: up the axis and outward), spinning down and tumbling
pl = prop["L"]
spin(pl, 2, a, a + 2, 72)
for i, (v2, v9, vb) in enumerate(((0, 0.25, 0.7), (0, 0.1, -0.3), (0, 0.55, 0.9))):
    key(pl, "location", i, a + 2, v2, "QUAD", "EASE_OUT")
    key(pl, "location", i, a + 12, v9, "QUAD", "EASE_IN")
    key(pl, "location", i, b, vb)
key(pl, "rotation_euler", 2, a + 2, d(144), "QUAD", "EASE_OUT")
key(pl, "rotation_euler", 2, b, d(144 + 900))
key(pl, "rotation_euler", 0, a + 2, 0.0)
key(pl, "rotation_euler", 0, b, d(540))
# right prop spins down inside its ring
key(prop["R"], "rotation_euler", 2, a, 0.0, "QUAD", "EASE_OUT")
key(prop["R"], "rotation_euler", 2, a + 20, d(-700))
# right rotor ring breaks away (chassis frame), tumbling
rr = rot["R"]
r0 = rot_rest["R"]
key(rr, "rotation_euler", 0, a, TILT)
for i, (v5, v15, vb) in enumerate(((0.0, 0.0, 0.0), (0.45, -0.15, 0.3), (1.3, -0.6, -0.1))):
    key(rr, "location", i, a + 5, r0[i] + v5, "QUAD", "EASE_OUT")
    key(rr, "location", i, a + 15, r0[i] + v15)
    key(rr, "location", i, b, r0[i] + vb)
key(rr, "rotation_euler", 0, a + 5, TILT)
key(rr, "rotation_euler", 0, b, TILT + d(620))
key(rr, "rotation_euler", 1, a + 5, 0.0)
key(rr, "rotation_euler", 1, b, d(250))
key(rot["L"], "rotation_euler", 0, a, TILT)
key(rot["L"], "rotation_euler", 0, a + 8, TILT + d(25))
key(rot["L"], "rotation_euler", 0, b, TILT + d(30))
for s in "LR":
    sign = 1 if s == "L" else -1
    key(barrels[s], "rotation_euler", 1, a, 0.0, "QUAD", "EASE_OUT")
    key(barrels[s], "rotation_euler", 1, a + 15, sign * d(200))
flash_off(a)
for f, v in ((a, 8), (a + 1, 30), (a + 2, 0), (a + 3, 20), (a + 4, 0), (a + 5, 12), (a + 7, 0)):
    eye(f, v, "CONSTANT")
eye(b, 0, "CONSTANT")

# Markers
for name, (a, b) in CLIPS.items():
    mk = sc.timeline_markers.get(name) or sc.timeline_markers.new(name, frame=a)
    mk.frame = a
sc.frame_set(1)
bpy.ops.wm.save_mainfile()
print("animated", bpy.data.filepath, {k: v for k, v in CLIPS.items()})
