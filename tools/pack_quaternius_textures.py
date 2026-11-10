#!/usr/bin/env python3
"""Downsize + recompress the Quaternius textures copied by normalize_quaternius.py.

    python3 -I tools/pack_quaternius_textures.py

Budget (web build): trim-sheet / padded-wall *base colour* stays 2K (what you look at most);
every other map (normal, ORM, props, enemies, guns, emissive masks) goes to 1K. Opaque maps
become JPEG; maps with alpha (decals) stay PNG. Originals (PNG) are replaced.
"""
import pathlib
from PIL import Image

D = pathlib.Path(__file__).resolve().parent.parent / "assets" / "textures" / "quaternius"
for p in sorted(D.glob("*.png")):
    im = Image.open(p)
    keep_2k = (p.stem.startswith(("T_Trim_", "T_PaddedWall")) and "BaseColor" in p.stem) or "Cables" in p.stem
    size = 2048 if keep_2k else 1024
    if max(im.size) > size:
        im = im.resize((size, size), Image.LANCZOS)
    has_alpha = im.mode in ("RGBA", "LA") and im.getchannel("A").getextrema()[0] < 250
    if has_alpha:
        im.save(p, optimize=True)
        print(f"{p.name:40s} {im.size[0]} png (alpha)")
    else:
        out = p.with_suffix(".jpg")
        im.convert("RGB").save(out, quality=92 if "Normal" not in p.stem else 95)
        p.unlink()
        imp = p.with_suffix(".png.import")
        if imp.exists():
            imp.unlink()
        print(f"{out.name:40s} {im.size[0]} jpg")
