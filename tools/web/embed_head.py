#!/usr/bin/env python3
"""Copies tools/web/head_include.html into the "Web (site)" preset of export_presets.cfg (its html/head_include).

    python3 -I tools/web/embed_head.py        # after editing head_include.html
"""
import os, re
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
head = open(os.path.join(root, "tools", "web", "head_include.html"), encoding="utf-8").read().rstrip("\n")
cfg_path = os.path.join(root, "export_presets.cfg")
cfg = open(cfg_path, encoding="utf-8").read()
at = cfg.index('name="Web (site)"')
m = re.compile(r'html/head_include="((?:[^"\\]|\\.)*)"', re.S).search(cfg, at)
assert m, "the preset has no html/head_include"
escaped = head.replace("\\", "\\\\").replace('"', '\\"')
cfg = cfg[:m.start(1)] + escaped + cfg[m.end(1):]
open(cfg_path, "w", encoding="utf-8").write(cfg)
print("head include: %d characters into export_presets.cfg" % len(head))
