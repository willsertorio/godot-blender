"""The V2 texture sets for Godot: v2/textures/<Set>/*_{Color,NormalGL,Roughness}.jpg -> assets/textures/v2/<Set>_{color,normal,rough}.jpg at 1K."""
import glob
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "textures")
DST = os.path.join(HERE, "..", "..", "assets", "textures", "v2")
os.makedirs(DST, exist_ok=True)
for d in sorted(os.listdir(SRC)):
    for suffix, short in (("Color", "color"), ("NormalGL", "normal"), ("Roughness", "rough")):
        f = glob.glob(os.path.join(SRC, d, f"*_{suffix}.jpg"))
        if f:
            im = Image.open(f[0]).convert("RGB" if short != "rough" else "L").resize((1024, 1024), Image.LANCZOS)
            im.save(os.path.join(DST, f"{d}_{short}.jpg"), quality=90)
print(sorted(os.listdir(DST)))
