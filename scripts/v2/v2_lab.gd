extends Node3D
## V2 lab: three copies of the V2 room, one robot in each, to preview what was built in Blender (v2/): the room,
## the robots' clips, the two weapon views with their clips, the effects.
##   1 2 3 (or Tab) = go to a room · N = next clip of that room's robot · M = auto-cycle on / off
##   LMB fire · RMB aim · R reload · T reload from empty · F inspect · Q switch gun · Shift sprint · Space jump
##   godot --path . -- --v1          the V1 game / lab (scenes/main.tscn)
##   godot --path . -- --capture=DIR  save a tour of screenshots and quit
const KINDS := ["spider", "drone", "turret"]
const ROOM_DX := 40.0
const NO_COLLISION := ["Cable", "TrayCable", "Loop", "Bubbles", "CoveLights", "LightStrips", "CeilingLights", "Screens"]

var rooms: Array[Node3D] = []
var robots: Array[V2Robot] = []
var player: V2Player
var current := 0
var _hud: Label
var _quick := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--v1" in args:
		get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
		return
	V2Fx.root = self
	_environment()
	for i in KINDS.size():
		_room(i)
	player = V2Player.new()
	add_child(player)
	_hud_setup()
	goto(0)
	var capture := ""
	_quick = "--quick" in args
	for a in args:
		if a.begins_with("--capture="):
			capture = a.trim_prefix("--capture=")
	if capture != "":
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
	env.glow_enabled = true                         # the bloom of the Blender look
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
	# the room is lit by its ceiling panels in Blender; here by a grid of lights under them (x -4.6..6.4, z 3..-14)
	for z in [0.0, -5.5, -11.0]:
		for x in [-2.0, 3.8]:
			var l := OmniLight3D.new()
			l.position = Vector3(x, 4.5, z)
			l.light_color = Color(0.95, 0.97, 1.0)
			l.light_energy = 0.55
			l.omni_range = 11.0
			l.omni_attenuation = 0.8
			l.shadow_enabled = z == -5.5
			room.add_child(l)
	var robot := V2Robot.new()
	room.add_child(robot)
	robot.setup(KINDS[i])
	rooms.append(room)
	robots.append(robot)


func goto(i: int) -> void:
	current = posmod(i, rooms.size())
	for k in rooms.size():
		rooms[k].visible = k == current
		rooms[k].process_mode = Node.PROCESS_MODE_INHERIT if k == current else Node.PROCESS_MODE_DISABLED
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
	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.8)
	dot.size = Vector2(4, 4)
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.position -= Vector2(2, 2)
	layer.add_child(dot)


func _process(_delta: float) -> void:
	if _hud == null:
		return
	var r := robots[current]
	_hud.text = "V2 LAB   room %d / %d: %s   clip: %s%s   gun: %s\n1 2 3 rooms  ·  N next clip  ·  M auto-cycle  ·  LMB fire  ·  RMB aim  ·  R reload  ·  T reload (empty)  ·  F inspect  ·  Q switch gun  ·  Shift sprint  ·  Space jump" % [
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
