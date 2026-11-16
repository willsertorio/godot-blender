"""The environment set: cover, the free-standing things (see build_set.py). References 10 to 15."""
import math

import setlib as S
from setlib import Part, T, asset, cable, chamfer, handle, pipe, rect, ring, rounded, valve_wheel


def crate_body(w=1.0, d=0.62, h=0.62, shell="white", z=0.0, lamps=True):
    """The equipment case of the set: a shell split by a grey band two thirds up, corner guards, latches on the
    front, a handle in each end, a ridge on the lid. Its foot at z."""
    hw, hd = w / 2, d / 2
    seam = z + h * 0.6
    c = 0.035
    Part(shell, bevel=0.012, name="lower").plate_xy(chamfer(-hw, -hd, hw, hd, c), z + 0.03, seam - 0.02).done()
    Part(shell, bevel=0.016, name="lid").plate_xy(chamfer(-hw, -hd, hw, hd, c), seam + 0.02, z + h - 0.035).done()
    g = Part("grey", bevel=0.006, name="band")
    g.plate_xy(chamfer(-hw - 0.008, -hd - 0.008, hw + 0.008, hd + 0.008, c), seam - 0.02, seam + 0.02)
    g.plate_xy(chamfer(-hw * 0.62, -hd * 0.62, hw * 0.62, hd * 0.62, 0.05), z + h - 0.035, z + h)           # the lid's ridge
    g.plate_xy(chamfer(-hw + 0.02, -hd + 0.02, hw - 0.02, hd - 0.02, c), z, z + 0.03)                      # the foot
    g.done()
    # corner guards: a chunky block on each of the eight corners, cut at 45 degrees
    gd = Part("grey", bevel=0.01, name="guards")
    gw, gh = min(0.15, w * 0.16), h * 0.24
    for sx in (-1, 1):
        for sy in (-1, 1):
            for z0, z1 in ((z, z + gh), (z + h - gh - 0.02, z + h - 0.01)):
                x0, x1 = sorted((sx * (hw + 0.012), sx * (hw - gw)))
                y0, y1 = sorted((sy * (hd + 0.012), sy * (hd - gw)))
                cut = [0.0, 0.0, 0.0, 0.0]
                cut[{(-1, -1): 0, (1, -1): 1, (1, 1): 2, (-1, 1): 3}[(sx, sy)]] = c + 0.012
                gd.plate_xy(chamfer(x0, y0, x1, y1, tuple(cut)), z0, z1)
    gd.done()
    # the plate let into the lower front and back, with two slots
    for sy in (-1, 1):
        y = sy * hd
        pl = Part("grey", bevel=0.004, name="plate")
        pl.plate_xz(chamfer(-hw * 0.44, z + 0.07, hw * 0.44, seam - 0.07, (0.0, 0.0, 0.035, 0.035)), y - 0.007 * (sy < 0) - 0.0, y + 0.007 * (sy > 0) + 0.0)
        pl.done()
        Part("dark", bevel=0.0, name="slots").box((-hw * 0.2, y + sy * 0.007, z + 0.11), (-hw * 0.06, y + sy * 0.009, z + 0.125)) \
            .box((hw * 0.06, y + sy * 0.007, z + 0.11), (hw * 0.2, y + sy * 0.009, z + 0.125)).done()
    # latches on the front, hinges on the back
    lt = Part("darksteel", bevel=0.004, name="latches")
    for sx in (-1, 1):
        x = sx * hw * 0.5
        lt.box((x - 0.035, -hd - 0.022, seam - 0.075), (x + 0.035, -hd - 0.006, seam + 0.075))
        lt.box((x - 0.022, -hd - 0.034, seam - 0.05), (x + 0.022, -hd - 0.02, seam + 0.035))
        lt.cyl((x - 0.03, -hd - 0.024, seam + 0.062), (x + 0.03, -hd - 0.024, seam + 0.062), 0.011, segs=10)
        lt.box((x - 0.045, hd + 0.004, seam - 0.03), (x + 0.045, hd + 0.016, seam + 0.03))
        lt.cyl((x - 0.05, hd + 0.02, seam), (x + 0.05, hd + 0.02, seam), 0.01, segs=10)
    lt.done()
    # a handle in each end, in a dark recess
    for sx in (-1, 1):
        x = sx * hw
        Part("dark", bevel=0.004, name="recess").plate_yz(chamfer(-hd * 0.42, seam - 0.17, hd * 0.42, seam - 0.045, 0.02), x, x + sx * 0.006).done()
        handle((x + sx * 0.004, -hd * 0.26, seam - 0.075), (x + sx * 0.004, hd * 0.26, seam - 0.075), (sx * 0.034, 0, -0.04), r=0.009)
    if lamps:
        Part("cyan", bevel=0.0, name="lamp").box((-0.04, -hd - 0.003, seam + 0.07), (0.04, -hd + 0.002, seam + 0.082)).done()
        Part("orange", bevel=0.0, name="lamp").box((-hw + 0.06, -hd - 0.003, seam - 0.04), (-hw + 0.085, -hd + 0.002, seam - 0.03)) \
            .box((hw * 0.72, -hd - 0.014, z + 0.19), (hw * 0.72 + 0.03, -hd - 0.011, z + 0.2)).done()
        Part("cyan", bevel=0.0, name="lamp").box((-hw + 0.03, -hd - 0.003, seam - 0.04), (-hw + 0.055, -hd + 0.002, seam - 0.03)).done()


@asset("crate")
def crate():
    crate_body()


@asset("crate_stack", views=[(-0.6, -1.0, 0.3), (1.0, -0.4, 0.15)])
def crate_stack():
    root = S._root[0]
    for i, (x, y, z) in enumerate(((-0.52, 0.0, 0.0), (0.52, 0.0, 0.0), (-0.52, 0.0, 0.64), (0.5, 0.02, 0.64))):
        sub = S.begin("crate_stack_%d" % i)
        sub.parent = root
        sub.location = (x, y, z)
        crate_body()
    S._root[0] = root


# ------------------------------------------------------------------ the drum (reference 11): 0.62 m across, 0.92 m high
def drum_body(z=0.0):
    R, H = 0.3, 0.9
    seg = 28
    Part("white", bevel=0.006, name="ribbed body").cyl((0, 0, z + 0.2), (0, 0, z + 0.62), R - 0.012, segs=seg).done()
    rb = Part("white", bevel=0.01, name="ribs")
    for i in range(5):
        zc = z + 0.26 + i * 0.075
        rb.cyl((0, 0, zc - 0.022), (0, 0, zc + 0.022), R + 0.004, segs=seg)
    rb.done()
    g = Part("grey", bevel=0.012, name="shells")
    g.cyl((0, 0, z + 0.02), (0, 0, z + 0.2), R + 0.008, segs=seg)             # the foot shell
    g.cyl((0, 0, z), (0, 0, z + 0.03), R - 0.03, segs=seg)
    g.done()
    Part("white", bevel=0.014, name="top").cyl((0, 0, z + 0.62), (0, 0, z + H - 0.03), R + 0.002, segs=seg).cyl((0, 0, z + H - 0.03), (0, 0, z + H), R - 0.03, segs=seg).done()
    bd = Part("grey", bevel=0.005, name="bands")
    bd.cyl((0, 0, z + 0.6), (0, 0, z + 0.645), R + 0.014, segs=seg).cyl((0, 0, z + 0.18), (0, 0, z + 0.22), R + 0.014, segs=seg)
    bd.done()
    # the grey panels on the upper shell, the handles above them, the latch
    for a in (0, 90, 180, 270):
        m = T(rz=a + 45)
        Part("grey", bevel=0.008, name="panel").plate_xz(chamfer(-0.13, z + 0.68, 0.13, z + 0.83, 0.03), -R - 0.012, -R + 0.03).done(m)
    for a in (0, 180):
        m = T(rz=a)
        handle((-0.1, -R + 0.03, z + H - 0.05), (0.1, -R + 0.03, z + H - 0.05), (0, -0.07, 0.035), r=0.014, m=m)
        lt = Part("darksteel", bevel=0.004, name="latch")
        lt.box((-0.04, -R - 0.03, z + 0.56), (0.04, -R - 0.008, z + 0.7)).box((-0.026, -R - 0.042, z + 0.59), (0.026, -R - 0.028, z + 0.67))
        lt.box((-0.035, -R - 0.03, z + 0.14), (0.035, -R - 0.01, z + 0.24))
        lt.done(m)
    for a in (90, 270):
        handle((-0.08, -R - 0.0, z + 0.74), (0.08, -R - 0.0, z + 0.74), (0, -0.05, 0.0), r=0.012, m=T(rz=a))
    cp = Part("grey", bevel=0.006, name="caps")
    cp.cyl((-0.11, 0.02, z + H), (-0.11, 0.02, z + H + 0.03), 0.055, segs=8).cyl((0.12, -0.04, z + H), (0.12, -0.04, z + H + 0.035), 0.065, segs=8)
    cp.cyl((0.12, -0.04, z + H + 0.035), (0.12, -0.04, z + H + 0.05), 0.03, segs=8)
    cp.done()
    Part("cyan", bevel=0.0, name="lamp").box((-0.19, -R + 0.02, z + 0.655), (-0.15, -R + 0.03, z + 0.668)).done(T(rz=-28))
    Part("orange", bevel=0.0, name="lamp").box((-0.19, -R + 0.02, z + 0.655), (-0.15, -R + 0.03, z + 0.668)).done(T(rz=-20))


@asset("drum", res=[(560, 620), (460, 620)])
def drum():
    drum_body()


@asset("drum_stack", views=[(-0.5, -1.0, 0.28), (1.0, -0.45, 0.15)])
def drum_stack():
    root = S._root[0]
    for i, (x, y, z, rz) in enumerate(((-0.34, 0.2, 0.0, 10), (0.32, 0.22, 0.0, 80), (-0.02, -0.36, 0.0, 200), (-0.34, 0.2, 0.92, 120), (0.32, 0.22, 0.92, 300),
                                       (0.78, -0.3, 0.0, 30))):
        sub = S.begin("drum_stack_%d" % i)
        sub.parent = root
        sub.location = (x, y, z)
        sub.rotation_euler = (0, 0, math.radians(rz))
        drum_body()
    S._root[0] = root


# ------------------------------------------------------------------ the barrier (reference 12): 1.9 m wide, 1.25 m high
@asset("barrier", views=[(-0.5, -1.0, 0.2), (1.0, -0.12, 0.08)])
def barrier():
    w, h = 0.95, 1.25
    # the shield: a slab whose outline rises to two shoulders with a dip between, thicker at the foot
    out = [(-w + 0.08, 0.1), (w - 0.08, 0.1), (w, 0.2), (w, h - 0.22), (w - 0.12, h - 0.06), (w - 0.52, h - 0.06), (w - 0.6, h - 0.14), (-w + 0.6, h - 0.14),
           (-w + 0.52, h - 0.06), (-w + 0.12, h - 0.06), (-w, h - 0.22), (-w, 0.2)]
    Part("white", bevel=0.016, name="shield").plate_xz(out, -0.09, 0.09).done()
    Part("white", bevel=0.014, name="foot").plate_yz([(-0.17, 0.08), (0.17, 0.08), (0.17, 0.3), (0.09, 0.52), (-0.09, 0.52), (-0.17, 0.3)], -w + 0.06, w - 0.06).done()
    for sy in (-1, 1):
        m = T(rz=0 if sy < 0 else 180)
        g = Part("grey", bevel=0.008, name="plates")
        # the two angled plates of the X, the lower centre plate
        g.plate_xz([(-w + 0.14, 0.62), (-0.42, 0.62), (-0.2, 0.84), (-0.2, h - 0.26), (-w + 0.14, h - 0.26)], -0.104, -0.085)
        g.plate_xz([(w - 0.14, 0.62), (w - 0.14, h - 0.26), (0.2, h - 0.26), (0.2, 0.84), (0.42, 0.62)][::-1], -0.104, -0.085)
        g.plate_xz(chamfer(-0.36, 0.2, 0.36, 0.56, (0.05, 0.05, 0.0, 0.0)), -0.2, -0.16)
        g.done(m)
        st = Part("grey", bevel=0.006, name="struts")       # the diagonal struts and the cross beam
        for sx in (-1, 1):
            st.box((sx * 0.5 - 0.035, -0.125, 0.52), (sx * 0.5 + 0.035, -0.1, 1.1), rot=__import__("mathutils").Matrix.Rotation(math.radians(sx * 32), 4, "Y"),
                   pivot=(sx * 0.5, -0.11, 0.8))
        st.box((-0.34, -0.13, 0.56), (0.34, -0.1, 0.68))
        st.box((-0.14, -0.12, h - 0.2), (0.14, -0.09, h - 0.1))
        st.done(m)
        ft = Part("white", bevel=0.01, name="feet")         # the two blocks the shield stands on, with their wedges
        for sx in (-1, 1):
            ft.plate_yz([(-0.42, 0.0), (-0.16, 0.0), (-0.16, 0.34), (-0.2, 0.34), (-0.42, 0.1)], sx * 0.52 - 0.1, sx * 0.52 + 0.1)
        ft.done(m)
        Part("grey", bevel=0.006, name="foot plates").box((-0.64, -0.46, 0.0), (-0.4, -0.16, 0.05)).box((0.4, -0.46, 0.0), (0.64, -0.16, 0.05)).done(m)
        hz = Part("hazard", bevel=0.0, name="ticks")
        for x0, x1, z in ((-0.86, -0.56, h - 0.17), (0.56, 0.86, h - 0.17), (-0.24, 0.24, h - 0.36), (-0.3, 0.3, 0.72), (-0.88, -0.6, 0.5), (0.6, 0.88, 0.5)):
            hz.box((x0, -0.0915, z), (x1, -0.0895, z + 0.045))
        hz.done(m)
        Part("ledgreen", bevel=0.0, name="lamp").box((-0.6, -0.0925, h - 0.27), (-0.56, -0.09, h - 0.255)).done(m)
        Part("orange", bevel=0.0, name="lamp").box((-0.54, -0.0925, h - 0.27), (-0.5, -0.09, h - 0.255)).done(m)
        bl = Part("steel", bevel=0.0, name="bolts")
        for sx in (-1, 1):
            for x, z in ((0.82, 0.3), (0.82, 0.95), (0.3, 0.26), (0.3, 0.5)):
                bl.bolt((sx * x, -0.105 if x < 0.5 else -0.09, z), r=0.014, h=0.008)
        bl.done(m)
    for sx in (-1, 1):                                       # handles on the ends and on the shoulders
        handle((sx * w, 0.0, 0.55), (sx * w, 0.0, 0.95), (sx * 0.07, 0, 0), r=0.016)
        handle((sx * 0.62, 0.0, h - 0.06), (sx * 0.82, 0.0, h - 0.06), (0, 0, 0.07), r=0.016)


# ------------------------------------------------------------------ the specimen tank (reference 13): 1.3 m across, 2.3 m high
@asset("tank", views=[(-0.35, -1.0, 0.16), (0.95, -0.5, 0.12)], res=[(620, 620), (540, 620)])
def tank():
    R, H = 0.6, 2.3
    seg = 40
    Part("grey", bevel=0.01, name="plinth").cyl((0, 0, 0.0), (0, 0, 0.1), R + 0.06, segs=seg).cyl((0, 0, 0.1), (0, 0, 0.2), R + 0.02, segs=seg).done()
    Part("white", bevel=0.014, name="base").cyl((0, 0, 0.2), (0, 0, 0.5), R + 0.05, segs=seg).done()
    Part("white", bevel=0.016, name="cap").cyl((0, 0, 1.92), (0, 0, 2.16), R + 0.05, segs=seg).cyl((0, 0, 2.16), (0, 0, H), R - 0.08, segs=seg).done()
    bd = Part("grey", bevel=0.006, name="bands")
    bd.cyl((0, 0, 0.44), (0, 0, 0.52), R + 0.07, segs=seg).cyl((0, 0, 1.9), (0, 0, 1.98), R + 0.07, segs=seg).cyl((0, 0, 2.2), (0, 0, 2.26), R - 0.02, segs=seg)
    bd.done()
    Part("liquid", bevel=0.0, name="liquid").cyl((0, 0, 0.52), (0, 0, 1.88), R - 0.06, segs=seg).done()
    Part("tankglass", bevel=0.0, name="glass").cyl((0, 0, 0.5), (0, 0, 1.92), R - 0.01, segs=seg).done()
    # the back half is a white housing; the front a window in a bezel with cut corners
    hs = Part("white", bevel=0.012, name="housing")
    hs.plate_xy([(R * math.cos(math.radians(a)) * 1.06, R * math.sin(math.radians(a)) * 1.06) for a in range(20, 161, 10)] + [(-0.5, 0.2), (0.5, 0.2)][::-1] if False else
                [(R * 1.06 * math.cos(math.radians(a)), R * 1.06 * math.sin(math.radians(a))) for a in range(10, 171, 10)], 0.5, 1.92)
    hs.done()
    for sx in (-1, 1):                                       # the bezel's uprights, either side of the window
        m = T(rz=sx * 52)
        Part("white", bevel=0.012, name="bezel upright").plate_xz(chamfer(-0.07, 0.5, 0.07, 1.92, 0.0), -R - 0.03, -R + 0.03).done(m)
        Part("grey", bevel=0.006, name="clamp").box((-0.085, -R - 0.045, 1.15), (0.085, -R - 0.02, 1.33)).box((-0.085, -R - 0.045, 0.7), (0.085, -R - 0.02, 0.8)).done(m)
        pipe([(0.13, -R - 0.02, 0.5), (0.13, -R - 0.02, 1.9)], 0.02, "pipe", m=m)
    for z0, z1, name in ((0.5, 0.62, "sill"), (1.8, 1.92, "head")):
        pc = Part("white", bevel=0.01, name="bezel " + name)
        pc.plate_xy([((R + 0.03) * math.sin(math.radians(a)), -(R + 0.03) * math.cos(math.radians(a))) for a in range(-52, 53, 8)]
                    + [((R - 0.03) * math.sin(math.radians(a)), -(R - 0.03) * math.cos(math.radians(a))) for a in range(52, -53, -8)], z0, z1)
        pc.done()
    lt = Part("grey", bevel=0.006, name="latches")
    lt.box((-0.13, -R - 0.07, 1.96), (0.13, -R - 0.02, 2.1)).box((-0.13, -R - 0.07, 0.3), (0.13, -R - 0.02, 0.44))
    lt.done()
    Part("cyan", bevel=0.0, name="lamp").box((-0.08, -R - 0.073, 2.02), (0.08, -R - 0.07, 2.04)).box((-0.08, -R - 0.073, 0.36), (0.08, -R - 0.07, 0.38)).done()
    Part("ledred", bevel=0.0, name="lamp").box((-0.02, -R - 0.034, 1.84), (0.0, -R - 0.03, 1.855)).done()
    Part("ledgreen", bevel=0.0, name="lamp").box((0.01, -R - 0.034, 1.84), (0.03, -R - 0.03, 1.855)).done()
    # inside: a frame of two rails with brackets, and cables hanging
    ins = Part("steel", bevel=0.003, name="inside")
    for sx in (-1, 1):
        ins.box((sx * 0.3 - 0.02, 0.1, 0.55), (sx * 0.3 + 0.02, 0.14, 1.85))
        for z in (0.9, 1.5):
            ins.box(tuple(sorted((sx * 0.3, sx * 0.14)))[0:1] + (0.08, z), tuple(sorted((sx * 0.3, sx * 0.14)))[1:2] + (0.14, z + 0.05))
    ins.done()
    for k, (x0, x1) in enumerate(((-0.3, 0.25), (-0.2, 0.3), (0.05, -0.28))):
        cable([(x0, 0.1, 1.86), ((x0 + x1) / 2, 0.02, 1.55 - k * 0.12), (x1, 0.1, 1.86)], 0.008)
    # the feet: four braced brackets; the pipes round the foot; on the back a service face like the column's
    for a in (45, 135, 225, 315):
        m = T(rz=a)
        Part("white", bevel=0.01, name="foot").plate_yz([(-R - 0.3, 0.0), (-R - 0.02, 0.0), (-R - 0.02, 0.62), (-R - 0.09, 0.62), (-R - 0.3, 0.14)], -0.07, 0.07).done(m)
    Part("white", bevel=0.01, name="front foot").plate_xz(chamfer(-0.1, 0.0, 0.1, 0.36, (0.0, 0.0, 0.03, 0.03)), -R - 0.16, -R - 0.03).done()
    ring((0, 0, 0.14), (0, 0, 1), R + 0.085, 0.022, "pipe")
    ring((0, 0, 0.06), (0, 0, 1), R + 0.085, 0.016, "pipe")
    y = R + 0.04
    bk = Part("white", bevel=0.01, name="back plate")
    bk.box((-0.42, R - 0.2, 0.3), (0.42, y, 2.12))
    bk.plate_yz([(y, 2.12), (y + 0.02, 2.12), (y + 0.32, 2.3), (y + 0.32, 2.36), (R - 0.2, 2.36), (R - 0.2, 2.12)][::-1], -0.36, 0.36)       # the head bracket on the back
    bk.done()
    pipe([(-0.2, y + 0.04, 0.3), (-0.2, y + 0.04, 1.75), (-0.08, y + 0.04, 1.86), (0.14, y + 0.04, 1.86)], 0.03, fillet=0.06)
    pipe([(-0.3, y + 0.035, 0.3), (-0.3, y + 0.035, 2.1)], 0.022)
    bb = Part("white", bevel=0.008, name="back boxes")
    bb.box((0.1, y, 1.72), (0.34, y + 0.1, 1.96)).box((-0.1, y, 1.02), (0.08, y + 0.09, 1.3)).box((0.14, y, 0.6), (0.36, y + 0.08, 0.84))
    bb.done()
    v = Part("white", bevel=0.006, name="back vent")
    v.frame_xz(0.12, 1.0, 0.38, 1.6, 0.04, y, y + 0.05)
    v.done()
    Part("dark", bevel=0.0, name="back vent in").box((0.15, y + 0.004, 1.03), (0.35, y + 0.012, 1.57)).done()
    sl = Part("pipe", bevel=0.002, name="back slats")
    for i in range(9):
        sl.box((0.155, y + 0.012, 1.05 + i * 0.058), (0.345, y + 0.04, 1.075 + i * 0.058))
    sl.done()
    for k in range(3):
        cable([(0.16 + k * 0.035, y + 0.03, 1.72), (0.12 + k * 0.03, y + 0.035, 1.66), (0.02 + k * 0.03, y + 0.035, 1.4), (0.0 + k * 0.02, y + 0.03, 1.3)], 0.01)
    bd2 = Part("grey", bevel=0.005, name="back bands")
    for z in (0.9, 1.66):
        bd2.box((-0.44, y + 0.0, z), (-0.14, y + 0.03, z + 0.1))
    bd2.done()


def lifting_posts(hw, hd, h, post=0.1, foot=True, eyes=True):
    """The four corner posts of the heavy equipment (rack, core): square posts, a grey shoe and cap on each, a
    lifting eye on top."""
    for sx in (-1, 1):
        for sy in (-1, 1):
            x0, x1 = sorted((sx * hw, sx * (hw - post)))
            y0, y1 = sorted((sy * hd, sy * (hd - post)))
            Part("white", bevel=0.01, name="post").box((x0, y0, 0.1), (x1, y1, h - 0.08)).done()
            g = Part("grey", bevel=0.01, name="shoe")
            ex = 0.035
            g.plate_xy(chamfer(x0 - ex, y0 - ex, x1 + ex, y1 + ex, 0.025), 0.0, 0.16)
            g.plate_xy(chamfer(x0 - ex, y0 - ex, x1 + ex, y1 + ex, 0.025), h - 0.14, h)
            g.done()
            if eyes:
                xc, yc = (x0 + x1) / 2, (y0 + y1) / 2
                ring((xc, yc, h + 0.035), (1, 0, 0) if sy < 0 else (1, 0, 0), 0.03, 0.01, "darksteel")
                Part("grey", bevel=0.004, name="eye base").box((xc - 0.03, yc - 0.02, h), (xc + 0.03, yc + 0.02, h + 0.015)).done()


# ------------------------------------------------------------------ the server rack (reference 14): 1.0 x 1.1 m, 2.1 m high
@asset("server_rack", views=[(-0.55, -1.0, 0.18), (1.0, -0.75, 0.16)], res=[(580, 620), (580, 620)])
def server_rack():
    hw, hd, h = 0.5, 0.55, 2.1
    lifting_posts(hw, hd, h)
    Part("grey", bevel=0.01, name="plinth").box((-hw + 0.04, -hd + 0.04, 0.0), (hw - 0.04, hd - 0.04, 0.14)).done()
    Part("white", bevel=0.01, name="top").box((-hw + 0.03, -hd + 0.03, h - 0.12), (hw - 0.03, hd - 0.03, h - 0.02)).done()
    Part("dark", bevel=0.0, name="inside").box((-hw + 0.1, -hd + 0.22, 0.14), (hw - 0.1, hd - 0.06, h - 0.12)).done()
    # the sides and the back: white panels with vents, hinges, a latch
    for sx in (-1, 1):
        x0, x1 = sorted((sx * (hw - 0.03), sx * (hw - 0.07)))
        pn = Part("white", bevel=0.008, name="side")
        pn.box((x0, -hd + 0.1, 0.16), (x1, hd - 0.1, h - 0.14))
        xo0, xo1 = sorted((sx * (hw - 0.03), sx * (hw - 0.012)))
        for z0, z1 in ((0.24, 0.72), (0.78, 1.26), (1.32, 1.94)):
            pn.plate_yz(chamfer(-hd + 0.16, z0, hd - 0.16, z1, 0.03), xo0, xo1)
        pn.done()
        Part("mesh", bevel=0.0, name="side vent").plate_yz(rounded(-hd + 0.24, 1.42, hd - 0.24, 1.84, 0.03), sx * (hw - 0.012), sx * (hw - 0.008) + sx * 0.004).done()
        hg = Part("darksteel", bevel=0.003, name="hinges")
        for z in (0.4, 0.95, 1.5, 1.85):
            x0h, x1h = sorted((sx * (hw - 0.012), sx * (hw + 0.012)))
            hg.box((x0h, hd - 0.2, z - 0.035), (x1h, hd - 0.12, z + 0.035))
        hg.box(tuple(sorted((sx * (hw - 0.012), sx * (hw + 0.01))))[0:1] + (-hd + 0.14, 0.42), tuple(sorted((sx * (hw - 0.012), sx * (hw + 0.01))))[1:2] + (-hd + 0.2, 0.52))
        hg.done()
    Part("white", bevel=0.008, name="back").box((-hw + 0.1, hd - 0.07, 0.16), (hw - 0.1, hd - 0.03, h - 0.14)).done()
    # the back's services: a riser, boxes, a vent, a cable bundle over the top
    y = hd - 0.03
    pipe([(-0.22, y + 0.04, 0.2), (-0.22, y + 0.04, 1.9), (-0.1, y + 0.04, 1.98)], 0.026, fillet=0.05)
    bb = Part("white", bevel=0.008, name="back boxes")
    bb.box((0.0, y, 0.95), (0.2, y + 0.07, 1.5)).box((-0.34, y, 1.1), (-0.26, y + 0.06, 1.35)).box((-0.1, y, 0.24), (0.3, y + 0.05, 0.5))
    bb.done()
    Part("pipe", bevel=0.002, name="back slats").louvres(0.02, 0.18, 1.0, 1.45, y + 0.07, 8, depth=0.02).done(T(rz=0))
    for k in range(4):
        cable([(-0.3 + k * 0.04, y + 0.03, 1.5), (-0.3 + k * 0.04, y + 0.04, 1.9), (-0.28 + k * 0.04, y - 0.1, h + 0.04 + k * 0.01), (-0.26 + k * 0.04, y - 0.4, h - 0.02)], 0.012)
    # the front: open, the units one above another
    y = -hd + 0.1
    rail = Part("grey", bevel=0.004, name="rails")
    for sx in (-1, 1):
        rail.box(tuple(sorted((sx * (hw - 0.1), sx * (hw - 0.14))))[0:1] + (y - 0.02, 0.16), tuple(sorted((sx * (hw - 0.1), sx * (hw - 0.14))))[1:2] + (y + 0.02, h - 0.14))
    rail.done()
    units = [(0.2, 0.34, "mesh"), (0.36, 0.5, "mesh"), (0.52, 0.66, "mesh"), (0.68, 0.82, "mesh"), (0.84, 1.14, "patch"), (1.16, 1.3, "mesh"), (1.32, 1.42, "drive"),
             (1.44, 1.54, "drive"), (1.56, 1.66, "drive"), (1.68, 1.78, "drive"), (1.8, 1.94, "mesh")]
    body = Part("grey", bevel=0.004, name="units")
    mesh = Part("mesh", bevel=0.0, name="unit grilles")
    g_led, o_led, b_led = Part("ledgreen", bevel=0.0, name="leds"), Part("orange", bevel=0.0, name="leds"), Part("ledblue", bevel=0.0, name="leds")
    ports = Part("dark", bevel=0.0, name="ports")
    x0, x1 = -hw + 0.15, hw - 0.15
    for i, (z0, z1, kind) in enumerate(units):
        body.box((x0, y, z0), (x1, y + 0.5, z1))
        if kind == "mesh":
            mesh.box((x0 + 0.03, y - 0.004, z0 + 0.025), (x1 - 0.25, y, z1 - 0.025))
            for k in range(3):
                (g_led, o_led, b_led)[(i + k) % 3].box((x1 - 0.2 + k * 0.05, y - 0.004, z0 + 0.05), (x1 - 0.18 + k * 0.05, y, z0 + 0.065))
            ports.box((x1 - 0.21, y - 0.004, z1 - 0.06), (x1 - 0.05, y, z1 - 0.035))
        elif kind == "drive":
            mesh.box((x0 + 0.03, y - 0.004, z0 + 0.02), (x0 + 0.33, y, z1 - 0.02))
            for k in range(4):
                (b_led, g_led)[k % 2].box((x1 - 0.26 + k * 0.05, y - 0.004, z0 + 0.04), (x1 - 0.235 + k * 0.05, y, z0 + 0.06))
        else:                                               # the patch panel: sockets, and cables plugged across
            for k in range(6):
                ports.box((x0 + 0.05 + k * 0.1, y - 0.004, z0 + 0.18), (x0 + 0.11 + k * 0.1, y, z0 + 0.25))
                ports.box((x0 + 0.05 + k * 0.1, y - 0.004, z0 + 0.05), (x0 + 0.11 + k * 0.1, y, z0 + 0.12))
    for p in (body, mesh, g_led, o_led, b_led, ports):
        p.done()
    for k, (xa, za, xb, zb) in enumerate(((x0 + 0.08, 1.05, x0 + 0.38, 0.92), (x0 + 0.28, 1.05, x1 - 0.12, 1.36), (x0 + 0.48, 0.92, x0 + 0.58, 1.48), (x0 + 0.18, 0.92, x1 - 0.1, 0.72))):
        cable([(xa, y - 0.004, za), (xa, y - 0.06, za - 0.03), ((xa + xb) / 2, y - 0.09, min(za, zb) - 0.1), (xb, y - 0.06, zb - 0.02), (xb, y - 0.004, zb)], 0.008,
              ("cable", "cable_tan", "cable", "cable")[k])


# ------------------------------------------------------------------ the power core (reference 15): 1.5 m across, 2.2 m high
@asset("power_core", views=[(-0.5, -1.0, 0.16), (1.0, -0.6, 0.14)], res=[(580, 620), (580, 620)])
def power_core():
    R, h = 0.62, 2.2
    seg = 36
    hp = R * 0.74                                           # the corner posts stand at the corners of a square
    Part("grey", bevel=0.012, name="bowl").cyl((0, 0, 0.12), (0, 0, 0.34), R - 0.2, r2=R - 0.02, segs=seg).done()
    dr = Part("white", bevel=0.014, name="drums")
    dr.cyl((0, 0, 0.34), (0, 0, 0.78), R, segs=seg).cyl((0, 0, 1.5), (0, 0, 1.96), R, segs=seg).cyl((0, 0, 1.96), (0, 0, 2.08), R - 0.1, segs=seg)
    dr.done()
    Part("grey", bevel=0.01, name="waist").cyl((0, 0, 0.78), (0, 0, 1.5), R - 0.14, segs=seg).done()
    bd = Part("grey", bevel=0.006, name="bands")
    for z in (0.74, 1.46):
        bd.cyl((0, 0, z), (0, 0, z + 0.07), R + 0.02, segs=seg)
    bd.done()
    pl = Part("white", bevel=0.006, name="drum plates")      # plates round the drums, with seams
    for a in range(0, 360, 45):
        m = T(rz=a + 22.5)
        for z0, z1 in ((0.4, 0.72), (1.56, 1.9)):
            q = Part("white", bevel=0.006, name="plate")
            q.plate_xz(chamfer(-0.2, z0, 0.2, z1, 0.025), -R - 0.012, -R + 0.03)
            q.done(m)
    pl.done()
    # the corner posts with their shoes and eyes
    for a in (45, 135, 225, 315):
        m = T(rz=a)
        Part("white", bevel=0.012, name="post").box((-0.09, -R - 0.12, 0.2), (0.09, -R + 0.06, h - 0.1)).done(m)
        g = Part("grey", bevel=0.01, name="shoe")
        g.plate_yz([(-R - 0.3, 0.0), (-R + 0.06, 0.0), (-R + 0.06, 0.34), (-R - 0.14, 0.34), (-R - 0.3, 0.14)], -0.12, 0.12)
        g.box((-0.12, -R - 0.15, h - 0.2), (0.12, -R + 0.08, h))
        g.box((-0.06, -R - 0.135, 0.9), (0.06, -R - 0.12, 1.36))
        g.done(m)
        ring((0, -R - 0.03, h + 0.04), (1, 0, 0), 0.035, 0.011, "darksteel", m=m)
    # the port: a round window in a heavy bezel, caged, glowing
    Part("white", bevel=0.014, name="port bezel").cyl((0, -R + 0.1, 1.14), (0, -R + 0.02 - 0.14, 1.14), 0.4, segs=32).done()
    Part("grey", bevel=0.008, name="port ring").cyl((0, -R - 0.12, 1.14), (0, -R - 0.15, 1.14), 0.33, segs=32).done()
    Part("coreglow", bevel=0.0, name="port glow").cyl((0, -R - 0.15, 1.14), (0, -R - 0.156, 1.14), 0.27, segs=32).done()
    for z in (0.98, 1.06, 1.14, 1.22, 1.3):
        hwid = math.sqrt(max(0.33 ** 2 - (z - 1.14) ** 2, 0.0)) + 0.06
        pipe([(-hwid, -R - 0.12, z), (-hwid, -R - 0.2, z), (hwid, -R - 0.2, z), (hwid, -R - 0.12, z)], 0.012, "pipe", fillet=0.03)
    pipe([(0.0, -R - 0.12, 0.76), (0.0, -R - 0.215, 0.82), (0.0, -R - 0.215, 1.46), (0.0, -R - 0.12, 1.52)], 0.012, "pipe", fillet=0.03)
    # the control box (left of the port), heat sinks, a vented box (right side)
    m = T(rz=-62)
    Part("white", bevel=0.01, name="control box").box((-0.17, -R - 0.02, 0.92), (0.17, -R + 0.12, 1.4)).done(m)
    Part("dark", bevel=0.004, name="control face").box((-0.13, -R - 0.03, 0.98), (0.13, -R - 0.02, 1.34)).done(m)
    Part("steel", bevel=0.002, name="dial").cyl((-0.04, -R - 0.03, 1.24), (-0.04, -R - 0.05, 1.24), 0.045, segs=20).cyl((-0.04, -R - 0.05, 1.24), (-0.04, -R - 0.07, 1.24), 0.012, segs=8) \
        .box((-0.09, -R - 0.045, 1.02), (-0.07, -R - 0.03, 1.12)).box((-0.03, -R - 0.045, 1.02), (-0.01, -R - 0.03, 1.12)).done(m)
    Part("orange", bevel=0.0, name="lamp").box((0.04, -R - 0.034, 1.26), (0.07, -R - 0.03, 1.28)).box((0.04, -R - 0.034, 1.2), (0.07, -R - 0.03, 1.22)).done(m)
    Part("ledblue", bevel=0.0, name="lamp").box((0.085, -R - 0.034, 1.26), (0.115, -R - 0.03, 1.28)).done(m)
    Part("ledgreen", bevel=0.0, name="lamp").box((0.085, -R - 0.034, 1.2), (0.115, -R - 0.03, 1.22)).done(m)
    for a, z0, z1 in ((-118, 1.56, 1.9), (62, 1.56, 1.9), (118, 0.9, 1.36), (-100, 0.9, 1.36)):       # heat sinks
        m = T(rz=a)
        Part("grey", bevel=0.004, name="sink base").box((-0.2, -R - 0.03, z0), (0.2, -R + 0.05, z1)).done(m)
        fn = Part("darksteel", bevel=0.0, name="fins")
        for i in range(12):
            fn.box((-0.18 + i * 0.031, -R - 0.075, z0 + 0.03), (-0.168 + i * 0.031, -R - 0.03, z1 - 0.03))
        fn.done(m)
    m = T(rz=62)
    Part("white", bevel=0.01, name="vent box").box((-0.16, -R - 0.06, 0.92), (0.16, -R + 0.1, 1.36)).done(m)
    Part("pipe", bevel=0.002, name="vent slats").louvres(-0.12, 0.12, 0.98, 1.3, -R - 0.062, 8, depth=0.02).done(m)
    # heavy cables: from the control box round the waist, and from the top down the posts
    for k in range(3):
        pts = []
        for a in range(-150, -19, 13):
            rr = R - 0.05 + 0.02 * k
            pts.append((rr * math.sin(math.radians(a)), -rr * math.cos(math.radians(a)), 0.86 + k * 0.045 + 0.05 * math.sin(math.radians(a * 3))))
        cable(pts, 0.022, ("cable", "cable", "pipe")[k])
        pts = []
        for a in range(20, 151, 13):
            rr = R - 0.05 + 0.02 * k
            pts.append((rr * math.sin(math.radians(a)), -rr * math.cos(math.radians(a)), 0.84 + k * 0.045 - 0.04 * math.sin(math.radians(a * 3))))
        cable(pts, 0.022, ("cable", "pipe", "cable")[k])
    for a, mat_k in ((-30, "cable"), (-22, "cable"), (150, "cable"), (158, "pipe")):
        s_, c_ = math.sin(math.radians(a)), -math.cos(math.radians(a))
        cable([((R - 0.2) * s_, (R - 0.2) * c_, 2.08), ((R + 0.02) * s_, (R + 0.02) * c_, 2.0), ((R + 0.05) * s_, (R + 0.05) * c_, 1.7), ((R - 0.06) * s_, (R - 0.06) * c_, 1.42)], 0.02, mat_k)
    Part("grey", bevel=0.008, name="top cap").cyl((0, 0, 2.08), (0, 0, 2.14), R - 0.25, segs=seg).done()
