"""Quaternius Sci-Fi Essentials Kit + Modular Sci-Fi MegaKit (CC0) -> our glbs.

    blender -b -P blender/scripts/normalize_quaternius.py -- assets_src/quaternius assets/models

Raw packs live in assets_src/quaternius/ (git-ignored; fetched from itch.io). Every piece is
re-framed to our conventions (CLAUDE.md "Kit piece frames"), helper meshes without materials
are dropped, and Quaternius' own materials and textures are kept (embedded as JPEG; Godot's
MaterialLib passes unknown material names through untouched).

Outputs (assets/models/):
  q_kit.glb      Floor_A/B/C, Ceiling, CeilingLight, Wall_Astra/Band/Window, Doorframe, Pillar, Deco_*
  q_door.glb     Door with PanelL / PanelR (Godot slides them apart 1.9 m)
  turret.glb     Enemy_Trilobite   (rig + Idle/Look/Attack/AttackAuto/Hit/TurnOff... actions)
  brawler.glb    Enemy_QuadShell   (rig + Run/Charge/Attack/Hit/TurnOff...)
  pursuer.glb    Enemy_EyeDrone    (rig + Idle/Look/Charging/Attack/Hit/BackFlip)
  pistol.glb rifle.glb   Gun_Pistol / Gun_Rifle, barrel +Y, origin at the grip, "Muzzle"
  container.glb  Prop_Chest (rig + Open/Close)
  kit.glb ammo.glb health_cell.glb   Prop_HealthPack / Prop_Ammo_Small / Prop_HealthPack_Tube
"""
import json
import math
import os
import shutil
import sys

import bpy
from mathutils import Matrix, Vector

args = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = args[0], args[1]
ESS = os.path.join(SRC, "sci-fi-essentials-kit", "glTF")
MEGA = os.path.join(SRC, "modular-sci-fi-megakit", "Modular SciFi MegaKit[Standard]", "glTF")


_canon = {}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    _canon.clear()


def _dedupe_materials(objs):
    """Repeated imports create MI_Trim_01.001, .002 ...; map every slot back to one material per
    base name so merged meshes keep one surface (one draw call) per real material."""
    for o in objs:
        if o.type != "MESH":
            continue
        for slot in o.material_slots:
            m = slot.material
            if m is None:
                continue
            base = m.name.split(".")[0]
            if base not in _canon:
                _canon[base] = m
                m.name = base
            slot.material = _canon[base]


def load(path):
    """Import a glTF; return its new objects, minus untextured helper meshes."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for o in list(new):
        if o.type == "MESH" and len(o.data.materials) == 0:
            bpy.data.objects.remove(o)
            new.remove(o)
    _dedupe_materials(new)
    return new


def mesh_bounds(objs):
    pts = [o.matrix_world @ Vector(c) for o in objs if o.type == "MESH" for c in o.bound_box]
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    return lo, hi


def static_piece(name, parts, xform=Matrix.Identity(4)):
    """parts: [(gltf path, Matrix)] -> one joined mesh object `name`, baked with xform."""
    objs = []
    for path, m in parts:
        for o in load(path):
            if o.type == "MESH":
                o.data = o.data.copy()
                o.data.transform(xform @ m @ o.matrix_world)
                o.matrix_world = Matrix.Identity(4)
                o.parent = None
                objs.append(o)
            elif o.type == "EMPTY":
                bpy.data.objects.remove(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def base_centre(objs):
    """Matrix that centres objs on X/Y and puts their lowest point at z=0."""
    lo, hi = mesh_bounds(objs)
    return Matrix.Translation(Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z)))


def export(path, objects, animations=False):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
        for c in o.children_recursive:
            c.select_set(True)
    _record_materials(objects)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True, export_animations=animations, export_animation_mode="ACTIONS",
                              export_image_format="NONE", export_tangents=True)
    print("exported", path)


# Textures are shared between many glbs (trim sheets, the props and enemy atlases). Embedding
# them would make Godot extract one copy per glb, so glbs carry material *names* only and
# MaterialLib builds each material once from q_materials.json + assets/textures/quaternius/.
MATERIALS = {}
TEXTURES = set()


def _tex_name(node):
    return os.path.splitext(node.image.name)[0].replace("_png", "")


def _record_materials(objects):
    obs = set()
    for o in objects:
        obs.add(o)
        obs.update(o.children_recursive)
    for o in obs:
        if o.type != "MESH":
            continue
        for slot in o.material_slots:
            m = slot.material
            if m is None or m.name in MATERIALS or not m.use_nodes:
                continue
            bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
            spec = {"color": [1, 1, 1, 1], "metallic": 0.0, "roughness": 0.5, "base": "", "orm": "", "normal": "",
                    "alpha": m.blend_method != "OPAQUE" or (bsdf is not None and bsdf.inputs["Alpha"].default_value < 0.999)}
            if bsdf:
                spec["color"] = list(bsdf.inputs["Base Color"].default_value)
                spec["metallic"] = bsdf.inputs["Metallic"].default_value
                spec["roughness"] = bsdf.inputs["Roughness"].default_value
                spec["alpha_value"] = bsdf.inputs["Alpha"].default_value
            for n in m.node_tree.nodes:
                if n.type != "TEX_IMAGE" or n.image is None:
                    continue
                t = _tex_name(n)
                low = t.lower()
                kind = "normal" if "normal" in low else "orm" if "orm" in low else "base"
                spec[kind] = t
                TEXTURES.add((t, n.image.filepath_raw or n.image.filepath))
            MATERIALS[m.name] = spec


def write_material_table():
    tex_out = os.path.join(OUT, "..", "textures", "quaternius")
    os.makedirs(tex_out, exist_ok=True)
    for t, fp in sorted(TEXTURES):
        src = bpy.path.abspath(fp)
        if os.path.exists(src):
            shutil.copy(src, os.path.join(tex_out, t + ".png"))
        else:
            print("  missing texture", t, src)
    with open(os.path.join(OUT, "q_materials.json"), "w") as f:
        json.dump(MATERIALS, f, indent=1, sort_keys=True)
    print(f"wrote {len(MATERIALS)} materials, {len(TEXTURES)} textures")


M = lambda *p: os.path.join(MEGA, *p)
E = lambda *p: os.path.join(ESS, *p)
WALL = Matrix.Rotation(math.pi / 2, 4, "Z") @ Matrix.Translation((2, 0, 0))  # cell -X edge -> edge frame facing +Y
H = 5.0  # wall height (bottom strip + 3 m wall + 2 m top band)


def kit():
    reset()
    pieces = []
    for n, src in (("Floor_A", "Platform_Metal"), ("Floor_B", "Platform_DarkPlates"), ("Floor_C", "Platform_Squares")):
        pieces.append(static_piece(n, [(M("Platforms", src + ".gltf"), Matrix.Identity(4))]))
    flip = Matrix.Translation((0, 0, H)) @ Matrix.Rotation(math.pi, 4, "X")
    pieces.append(static_piece("Ceiling", [(M("Platforms", "Platform_DarkPlates.gltf"), flip)]))
    light = Matrix.Translation((0.66, 0, H - 0.01))  # Prop_Light_Wide spans x -1.32..0, hangs below z=0
    pieces.append(static_piece("CeilingLight", [(M("Platforms", "Platform_DarkPlates.gltf"), flip),
                                                (M("Props", "Prop_Light_Wide.gltf"), light)]))
    styles = {
        "Wall_Astra": ("BottomMetal_Straight", "WallAstra_Straight", "TopCables_Straight"),
        "Wall_Band": ("BottomSimple_Straight", "WallBand_Straight", "TopSimple_Straight"),
        "Wall_Window": ("BottomMetal_Straight", "WallWindow_Straight", "TopPlastic_Straight"),
    }
    for n, (b, w, t) in styles.items():
        pieces.append(static_piece(n, [(M("Walls", x + ".gltf"), Matrix.Identity(4)) for x in (b, w, t)], WALL))
    pieces.append(static_piece("Doorframe", [(M("Platforms", "Door_Frame_Square.gltf"), Matrix.Identity(4))]))
    pieces.append(static_piece("Pillar", [(M("Columns", "Column_Hollow.gltf"), Matrix.Identity(4))]))
    deco = {
        # Only pieces shallow enough to stand against a wall without blocking a lane
        # (DungeonGen.DECO_KINDS).
        "Deco_Crate3": M("Props", "Prop_Crate3.gltf"),
        "Deco_BarrelLarge": M("Props", "Prop_Barrel_Large.gltf"), "Deco_Computer": M("Props", "Prop_Computer.gltf"),
        "Deco_Barrel": E("Prop_Barrel1.gltf"), "Deco_Locker": E("Prop_Locker.gltf"),
        "Deco_Shelves": E("Prop_Shelves_ThinTall.gltf"),
    }
    for n, path in deco.items():
        tmp = load(path)
        m = base_centre(tmp)
        for o in tmp:
            bpy.data.objects.remove(o)
        pieces.append(static_piece(n, [(path, m)]))
    export(os.path.join(OUT, "q_kit.glb"), pieces)
    for p in pieces:
        lo, hi = mesh_bounds([p])
        print(f"  {p.name:16s} {tuple(round(x, 2) for x in lo)} .. {tuple(round(x, 2) for x in hi)}")


def door():
    reset()
    root = bpy.data.objects.new("Door", None)
    bpy.context.scene.collection.objects.link(root)
    left = static_piece("PanelL", [(M("Platforms", "Door_DarkMetal.gltf"), Matrix.Identity(4))])
    right = static_piece("PanelR", [(M("Platforms", "Door_DarkMetal.gltf"), Matrix.Rotation(math.pi, 4, "Z"))])
    # No baked animation: glTF keeps one action per object, so Godot's Door slides the two
    # halves itself (PanelL -> -x, PanelR -> +x, 1.9 m).
    for p in (left, right):
        p.parent = root
    export(os.path.join(OUT, "q_door.glb"), [root])


def rigged(src, out, height, root_name):
    """Animated asset: keep the armature + actions, scale so the mesh is `height` tall, base on z=0."""
    reset()
    objs = load(src)
    lo, hi = mesh_bounds(objs)
    k = height / (hi.z - lo.z)
    tops = [o for o in objs if o.parent is None]
    root = bpy.data.objects.new(root_name, None)
    bpy.context.scene.collection.objects.link(root)
    for o in tops:
        o.parent = root
    root.scale = (k, k, k)
    root.location = (0, 0, -lo.z * k)
    bpy.context.view_layer.update()
    lo2, hi2 = mesh_bounds(objs)
    print(f"  {root_name}: scale {k:.3f} -> {tuple(round(x, 2) for x in lo2)} .. {tuple(round(x, 2) for x in hi2)}; "
          f"actions {[a.name for a in bpy.data.actions]}")
    export(os.path.join(OUT, out), [root], animations=True)


def gun(src, out, length, name):
    reset()
    objs = load(src)
    # Barrel points -X in the pack; turn to +Y and scale to `length`; origin stays at the grip.
    lo, hi = mesh_bounds(objs)
    k = length / (hi.x - lo.x)
    m = Matrix.Scale(k, 4) @ Matrix.Rotation(-math.pi / 2, 4, "Z")
    ob = static_piece(name + "Body", [(src, m)])
    for o in objs:
        if o.name in bpy.data.objects and o != ob:
            bpy.data.objects.remove(o)
    lo, hi = mesh_bounds([ob])
    front = [v.co for v in ob.data.vertices if v.co.y > hi.y - 0.01]
    c = sum(front, Vector()) / len(front)
    root = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(root)
    ob.parent = root
    mz = bpy.data.objects.new("Muzzle", None)
    bpy.context.scene.collection.objects.link(mz)
    mz.parent = root
    mz.location = (0, hi.y + 0.005, c.z)
    print(f"  {name}: {tuple(round(x, 3) for x in lo)} .. {tuple(round(x, 3) for x in hi)}, muzzle {tuple(round(x, 3) for x in mz.location)}")
    export(os.path.join(OUT, out), [root])


def prop(src, out, name, scale=1.0):
    reset()
    tmp = load(src)
    m = Matrix.Scale(scale, 4) @ base_centre(tmp)
    for o in tmp:
        bpy.data.objects.remove(o)
    ob = static_piece(name + "Prop", [(src, m)])
    root = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(root)
    ob.parent = root
    export(os.path.join(OUT, out), [root])


os.makedirs(OUT, exist_ok=True)
kit()
door()
rigged(E("Enemy_Trilobite.gltf"), "turret.glb", 2.4, "Turret")
rigged(E("Enemy_QuadShell.gltf"), "brawler.glb", 1.3, "Brawler")
rigged(E("Enemy_EyeDrone.gltf"), "pursuer.glb", 1.0, "Pursuer")
rigged(E("Prop_Chest.gltf"), "container.glb", 0.9, "Container")
gun(E("Gun_Pistol.gltf"), "pistol.glb", 0.30, "Pistol")
gun(E("Gun_Rifle.gltf"), "rifle.glb", 0.82, "Rifle")
prop(E("Prop_HealthPack.gltf"), "kit.glb", "Kit")
prop(E("Prop_Ammo_Small.gltf"), "ammo.glb", "Ammo")
prop(E("Prop_HealthPack_Tube.gltf"), "health_cell.glb", "HealthCell", scale=1.4)
write_material_table()
