"""The environment set: structure (see build_set.py)."""
import math

import setlib as S
from setlib import Part, T, asset, cable, chamfer, handle, pipe, rect, ring, rounded, valve_wheel

# ------------------------------------------------------------------ the wall panel: 2 m wide, 3 m high, its face toward -y
PW, PH = 2.0, 3.0


def wall_frame(inner=True, w=PW, h=PH):
    """The panel every wall variant is built on (reference 01): a blue-grey carrier frame behind, with brackets down
    its sides; on it the white face: a border, an upper and a lower field with a seam between, a tab let into the
    top and the bottom, a bolt in each corner."""
    hw = w / 2
    # the carrier: wider on the right, where it shows as a second strip
    game = S.GAME[0]                                        # (in the game the panels stand edge to edge: no brackets, a plain backing)
    if game:
        Part("bluegrey", bevel=0.0, name="carrier").box((-hw, 0.03, 0.0), (hw, 0.11, h)).done()
    else:
        cf = Part("bluegrey", bevel=0.006, name="carrier")
        cf.box((-hw - 0.03, 0.03, 0.0), (hw + 0.05, 0.11, h))
        for sx in (-1, 1):
            for z in (0.35, h * 0.5, h - 0.35):             # brackets
                cf.box((sx * (hw + 0.03) - 0.03, 0.0, z - 0.07), (sx * (hw + 0.03) + 0.03, 0.14, z + 0.07))
        cf.done()
        Part("dark", bevel=0.0, name="gap").box((-hw - 0.02, 0.02, 0.01), (hw + 0.04, 0.04, h - 0.01)).done()
    # the face: border
    face = Part("white", bevel=0.008, name="border")
    b = 0.11
    face.plate_xz(chamfer(-hw, 0.0, hw, h, 0.035), -0.012, 0.03)
    face.done()
    rim = Part("white", bevel=0.006, name="rim")
    rim.frame_xz(-hw + 0.012, 0.012, hw - 0.012, h - 0.012, b - 0.03, -0.03, -0.012)
    rim.done()
    tab = Part("white", bevel=0.005, name="tabs")           # the tabs let into the top and the bottom of the border
    tab.plate_xz(chamfer(-hw * 0.5, h - 0.1, hw * 0.5, h - 0.025, (0.03, 0.03, 0.0, 0.0)), -0.042, -0.03)
    tab.plate_xz(chamfer(-hw * 0.5, 0.025, hw * 0.5, 0.1, (0.0, 0.0, 0.03, 0.03)), -0.042, -0.03)
    tab.done()
    if inner:
        seam = h * 0.33
        f = Part("white", bevel=0.007, name="fields")
        f.plate_xz(chamfer(-hw + b, seam + 0.008, hw - b, h - b, 0.02), -0.045, -0.012)
        f.plate_xz(chamfer(-hw + b, b, hw - b, seam - 0.008, 0.02), -0.045, -0.012)
        f.done()
        Part("darksteel", bevel=0.002, name="clips").box((-hw + b - 0.012, -0.05, seam - 0.08), (-hw + b + 0.01, -0.03, seam + 0.08)) \
            .box((hw - b - 0.01, -0.05, seam - 0.08), (hw - b + 0.012, -0.03, seam + 0.08)).done()
    bl = Part("steel", bevel=0.0, name="bolts")
    for sx in (-1, 1):
        for z in (0.06, h - 0.06):
            bl.bolt((sx * (hw - 0.06), -0.03, z), r=0.014, h=0.008)
        for z in (() if game else (0.5, h * 0.5 + 0.1, h - 0.5)):
            bl.bolt((sx * (hw + 0.03), 0.0, z), r=0.011, h=0.008)
    bl.done()
    if not game:
        mk = Part("dark", bevel=0.0, name="marks")          # the small slots stamped by the corners
        for sx in (-1, 1):
            for z in (0.2, h - 0.24):
                mk.box((sx * (hw - 0.055) - 0.004, -0.0315, z), (sx * (hw - 0.055) + 0.004, -0.0295, z + 0.04))
        mk.done()


@asset("wall_plain")
def wall_plain():
    wall_frame()


@asset("wall_screen")
def wall_screen():
    wall_frame(inner=False)
    hw = PW / 2
    # the bezel: a raised surround with cut corners, a dark gasket, the display let into it
    x0, x1, z0, z1 = -hw + 0.13, hw - 0.13, 0.22, PH - 0.2
    bz = Part("white", bevel=0.008, name="bezel")
    bw = 0.17
    bz.box((x0, -0.06, z0), (x1, -0.012, z0 + bw)).box((x0, -0.06, z1 - bw), (x1, -0.012, z1))
    bz.box((x0, -0.06, z0 + bw), (x0 + bw, -0.012, z1 - bw)).box((x1 - bw, -0.06, z0 + bw), (x1, -0.012, z1 - bw))
    bz.done()
    ix0, ix1, iz0, iz1 = x0 + bw, x1 - bw, z0 + bw, z1 - bw
    Part("panelscreen", bevel=0.0, name="display").plate_xz(rounded(ix0 - 0.01, iz0 - 0.01, ix1 + 0.01, iz1 + 0.01, 0.07), -0.03, -0.02).done()
    gasket = [(x, -0.045, z) for x, z in rounded(ix0 + 0.012, iz0 + 0.012, ix1 - 0.012, iz1 - 0.012, 0.07, seg=6)]
    pipe(gasket + [gasket[0]], 0.016, "darksteel", fillet=0.0, name="gasket")
    cs = Part("darksteel", bevel=0.003, name="corners")     # the gussets that round the opening's corners
    for cx, cz, sx, sz in ((ix0, iz0, 1, 1), (ix1, iz0, -1, 1), (ix1, iz1, -1, -1), (ix0, iz1, 1, -1)):
        cs.plate_xz([(cx, cz), (cx + sx * 0.09, cz), (cx, cz + sz * 0.09)] if sx * sz > 0 else [(cx, cz), (cx, cz + sz * 0.09), (cx + sx * 0.09, cz)], -0.058, -0.03)
    cs.box((-0.3, -0.066, iz1 - 0.012), (0.3, -0.05, iz1 + 0.035)).box((-0.22, -0.066, iz0 - 0.035), (0.22, -0.05, iz0 + 0.012))
    cs.done()
    Part("ledred", bevel=0.0, name="led").box((-0.02, -0.068, iz0 - 0.02), (0.02, -0.066, iz0 - 0.008)).done()
    for k, x in enumerate((ix0 - 0.05, ix0 - 0.085)):          # two thin cables down the left of the bezel
        cable([(x, -0.07, 0.75), (x - 0.01, -0.075, 1.3), (x, -0.07, 1.9)], 0.008)
    Part("darksteel", bevel=0.003, name="clip").box((ix0 - 0.11, -0.075, 1.25), (ix0 - 0.03, -0.06, 1.33)).done()


@asset("wall_service")
def wall_service():
    wall_frame()
    y = -0.045                                              # the fields' face
    # two risers on the left: the thick one ends in an elbow into the wall at the top, the thin one loops under
    pipe([(-0.72, y - 0.06, 0.34), (-0.72, y - 0.06, 2.62), (-0.72, y + 0.0, 2.72)], 0.05, fillet=0.09)
    pipe([(-0.56, y - 0.045, 2.2), (-0.56, y - 0.045, 0.3), (-0.72, y - 0.045, 0.22), (-0.72, y - 0.06, 0.34)], 0.036, fillet=0.08)
    pipe([(-0.56, y - 0.045, 2.2), (-0.56, y - 0.045, 2.3), (-0.42, y - 0.045, 2.42), (-0.42, y - 0.045, 2.48), (0.02, y - 0.045, 2.48)], 0.03, fillet=0.06)
    fl = Part("steel", bevel=0.003, name="flanges")
    for z in (0.55, 1.0, 1.9, 2.5):
        fl.cyl((-0.72, y - 0.06, z - 0.018), (-0.72, y - 0.06, z + 0.018), 0.065, segs=16)
    for z in (0.7, 1.75):
        fl.cyl((-0.56, y - 0.045, z - 0.014), (-0.56, y - 0.045, z + 0.014), 0.048, segs=16)
    fl.cyl((-0.2, y - 0.045, 2.46), (-0.2, y - 0.045, 2.5), 0.045, segs=6).cyl((-0.2, y - 0.045, 2.5), (-0.2, y - 0.045, 2.58), 0.012, segs=8)
    fl.box((-0.25, y - 0.05, 2.575), (-0.15, y - 0.04, 2.59))
    for z in (0.45, 1.3, 2.3):                              # clamps to the wall
        fl.box((-0.8, y - 0.02, z - 0.02), (-0.5, y, z + 0.02))
    fl.done()
    valve_wheel((-0.56, y - 0.1, 1.28), (0, -1, 0), R=0.065, material="steel")
    valve_wheel((-0.42, y - 0.1, 0.92), (0, -1, 0), R=0.06, material="steel")
    Part("steel", bevel=0.002, name="stems").cyl((-0.56, y - 0.045, 1.28), (-0.56, y - 0.1, 1.28), 0.016, segs=8) \
        .cyl((-0.56, y - 0.045, 0.92), (-0.42, y - 0.045, 0.92), 0.02, segs=8).cyl((-0.42, y - 0.045, 0.92), (-0.42, y - 0.1, 0.92), 0.016, segs=8).done()
    # junction boxes
    bx = Part("white", bevel=0.01, name="boxes")
    bx.box((0.02, y - 0.13, 2.26), (0.4, y, 2.62))           # top right, the cables leave it downward
    bx.box((-0.84, y - 0.12, 1.36), (-0.46, y - 0.02, 1.7))  # on the risers
    bx.box((0.08, y - 0.1, 0.56), (0.42, y, 0.82))           # lower right
    bx.box((-0.34, y - 0.09, 0.42), (-0.16, y, 0.84))        # lower left, tall
    bx.done()
    dt = Part("darksteel", bevel=0.003, name="box details")
    dt.box((0.07, y - 0.136, 2.3), (0.35, y - 0.13, 2.36)).box((-0.58, y - 0.126, 1.44), (-0.5, y - 0.12, 1.62))
    dt.box((0.13, y - 0.106, 0.7), (0.37, y - 0.1, 0.76)).box((-0.31, y - 0.096, 0.62), (-0.19, y - 0.09, 0.78))
    dt.cyl((-0.25, y - 0.09, 0.5), (-0.25, y - 0.1, 0.5), 0.03, segs=14)
    dt.done()
    Part("ledgreen", bevel=0.0, name="leds").box((0.1, y - 0.138, 2.315), (0.2, y - 0.136, 2.345)).box((0.16, y - 0.108, 0.715), (0.3, y - 0.106, 0.745)) \
        .box((-0.29, y - 0.098, 0.66), (-0.21, y - 0.096, 0.76)).done()
    hd = Part("steel", bevel=0.0, name="box bolts")
    for bx0, bx1, bz0, bz1, by in ((0.02, 0.4, 2.26, 2.62, y - 0.13), (-0.84, -0.46, 1.36, 1.7, y - 0.12), (0.08, 0.42, 0.56, 0.82, y - 0.1)):
        for px in (bx0 + 0.03, bx1 - 0.03):
            for pz in (bz0 + 0.03, bz1 - 0.03):
                hd.bolt((px, by, pz), r=0.01, h=0.006)
    hd.done()
    # the vent: frame, louvres, soot
    S_part = Part("white", bevel=0.008, name="vent frame")
    S_part.frame_xz(-0.1, 0.98, 0.62, 2.0, 0.07, y - 0.07, y)
    S_part.done()
    Part("dark", bevel=0.0, name="vent back").box((-0.04, y - 0.012, 1.04), (0.56, y - 0.004, 1.94)).done()
    Part("pipe", bevel=0.003, name="louvres").louvres(-0.035, 0.555, 1.05, 1.93, y - 0.06, 11, depth=0.045).done()
    # the cable bundle: out of the top box, down the left of the vent, under it and into the lower boxes
    for k in range(5):
        o = k * 0.03
        mat_k = ("cable", "cable", "cable_tan", "cable", "cable_red")[k]
        if k < 3:
            cable([(0.06 + o, y - 0.03, 2.27), (0.02 + o * 0.5, y - 0.035, 2.12), (-0.28 + o, y - 0.035, 2.06), (-0.36 + o, y - 0.035, 1.8),
                   (-0.36 + o, y - 0.035, 1.1), (-0.3 + o, y - 0.035, 0.94 - o * 0.4), (0.06, y - 0.035, 0.9 - o), (0.14 + o, y - 0.035, 0.82)], 0.011, mat_k)
        else:
            cable([(0.2 + o, y - 0.03, 0.56), (0.2 + o, y - 0.03, 0.3), (0.22 + o, y - 0.025, 0.13)], 0.011, mat_k)
            cable([(-0.3 + o * 0.6, y - 0.03, 0.42), (-0.3 + o * 0.6, y - 0.03, 0.28), (-0.28 + o * 0.6, y - 0.02, 0.13)], 0.009, mat_k)
    Part("darksteel", bevel=0.002, name="cable clips").box((-0.4, y - 0.05, 1.42), (-0.2, y - 0.02, 1.46)).box((-0.4, y - 0.05, 1.86), (-0.2, y - 0.02, 1.9)) \
        .box((-0.3, y - 0.05, 2.03), (-0.26, y - 0.02, 2.11)).done()


# ------------------------------------------------------------------ the doorway (reference 04): opening 2.4 x 2.6 m
DW, DH = 1.2, 2.6


@asset("door", views=[(-0.5, -1.0, 0.2), (1.0, -0.55, 0.12)])
def door(frame=True, leaves=("L", "R"), half=False):
    """half (the game): the frame is as deep as half the wall, so that two stand back to back in a doorway, one
    facing the room and one the corridor, with the leaves between them."""
    ow, oh = DW + 0.62, DH + 0.72                           # the carrier frame's half width, height
    deep = 0.15 if half else 0.2
    if frame:
        door_frame(ow, oh, deep, half)
    if leaves:
        door_leaves(leaves, both_faces=half)


def door_frame(ow, oh, deep, half):
    # the carrier: a flat frame the conduits run on
    cf = Part("white", bevel=0.01, name="carrier")
    cf.box((-ow, 0.0, 0.0), (-DW - 0.02, deep, oh)).box((DW + 0.02, 0.0, 0.0), (ow, deep, oh)).box((-DW - 0.02, 0.0, DH + 0.02), (DW + 0.02, deep, oh))
    cf.done()
    if not half:
        Part("bluegrey", bevel=0.006, name="back").box((-ow - 0.04, 0.2, 0.0), (-DW, 0.3, oh + 0.02)).box((DW, 0.2, 0.0), (ow + 0.04, 0.3, oh + 0.02)) \
            .box((-DW, 0.2, DH), (DW, 0.3, oh + 0.02)).done()
    lind = deep if half else 0.26                           # how far back the opening's lining goes
    # the portal: the heavy inner frame, its top corners cut, standing proud of the carrier
    iw = DW + 0.3
    outer = chamfer(-iw, 0.0, iw, DH + 0.38, (0.0, 0.0, 0.2, 0.2))
    pf = Part("white", bevel=0.014, name="portal")
    pf.plate_xz([(-iw, 0.0), (-DW, 0.0), (-DW, DH - 0.12), (-DW + 0.12, DH), (DW - 0.12, DH), (DW, DH - 0.12), (DW, 0.0), (iw, 0.0)] + outer[2:6][::1], -0.14, 0.02) \
        if False else None
    # (as four pieces: two legs, two cut corners, the lintel)
    for sx in (-1, 1):
        x0, x1 = sorted((sx * DW, sx * iw))
        pf.box((x0, -0.14, 0.0), (x1, 0.02, DH - 0.1))
        pf.plate_xz([(sx * DW, DH - 0.1), (sx * iw, DH - 0.1), (sx * iw, DH + 0.18), (sx * (iw - 0.2), DH + 0.38), (sx * (DW - 0.14), DH + 0.38),
                     (sx * (DW - 0.14), DH + 0.02)][::sx], -0.14, 0.02)
    pf.box((-DW + 0.14, -0.14, DH + 0.02), (DW - 0.14, 0.02, DH + 0.38))
    pf.done()
    lin = Part("grey", bevel=0.006, name="lining")           # the dark lining inside the opening, its top corners cut too
    for sx in (-1, 1):
        x0, x1 = sorted((sx * (DW - 0.05), sx * DW))
        lin.box((x0, -0.1, 0.0), (x1, lind, DH - 0.14))
        lin.plate_xz([(sx * (DW - 0.05), DH - 0.14), (sx * DW, DH - 0.14), (sx * DW, DH - 0.08), (sx * (DW - 0.14), DH + 0.02), (sx * (DW - 0.2), DH + 0.02),
                      (sx * (DW - 0.2), DH - 0.03)][::sx], -0.1, lind)
    lin.box((-DW + 0.2, -0.1, DH - 0.03), (DW - 0.2, lind, DH + 0.02))
    lin.done()
    # the lintel's box with the two status lights, a top cover
    Part("white", bevel=0.012, name="lintel box").box((-0.62, -0.17, DH + 0.1), (0.62, -0.13, DH + 0.3)).box((-0.55, -0.05, oh - 0.16), (0.55, 0.06, oh + 0.03)).done()
    Part("cyan", bevel=0.0, name="lamp").box((-0.34, -0.176, DH + 0.18), (-0.14, -0.17, DH + 0.215)).done()
    Part("orange", bevel=0.0, name="lamp").box((0.14, -0.176, DH + 0.18), (0.34, -0.17, DH + 0.215)).done()
    # blocks on the legs, mid height; the recessed grips in the legs; the feet
    bk = Part("white", bevel=0.01, name="blocks")
    for sx in (-1, 1):
        x0, x1 = sorted((sx * (iw - 0.02), sx * (iw + 0.2)))
        bk.box((x0, -0.1, 1.5), (x1, 0.04, 1.86))
        x0, x1 = sorted((sx * (DW + 0.02), sx * (iw + 0.06)))
        bk.plate_xz(chamfer(x0, 0.0, x1, 0.42, (0.0, 0.0, 0.05, 0.05)), -0.18, -0.14)
    bk.done()
    gr = Part("grey", bevel=0.008, name="grips")
    for sx in (-1, 1):
        xc = sx * (DW + 0.15)
        gr.plate_xz(rounded(xc - 0.035, 0.75, xc + 0.035, 1.25, 0.03), -0.15, -0.135)
        gr.plate_xz(rounded(xc - 0.035, 1.95, xc + 0.035, 2.4, 0.03), -0.15, -0.135)
        gr.box((xc - 0.05, -0.19, 0.08), (xc + 0.05, -0.18, 0.2))
    gr.done()
    bl = Part("steel", bevel=0.0, name="bolts")
    for sx in (-1, 1):
        for z in (0.5, 1.4, 2.0, 2.9, 3.2):
            bl.bolt((sx * (ow - 0.07), 0.0, z), r=0.016, h=0.01)
        for z in (1.56, 1.8):
            bl.bolt((sx * (iw + 0.12), -0.1, z), r=0.013, h=0.008)
    bl.done()
    # the conduits: three cables each side, up the carrier and over the portal's cut corners to the top cover
    for sx in (-1, 1):
        for k in range(3):
            x = sx * (iw + 0.1 + k * 0.045)
            cable([(x, -0.02, 1.9), (x, -0.02, DH + 0.2), (sx * (iw - 0.12 + k * 0.045), -0.02, DH + 0.47 + k * 0.04), (sx * 0.56, -0.02, DH + 0.56 + k * 0.035)], 0.014,
                  "cable" if k != 1 else "pipe")
        Part("darksteel", bevel=0.003, name="conduit clips").box(tuple(sorted((sx * (iw + 0.06), sx * (iw + 0.24))))[0:1] + (-0.045, 2.2), tuple(sorted((sx * (iw + 0.06), sx * (iw + 0.24))))[1:2] + (0.0, 2.26)) \
            .box(tuple(sorted((sx * (iw + 0.06), sx * (iw + 0.24))))[0:1] + (-0.045, DH + 0.06), tuple(sorted((sx * (iw + 0.06), sx * (iw + 0.24))))[1:2] + (0.0, DH + 0.12)).done()
    # the keypad on the right leg
    Part("grey", bevel=0.006, name="keypad").box((iw - 0.2, -0.17, 1.02), (iw - 0.04, -0.14, 1.4)).done()
    Part("ledgreen", bevel=0.0, name="keypad led").box((iw - 0.17, -0.174, 1.3), (iw - 0.07, -0.17, 1.36)).done()
    Part("darksteel", bevel=0.002, name="keys").box((iw - 0.17, -0.176, 1.08), (iw - 0.07, -0.17, 1.26)).done()
    Part("dark", bevel=0.0, name="sill").box((-DW, -0.1, 0.0), (DW, lind, 0.02)).done()


def door_leaves(which, both_faces=False):
    """The door: a wide leaf (L) and a narrow one (R), which part at the seam; each a slab with two fields.
    both_faces (the game): the fields are on the corridor's side too, and the leaves stand in the wall's middle."""
    split = 0.42
    y0, y1 = (0.11, 0.19) if both_faces else (0.04, 0.12)
    for x0, x1, key in ((-DW + 0.06, split - 0.006, "L"), (split + 0.006, DW - 0.06, "R")):
        if key not in which:
            continue
        lf = Part("white", bevel=0.008, name="leaf")
        lf.box((x0, y0, 0.02), (x1, y1, DH - 0.05))
        seam = 0.95
        faces = ((y0 - 0.028, y0), (y1, y1 + 0.028)) if both_faces else ((y0 - 0.028, y0),)
        for ya, yb in faces:
            lf.plate_xz(chamfer(x0 + 0.06, seam + 0.01, x1 - 0.06, DH - 0.14, 0.03), ya, yb)
            lf.plate_xz(chamfer(x0 + 0.06, 0.1, x1 - 0.06, seam - 0.01, 0.03), ya, yb)
        lf.done()
        ya = y0 - 0.028                                     # the fields' face, room side
        if key == "L":
            Part("white", bevel=0.006, name="door tab").plate_xz(chamfer(-DW + 0.5, DH - 0.25, split - 0.4, DH - 0.17, (0.03, 0.03, 0.0, 0.0)), ya - 0.012, ya).done()
            Part("grey", bevel=0.006, name="pull").box((-DW + 0.1, ya - 0.022, 0.75), (-DW + 0.13, ya, 1.15)).done()
        else:
            Part("grey", bevel=0.006, name="lock").box((split + 0.04, ya - 0.032, 1.2), (split + 0.3, ya, 1.48)).done()
            Part("darksteel", bevel=0.003, name="lock handle").box((split + 0.1, ya - 0.057, 1.25), (split + 0.16, ya - 0.032, 1.42)).done()
            Part("cyan", bevel=0.0, name="lamp").box((split + 0.06, ya - 0.028, 1.52), (split + 0.14, ya - 0.024, 1.545)).done()
            Part("orange", bevel=0.0, name="lamp").box((split + 0.17, ya - 0.028, 1.52), (split + 0.25, ya - 0.024, 1.545)).done()


# ------------------------------------------------------------------ floor tiles (reference 05): 1 x 2 m, lying flat
TW, TL = 1.0, 2.0


def tile_frame(open_middle=False):
    """A tile's frame: cut corners, a notch in the middle of each long side and in each end, a bolt by each corner.
    Returns the opening (x0, y0, x1, y1) the variants fill. open_middle: the frame is a border only (the grating)."""
    hw, hl = TW / 2, TL / 2
    if open_middle:
        x0, y0, x1, y1 = -hw + 0.1, -hl + 0.12, hw - 0.1, hl - 0.12
        fr = Part("floor", bevel=0.006, name="frame")
        fr.plate_xy(chamfer(-hw, -hl, hw, y0, (0.07, 0.07, 0.0, 0.0)), 0.0, 0.06).plate_xy(chamfer(-hw, y1, hw, hl, (0.0, 0.0, 0.07, 0.07)), 0.0, 0.06)
        fr.box((-hw, y0, 0.0), (x0, y1, 0.06)).box((x1, y0, 0.0), (hw, y1, 0.06))
        fr.done()
        Part("bluegrey", bevel=0.004, name="tray").box((-hw + 0.02, -hl + 0.02, -0.05), (hw - 0.02, hl - 0.02, 0.0)).done()
        bl = Part("steel", bevel=0.0, name="bolts")
        for sx in (-1, 1):
            for sy in (-1, 1):
                bl.bolt((sx * (hw - 0.05), sy * (hl - 0.06), 0.06), axis=(0, 0, 1), r=0.014, h=0.006)
        bl.done()
        return x0, y0, x1, y1
    if S.GAME[0]:                                           # (hundreds to a room: no notches, tray or clips, four bolts)
        Part("floor", bevel=0.006, name="frame").plate_xy(chamfer(-hw, -hl, hw, hl, 0.07), 0.0, 0.06).done()
        bl = Part("steel", bevel=0.0, name="bolts")
        for sx in (-1, 1):
            for sy in (-1, 1):
                bl.bolt((sx * (hw - 0.06), sy * (hl - 0.06), 0.06), axis=(0, 0, 1), r=0.014, h=0.006)
        bl.done()
        return -hw + 0.1, -hl + 0.12, hw - 0.1, hl - 0.12
    n, nd = 0.2, 0.03                                       # the notches: half length, depth
    out = [(-hw + 0.07, -hl), (-0.22, -hl), (-0.19, -hl + nd), (0.19, -hl + nd), (0.22, -hl), (hw - 0.07, -hl), (hw, -hl + 0.07),
           (hw, -n - 0.04), (hw - nd, -n), (hw - nd, n), (hw, n + 0.04), (hw, hl - 0.07), (hw - 0.07, hl),
           (0.22, hl), (0.19, hl - nd), (-0.19, hl - nd), (-0.22, hl), (-hw + 0.07, hl), (-hw, hl - 0.07),
           (-hw, n + 0.04), (-hw + nd, n), (-hw + nd, -n), (-hw, -n - 0.04), (-hw, -hl + 0.07)]
    Part("floor", bevel=0.006, name="frame").plate_xy(out, 0.0, 0.06).done()
    Part("bluegrey", bevel=0.004, name="tray").box((-hw + 0.02, -hl + 0.02, -0.05), (hw - 0.02, hl - 0.02, 0.0)).done()
    cl = Part("darksteel", bevel=0.003, name="clips")
    for sx in (-1, 1):
        for y in (-0.62, 0.62):
            cl.box(tuple(sorted((sx * (hw - 0.02), sx * (hw + 0.012))))[0:1] + (y - 0.05, -0.04), tuple(sorted((sx * (hw - 0.02), sx * (hw + 0.012))))[1:2] + (y + 0.05, 0.03))
    cl.done()
    bl = Part("steel", bevel=0.0, name="bolts")
    for sx in (-1, 1):
        for sy in (-1, 1):
            bl.bolt((sx * (hw - 0.06), sy * (hl - 0.06), 0.06), axis=(0, 0, 1), r=0.014, h=0.006)
            bl.bolt((sx * (hw - 0.085), sy * 0.3, 0.06), axis=(0, 0, 1), r=0.01, h=0.005)
    bl.done()
    return -hw + 0.1, -hl + 0.12, hw - 0.1, hl - 0.12


@asset("floor_plain", views=[(-0.25, -0.75, 1.0), (1.0, -0.5, 0.45)])
def floor_plain():
    x0, y0, x1, y1 = tile_frame()
    f = Part("floor", bevel=0.005, name="fields")
    f.plate_xy(chamfer(x0, y0, x1, -0.006, (0.06, 0.06, 0.0, 0.0)), 0.04, 0.068)
    f.plate_xy(chamfer(x0, 0.006, x1, y1, (0.0, 0.0, 0.06, 0.06)), 0.04, 0.068)
    f.done()
    if not S.GAME[0]:
        ln = Part("dark", bevel=0.0, name="scores")          # scored lines across the fields
        for y in (-0.52, 0.52):
            ln.box((x0 + 0.02, y - 0.003, 0.0675), (x1 - 0.02, y + 0.003, 0.0685))
        ln.box((-0.003, y0 + 0.08, 0.0675), (0.003, -0.02, 0.0685))
        ln.done()
    if not S.GAME[0]:
        bl = Part("steel", bevel=0.0, name="field bolts")
        for sx in (-1, 1):
            for y in (-0.08, 0.08, y0 + 0.1, y1 - 0.1):
                bl.bolt((sx * (x1 - 0.06), y, 0.068), axis=(0, 0, 1), r=0.009, h=0.004)
        bl.done()


@asset("floor_grating", views=[(-0.25, -0.75, 1.0), (1.0, -0.5, 0.45)])
def floor_grating():
    x0, y0, x1, y1 = tile_frame(open_middle=True)
    Part("dark", bevel=0.0, name="pit").box((x0, y0, 0.0), (x1, y1, 0.012)).done()
    Part("mesh", bevel=0.0, name="mesh").box((x0, y0, 0.03), (x1, y1, 0.04)).done()
    g = Part("pipe", bevel=0.0 if S.GAME[0] else 0.003, name="bars")
    for ya, yb in ((y0, -0.08), (0.08, y1)):
        g.grid_xy(x0, x1, ya, yb, 0.03, 0.058, 3, 4, bar=0.022)
    g.box((x0, -0.08, 0.03), (x1, 0.08, 0.062))              # the bridge across the middle
    g.done()
    Part("floor", bevel=0.004, name="bridge").plate_xy(chamfer(-0.2, -0.05, 0.2, 0.05, 0.02), 0.062, 0.07).done()
    lv = Part("pipe", bevel=0.002, name="slats")             # the slats at one end
    for i in range(5):
        lv.box((x0 + 0.04, y0 + 0.03 + i * 0.035, 0.04), (x1 - 0.04, y0 + 0.048 + i * 0.035, 0.062))
    lv.done()


@asset("floor_hazard", views=[(-0.25, -0.75, 1.0), (1.0, -0.5, 0.45)])
def floor_hazard():
    x0, y0, x1, y1 = tile_frame()
    f = Part("hazard", bevel=0.005, name="fields")
    f.plate_xy(chamfer(x0, y0, x1, -0.006, (0.06, 0.06, 0.0, 0.0)), 0.04, 0.068)
    f.plate_xy(chamfer(x0, 0.006, x1, y1, (0.0, 0.0, 0.06, 0.06)), 0.04, 0.068)
    f.done()


# ------------------------------------------------------------------ ceilings: 2 x 2 m panels, hung face down (their face toward -z)
CW = 2.0


def ceiling_frame():
    """The square ceiling panel (references 06, 07): bevelled rim, a carrier above with brackets."""
    h = CW / 2
    rim = Part("white", bevel=0.02, name="panel")
    rim.plate_xy(chamfer(-h, -h, h, h, 0.07), -0.04, 0.06)
    rim.done()
    if S.GAME[0]:                                           # (in the game the panels hang edge to edge under the slab: a plain backing)
        Part("bluegrey", bevel=0.0, name="carrier").box((-h, -h, 0.02), (h, h, 0.05)).done()
    else:
        Part("bluegrey", bevel=0.006, name="carrier").box((-h - 0.03, -h - 0.03, 0.06), (h + 0.03, h + 0.03, 0.14)).done()
        br = Part("bluegrey", bevel=0.004, name="brackets")
        for sx in (-1, 1):
            for y in (-0.6, 0.6):
                br.box(tuple(sorted((sx * h, sx * (h + 0.07))))[0:1] + (y - 0.06, 0.0), tuple(sorted((sx * h, sx * (h + 0.07))))[1:2] + (y + 0.06, 0.16))
        br.done()
    sl = Part("dark", bevel=0.0, name="slots")
    for sx in (-1, 1):
        sl.box((sx * (h - 0.06) - 0.012, -0.3, -0.042), (sx * (h - 0.06) + 0.012, 0.3, -0.039))
    sl.done()


@asset("ceiling_light", views=[(-0.45, -1.0, -0.42), (1.0, -0.4, -0.2)])
def ceiling_light():
    ceiling_frame()
    h = CW / 2
    z = -0.04                                               # the panel's face (it looks down)
    pl = Part("white", bevel=0.006, name="plates")           # the plates the face is made of, with seams between
    for x0, y0, x1, y1 in ((-h + 0.1, 0.42, -0.02, h - 0.1), (0.02, 0.42, h - 0.1, h - 0.1), (-h + 0.1, -h + 0.1, -0.55, -0.42), (-0.51, -h + 0.1, 0.51, -0.47),
                           (0.55, -h + 0.1, h - 0.1, -0.42), (-h + 0.1, -0.38, -0.66, 0.38), (0.66, -0.38, h - 0.1, 0.38)):
        pl.plate_xy(chamfer(x0, y0, x1, y1, 0.02), z - 0.012, z + 0.01)
    pl.plate_xy(chamfer(-0.62, -0.43, 0.62, 0.38, 0.05), z - 0.03, z + 0.01)       # the raised surround of the lamp
    pl.done()
    Part("dark", bevel=0.0, name="well").box((-0.5, -0.3, z - 0.034), (0.5, 0.27, z - 0.028)).done()
    Part("light", bevel=0.01, name="lamp").box((-0.44, -0.25, z - 0.07), (0.44, 0.22, z - 0.03)).done()
    # the cage: two rails along, three hoops across
    for y in (-0.2, 0.17):
        pipe([(-0.56, y, z - 0.03), (-0.56, y, z - 0.1), (0.56, y, z - 0.1), (0.56, y, z - 0.03)], 0.012, "pipe", fillet=0.03)
    for x in ((0.0,) if S.GAME[0] else (-0.3, 0.3)):
        pipe([(x, -0.36, z - 0.03), (x, -0.36, z - 0.11), (x, 0.33, z - 0.11), (x, 0.33, z - 0.03)], 0.01, "pipe", fillet=0.03)
    # the conduit: from the lamp's surround across the face and up through the rim
    if S.GAME[0]:
        pipe([(0.1, 0.38, z - 0.05), (0.1, 0.55, z - 0.05), (0.32, 0.72, z - 0.05), (0.32, h - 0.04, z - 0.05)], 0.028, "pipe", fillet=0.07)
    else:
        pipe([(0.1, 0.38, z - 0.05), (0.1, 0.55, z - 0.05), (0.32, 0.72, z - 0.05), (0.32, h + 0.02, z - 0.05), (0.32, h + 0.02, 0.1), (0.62, h + 0.02, 0.1)], 0.028, "pipe", fillet=0.07)
        pipe([(0.2, 0.38, z - 0.04), (0.2, 0.52, z - 0.04), (0.4, 0.68, z - 0.04), (0.4, h - 0.02, z - 0.04)], 0.018, "pipe", fillet=0.05)
    cl = Part("steel", bevel=0.002, name="clamps")
    cl.box((0.26, 0.76, z - 0.085), (0.45, 0.8, z)).box((0.04, 0.44, z - 0.085), (0.26, 0.48, z))
    for x0, y0, x1, y1 in ((-0.42, 0.44, -0.3, 0.5), (0.34, -0.46, 0.5, -0.4), (-0.5, -0.46, -0.3, -0.4)):       # small vents
        cl.box((x0, y0, z - 0.02), (x1, y1, z - 0.012))
    cl.done()
    Part("dark", bevel=0.0, name="vent slots").box((-0.41, 0.455, z - 0.022), (-0.31, 0.465, z - 0.02)).box((-0.41, 0.475, z - 0.022), (-0.31, 0.485, z - 0.02)) \
        .box((0.35, -0.445, z - 0.022), (0.49, -0.435, z - 0.02)).box((0.35, -0.425, z - 0.022), (0.49, -0.415, z - 0.02)).done()
    Part("ledred", bevel=0.0, name="led").box((-0.22, -0.455, z - 0.016), (-0.19, -0.44, z - 0.012)).done()
    Part("ledgreen", bevel=0.0, name="led").box((-0.17, -0.455, z - 0.016), (-0.14, -0.44, z - 0.012)).done()
    bl = Part("steel", bevel=0.0, name="bolts")
    for sx in (-1, 1):
        for sy in (-1, 1):
            bl.bolt((sx * (h - 0.16), sy * (h - 0.16), z - 0.012), axis=(0, 0, -1), r=0.014, h=0.008)
    bl.done()


@asset("ceiling_services", views=[(-0.45, -1.0, -0.42), (1.0, -0.4, -0.2)])
def ceiling_services():
    ceiling_frame()
    h = CW / 2
    z = -0.04
    Part("white", bevel=0.006, name="plates").plate_xy(chamfer(-h + 0.1, -h + 0.1, h - 0.1, h - 0.1, 0.05), z - 0.012, z + 0.01).done()
    # the duct along one side: four sections with joint bands, its end turned up
    d = Part("pipe", bevel=0.012, name="duct")
    for i in range(4):
        d.box((-0.92 + i * 0.47, 0.5, z - 0.3), (-0.48 + i * 0.47, 0.88, z - 0.02))
    d.done()
    db = Part("steel", bevel=0.004, name="duct bands")
    for i in range(5):
        db.box((-0.95 + i * 0.47, 0.48, z - 0.32), (-0.92 + i * 0.47, 0.9, z))
    db.done()
    # the big pipe, flanged, with elbows up at both ends
    pipe([(-0.86, 0.22, z - 0.03), (-0.86, 0.22, z - 0.2), (0.86, 0.22, z - 0.2), (0.86, 0.22, z - 0.03)], 0.085, "pipe", fillet=0.13)
    fl = Part("steel", bevel=0.004, name="flanges")
    for x in (-0.3, 0.26, 0.42):
        fl.cyl((x - 0.022, 0.22, z - 0.2), (x + 0.022, 0.22, z - 0.2), 0.11, segs=20)
    for x in (-0.55, 0.0, 0.62):                            # the pipe's hangers
        fl.box((x - 0.02, 0.1, z - 0.31), (x + 0.02, 0.34, z - 0.29)).box((x - 0.02, 0.1, z - 0.3), (x + 0.02, 0.12, z)).box((x - 0.02, 0.32, z - 0.3), (x + 0.02, 0.34, z))
    fl.done()
    # the ventilation unit
    Part("white", bevel=0.012, name="unit").box((0.12, -0.36, z - 0.24), (0.9, 0.02, z - 0.01)).done()
    Part("dark", bevel=0.0, name="unit back").box((0.2, -0.3, z - 0.246), (0.82, -0.14, z - 0.24)).box((0.5, -0.1, z - 0.246), (0.82, -0.04, z - 0.24)).done()
    lv = Part("pipe", bevel=0.002, name="unit slats")
    for i in range(6):
        lv.box((0.21, -0.295 + i * 0.027, z - 0.262), (0.81, -0.283 + i * 0.027, z - 0.24))
    for i in range(8):
        lv.box((0.51 + i * 0.04, -0.1, z - 0.258), (0.522 + i * 0.04, -0.04, z - 0.24))
    lv.done()
    # two cable trays of wire: one straight, one that bends across to join it
    def tray(points, width=0.3, depth=0.07):
        w = Part("steel", bevel=0.0, name="tray")
        for a, b in zip(points[:-1], points[1:]):
            ax, ay = a
            bx_, by_ = b
            ln = math.hypot(bx_ - ax, by_ - ay)
            ux, uy = (bx_ - ax) / ln, (by_ - ay) / ln
            nx, ny = -uy, ux
            for off in (-width / 2, width / 2):               # the side rails, top and bottom
                for zz in (z - 0.36, z - 0.36 - depth):
                    w.cyl((ax + nx * off, ay + ny * off, zz), (bx_ + nx * off, by_ + ny * off, zz), 0.007, segs=6)
            for k in range(int(ln / 0.12) + 1):               # the rungs and uprights
                px, py = ax + ux * k * 0.12, ay + uy * k * 0.12
                w.cyl((px - nx * width / 2, py - ny * width / 2, z - 0.36 - depth), (px + nx * width / 2, py + ny * width / 2, z - 0.36 - depth), 0.005, segs=5)
                for off in (-width / 2, width / 2):
                    w.cyl((px + nx * off, py + ny * off, z - 0.36), (px + nx * off, py + ny * off, z - 0.36 - depth), 0.005, segs=5)
        w.done()
        for k in range(6):                                  # the cables lying in it
            off = (k - 2.5) * width / 7.5
            pts = []
            for a, b in zip(points[:-1], points[1:]):
                ln = math.hypot(b[0] - a[0], b[1] - a[1])
                nx, ny = -(b[1] - a[1]) / ln, (b[0] - a[0]) / ln
                pts += [(a[0] + nx * off, a[1] + ny * off, z - 0.36 - depth + 0.02), (b[0] + nx * off, b[1] + ny * off, z - 0.36 - depth + 0.02)]
            cable(pts, 0.013, ("cable", "pipe", "cable", "cable", "pipe", "cable")[k])
    tray([(-1.02, -0.72), (1.02, -0.72)])
    tray([(-1.02, -0.2), (-0.5, -0.2), (-0.12, -0.56)], width=0.26)
    hg = Part("steel", bevel=0.002, name="tray hangers")
    for x in (-0.7, 0.0, 0.7):
        hg.box((x - 0.012, -0.9, z - 0.45), (x + 0.012, -0.88, z)).box((x - 0.012, -0.56, z - 0.45), (x + 0.012, -0.54, z)).box((x - 0.012, -0.9, z - 0.45), (x + 0.012, -0.54, z - 0.435))
    hg.done()
    # three drops: square ducts down from the panel at the far edge
    dp = Part("pipe", bevel=0.01, name="drops")
    for x in (-0.72, -0.1, 0.56):
        dp.box((x - 0.15, -1.0, z - 0.34), (x + 0.15, -0.92, z - 0.02))
    dp.done()


# ------------------------------------------------------------------ the corridor section (reference 08): 4 m wide, 3.4 m high, 4 m long
KW, KH, KL = 4.0, 3.4, 4.0


@asset("corridor", views=[(-1.0, -0.62, 0.3), (0.0, -1.0, 0.08)], res=[(760, 620), (560, 620)], hide=["near_", None])
def corridor(variant=0):
    """variant 0: the reference's (a wire tray under the ceiling, a rail and small boxes on the walls);
    1: a display on one wall, a duct under the ceiling; 2: three pipes with a valve along one wall, more floor grating."""
    hw, hl = KW / 2, KL / 2
    # floor: a slab with two plates, grating strips along the walls, a marked line
    Part("bluegrey", bevel=0.01, name="floor slab").box((-hw - 0.12, -hl, -0.16), (hw + 0.12, hl, -0.02)).done()
    fp = Part("floor", bevel=0.006, name="floor plates")
    for y0, y1 in ((-hl + 0.03, -0.02), (0.02, hl - 0.03)):
        fp.plate_xy(chamfer(-hw + 0.5, y0, -0.02, y1, 0.04), -0.02, 0.012).plate_xy(chamfer(0.02, y0, hw - 0.5, y1, 0.04), -0.02, 0.012)
    fp.done()
    for sx in (-1, 1):
        x0, x1 = sorted((sx * (hw - 0.48), sx * (hw - 0.14)))
        Part("mesh", bevel=0.0, name="floor grating").box((x0, -hl + 0.03, -0.02), (x1, hl - 0.03, 0.002)).done()
        g = Part("pipe", bevel=0.002, name="floor grating bars")
        g.grid_xy(x0, x1, -hl + 0.03, hl - 0.03, -0.02, 0.012, 1, 10, bar=0.03)
        g.done()
    Part("hazard", bevel=0.002, name="floor line").box((-hw + 0.52, -hl + 0.2, 0.012), (-hw + 0.6, -hl + 1.5, 0.016)).done()
    # ceiling: slab, two lamps, a wire tray, a conduit
    Part("bluegrey", bevel=0.01, name="ceiling slab").box((-hw - 0.12, -hl, KH + 0.02), (hw + 0.12, hl, KH + 0.16)).done()
    cp = Part("white", bevel=0.006, name="ceiling plates")
    cp.plate_xy(chamfer(-hw + 0.5, -hl + 0.03, hw - 0.5, hl - 0.03, 0.05), KH - 0.012, KH + 0.02)
    for y in (-1.0, 1.0):
        cp.plate_xy(chamfer(-0.55, y - 0.36, 0.55, y + 0.36, 0.05), KH - 0.05, KH - 0.012)
    cp.done()
    for y in (-1.0, 1.0):
        Part("light", bevel=0.006, name="lamp").box((-0.42, y - 0.24, KH - 0.07), (0.42, y + 0.24, KH - 0.05)).done()
        Part("pipe", bevel=0.003, name="lamp bars").box((-0.44, y - 0.01, KH - 0.085), (0.44, y + 0.01, KH - 0.05)).done()
    if variant == 1:                                         # a duct in place of the tray, on hangers
        Part("grey", bevel=0.012, name="duct").box((0.86, -hl + 0.02, KH - 0.3), (1.36, hl - 0.02, KH - 0.06)).done()
        hg = Part("pipe", bevel=0.004, name="duct hangers")
        for y in (-1.3, 0.0, 1.3):
            hg.box((0.84, y - 0.03, KH - 0.32), (1.38, y + 0.03, KH - 0.3)).box((0.84, y - 0.03, KH - 0.32), (0.86, y + 0.03, KH)).box((1.36, y - 0.03, KH - 0.32), (1.38, y + 0.03, KH))
        hg.done()
    elif variant == 2:                                       # two pipes under the ceiling
        for x in (0.95, 1.22):
            pipe([(x, -hl + 0.05, KH - 0.1), (x, hl - 0.05, KH - 0.1)], 0.055 if x < 1.0 else 0.04, "pipe")
        cl = Part("grey", bevel=0.004, name="pipe clamps")
        for y in (-1.2, 1.2):
            cl.box((0.86, y - 0.04, KH - 0.18), (1.3, y + 0.04, KH - 0.16)).box((0.86, y - 0.04, KH - 0.18), (0.88, y + 0.04, KH)).box((1.28, y - 0.04, KH - 0.18), (1.3, y + 0.04, KH))
        cl.done()
    else:
        tr = Part("steel", bevel=0.0, name="tray")
        for x in (0.95, 1.3):
            tr.cyl((x, -hl + 0.05, KH - 0.16), (x, hl - 0.05, KH - 0.16), 0.008, segs=6).cyl((x, -hl + 0.05, KH - 0.08), (x, hl - 0.05, KH - 0.08), 0.008, segs=6)
        for k in range(27):
            y = -hl + 0.1 + k * 0.146
            tr.cyl((0.95, y, KH - 0.16), (1.3, y, KH - 0.16), 0.005, segs=5).cyl((0.95, y, KH - 0.16), (0.95, y, KH - 0.08), 0.005, segs=5).cyl((1.3, y, KH - 0.16), (1.3, y, KH - 0.08), 0.005, segs=5)
        tr.done()
        for k in range(4):
            cable([(1.0 + k * 0.08, -hl + 0.06, KH - 0.14), (1.01 + k * 0.08, 0.0, KH - 0.142), (1.0 + k * 0.08, hl - 0.06, KH - 0.14)], 0.015, ("cable", "pipe", "cable", "cable")[k])
    pipe([(-1.1, -hl + 0.05, KH - 0.06), (-1.1, hl - 0.05, KH - 0.06)], 0.035, "pipe")
    # the walls: ribs with braced corners, between them three panels a side
    for sx in (-1, 1):
        S.prefix[0] = "near_" if sx < 0 else ""                 # (the first picture leaves this wall out, to show the inside)
        xw = sx * hw                                            # the wall's face
        Part("bluegrey", bevel=0.01, name="wall carrier").box(tuple(sorted((xw + sx * 0.02, xw + sx * 0.14)))[0:1] + (-hl, 0.0),
                                                              tuple(sorted((xw + sx * 0.02, xw + sx * 0.14)))[1:2] + (hl, KH)).done()
        rb = Part("white", bevel=0.012, name="ribs")
        for y in (-hl + 0.07, -hl / 3, hl / 3, hl - 0.07):
            # a rib: a post, with a brace cut across the floor corner and the ceiling corner (seen along the corridor)
            prof = [(xw, 0.0), (xw - sx * 0.5, 0.0), (xw - sx * 0.5, 0.06), (xw - sx * 0.22, 0.42), (xw - sx * 0.22, KH - 0.42), (xw - sx * 0.5, KH - 0.06),
                    (xw - sx * 0.5, KH), (xw, KH)]
            rb._extrude([(px, y - 0.07, pz) for px, pz in (prof if sx > 0 else prof[::-1])], (0, 0.14, 0))
        rb.done()
        pn = Part("white", bevel=0.008, name="wall panels")
        for i in range(3):
            y0, y1 = -hl + 0.16 + i * (KL - 0.18) / 3, -hl + 0.02 + (i + 1) * (KL - 0.18) / 3
            x0, x1 = sorted((xw - sx * 0.07, xw + sx * 0.02))
            pn.plate_yz(chamfer(y0, 0.5, y1, KH - 0.52, 0.05), x0, x1)
            pn.plate_yz(chamfer(y0 + 0.02, 0.14, y1 - 0.02, 0.46, (0.0, 0.0, 0.04, 0.04)), x0 + (0.0 if sx > 0 else 0.0), x1)       # the skirting plate
        pn.done()
        dk = Part("dark", bevel=0.0, name="wall seams")
        for i in range(3):
            y0, y1 = -hl + 0.16 + i * (KL - 0.18) / 3, -hl + 0.02 + (i + 1) * (KL - 0.18) / 3
            x0, x1 = sorted((xw - sx * 0.072, xw - sx * 0.069))
            dk.box((x0, y0 + 0.08, 1.38), (x1, y1 - 0.08, 1.39))
        dk.done()
        xf = xw - sx * 0.07
        y0 = -hl + 0.16 + (KL - 0.18) / 3
        x0, x1 = sorted((xf, xf - sx * 0.02))
        if variant == 1 and sx > 0:
            # a display in the middle panel, a status strip under it
            xa, xb = sorted((xf - sx * 0.012, xf - sx * 0.03))
            Part("dark", bevel=0.006, name="display frame").plate_yz(chamfer(y0 + 0.1, 1.05, y0 + 1.02, 2.2, 0.04), x0, x1).done()
            Part("panelscreen", bevel=0.0, name="display").box((xa, y0 + 0.16, 1.11), (xb, y0 + 0.96, 2.14)).done()
            Part("ledgreen", bevel=0.0, name="status").box((xa, y0 + 0.2, 0.9), (xb, y0 + 0.3, 0.93)).done()
            Part("orange", bevel=0.0, name="status").box((xa, y0 + 0.36, 0.9), (xb, y0 + 0.46, 0.93)).done()
        elif variant == 2 and sx > 0:
            # three pipes along the wall through the ribs, a valve on the middle one
            for k, z in enumerate((1.2, 1.42, 1.64)):
                pipe([(xw - sx * 0.16, -hl + 0.05, z), (xw - sx * 0.16, hl - 0.05, z)], (0.045, 0.06, 0.035)[k], "pipe")
            fl = Part("grey", bevel=0.004, name="flanges")
            for y in (y0 + 0.25, y0 + 0.85):
                fl.cyl((xw - sx * 0.16, y - 0.02, 1.42), (xw - sx * 0.16, y + 0.02, 1.42), 0.085, segs=12)
            fl.done()
            valve_wheel((xw - sx * 0.27, y0 + 0.55, 1.42), (-sx, 0, 0), R=0.1)
            Part("pipe", bevel=0.0, name="valve stem").cyl((xw - sx * 0.16, y0 + 0.55, 1.42), (xw - sx * 0.27, y0 + 0.55, 1.42), 0.016, segs=6).done()
        else:
            # what is on the panels: a rail on one, a vent and a small box on another, a riser between two ribs
            handle((xf, y0 + 0.2, 1.75), (xf, y0 + 0.9, 1.75), (-sx * 0.06, 0, 0), r=0.022, material="pipe")
            sm = Part("grey", bevel=0.004, name="wall fittings")
            sm.box((x0, y0 + 0.2, 0.62), (x1, y0 + 0.85, 0.8)).box((x0, y0 + 0.75, 1.2), (x1, y0 + 0.95, 1.42)).box((x0, -hl + 0.5, 2.3), (x1, -hl + 1.1, 2.36))
            sm.done()
        pipe([(xw - sx * 0.2, hl / 3 + 0.16, 0.44), (xw - sx * 0.2, hl / 3 + 0.16, KH - 0.44)], 0.035, "pipe")
        pipe([(xw - sx * 0.12, -hl + 0.05, 0.25), (xw - sx * 0.12, hl - 0.05, 0.25)], 0.03, "pipe")
        st = Part("light", bevel=0.0, name="cove")
        x0, x1 = sorted((xw - sx * 0.24, xw - sx * 0.2))
        st.box((x0, -hl + 0.2, KH - 0.47), (x1, hl - 0.2, KH - 0.44))
        st.done()
    S.prefix[0] = ""


# ------------------------------------------------------------------ the column (reference 09): 0.9 m square; height to order
@asset("column", views=[(-0.6, -1.0, 0.18), (1.0, -0.25, 0.1)], res=[(560, 620), (460, 620)])
def column(height=3.4):
    h, r = height, 0.4
    Part("white", bevel=0.012, name="shaft").plate_xy(chamfer(-r, -r, r, r, 0.05), 0.12, h - 0.1).done()
    pl = Part("white", bevel=0.008, name="plates")           # raised plates on the faces, a seam at mid height
    for a in range(4):
        m = T(rz=90 * a)
        for z0, z1 in ((0.5, h * 0.5 - 0.02), (h * 0.5 + 0.02, h - 0.55)):
            q = Part("white", bevel=0.008, name="plate")
            q.plate_xz(chamfer(-r + 0.09, z0, r - 0.09, z1, 0.03), -r - 0.018, -r + 0.01)
            q.done(m)
    pl.done()
    bd = Part("grey", bevel=0.006, name="bands")
    for z in (h * 0.28, h * 0.68):
        bd.plate_xy(chamfer(-r - 0.03, -r - 0.03, r + 0.03, r + 0.03, 0.06), z, z + 0.16)
    bd.done()
    # the foot and the head: four braced brackets each
    for a in range(4):
        m = T(rz=90 * a)
        br = Part("white", bevel=0.01, name="brackets")
        for sx in (-1, 1):
            x0, x1 = sorted((sx * 0.1, sx * 0.34))
            br.plate_yz([(-r - 0.3, 0.0), (-r + 0.02, 0.0), (-r + 0.02, 0.5), (-r - 0.06, 0.5), (-r - 0.3, 0.12)], x0, x1)           # foot gusset
            br.plate_yz([(-r - 0.3, h), (-r - 0.3, h - 0.12), (-r - 0.06, h - 0.46), (-r + 0.02, h - 0.46), (-r + 0.02, h)], x0, x1)   # head gusset
        br.box((-0.4, -r - 0.34, 0.0), (0.4, -r - 0.02, 0.06)).box((-0.42, -r - 0.36, h - 0.07), (0.42, -r - 0.02, h))
        br.done(m)
        bl = Part("steel", bevel=0.0, name="bolts")
        for sx in (-1, 1):
            for z in (h * 0.28 + 0.08, h * 0.68 + 0.08):
                bl.bolt((sx * 0.3, -r - 0.03, z), r=0.014, h=0.008)
            for z in (0.2, 0.36, h - 0.2, h - 0.34):
                bl.bolt((sx * 0.4, -r - 0.018, z), r=0.011, h=0.007)
        bl.done(m)
    # one face carries services: a riser, a vent, two boxes, cables
    y = -r - 0.018
    pipe([(-0.2, y - 0.045, 0.62), (-0.2, y - 0.045, h - 0.75), (-0.08, y - 0.045, h - 0.66), (0.12, y - 0.045, h - 0.66)], 0.03, fillet=0.06)
    pipe([(-0.1, y - 0.035, 0.62), (-0.1, y - 0.035, h - 0.95)], 0.02)
    bx = Part("white", bevel=0.008, name="boxes")
    bx.box((0.08, y - 0.1, h - 0.82), (0.3, y, h - 0.6)).box((-0.28, y - 0.09, h * 0.47), (-0.04, y, h * 0.47 + 0.2)).box((0.06, y - 0.08, 0.72), (0.28, y, 0.94))
    bx.done()
    v = Part("white", bevel=0.006, name="vent frame")
    v.frame_xz(0.0, h * 0.42, 0.3, h * 0.42 + 0.5, 0.04, y - 0.05, y)
    v.done()
    Part("dark", bevel=0.0, name="vent back").box((0.03, y - 0.01, h * 0.42 + 0.03), (0.27, y - 0.004, h * 0.42 + 0.47)).done()
    Part("pipe", bevel=0.002, name="louvres").louvres(0.035, 0.265, h * 0.42 + 0.04, h * 0.42 + 0.46, y - 0.042, 8, depth=0.03).done()
    for k in range(3):
        cable([(0.12 + k * 0.035, y - 0.03, h - 0.82), (0.11 + k * 0.035, y - 0.035, h - 1.0), (-0.02 + k * 0.03, y - 0.035, h * 0.42 + 0.62), (-0.03 + k * 0.03, y - 0.03, 1.0),
               (0.1 + k * 0.03, y - 0.03, 0.94)], 0.01, ("cable", "cable_tan", "cable")[k])
    Part("ledgreen", bevel=0.0, name="led").box((-0.24, y - 0.094, h * 0.47 + 0.12), (-0.16, y - 0.09, h * 0.47 + 0.16)).done()
    # the opposite face: a channel with two pipes running in it
    Part("dark", bevel=0.0, name="channel").box((-0.1, r + 0.0, 0.5), (0.1, r + 0.02, h - 0.5)).done()
    for x in (-0.04, 0.04):
        pipe([(x, r + 0.035, 0.45), (x, r + 0.035, h - 0.45)], 0.022)


# ------------------------------------------------------------------ pieces only the game needs (not on the sheets)
@asset("wall_upper", game=True)
def wall_upper():
    """The second row of a room's wall: the same panel, 1.8 m high (a room is 5.2 m: plinth 0.4 + 3.0 + 1.8).
    Above head height, and two to every wall cell: border and fields only."""
    hw, h, bd = PW / 2, 1.8, 0.11
    Part("bluegrey", bevel=0.0, name="carrier").box((-hw, 0.03, 0.0), (hw, 0.11, h)).done()
    Part("white", bevel=0.008, name="border").plate_xz(chamfer(-hw, 0.0, hw, h, 0.035), -0.012, 0.03).done()
    Part("white", bevel=0.007, name="field").plate_xz(chamfer(-hw + bd, bd, hw - bd, h - bd, 0.02), -0.045, -0.012).done()
    Part("accent", bevel=0.003, name="upper line").box((-hw + 0.04, -0.024, 0.025), (hw - 0.04, -0.004, 0.095)).done()


@asset("corridor_b", game=True)
def corridor_b():
    corridor(1)


@asset("corridor_c", game=True)
def corridor_c():
    corridor(2)


@asset("wall_plinth", game=True)
def wall_plinth():
    """The foot of a room's wall: 0.4 m of dark plinth under the panels, one panel wide."""
    hw = PW / 2
    Part("grey", bevel=0.008, name="plinth").plate_xz(chamfer(-hw, 0.0, hw, 0.4, (0.0, 0.0, 0.02, 0.02)), -0.03, 0.11).done()
    Part("grey", bevel=0.006, name="plinth foot").box((-hw, -0.06, 0.0), (hw, -0.03, 0.09)).done()
    Part("accent", bevel=0.003, name="plinth line").box((-hw, -0.04, 0.265), (hw, -0.02, 0.36)).done()       # the room's colour
    Part("dark", bevel=0.0, name="plinth slots").box((-0.5, -0.032, 0.2), (-0.1, -0.03, 0.23)).box((0.1, -0.032, 0.2), (0.5, -0.03, 0.23)).done()


@asset("ceiling_plain", game=True, views=[(-0.45, -1.0, -0.42), (1.0, -0.4, -0.2)])
def ceiling_plain():
    ceiling_frame()
    h = CW / 2
    pl = Part("white", bevel=0.006, name="plates")
    pl.plate_xy(chamfer(-h + 0.1, -h + 0.1, -0.02, h - 0.1, 0.03), -0.052, -0.03).plate_xy(chamfer(0.02, -h + 0.1, h - 0.1, h - 0.1, 0.03), -0.052, -0.03)
    pl.done()


@asset("door_frame", game=True)
def door_frame_piece():
    door(frame=True, leaves=(), half=True)


@asset("door_leaf_l", game=True)
def door_leaf_l():
    door(frame=False, leaves=("L",), half=True)


@asset("door_leaf_r", game=True)
def door_leaf_r():
    door(frame=False, leaves=("R",), half=True)


@asset("door_surround", game=True)
def door_surround():
    """What closes a doorway's cell round the door frame (3.64 m wide, 3.32 m high) up to the wall's second row:
    a strip each side and one over the top, half the wall deep (one stands on each side of the wall)."""
    ow, oh = DW + 0.62, DH + 0.72
    p = Part("white", bevel=0.008, name="surround")
    p.box((-2.0, 0.0, 0.0), (-ow, 0.15, 3.4)).box((ow, 0.0, 0.0), (2.0, 0.15, 3.4)).box((-ow, 0.0, oh), (ow, 0.15, 3.4))
    p.done()


@asset("column_tall", game=True)
def column_tall():
    """The column at a room's height (5.2 m)."""
    column(height=5.2)
