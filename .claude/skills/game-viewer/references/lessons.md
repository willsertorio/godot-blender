# Lessons from building the Project Firewall viewer

## Working with the user
- Propose before building when asked "how would we..."; build only on "go ahead".
- They polish text in rounds: show the full text in chat, apply, then screenshot. Keep blocks non-repetitive
  (one Goal sentence; Steps; Learnings; Tools), no first person ("Learnings", not "what I watched for").
- Offer picture candidates as lettered contact sheets per section, with a recommended pick.
- Screenshot first; zip/push only on request. Push to `gh-pages` only when told.

## 3D viewer
- Godot-style projects often export glbs without images and rebuild materials by name: the viewer then needs a
  port of those rules (box/triplanar projection in object space, worn-paint masks from UV, vertex-colour wear,
  rest-pose projection for skinned gloves, unlit animated shaders for screens / portal / muzzle flash). Port GLSL
  through `MeshStandardMaterial.onBeforeCompile`; build normal maps with a screen-space cotangent frame (no mesh
  tangents needed). Blender colours are linear; three.js works in linear: no conversion for tints, `SRGBColorSpace`
  only on base-colour textures.
- A first-person view glb hangs from a camera node (`Eye`): place it with `Rx(90deg) * inverse(Eye)` and drive the
  camera from the kick node for "Player's view" (horizontal FOV from the game, kept across aspect ratios).
- Clips baked on one Blender timeline: cut with `AnimationUtils.subclip(src, name, first, last + 1, fps)`; a looping
  clip of n frames lasts n frames.
- Multi-asset glbs (an environment set): one root node per piece, laid out apart in Blender; clone the node and
  zero its position. Fronts differ by convention: check which side a piece faces and point the camera there.
- Frame the camera with the smaller of the vertical and horizontal FOV, or models overflow phones.
- `MeshoptDecoder` + `gltf-transform meshopt` shrank 38 MB of glbs to 8 MB with no visual change.

## Trajectory
- Claude Code transcripts: `~/.claude/projects/<cwd-with-dashes>/<session>.jsonl` (+ a folder of subagent files).
  Typed prompts are `type: user` entries whose content is text (not tool_result); prompts typed mid-turn are
  `attachment` entries of type `queued_command` with `commandMode: prompt` and origin kind `human`; images may be
  inline base64. Drop `<system-reminder>` blocks, hook feedback and "[Request interrupted" markers.
- Large transcripts (400 MB) go to git split and xz-compressed by the owning session; reassemble and check
  `SHA256SUMS` before digesting.

## Hosting
- GitHub Pages from a prebuilt `gh-pages` branch avoids building Godot in CI and merging into main.
- `*.github.io`, Descript and similar hosts may be unreachable from the container: say so, and ask the user to check.
- Without the materials port, glbs that use vertex colours as data (wear masks, rest-pose encodings) render with
  rainbow vertex colours (seen on the gloves in the template test): that is the sign the port is needed.
