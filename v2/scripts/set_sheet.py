"""Sheets of the environment set from the pictures in v2/renders/set (two views an asset, side by side, labelled).
    python3 -I v2/scripts/set_sheet.py                      # all of them: v2/renders/set_sheet_<n>.jpg
    python3 -I v2/scripts/set_sheet.py OUT.jpg name name ...  # those only, into one picture"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, "..", "renders", "set"))
ORDER = ["wall_plain", "wall_screen", "wall_service", "door", "floor_plain", "floor_grating", "floor_hazard", "ceiling_light",
         "ceiling_services", "corridor", "column", "crate", "crate_stack", "drum", "drum_stack", "barrier", "tank", "server_rack",
         "power_core", "console", "locker", "shelving", "workbench", "charging_dock", "pipe_riser", "exit_portal", "loot_crate",
         "loot_crate_olive", "loot_crate_green", "medkit", "medkit_white", "ammo_box", "ammo_box_shut"]


def pair(name):
    a = Image.open(os.path.join(SRC, name + "_a.png")).convert("RGB")
    b = Image.open(os.path.join(SRC, name + "_b.png")).convert("RGB")
    out = Image.new("RGB", (a.width + b.width, max(a.height, b.height)), (48, 48, 48))
    out.paste(a, (0, 0))
    out.paste(b, (a.width, 0))
    return out


def sheet(names, path, cols=3, tile=(870, 465)):
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 22)
    except OSError:
        font = ImageFont.load_default()
    rows = (len(names) + cols - 1) // cols
    out = Image.new("RGB", (tile[0] * cols, tile[1] * rows), (48, 48, 48))
    for i, n in enumerate(names):
        im = pair(n).resize(tile, Image.LANCZOS)
        x, y = (i % cols) * tile[0], (i // cols) * tile[1]
        out.paste(im, (x, y))
        ImageDraw.Draw(out).text((x + 12, y + 8), n.replace("_", " "), fill=(255, 255, 255), font=font)
    out.save(path, quality=90)
    print(path, out.size)


if __name__ == "__main__":
    have = [n for n in ORDER if os.path.exists(os.path.join(SRC, n + "_a.png"))]
    if len(sys.argv) > 2:
        sheet(sys.argv[2:], sys.argv[1], cols=min(len(sys.argv) - 2, 3))
    else:
        for k in range(0, len(have), 9):
            sheet(have[k:k + 9], os.path.normpath(os.path.join(SRC, "..", "set_sheet_%d.jpg" % (k // 9 + 1))))
