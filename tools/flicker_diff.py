"""Reads the frames of the flicker hunt (godot ... -- --game-capture=DIR --part=flicker): per view, `a` just after arriving from another
area, `b` eight frames later, `c` 1 mm aside. Lists the views where most pixels changed from a to b (a flash on
changing area) and from b to c (surfaces fighting for the same pixels, sparkle); writes the worst with the changed
pixels marked.
    python3 -I tools/flicker_diff.py DIR [how many]"""
import os
import sys

import numpy as np
from PIL import Image

d = sys.argv[1]
top = int(sys.argv[2]) if len(sys.argv) > 2 else 8


def load(name):
    return np.asarray(Image.open(os.path.join(d, name)).convert("RGB"), dtype=np.float32) / 255.0


for pair, what in (("ab", "after arriving (a -> b)"), ("bc", "1 mm aside (b -> c)")):
    rows = []
    for f in sorted(os.listdir(d)):
        if not f.endswith("_a.png") or f.startswith("hot_"):
            continue
        base = f[:-6]
        x, y = load(base + "_%s.png" % pair[0]), load(base + "_%s.png" % pair[1])
        diff = np.abs(x - y).max(axis=2)
        hot = diff > 0.08
        rows.append((int(hot.sum()), base, hot, float(np.abs(x.mean() - y.mean()))))
    rows.sort(key=lambda r: -r[0])
    counts = sorted(r[0] for r in rows)
    print("%s: %d views, changed pixels (of %d): median %d, 90%% %d" % (what, len(rows), rows[0][2].size, counts[len(rows) // 2], counts[int(len(rows) * 0.9)]))
    for n, name, hot, mean in rows[:top]:
        print("  %6d  %-22s mean brightness changed by %.3f" % (n, name, mean))
        if n:
            mark = np.asarray(Image.open(os.path.join(d, name + "_%s.png" % pair[1])).convert("RGB")).copy()
            mark[hot] = (255, 0, 255)
            Image.fromarray(mark).save(os.path.join(d, "hot_%s_%s.png" % (pair, name)))
