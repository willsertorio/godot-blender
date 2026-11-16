"""The environment set, modelled from the references in v2/reference/set (one function per asset, in set_*.py).

    blender -b -P v2/scripts/build_set.py                       # every asset -> v2/set.blend
    blender -b -P v2/scripts/build_set.py -- --only=crate,drum --render    # those only, and their pictures
    blender -b -P v2/scripts/build_set.py -- --render           # everything and every picture (v2/renders/set/)
then  python3 -I v2/scripts/set_sheet.py                        # the sheets, from the pictures

Each asset is rendered alone in a grey studio from two sides, as the reference sheets show them."""
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import setlib as S  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
only = []
for a in argv:
    if a.startswith("--only="):
        only = a[7:].split(",")
render = "--render" in argv
samples = 72
for a in argv:
    if a.startswith("--samples="):
        samples = int(a[10:])

bpy.ops.wm.read_factory_settings(use_empty=True)
S.studio(samples)
import set_structure, set_cover, set_equipment, set_pickups  # noqa: E401,E402,F401  (they register their assets)

OUT = os.path.normpath(os.path.join(HERE, "..", "renders", "set"))
os.makedirs(OUT, exist_ok=True)
x = 0.0
roots = {}
for name, (fn, opts) in S.ASSETS.items():
    if only and name not in only:
        continue
    root = S.begin(name, at=(x, 0, 0))
    fn()
    roots[name] = (root, opts)
    x += 8.0
bpy.context.view_layer.update()
for name, (root, opts) in roots.items():
    lo, hi = S.bounds(root)
    print("[set] %-16s %.2f x %.2f x %.2f m, %d parts" % (name, hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, len(root.children_recursive)))
    if render:
        views = opts.get("views", [(-0.5, -1.0, 0.25), (1.0, -0.32, 0.12)])
        for k, v in enumerate(views):
            S.shoot(root, v, os.path.join(OUT, "%s_%s.png" % (name, "ab"[k])), res=opts.get("res", [(700, 620), (460, 620)])[k],
                    hide=opts.get("hide", [None, None])[k])
if not only:
    bpy.ops.wm.save_as_mainfile(filepath=os.path.normpath(os.path.join(HERE, "..", "set.blend")), compress=True)
