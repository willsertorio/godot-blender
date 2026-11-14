extends Node3D
## V2 lab: three copies of the V2 room side by side, joined by doorways, one robot in each, to preview what was built
## in Blender (v2/): the room, the robots' clips, the two weapon views with their clips, the effects.
##   walk through the doors, or 1 2 3 (Tab) = jump to a room · N = next clip of that room's robot · M = auto-cycle on / off
##   LMB fire · RMB aim · R reload · T reload from empty · F inspect · Q switch gun · Shift sprint · Space jump
##   godot --path . -- --v1          the V1 game / lab (scenes/main.tscn)
##   godot --path . -- --capture=DIR  save a tour of screenshots and quit
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

var rooms: Array[Node3D] = []
var robots: Array[V2Robot] = []
var player: V2Player
var current := 0
var _hud: Label
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
	_quick = "--quick" in args
	_door_only = "--doors" in args
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
			l.shadow_enabled = z == -5.5
			l.light_cull_mask = _layer(i)
			room.add_child(l)
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
	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.8)
	dot.size = Vector2(4, 4)
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.position -= Vector2(2, 2)
	layer.add_child(dot)


func _process(_delta: float) -> void:
	if _hud == null:
		return
	current = _room_at(player.global_position.x)
	player.set_layer(_layer(current))                # the gun is lit by the lights of the room it is in
	var r := robots[current]
	_hud.text = "V2 LAB   room %d / %d: %s   clip: %s%s   gun: %s\nwalk through the doors or 1 2 3  ·  N next clip  ·  M auto-cycle  ·  LMB fire  ·  RMB aim  ·  R reload  ·  T reload (empty)  ·  F inspect  ·  Q switch gun  ·  Shift sprint  ·  Space jump" % [
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
