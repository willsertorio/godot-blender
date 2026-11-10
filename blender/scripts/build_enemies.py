"""Hostile constructs: turret.glb, brawler.glb, pursuer.glb.

    blender -b -P blender/scripts/build_enemies.py -- assets/models

All face +Y (Godot -Z), origin on the floor. Armour is dark; the hostile identity is carried
by NeonRed (enemies only). Node contract with scripts/enemies/*.gd:
  turret : "Head" (pivot at 1.55 m, yaws/pitches toward the player), "Muzzle" under Head
  brawler: "Body" (yawed and bobbed by code)
  pursuer: "Body" (pivot at its centre; code sets its hover height), "Core" (pulses), "Muzzle"
"""
import math
import os
import sys

sys.path.append(os.path.dirname(__file__))
import bpy  # noqa: E402
from lib_hardsurface import MATERIALS, Part, build, export_glb, reset_scene  # noqa: E402

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "assets/models"
MATERIALS.update({
    "EnemyArmor": dict(color=(0.07, 0.05, 0.055), metallic=0.5, rough=0.45),
    "EnemyMetal": dict(color=(0.2, 0.2, 0.21), metallic=0.8, rough=0.4),
})
A, M, R = "EnemyArmor", "EnemyMetal", "NeonRed"


def empty(name, parent, loc=(0, 0, 0)):
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    e.parent = parent
    e.location = loc
    return e


def turret():
    root = empty("Turret", None)
    base = build("Base", [
        Part((-0.62, -0.62, 0), (0.62, 0.62, 0.22), A, kind="cyl", segments=8, bevel=0.03),
        Part((-0.5, -0.5, 0.22), (0.5, 0.5, 0.3), M, kind="cyl", segments=8, bevel=0.015),
        Part((-0.65, -0.65, 0.1), (0.65, 0.65, 0.14), R, kind="cyl", segments=8, bevel=0),
        Part((-0.36, -0.36, 1.22), (0.36, 0.36, 1.26), R, kind="cyl", segments=8, bevel=0),
        Part((-0.2, -0.2, 0.3), (0.2, 0.2, 1.25), M, kind="cyl", segments=8, bevel=0.01),
        Part((-0.34, -0.34, 1.18), (0.34, 0.34, 1.32), A, kind="cyl", segments=8, bevel=0.02),
        # Armoured fins around the mast.
        *[Part((-0.04, 0.16, 0.3), (0.04, 0.42, 0.95), A, rot=(0, 0, a), bevel=0.012) for a in (0, math.pi / 2, math.pi, -math.pi / 2)],
    ])
    base.parent = root
    head = empty("Head", root, (0, 0, 1.55))
    h = build("HeadMesh", [
        Part((-0.32, -0.32, -0.2), (0.32, 0.34, 0.2), A, bevel=0.06),
        Part((-0.37, -0.22, -0.13), (0.37, 0.2, 0.13), M, bevel=0.025),           # cheek pods
        Part((-0.24, 0.335, 0.02), (0.24, 0.36, 0.08), R, bevel=0),               # visor slit
        Part((-0.335, -0.3, 0.11), (-0.32, 0.3, 0.14), R, bevel=0),               # side trims
        Part((0.32, -0.3, 0.11), (0.335, 0.3, 0.14), R, bevel=0),
        Part((-0.05, -0.36, 0.2), (0.05, 0.2, 0.25), A, bevel=0.015),             # dorsal ridge
        Part((-0.15, 0.3, -0.13), (-0.05, 0.86, -0.03), M, kind="cyl", axis="Y", segments=10, bevel=0.006),
        Part((0.05, 0.3, -0.13), (0.15, 0.86, -0.03), M, kind="cyl", axis="Y", segments=10, bevel=0.006),
        Part((-0.16, 0.8, -0.14), (-0.04, 0.83, -0.02), R, kind="cyl", axis="Y", segments=10, bevel=0),
        Part((0.04, 0.8, -0.14), (0.16, 0.83, -0.02), R, kind="cyl", axis="Y", segments=10, bevel=0),
    ])
    h.parent = head
    empty("Muzzle", head, (0, 0.9, -0.08))
    return root


def brawler():
    root = empty("Brawler", None)
    body = empty("Body", root)
    b = build("BodyMesh", [
        # Tracks.
        Part((-0.52, -0.5, 0.0), (-0.3, 0.5, 0.36), M, bevel=0.05),
        Part((0.3, -0.5, 0.0), (0.52, 0.5, 0.36), M, bevel=0.05),
        Part((-0.535, -0.4, 0.15), (-0.515, 0.4, 0.19), R, bevel=0),
        Part((0.515, -0.4, 0.15), (0.535, 0.4, 0.19), R, bevel=0),
        # Hull, sloped glacis and shoulders.
        Part((-0.36, -0.42, 0.3), (0.36, 0.3, 1.0), A, bevel=0.06),
        Part((-0.34, 0.12, 0.42), (0.34, 0.5, 0.95), A, rot=(math.radians(-28), 0, 0), bevel=0.04),
        Part((-0.5, -0.3, 0.78), (-0.24, 0.2, 1.08), A, rot=(0, math.radians(18), 0), bevel=0.04),
        Part((0.24, -0.3, 0.78), (0.5, 0.2, 1.08), A, rot=(0, math.radians(-18), 0), bevel=0.04),
        Part((-0.26, 0.38, 0.8), (0.26, 0.42, 0.86), R, rot=(math.radians(-28), 0, 0), bevel=0),   # visor
        Part((-0.14, -0.45, 0.62), (0.14, -0.4, 0.92), R, bevel=0),                                  # rear vent
        Part((-0.375, -0.4, 0.94), (-0.355, 0.26, 0.97), R, bevel=0),                                # hull edge lines
        Part((0.355, -0.4, 0.94), (0.375, 0.26, 0.97), R, bevel=0),
        # Ram blades.
        *[Part((x - 0.035, 0.3, 0.28), (x + 0.035, 0.85, 0.36), R, rot=(math.radians(-14), 0, 0), bevel=0)
          for x in (-0.26, -0.09, 0.09, 0.26)],
    ])
    b.parent = body
    return root


def pursuer():
    root = empty("Pursuer", None)
    body = empty("Body", root, (0, 0, 2.1))
    b = build("BodyMesh", [
        Part((-0.46, -0.46, -0.42), (0.46, 0.46, 0.42), A, kind="gem", bevel=0.012),
        Part((-0.82, -0.16, -0.04), (-0.4, 0.22, 0.04), M, bevel=0.015),
        Part((0.4, -0.16, -0.04), (0.82, 0.22, 0.04), M, bevel=0.015),
        Part((-0.83, -0.17, -0.015), (-0.7, 0.23, 0.015), R, bevel=0),
        Part((0.7, -0.17, -0.015), (0.83, 0.23, 0.015), R, bevel=0),
        # Two upright crossed rings: read as a ring from any side.
        Part((-0.64, -0.64, -0.03), (0.64, 0.64, 0.03), R, kind="torus", segments=12, rot=(math.pi / 2, 0, 0), bevel=0),
        Part((-0.64, -0.64, -0.03), (0.64, 0.64, 0.03), R, kind="torus", segments=12, rot=(0, math.pi / 2, 0), bevel=0),
        Part((-0.1, -0.48, -0.1), (0.1, -0.34, 0.1), M, kind="cyl", axis="Y", segments=8, bevel=0.01),  # thruster
    ])
    b.parent = body
    core = build("Core", [Part((-0.2, -0.2, -0.2), (0.2, 0.2, 0.2), R, kind="gem", bevel=0)])
    core.parent = body
    core.location = (0, 0.36, 0)
    empty("Muzzle", body, (0, 0.58, 0))
    return root


os.makedirs(OUT, exist_ok=True)
for fn, name in ((turret, "turret"), (brawler, "brawler"), (pursuer, "pursuer")):
    reset_scene()
    root = fn()
    export_glb(os.path.join(OUT, name + ".glb"), [root])
