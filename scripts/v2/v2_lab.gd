extends Node3D
## V2 lab: three copies of the V2 room side by side, joined by doorways, one robot in each, built from what was made
## in Blender (v2/): the room, the robots and their clips, the two weapon views with their clips.
## The robots are enemies (v2_robot.gd): they move, shoot at the player and can be destroyed; they come back.
##   walk through the doors, or 1 2 3 (Tab) = jump to a room
##   M = that room's robot: enemy <-> clip preview (cycles its clips where it stands in Blender) · N = next clip
##   LMB fire · C / RMB aim · R reload · T reload from empty · F inspect · Q switch gun · Shift sprint  ·  X crouch · Space jump
##   godot --path . -- --v1          the V1 game / lab (scenes/main.tscn)
##   godot --path . -- --capture=DIR  save a tour of screenshots and quit
##   godot --path . -- --quality=low   no shadows, glow or MSAA (for a weak graphics card)
##   godot --path . -- --perf          print the performance line every second for 12 s and quit (F3 shows it in play)
##   godot --path . -- --preview       start with the robots in clip preview
##   godot --headless --path . -- --enemy-test   plays each room by code and prints PASS / FAIL (moves, shoots, dies, returns)
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
	"FloorTiles", "FloorBase", "FloorPaint", "Drains", "StudioFloor", "StudioLight", "StudioTrim"]

# Room meshes that cast no shadow: the shell and what hangs above the lights. The things standing in the room
# (mezzanine, stairs, railings, tanks, door frames) and the robots do.
const NO_SHADOW := ["Floor", "Wall", "Ceiling", "Trim", "Cable", "TrayCable", "Loop", "LightGrid", "Ducts", "Pipes",
	"CoveLights", "LightStrips", "Screens", "Signs", "StatusLights", "Drains", "Bubbles", "Hazard",
	"StudioFloor", "StudioWalls", "StudioCeiling", "StudioLight", "StudioTrim"]

var rooms: Array[Node3D] = []
var robots: Array[V2Robot] = []
var player: V2Player
var current := 0
var _hud: Label
var _health_fill: ColorRect
var _health_text: Label
var _enemy_fill: ColorRect
var _enemy_text: Label
var _flash: ColorRect
var _dot: ColorRect
var _down_text: Label
var _down_t := 0.0
var downs := 0
var _only := ""
var _low := false                 # --quality=low: no shadows, no glow, no MSAA
var _perf: Label                  # F3: frame rate and what the frame costs to draw
var _perf_log := false            # --perf: print that line every second, quit after 12 s
var _perf_t := 0.0
var _perf_frames := 0
var _perf_worst := 0.0
var _perf_line := ""
var _quick := false
var _door_only := false
var _room_lights: Array = []        # per room: its omni and spot lights
var _gun_room := -1
var _concept := false             # --concept: the detailed room of the Blender scene instead of the studio


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--v1" in args:
		get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
		return
	V2Fx.root = self
	V2Sfx.root = self
	V2Sfx.enabled = not ("--no-sound" in args)
	_low = "--quality=low" in args                 # (before the environment is built: it reads this)
	_concept = "--concept" in args
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
	player.died.connect(_on_player_died)
	for r in robots:
		r.player = player
		if "--preview" in args:
			r.set_ai(false)
	_hud_setup()
	goto(0)
	var capture := ""
	_perf_log = "--perf" in args
	if _low:
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	_quick = "--quick" in args
	_door_only = "--doors" in args
	for a in args:
		if a.begins_with("--capture="):
			capture = a.trim_prefix("--capture=")
		if a.begins_with("--only="):
			_only = a.trim_prefix("--only=")
	if _perf_log:
		_perf.visible = true
		player.mouse_look = false
		get_tree().create_timer(12.0).timeout.connect(get_tree().quit)
	elif "--enemy-test" in args:
		_enemy_test()
	elif "--gun-test" in args:
		_gun_test()
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
	env.ambient_light_color = Color(0.88, 0.92, 0.95)
	env.ambient_light_energy = 0.16
	var sky := Sky.new()                            # only for reflections on the metal (CC0 HDRI, as in V1)
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = load("res://assets/sky/bank_vault_1k.hdr")
	sky.sky_material = pano
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.15 if _low else 0.9    # (low quality has no glow and no shadow pass: both add light,
	#                                                 so it is exposed up and its floor light is stronger, to look the same)
	env.glow_enabled = not _low                     # the bloom of the Blender look
	env.glow_intensity = 0.6
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true                          # its haze
	env.fog_light_color = Color(0.82, 0.86, 0.92)
	env.fog_density = 0.0035                        # (thin: at 0.012 it lifted every dark surface across the room to mid grey)
	V2Player.world_env = env
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# The Blender room is lit by its ceiling panels: the floor and the tops of things are bright, the walls less so.
	# Lights hung under the ceiling alone light the walls most. So half of the light comes straight down
	# (no shadows: it is the soft light of a whole luminous ceiling), reaching every room's layer and the gun's.
	var down := DirectionalLight3D.new()
	down.rotation_degrees = Vector3(-84.0, 20.0, 0.0)
	down.light_color = Color(0.98, 0.99, 1.0)
	down.light_energy = 0.5 if _low else 0.32
	# Its shadows fall straight down: the pools under the robots, the stairs and the mezzanine. They are the only
	# shadows: one flat pass over the three rooms (the shell casts none). A shadow-casting omni light draws
	# everything in its range six times (a cube; the dual-paraboloid mode drew nothing here): two of those per room
	# once made a frame 7.8 million triangles and 1900 draw calls.
	# (measured: with shadows on, this light comes out about half as bright again as without, hence 0.32)
	down.shadow_enabled = not _low
	down.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	down.directional_shadow_max_distance = 34.0
	down.shadow_blur = 2.2
	down.shadow_bias = 0.06
	down.shadow_normal_bias = 1.5
	add_child(down)


func _room(i: int) -> void:
	var room := Node3D.new()
	room.name = "Room_" + KINDS[i]
	room.position = Vector3(i * ROOM_DX, 0, 0)
	add_child(room)
	# The lab's rooms are a plain studio (v2/scripts/build_studio.py), the size of the concept room and with the
	# same doorways. The concept room itself (room.glb, from scene.blend) is kept for the real game: --concept.
	var shell: Node3D = (load(V2Assets.DIR + ("room.glb" if _concept else "studio.glb")) as PackedScene).instantiate()
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
	var lights: Array = []
	_room_lights.append(lights)
	for z in [0.0, -5.5, -11.0]:
		for x in [-2.0, 3.8]:
			var l := OmniLight3D.new()
			l.position = Vector3(x, 4.5, z)
			l.light_color = Color(0.97, 0.98, 1.0)
			l.light_energy = 0.27
			l.omni_range = 11.0
			l.omni_attenuation = 0.8
			l.light_cull_mask = _layer(i)
			room.add_child(l)
			lights.append(l)
	# under the mezzanine the ceiling's light does not reach: its own strip lights there are two spot lights
	# (spots, not omnis: a mesh takes 8 of each kind, and the six above, the gun's and a muzzle flash make 8 omnis)
	for x in ([-2.4, 4.0] if _concept else []):
		var sp := SpotLight3D.new()
		sp.position = Vector3(x, 2.3, -11.4)
		sp.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		sp.spot_angle = 72.0
		sp.spot_angle_attenuation = 0.6
		sp.spot_range = 6.0
		sp.spot_attenuation = 0.7
		sp.light_color = Color(0.97, 0.98, 1.0)
		sp.light_energy = 0.7
		sp.light_cull_mask = _layer(i)
		room.add_child(sp)
		lights.append(sp)
	if not _concept:                                   # the room's number and tenant on the far wall
		var plate := Label3D.new()
		plate.text = "%02d  %s" % [i + 1, KINDS[i].to_upper()]
		plate.font_size = 160
		plate.pixel_size = 0.004
		plate.modulate = Color(0.2, 0.22, 0.25)
		plate.outline_size = 0
		plate.position = Vector3((XL + XR) / 2.0, 3.6, -13.985)
		room.add_child(plate)
	var robot := V2Robot.new()
	room.add_child(robot)
	robot.setup(KINDS[i])
	_set_layer(room, _layer(i))
	rooms.append(room)
	robots.append(robot)


## The gun and arms are on a layer of their own (V2Player.GUN_LAYER); the lights of the room the player stands in
## reach it, the other rooms' do not.
func _gun_lights(room: int) -> void:
	if room == _gun_room:
		return
	_gun_room = room
	for i in _room_lights.size():
		for l in _room_lights[i]:
			(l as Light3D).light_cull_mask = _layer(i) | (V2Player.GUN_LAYER if i == room else 0)


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
	layer.layer = 5                                    # over the gun's picture (the player's overlay is layer 1)
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
	# (every control ignores the mouse: a ColorRect stops it by default, and the captured cursor sits on the dot)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash = _rect(layer, Color(0.75, 0.04, 0.02, 0.0))          # red wash when hit
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dot = _rect(layer, Color(1, 1, 1, 0.8))
	_dot.set_anchors_preset(Control.PRESET_CENTER)
	_bar_place(_dot, 0.5, 0.5, -2, -2, 4, 4)
	_bar_place(_rect(layer, Color(0, 0, 0, 0.55)), 0.0, 1.0, 14, -38, 224, 18)      # health, bottom left
	_health_fill = _rect(layer, Color(0.3, 0.9, 0.5))
	_health_text = _text(layer, 0.0, 1.0, 16, -62)
	_bar_place(_rect(layer, Color(0, 0, 0, 0.55)), 0.5, 1.0, -162, -38, 324, 18)    # the room's robot, bottom centre
	_enemy_fill = _rect(layer, Color(1.0, 0.35, 0.2))
	_enemy_text = _text(layer, 0.5, 1.0, -160, -62)
	_down_text = _text(layer, 0.5, 0.5, -150, 30)
	_down_text.text = "DOWN  -  back to the start of the room"
	_down_text.visible = false


func _rect(layer: CanvasLayer, color: Color) -> ColorRect:
	var c := ColorRect.new()
	c.color = color
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(c)
	return c


func _bar_place(c: Control, ax: float, ay: float, x: float, y: float, w: float, h: float) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = x
	c.offset_top = y
	c.offset_right = x + w
	c.offset_bottom = y + h


func _text(layer: CanvasLayer, ax: float, ay: float, x: float, y: float) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.9, 0.97, 1.0))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(l)
	_bar_place(l, ax, ay, x, y, 320, 20)
	return l


func _on_player_died() -> void:
	downs += 1
	_down_t = 1.4


func _hud_update(delta: float) -> void:
	var r := robots[current]
	var preview := r.state == V2Robot.PREVIEW
	_hud.text = "V2 LAB   room %d / %d: %s (%s)   gun: %s   destroyed: %d   downs: %d\nwalk through the doors or 1 2 3  ·  M enemy / clip preview  ·  N next clip  ·  F3 performance\nLMB fire  ·  C / RMB aim  ·  R reload  ·  T reload (empty)  ·  F inspect  ·  Q switch gun  ·  Shift sprint  ·  X crouch  ·  Space jump" % [
		current + 1, rooms.size(), r.kind.to_upper(), ("preview: " + r.clip + ("" if r.auto else ", held")) if preview else "enemy",
		player.weapon, robots.reduce(func(n: int, x: V2Robot) -> int: return n + x.kills, 0), downs]
	var h := player.hp / V2Player.MAX_HP
	_bar_place(_health_fill, 0.0, 1.0, 16, -36, 220.0 * h, 14)
	_health_fill.color = Color(0.3, 0.9, 0.5).lerp(Color(1.0, 0.25, 0.15), 1.0 - h)
	_health_text.text = "HEALTH  %d" % ceili(player.hp)
	_bar_place(_enemy_fill, 0.5, 1.0, -160, -36, 320.0 * r.hp / r.max_hp, 14)
	_enemy_fill.visible = not preview
	_enemy_text.text = r.kind.to_upper() + ("" if preview else ("   destroyed, back soon" if r.state == V2Robot.DEAD else ""))
	_flash.color.a = clampf(player.hurt_flash * 0.3 + (0.25 if player.down else 0.0) + maxf(0.3 - h, 0.0) * 0.4, 0.0, 0.6)
	var hit := player.hit_confirm > 0.0
	# the cursor: where the next round goes (the middle of the screen for the pistol; the machine gun's rides on
	# its barrel and climbs with the recoil); hidden while the gun is busy with something else
	_dot.color = Color(1.0, 0.3, 0.2, 1.0) if hit else Color(1, 1, 1, 0.85)
	_dot.visible = player.aim_dot.x >= 0.0
	var half := 4.0 if hit else 2.5
	_bar_place(_dot, 0.0, 0.0, player.aim_dot.x - half, player.aim_dot.y - half, half * 2.0, half * 2.0)
	_down_text.visible = player.down
	if player.down:
		_down_t -= delta
		if _down_t <= 0.0:
			goto(current)
			player.revive()


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
	_gun_lights(current)                             # the gun is lit by the lights of the room it is in
	for k in robots.size():
		robots[k].active = k == current
	_hud_update(delta)


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
				robots[current].set_ai(robots[current].state == V2Robot.PREVIEW)
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
func _press(button: int, pressed: bool) -> void:
	var mb := InputEventMouseButton.new()
	mb.position = Vector2(get_viewport().get_visible_rect().size / 2.0)
	mb.global_position = mb.position
	mb.button_index = button
	mb.pressed = pressed
	Input.parse_input_event(mb)


func _key(code: int, pressed: bool) -> void:
	var k := InputEventKey.new()
	k.keycode = code
	k.physical_keycode = code
	k.pressed = pressed
	Input.parse_input_event(k)


## --gun-test (under xvfb, with real events): the machine gun must fire without a break for as long as the button
## is held and stop when it is let go; its rounds must leave along the barrel and the cursor must ride on it (in
## the middle at rest, climbing in fire); fire while aiming; a sprint must end when the player stops.
func _gun_test() -> void:
	for r in robots:
		r.set_ai(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.invulnerable = true
	var ok := true
	var centre := Vector2(get_viewport().get_visible_rect().size / 2.0)
	await _wait(0.5)
	player.switch_weapon()                             # the machine gun
	await _until(func() -> bool: return player.busy == "", 4.0)
	await _wait(0.4)
	var rest_off := player.aim_dot.distance_to(centre)
	var a := rest_off < 14.0
	ok = ok and a
	print("[gun] cursor at rest in the middle of the screen: ", "PASS" if a else "FAIL", " (%.1f px off)" % rest_off)
	# hold the trigger for 2.5 s
	player.shot_times.clear()
	player.worst_bend = 0.0
	var highest := centre.y
	_press(MOUSE_BUTTON_LEFT, true)
	var t := 0.0
	while t < 2.5:
		await get_tree().process_frame
		t += get_process_delta_time()
		if player.aim_dot.x >= 0.0:
			highest = minf(highest, player.aim_dot.y)
	var n_held := player.shot_times.size()
	var gap := 0.0
	for i in range(1, n_held):
		gap = maxf(gap, player.shot_times[i] - player.shot_times[i - 1])
	_press(MOUSE_BUTTON_LEFT, false)
	var t_stop := 0.0
	while player.busy != "" and t_stop < 2.0:
		await get_tree().process_frame
		t_stop += get_process_delta_time()
	await _wait(0.5)
	var after := player.shot_times.size() - n_held
	# (game time. A frame here is 0.13 s of software rendering and the rounds of one frame leave together, so the
	# gap is measured against a frame and a half; on a real graphics card it is the 1/12 s between rounds)
	var frame := get_process_delta_time()
	# (the release reaches the game a frame late, and the gun stops the frame after: two frames' worth of rounds)
	a = n_held >= 24 and gap < maxf(0.1, 1.5 * frame) and t_stop < maxf(0.15, 2.5 * frame) and after <= int(2.0 * frame * 12.0) + 1
	ok = ok and a
	print("[gun] held 2.5 s: ", "PASS" if a else "FAIL", " (%d rounds, longest gap %.2f s, stopped %.2f s after release, %d rounds after it)" % [
		n_held, gap, t_stop, after])
	a = player.worst_bend < 3.0 and highest < centre.y - 12.0
	ok = ok and a
	print("[gun] rounds leave along the barrel, cursor climbs: ", "PASS" if a else "FAIL",
		" (path bends %.1f degrees at most, cursor up to %.0f px above the middle)" % [player.worst_bend, centre.y - highest])
	# aimed fire
	player.shot_times.clear()
	var fov0 := player.cam.fov
	_key(KEY_C, true)                                  # C aims (as the right mouse button does)
	await _wait(0.8)
	var zoom := player.cam.fov / fov0
	var aimed_off := player.aim_dot.distance_to(centre)
	_press(MOUSE_BUTTON_LEFT, true)
	await _wait(1.0)
	_press(MOUSE_BUTTON_LEFT, false)
	await _wait(0.5)
	var still_aiming := player.busy == "ADS"
	_key(KEY_C, false)
	await _until(func() -> bool: return player.busy == "", 3.0)
	a = player.shot_times.size() >= 8 and still_aiming and player.busy == "" and aimed_off < 14.0 and zoom < 0.85 and player.cam.fov > fov0 * 0.97
	ok = ok and a
	print("[gun] C aims, the view zooms, fire while aiming: ", "PASS" if a else "FAIL", " (%d rounds, back at the aim: %s, lowered: %s, cursor %.1f px off, field of view x%.2f while aiming)" % [
		player.shot_times.size(), still_aiming, player.busy == "", aimed_off, zoom])
	# the gun is drawn by its own camera over the world: a wall cannot cut into it
	a = (player.cam.cull_mask & V2Player.GUN_LAYER) == 0 and player.view_cam.cull_mask == V2Player.GUN_LAYER
	for n in (player._views[player.weapon].scene as Node).find_children("*", "MeshInstance3D", true, false):
		a = a and (n as MeshInstance3D).layers == V2Player.GUN_LAYER
	ok = ok and a
	print("[gun] the gun is drawn over the world by its own camera: ", "PASS" if a else "FAIL")
	# crouch: X
	var eye0 := player.cam.position.y
	_key(KEY_X, true)
	_key(KEY_X, false)
	await _wait(0.6)
	var eye1 := player.cam.position.y
	var chest1 := player.chest().y - player.global_position.y
	_key(KEY_X, true)
	_key(KEY_X, false)
	await _wait(0.6)
	a = eye1 < eye0 - 0.5 and chest1 < 0.7 and absf(player.cam.position.y - eye0) < 0.02
	ok = ok and a
	print("[gun] X crouches and stands: ", "PASS" if a else "FAIL", " (eye %.2f -> %.2f -> %.2f m, crouched chest at %.2f m)" % [eye0, eye1, player.cam.position.y, chest1])
	# reload: its sounds come at the clip's moments
	_key(KEY_T, true)
	_key(KEY_T, false)
	await _until(func() -> bool: return player.busy == "ReloadEmpty", 1.0)
	await _until(func() -> bool: return player.busy == "", 5.0)
	# sprint, then stop
	player._yaw = PI                                   # (down the room, away from the wall behind)
	player.global_position = rooms[0].position + Vector3(0.2, 0.02, -10.0)
	_key(KEY_SHIFT, true)
	_key(KEY_W, true)
	await _wait(1.2)
	var was_sprinting := player.busy == "Sprint"
	_key(KEY_W, false)
	_key(KEY_SHIFT, false)
	var t_run := 0.0
	while player.busy == "Sprint" and t_run < 3.0:
		await get_tree().process_frame
		t_run += get_process_delta_time()
	a = was_sprinting and t_run < 0.35
	ok = ok and a
	print("[gun] sprint ends when the player stops: ", "PASS" if a else "FAIL", " (sprinting: %s, the clip let go after %.2f s)" % [was_sprinting, t_run])
	await get_tree().process_frame
	var unheard: Array = []
	for key in ["rifle_shot", "rifle_tail", "casing", "handling", "rifle_mag_out", "rifle_mag_in", "bolt", "step", "crouch"]:
		if not V2Sfx.heard.has(key):
			unheard.append(key)
	ok = ok and unheard.is_empty()
	print("[gun] sounds of the gun and the player: ", "PASS" if unheard.is_empty() else "FAIL", "" if unheard.is_empty() else "  never played: " + ", ".join(unheard))
	print("[gun] RESULT: ", "PASS" if ok else "FAIL")
	get_tree().quit()


func _input_test() -> void:
	for r in robots:
		r.set_ai(false)                               # (nothing shooting back while the controls are checked)
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
	# the camera must follow the clip's own camera motion (view punch of a shot). Found by stepping through the
	# clip, not by watching frames go by: the punch lasts two frames of the clip and a slow frame steps over it.
	player.busy = ""
	player.act("Fire")
	var kick_node: Node3D = player._views[player.weapon].kick
	var kap := player._ap()
	var kick_len := kap.get_animation("Fire").length
	var in_clip := 0.0
	var at := 0.0
	for step in 48:
		kap.seek(kick_len * step / 48.0, true)
		var a := rad_to_deg(kick_node.transform.basis.get_euler().length()) if kick_node != null else 0.0
		if a > in_clip:
			in_clip = a
			at = kick_len * step / 48.0
	kap.seek(at, true)
	kap.pause()
	await get_tree().process_frame
	await get_tree().process_frame
	var punch := rad_to_deg((Basis(Vector3.RIGHT, player._pitch + player._kick).inverse() * player.cam.basis).get_euler().length())
	kap.play()
	print("[input] camera kick from the clip: ", "PASS" if in_clip > 0.3 and punch > 0.8 * in_clip else "FAIL",
		" (%.2f degrees in the clip, %.2f on the camera)" % [in_clip, punch])
	await _wait(0.4)
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


func _want(section: String) -> bool:
	return _only == "" or section in _only.split(",")


## Screenshot tour. --only=rooms,doors,guns,ai limits it to those parts.
func _capture(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	player.mouse_look = false
	player.invulnerable = true
	V2Fx.hold = 40.0
	for r in robots:
		r.set_ai(false)
		r.auto = false
	if _want("rooms"):
		for i in rooms.size():
			goto(i)
			robots[i].play("Idle")
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
			robots[i].play("Idle")
	if _want("doors"):
		# the doorways: look at the first, walk through each (0.25 m off centre: clear of the stair post beyond), look back
		goto(0)
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
	if _want("guns"):
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
		player.switch_weapon()
	if _want("tone"):
		# the Blender camera's own view (v2/renders/stage3_scene.png is the same frame): for comparing light and colour
		goto(0)
		robots[0].play("Idle")
		robots[0].ap.pause()
		await _wait(0.5)
		await _shot(dir, "tone_room1")
	if _want("look"):
		# materials from close by: each robot where it stands in Blender, and the two guns turned over
		for i in rooms.size():
			goto(i)
			robots[i].play("Idle")
			robots[i].ap.pause()
			var hp := robots[i].hit_point()
			var off := Vector3(1.0, 0.0, 1.9) if KINDS[i] != "turret" else Vector3(1.2, 0.0, 2.6)
			player.global_position = Vector3(hp.x + off.x, 0.02 if KINDS[i] == "spider" else (1.1 if KINDS[i] == "drone" else 0.6), hp.z + off.z)
			var d := hp - (player.global_position + Vector3(0, V2Player.EYE, 0))
			player._yaw = atan2(-d.x, -d.z)
			player._pitch = atan2(d.y, Vector2(d.x, d.z).length())
			player.velocity = Vector3.ZERO
			player.set_physics_process(false)
			await _wait(0.5)
			await _shot(dir, "look_" + KINDS[i])
			player.set_physics_process(true)
		goto(0)
		for w in 2:
			player.busy = ""
			player.act("Inspect")
			await _wait(1.0)
			player._ap().pause()
			await _shot(dir, "look_" + player.weapon)
			player._ap().play()
			player.busy = ""
			player.switch_weapon()
			await _wait(1.5)
	if _only != "" and "wreck" in _only.split(","):
		# (only on request: a quick look at a destroyed robot, the burst and the smoke that follows)
		goto(0)
		var w := robots[0]
		w.set_ai(true)
		var hp := w.hit_point()
		player._yaw = atan2(-(hp.x - player.global_position.x), -(hp.z - player.global_position.z))
		w.hit(9999.0)
		Engine.time_scale = 0.05
		await _wait(0.06)
		await _shot(dir, "wreck_burst")
		Engine.time_scale = 1.0
		V2Fx.hold = 1.0                                   # (the flash of the burst must be gone for the next picture)
		await _wait(5.0)
		await _shot(dir, "wreck_smoke")
	if _only != "" and "fx" in _only.split(","):
		# (only on request: the player's rounds on a wall: sparks, chips and dust at the moment of a hit, then the marks)
		goto(0)
		robots[0].set_ai(false)
		V2Fx.hold = 1.0
		player._yaw = deg_to_rad(52.0)
		player._pitch = deg_to_rad(-8.0)
		for k in 3:
			player._yaw += deg_to_rad(2.5)
			player.busy = ""
			player.act("Fire")
			await _wait(0.6)
		player._yaw += deg_to_rad(2.5)
		player.busy = ""
		player.act("Fire")
		Engine.time_scale = 0.05
		await _wait(0.12)
		await _shot(dir, "fx_impact")
		Engine.time_scale = 1.0
		await _wait(1.5)
		await _shot(dir, "fx_marks")
		V2Fx.hold = 40.0
	if _only != "" and "panel" in _only.split(","):
		# (only on request: consecutive frames of the machine gun at rest and walking, to look for flicker)
		goto(0)
		robots[0].set_ai(false)
		if player.weapon != "rifle":
			player.switch_weapon()
		await _wait(1.6)
		Engine.time_scale = 0.25
		for k in 12:
			await get_tree().process_frame
			await _shot(dir, "panel_%02d" % k)
		Engine.time_scale = 1.0
	if _only != "" and "adsfire" in _only.split(","):
		# (only on request: every frame, at a 60th of a second, of aiming and firing the machine gun with real input:
		# aim, hold the trigger, let go, two taps, lower. For hunting one-frame glitches.)
		goto(0)
		robots[0].set_ai(false)
		player.mouse_look = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if player.weapon != "rifle":
			player.switch_weapon()
		await _wait(1.6)
		Engine.max_fps = 0
		Engine.time_scale = 1.0 / 60.0 / maxf(get_process_delta_time(), 0.02)     # a frame here = 1/60 s of the game
		var script_keys := {20: [KEY_C, true], 50: [MOUSE_BUTTON_LEFT, true], 110: [MOUSE_BUTTON_LEFT, false], 125: [MOUSE_BUTTON_LEFT, true],
			131: [MOUSE_BUTTON_LEFT, false], 145: [MOUSE_BUTTON_LEFT, true], 150: [MOUSE_BUTTON_LEFT, false], 175: [KEY_C, false]}
		for k in 215:
			if script_keys.has(k):
				var ev: Array = script_keys[k]
				if ev[0] == KEY_C:
					_key(KEY_C, ev[1])
				else:
					_press(ev[0], ev[1])
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(dir.path_join("adsfire_%03d_%s.png" % [k, player.busy if player.busy != "" else "none"]))
			if OS.has_environment("V2_DEBUG_GUN"):
				print("[af] %03d busy=%s anim=%s pos=%.3f playing=%s aimed=%.2f" % [k, player.busy, player._ap().current_animation, player._ap().current_animation_position, player._ap().is_playing(), player._aimed])
		Engine.time_scale = 1.0
		player.mouse_look = false
	if _only != "" and "wall" in _only.split(","):
		# (only on request: nose against a wall with each gun: the gun must stay whole; then crouched behind cover)
		goto(0)
		robots[0].set_ai(false)
		for w in 2:
			player.global_position = rooms[0].position + Vector3(XL + 0.36, 0.02, -3.0)
			player._yaw = PI / 2.0
			player._pitch = 0.0
			await _wait(1.2)
			await _shot(dir, "wall_" + player.weapon)
			player.switch_weapon()
			await _wait(1.3)
		player.global_position = rooms[0].position + Vector3(3.7, 0.02, -0.5)      # behind the low wall
		player._yaw = 0.3
		await _wait(0.5)
		await _shot(dir, "cover_standing")
		player.set_crouch(true)
		await _wait(0.8)
		await _shot(dir, "cover_crouched")
		player.set_crouch(false)
	if _only != "" and "spin" in _only.split(","):
		# (only on request: the drone shot down: its flight out of control, the crash, the wreck burning)
		goto(1)
		var dr := robots[1]
		dr.set_ai(true)
		V2Fx.hold = 1.0
		await _wait(1.0)
		dr.hit(9999.0, Vector3(0.3, 0, -1).normalized())
		for k in 12:
			await _wait(0.5)
			var dp := dr.hit_point() - player.cam.global_position
			player._yaw = atan2(-dp.x, -dp.z)
			player._pitch = atan2(dp.y, Vector2(dp.x, dp.z).length())
			await get_tree().process_frame
			await _shot(dir, "spin_%02d_%s" % [k, "flying" if dr._spin > 0.0 else ("falling" if not dr._exploded else "wreck")])
		V2Fx.hold = 40.0
	if _want("ai"):
		# the robots as enemies: on the move, firing (the game slowed down to catch the flash), wrecked and smoking
		for i in rooms.size():
			goto(i)
			var r := robots[i]
			r.set_ai(true)
			r._cool = 0.5
			await _wait(2.5)
			await _shot(dir, "ai%d_%s_move" % [i + 1, KINDS[i]])
			await _until(func() -> bool: return r.state == V2Robot.SHOOT, 25.0)
			Engine.time_scale = 0.12
			await _until(r.flash_on, 4.0)
			Engine.time_scale = 0.02
			await _shot(dir, "ai%d_%s_fire" % [i + 1, KINDS[i]])
			# the same moment from the side: the round must leave along the barrel, toward the player
			var side_cam := Camera3D.new()
			add_child(side_cam)
			var from_p := r.hit_point()
			var to_p := player.global_position + Vector3(0, 1.2, 0)
			var across := (to_p - from_p).cross(Vector3.UP).normalized()
			side_cam.fov = 55.0
			side_cam.look_at_from_position(from_p.lerp(to_p, 0.3) + across * 4.2 + Vector3(0, 0.6, 0), from_p.lerp(to_p, 0.3), Vector3.UP)
			side_cam.cull_mask &= ~V2Player.GUN_LAYER
			side_cam.make_current()
			player.overlay.visible = false
			_hud.get_parent().visible = false
			await _shot(dir, "ai%d_%s_fire_side" % [i + 1, KINDS[i]])
			_hud.get_parent().visible = true
			player.overlay.visible = true
			player.cam.make_current()
			side_cam.queue_free()
			Engine.time_scale = 1.0
			player._yaw = atan2(-(r.hit_point().x - player.global_position.x), -(r.hit_point().z - player.global_position.z))
			V2Fx.hold = 1.0                               # (the burst's flash must be over in the wreck picture)
			r.hit(9999.0)
			await _wait(4.0)
			await _shot(dir, "ai%d_%s_wreck" % [i + 1, KINDS[i]])
			print("[capture] %s wreck: lowest point %.3f m above the floor, barrels point %.0f degrees below level" % [
				KINDS[i], r.lowest_point() - rooms[i].global_position.y, -rad_to_deg(asin(r._barrel().y))])
			V2Fx.hold = 40.0
			r.set_ai(false)
	get_tree().quit()


# ---------------------------------------------------------------- enemy check (--enemy-test; runs headless)
## Plays each room by code, at four times speed: the robot must move (the turret: swing onto the player), stay in
## its arena, fire, and hurt a player who stands still; the player's own rounds (aimed by code, fired through the
## real clips) must destroy it, and it must come back. Then the player is left to be shot down and must be revived.
func _enemy_test() -> void:
	Engine.time_scale = 4.0
	player.mouse_look = false
	var ok := true
	for i in rooms.size():
		goto(i)
		var r := robots[i]
		r.respawn()
		r._cool = 0.5
		player.revive()
		player._grace = 0.0
		var shots0 := r.shots_fired
		var trav0 := r.travelled
		var hp_min := V2Player.MAX_HP
		var outside := false
		var best_aim := 9.0
		var t := 0.0
		while t < 24.0:
			await get_tree().process_frame
			t += get_process_delta_time()
			hp_min = minf(hp_min, player.hp)
			outside = outside or not r.in_arena()
			if r.kind == "turret" and r._aim_valid:
				best_aim = minf(best_aim, r.aim_error())
			if player.down:
				player.revive()
				player._grace = 0.0
		var moved := (best_aim < 0.12) if r.kind == "turret" else (r.travelled - trav0 > 2.0)
		var a := moved and not outside and r.shots_fired > shots0 and hp_min < V2Player.MAX_HP
		ok = ok and a
		print("[enemy] %s as enemy: %s  (travelled %.1f m, best aim %.2f rad, in arena %s, shots %d, player health down to %d)" % [
			r.kind, "PASS" if a else "FAIL", r.travelled - trav0, best_aim, not outside, r.shots_fired - shots0, hp_min])
		player.invulnerable = true
		# a hit pushes it: the body is knocked off its seat and tips, comes back on its springs; spider and drone are shoved
		r.respawn()
		await _wait(0.3)
		var p0 := r.position
		var dir := (r.hit_point() - player.cam.global_position).normalized()
		r.hit(1.0, dir)
		var shoved := r._shove.dot(Vector3(dir.x, 0, dir.z).normalized())
		var knock := 0.0
		var tip := 0.0
		t = 0.0
		while t < 1.0:
			await get_tree().process_frame
			t += get_process_delta_time()
			knock = maxf(knock, r._knock.length())
			tip = maxf(tip, r._tilt.length())
		a = tip > 0.04 and r._tilt.length() < 0.02 and (r.kind == "turret" or (knock > 0.02 and r._knock.length() < 0.01 and shoved > 0.3))
		ok = ok and a
		print("[enemy] %s pushed by a hit: %s  (knocked %.0f mm, tipped %.0f degrees, both back; shoved off at %.1f m/s)" % [
			r.kind, "PASS" if a else "FAIL", knock * 1000.0, rad_to_deg(tip), shoved])
		if r.kind == "spider":
			# it turns on the spot by stepping round: the feet that stand must stay where they are on the floor
			r.respawn()
			r.set_process(false)                           # (driven from here: a fixed half turn)
			var face := Basis(Vector3.UP, r.rotation.y + deg_to_rad(165.0)) * Vector3.FORWARD
			var feet: Array = []
			for k in 4:
				feet.append(r.find_child("Spider_Foot%d" % k, true, false))
			var prev: Array = []
			var slip := 0.0
			var slips: Array[float] = []
			var turned := 0.0
			var yaw_prev := r.rotation.y
			var t_turn := 0.0
			t = 0.0
			Engine.time_scale = 1.0                        # (fine steps: a foot is watched from frame to frame)
			while t < 6.0 and turned < deg_to_rad(150.0):
				await get_tree().process_frame
				var dt := get_process_delta_time()
				t += dt
				r._step_round(face, dt)
				r.ap.advance(dt)                               # (the robot advances its own clips; it is switched off here)
				t_turn += dt
				turned += absf(angle_difference(yaw_prev, r.rotation.y))
				yaw_prev = r.rotation.y
				var now: Array = []
				var low := 1e9
				for f in feet:
					now.append((f as Node3D).global_position)
					low = minf(low, (f as Node3D).global_position.y)
				if prev.size() == 4 and t_turn > 0.35:        # (after the blend into the clip)
					for k in 4:
						if now[k].y < low + 0.006 and prev[k].y < low + 0.006:      # this foot stands
							slips.append(Vector2(now[k].x - prev[k].x, now[k].z - prev[k].z).length() / dt)
				prev = now
			Engine.time_scale = 4.0
			r.set_process(true)
			slips.sort()
			var mean := 0.0
			for v in slips:
				mean += v / maxf(slips.size(), 1.0)
			slip = slips[int(slips.size() * 0.95)] if not slips.is_empty() else 9.0      # (95th percentile: a foot's last frame down may count)
			a = turned > deg_to_rad(140.0) and slip < 0.15 and mean < 0.06
			ok = ok and a
			print("[enemy] spider turns by stepping: %s  (turned %.0f degrees in %.1f s; a standing foot moves %.2f m/s on average, %.2f at worst; sliding round would be 1.5)" % [
				"PASS" if a else "FAIL", rad_to_deg(turned), t_turn, mean, slip])
		r.respawn()
		var hits0 := player.shots_hit
		t = 0.0
		while r.state != V2Robot.DEAD and t < 60.0:
			await get_tree().process_frame
			t += get_process_delta_time()
			var d := r.hit_point() - player.cam.global_position
			player._yaw = atan2(-d.x, -d.z)
			player._pitch = atan2(d.y, Vector2(d.x, d.z).length())
			if player.busy == "":
				player.act("Fire")
		var killed := r.state == V2Robot.DEAD
		var t_kill := t
		# shot down, the drone flies on out of control before it falls and blows up; the others drop where they are
		var flew := 0.0
		if r.kind == "drone":
			var last := r.position
			var t_fly := 0.0
			while r._spin > 0.0 and t_fly < 6.0:
				await get_tree().process_frame
				t_fly += get_process_delta_time()
				flew += r.position.distance_to(last)
				last = r.position
			var t_boom := 0.0
			while not r._exploded and t_boom < 4.0:
				await get_tree().process_frame
				t_boom += get_process_delta_time()
			a = flew > 5.0 and t_fly > 1.5 and r._exploded and V2Sfx.heard.has("explosion")
			ok = ok and a
			print("[enemy] drone, shot down, flies out of control, then crashes and explodes: %s  (%.1f m in %.1f s, exploded %.1f s later: %s)" % [
				"PASS" if a else "FAIL", flew, t_fly, t_boom, r._exploded])
		# the wreck still answers a round: the joint that is struck swings and comes to rest again
		await _wait(0.6)
		var joint := r._hit_joint
		var rest := joint.transform
		r.hit(12.0, (r.hit_point() - player.cam.global_position).normalized(), r.hit_point() + Vector3(0.2, 0.1, 0.0), joint)
		var swing := 0.0
		t = 0.0
		while t < 0.5:
			await get_tree().process_frame
			t += get_process_delta_time()
			swing = maxf(swing, joint.transform.basis.get_rotation_quaternion().angle_to(rest.basis.get_rotation_quaternion()))
		a = r.state == V2Robot.DEAD and swing > deg_to_rad(2.0)
		ok = ok and a
		print("[enemy] %s wreck struck by a round: %s  (the struck joint swings %.0f degrees)" % [r.kind, "PASS" if a else "FAIL", rad_to_deg(swing)])
		t = 0.0
		while r.state == V2Robot.DEAD and t < 20.0:
			await get_tree().process_frame
			t += get_process_delta_time()
		var back := r.state != V2Robot.DEAD and r.hp == r.max_hp
		ok = ok and killed and back
		print("[enemy] %s shot by the player: %s  (%d hits, destroyed after %.1f s, back after %.1f s: %s)" % [
			r.kind, "PASS" if killed and back else "FAIL", player.shots_hit - hits0, t_kill, t, back])
		player.invulnerable = false
	goto(0)
	player.revive()
	player._grace = 0.0
	player.hp = 8.0
	player._since_hurt = -30.0
	var d0 := downs
	var t2 := 0.0
	while downs == d0 and t2 < 60.0:
		await get_tree().process_frame
		t2 += get_process_delta_time()
	var went_down := downs > d0
	t2 = 0.0
	while player.down and t2 < 6.0:
		await get_tree().process_frame
		t2 += get_process_delta_time()
	var revived := went_down and not player.down and player.hp == V2Player.MAX_HP
	ok = ok and revived
	print("[enemy] player shot down and revived: %s" % ("PASS" if revived else "FAIL"))
	# every interaction of the fight was heard (the keys played; this machine has no sound device)
	var want := ["pistol_shot", "casing", "impact_metal", "robot_hit", "robot_break", "spider_shot", "drone_shot", "turret_shot",
		"spider_step", "explosion", "power_down", "crash", "hurt", "down", "zap"]
	var unheard: Array = []
	for key in want:
		if not V2Sfx.heard.has(key):
			unheard.append(key)
	ok = ok and unheard.is_empty()
	print("[enemy] sounds of the fight: %s  (%d keys%s)" % ["PASS" if unheard.is_empty() else "FAIL", want.size(),
		"" if unheard.is_empty() else "; never played: " + ", ".join(unheard)])
	print("[enemy] RESULT: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
