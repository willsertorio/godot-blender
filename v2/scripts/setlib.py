"""The environment set (v2/reference/set): helpers on top of v2lib for modelling it from real shapes rather than boxes,
its materials (the robots' worn paint and steel, so the set sits with them), and a studio that renders one asset from
two views, as the reference sheets do.

An asset is an empty (its root, at the asset's floor contact point) with its parts under it. Coordinates are the
asset's own: x to the right, y away from the viewer (a wall panel's face is toward -y), z up, metres.
`begin(name)` starts one; every helper below adds a part to the current asset."""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2lib as L  # noqa: E402

COLL = "Set"
GAME = [False]                  # True: the game's detail (export_set.py): fewer sides to round things, coarser curves
_root = [None]
_count = [0]
ASSETS = {}                     # name -> (function, {options})


def asset(name, **opts):
    """Decorator: registers a function that builds the asset `name` (it is called between begin and end)."""
    def deco(fn):
        ASSETS[name] = (fn, opts)
        return fn
    return deco


def begin(name, at=(0, 0, 0)):
    root = bpy.data.objects.new("A_" + name, None)
    L.coll(COLL).objects.link(root)
    root.location = at
    _root[0] = root
    return root


def _adopt(ob, m=None):
    ob.parent = _root[0]
    if m is not None:
        ob.matrix_local = m
    return ob


prefix = [""]                   # put before the names of the parts made next (e.g. "near_": a side hidden in one view)


def _name(base):
    _count[0] += 1
    return "%s_%s%s_%03d" % (_root[0].name[2:], prefix[0], base, _count[0])


# ---------------------------------------------------------------------------------------------- materials
def _chips(m, amount, color, scale=9.0):
    """Paint missing in patches (not only along edges): `amount` 0..1 of the surface, down to `color`."""
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = scale
    nz.inputs["Detail"].default_value = 9.0
    nz.inputs["Roughness"].default_value = 0.72
    nz.inputs["Distortion"].default_value = 0.6
    nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.5 + 0.3 * (1.0 - amount) - 0.012
    ramp.color_ramp.elements[1].position = 0.5 + 0.3 * (1.0 - amount)
    nt.links.new(nz.outputs["Fac"], ramp.inputs["Fac"])
    col = L._mixc(nt, L._src(nt, bsdf.inputs["Base Color"]), color, ramp.outputs["Color"])
    nt.links.new(col, bsdf.inputs["Base Color"])
    rough = L._mixf(nt, L._src(nt, bsdf.inputs["Roughness"]), 0.5, ramp.outputs["Color"])
    nt.links.new(rough, bsdf.inputs["Roughness"])


def _smudge(m, amount, color=(0.2, 0.19, 0.17), scale=2.2):
    """Large soft dirty patches and streaks running down (z), multiplied into the colour."""
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (scale * 2.5, scale * 2.5, scale * 0.35)       # stretched down the object
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 1.0
    nz.inputs["Detail"].default_value = 7.0
    nz.inputs["Roughness"].default_value = 0.65
    nt.links.new(mp.outputs["Vector"], nz.inputs["Vector"])
    nz2 = nt.nodes.new("ShaderNodeTexNoise")
    nz2.inputs["Scale"].default_value = scale * 1.3
    nz2.inputs["Detail"].default_value = 5.0
    nt.links.new(tc.outputs["Object"], nz2.inputs["Vector"])
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    nt.links.new(nz.outputs["Fac"], mul.inputs[0])
    nt.links.new(nz2.outputs["Fac"], mul.inputs[1])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.14
    ramp.color_ramp.elements[1].position = 0.36
    ramp.color_ramp.elements[1].color = (amount, amount, amount, 1)
    nt.links.new(mul.outputs[0], ramp.inputs["Fac"])
    col = L._mixc(nt, L._src(nt, bsdf.inputs["Base Color"]), color, ramp.outputs["Color"])
    nt.links.new(col, bsdf.inputs["Base Color"])


def _floor_grime(m, height=0.3, amount=0.55, color=(0.1, 0.095, 0.085)):
    """Dirt that has crept up from the floor: darkest at z = 0, gone by `height`, broken up by noise."""
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs[0])
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 11.0
    nz.inputs["Detail"].default_value = 6.0
    nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
    mr = nt.nodes.new("ShaderNodeMapRange")              # z -> 1 at the floor, 0 at height (times the noise)
    mr.inputs["From Min"].default_value = 0.0
    mr.inputs["From Max"].default_value = height
    mr.inputs["To Min"].default_value = 1.0
    mr.inputs["To Max"].default_value = 0.0
    nt.links.new(sep.outputs["Z"], mr.inputs["Value"])
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    nt.links.new(mr.outputs["Result"], mul.inputs[0])
    nt.links.new(nz.outputs["Fac"], mul.inputs[1])
    k = nt.nodes.new("ShaderNodeMath")
    k.operation = "MULTIPLY"
    k.inputs[1].default_value = amount * 2.0
    k.use_clamp = True
    nt.links.new(mul.outputs[0], k.inputs[0])
    col = L._mixc(nt, L._src(nt, bsdf.inputs["Base Color"]), color, k.outputs[0])
    nt.links.new(col, bsdf.inputs["Base Color"])
    rough = L._mixf(nt, L._src(nt, bsdf.inputs["Roughness"]), 0.9, k.outputs[0])
    nt.links.new(rough, bsdf.inputs["Roughness"])


def paint(name, tint, wear=0.8, cavity=0.8, chips=0.05, smudge=0.75, rough=(0.3, 0.6), wear_color=(0.17, 0.17, 0.18), grime=0.55):
    if bpy.data.materials.get(name):
        return bpy.data.materials[name]
    # (the shader's bevel must reach further than the parts' modelled bevels, 4 to 16 mm, or it finds no edge)
    m = L.pbr(name, "PaintedPlaster017", scale=0.9, tint=tint, rough=rough, normal=0.35, grunge=0.45, edge_wear=wear,
              wear_color=wear_color, cavity=cavity, wear_radius=0.016, wear_noise=75.0, cavity_dist=0.035, wear_metal=0.7)
    if smudge > 0:
        _smudge(m, smudge)
    if chips > 0:
        _chips(m, chips, wear_color, scale=16.0)
    if grime > 0:
        _floor_grime(m, amount=grime)
    return m


def hazard(name="EHazard", period=0.115, chips=0.14):
    """Black and yellow stripes at 45 degrees (in the object's own space), worn and chipped."""
    if bpy.data.materials.get(name):
        return bpy.data.materials[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    dot.inputs[1].default_value = (1 / period, 1 / period, 1 / period)
    nt.links.new(tc.outputs["Object"], dot.inputs[0])
    fr = nt.nodes.new("ShaderNodeMath")
    fr.operation = "FRACT"
    nt.links.new(dot.outputs["Value"], fr.inputs[0])
    gt = nt.nodes.new("ShaderNodeMath")
    gt.operation = "GREATER_THAN"
    gt.inputs[1].default_value = 0.5
    nt.links.new(fr.outputs[0], gt.inputs[0])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.inputs[6].default_value = (0.6, 0.3, 0.0, 1)
    mix.inputs[7].default_value = (0.03, 0.03, 0.032, 1)
    nt.links.new(gt.outputs[0], mix.inputs[0])
    nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.5
    L._overlay(nt, bsdf, tc, 0.5, (0.3, 0.3, 0.31), 0.5, 0.0, 90.0, wear_radius=0.0025, wear_noise=120.0, cavity_dist=0.02, wear_metal=0.8)
    if chips > 0:
        _chips(m, chips, (0.3, 0.3, 0.31), scale=14.0)
    return m


def screen(name="EScreen", color=(0.2, 0.9, 0.85), cells=13.0, strength=1.1):
    """A display: a faint grid, blocks of read-out, a few bright lines; emissive."""
    if bpy.data.materials.get(name):
        return bpy.data.materials[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs[0])

    def lines(sock, freq, width):
        a = nt.nodes.new("ShaderNodeMath")
        a.operation = "MULTIPLY"
        a.inputs[1].default_value = freq
        nt.links.new(sock, a.inputs[0])
        f = nt.nodes.new("ShaderNodeMath")
        f.operation = "FRACT"
        nt.links.new(a.outputs[0], f.inputs[0])
        lt = nt.nodes.new("ShaderNodeMath")
        lt.operation = "LESS_THAN"
        lt.inputs[1].default_value = width
        nt.links.new(f.outputs[0], lt.inputs[0])
        return lt.outputs[0]

    def mx(a, b):
        n = nt.nodes.new("ShaderNodeMath")
        n.operation = "MAXIMUM"
        nt.links.new(a, n.inputs[0])
        nt.links.new(b, n.inputs[1])
        return n.outputs[0]

    add = nt.nodes.new("ShaderNodeMath")                 # x + y: the screen may face either way
    nt.links.new(sep.outputs["X"], add.inputs[0])
    nt.links.new(sep.outputs["Y"], add.inputs[1])
    grid = mx(lines(add.outputs[0], cells * 2, 0.04), lines(sep.outputs["Z"], cells * 2, 0.04))
    vor = nt.nodes.new("ShaderNodeTexVoronoi")           # blocks: some cells lit
    vor.distance = "CHEBYCHEV"
    vor.inputs["Scale"].default_value = cells
    vor.inputs["Randomness"].default_value = 0.0
    nt.links.new(tc.outputs["Object"], vor.inputs["Vector"])
    wn = nt.nodes.new("ShaderNodeTexWhiteNoise")
    nt.links.new(vor.outputs["Color"], wn.inputs["Vector"])
    blk = nt.nodes.new("ShaderNodeMath")
    blk.operation = "GREATER_THAN"
    blk.inputs[1].default_value = 0.8
    nt.links.new(wn.outputs["Value"], blk.inputs[0])
    edge = nt.nodes.new("ShaderNodeMath")                # only the frame of a lit cell
    edge.operation = "GREATER_THAN"
    edge.inputs[1].default_value = 0.4
    nt.links.new(vor.outputs["Distance"], edge.inputs[0])
    blocks = nt.nodes.new("ShaderNodeMath")
    blocks.operation = "MULTIPLY"
    nt.links.new(blk.outputs[0], blocks.inputs[0])
    nt.links.new(edge.outputs[0], blocks.inputs[1])
    g2 = nt.nodes.new("ShaderNodeMath")
    g2.operation = "MULTIPLY"
    g2.inputs[1].default_value = 0.22
    nt.links.new(grid, g2.inputs[0])
    total = nt.nodes.new("ShaderNodeMath")
    total.operation = "ADD"
    total.inputs[1].default_value = 0.05
    nt.links.new(mx(g2.outputs[0], blocks.outputs[0]), total.inputs[0])
    em = nt.nodes.new("ShaderNodeMath")
    em.operation = "MULTIPLY"
    em.inputs[1].default_value = strength
    nt.links.new(total.outputs[0], em.inputs[0])
    bsdf.inputs["Base Color"].default_value = (0.01, 0.03, 0.035, 1)
    bsdf.inputs["Roughness"].default_value = 0.12
    bsdf.inputs["Emission Color"].default_value = (*color, 1)
    nt.links.new(em.outputs[0], bsdf.inputs["Emission Strength"])
    return m


def swirl(name="EPortal"):
    """The exit's field: rings swirling into the middle, cyan with orange sparks; emissive."""
    if bpy.data.materials.get(name):
        return bpy.data.materials[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 1.6
    nz.inputs["Detail"].default_value = 4.0
    nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
    mp = nt.nodes.new("ShaderNodeMapping")               # the rings' centre: the middle of the field, not the floor
    mp.inputs["Location"].default_value = (0.0, 0.0, -1.35)
    mp.inputs["Scale"].default_value = (1.0, 1.0, 0.55)
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    mixv = nt.nodes.new("ShaderNodeMix")
    mixv.data_type = "VECTOR"
    mixv.inputs[0].default_value = 0.3
    nt.links.new(mp.outputs["Vector"], mixv.inputs[4])
    nt.links.new(nz.outputs["Color"], mixv.inputs[5])
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = "RINGS"
    wave.rings_direction = "Y"
    wave.inputs["Scale"].default_value = 3.2
    wave.inputs["Distortion"].default_value = 9.0
    wave.inputs["Detail"].default_value = 3.0
    wave.inputs["Detail Scale"].default_value = 1.2
    nt.links.new(mixv.outputs[1], wave.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    e = ramp.color_ramp.elements
    e[0].position, e[0].color = 0.0, (0.0, 0.02, 0.05, 1)
    e[1].position, e[1].color = 1.0, (0.3, 1.0, 1.0, 1)
    for pos, col in ((0.45, (0.0, 0.12, 0.2, 1)), (0.7, (0.05, 0.6, 0.75, 1)), (0.86, (1.0, 0.45, 0.08, 1)), (0.92, (0.1, 0.8, 0.9, 1))):
        n = e.new(pos)
        n.color = col
    nt.links.new(wave.outputs["Fac"], ramp.inputs["Fac"])
    bsdf.inputs["Base Color"].default_value = (0, 0, 0, 1)
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 3.0
    return m


def perforated(name="EMesh", tint=(0.1, 0.1, 0.105), scale=140.0):
    """Perforated or woven sheet seen from a few metres: dark, with a fine regular texture (bump and colour)."""
    if bpy.data.materials.get(name):
        return bpy.data.materials[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    ch = nt.nodes.new("ShaderNodeTexChecker")
    ch.inputs["Scale"].default_value = scale
    ch.inputs["Color1"].default_value = (*tint, 1)
    ch.inputs["Color2"].default_value = (tint[0] * 3.2, tint[1] * 3.2, tint[2] * 3.2, 1)
    nt.links.new(tc.outputs["Object"], ch.inputs["Vector"])
    nt.links.new(ch.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Metallic"].default_value = 0.6
    bsdf.inputs["Roughness"].default_value = 0.5
    bp = nt.nodes.new("ShaderNodeBump")
    bp.inputs["Strength"].default_value = 0.6
    bp.inputs["Distance"].default_value = 0.002
    nt.links.new(ch.outputs["Fac"], bp.inputs["Height"])
    nt.links.new(bp.outputs["Normal"], bsdf.inputs["Normal"])
    return m


def card(name="ECard"):
    """Worn cardboard: tan, blotchy, creased."""
    if bpy.data.materials.get(name):
        return bpy.data.materials[name]
    m = L.plain(name, (0.42, 0.36, 0.26), rough=0.85)
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 28.0
    nz.inputs["Detail"].default_value = 8.0
    nz.inputs["Roughness"].default_value = 0.7
    nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.13, 0.095, 0.055, 1)
    ramp.color_ramp.elements[0].position = 0.3
    ramp.color_ramp.elements[1].color = (0.33, 0.25, 0.15, 1)
    ramp.color_ramp.elements[1].position = 0.7
    nt.links.new(nz.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    mus = nt.nodes.new("ShaderNodeTexMusgrave") if hasattr(bpy.types, "ShaderNodeTexMusgrave") else None
    cr = nt.nodes.new("ShaderNodeTexNoise")
    cr.inputs["Scale"].default_value = 60.0
    cr.inputs["Detail"].default_value = 3.0
    cr.inputs["Distortion"].default_value = 3.0
    nt.links.new(tc.outputs["Object"], cr.inputs["Vector"])
    bp = nt.nodes.new("ShaderNodeBump")
    bp.inputs["Strength"].default_value = 0.5
    bp.inputs["Distance"].default_value = 0.004
    nt.links.new(cr.outputs["Fac"], bp.inputs["Height"])
    nt.links.new(bp.outputs["Normal"], bsdf.inputs["Normal"])
    if mus is not None:
        nt.nodes.remove(mus)
    return m


_M = {}


def mat(key):
    """The set's materials by short name (made on first use)."""
    if key in _M:
        return _M[key]
    steel_wear = dict(edge_wear=0.35, wear_color=(0.6, 0.6, 0.6), cavity=0.5, wear_radius=0.002, wear_noise=140.0, cavity_dist=0.02)
    make = {
        "white": lambda: paint("EPaint", (0.76, 0.77, 0.76)),                      # the off-white shell of everything
        # (what is walked on: the same paint here; the game gives it a tone under the walls', the lamps above bleach it)
        "floor": lambda: paint("EPaintFloor", (0.76, 0.77, 0.76)),
        "grey": lambda: paint("EPaintGrey", (0.15, 0.16, 0.17), wear_color=(0.42, 0.42, 0.42), smudge=0.4),
        "bluegrey": lambda: paint("EPaintBlueGrey", (0.36, 0.41, 0.44), wear_color=(0.2, 0.2, 0.21), smudge=0.5),      # the frames behind the panels
        "panelscreen": lambda: screen("EPanelScreen", color=(0.3, 0.6, 0.52), cells=4.0, strength=0.16),
        "dark": lambda: paint("EPaintDark", (0.07, 0.075, 0.082), wear_color=(0.5, 0.5, 0.5), smudge=0.3),
        "red": lambda: paint("EPaintRed", (0.5, 0.035, 0.025), chips=0.16, smudge=0.35, wear_color=(0.45, 0.45, 0.45)),
        "olive": lambda: paint("EPaintOlive", (0.3, 0.3, 0.12), chips=0.2, wear_color=(0.5, 0.5, 0.5)),
        "green": lambda: paint("EPaintGreen", (0.16, 0.22, 0.13), chips=0.2, wear_color=(0.5, 0.5, 0.5)),
        "redband": lambda: paint("EPaintBand", (0.5, 0.08, 0.05), chips=0.25, smudge=0.2),
        "hazard": hazard,
        "steel": lambda: L.pbr("ESteel", "Metal032", scale=0.5, tint=(0.5, 0.51, 0.53), rough=(0.3, 0.55), metallic=1.0, grunge=0.3, cavity=0.5,
                               cavity_dist=0.02),
        "pipe": lambda: paint("EPipe", (0.62, 0.64, 0.65), wear=0.45, smudge=0.45, wear_color=(0.28, 0.28, 0.29)),
        "darksteel": lambda: L.pbr("EDarkSteel", "Metal032", scale=0.5, tint=(0.11, 0.115, 0.125), rough=(0.4, 0.65), metallic=0.8, **steel_wear),
        "rubber": lambda: L.pbr("ERubber", "Rubber004", scale=0.2, rough=(0.6, 0.9), normal=1.2),
        "cable": lambda: L.plain("ECable", (0.03, 0.03, 0.033), rough=0.55),
        "cable_red": lambda: L.plain("ECableRed", (0.3, 0.05, 0.04), rough=0.55),
        "cable_tan": lambda: L.plain("ECableTan", (0.45, 0.33, 0.2), rough=0.55),
        "glass": lambda: L.plain("EGlass", (0.05, 0.09, 0.09), rough=0.08, metallic=0.5),
        "tankglass": lambda: L.plain("ETankGlass", (0.75, 0.9, 0.88), rough=0.04, transmission=1.0, ior=1.33),
        "liquid": lambda: L.plain("ELiquid", (0.25, 0.45, 0.42), rough=0.1, emit=(0.2, 0.45, 0.42), emit_strength=0.25),
        "screen": screen,
        "portal": swirl,
        "mesh": perforated,
        "card": card,
        "brass": lambda: L.plain("EBrass", (0.75, 0.55, 0.22), rough=0.3, metallic=1.0),
        "copper": lambda: L.plain("ECopper", (0.7, 0.36, 0.2), rough=0.3, metallic=1.0),
        "ink": lambda: L.plain("EInk", (0.06, 0.055, 0.05), rough=0.8),
        "cross": lambda: L.plain("ECross", (0.82, 0.82, 0.8), rough=0.5),
        "cyan": lambda: L.plain("ECyan", (0.0, 0.02, 0.03), emit=(0.15, 0.95, 0.9), emit_strength=7.0),
        "orange": lambda: L.plain("EOrange", (0.03, 0.01, 0.0), emit=(1.0, 0.42, 0.08), emit_strength=7.0),
        "ledgreen": lambda: L.plain("ELedGreen", (0.0, 0.03, 0.01), emit=(0.2, 1.0, 0.4), emit_strength=6.0),
        "ledred": lambda: L.plain("ELedRed", (0.03, 0.0, 0.0), emit=(1.0, 0.1, 0.06), emit_strength=6.0),
        "ledblue": lambda: L.plain("ELedBlue", (0.0, 0.0, 0.03), emit=(0.2, 0.45, 1.0), emit_strength=6.0),
        "light": lambda: L.plain("ELight", (1, 1, 1), emit=(0.85, 0.97, 1.0), emit_strength=9.0),
        "coreglow": lambda: L.plain("ECoreGlow", (0.02, 0.06, 0.07), emit=(0.3, 0.95, 0.95), emit_strength=6.0),
    }
    _M[key] = make[key]()
    return _M[key]


# ---------------------------------------------------------------------------------------------- 2D outlines
def rect(x0, z0, x1, z1):
    return [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]


def chamfer(x0, z0, x1, z1, c):
    """A rectangle with its corners cut by c (one number, or four: bottom-left, bottom-right, top-right, top-left)."""
    bl, br, tr, tl = (c, c, c, c) if isinstance(c, (int, float)) else c
    out = []
    out += [(x0 + bl, z0)] if bl else [(x0, z0)]
    out += [(x1 - br, z0), (x1, z0 + br)] if br else [(x1, z0)]
    out += [(x1, z1 - tr), (x1 - tr, z1)] if tr else [(x1, z1)]
    out += [(x0 + tl, z1), (x0, z1 - tl)] if tl else [(x0, z1)]
    if bl:
        out += [(x0, z0 + bl)]
    return out


def rounded(x0, z0, x1, z1, r, seg=5):
    out = []
    for cx, cz, a0 in ((x1 - r, z0 + r, -90), (x1 - r, z1 - r, 0), (x0 + r, z1 - r, 90), (x0 + r, z0 + r, 180)):
        for i in range(seg + 1):
            a = math.radians(a0 + 90.0 * i / seg)
            out.append((cx + r * math.cos(a), cz + r * math.sin(a)))
    return out


# ---------------------------------------------------------------------------------------------- solids
class Part(L.Builder):
    """One mesh of one material: boxes, cylinders, plates cut to an outline. done() adds it to the current asset."""

    def __init__(self, material, bevel=0.004, name="part"):
        super().__init__(_name(name), mat(material) if isinstance(material, str) else material, collection=COLL, bevel=bevel)

    def box(self, lo, hi, rot=None, pivot=None, tint=None):
        super().box(lo, hi, rot=rot, pivot=pivot, tint=tint)
        return self

    def cyl(self, a, b, r, segs=20, r2=None, caps=True):
        if GAME[0]:
            segs = 5 if segs <= 6 else max(6, int(round(segs * 0.5)))
        super().cyl(a, b, r, segs=segs, r2=r2, caps=caps)
        return self

    def _extrude(self, loop, vec):
        vs = [self.bm.verts.new(p) for p in loop]
        f = self.bm.faces.new(vs)
        r = bmesh.ops.extrude_face_region(self.bm, geom=[f])
        bmesh.ops.translate(self.bm, verts=[g for g in r["geom"] if isinstance(g, bmesh.types.BMVert)], vec=vec)
        return self

    def plate_xz(self, outline, y0, y1):
        """An outline in x, z (a panel seen from the front), from y0 to y1."""
        return self._extrude([(x, y0, z) for x, z in outline], (0, y1 - y0, 0))

    def plate_xy(self, outline, z0, z1):
        """An outline in x, y (seen from above), from z0 to z1."""
        return self._extrude([(x, y, z0) for x, y in outline], (0, 0, z1 - z0))

    def plate_yz(self, outline, x0, x1):
        """An outline in y, z (seen from the side), from x0 to x1."""
        return self._extrude([(x0, y, z) for y, z in outline], (x1 - x0, 0, 0))

    def band_xz(self, outer, inner, y0, y1):
        """The strip between two outlines of as many points each (an arch and the opening in it), from y0 to y1:
        one block per pair of neighbouring points, so no face is concave."""
        for i in range(len(outer) - 1):
            quad = [outer[i], outer[i + 1], inner[i + 1], inner[i]]
            area = sum(quad[k][0] * quad[(k + 1) % 4][1] - quad[(k + 1) % 4][0] * quad[k][1] for k in range(4))
            if abs(area) < 1e-9:
                continue
            self._extrude([(x, y0, z) for x, z in (quad if area > 0 else quad[::-1])], (0, y1 - y0, 0))
        return self

    def frame_xz(self, x0, z0, x1, z1, w, y0, y1, c=0.0):
        """A rectangular frame of width w (four bars), optionally with cut outer corners."""
        self.box((x0, y0, z0), (x1, y1, z0 + w))
        self.box((x0, y0, z1 - w), (x1, y1, z1))
        self.box((x0, y0, z0 + w), (x0 + w, y1, z1 - w))
        self.box((x1 - w, y0, z0 + w), (x1, y1, z1 - w))
        return self

    def bolt(self, p, axis=(0, -1, 0), r=0.012, h=0.008, segs=6):
        p, a = Vector(p), Vector(axis).normalized()
        self.cyl(p, p + a * h, r, segs=segs)
        return self

    def bolts(self, points, axis=(0, -1, 0), r=0.012, h=0.008):
        for p in points:
            self.bolt(p, axis, r, h)
        return self

    def louvres(self, x0, x1, z0, z1, y, n, depth=0.03, tilt=35.0):
        """Slats across an opening x0..x1, z0..z1 whose face is at y (toward -y), tilted down outward."""
        step = (z1 - z0) / n
        rot = Matrix.Rotation(math.radians(tilt), 4, "X")
        for i in range(n):
            zc = z0 + (i + 0.5) * step
            self.box((x0, y, zc - step * 0.36), (x1, y + depth, zc + step * 0.36 - step * 0.5), rot=rot, pivot=(0, y + depth / 2, zc))
        return self

    def grid_xz(self, x0, x1, z0, z1, y0, y1, nx, nz, bar=0.012):
        for i in range(nx + 1):
            x = x0 + (x1 - x0) * i / nx
            self.box((x - bar / 2, y0, z0), (x + bar / 2, y1, z1))
        for j in range(nz + 1):
            z = z0 + (z1 - z0) * j / nz
            self.box((x0, y0, z - bar / 2), (x1, y1, z + bar / 2))
        return self

    def grid_xy(self, x0, x1, y0, y1, z0, z1, nx, ny, bar=0.012):
        for i in range(nx + 1):
            x = x0 + (x1 - x0) * i / nx
            self.box((x - bar / 2, y0, z0), (x + bar / 2, y1, z1))
        for j in range(ny + 1):
            y = y0 + (y1 - y0) * j / ny
            self.box((x0, y - bar / 2, z0), (x1, y + bar / 2, z1))
        return self

    def done(self, m=None, smooth=35, segments=2):
        ob = self.finish(smooth_angle=smooth, bevel_segments=segments)
        return _adopt(ob, m)


def _fillet(points, radius, seg=6):
    """A polyline with its corners rounded to `radius` (points along the arcs)."""
    pts = [Vector(p) for p in points]
    out = [pts[0]]
    for i in range(1, len(pts) - 1):
        a, b, c = pts[i - 1], pts[i], pts[i + 1]
        u, v = (a - b).normalized(), (c - b).normalized()
        ang = u.angle(v)
        if ang > math.pi - 1e-3 or radius <= 0:
            out.append(b)
            continue
        d = min(radius / math.tan(ang / 2), (a - b).length * 0.45, (c - b).length * 0.45)
        r = d * math.tan(ang / 2)
        centre = b + (u + v).normalized() * (r / math.sin(ang / 2))
        p0, p1 = b + u * d, b + v * d
        for k in range(seg + 1):
            t = k / seg
            out.append((p0 - centre).normalized().slerp((p1 - centre).normalized(), t).normalized() * r + centre)
    out.append(pts[-1])
    return out


def pipe(points, r, material="pipe", fillet=None, res=5, name="pipe", m=None):
    """A rigid pipe along straight runs with round elbows (fillet = bend radius, default 2.2 r)."""
    pts = _fillet(points, r * 2.2 if fillet is None else fillet, seg=3 if GAME[0] else 6)
    cu = bpy.data.curves.new(_name(name), "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = r
    cu.bevel_resolution = (2 if r > 0.03 else 1) if GAME[0] else res
    cu.use_fill_caps = True
    sp = cu.splines.new("POLY")
    sp.points.add(len(pts) - 1)
    for p, q in zip(sp.points, pts):
        p.co = (*q, 1)
    ob = bpy.data.objects.new(cu.name, cu)
    L.coll(COLL).objects.link(ob)
    cu.materials.append(mat(material) if isinstance(material, str) else material)
    return _adopt(ob, m)


def cable(points, r=0.012, material="cable", name="cable", m=None):
    """A flexible cable through the points (smooth)."""
    ob = L.curve_tube(_name(name), [Vector(p) for p in points], r, mat(material) if isinstance(material, str) else material, collection=COLL, resolution=4)
    ob.data.use_fill_caps = True
    if GAME[0]:
        ob.data.bevel_resolution = 1 if r > 0.014 else 0     # (a thin cable: four sides)
        ob.data.resolution_u = 3
    return _adopt(ob, m)


def ring(centre, axis, R, r, material="steel", name="ring", m=None, res=5):
    """A torus: a round bar of radius r bent into a circle of radius R about `axis`."""
    centre, ax = Vector(centre), Vector(axis).normalized()
    ref = Vector((0, 0, 1)) if abs(ax.z) < 0.9 else Vector((1, 0, 0))
    u = ax.cross(ref).normalized()
    v = ax.cross(u)
    cu = bpy.data.curves.new(_name(name), "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = r
    cu.bevel_resolution = 1 if GAME[0] else res
    sp = cu.splines.new("POLY")
    n = 16 if GAME[0] else 32
    sp.points.add(n - 1)
    for i, p in enumerate(sp.points):
        a = math.tau * i / n
        p.co = (*(centre + (u * math.cos(a) + v * math.sin(a)) * R), 1)
    sp.use_cyclic_u = True
    ob = bpy.data.objects.new(cu.name, cu)
    L.coll(COLL).objects.link(ob)
    cu.materials.append(mat(material) if isinstance(material, str) else material)
    return _adopt(ob, m)


def handle(p0, p1, out, r=0.012, material="darksteel", m=None):
    """A grab handle: from p0 out by `out`, across, and back in at p1."""
    p0, p1, o = Vector(p0), Vector(p1), Vector(out)
    return pipe([p0, p0 + o, p1 + o, p1], r, material, fillet=r * 2.5, name="handle", m=m)


def valve_wheel(centre, axis, R=0.09, material="red", m=None):
    """A hand wheel: rim, hub, four spokes, facing along `axis`."""
    centre, ax = Vector(centre), Vector(axis).normalized()
    ref = Vector((0, 0, 1)) if abs(ax.z) < 0.9 else Vector((1, 0, 0))
    u = ax.cross(ref).normalized()
    v = ax.cross(u)
    ring(centre, ax, R, R * 0.13, material, name="wheel", m=m)
    p = Part(material, bevel=0.0, name="spokes")
    p.cyl(centre - ax * 0.01, centre + ax * 0.02, R * 0.26, segs=12)
    for d in (u, v):
        p.cyl(centre - d * R, centre + d * R, R * 0.09, segs=8)
    return p.done(m)


def text(body, size, at, rot=(math.pi / 2, 0, 0), material="ink", depth=0.0008, align="LEFT"):
    """Stencilled lettering laid on a surface: `at` = its origin, `rot` turns it from lying flat (default: upright,
    read from -y)."""
    cu = bpy.data.curves.new(_name("text"), "FONT")
    cu.body = body
    cu.size = size
    cu.extrude = depth
    cu.align_x = align
    ob = bpy.data.objects.new(cu.name, cu)
    L.coll(COLL).objects.link(ob)
    cu.materials.append(mat(material))
    ob.parent = _root[0]
    ob.location = at
    ob.rotation_euler = rot
    return ob


def T(loc=(0, 0, 0), rx=0.0, ry=0.0, rz=0.0):
    """A placement: turn by rx, ry, rz degrees (in that order about the fixed axes), then move to loc."""
    return Matrix.Translation(loc) @ Matrix.Rotation(math.radians(rz), 4, "Z") @ Matrix.Rotation(math.radians(ry), 4, "Y") \
        @ Matrix.Rotation(math.radians(rx), 4, "X")


# ---------------------------------------------------------------------------------------------- the studio
def studio(samples=72):
    sc = L.setup_cycles(samples=samples, res=(700, 620))
    sc.view_settings.look = "AgX - High Contrast"
    sc.view_settings.exposure = -0.15
    world = bpy.data.worlds.new("Studio")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.19, 0.19, 0.19, 1)
    bg.inputs["Strength"].default_value = 1.0
    sc.world = world
    for name, loc, energy, size in (("Key", (-5.5, -7.0, 8.0), 3200.0, 5.0), ("Fill", (7.0, -5.0, 3.0), 500.0, 8.0), ("Rim", (3.0, 7.0, 7.0), 1500.0, 5.0),
                                    ("Top", (0.0, -1.0, 10.0), 600.0, 9.0)):
        ld = bpy.data.lights.new(name, "AREA")
        ld.energy = energy
        ld.size = size
        ob = bpy.data.objects.new(name, ld)
        sc.collection.objects.link(ob)
        ob.location = loc
        ob.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.lens = 90.0
    cam.data.clip_end = 400.0
    sc.collection.objects.link(cam)
    sc.camera = cam
    return sc


def bounds(root):
    """The asset's box (world), from its evaluated geometry (curves and text included)."""
    lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    deps = bpy.context.evaluated_depsgraph_get()
    for ob in root.children_recursive:
        if ob.type not in ("MESH", "CURVE", "FONT"):
            continue
        ev = ob.evaluated_get(deps)
        me = ev.to_mesh()
        mw = ev.matrix_world
        for i in range(0, len(me.vertices), max(len(me.vertices) // 400, 1)):
            w = mw @ me.vertices[i].co
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
        ev.to_mesh_clear()
    return lo, hi


def shoot(root, direction, path, res=(700, 620), lights_follow=True, hide=None):
    """Render the asset `root` alone, seen from `direction` (a vector from the asset toward the camera).
    hide: parts with this in their name are left out (a near wall, to see inside)."""
    sc = bpy.context.scene
    for ob in sc.objects:
        if ob.name.startswith("A_") or ob.parent is not None:
            top = ob
            while top.parent is not None:
                top = top.parent
            ob.hide_render = top is not root or (hide is not None and hide in ob.name)
    lo, hi = bounds(root)
    centre = (lo + hi) / 2
    radius = (hi - lo).length / 2
    cam = sc.camera
    d = Vector(direction).normalized()
    sc.render.resolution_x, sc.render.resolution_y = res
    fov = 2 * math.atan(min(36.0, 36.0 * res[1] / res[0]) / 2 / cam.data.lens)
    cam.location = centre + d * (radius / math.sin(fov / 2) * 1.04)
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    if lights_follow:                                      # the lights keep their places relative to the camera's side
        yaw = math.atan2(d.x, -d.y)
        rot = Matrix.Rotation(yaw, 4, "Z")
        scale = max(radius / 1.6, 0.25)
        up = -1.0 if d.z < -0.1 else 1.0                      # (seen from below, a ceiling piece: the lights are below too)
        for name, loc in (("Key", (-5.5, -7.0, 8.0)), ("Fill", (7.0, -5.0, 3.0)), ("Rim", (3.0, 7.0, 7.0)), ("Top", (0.0, -1.0, 10.0))):
            ob = bpy.data.objects[name]
            ob.location = centre + rot @ (Vector((loc[0], loc[1], loc[2] * up)) * scale)
            ob.rotation_euler = (centre - ob.location).to_track_quat("-Z", "Y").to_euler()
            ob.data.size = {"Key": 5.0, "Fill": 8.0, "Rim": 5.0, "Top": 9.0}[name] * scale
            # (a floor tile seen from above faces the lights squarely: less of them, or its colours bleach)
            ob.data.energy = {"Key": 3200.0, "Fill": 500.0, "Rim": 1500.0, "Top": 350.0}[name] * scale * scale * (0.42 if d.z > 0.6 else 1.0)
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
