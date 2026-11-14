extends Node3D
## V2 lab: three copies of the V2 room side by side, joined by doorways, one robot in each, to preview what was built
## in Blender (v2/): the room, the robots' clips, the two weapon views with their clips, the effects.
##   walk through the doors, or 1 2 3 (Tab) = jump to a room · N = next clip of that room's robot · M = auto-cycle on / off
##   LMB fire · RMB aim · R reload · T reload from empty · F inspect · Q switch gun · Shift sprint · Space jump
##   godot --path . -- --v1          the V1 game / lab (scenes/main.tscn)
##   godot --path . -- --capture=DIR  save a tour of screenshots and quit
##   godot --path . -- --quality=low   no shadows, glow or MSAA (for a weak graphics card)
##   godot --path . -- --perf          print the performance line every second for 12 s and quit (F3 shows it in play)
##   godot --path . -- --input-test   send real mouse / key events and report what the player did (PASS / FAIL)
const KINDS := ["spider", "drone", "turret"]
const ROOM_DX := 11.6             # room width 11 + the two 0.3 m walls: neighbours share the doorway at Blender y = 10.2
# The doorway (Godot metres, room frame): through the right wall at x 6.4..6.7 and the next room's left wall
const DOOR_Z := -10.2
const DOOR_W := 1.3
const DOOR_H := 2.25
const XL := -4.6
const XR := 6.4
# Meshes that get no collision. The floor's (tiles, paint, drains) are replaced by one flat box per room: a capsule
# walking on the tile mesh snags on its edges (it stuck fast 13 cm from the right wall).
const NO_COLLISION := ["Cable", "TrayCable", "Loop", "Bubbles", "CoveLights", "LightStrips", "CeilingLights", "Screens",
	"FloorTiles", "FloorBase", "FloorPaint", "Drains"]

# Room meshes that cast no shadow: the shell and what hangs above the lights. The things standing in the room
# (mezzanine, stairs, railings, tanks, door frames) and the robots do.
const NO_SHADOW := ["Floor", "Wall", "Ceiling", "Trim", "Cable", "TrayCable", "Loop", "LightGrid", "Ducts", "Pipes",
	"CoveLights", "LightStrips", "Screens", "Signs", "StatusLights", "Drains", "Bubbles", "Hazard"]

var rooms: Array[Node3D] = []
var robots: Array[V2Robot] = []
var player: V2Player
var current := 0
var _hud: Label
var _shadow_lights: Array[OmniLight3D] = []
var _shadow_room := -1
var _low := false                 # --quality=low: no shadows, no glow, no MSAA
var _perf: Label                  # F3: frame rate and what the frame costs to draw
var _perf_log := false            # --perf: print that line every second, quit after 12 s
var _perf_t := 0.0
var _perf_frames := 0
var _perf_worst := 0.0
var _perf_line := ""
var _quick := false
var _door_only := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--v1" in args:
		get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
		return
	V2Fx.root = self
	_environment()
	for i in KINDS.size():
		_room(i)
	for i in KINDS.size() - 1:
		_door_lining(i)
	_door_frame(rooms[0], XL - 0.3, XL + 0.16, _layer(0))                         # the outer doorways lead nowhere:
	_door_frame(rooms[KINDS.size() - 1], XR - 0.16, XR + 0.3, _layer(KINDS.size() - 1))   # a frame with closed leaves
	_door_plug(0, XL + 0.1)
	_door_plug(KINDS.size() - 1, XR - 0.1)
	player = V2Player.new()
	add_child(player)
	_hud_setup()
	goto(0)
	var capture := ""
	_perf_log = "--perf" in args
	_low = "--quality=low" in args
	if _low:
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	_quick = "--quick" in args
	_door_only = "--doors" in args
	for a in args:
		if a.begins_with("--capture="):
			capture = a.trim_prefix("--capture=")
	if _perf_log:
		_perf.visible = true
		player.mouse_look = false
		get_tree().create_timer(12.0).timeout.connect(get_tree().quit)
	elif "--input-test" in args:
		_input_test()
	elif capture != "":
		_capture(capture)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.83, 0.92)
	env.ambient_light_energy = 0.32
	var sky := Sky.new()                            # only for reflections on the metal (CC0 HDRI, as in V1)
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = load("res://assets/sky/bank_vault_1k.hdr")
	sky.sky_material = pano
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.9
	env.glow_enabled = not _low                     # the bloom of the Blender look
	env.glow_intensity = 0.6
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true                          # its haze
	env.fog_light_color = Color(0.82, 0.86, 0.92)
	env.fog_density = 0.012
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _room(i: int) -> void:
	var room := Node3D.new()
	room.name = "Room_" + KINDS[i]
	room.position = Vector3(i * ROOM_DX, 0, 0)
	add_child(room)
	var shell: Node3D = (load(V2Assets.DIR + "room.glb") as PackedScene).instantiate()
	room.add_child(shell)
	V2Assets.apply(shell)
	for n in shell.find_children("*", "MeshInstance3D", true, false):
		var skip := false
		for prefix in NO_COLLISION:
			if String(n.name).begins_with(prefix):
				skip = true
		if not skip:
			(n as MeshInstance3D).create_trimesh_collision()
		for prefix in NO_SHADOW:
			if String(n.name).begins_with(prefix):
				(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var floor_body := StaticBody3D.new()               # the floor: one box, top at y = 0, out to the outer wall faces
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(XR - XL + 0.6, 1.0, 17.6)
	floor_shape.shape = floor_box
	floor_shape.position = Vector3((XL + XR) / 2.0, -0.5, -5.5)
	floor_body.add_child(floor_shape)
	room.add_child(floor_body)
	# the room is lit by its ceiling panels in Blender; here by a grid of lights under them (x -4.6..6.4, z 3..-14)
	for z in [0.0, -5.5, -11.0]:
		for x in [-2.0, 3.8]:
			var l := OmniLight3D.new()
			l.position = Vector3(x, 4.5, z)
			l.light_color = Color(0.95, 0.97, 1.0)
			l.light_energy = 0.55
			l.omni_range = 11.0
			l.omni_attenuation = 0.8
			l.light_cull_mask = _layer(i)
			room.add_child(l)
			if z == -5.5 and x > 0.0:                    # the one light per room that may cast shadows (see _shadows);
				# (the right-hand one: from the left, the drone's shadow falls on the wall outside the view)
				_shadow_lights.append(l)
	var robot := V2Robot.new()
	room.add_child(robot)
	robot.setup(KINDS[i])
	_set_layer(room, _layer(i))
	rooms.append(room)
	robots.append(robot)


## Each room is on its own render layer and its lights only reach that layer: with the rooms side by side, a room's
## big meshes would otherwise be in range of more than the 8 lights a mesh can have in the Compatibility renderer.
func _layer(i: int) -> int:
	return 1 << (i + 1)


func _set_layer(root: Node, layer: int) -> void:
	for n in root.find_children("*", "VisualInstance3D", true, false):
		if not (n is Light3D):
			(n as VisualInstance3D).layers = layer


func _box(parent: Node3D, from: Vector3, to: Vector3, mat: String, layer: int) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = (to - from).abs()
	mi.mesh = box
	mi.material_override = V2Assets.material(mat)
	mi.position = (from + to) / 2.0
	mi.layers = layer
	parent.add_child(mi)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = box.size
	shape.shape = bs
	body.add_child(shape)
	mi.add_child(body)


## A steel lining through a wall's doorway, x0..x1 (room frame): two jambs and a lintel. It stands a little proud
## of the wall as a door frame and covers the cut edges of the wall meshes.
func _door_frame(room: Node3D, x0: float, x1: float, layer: int) -> void:
	var z0 := DOOR_Z - DOOR_W / 2.0
	var z1 := DOOR_Z + DOOR_W / 2.0
	var t := 0.06
	_box(room, Vector3(x0, 0.0, z0 - 0.06), Vector3(x1, DOOR_H + 0.06, z0 + t), "DarkSteel", layer)
	_box(room, Vector3(x0, 0.0, z1 - t), Vector3(x1, DOOR_H + 0.06, z1 + 0.06), "DarkSteel", layer)
	_box(room, Vector3(x0, DOOR_H - t, z0), Vector3(x1, DOOR_H + 0.06, z1), "DarkSteel", layer)


## The passage from room i to room i + 1: one lining through both walls and a threshold plate for a floor.
func _door_lining(i: int) -> void:
	var layer := _layer(i) | _layer(i + 1)
	_door_frame(rooms[i], XR - 0.16, XR + 0.6 + 0.16, layer)
	_box(rooms[i], Vector3(XR - 0.02, -0.1, DOOR_Z - DOOR_W / 2.0), Vector3(XR + 0.62, 0.0, DOOR_Z + DOOR_W / 2.0), "Grating", layer)


## The outer doorways of the first and last room lead nowhere: a closed pair of leaves stands in them.
func _door_plug(i: int, x: float) -> void:
	for side in [-1.0, 1.0]:
		_box(rooms[i], Vector3(x - 0.03, 0.02, DOOR_Z + side * 0.006), Vector3(x + 0.03, DOOR_H, DOOR_Z + side * DOOR_W / 2.0),
			"Steel", _layer(i))


## Shadows are the expensive part of a frame: a shadow-casting omni light draws everything in its range again (six
## times, as a cube map; the cheaper dual-paraboloid mode drew no shadows at all here). Two such lights in each of
## the three rooms made a frame 7.8 million triangles and 1900 draw calls; one, in the room the player is in, is
## what the picture needs.
func _shadows(room: int) -> void:
	if room == _shadow_room:
		return
	_shadow_room = room
	for i in _shadow_lights.size():
		_shadow_lights[i].shadow_enabled = i == room and not _low


func _room_at(x: float) -> int:
	return clampi(int(floor((x - XL + 0.3) / ROOM_DX)), 0, rooms.size() - 1)


func goto(i: int) -> void:
	current = posmod(i, rooms.size())
	var eye: Array = V2Assets.data().camera.eye          # Blender (x, y, z) -> Godot (x, z, -y)
	player.global_position = rooms[current].position + Vector3(eye[0], 0.02, -eye[1])
	player.velocity = Vector3.ZERO
	player._yaw = 0.0
	player._pitch = deg_to_rad(-3.0)


func _hud_setup() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 15)
	_hud.add_theme_color_override("font_color", Color(0.8, 0.95, 1.0))
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hud.add_theme_constant_override("outline_size", 5)
	layer.add_child(_hud)
	_perf = Label.new()
	_perf.position = Vector2(16, 88)
	_perf.add_theme_font_size_override("font_size", 15)
	_perf.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	_perf.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_perf.add_theme_constant_override("outline_size", 5)
	_perf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_perf.visible = false
	layer.add_child(_perf)
	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.8)
	dot.size = Vector2(4, 4)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE   # (a ColorRect stops the mouse by default, and the captured cursor
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE  # sits right on it: it swallowed every look and click)
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.position -= Vector2(2, 2)
	layer.add_child(dot)


## Once a second: average frame rate, the slowest frame of that second, and the renderer's counts for the last frame
## (draw calls, triangles and objects do not depend on the graphics card; the frame rate does).
func _perf_update(delta: float) -> void:
	_perf_t += delta
	_perf_frames += 1
	_perf_worst = maxf(_perf_worst, delta)
	if _perf_t < 1.0:
		return
	_perf_line = "%.0f fps (avg %.1f ms, worst %.1f ms)   draw calls %d   triangles %dk   objects %d   video memory %.0f MB   %dx%d   %s" % [
		_perf_frames / _perf_t, 1000.0 * _perf_t / _perf_frames, 1000.0 * _perf_worst,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y,
		RenderingServer.get_video_adapter_name()]
	_perf.text = _perf_line + "\nF3 hides this"
	if _perf_log:
		print("[perf] room %d  " % (current + 1), _perf_line)
	_perf_t = 0.0
	_perf_frames = 0
	_perf_worst = 0.0


func _process(delta: float) -> void:
	if _hud == null:
		return
	if _perf.visible:
		_perf_update(delta)
	current = _room_at(player.global_position.x)
	player.set_layer(_layer(current))                # the gun is lit by the lights of the room it is in
	_shadows(current)
	var r := robots[current]
	_hud.text = "V2 LAB   room %d / %d: %s   clip: %s%s   gun: %s\nwalk through the doors or 1 2 3  ·  N next clip  ·  M auto-cycle  ·  F3 performance\nLMB fire  ·  RMB aim  ·  R reload  ·  T reload (empty)  ·  F inspect  ·  Q switch gun  ·  Shift sprint  ·  Space jump" % [
		current + 1, rooms.size(), r.kind.to_upper(), r.clip, "" if r.auto else " (held)", player.weapon]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				goto(0)
			KEY_2:
				goto(1)
			KEY_3:
				goto(2)
			KEY_TAB:
				goto(current + 1)
			KEY_N:
				robots[current].next()
			KEY_M:
				robots[current].auto = not robots[current].auto
			KEY_F3:
				_perf.visible = not _perf.visible
				_perf_t = 0.0
				_perf_frames = 0
				_perf_worst = 0.0
				_perf.text = "measuring ..."


# ---------------------------------------------------------------- input check (--input-test)
## Sends real input events through the viewport (as the mouse and keyboard would) and reports what the player did
## with them: PASS / FAIL lines, then quits. The capture tour drives the player by code and cannot catch a control
## that swallows the mouse.
func _input_test() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await _wait(0.5)
	var centre := Vector2(get_viewport().get_visible_rect().size / 2.0)
	var yaw0 := player._yaw
	var pitch0 := player._pitch
	for k in 5:
		var mm := InputEventMouseMotion.new()
		mm.position = centre
		mm.global_position = centre
		mm.relative = Vector2(40, 12)
		Input.parse_input_event(mm)
		await get_tree().process_frame
	await get_tree().process_frame
	print("[input] mouse mode captured: ", Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
	print("[input] look: ", "PASS" if absf(player._yaw - yaw0) > 0.1 and absf(player._pitch - pitch0) > 0.02 else "FAIL",
		" (yaw %.3f -> %.3f, pitch %.3f -> %.3f)" % [yaw0, player._yaw, pitch0, player._pitch])
	for spec in [[MOUSE_BUTTON_LEFT, "Fire"], [MOUSE_BUTTON_RIGHT, "ADS"]]:
		player.busy = ""
		var mb := InputEventMouseButton.new()
		mb.position = centre
		mb.global_position = centre
		mb.button_index = spec[0]
		mb.pressed = true
		Input.parse_input_event(mb)
		await get_tree().process_frame
		await get_tree().process_frame
		print("[input] ", spec[1], ": ", "PASS" if player.busy == spec[1] else "FAIL", " (busy = '", player.busy, "')")
		var up := mb.duplicate() as InputEventMouseButton
		up.pressed = false
		Input.parse_input_event(up)
		await _wait(0.3)
	for spec in [[KEY_R, "Reload"], [KEY_F, "Inspect"]]:
		player.busy = ""
		var ke := InputEventKey.new()
		ke.keycode = spec[0]
		ke.physical_keycode = spec[0]
		ke.pressed = true
		Input.parse_input_event(ke)
		await get_tree().process_frame
		await get_tree().process_frame
		print("[input] key ", spec[1], ": ", "PASS" if player.busy == spec[1] else "FAIL", " (busy = '", player.busy, "')")
	get_tree().quit()


# ---------------------------------------------------------------- screenshots (--capture=DIR)
func _shot(dir: String, shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(shot_name + ".png"))
	print("[capture] ", shot_name)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _until(cond: Callable, timeout: float = 4.0) -> void:
	var t := 0.0
	while not cond.call() and t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()


func _capture(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	player.mouse_look = false
	V2Fx.hold = 40.0
	for r in robots:
		r.auto = false
	for i in rooms.size():
		if _door_only:
			break
		goto(i)
		await _wait(0.6)
		await _shot(dir, "room%d_%s" % [i + 1, KINDS[i]])
		robots[i].play("Shoot")
		robots[i].ap.speed_scale = 0.08               # (a flash lasts two frames: slow down to catch it, then hold it)
		robots[i]._left = 999.0                       # (and keep the preview loop from restarting the clip meanwhile)
		await _until(robots[i].flash_on, 12.0)
		robots[i].ap.pause()
		await _shot(dir, "room%d_%s_shoot" % [i + 1, KINDS[i]])
		robots[i].ap.speed_scale = 1.0
		if _quick:
			continue
		robots[i].play(V2Robot.ORDER[KINDS[i]][2])
		await _wait(1.0)
		await _shot(dir, "room%d_%s_move" % [i + 1, KINDS[i]])
		robots[i].hit()
		for k in 3:
			await _wait(1.0)
			await _shot(dir, "room%d_%s_death%d" % [i + 1, KINDS[i], k + 1])
	goto(0)
	robots[0].play("Walk")
	await _wait(0.5)
	# the doorways: look at the first, walk through each (0.25 m off centre: clear of the stair post beyond), look back
	player.global_position = rooms[0].position + Vector3(3.4, 0.02, DOOR_Z + 1.3)
	player._yaw = deg_to_rad(-65.0)
	await _wait(0.4)
	await _shot(dir, "door_from_room1")
	for i in rooms.size() - 1:
		player.global_position = rooms[i].position + Vector3(4.6, 0.02, DOOR_Z - 0.25)
		player._yaw = deg_to_rad(-90.0)
		player.auto_move = Vector3(0, 0, -1)
		var goal := rooms[i + 1].position.x - 1.6     # past the wall, the frame and the post, under the landing
		await _until(func() -> bool: return player.global_position.x > goal, 60.0)
		player.auto_move = Vector3.ZERO
		print("[walk] door %d -> %d: x=%.2f, goal %.2f, now in room %d" % [i + 1, i + 2, player.global_position.x, goal,
			_room_at(player.global_position.x) + 1])
		player._yaw = deg_to_rad(-35.0)
		await _wait(0.3)
		await _shot(dir, "door_into_room%d" % (i + 2))
	player._yaw = deg_to_rad(90.0)
	await _wait(0.3)
	await _shot(dir, "door_back_to_room2")
	goto(0)
	player._yaw = deg_to_rad(75.0)
	player.global_position = rooms[0].position + Vector3(-2.2, 0.02, DOOR_Z + 0.5)
	await _wait(0.3)
	await _shot(dir, "room1_closed_end_door")
	if _door_only:
		get_tree().quit()
		return
	goto(0)
	await _wait(0.3)
	for w in 2:
		player.busy = ""
		player.act("Fire")
		player._ap().speed_scale = 0.08
		await _until(player.flash_on, 12.0)
		player._ap().pause()
		await _shot(dir, player.weapon + "_fire")
		player._ap().speed_scale = 1.0
		player._ap().play()
		if _quick:
			break
		await _wait(1.3)
		player.busy = ""
		player.act("Reload" if player.weapon == "pistol" else "ReloadEmpty")
		await _wait(0.75)
		await _shot(dir, player.weapon + "_reload")
		await _wait(1.6)
		player.busy = ""
		player.act("Inspect")
		await _wait(1.0)
		await _shot(dir, player.weapon + "_inspect")
		player.busy = ""
		player.act("ADS")
		await _wait(0.6)
		await _shot(dir, player.weapon + "_ads")
		player.busy = ""
		if w == 0:
			player.switch_weapon()
			await _wait(1.6)
			await _shot(dir, "rifle_hold")
	get_tree().quit()
