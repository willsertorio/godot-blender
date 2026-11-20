extends Node
## The watch on the 3D picture (the game adds one).
##
## **Why:** in the user's browser (Chrome on an M1) the world and the gun stop being drawn at some moment of a
## run, at a different spot every time: the HUD goes on, the engine runs at 60 fps, the camera's numbers are sane,
## the console shows no error, and the engine reports a handful of draw calls. It was never reproduced here
## (SwiftShader, llvmpipe), so guessing at it cost the user three site rebuilds. This node does not guess: it
## notices the moment the engine finds nothing to draw in 3D, writes down everything about the view at that
## moment (console, and a short line on the screen), and then tries the ways of getting the picture back one
## after another, least intrusive first, noting which one worked. Whatever it reports names the cause's kind.
##
## Not for headless runs (nothing is drawn there, so it never arms).

var game: Node3D                       # V2Game
var label: Label                       # the line on the screen (the game puts it under the room panel)

const LOST_FRAMES := 20                # this many frames in a row with nothing found in 3D = lost
const TRY_FRAMES := 12                 # frames given to a remedy before it is judged
const REMEDIES := ["cameras", "buffers", "shadows", "show", "retree", "camera node"]

var _armed := false                    # the engine has drawn the world at least once
var _empty := 0                        # frames in a row with nothing found
var _incident := 0
var _step := -1                        # the remedy being tried (-1: none)
var _wait := 0
var _tried: Array[String] = []
var _suns: Array[DirectionalLight3D] = []
var _t0 := 0
var report: Array[String] = []         # what was written (the checks read it)
var recovered_by := ""
var force_loss := ""                   # a test's way of losing the view ("hide", "camera", ...): see lose()


func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	process_priority = 1000            # (after everything else has moved)


func found() -> int:
	return RenderingServer.viewport_get_render_info(game.get_viewport().get_viewport_rid(),
		RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)


func drawn() -> int:
	return RenderingServer.viewport_get_render_info(game.get_viewport().get_viewport_rid(),
		RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)


func _process(_delta: float) -> void:
	if game == null or game.get("player") == null or game.player == null:
		return
	var n := found()
	var d := drawn()
	if not _armed:
		_armed = n > 20 and d > 20
		return
	var lost := n == 0 or d == 0
	if _step >= 0:                                         # a remedy is on trial
		_wait -= 1
		if _wait > 0:
			return
		if not lost:
			recovered_by = REMEDIES[_step]
			_say("3D view lost %d time%s; brought back by: %s  (tried: %s)" % [_incident, "" if _incident == 1 else "s", recovered_by, ", ".join(_tried)])
			_step = -1
			_empty = 0
			return
		if REMEDIES[_step] == "shadows":                    # (it did not help: the shadows come back)
			for sun: DirectionalLight3D in _suns:
				if is_instance_valid(sun):
					sun.shadow_enabled = true
		_step += 1
		if _step >= REMEDIES.size():
			_say("3D view lost; NOT brought back  (tried: %s)" % ", ".join(_tried))
			_step = -1
			_armed = false                                 # (it arms again if the picture returns by itself)
			return
		_apply(REMEDIES[_step])
		return
	if not lost:
		_empty = 0
		return
	_empty += 1
	if _empty < LOST_FRAMES:
		return
	_incident += 1
	_tried.clear()
	_snapshot(n, d)
	_step = 0
	_apply(REMEDIES[0])


func _say(text: String) -> void:
	report.append(text)
	print("[view-watch] " + text)
	if label != null:
		label.text = text
		label.visible = true


func _fin(v: Variant) -> bool:
	if v is Transform3D:
		return (v as Transform3D).origin.is_finite() and (v as Transform3D).basis.x.is_finite() and (v as Transform3D).basis.y.is_finite() and (v as Transform3D).basis.z.is_finite()
	if v is Vector3:
		return (v as Vector3).is_finite()
	return is_finite(float(v))


## Everything about the view at the moment it was lost.
func _snapshot(n: int, d: int) -> void:
	var vp := game.get_viewport()
	var rid := vp.get_viewport_rid()
	var player: Node3D = game.player
	var cam: Camera3D = player.cam
	var view_cam: Camera3D = player.view_cam
	var lines: Array[String] = []
	lines.append("LOST at %.1f s (incident %d): 3D found %d drawn %d, shadows found %d drawn %d, all draw calls %d" % [
		(Time.get_ticks_msec() - _t0) / 1000.0, _incident, n, d,
		RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
		RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))])
	lines.append("viewport: size %s  window %s  3D scale %.4f  msaa %d  disable_3d %s  own world %s  world %s  camera's world %s  viewport's camera is the player's %s" % [
		vp.size, game.get_window().size, vp.scaling_3d_scale, vp.msaa_3d, vp.disable_3d, vp.own_world_3d,
		vp.find_world_3d().get_rid() if vp.find_world_3d() != null else RID(), cam.get_world_3d().get_rid() if cam.is_inside_tree() else RID(),
		vp.get_camera_3d() == cam])
	lines.append("camera: in tree %s  current %s  fov %.2f  near %.3f  far %.1f  keep %d  mask %x  h/v offset %.3f %.3f  transform %s  finite %s  projection %s" % [
		cam.is_inside_tree(), cam.current, cam.fov, cam.near, cam.far, cam.keep_aspect, cam.cull_mask, cam.h_offset, cam.v_offset,
		cam.global_transform, _fin(cam.global_transform), cam.get_camera_projection()])
	lines.append("gun camera: in tree %s  current %s  fov %.2f  mask %x  viewport size %s  transform finite %s" % [
		view_cam.is_inside_tree(), view_cam.current, view_cam.fov, view_cam.cull_mask,
		view_cam.get_viewport().size if view_cam.is_inside_tree() else Vector2i.ZERO, _fin(view_cam.global_transform)])
	lines.append("player: at %s  in tree %s  visible in tree %s  game visible %s  dungeon visible %s  state %s  here %s" % [
		player.global_position, player.is_inside_tree(), player.is_visible_in_tree(), game.visible,
		(game.dungeon as Node3D).is_visible_in_tree() if game.get("dungeon") != null else false, game.get("state"), game.get("here")])
	# every 3D thing in the scene: how many are there, how many may be drawn, which are not where a number can say
	var all := 0
	var shown := 0
	var bad: Array[String] = []
	var lights := 0
	var suns := 0
	var stack: Array[Node] = [game]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for c in node.get_children():
			stack.append(c)
		if node is Node3D:
			var n3 := node as Node3D
			if not _fin(n3.global_transform) and bad.size() < 12:
				bad.append("%s %s" % [n3.get_path(), n3.global_transform])
			if node is VisualInstance3D:
				all += 1
				if n3.is_visible_in_tree():
					shown += 1
				if node is Light3D and n3.is_visible_in_tree():
					lights += 1
					if node is DirectionalLight3D:
						suns += 1
						var s := node as DirectionalLight3D
						lines.append("sun: shadows %s  mode %d  max distance %.1f  energy %.2f  transform finite %s  basis %s" % [
							s.shadow_enabled, s.directional_shadow_mode, s.directional_shadow_max_distance, s.light_energy, _fin(s.global_transform), s.global_basis])
	lines.append("scene: %d things to draw, %d visible in tree, %d lights on (%d directional)  nodes %d" % [all, shown, lights, suns, game.get_tree().get_node_count()])
	lines.append("not finite: %s" % ("none" if bad.is_empty() else "  ".join(bad)))
	var log: Array = V2Sfx.log
	lines.append("last sounds: %s" % " ".join(log.slice(maxi(log.size() - 16, 0))))
	if OS.has_feature("web"):
		var js := "(function(){try{var c=document.querySelector('canvas');var g=c.getContext('webgl2');return 'canvas '+c.width+'x'+c.height+' css '+c.clientWidth+'x'+c.clientHeight+' dpr '+window.devicePixelRatio+' contextLost '+(g?g.isContextLost():'no context')+' glError '+(g?g.getError():'-')+' visibility '+document.visibilityState+' fullscreen '+(document.fullscreenElement?1:0)+' lock '+(document.pointerLockElement?1:0);}catch(e){return 'js: '+e;}})()"
		lines.append("browser: %s" % str(JavaScriptBridge.eval(js, true)))
	lines.append("renderer: %s | %s | %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version(), OS.get_name()])
	for l in lines:
		report.append(l)
		print("[view-watch] " + l)
	if label != null:
		label.text = "3D view lost: looking for the way back..."
		label.visible = true


## One way of getting the picture back. Each is left in force if it works (and is named on the screen).
func _apply(what: String) -> void:
	_tried.append(what)
	_wait = TRY_FRAMES
	var vp := game.get_viewport()
	var player: Node3D = game.player
	var cam: Camera3D = player.cam
	var view_cam: Camera3D = player.view_cam
	print("[view-watch] trying: " + what)
	match what:
		"cameras":                                         # the viewports take their cameras afresh
			cam.clear_current(false)
			cam.make_current()
			view_cam.clear_current(false)
			view_cam.make_current()
		"buffers":                                         # the 3D picture's buffers are made anew
			var msaa := vp.msaa_3d
			var k := vp.scaling_3d_scale
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.scaling_3d_scale = 0.99 if k >= 0.995 else 1.0
			await get_tree().process_frame
			await get_tree().process_frame
			vp.msaa_3d = msaa
			vp.scaling_3d_scale = k
		"shadows":                                         # the one light that casts shadows casts none
			_suns.clear()
			for n in game.find_children("*", "DirectionalLight3D", true, false):
				if (n as DirectionalLight3D).shadow_enabled:
					_suns.append(n)
					(n as DirectionalLight3D).shadow_enabled = false
		"show":                                            # everything is taken out of the renderer's lists and put back
			game.visible = false
			await get_tree().process_frame
			game.visible = true
		"retree":                                          # the dungeon leaves the scene and enters it again
			var dungeon: Node = game.get("dungeon")
			if dungeon != null and dungeon.get_parent() != null:
				var parent := dungeon.get_parent()
				var at := dungeon.get_index()
				parent.remove_child(dungeon)
				await get_tree().process_frame
				parent.add_child(dungeon)
				parent.move_child(dungeon, at)
		"camera node":                                     # the world's camera leaves the scene and enters it again
			var parent := cam.get_parent()
			if parent != null:
				var at := cam.get_index()
				parent.remove_child(cam)
				parent.add_child(cam)
				parent.move_child(cam, at)
				cam.make_current()


## For the checks: lose the view on purpose, one way or another.
func lose(how: String) -> void:
	match how:
		"hide":
			game.visible = false
		"camera":
			(game.player.cam as Camera3D).clear_current(false)
		"dungeon":
			(game.dungeon as Node3D).visible = false
