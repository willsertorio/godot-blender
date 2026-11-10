"""First-person arms in the Quaternius style: chunky gloves, armoured sleeves (arms.glb).

    blender -b -P blender/scripts/build_arms.py -- assets/models

Rigid-part rig (no skinning): each arm is a hierarchy Godot can pose and animate.
  ArmR / ArmL (empty, origin = the hand's grip point)
    Hand<side>    palm + curled fingers + thumb + cuff, closed around a vertical grip at the origin
    Wrist<side>   (empty at the wrist) -> Forearm<side> sleeve running back along -Y
Faces +Y (barrel direction). Flat colours sampled from the Quaternius gun palette.
"""
import math
import os
import sys

sys.path.append(os.path.dirname(__file__))
import bpy  # noqa: E402
from lib_hardsurface import MATERIALS, Part, build, export_glb, reset_scene  # noqa: E402

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "assets/models"
MATERIALS.update({
    "ArmSuit": dict(color=(0.11, 0.12, 0.14), metallic=0.0, rough=0.75),
    "ArmGlove": dict(color=(0.045, 0.045, 0.05), metallic=0.0, rough=0.6),
    "ArmPlate": dict(color=(0.55, 0.57, 0.6), metallic=0.35, rough=0.45),
    "ArmAccent": dict(color=(0.95, 0.42, 0.08), metallic=0.1, rough=0.5),
})


def empty(name, parent=None, loc=(0, 0, 0), rot=(0, 0, 0)):
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    e.parent = parent
    e.location = loc
    e.rotation_euler = rot
    return e


def arm(side):
    """side = 1 (right) or -1 (left). The grip is a vertical bar at the origin; the palm sits
    on the outer side (+x for the right hand), fingers wrap the front (+y), thumb over the top."""
    s = side
    n = "R" if s > 0 else "L"
    root = empty("Arm" + n)
    X = lambda a, b: (min(s * a, s * b), max(s * a, s * b))  # mirror an x-interval

    parts = []
    # Palm block on the outer side of the grip, back of the hand facing out.
    x0, x1 = X(0.012, 0.058)
    parts.append(Part((x0, -0.045, -0.06), (x1, 0.035, 0.045), "ArmGlove", bevel=0.012))
    # Knuckle armour plate + orange accent on the back of the hand.
    x0, x1 = X(0.05, 0.066)
    parts.append(Part((x0, -0.035, -0.045), (x1, 0.03, 0.035), "ArmPlate", bevel=0.006))
    x0, x1 = X(0.064, 0.07)
    parts.append(Part((x0, -0.02, -0.03), (x1, 0.015, 0.02), "ArmAccent", bevel=0))
    # Four curled fingers wrapping the front of the grip (index on top).
    for i in range(4):
        z = 0.03 - i * 0.026
        x0, x1 = X(-0.03, 0.03)
        parts.append(Part((x0, 0.022, z - 0.011), (x1, 0.05, z + 0.011), "ArmGlove", bevel=0.009))
        x0, x1 = X(-0.034, -0.012)
        parts.append(Part((x0, -0.0, z - 0.011), (x1, 0.04, z + 0.011), "ArmGlove", bevel=0.008))
    # Thumb over the top inner side.
    x0, x1 = X(-0.03, 0.005)
    parts.append(Part((x0, -0.035, 0.04), (x1, 0.03, 0.066), "ArmGlove", bevel=0.01))
    hand = build("Hand" + n, parts)
    hand.parent = root

    # Wrist pivot behind and below the palm; the forearm runs back (-Y) and down, toward the
    # bottom corner of the screen.
    # Rx(+55 deg) turns the sleeve's -Y axis down (z < 0); Rz splays it outward.
    wrist = empty("Wrist" + n, root, loc=(s * 0.04, -0.05, -0.05),
                  rot=(math.radians(58), 0, math.radians(-22) * s))
    fore = build("Forearm" + n, [
        Part((-0.052, -0.06, -0.052), (0.052, 0.02, 0.052), "ArmGlove", kind="cyl", axis="Y", segments=12, bevel=0.01),
        Part((-0.058, -0.42, -0.058), (0.058, -0.05, 0.058), "ArmSuit", kind="cyl", axis="Y", segments=12, bevel=0.01),
        # Vambrace armour on top of the forearm, orange stripe.
        Part((-0.045, -0.34, 0.035), (0.045, -0.08, 0.07), "ArmPlate", bevel=0.012),
        Part((-0.012, -0.32, 0.068), (0.012, -0.1, 0.074), "ArmAccent", bevel=0),
        Part((-0.06, -0.075, -0.06), (0.06, -0.055, 0.06), "ArmAccent", kind="cyl", axis="Y", segments=12, bevel=0),
    ])
    fore.parent = wrist
    return root


reset_scene()
r = arm(1)
l = arm(-1)
os.makedirs(OUT, exist_ok=True)
export_glb(os.path.join(OUT, "arms.glb"), [r, l])
