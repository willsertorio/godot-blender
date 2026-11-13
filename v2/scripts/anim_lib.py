"""Baking weapon-view animations onto the timeline of v2/scene.blend (used by anim_pistol.py).

A clip is a function of time that returns a *state*: where the gun is in the eye's frame, a camera offset, the
matrices of the moving gun parts, a pose spec for each hand. `Baker.frame()` applies one state (the arms are solved
again with hands.pose() from shoulders that stay fixed to the eye, so elbows and wrists follow the gun) and records
every channel; `Baker.write()` turns the records into one action per object with a key on every frame.

Frames: gun space is +Y muzzle, +Z up, -X the gun's left. The camera's local frame is X right, Y up, -Z forward.
"""
import json
import math

import bpy
from mathutils import Matrix, Vector

import hands as H

FPS = 24
WINDOW = 600                    # frames of the timeline each weapon view owns (pistol 1-600, machine gun 601-1200)
I4 = Matrix.Identity(4)


# ---------------------------------------------------------------------- curves
def clamp(t, a=0.0, b=1.0):
    return max(a, min(b, t))


def seg(t, a, b):
    """0 before a, 1 after b, linear between."""
    return clamp((t - a) / (b - a))


def smooth(t):
    t = clamp(t)
    return t * t * (3 - 2 * t)


def ease_out(t, p=3):
    return 1 - (1 - clamp(t)) ** p


def back_out(t, s=1.7):
    """Ease out with an overshoot (arrives, passes the target, settles)."""
    t = clamp(t) - 1
    return t * t * ((s + 1) * t + s) + 1


def table(x, keys):
    """Piecewise-linear lookup in [(x0, v0), (x1, v1), ...]."""
    if x <= keys[0][0]:
        return keys[0][1]
    for (x0, v0), (x1, v1) in zip(keys, keys[1:]):
        if x <= x1:
            return v0 + (v1 - v0) * (x - x0) / (x1 - x0)
    return keys[-1][1]


def lerp(a, b, t):
    return a + (b - a) * t


# ---------------------------------------------------------------------- transforms
def move(right=0.0, fwd=0.0, up=0.0):
    """A shift in the eye's frame (metres)."""
    return Matrix.Translation((right, up, -fwd))


def rot(pitch=0.0, yaw=0.0, roll=0.0, pivot=(0, 0, 0)):
    """A turn of the gun about a point of the gun (degrees): pitch = muzzle up, yaw = muzzle to the left,
    roll = top to the right."""
    r = Matrix.Rotation(math.radians(yaw), 4, "Z") @ Matrix.Rotation(math.radians(pitch), 4, "X") \
        @ Matrix.Rotation(math.radians(roll), 4, "Y")
    p = Vector(pivot)
    return Matrix.Translation(p) @ r @ Matrix.Translation(-p)


def cam_rot(pitch=0.0, yaw=0.0, roll=0.0):
    """A turn of the eye (degrees): pitch = look up, yaw = look left, roll = head tilts to the left."""
    return Matrix.Rotation(math.radians(yaw), 4, "Y") @ Matrix.Rotation(math.radians(pitch), 4, "X") \
        @ Matrix.Rotation(math.radians(roll), 4, "Z")


def mix_m(a, b, t):
    """Between two placements: straight line for the position, shortest turn for the rotation."""
    la, qa, _ = a.decompose()
    lb, qb, _ = b.decompose()
    return Matrix.Translation(la.lerp(lb, t)) @ qa.slerp(qb, t).to_matrix().to_4x4()


# ---------------------------------------------------------------------- hand pose specs
def xform_spec(spec, m):
    """A hand pose given in another frame (the eye's, a magazine's ...) moved into gun space by matrix m."""
    r = m.to_3x3()
    s = dict(spec)
    s["F_t"] = r @ Vector(spec["F_t"])
    s["A_hint"] = r @ Vector(spec["A_hint"])
    s["anchor_target"] = m @ Vector(spec["anchor_target"])
    s["thumb_dirs"] = [r @ Vector(d) for d in spec["thumb_dirs"]]
    if spec.get("wrap"):
        s["wrap"] = dict(spec["wrap"], frame=m @ spec["wrap"].get("frame", I4))
    return s


def mix_spec(a, b, t):
    """Between two hand poses that use the same anchor point on the hand."""
    if t <= 0:
        return dict(a)
    if t >= 1:
        return dict(b)
    s = dict(a)
    s["curls"] = {f: tuple(lerp(x, y, t) for x, y in zip(a["curls"][f], b["curls"][f])) for f in a["curls"]}
    for k in ("F_t", "A_hint", "anchor_target"):
        s[k] = Vector(a[k]).lerp(Vector(b[k]), t)
    s["thumb_dirs"] = [Vector(x).normalized().lerp(Vector(y).normalized(), t) for x, y in zip(a["thumb_dirs"], b["thumb_dirs"])]
    wa, wb = a.get("wrap"), b.get("wrap")                # fingers laid round a grip: fade in / out with the pose
    if wa and wb:
        s["wrap"] = dict(wa, front=tuple(lerp(x, y, t) for x, y in zip(wa["front"], wb["front"])),
                         pts=tuple((lerp(p[0], q[0], t), lerp(p[1], q[1], t)) for p, q in zip(wa["pts"], wb["pts"])),
                         weight=lerp(wa.get("weight", 1.0), wb.get("weight", 1.0), t),
                         frame=mix_m(wa.get("frame", I4), wb.get("frame", I4), t))
    elif wa:
        s["wrap"] = dict(wa, weight=wa.get("weight", 1.0) * (1 - t))
    elif wb:
        s["wrap"] = dict(wb, weight=wb.get("weight", 1.0) * t)
    return s


def away_left(anchor_fn):
    """Left hand out of the way: low and to the left, out of frame, relaxed, palm turned in. Given in the eye's
    frame: use xform_spec(spec, root_matrix.inverted())."""
    return dict(curls={2: (22, 32, 18), 3: (26, 36, 20), 4: (30, 40, 22), 5: (34, 44, 24)},
                F_t=Vector((0.15, 0.25, -0.95)), A_hint=Vector((0.0, -1.0, 0.0)), anchor_fn=anchor_fn,
                anchor_target=Vector((-0.2, -0.4, -0.2)),
                thumb_dirs=((0.25, 0.6, -0.75), (0.2, 0.7, -0.7), (0.15, 0.75, -0.65)))


def sway(t, k=1.0, period=3.0, tremor=1.0):
    """The idle figure-eight (breathing + a little tremor): side to side once, up and down twice per period."""
    ph = math.tau * t / period
    return dict(right=k * (0.0045 * math.sin(ph) + tremor * 0.0004 * math.sin(7 * ph + 1.0)),
                up=k * (0.0028 * math.sin(2 * ph) + 0.002 * math.sin(ph - 0.5) + tremor * 0.0003 * math.sin(9 * ph)),
                fwd=k * 0.0015 * math.sin(ph + 2.0),
                pitch=k * 0.45 * math.sin(2 * ph + 0.4), yaw=k * 0.5 * math.sin(ph + 1.0), roll=k * 0.7 * math.sin(ph + 0.3))


# ---------------------------------------------------------------------- baking
def write_fcurves(ch, tag):
    """Turn recorded channels {(datablock, data_path, index, group): {frame: value}} into one action per datablock,
    a linear key on every recorded frame."""
    acts = {}
    for (idb, path, idx, group), keys in ch.items():
        if idb not in acts:
            idb.animation_data_create()
            acts[idb] = bpy.data.actions.new(f"{idb.name}.{tag}Anim")
            idb.animation_data.action = acts[idb]
        fc = acts[idb].fcurves.new(path, index=idx, action_group=group)
        frames = sorted(keys)
        fc.keyframe_points.add(len(frames))
        flat = []
        for fr in frames:
            flat += [fr, keys[fr]]
        fc.keyframe_points.foreach_set("co", flat)
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
        fc.update()
    return acts


class Recorder:
    """Collects keys frame by frame: object transforms (as matrices) and plain numbers."""

    def __init__(self):
        self.ch = {}            # (datablock, data_path, index, group) -> {frame: value}
        self.last = {}

    def _put(self, idb, path, values, frame, group):
        for i, v in enumerate(values):
            self.ch.setdefault((idb, path, i, group), {})[frame] = v

    def _trs(self, idb, prefix, key, frame, loc, quat, scale, group):
        prev = self.last.get(key)
        if prev is not None and prev.dot(quat) < 0:      # keep neighbouring keys on the same side of the sphere
            quat = -quat
        self.last[key] = quat.copy()
        self._put(idb, prefix + "location", loc, frame, group)
        self._put(idb, prefix + "rotation_quaternion", quat, frame, group)
        self._put(idb, prefix + "scale", scale, frame, group)

    def key_object(self, ob, frame, basis, hidden=False):
        """Key an object's own transform (its matrix_basis); hidden = scale 0 at that place."""
        loc, quat, scale = basis.decompose()
        if hidden:
            scale = Vector((0, 0, 0))
        ob.rotation_mode = "QUATERNION"
        self._trs(ob, "", ob.name, frame, loc, quat, scale, "Object Transforms")

    def key_value(self, idb, path, frame, value):
        self._put(idb, path, [value], frame, "Animation")


class Baker(Recorder):
    def __init__(self, weapon, hold, parts, props=None, first_frame=1, label=""):
        """hold = {side: hold pose spec}; parts = {object name: rest matrix in gun space, None = hidden, or
        ("hidden", matrix) = hidden at that place};
        props = {(datablock, data_path): rest value} for extra animated numbers (a light's energy)."""
        super().__init__()
        self.weapon, self.first_frame, self.label = weapon, first_frame, label
        self.root = bpy.data.objects[H.COLL[weapon]]
        self.cam = bpy.data.objects["PlayerCamera"]
        self.local0 = H.view_local(weapon)
        # the camera is shared by the weapon views: keep the keys the other view baked (each view owns WINDOW frames)
        ad = self.cam.animation_data
        if ad and ad.action:
            for fc in ad.action.fcurves:
                keep = {kp.co[0]: kp.co[1] for kp in fc.keyframe_points
                        if not first_frame - 1 <= kp.co[0] < first_frame - 1 + WINDOW}
                if keep:
                    self.ch[(self.cam, fc.data_path, fc.array_index, "Object Transforms")] = keep
            old = ad.action
            self.cam.animation_data_clear()
            if old.users == 0:
                bpy.data.actions.remove(old)
        self.root.animation_data_clear()
        self.root.matrix_basis = self.local0
        self.cam0 = self.cam.matrix_basis.copy()
        self.rigs = {s: bpy.data.objects[f"ArmRig.{s}.{weapon}"] for s in hold}
        self.hold = {s: dict(sp) for s, sp in hold.items()}
        # shoulders and elbow directions stay fixed to the eye (the body), whatever the gun does
        self.sh_cam = {s: self.local0 @ Vector(sp["shoulder"]) for s, sp in hold.items()}
        self.pole_cam = {s: self.local0.to_3x3() @ Vector(sp["pole"]) for s, sp in hold.items()}
        self.parts = dict(parts)
        self.objs = {n: bpy.data.objects[n] for n in parts}
        self.props = dict(props or {})
        self.last_loc = {n: I4.decompose()[:2] for n in parts}
        self.clips = {}
        self.worst = {}
        for ob in list(self.objs.values()) + list(self.rigs.values()):
            ob.animation_data_clear()
        for idb, _ in self.props:
            idb.animation_data_clear()
        self.mods = [m for r in self.rigs.values() for c in r.children for m in c.modifiers if m.type == "ARMATURE"]
        for m in self.mods:     # no need to deform the gloves while the poses are solved
            m.show_viewport = False

    # .................................................................. recording
    def frame(self, f, st=None):
        """Apply a state and record it at frame f. Missing fields mean 'at rest'."""
        st = st or {}
        root_m = st.get("root", self.local0)
        cam_m = self.cam0 @ st.get("cam", I4)
        self.root.matrix_basis = root_m
        self.cam.matrix_basis = cam_m
        inv = root_m.inverted()
        self._trs(self.root, "", "root", f, *root_m.decompose(), "Object Transforms")
        self._trs(self.cam, "", "cam", f, *cam_m.decompose(), "Object Transforms")
        for name, ob in self.objs.items():
            m = st.get("objs", {}).get(name, self.parts[name])
            if isinstance(m, tuple):                     # ("cam", matrix): given in the eye's frame
                m = inv @ m[1]
            if isinstance(m, tuple):                     # ("hidden", matrix): scale 0 at that place
                self.last_loc[name] = m[1].decompose()[:2]
                m = None
            if m is None:                                # hidden: scale 0 where it last was
                loc, quat = self.last_loc[name]
                scale = Vector((0, 0, 0))
            else:
                loc, quat, scale = m.decompose()
                self.last_loc[name] = (loc.copy(), quat.copy())
            ob.rotation_mode = "QUATERNION"
            ob.location, ob.rotation_quaternion, ob.scale = loc, quat, scale
            self._trs(ob, "", name, f, loc, quat, scale, "Object Transforms")
        for (idb, path), rest in self.props.items():
            v = st.get("props", {}).get((idb, path), rest)
            self._put(idb, path, [v], f, "Animation")
        for side, rig in self.rigs.items():
            spec = dict(st.get("hands", {}).get(side) or self.hold[side])
            spec["shoulder"] = inv @ self.sh_cam[side]
            spec["pole"] = inv.to_3x3() @ self.pole_cam[side]
            H.pose(rig, side, quiet=True, reach=0.96, **spec)
            pb = rig.pose.bones
            fax = (pb["wrist"].head - pb["lowerarm01"].head).normalized()
            bend = math.degrees(fax.angle((pb["finger3-1"].head - pb["wrist"].head).normalized()))
            self.worst[side] = max(self.worst.get(side, 0.0), bend)
            for b in pb:
                self._trs(rig, f'pose.bones["{b.name}"].', (side, b.name), f, b.location.copy(),
                          b.rotation_quaternion.copy(), b.scale.copy(), b.name)

    def clip(self, name, start, n, fn, loop=False):
        """Bake n frames of fn(t seconds) -> state from frame `start`, with the rest pose keyed just outside."""
        self.worst = {}
        self.frame(start - 1)
        for i in range(n):
            self.frame(start + i, fn(i / FPS))
        self.frame(start + n)
        self.clips[name] = dict(start=start, end=start + n - 1, loop=loop)
        print(f"clip {name}: frames {start}-{start + n - 1}" + (" (loop)" if loop else "")
              + "  max wrist bend " + ", ".join(f"{s} {v:.0f}" for s, v in self.worst.items()))
        return start + n

    # .................................................................. writing
    def write(self):
        sc = bpy.context.scene
        write_fcurves(self.ch, self.weapon)
        for ob in (self.root, self.cam):
            ob.rotation_mode = "QUATERNION"
        for m in self.mods:
            m.show_viewport = True
        mine = {self.label + name for name in self.clips}
        for mk in list(sc.timeline_markers):
            if mk.name in mine or self.first_frame - 1 <= mk.frame < self.first_frame - 1 + WINDOW:
                sc.timeline_markers.remove(mk)
        for name, c in self.clips.items():
            sc.timeline_markers.new(self.label + name, frame=c["start"])
        sc["v2_clips_" + self.weapon] = json.dumps(self.clips)
        sc.render.fps = FPS
        sc.frame_start = 1
        sc.frame_end = max(c["end"] for k in sc.keys() if k.startswith("v2_clips_") for c in json.loads(sc[k]).values())
        sc.frame_set(1)
        return self.clips

    def run(self, clips, argv=()):
        """Bake [(name, seconds, fn, loop), ...] one after another (8 frames apart) and write the actions.
        argv may hold only=Name,Name to bake some of them (the others keep their slot, without keys)."""
        only = [a.split("=")[1].split(",") for a in argv if a.startswith("only=")]
        start = self.first_frame
        for name, dur, fn, loop in clips:
            n = round(dur * FPS)
            if only and name not in only[0]:
                self.clips[name] = dict(start=start, end=start + n - 1, loop=loop)
                start += n + 8
                continue
            start = self.clip(name, start, n, fn, loop) + 8
        assert start - self.first_frame <= WINDOW, "clips do not fit the view's frame window"
        return self.write()
