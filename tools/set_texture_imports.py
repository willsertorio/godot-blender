#!/usr/bin/env python3
"""Force correct import settings on every 3D texture (assets/textures, assets/models).

Godot only auto-switches a texture to VRAM compression when the *editor* sees it used in
a 3D material; ours are bound at runtime by MaterialLib, so without this they import
lossless with no mipmaps (shimmering, ~16 MB VRAM each, huge web pck).

    python3 -I tools/set_texture_imports.py && godot --headless --editor --quit
"""
import pathlib, re

ROOT = pathlib.Path(__file__).resolve().parent.parent
WANT = {
    "compress/mode": "2",              # VRAM compressed (S3TC/BPTC desktop; ETC2 if enabled)
    "compress/high_quality": "false",
    "mipmaps/generate": "true",
    "detect_3d/compress_to": "0",      # already decided
}
n = 0
for imp in list(ROOT.glob("assets/textures/**/*.import")) + list(ROOT.glob("assets/models/*.jpg.import")) + list(ROOT.glob("assets/models/*.png.import")):
    s = imp.read_text()
    is_normal = bool(re.search(r"normal|nor_gl", imp.name, re.I))
    want = dict(WANT, **{"compress/normal_map": "1" if is_normal else "2"})  # 2 = disabled
    for k, v in want.items():
        pat = re.compile(rf"^{re.escape(k)}=.*$", re.M)
        s = pat.sub(f"{k}={v}", s) if pat.search(s) else s.replace("[params]\n", f"[params]\n\n{k}={v}\n", 1)
    imp.write_text(s)
    n += 1
print(f"updated {n} texture import files")
