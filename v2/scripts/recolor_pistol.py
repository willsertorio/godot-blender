"""The pistol in the machine gun's colours: its slide the same white paint, its frame a grey one (it was dark steel
on black plastic, and read as a black gun beside the white machine gun).

    blender -b v2/scene.blend -P v2/scripts/recolor_pistol.py      # changes the two materials in place; saves
    v2/scripts/export_godot.sh materials                           # then: the game's material table

build_pistol.py makes the same two materials, so a rebuild gives the same gun.
"""
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_pistol as P  # noqa: E402

for name, make in P.PAINT.items():
    old = bpy.data.materials.get(name)
    if old is None:
        print("no material", name)
        continue
    old.name = name + "_old"
    new = make()
    old.user_remap(new)
    bpy.data.materials.remove(old)
    print("recoloured", name, "users", new.users)
bpy.ops.wm.save_mainfile()
