#!/usr/bin/env python3
"""Side-by-side contact sheet of two capture sets plus a per-view change score.

    python3 tools/compare.py                       # captures/prev vs captures/latest
    python3 tools/compare.py captures/a captures/b
Writes <new>/compare.png. Change score = mean absolute pixel difference (0-255).
"""
import sys, pathlib
from PIL import Image, ImageChops, ImageDraw, ImageStat

old = pathlib.Path(sys.argv[1] if len(sys.argv) > 2 else "captures/prev")
new = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "captures/latest")
names = sorted({p.name for p in new.glob("*.png") if p.name != "compare.png"} |
               {p.name for p in old.glob("*.png") if p.name != "compare.png"})
W, H = 640, 360
sheet = Image.new("RGB", (W * 2, (H + 24) * len(names)), (20, 20, 24))
d = ImageDraw.Draw(sheet)
for i, n in enumerate(names):
    y = i * (H + 24)
    imgs = []
    for col, base in enumerate((old, new)):
        p = base / n
        if p.exists():
            im = Image.open(p).convert("RGB").resize((W, H))
            sheet.paste(im, (col * W, y + 24))
            imgs.append(im)
        else:
            d.text((col * W + 10, y + 120), "(missing)", fill=(255, 80, 80))
    score = "n/a"
    if len(imgs) == 2:
        score = "%.1f" % (sum(ImageStat.Stat(ImageChops.difference(*imgs)).mean) / 3)
    d.text((8, y + 6), f"{n}   [{old.name} | {new.name}]   change={score}", fill=(220, 240, 255))
    print(f"{n:28s} change={score}")
out = new / "compare.png"
sheet.save(out)
print("wrote", out)
