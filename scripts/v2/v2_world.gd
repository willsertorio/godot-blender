class_name V2World
extends Node3D
## What the V2 lab and the V2 game are both built from: a row of rooms (the plain studio or the concept room of the
## Blender scene) side by side, joined by doorways, each on its own render layer with its own lights, and the light
## and look of the whole (`_environment`). v2_lab.gd and v2_game.gd extend this.

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

# How many rows of pixels the 3D picture is drawn with, at most (0 = as many as the window has). A Retina display
# gives the window 2560 x 1600 pixels: four times the 1280 x 720 the frame rate was first measured at, each with
# 4x anti-aliasing. The picture is drawn smaller and stretched; the HUD stays at the window's pixels. F4 steps
# through these in the game and the lab (static: the choice lasts over scene changes).
const RENDER_ROWS := [1080, 900, 720, 0]
static var render_rows := 1080

var rooms: Array[Node3D] = []
var _low := false                 # --quality=low: no shadows, no glow, no MSAA
var _room_lights: Array = []        # per room: its omni and spot lights
var _gun_room := -1
var _concept := false             # the detailed room of the Blender scene instead of the studio


## The 3D picture's size (see RENDER_ROWS): set now and whenever the window changes size.
## The colour a run opens out of: the title sets its own white before it hands over, so that its page seems to
## dissolve into the room; a run started from an end screen opens out of that screen's grey.
static var open_from := UIPalette.COMPLETE_BG

func _render_setup() -> void:
	# (the UI concept's canvas: its pixel values are at 1440 x 810; a taller window shows more, it is not letterboxed)
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	win.content_scale_size = Vector2i(1440, 810)
	_render_apply()
	if not get_window().size_changed.is_connected(_render_apply):
		get_window().size_changed.connect(_render_apply)


func _render_apply() -> void:
	var rows := float(get_window().size.y)
	get_viewport().scaling_3d_scale = 1.0 if render_rows == 0 or rows <= render_rows else clampf(render_rows / rows, 0.35, 1.0)


func _render_next() -> void:
	render_rows = RENDER_ROWS[(RENDER_ROWS.find(render_rows) + 1) % RENDER_ROWS.size()]
	_render_apply()


## For the F3 line: what the 3D picture is drawn at.
func _render_text() -> String:
	var win := get_window().size
	var k := get_viewport().scaling_3d_scale
	return "3D %d x %d%s" % [roundi(win.x * k), roundi(win.y * k), "" if k >= 0.999 else " of %d x %d" % [win.x, win.y]]


## `ambient`: the even light from all sides; `floor_light`: the light straight down. The lab's numbers are the
## defaults; the dungeon asks for more of the first (its props are lit from two or three lamps under the ceiling,
## and a side turned away from them was nearly black: in a real white room the floor lights it).
func _environment(ambient: float = 0.16, floor_light: float = 0.32, shadows_to: float = 34.0) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.88, 0.92, 0.95)
	env.ambient_light_energy = ambient
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
	down.light_energy = floor_light * (1.56 if _low else 1.0)
	# Its shadows fall straight down: the pools under the robots, the stairs and the mezzanine. They are the only
	# shadows: one flat pass over the three rooms (the shell casts none). A shadow-casting omni light draws
	# everything in its range six times (a cube; the dual-paraboloid mode drew nothing here): two of those per room
	# once made a frame 7.8 million triangles and 1900 draw calls.
	# (measured: with shadows on, this light comes out about half as bright again as without, hence 0.32)
	down.shadow_enabled = not _low
	down.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	down.directional_shadow_max_distance = shadows_to       # (everything that casts within it is drawn twice)
	down.shadow_blur = 2.2
	down.shadow_bias = 0.06
	down.shadow_normal_bias = 1.5
	add_child(down)


## Room i of the row: the shell (the studio, or the concept room), its collision, its floor, its lights. The caller
## puts what lives in it there and then calls _set_layer(room, _layer(i)).
func _room_shell(i: int, room_name: String) -> Node3D:
	var room := Node3D.new()
	room.name = room_name
	room.position = Vector3(i * ROOM_DX, 0, 0)
	add_child(room)
	# The lab's rooms are a plain studio (v2/scripts/build_studio.py), the size of the concept room and with the
	# same doorways; the game's are the concept room itself (room.glb, from scene.blend).
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
	rooms.append(room)
	return room


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


## The concept room has a loop of cable hanging where the turret's rail runs: out of that room.
func hide_for_rail(room: Node3D) -> void:
	for n in room.find_children("Loop3*", "MeshInstance3D", true, false):
		(n as Node3D).visible = false


## Every frame of the next `seconds` as a picture: DIR/<label>_<milliseconds>.png (for looking at a transition;
## it ends with the node `on`, so a change of scene ends it; at the end of the game's own film the game quits).
static func film(on: Node, dir: String, label: String, seconds: float) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(on) and on.is_inside_tree() and Time.get_ticks_msec() - t0 < seconds * 1000.0:
		await RenderingServer.frame_post_draw
		if not (is_instance_valid(on) and on.is_inside_tree()):
			return
		on.get_viewport().get_texture().get_image().save_jpg("%s/%s_%05d.jpg" % [dir, label, Time.get_ticks_msec() - t0], 0.8)
	if label == "game" and is_instance_valid(on) and on.is_inside_tree():
		on.get_tree().quit()

