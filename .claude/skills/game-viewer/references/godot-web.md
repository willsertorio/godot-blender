# The game in the browser (Godot 4.3, GL Compatibility, no threads)

Measured on Project Firewall: Chrome on an M1 went from 30-40 fps to ~50 fps in combat with these.

## Export

- A separate preset for the site (e.g. "Web (site)") exporting to `build/site/play/index.html`, no threads (works
  on any static host, no COOP/COEP headers), VRAM compression for desktop.
- **Trim the pck**: `export_filter="all_resources"` packs every imported file. Exclude what the shipped scenes do
  not load (earlier versions' art, review files, `site/*`, `docs/*`, `build/*`). Glob `*` matches across `/`, so
  list files by name when a folder mixes kept and dropped ones. 191 MB -> 77 MB. GitHub rejects files > 100 MB
  and warns over 50 MB.
- **Frame-stall fix** (`scripts/web_head_include.html` -> the preset's `html/head_include`, escaped): Emscripten's
  shell calls `getParameter(SCISSOR_TEST)` at the end of every frame, which makes the browser wait for the GPU
  process; the page thread stood still for most of the frame ("process step" 33 ms with 2 ms drawing, 3 ms scripts).
- Godot imports anything under `res://`: put `.gdignore` in `build/` and `site/`.

## Known browser-only bugs and their fixes

- **Silent sound effects, music fine**: Godot 4.3 web plays sounds as Web Audio samples; a bus added at runtime
  (with reverb/limiter) is silent. On web, play on `Master`.
- **Black screen on a hit**: `textureLod` on a screen texture with mipmaps returns black in WebGL. Use a two-pass
  blur (`BackBufferCopy` + a separable Gaussian) instead.
- **Opens on the pause card**: pointer lock needs a click/key within the last moments; ask for it on the key or
  click that starts the run, and show "click to play" when refused.
- **Slow first load into the game**: build the level over frames behind a progress bar; preload models and sounds
  during the title; draw one of each effect under the loading sheet so shaders compile there.
- **Firing drops frames**: `.ogg` one-shots set up a Vorbis decoder on every play (1.3 ms each in WASM); use WAV
  for one-shots, pool effect nodes and sound players.
- Point lights spawned per shot/hit add per-pixel cost on large merged meshes: switch them off on web.

## Measuring

- This container renders WebGL in software (SwiftShader): frame rate here means nothing; the page's own thread
  time does. Ask the user for the in-game F3 readout on their machine (fps, frame ms, draw calls, per-system ms).
- Lowering render resolution (`scaling_3d_scale`) only helps when GPU-bound; if 720 rows barely changes fps, look
  at the CPU side (draw calls, engine stalls, scripts).
- Drive the build headless with Playwright (`--use-gl=angle --use-angle=swiftshader --enable-unsafe-swiftshader`);
  a screenshot of the game can take minutes; pointer lock fails headless (expect the pause card).
