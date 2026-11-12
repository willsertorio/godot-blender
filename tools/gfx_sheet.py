#!/usr/bin/env python3
"""Before / after sheet of the graphics capture: python3 -I tools/gfx_sheet.py [before_dir] [after_dir] [out.png]"""
import sys, os
from PIL import Image, ImageDraw
a = sys.argv[1] if len(sys.argv) > 1 else "captures/gfx_before"
b = sys.argv[2] if len(sys.argv) > 2 else "captures/gfx"
out = sys.argv[3] if len(sys.argv) > 3 else "captures/gfx_compare.png"
names = sorted(f for f in os.listdir(b) if f.endswith(".png"))
W, H = 640, 360
sheet = Image.new("RGB", (W * 2, H * len(names)))
d = ImageDraw.Draw(sheet)
for i, n in enumerate(names):
    for j, src in enumerate((a, b)):
        p = os.path.join(src, n)
        if os.path.exists(p):
            sheet.paste(Image.open(p).convert("RGB").resize((W, H), Image.LANCZOS), (j * W, i * H))
    d.text((8, i * H + 6), "before", fill=(255, 255, 0)); d.text((W + 8, i * H + 6), "after  " + n, fill=(255, 255, 0))
sheet.save(out); print(out)
