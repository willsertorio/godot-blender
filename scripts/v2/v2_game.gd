extends V2World
## The V2 game: one level. Four sectors (the concept room of the Blender scene, four times in a row) joined by
## doors, the robots of the lab as its garrison, supply crates, an exit gate in the last sector.
##   The player starts in sector A, opens the doors (E), and wins by walking into the exit gate in sector D.
##   A sector's door onward is locked while one of its robots still works (its lamp: red = locked, amber = shut,
##   green = open). Without that the level is a sprint: the doorways face each other under the mezzanine, and a
##   player could run from door to door past every hall.
##   Robots do not come back; a wreck stays where it fell. Spiders hold their hall; drones that have seen the
##   player follow through open doors (on edge: a drone is wider than a doorway); a turret runs along its rail.
##   Magazines run out (R reloads, an empty gun reloads by itself), the machine gun's rounds are finite, health
##   does not come back by itself: crates (E) and some wrecks give ammunition, health cells and med kits (H).
##   No pause, no prompts (the GDD's rules); Esc frees the mouse and offers the way back to the title.
##   F3 shows the frame rate and what a frame costs to draw.
##   godot --path . -- --play                 straight into the level
##   godot --path . -- --game-test            checks by code, PASS / FAIL (headless: rules; with a display: the walk too)
##   godot --path . -- --bot=5                the balance bot plays the level 5 times and prints how it went
##   godot --path . -- --game-capture=DIR     screenshots of the level
const TITLE := "res://scenes/v2_title.tscn"
const SCORE := {"turret": 100, "drone": 150, "spider": 200}
# What each sector holds (room frame, metres; yaw in degrees, 0 = facing -z, the back of the room).
#   robots: [kind, x, z, yaw, arena or null (SPEC's)]   crates: [x, z, yaw (0 = its front toward +z), what is in it]
#   tank = the liquid's colour
const LEVEL := [
	{"name": "A", "tank": Color(0.2, 0.62, 0.68), "robots": [], "crates": [[5.85, -8.4, -90.0, "ammo"]]},
	{"name": "B", "tank": Color(0.25, 0.68, 0.4), "robots": [
		["spider", 0.5, -5.0, -35.0, Rect2(-1.6, -6.8, 3.9, 3.9)], ["spider", 0.3, 0.3, -20.0, Rect2(-1.6, -2.1, 3.9, 4.1)]],
		"crates": [[-4.02, 1.0, 90.0, "kit"], [5.85, -8.4, -90.0, "health"]]},
	{"name": "C", "tank": Color(0.75, 0.55, 0.16), "robots": [
		["drone", 2.0, -4.6, 160.0, Rect2(-2.3, -7.0, 5.0, 4.0)], ["drone", -0.8, -0.6, 200.0, Rect2(-2.3, -2.6, 5.0, 4.1)],
		["turret", 0.0, 0.0, 0.0, null]],
		"crates": [[-1.5, 2.65, 180.0, "ammo"], [1.0, -13.62, 0.0, "kit"]]},
	{"name": "D", "tank": Color(0.5, 0.36, 0.85), "robots": [
		["spider", 0.4, -4.4, -30.0, Rect2(-1.6, -6.8, 3.9, 4.6)], ["drone", 1.4, -0.4, 180.0, Rect2(-2.3, -2.2, 5.0, 3.4)],
		["turret", 0.0, 0.0, 0.0, null]],
		"crates": [[-4.02, 1.0, 90.0, "ammo"]], "exit": [1.0, 2.5]},
]
# The robots of the game against the lab's: [aim lag in seconds (the lab: 0.3), damage x, pauses between bursts /].
# Tuned with the bot (tools/v2_bot.sh; CLAUDE.md, "V2 game", has the runs). The spider most of all: with the lab's
# numbers, and with the drone's here, the two spiders of sector B never once hit a bot that keeps moving sideways.
const TOUGH := {"spider": [0.09, 1.3, 1.3], "drone": [0.24, 1.15, 1.2], "turret": [0.24, 1.15, 1.2]}
const DROP := 0.35                  # chance that a destroyed robot leaves something
const DROPS := ["ammo", "ammo", "ammo", "health", "health", "kit"]
const REACH := 2.3                  # how near a door or a crate must be for E

enum { PLAYING, WON, LOST }

var player: V2Player
var robots: Array[V2Robot] = []
var state := PLAYING
var kills := 0
var score := 0
var elapsed := 0.0
var current := 0                    # the sector the player is in
var doors: Array = []               # between sector i and i + 1: {leaves, open, light, x}
var crates: Array = []              # {node, lid, light, what, open}
var pickups: Array = []             # {node, what, t}
var _props: Node3D
var _exit_at := Vector3.INF
var _exit_hum: AudioStreamPlayer3D
var _ui: CanvasLayer
var _hp_fill: ColorRect
var _hp_text: Label
var _kits_text: Label
var _gun_text: Label
var _ammo_text: Label
var _goal_text: Label
var _note_text: Label
var _note_t := 0.0
var _dot: ColorRect
var _flash: ColorRect
var _low_hp: ColorRect
var _menu: Control
var _end: Control
var _chase_t := 0.0
var _bot: Node
var _seen: Dictionary = {}          # sectors the player has been in
var _lamps: Dictionary = {}
var _banner: Label
var _from_bars: Array = []          # red bars at the screen's edges: the side a hit came from (top = ahead)
var _perf: Label                    # F3: frame rate and what the frame costs to draw
var _perf_t := 0.0
var _perf_n := 0
var _banner_t := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	V2Fx.root = self
	V2Fx.reset()
	V2Sfx.root = self
	V2Sfx.enabled = not ("--no-sound" in args)
	_low = "--quality=low" in args
	_concept = true
	if _low:
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	_environment()
	_props = (load(V2Assets.DIR + "props.glb") as PackedScene).instantiate()
	V2Assets.apply(_props)
	for i in LEVEL.size():
		_sector(i)
	for i in LEVEL.size() - 1:
		_door_lining(i)
		_door(i)
	_door_frame(rooms[0], XL - 0.3, XL + 0.16, _layer(0))                               # the outer doorways lead nowhere
	_door_frame(rooms[LEVEL.size() - 1], XR - 0.16, XR + 0.3, _layer(LEVEL.size() - 1))
	_door_plug(0, XL + 0.1)
	_door_plug(LEVEL.size() - 1, XR - 0.1)
	player = V2Player.new()
	player.rules = true
	player.grab = false                                # (a click does not take the mouse back: the menu's buttons must work)
	add_child(player)
	player.global_position = rooms[0].position + Vector3(0.2, 0.02, 0.0)
	player._pitch = deg_to_rad(-3.0)
	player.died.connect(_on_died)
	player.interact.connect(interact)
	for r in robots:
		r.player = player
	_hud()
	_rooms_shown()
	V2Sfx.ambience("room_tone")
	var capture := ""
	var bot := 0
	for a in args:
		if a.begins_with("--game-capture="):
			capture = a.trim_prefix("--game-capture=")
		if a.begins_with("--bot"):
			bot = maxi(int(a.trim_prefix("--bot=")), 1) if a.contains("=") else 3
	if "--game-test" in args or bot > 0 or capture != "" or "--bot-diag" in args:
		_bot = (load("res://scripts/v2/v2_game_bot.gd") as GDScript).new()
		_bot.game = self
		add_child(_bot)
		if "--bot-diag" in args:
			_bot.diag()
		elif capture != "":
			_bot.capture(capture)
		elif bot > 0:
			_bot.play_runs(bot)
		else:
			_bot.test()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---------------------------------------------------------------------------------------------- building the level
func _sector(i: int) -> void:
	var spec: Dictionary = LEVEL[i]
	var room := _room_shell(i, "Sector_" + String(spec.name))
	_tanks(room, spec.tank)
	for k in spec.robots.size():
		var rs: Array = spec.robots[k]
		var robot := V2Robot.new()
		room.add_child(robot)
		robot.setup(rs[0])
		robot.respawns = false
		robot.aim_lag = TOUGH[rs[0]][0]
		robot.damage_scale = TOUGH[rs[0]][1]
		robot.haste = TOUGH[rs[0]][2]
		robot.show_label = false
		robot.world = self
		robot.room = i
		if rs[0] == "turret":
			robot.set_rail(-4.9, -1.4)
			hide_for_rail(room)
		else:
			robot.place(Vector3(rs[1], 0.0, rs[2]), rs[3])
			if rs[0] == "spider":
				robot._spec.keep = [3.8, 6.0]              # it closes in more than the lab's (5 to 7.5 m): its rounds scatter with its guns' recoil
			if rs[4] != null:
				robot.arena = rs[4]
		robot.destroyed.connect(_on_destroyed)
		robots.append(robot)
	for cs in spec.crates:
		_crate(room, Vector3(cs[0], 0.0, cs[1]), cs[2], cs[3])
	if spec.has("exit"):
		_exit(room, Vector3(spec.exit[0], 0.0, spec.exit[1]))
	# the sector's letter by its doors
	for side in [[XL + 0.03, 90.0], [XR - 0.03, -90.0]]:
		var plate := Label3D.new()
		plate.text = String(spec.name)
		plate.font = V2Ui.heading()
		plate.font_size = 150
		plate.pixel_size = 0.004
		plate.modulate = Color(0.1, 0.11, 0.13)
		plate.outline_size = 0
		plate.position = Vector3(side[0], 1.55, DOOR_Z + 1.45)
		plate.rotation_degrees.y = side[1]
		room.add_child(plate)
	_set_layer(room, _layer(i))


## Each sector's tanks hold a liquid of its own colour: the one thing that tells four copies of a room apart at once.
func _tanks(room: Node3D, color: Color) -> void:
	var liquid := (V2Assets.material("TankLiquid") as StandardMaterial3D).duplicate() as StandardMaterial3D
	liquid.albedo_color = Color(color.r, color.g, color.b, 0.45)
	liquid.emission = color * 0.8
	for n in room.find_children("TankLiquid*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			mi.set_surface_override_material(s, liquid)
	for n in room.find_children("TankLights*", "MeshInstance3D", true, false):
		var mi2 := n as MeshInstance3D
		for s in mi2.mesh.get_surface_count():
			var src := mi2.get_surface_override_material(s) as StandardMaterial3D
			if src != null:
				var lit := src.duplicate() as StandardMaterial3D
				lit.emission = color.lerp(Color.WHITE, 0.35)
				mi2.set_surface_override_material(s, lit)


func _prop(prop_name: String) -> Node3D:
	var n := (_props.find_child(prop_name, true, false) as Node3D).duplicate() as Node3D
	n.position = Vector3.ZERO
	return n


func _solid(parent: Node3D, size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	body.position = at
	parent.add_child(body)


func _crate(room: Node3D, at: Vector3, yaw: float, what: String) -> void:
	var node := _prop("Crate")
	room.add_child(node)
	node.position = at
	node.rotation_degrees.y = yaw
	_solid(node, Vector3(0.9, 0.58, 0.56), Vector3(0, 0.29, 0))
	crates.append({"node": node, "lid": node.find_child("Crate_Lid", true, false), "light": node.find_child("Crate_Light", true, false),
		"what": what, "open": false})


func _exit(room: Node3D, at: Vector3) -> void:
	var gate := _prop("ExitGate")
	room.add_child(gate)
	gate.position = at
	for sx in [-1.0, 1.0]:
		_solid(gate, Vector3(0.42, 2.8, 0.6), Vector3(sx * 1.06, 1.4, 0))
	_solid(gate, Vector3(2.5, 0.42, 0.6), Vector3(0, 2.61, 0))
	var spot := SpotLight3D.new()                          # the field lights the floor before it (a spot: the omnis are spoken for)
	spot.light_color = V2Ui.VIOLET
	spot.light_energy = 2.2
	spot.spot_range = 5.0
	spot.spot_angle = 70.0
	spot.position = Vector3(0, 2.2, -0.3)
	spot.rotation_degrees = Vector3(-60.0, 0, 0)
	spot.light_cull_mask = _layer(rooms.size() - 1)
	gate.add_child(spot)
	for side in [-1.0, 1.0]:                               # its sign (not in the heading font: that one has no X)
		var sign := Label3D.new()
		sign.text = "EXIT"
		sign.font_size = 96
		sign.pixel_size = 0.0022
		sign.modulate = Color(0.1, 0.04, 0.22)                 # (dark on the lit strip behind it)
		sign.outline_size = 0
		sign.position = Vector3(0, 2.61, side * 0.33)
		sign.rotation_degrees.y = 0.0 if side > 0.0 else 180.0
		gate.add_child(sign)
	_exit_at = room.position + at
	_exit_hum = V2Sfx.loop("exit_hum", gate)
	V2Sfx.drive(_exit_hum, true)


## The door between sector i and i + 1: two leaves in the passage that slide apart into the walls, a light over it.
func _door(i: int) -> void:
	var x := XR + 0.3
	var leaves: Array = []
	for side in [-1.0, 1.0]:
		var leaf := Node3D.new()
		leaf.position = Vector3(x, 0.0, DOOR_Z + side * DOOR_W / 4.0)
		rooms[i].add_child(leaf)
		var layer := _layer(i) | _layer(i + 1)
		# (painted white like the robots' armour: bare steel under the mezzanine came out as a black hole)
		_box(leaf, Vector3(-0.035, 0.01, -DOOR_W / 4.0), Vector3(0.035, DOOR_H - 0.02, DOOR_W / 4.0), "RArmor", layer)
		_box(leaf, Vector3(-0.04, 1.5, -DOOR_W / 4.0 + 0.12), Vector3(0.04, 1.86, DOOR_W / 4.0 - 0.12), "DarkGlass", layer)
		_box(leaf, Vector3(-0.045, 0.9, -DOOR_W / 4.0 + 0.04), Vector3(0.045, 1.02, DOOR_W / 4.0 - 0.04), "Hazard", layer)
		_box(leaf, Vector3(-0.042, 0.01, side * DOOR_W / 4.0 - side * 0.05), Vector3(0.042, DOOR_H - 0.02, side * DOOR_W / 4.0), "DarkSteel", layer)
		leaves.append(leaf)
	var lights: Array = []
	for dx in [-0.47, 0.47]:                                # one over the door on each side
		var lamp := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.03, 0.06, 0.5)
		lamp.mesh = box
		lamp.material_override = _lamp(V2Ui.RED if not LEVEL[i].robots.is_empty() else Color(1.0, 0.6, 0.15))
		lamp.position = Vector3(x + dx, DOOR_H + 0.18, DOOR_Z)
		lamp.layers = _layer(i) | _layer(i + 1)
		rooms[i].add_child(lamp)
		lights.append(lamp)
	doors.append({"leaves": leaves, "open": false, "lights": lights, "x": rooms[i].position.x + x, "locked": not LEVEL[i].robots.is_empty()})


func _lamp(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _lamps.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.02, 0.02, 0.02)
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 2.6
		_lamps[key] = m
	return _lamps[key]


## The door out of sector i is locked while a robot of that sector still works.
func _locks() -> void:
	for i in doors.size():
		var d: Dictionary = doors[i]
		var locked := alive_in(i) > 0
		if locked != bool(d.locked) and not d.open:
			d.locked = locked
			for lamp in d.lights:
				(lamp as MeshInstance3D).material_override = _lamp(V2Ui.RED if locked else Color(1.0, 0.6, 0.15))
			if not locked:
				V2Sfx.play("ui", Vector3(d.x, 2.0, DOOR_Z), 6.0)
				if i == current:
					say("Sector %s clear: the door is unlocked" % LEVEL[i].name)


# ---------------------------------------------------------------------------------------------- what the player does
## E: the door or the crate within reach that the player is nearest to.
func interact() -> void:
	if state != PLAYING:
		return
	var here := player.global_position
	var best := REACH
	var act := Callable()
	for i in doors.size():
		var d: Dictionary = doors[i]
		var dist := Vector2(here.x - float(d.x), here.z - DOOR_Z).length()
		if not d.open and dist < best:
			best = dist
			act = open_door.bind(i)
	for c in crates:
		var dist2 := here.distance_to((c.node as Node3D).global_position)
		if not c.open and dist2 < best:
			best = dist2
			act = open_crate.bind(c)
	if act.is_valid():
		act.call()


func open_door(i: int, force: bool = false) -> void:
	var d: Dictionary = doors[i]
	if d.open:
		return
	if alive_in(i) > 0 and not force:
		V2Sfx.play("dry", Vector3(d.x, 1.2, DOOR_Z), 4.0)
		say("Locked: %d hostile%s left in sector %s" % [alive_in(i), "" if alive_in(i) == 1 else "s", LEVEL[i].name])
		return
	d.open = true
	V2Sfx.play("door", Vector3(d.x, 1.2, DOOR_Z))
	for k in 2:
		var leaf := d.leaves[k] as Node3D
		var tw := create_tween()
		tw.tween_interval(0.12)
		tw.tween_property(leaf, "position:z", leaf.position.z + (-1.0 if k == 0 else 1.0) * (DOOR_W / 2.0 - 0.03), 0.55) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for lamp in d.lights:
		(lamp as MeshInstance3D).material_override = _lamp(V2Ui.GREEN)
	for r in robots:                                       # the robots beyond it hear it open
		if r.room == i + 1 and r.state != V2Robot.DEAD:
			r.alerted = true
	_rooms_shown()


func open_crate(c: Dictionary) -> void:
	if c.open:
		return
	c.open = true
	var node := c.node as Node3D
	V2Sfx.play("crate", node.global_position + Vector3(0, 0.4, 0))
	var tw := create_tween()
	tw.tween_property(c.lid as Node3D, "rotation_degrees:x", -105.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if c.light != null:
		(c.light as MeshInstance3D).set_surface_override_material(0, V2Assets.material("RFrame"))
	# what is in it rises out of it and is taken (or stays on the lid's edge if the player has no use for it)
	drop(String(c.what), node.global_position + Vector3(0, 0.62, 0), 0.5)


## A pickup at `at` (world), which the player takes by walking to it, after `delay` seconds.
func drop(what: String, at: Vector3, delay: float = 0.0) -> void:
	var node := _prop({"ammo": "AmmoBox", "health": "HealthCell", "kit": "MedKit"}[what])
	add_child(node)
	node.global_position = at
	_set_layer(node, _layer(_room_at(at.x)))
	pickups.append({"node": node, "what": what, "t": -delay, "y": at.y})


func _take(p: Dictionary) -> bool:
	var ok := false
	var note := ""
	match String(p.what):
		"ammo":
			ok = player.add_ammo(60)
			note = "Ammunition +60"
		"health":
			ok = player.add_health(35.0)
			note = "Health +35"
		"kit":
			ok = player.add_kit()
			note = "Med kit (H)"
	if ok:
		V2Sfx.play("pickup")
		say(note)
	return ok


func say(text: String) -> void:
	if _note_text != null:
		_note_text.text = text
		_note_t = 2.2


func _on_destroyed(robot: V2Robot) -> void:
	kills += 1
	score += SCORE[robot.kind]
	if randf() < DROP:
		var at := robot.global_position
		drop(DROPS[randi() % DROPS.size()], Vector3(at.x + randf_range(-0.5, 0.5), 0.05, at.z + randf_range(-0.5, 0.5)), 2.5 if robot.kind == "drone" else 1.0)


func _on_died() -> void:
	finish(false)


func finish(won: bool) -> void:
	if state != PLAYING:
		return
	state = WON if won else LOST
	if won:
		V2Sfx.play("exit")
		player.invulnerable = true
		score += maxi(0, 300 - int(elapsed))               # a bonus for speed
	_end_screen()
	if _bot == null:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.mouse_look = false


func alive() -> int:
	var n := 0
	for r in robots:
		if r.state != V2Robot.DEAD:
			n += 1
	return n


func alive_in(sector: int) -> int:
	var n := 0
	for r in robots:
		if r.state != V2Robot.DEAD and r.room == sector:
			n += 1
	return n


# ---------------------------------------------------------------------------------------------- every frame
## Which rooms are drawn and whose robots are awake: the player's, and a neighbour whose door is open.
func _rooms_shown() -> void:
	for i in rooms.size():
		var near := i == current or (absi(i - current) == 1 and bool(doors[mini(i, current)].open))
		rooms[i].visible = near
	for r in robots:
		r.active = r.room == current or (absi(r.room - current) == 1 and bool(doors[mini(r.room, current)].open))


func _process(delta: float) -> void:
	if player == null:
		return
	var room := _room_at(player.global_position.x)
	if room != current or not _seen.has(room):
		current = room
		if not _seen.has(room):                            # a sector entered for the first time is announced
			_banner.text = "SECTOR %s" % LEVEL[room].name
			_banner_t = 2.6
		_seen[room] = true
		_rooms_shown()
	_gun_lights(current)
	if state == PLAYING:
		elapsed += delta
		if _exit_at != Vector3.INF:
			var d := player.global_position - _exit_at
			if absf(d.x) < 0.8 and absf(d.z) < 0.45:
				finish(true)
		_chase_t -= delta
		if _chase_t <= 0.0:
			_chase_t = 0.5
			_rooms_shown()
			_locks()
			_chase()
	_pickups(delta)
	_hud_update(delta)


## A drone that has seen the player and lost them goes after them into the next sector, if the door is open.
func _chase() -> void:
	for r in robots:
		if r.kind != "drone" or r.state != V2Robot.ROAM or not r.alerted or r.room == current:
			continue
		var way := signi(current - r.room)
		if bool(doors[mini(r.room, r.room + way)].open):
			r.travel(way)


func _pickups(delta: float) -> void:
	for p in pickups.duplicate():
		var node := p.node as Node3D
		p.t += delta
		if p.t < 0.0:
			node.visible = false
			continue
		node.visible = true
		node.rotation.y += delta * 1.4
		node.position.y = float(p.y) + 0.08 + 0.05 * sin(float(p.t) * 3.0)
		var flat := Vector2(player.global_position.x - node.global_position.x, player.global_position.z - node.global_position.z)
		if state == PLAYING and flat.length() < 1.1 and float(p.t) > 0.25 and _take(p):
			pickups.erase(p)
			node.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_perf.visible = not _perf.visible
		_perf.text = "measuring ..."
		_perf_t = 0.0
		_perf_n = 0


# ---------------------------------------------------------------------------------------------- HUD and screens
func _hud() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)
	_low_hp = V2Ui.full(_ui, Color(0.8, 0.05, 0.02, 0.0))
	_flash = V2Ui.full(_ui, Color(1.0, 0.1, 0.05, 0.0))
	_dot = V2Ui.rect(_ui, Color(1, 1, 1, 0.9), 0.0, 0.0, 0, 0, 4, 4)
	V2Ui.label(_ui, "HEALTH", 0.0, 1.0, 26.0, -62.0, 13, Color(0.7, 0.8, 0.86))
	V2Ui.rect(_ui, Color(0, 0, 0, 0.55), 0.0, 1.0, 24.0, -42.0, 244.0, 18.0)
	_hp_fill = V2Ui.rect(_ui, V2Ui.GREEN, 0.0, 1.0, 26.0, -40.0, 240.0, 14.0)
	_hp_text = V2Ui.label(_ui, "100", 0.0, 1.0, 278.0, -46.0, 18)
	_kits_text = V2Ui.label(_ui, "", 0.0, 1.0, 26.0, -88.0, 14, V2Ui.GREEN)
	_gun_text = V2Ui.label(_ui, "", 1.0, 1.0, -26.0, -88.0, 14, Color(0.7, 0.8, 0.86), false, HORIZONTAL_ALIGNMENT_RIGHT)
	_ammo_text = V2Ui.label(_ui, "", 1.0, 1.0, -26.0, -66.0, 34, Color(0.95, 0.98, 1.0), false, HORIZONTAL_ALIGNMENT_RIGHT)
	_goal_text = V2Ui.label(_ui, "", 0.0, 0.0, 26.0, 20.0, 15, V2Ui.CYAN)
	_note_text = V2Ui.label(_ui, "", 0.5, 1.0, 0.0, -150.0, 17, Color(0.95, 0.98, 1.0), false, HORIZONTAL_ALIGNMENT_CENTER)
	_banner = V2Ui.label(_ui, "", 0.5, 0.0, 0.0, 90.0, 40, Color(0.95, 0.98, 1.0), true, HORIZONTAL_ALIGNMENT_CENTER)
	# where a hit came from: ahead, right, behind, left
	for spec in [[0.5, 0.5, -90.0, -150.0, 180.0, 6.0], [0.5, 0.5, 150.0, -90.0, 6.0, 180.0], [0.5, 0.5, -90.0, 144.0, 180.0, 6.0], [0.5, 0.5, -156.0, -90.0, 6.0, 180.0]]:
		var bar := V2Ui.rect(_ui, Color(1.0, 0.2, 0.12, 0.0), spec[0], spec[1], spec[2], spec[3], spec[4], spec[5])
		_from_bars.append(bar)
	_perf = V2Ui.label(_ui, "", 0.0, 0.0, 26.0, 46.0, 14, Color(1.0, 0.9, 0.5))
	_perf.visible = false
	# Esc: the mouse is free; the way back
	_menu = Control.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.visible = false
	_ui.add_child(_menu)
	V2Ui.rect(_menu, Color(0.02, 0.03, 0.045, 0.8), 0.5, 0.5, -180.0, -110.0, 360.0, 200.0)
	V2Ui.label(_menu, "The game goes on: there is no pause.", 0.5, 0.5, 0.0, -96.0, 13, Color(0.7, 0.78, 0.84), false, HORIZONTAL_ALIGNMENT_CENTER)
	V2Ui.button(_menu, "RESUME", 0.5, 0.5, 0.0, -60.0, func() -> void: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	V2Ui.button(_menu, "TITLE", 0.5, 0.5, 0.0, 4.0, func() -> void: get_tree().change_scene_to_file(TITLE))


func _hud_update(delta: float) -> void:
	var size := get_viewport().get_visible_rect().size
	_hp_fill.offset_right = _hp_fill.offset_left + 240.0 * player.hp / V2Player.MAX_HP
	_hp_fill.color = V2Ui.GREEN if player.hp > 35.0 else V2Ui.RED
	_hp_text.text = "%d" % int(ceil(player.hp))
	_kits_text.text = ("MED KITS  %d   (H)" % player.kits) if player.kits > 0 else ""
	_gun_text.text = "MACHINE GUN" if player.weapon == "rifle" else "PISTOL"
	_ammo_text.text = ("%d / %d" % [player.mag.rifle, player.reserve]) if player.weapon == "rifle" else ("%d" % player.mag.pistol)
	_ammo_text.add_theme_color_override("font_color", V2Ui.RED if player.mag[player.weapon] <= 3 else Color(0.95, 0.98, 1.0))
	var here := alive_in(current)
	_goal_text.text = "SECTOR %s   ·   %s   ·   find the exit gate" % [LEVEL[current].name, ("%d hostile%s" % [here, "" if here == 1 else "s"]) if here > 0 else "clear"]
	_note_t -= delta
	_banner_t -= delta
	_banner.modulate.a = clampf(_banner_t, 0.0, 1.0) * clampf((2.6 - _banner_t) * 4.0, 0.0, 1.0)
	_note_text.modulate.a = clampf(_note_t, 0.0, 1.0)
	_flash.color.a = player.hurt_flash * 0.3
	var to := player.hurt_from - player.global_position
	var side := wrapi(int(round(angle_difference(player._yaw, atan2(-to.x, -to.z)) / (-PI / 2.0))), 0, 4)      # 0 ahead, 1 right, 2 behind, 3 left
	for k in 4:
		(_from_bars[k] as ColorRect).color.a = player.hurt_flash * 0.75 if (k == side and state == PLAYING) else 0.0
	if _perf.visible:
		_perf_t += delta
		_perf_n += 1
		if _perf_t >= 1.0:
			_perf.text = "%.0f fps (%.1f ms)   draw calls %d   triangles %dk   video memory %.0f MB   F3 hides this" % [_perf_n / _perf_t, 1000.0 * _perf_t / _perf_n,
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0,
				Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0]
			_perf_t = 0.0
			_perf_n = 0
	_low_hp.color.a = clampf((35.0 - player.hp) / 35.0, 0.0, 1.0) * (0.1 + 0.05 * sin(elapsed * 5.0)) if state == PLAYING else 0.0
	var dot := player.aim_dot if player.weapon in V2Player.AUTO else size / 2.0
	_dot.visible = state == PLAYING and dot.x >= 0.0 and not (player.busy in V2Player.NO_CURSOR)
	_dot.position = dot - Vector2(2, 2)
	_dot.color = Color(1.0, 0.25, 0.15) if player.hit_confirm > 0.0 else Color(1, 1, 1, 0.9)
	_menu.visible = state == PLAYING and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and _bot == null


func _end_screen() -> void:
	_end = Control.new()
	_end.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_end)
	var won := state == WON
	V2Ui.full(_end, Color(0.02, 0.03, 0.045, 0.78))
	V2Ui.label(_end, "MISSION COMPLETE" if won else "MISSION FAILED", 0.5, 0.5, 0.0, -170.0, 44, V2Ui.VIOLET if won else V2Ui.RED, true, HORIZONTAL_ALIGNMENT_CENTER)
	V2Ui.label(_end, "You reached the exit gate." if won else "You went down in sector %s." % LEVEL[current].name, 0.5, 0.5, 0.0, -108.0, 17,
		Color(0.8, 0.86, 0.9), false, HORIZONTAL_ALIGNMENT_CENTER)
	var lines := "Score  %d\nRobots destroyed  %d of %d\nSectors seen  %d of %d\nTime  %d:%02d" % [score, kills, robots.size(), _seen.size(), LEVEL.size(),
		int(elapsed) / 60, int(elapsed) % 60]
	V2Ui.label(_end, lines, 0.5, 0.5, 0.0, -66.0, 18, Color(0.95, 0.98, 1.0), false, HORIZONTAL_ALIGNMENT_CENTER)
	V2Ui.button(_end, "AGAIN", 0.5, 0.5, -150.0, 70.0, func() -> void: get_tree().reload_current_scene())
	V2Ui.button(_end, "TITLE", 0.5, 0.5, 150.0, 70.0, func() -> void: get_tree().change_scene_to_file(TITLE))
