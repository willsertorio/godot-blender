#!/usr/bin/env bash
# Renderer load probe: runs seed 123 with --perf for ~25 s under a virtual display and
# prints the [perf] lines (draw calls / objects / primitives are GPU-independent; FPS here
# is software GL and not representative of a real GPU).
cd "$(dirname "$0")/.."
timeout 60 xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --resolution 1280x720 --path . \
  -- --seed="${1:-123}" --autostart --perf 2>&1 | grep '\[perf\]' | head -${2:-6}
