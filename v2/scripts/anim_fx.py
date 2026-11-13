"""V2: the effects pass. Tracers, impact sparks, dust, debris, scorch marks, muzzle smoke and damage smoke, keyed onto
the timeline of v2/scene.blend for every shot of the weapon views and the robots, the robots' deaths, and the
Firefight section (fx_plan.py).

    blender -b v2/scene.blend -P v2/scripts/anim_fx.py       (run last: after anim_pistol, anim_rifle, anim_robots)

Everything is a plain mesh with keyed transform and colour, so it plays on the timeline and can be exported:
- tracer: a thin bright rod stretched along a stretch of the bullet's path, two frames per shot
- sparks: one mesh of streaks that grows and fades over five frames (+ a point light for two)
- puff: a cluster of soft blobs (dust, smoke) that grows, rises and fades
- debris: small chunks on ballistic paths that come to rest on the floor
- scorch: a dark soft-edged disc left where a round hit (Firefight only)
The objects come from pools and are hidden (scale 0) when not in use. Effects of the player's shots live in that
weapon view's collection (so they show with the gun that fired them); the robots' in the collection `FX`.
Where things are comes from the baked scene: muzzle and body positions are sampled at the frame of each shot;
the guns' Fire / ADS rounds go where a ray from the eye lands.
"""
import json
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import v2lib as L  # noqa: E402
import hands as H  # noqa: E402
import fx_plan as PLAN  # noqa: E402
from anim_lib import FPS, Recorder, ease_out, write_fcurves  # noqa: E402

sc = bpy.context.scene
OBJ = bpy.data.objects
cam = OBJ["PlayerCamera"]
G = Vector((0, 0, -9.8))
YELLOW, RED, SPARK = (1.0, 0.82, 0.45), (1.0, 0.3, 0.12), (1.0, 0.62, 0.22)
DUST, SMOKE, GUNSMOKE = (0.7, 0.69, 0.66), (0.3, 0.3, 0.31), (0.8, 0.8, 0.78)

# ---------------------------------------------------------------------- clean up an earlier run
for o in list(OBJ):
    if o.name.startswith("Fx"):
        data = o.data
        OBJ.remove(o)
        if data and data.users == 0:
            (bpy.data.lights if isinstance(data, bpy.types.Light) else bpy.data.meshes).remove(data)
for block in (bpy.data.materials, bpy.data.meshes, bpy.data.actions):
    for d in list(block):
        if d.name.startswith("Fx") and d.users == 0:
            block.remove(d)
FX = L.coll("FX")
COLLS = {"fx": FX, "pistol": bpy.data.collections[H.COLL["pistol"]], "rifle": bpy.data.collections[H.COLL["rifle"]]}
clips = {k[len("v2_clips_"):]: json.loads(sc[k]) for k in sc.keys() if k.startswith("v2_clips_")}


# ---------------------------------------------------------------------- materials
def glow_material(name="FxGlow", strength=28.0):
    """Emission in the object's colour, fading out with the object's alpha."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.remove(nt.nodes["Principled BSDF"])
    oi = nt.nodes.new("ShaderNodeObjectInfo")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = strength
    nt.links.new(oi.outputs["Color"], em.inputs["Color"])
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(oi.outputs["Alpha"], mix.inputs[0])
    nt.links.new(nt.nodes.new("ShaderNodeBsdfTransparent").outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], nt.nodes["Material Output"].inputs["Surface"])
    return m


def smoke_material():
    """Soft matte blobs: the object's colour, see-through toward the rim and through a noise, times its alpha."""
    m = bpy.data.materials.new("FxSmoke")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 1.0
    oi = nt.nodes.new("ShaderNodeObjectInfo")
    nt.links.new(oi.outputs["Color"], bsdf.inputs["Base Color"])
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.35
    inv = nt.nodes.new("ShaderNodeMath")
    inv.operation = "SUBTRACT"
    inv.inputs[0].default_value = 1.0
    nt.links.new(lw.outputs["Facing"], inv.inputs[1])
    pw = nt.nodes.new("ShaderNodeMath")
    pw.operation = "POWER"
    pw.inputs[1].default_value = 1.6
    nt.links.new(inv.outputs[0], pw.inputs[0])
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 7.0
    nz.inputs["Detail"].default_value = 4.0
    nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value, mr.inputs["From Max"].default_value = 0.3, 0.7
    mr.inputs["To Min"].default_value, mr.inputs["To Max"].default_value = 0.35, 1.0
    nt.links.new(nz.outputs["Fac"], mr.inputs["Value"])
    a1 = nt.nodes.new("ShaderNodeMath")
    a1.operation = "MULTIPLY"
    nt.links.new(pw.outputs[0], a1.inputs[0])
    nt.links.new(mr.outputs["Result"], a1.inputs[1])
    a2 = nt.nodes.new("ShaderNodeMath")
    a2.operation = "MULTIPLY"
    nt.links.new(a1.outputs[0], a2.inputs[0])
    nt.links.new(oi.outputs["Alpha"], a2.inputs[1])
    nt.links.new(a2.outputs[0], bsdf.inputs["Alpha"])
    return m


def scorch_material():
    """Soot: black, dense in the middle, gone at the rim."""
    m = bpy.data.materials.new("FxScorch")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.012, 0.011, 0.01, 1)
    bsdf.inputs["Roughness"].default_value = 0.9
    tc = nt.nodes.new("ShaderNodeTexCoord")
    ln = nt.nodes.new("ShaderNodeVectorMath")
    ln.operation = "LENGTH"
    nt.links.new(tc.outputs["Object"], ln.inputs[0])
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value, mr.inputs["From Max"].default_value = 0.25, 1.0
    mr.inputs["To Min"].default_value, mr.inputs["To Max"].default_value = 0.85, 0.0
    nt.links.new(ln.outputs["Value"], mr.inputs["Value"])
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 9.0
    nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
    mu = nt.nodes.new("ShaderNodeMath")
    mu.operation = "MULTIPLY"
    nt.links.new(mr.outputs["Result"], mu.inputs[0])
    nt.links.new(nz.outputs["Fac"], mu.inputs[1])
    nt.links.new(mu.outputs[0], bsdf.inputs["Alpha"])
    return m


M_GLOW, M_SMOKE, M_SCORCH = glow_material(), smoke_material(), scorch_material()
M_TRACER = glow_material("FxTracerGlow", 7.0)      # (dimmer than the sparks: at full strength a tracer burns out white)


def debris_material():
    m = bpy.data.materials.new("FxDebris")
    m.use_nodes = True
    nt = m.node_tree
    nt.links.new(nt.nodes.new("ShaderNodeObjectInfo").outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
    nt.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.85
    return m


M_DEBRIS = debris_material()
CHIP, FLAKE = (0.5, 0.5, 0.49), (0.1, 0.1, 0.11)    # floor / wall chips, bits of robot


# ---------------------------------------------------------------------- meshes
def mesh(name, bm, mat):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    for p in me.polygons:
        p.use_smooth = True
    return me


def tracer_mesh():
    bm = bmesh.new()                                # a rod from 0 to 1 along +Y, thin at both ends
    bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.0015, radius2=0.0055, depth=0.7,
                          matrix=Matrix.Translation((0, 0.35, 0)) @ Matrix.Rotation(-math.pi / 2, 4, "X"))
    bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.0055, radius2=0.003, depth=0.3,
                          matrix=Matrix.Translation((0, 0.85, 0)) @ Matrix.Rotation(-math.pi / 2, 4, "X"))
    return mesh("FxTracer", bm, M_TRACER)


def sparks_mesh(seed):
    """Streaks flying out over a half-sphere about +Z, from a small core."""
    rng = random.Random(seed)
    bm = bmesh.new()
    for _ in range(20):
        d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), abs(rng.gauss(0, 1)) + 0.15)).normalized()
        r0, r1, w = rng.uniform(0.08, 0.3), rng.uniform(0.45, 1.0), rng.uniform(0.006, 0.014)
        side = d.orthogonal().normalized() * w
        up = d.cross(side).normalized() * w
        a, b = d * r0, d * r1
        vs = [bm.verts.new(a + side), bm.verts.new(a + up), bm.verts.new(a - side), bm.verts.new(a - up), bm.verts.new(b)]
        for i in range(4):
            bm.faces.new((vs[i], vs[(i + 1) % 4], vs[4]))
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.09)
    return mesh(f"FxSparks{seed}", bm, M_GLOW)


def puff_mesh(seed):
    """One soft, lumpy ball (a puff is several of these overlapping; one mesh of merged balls shows hard seams)."""
    rng = random.Random(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=3, radius=0.5)
    k = [Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * 3.0 for _ in range(3)]
    for v in bm.verts:
        v.co *= 1.0 + 0.12 * sum(math.sin(v.co.dot(q) + i) for i, q in enumerate(k))
    return mesh(f"FxPuff{seed}", bm, M_SMOKE)


def chunk_mesh(seed):
    rng = random.Random(seed)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * rng.uniform(0.6, 1.4), v.co.y * rng.uniform(0.6, 1.4), v.co.z * rng.uniform(0.3, 0.8)))
        v.co += Vector((rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2), rng.uniform(-0.1, 0.1)))
    me = mesh(f"FxChunk{seed}", bm, M_DEBRIS)
    for p in me.polygons:
        p.use_smooth = False
    return me


def disc_mesh():
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=True, segments=24, radius=1.0)
    return mesh("FxDisc", bm, M_SCORCH)


MESHES = {"tracer": [tracer_mesh()], "sparks": [sparks_mesh(i) for i in range(4)], "puff": [puff_mesh(i) for i in range(4)],
          "chunk": [chunk_mesh(i) for i in range(5)], "scorch": [disc_mesh()]}
rec = Recorder()


class Pool:
    """Objects of one kind in one collection, handed out for a span of frames and reused when free."""

    def __init__(self, kind, where):
        self.kind, self.where, self.items = kind, where, []

    def get(self, f0, f1):
        for it in self.items:
            if it[1] < f0 - 1:
                it[1] = f1
                return it[0]
        i = len(self.items)
        if self.kind == "light":
            ld = bpy.data.lights.new(f"FxLight_{self.where}{i}", "POINT")
            ld.energy, ld.color, ld.shadow_soft_size = 0.0, (1.0, 0.65, 0.3), 0.04
            ob = bpy.data.objects.new(f"FxLight_{self.where}{i}", ld)
        else:
            ms = MESHES[self.kind]
            ob = bpy.data.objects.new(f"Fx{self.kind.capitalize()}_{self.where}{i}", ms[i % len(ms)])
            ob.scale = (0, 0, 0)
            ob.visible_shadow = self.kind == "chunk"
        ob.rotation_mode = "QUATERNION"
        COLLS[self.where].objects.link(ob)
        self.items.append([ob, f1])
        return ob


POOLS = {}


def take(kind, where, f0, f1):
    if (kind, where) not in POOLS:
        POOLS[(kind, where)] = Pool(kind, where)
    return POOLS[(kind, where)].get(f0, f1)


def show(ob, f, m, color=None):
    rec.key_object(ob, f, m)
    if color is not None:
        rec._put(ob, "color", list(color), f, "Animation")


def hide(ob, f, m=None):
    rec.key_object(ob, f, m or Matrix.Identity(4), hidden=True)




# ---------------------------------------------------------------------- the effects
def tracer(where, f, a, b, color):
    d = b - a
    if d.length < 0.05:
        return
    ob = take("tracer", where, f, f)
    m = Matrix.Translation(a) @ d.to_track_quat("Y", "Z").to_matrix().to_4x4() @ Matrix.Diagonal((1, d.length, 1, 1))
    hide(ob, f - 1, m)
    show(ob, f, m, (*color, 1.0))
    hide(ob, f + 1, m)


def sparks(where, f, p, n, size, color=SPARK, life=5, light=6.0):
    ob = take("sparks", where, f, f + life - 1)
    rot = n.to_track_quat("Z", "Y").to_matrix().to_4x4() @ Matrix.Rotation(random.Random(f * 7 + int(p.x * 100)).uniform(0, 6.28), 4, "Z")
    hide(ob, f - 1, Matrix.Translation(p))
    for i in range(life):
        k = i / (life - 1)
        m = Matrix.Translation(p + Vector((0, 0, -0.12 * size * k * k))) @ rot @ Matrix.Scale(size * (0.35 + 0.65 * ease_out(k, 2)), 4)
        show(ob, f + i, m, (*color, (1 - k) ** 1.3))
    hide(ob, f + life, Matrix.Translation(p))
    if light > 0:
        lo = take("light", where, f, f + 2)
        for i, e in enumerate((light, light * 0.3, 0.0)):
            rec.key_object(lo, f + i, Matrix.Translation(p + n * 0.08))
            rec.key_value(lo.data, "energy", f + i, e)
        rec.key_value(lo.data, "energy", f - 1, 0.0)


def puff(where, f, p, size, life, rise=0.25, color=DUST, alpha=0.55, drift=(0, 0, 0), seed=0, balls=3):
    """Dust or smoke: a few soft balls that swell, rise, drift apart and fade."""
    rng = random.Random(seed * 31 + f)
    for b in range(balls):
        off = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.4, 0.8))) * size * 0.3 * (b > 0)
        sz = size * rng.uniform(0.7, 1.15)
        ob = take("puff", where, f, f + life - 1)
        rot = Matrix.Rotation(rng.uniform(0, 6.28), 4, "Z") @ Matrix.Rotation(rng.uniform(0, 6.28), 4, "X")
        hide(ob, f - 1, Matrix.Translation(p))
        for i in range(life):
            k = i / (life - 1)
            m = Matrix.Translation(p + off * (1 + k) + Vector((0, 0, rise)) * ease_out(k, 2) + Vector(drift) * k) @ rot \
                @ Matrix.Scale(sz * (0.3 + 0.7 * ease_out(k, 2.5)), 4)
            show(ob, f + i, m, (*color, alpha * min(1.0, (i + 1) / 2) * (1 - k) ** 1.2))
        hide(ob, f + life, Matrix.Translation(p))


def debris(where, f, p, n, count, seed, until=None, speed=1.0, size=1.0, color=CHIP):
    """Chunks thrown off the surface: they fly, fall, and lie on the floor until `until` (default: half a second)."""
    rng = random.Random(seed)
    for c in range(count):
        t1 = n.orthogonal().normalized()
        v = (n * rng.uniform(1.0, 2.6) + t1 * rng.uniform(-1.6, 1.6) + n.cross(t1) * rng.uniform(-1.6, 1.6) + Vector((0, 0, rng.uniform(0.6, 1.8)))) * speed
        s = rng.uniform(0.007, 0.018) * size
        axis = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()
        spin = rng.uniform(8, 20)
        # time of flight to the floor (z = half its thickness)
        a_, b_, c_ = -4.9, v.z, p.z - s * 0.3
        tl = (-b_ - math.sqrt(max(b_ * b_ - 4 * a_ * c_, 0))) / (2 * a_)
        n_fly = max(1, math.ceil(tl * FPS))
        end = until if until is not None else f + n_fly + 12
        ob = take("chunk", where, f, end)
        hide(ob, f - 1, Matrix.Translation(p))
        for i in range(n_fly + 1):
            tt = min(i / FPS, tl)
            pos = p + v * tt + G * tt * tt / 2
            show(ob, f + i, Matrix.Translation(pos) @ Matrix.Rotation(spin * tt, 4, axis) @ Matrix.Scale(s, 4), (*color, 1.0))
        last = Matrix.Translation(p + v * tl + G * tl * tl / 2) @ Matrix.Rotation(spin * tl, 4, axis) @ Matrix.Scale(s, 4)
        show(ob, end, last, (*color, 1.0))
        hide(ob, end + 1, last)


def scorch(where, f, p, n, size, until):
    ob = take("scorch", where, f, until)
    m = Matrix.Translation(p + n * 0.0015) @ n.to_track_quat("Z", "Y").to_matrix().to_4x4() @ Matrix.Scale(size, 4)
    hide(ob, f - 1, m)
    show(ob, f, m)
    show(ob, until, m)
    hide(ob, until + 1, m)


def impact(where, f, p, n, kind, seed, until=None):
    """A round landing. floor / wall: sparks, dust, chips (and a scorch mark if `until`); metal: sparks and a flake."""
    if kind == "metal":
        sparks(where, f, p, n, 0.42, light=9.0)
        puff(where, f, p + n * 0.05, 0.16, 10, rise=0.12, color=SMOKE, alpha=0.18, seed=seed, balls=2)
        debris(where, f, p, n, 2, seed, until, speed=0.8, color=FLAKE)
    else:
        sparks(where, f, p, n, 0.3)
        puff(where, f, p + n * 0.05, 0.3, 18, rise=0.28, alpha=0.4, seed=seed)
        debris(where, f, p, n, 3, seed, until)
        if until is not None:
            scorch(where, f, p, n, 0.09, until)


def shot(where, f, muzzle, target, color, hit=None, seed=0, until=None):
    """A round: two frames of tracer along its path, then what it does where it lands. hit = (normal, kind)."""
    d = target - muzzle
    u, ln = d.normalized(), d.length
    tracer(where, f, muzzle + u * min(0.5, ln * 0.1), muzzle + u * ln * 0.62, color)
    tracer(where, f + 1, muzzle + u * ln * 0.55, target, color)
    if hit:
        impact(where, f + 1, target, hit[0], hit[1], seed, until)


# ---------------------------------------------------------------------- what happens when
FF = PLAN.FF_START
events = []                                        # (frame, object names to sample) gathered first
need = {}


def want(f, *names):
    need.setdefault(f, set()).update(names)


def cs(group, name):
    return clips[group][name]["start"]


P_FIRE = [cs("pistol", "Fire") + 2]
R_FIRE = [cs("rifle", "Fire") + 2 + 2 * j for j in range(8)]
R_ADS = [cs("rifle", "ADS") + 17 + 2 * j for j in range(6)]
P_FF = [FF + x for x in PLAN.FF_PISTOL]
R_FF = [FF + a0 + 2 * j for a0, n in PLAN.FF_RIFLE for j in range(n)]
RS = cs("robots", "Spider Shoot")
ROBOT_SHOTS = {"Spider": [RS + x for x in PLAN.SHOOT_SPIDER] + [FF + x for x in PLAN.FF_SPIDER],
               "Drone": [RS + x for x in PLAN.SHOOT_DRONE] + [FF + x for x in PLAN.FF_DRONE],
               "Turret": [RS + x for x in PLAN.SHOOT_TURRET] + [FF + x for x in PLAN.FF_TURRET]}
DEATH = cs("robots", "Spider Death")
DEATH_END = clips["robots"]["Spider Death"]["end"]
for f in P_FIRE + P_FF:
    want(f, "P_Flash")
for f in R_FIRE + R_ADS + R_FF:
    want(f, "R_Flash")
for f in P_FF + R_FF:
    want(f + 1, "Spider_Body", "Spider_Foot0", "Spider_Foot1")
for name, frames in ROBOT_SHOTS.items():
    for f in frames:
        want(f, *([f"{name}_FlashL", f"{name}_FlashR"] if name != "Drone" else ["Drone_Flash"]))
for f in range(DEATH, DEATH_END + 1):
    want(f, "Spider_Body", "Spider_Turret", "Drone_Body", "Turret_Head")

# pass 1: where things are (both weapon views evaluated)
vis = {c: bpy.data.collections[c].hide_viewport for c in H.COLL.values()}
for c in H.COLL.values():
    bpy.data.collections[c].hide_viewport = False
at = {}
for f in sorted(need):
    sc.frame_set(f)
    for n in need[f]:
        at[(f, n)] = OBJ[n].matrix_world.translation.copy()
    at[(f, "cam")] = cam.matrix_world.copy()
# pass 2: what the guns' rounds hit (a ray from the eye; the weapon views out of the way)
sc.frame_set(1)
for c in H.COLL.values():
    bpy.data.collections[c].hide_viewport = True
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
CAM0 = cam.matrix_world.copy()


def eye_ray(cm, yaw=0.0, pitch=0.0):
    """Where a ray from the eye lands (degrees off the view axis). -> (point, normal)"""
    d = (cm.to_3x3() @ (Matrix.Rotation(math.radians(yaw), 3, "Y") @ Matrix.Rotation(math.radians(pitch), 3, "X") @ Vector((0, 0, -1)))).normalized()
    ok, loc, nrm, *_ = sc.ray_cast(dg, cm.translation + d * 0.3, d)
    return (loc.copy(), nrm.copy()) if ok else (cm.translation + d * 14, -d)


rng = random.Random(5)
gun_hits = {}
gun_hits[P_FIRE[0]] = eye_ray(CAM0)
for j, f in enumerate(R_FIRE):
    gun_hits[f] = eye_ray(CAM0, rng.uniform(-1.3, 1.3), 0.5 * j + rng.uniform(-0.6, 0.6))
for j, f in enumerate(R_ADS):
    gun_hits[f] = eye_ray(CAM0, rng.uniform(-0.45, 0.45), 0.2 * j + rng.uniform(-0.3, 0.3))
for c, v in vis.items():
    bpy.data.collections[c].hide_viewport = v

# ---- the guns' Fire / ADS clips: tracer to the crosshair, impact there, a wisp of smoke at the muzzle
for where, frames, flash in (("pistol", P_FIRE, "P_Flash"), ("rifle", R_FIRE + R_ADS, "R_Flash")):
    for j, f in enumerate(frames):
        p, n = gun_hits[f]
        shot(where, f, at[(f, flash)], p, YELLOW, (n, "wall"), seed=f)
        if where == "pistol" or j % 3 == 0:
            puff(where, f + 1, at[(f, flash)], 0.07, 14, rise=0.1, color=GUNSMOKE, alpha=0.3, seed=f)

# ---- the robots' shots: half at the floor in front of the player (sparks, dust, chips), half streaking past
eye = CAM0.translation
fwd, right = (CAM0.to_3x3() @ Vector((0, 0, -1))), (CAM0.to_3x3() @ Vector((1, 0, 0)))
fwd.z = 0
fwd.normalize()
k = 0
for name, frames in ROBOT_SHOTS.items():
    for f in frames:
        ff = f >= FF
        for flash in ([f"{name}_FlashL", f"{name}_FlashR"] if name == "Spider" else
                      ["Drone_Flash"] if name == "Drone" else [f"Turret_Flash{'LR'[frames.index(f) % 2]}"]):
            mz = at[(f, flash)]
            r = random.Random(k * 13 + 1)
            k += 1
            if k % 2 == 0:                                  # into the floor between them
                tgt = Vector((eye.x, eye.y, 0)) + fwd * r.uniform(2.0, 3.6) + right * r.uniform(-1.6, 0.5)
                shot("fx", f, mz, tgt, RED, (Vector((0, 0, 1)), "floor"), seed=k, until=FF + PLAN.FF_N - 1 if ff else None)
            else:                                           # past the player's head, out of the frame
                # (the streak is cut 1.6 m short of the eye: any nearer it fills the frame)
                aim = eye + right * r.choice((-1, 1)) * r.uniform(0.55, 1.0) + Vector((0, 0, r.uniform(-0.45, 0.3)))
                shot("fx", f, mz, mz + (aim - mz) * (1 - 1.6 / (aim - mz).length), RED)
            puff("fx", f + 1, mz, 0.13, 12, rise=0.12, color=GUNSMOKE, alpha=0.3, seed=k)

# ---- Firefight: the player's rounds hit the spider and the floor at its feet; smoke gathers round it
FF_END = FF + PLAN.FF_N - 1
SPIDER_PTS = [Vector(v) for v in ((0.0, 0.42, 0.03), (0.2, 0.33, 0.13), (-0.22, 0.3, 0.12), (0.05, 0.2, 0.2), (-0.1, 0.4, -0.02))]
for where, frames in (("pistol", P_FF), ("rifle", R_FF)):
    for j, f in enumerate(frames):
        body = at[(f + 1, "Spider_Body")]
        r = random.Random(f * 3 + 2)
        if j % 3 == 2:                                      # a miss: into the floor by a front foot
            foot = at[(f + 1, "Spider_Foot" + str(j % 2))]
            tgt = Vector((foot.x + r.uniform(-0.25, 0.25), foot.y - r.uniform(0.1, 0.5), 0))
            hit = (Vector((0, 0, 1)), "floor")
        else:
            sm = OBJ["Spider_Body"].matrix_world                    # (its rest placement: good enough for a hit point)
            tgt = body + sm.to_3x3() @ SPIDER_PTS[j % len(SPIDER_PTS)]
            hit = ((eye - tgt).normalized(), "metal")
        shot(where, f, at[(f, "P_Flash" if where == "pistol" else "R_Flash")], tgt, YELLOW, hit, seed=f, until=FF_END)
        if where == "pistol" or j % 3 == 0:
            puff(where, f + 1, at[(f, "P_Flash" if where == "pistol" else "R_Flash")], 0.07, 14, rise=0.1, color=GUNSMOKE, alpha=0.3, seed=f)
sp_rest = OBJ["Spider_Body"].matrix_world.translation.copy()
for i, f in enumerate(range(FF + 10, FF_END - 16, 7)):      # the spider starts to smoke as it is hit
    puff("fx", f, sp_rest + Vector((random.Random(i).uniform(-0.2, 0.2), 0.1, 0.25)), 0.3 + 0.02 * i, 22, rise=0.7,
         color=SMOKE, alpha=0.13, drift=(0.1, 0.0, 0.0), seed=i, balls=2)

# ---- Death: sparks where each robot is hit and while it fails, smoke off the wrecks, dust where they land
TURRET_T0, DRONE_T0, SPIDER_T0 = DEATH, DEATH + 4, DEATH + 8
to_eye = lambda p: (eye - p).normalized()                 # noqa: E731
for f, n in ((TURRET_T0, 0.5), (TURRET_T0 + 3, 0.3), (TURRET_T0 + 7, 0.36), (TURRET_T0 + 10, 0.26)):
    p = at[(f, "Turret_Head")]
    sparks("fx", f, p + to_eye(p) * 0.15, to_eye(p), n, light=14.0)
for f in range(TURRET_T0 + 12, DEATH_END - 14, 5):
    puff("fx", f, at[(f, "Turret_Head")], 0.3, 26, rise=0.8, color=SMOKE, alpha=0.16, seed=f)
p = at[(DRONE_T0, "Drone_Body")]
sparks("fx", DRONE_T0, p + to_eye(p) * 0.15, to_eye(p), 0.5, light=14.0)
land = min(range(DRONE_T0, DEATH_END), key=lambda f_: (round(at[(f_, "Drone_Body")].z, 2), f_))   # first frame on the floor
for f in range(DRONE_T0 + 2, land, 2):                    # a trail on the way down
    puff("fx", f, at[(f, "Drone_Body")], 0.2, 16, rise=0.2, color=SMOKE, alpha=0.16, seed=f)
p = Vector((at[(land, "Drone_Body")].x, at[(land, "Drone_Body")].y, 0.02))
sparks("fx", land, p, Vector((0, 0, 1)), 0.6, light=16.0)
puff("fx", land, p, 0.6, 26, rise=0.3, seed=land)
debris("fx", land, p + Vector((0, 0, 0.05)), Vector((0, 0, 1)), 7, land, until=DEATH_END, speed=1.3, size=1.6, color=FLAKE)
for f in range(land + 6, DEATH_END - 14, 6):
    puff("fx", f, at[(f, "Drone_Body")] + Vector((0, 0, 0.1)), 0.3, 26, rise=0.8, color=SMOKE, alpha=0.16, seed=f)
for f, n in ((SPIDER_T0, 0.5), (SPIDER_T0 + 6, 0.3), (SPIDER_T0 + 12, 0.34)):
    p = at[(f, "Spider_Turret")]
    sparks("fx", f, p + to_eye(p) * 0.2, to_eye(p), n, light=14.0)
slam = SPIDER_T0 + round(1.05 * FPS)
b = at[(slam, "Spider_Body")]
for i in range(5):                                         # dust thrown out all round as the body hits the floor
    a = i * math.tau / 5 + 0.4
    puff("fx", slam, Vector((b.x + 0.5 * math.cos(a), b.y + 0.5 * math.sin(a), 0.08)), 0.45, 24, rise=0.25,
         drift=(0.5 * math.cos(a), 0.5 * math.sin(a), 0), seed=i)
debris("fx", slam, Vector((b.x, b.y, 0.1)), Vector((0, 0, 1)), 6, slam, until=DEATH_END, speed=1.2, size=1.5, color=FLAKE)
for f in range(slam + 5, DEATH_END - 14, 6):
    puff("fx", f, at[(f, "Spider_Turret")] + Vector((0, 0, 0.1)), 0.32, 26, rise=0.8, color=SMOKE, alpha=0.16, seed=f)

write_fcurves(rec.ch, "Fx")
sc.frame_set(1)
print("fx:", {f"{k}/{w}": len(p.items) for (k, w), p in POOLS.items()})
if "nosave" not in sys.argv:
    bpy.ops.wm.save_mainfile(compress=True)
