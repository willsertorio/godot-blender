"""The game's props in the V2 look (the robots' white armour paint, dark frames, hazard stripes, status lights):
a supply crate whose lid opens, what comes out of it (ammunition, a health cell, a med kit), and the exit gate.

    blender -b -P v2/scripts/build_props.py          # -> v2/props.blend + assets/models/v2/props.glb

Blender metres, z up, each prop's origin at its base, its front toward -Y (Godot +Z: toward whoever stands before
it). Every prop is an empty (`Crate`, `AmmoBox`, `HealthCell`, `MedKit`, `ExitGate`) with its parts under it; the
crate's lid hangs from `Crate_Lid`, an empty on its hinge line. The props stand side by side in the file; the game
takes each by name and puts it where it wants it (v2_game.gd).
The materials are only names here: the game builds them (`V2Assets`: the robots' materials of materials.json, and
`ExitLight` / `ExitField` of its own).
"""
import math
import os

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "assets", "models", "v2", "props.glb")
BLEND = os.path.join(HERE, "..", "props.blend")

bpy.ops.wm.read_factory_settings(use_empty=True)
COLOURS = {  # what the .blend shows (base colour, emission strength)
    "RArmor": ((0.85, 0.86, 0.88), 0), "RFrame": ((0.03, 0.03, 0.035), 0), "RSteel": ((0.6, 0.6, 0.62), 0),
    "Hazard": ((0.8, 0.55, 0.02), 0), "SignGreen": ((0.2, 1.0, 0.45), 5), "StatusOrange": ((1.0, 0.45, 0.1), 6),
    "ScreenCyan": ((0.15, 0.85, 1.0), 5), "RBrass": ((0.75, 0.55, 0.22), 0), "ExitLight": ((0.7, 0.55, 1.0), 6),
    "ExitField": ((0.5, 0.35, 1.0), 2), "RRed": ((0.5, 0.03, 0.02), 0),
}
MATS = {}
for name, (col, emit) in COLOURS.items():
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*col, 1)
    if emit:
        b.inputs["Emission Color"].default_value = (*col, 1)
        b.inputs["Emission Strength"].default_value = emit
    MATS[name] = m


def empty(name, at=(0, 0, 0), parent=None):
    ob = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = parent
    ob.location = at
    return ob


class Part:
    """Boxes gathered into one mesh object under `parent` (coordinates in the parent's frame)."""

    def __init__(self, name, mat, parent, bevel=0.0):
        self.name, self.mat, self.parent, self.bevel = name, mat, parent, bevel
        self.verts, self.faces = [], []

    def box(self, lo, hi):
        (x0, y0, z0), (x1, y1, z1) = lo, hi
        n = len(self.verts)
        self.verts += [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
        self.faces += [tuple(n + i for i in f) for f in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7))]
        return self

    def done(self):
        me = bpy.data.meshes.new(self.name)
        me.from_pydata(self.verts, [], self.faces)
        me.materials.append(MATS[self.mat])
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        ob.parent = self.parent
        if self.bevel:
            md = ob.modifiers.new("Bevel", "BEVEL")
            md.width, md.segments, md.limit_method, md.angle_limit = self.bevel, 2, "ANGLE", math.radians(40)
        return ob


def cross(part, cx, y0, y1, cz, arm, thick):
    """A + of two bars on a face at y0..y1."""
    part.box((cx - arm, y0, cz - thick), (cx + arm, y1, cz + thick))
    part.box((cx - thick, y0, cz - arm), (cx + thick, y1, cz + arm))


# ------------------------------------------------------------------ supply crate: 0.9 wide, 0.56 deep, 0.58 high shut
W, D, H = 0.45, 0.28, 0.5
crate = empty("Crate", (0, 0, 0))
Part("Crate_Body", "RArmor", crate, 0.012).box((-W + 0.03, -D + 0.03, 0.06), (W - 0.03, D - 0.03, H)).done()
fr = Part("Crate_Frame", "RFrame", crate, 0.006)
for sx in (-1, 1):
    for sy in (-1, 1):                                              # corner posts and feet
        fr.box((sx * W - 0.04 * (sx > 0) - 0.0 * (sx < 0), sy * D - 0.04 * (sy > 0), 0.0),
               (sx * W + 0.04 * (sx < 0), sy * D + 0.04 * (sy < 0), H + 0.005))
fr.box((-W, -D, 0.0), (W, D, 0.06))                                 # plinth
fr.box((-0.16, -D - 0.012, 0.3), (0.16, -D + 0.03, 0.42))           # latch plate on the front
fr.done()
Part("Crate_Band", "Hazard", crate).box((-W + 0.045, -D + 0.022, 0.1), (W - 0.045, -D + 0.032, 0.18)) \
    .box((-W + 0.045, D - 0.032, 0.1), (W - 0.045, D - 0.022, 0.18)).done()
# the status light on the latch: green = something inside (the game swaps it when the crate is empty)
Part("Crate_Light", "SignGreen", crate).box((-0.12, -D - 0.018, 0.345), (0.12, -D - 0.008, 0.375)).done()
Part("Crate_Inside", "RFrame", crate).box((-W + 0.06, -D + 0.06, H - 0.02), (W - 0.06, D - 0.06, H + 0.004)).done()
lid = empty("Crate_Lid", (0, D - 0.02, H + 0.01), crate)             # the hinge line: the back top edge
Part("Crate_LidShell", "RArmor", lid, 0.012).box((-W + 0.01, -2 * D + 0.03, 0.0), (W - 0.01, 0.01, 0.07)).done()
lf = Part("Crate_LidFrame", "RFrame", lid, 0.006)
lf.box((-W, -2 * D + 0.02, -0.005), (-W + 0.05, 0.02, 0.075)).box((W - 0.05, -2 * D + 0.02, -0.005), (W, 0.02, 0.075))
lf.box((-0.1, -2 * D + 0.005, 0.01), (0.1, -2 * D + 0.04, 0.06))    # handle
lf.done()
Part("Crate_LidBand", "Hazard", lid).box((-W + 0.06, -2 * D + 0.08, 0.068), (W - 0.06, -2 * D + 0.14, 0.073)).done()

# ------------------------------------------------------------------ ammunition box: 0.3 x 0.16 x 0.19
ammo = empty("AmmoBox", (1.5, 0, 0))
Part("Ammo_Body", "RFrame", ammo, 0.008).box((-0.15, -0.08, 0.0), (0.15, 0.08, 0.15)).done()
Part("Ammo_Lid", "RSteel", ammo, 0.006).box((-0.155, -0.085, 0.15), (0.155, 0.085, 0.175)) \
    .box((-0.06, -0.012, 0.175), (0.06, 0.012, 0.2)).done()
Part("Ammo_Label", "StatusOrange", ammo).box((-0.1, -0.084, 0.05), (0.1, -0.08, 0.1)).box((-0.1, 0.08, 0.05), (0.1, 0.084, 0.1)).done()
br = Part("Ammo_Rounds", "RBrass", ammo, 0.003)
for i in range(5):
    br.box((-0.12 + i * 0.055, -0.094, 0.115), (-0.09 + i * 0.055, -0.08, 0.14))
br.done()

# ------------------------------------------------------------------ health cell: a canister, 0.16 x 0.16 x 0.3
cell = empty("HealthCell", (2.5, 0, 0))
Part("Cell_Body", "RArmor", cell, 0.02).box((-0.07, -0.07, 0.03), (0.07, 0.07, 0.27)).done()
Part("Cell_Caps", "RFrame", cell, 0.01).box((-0.08, -0.08, 0.0), (0.08, 0.08, 0.04)).box((-0.08, -0.08, 0.26), (0.08, 0.08, 0.3)) \
    .box((-0.02, -0.02, 0.3), (0.02, 0.02, 0.325)).done()
cg = Part("Cell_Glow", "SignGreen", cell)
for sy in (-1, 1):
    cross(cg, 0.0, sy * 0.071 - 0.002, sy * 0.071 + 0.002, 0.15, 0.045, 0.014)
cg.box((-0.073, -0.014, 0.105), (-0.069, 0.014, 0.195)).box((0.069, -0.014, 0.105), (0.073, 0.014, 0.195))
cg.done()

# ------------------------------------------------------------------ med kit: a case, 0.34 x 0.1 x 0.24, standing
kit = empty("MedKit", (3.5, 0, 0))
Part("Kit_Case", "RArmor", kit, 0.015).box((-0.17, -0.05, 0.0), (0.17, 0.05, 0.24)).done()
# the lid's seam near the top, two latches on it, the handle (the faces stay clear for the one cross)
Part("Kit_Trim", "RFrame", kit, 0.006).box((-0.175, -0.054, 0.196), (0.175, 0.054, 0.208)) \
    .box((-0.13, -0.06, 0.18), (-0.09, 0.06, 0.222)).box((0.09, -0.06, 0.18), (0.13, 0.06, 0.222)) \
    .box((-0.07, -0.015, 0.24), (0.07, 0.015, 0.25)).box((-0.07, -0.015, 0.25), (-0.05, 0.015, 0.285)) \
    .box((0.05, -0.015, 0.25), (0.07, 0.015, 0.285)).box((-0.07, -0.015, 0.275), (0.07, 0.015, 0.295)).done()
kg = Part("Kit_Glow", "SignGreen", kit)
for sy in (-1, 1):                                                  # one green cross on each face
    cross(kg, 0.0, sy * 0.051 - 0.002, sy * 0.051 + 0.002, 0.098, 0.062, 0.021)
kg.done()

# ------------------------------------------------------------------ exit gate: an opening 1.7 wide, 2.4 high
gate = empty("ExitGate", (6.5, 0, 0))
GW, GD = 0.85, 0.3
gb = Part("Gate_Armor", "RArmor", gate, 0.02)
for sx in (-1, 1):
    gb.box((sx * GW + (0.0 if sx > 0 else -0.42), -GD, 0.12), (sx * GW + (0.42 if sx > 0 else 0.0), GD, 2.4))
gb.box((-GW - 0.42, -GD, 2.4), (GW + 0.42, GD, 2.82))
gb.done()
gf = Part("Gate_Frame", "RFrame", gate, 0.01)
for sx in (-1, 1):
    gf.box((sx * GW + (-0.02 if sx > 0 else -0.46), -GD - 0.04, 0.0), (sx * GW + (0.46 if sx > 0 else 0.02), GD + 0.04, 0.14))   # feet
    gf.box((sx * GW - 0.03, -GD + 0.05, 0.14), (sx * GW + 0.03, GD - 0.05, 2.4))                                                # inner jambs
    gf.box((sx * (GW + 0.42) - 0.03, -0.12, 0.5), (sx * (GW + 0.42) + 0.03, 0.12, 2.0))                                         # outer ribs
gf.box((-GW, -GD + 0.05, 2.37), (GW, GD - 0.05, 2.43))
gf.box((-0.5, -GD - 0.02, 2.5), (0.5, GD + 0.02, 2.72))                                                                          # sign plate
gf.box((-GW - 0.3, -0.75, 0.0), (GW + 0.3, 0.75, 0.03))                                                                          # threshold
gf.done()
gh = Part("Gate_Hazard", "Hazard", gate)
gh.box((-GW - 0.3, -0.76, 0.03), (GW + 0.3, -0.6, 0.036)).box((-GW - 0.3, 0.6, 0.03), (GW + 0.3, 0.76, 0.036)).done()
gl = Part("Gate_Light", "ExitLight", gate)
for sx in (-1, 1):
    for sy in (-1, 1):
        gl.box((sx * GW + sx * 0.06 - 0.02, sy * (GD + 0.002) - 0.004, 0.3), (sx * GW + sx * 0.06 + 0.02, sy * (GD + 0.002) + 0.004, 2.3))
for sy in (-1, 1):
    gl.box((-0.42, sy * (GD + 0.022) - 0.004, 2.56), (0.42, sy * (GD + 0.022) + 0.004, 2.66))
gl.done()
Part("Gate_Field", "ExitField", gate).box((-GW + 0.03, -0.004, 0.14), (GW - 0.03, 0.004, 2.37)).done()

for ob in bpy.context.scene.objects:
    ob.select_set(True)
bpy.context.view_layer.objects.active = bpy.context.scene.objects[0]
bpy.ops.wm.save_as_mainfile(filepath=BLEND, compress=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True, export_apply=True,
                          export_image_format="NONE", export_materials="EXPORT", export_animations=False)
print("props:", len(bpy.context.scene.objects), "objects ->", os.path.normpath(OUT))
