extends Node
## Game flow: title -> run -> end screen -> run (harder) ...
##
## Command-line (after `--`):
##   --seed=N        first dungeon uses seed N (later runs use N+1, N+2, ...)
##   --autostart     skip the title screen
##   --capture=DIR   run the capture tour (scripts/capture.gd) and quit
##   --greybox       build with greybox boxes instead of the Blender kit
##   (no args)       test room: one room, frozen targets, invulnerable (polish phase default)
##   --game          title screen + full dungeon runs
##   --lab           with --capture: the test-room capture tour
##   --perf          log FPS, draw calls, objects and triangles every 2 s (web: ?perf=1)
## In the browser the same options come from the URL query: ?seed=N&autostart=1

const NEON_CYAN := Color("#22E5FF")

var args: Dictionary = {}
var base_seed := 0
var run_index := 0
## Missions completed this session; raises difficulty. Nothing is saved, so it
## resets when the game is reloaded.
var difficulty := 0

var state := "title"
var world: Node3D
var layout: DungeonGen
var player: Player
var ui: GameUI

## Lights further than this beyond their own range are hidden. The Compatibility
## renderer has a global cap on renderable lights and every live light costs on the web.
const LIGHT_CULL_MARGIN := 10.0
var light_cull_enabled := true
var _cull_timer := 0.0

## Hostile toughness per completed mission (numbers grow in DungeonGen).
const HP_PER_DIFFICULTY := 0.2
const DROP_CHANCE := 0.35
var ENEMY_SCRIPTS := {"turret": Turret, "brawler": Brawler, "pursuer": Pursuer}

## Tests can turn enemies off (traversal bot) before start_run().
var enemies_enabled := true
## Test room mode (see start_lab).
var lab := false
var drop_rng := RandomNumberGenerator.new()
## Door edges that are still closed: [cell_a, cell_b] both ways -> Door. Enemy pathing avoids them.
var closed_edges: Dictionary = {}

# Run stats
var kills := 0
var score := 0
var visited: Dictionary = {}
## Every floor cell the player has stood in (rooms and corridors), for the map.
var visited_cells: Dictionary = {}
## Exit portal seen (clear line to it) or its room entered.
var exit_found := false
## Walking distance to the portal in metres (grid path), refreshed a few times a second.
var exit_distance := 0.0
var _exit_timer := 0.0
var kills_by_type := {"turret": 0, "brawler": 0, "pursuer": 0}


func set_paused(on: bool) -> void:
	get_tree().paused = on
	ui.show_pause(on)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED
	if not on and player:
		player.hold_look()


func _ready() -> void:
	# Main keeps running while paused (input, UI); the world below it is pausable.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	args = _parse_args()
	base_seed = int(args.seed) if args.has("seed") else int(Time.get_unix_time_from_system()) % 1000000
	ui = GameUI.new()
	ui.name = "UI"
	add_child(ui)
	ui.start_pressed.connect(func(): Sfx.play("ui"); start_run())
	ui.again_pressed.connect(func(): Sfx.play("ui"); start_run())
	ui.resume_pressed.connect(func(): set_paused(false))
	ui.quit_pressed.connect(func(): get_tree().quit())
	_setup_environment()
	if args.has("capture"):
		var cap := CaptureTour.new()
		cap.name = "CaptureTour"
		add_child(cap)
		if args.has("poses"):
			cap.run_poses(self, args.capture, args.poses)
		elif args.has("lab"):
			cap.run_lab(self, args.capture)
		else:
			cap.run(self, args.capture)
	elif args.has("autostart"):
		start_run()
	elif args.has("game"):
		ui.show_title()
	else:
		# Polish phase: pressing Play opens the one-room test room. `--game` (or ?game=1 on the
		# web) restores the title screen and full dungeon runs.
		start_lab()


func current_seed() -> int:
	return base_seed + run_index


## Test room (`--lab` / `?lab=1`): one room, the three enemies frozen as targets, player invulnerable.
func start_lab() -> void:
	lab = true
	_begin(DungeonGen.new().generate_lab(current_seed()))
	player.invulnerable = true
	var c := DungeonGen.cell_center
	for spec in [["turret", Vector2i(0, 1)], ["brawler", Vector2i(2, 1)], ["pursuer", Vector2i(4, 1)]]:
		_lab_target(spec[0], c.call(spec[1]))
	await get_tree().process_frame
	for e in get_tree().get_nodes_in_group("hostiles"):
		e.face_player_now()


## A frozen lab target; when killed, its wreck stays and a new one appears 1.5 m to the side
## after 3 s (the previous wreck at that spot, if any, is cleared first).
func _lab_target(kind: String, pos: Vector3, offset: int = 0) -> void:
	var e := spawn_enemy(kind, pos + Vector3(1.5 * (offset % 2), 0, 0), 0)
	e.frozen = true
	e.died.connect(func(_e):
		await get_tree().create_timer(3.0).timeout
		if lab and state == "playing":
			var target := _lab_target_spot(pos, offset + 1)
			for wreck in get_tree().get_nodes_in_group("wrecks"):
				if is_instance_valid(wreck) and Vector2(wreck.global_position.x - target.x, wreck.global_position.z - target.z).length() < 0.8:
					wreck.queue_free()
			_lab_target(kind, pos, offset + 1)
			for h in get_tree().get_nodes_in_group("hostiles"):
				if not h.dead:
					h.face_player_now())


func _lab_target_spot(pos: Vector3, offset: int) -> Vector3:
	return pos + Vector3(1.5 * (offset % 2), 0, 0)


func start_run() -> void:
	lab = false
	_begin(DungeonGen.new().generate(current_seed(), difficulty))


func _begin(p_layout: DungeonGen) -> void:
	_clear_world()
	layout = p_layout
	world = DungeonBuilder.new(KitGreybox.new() if args.has("greybox") else null).build(layout)
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	var portal: ExitPortal = world.get_node("ExitPortal")
	portal.reached.connect(func(): end_run(true))

	player = Player.new()
	player.name = "Player"
	world.add_child(player)
	player.global_position = layout.player_spawn
	player.rotation.y = layout.player_yaw
	player.died.connect(func(): end_run(false))
	player.damaged.connect(func(_a): ui.flash_damage())
	player.weapons.hit_hostile.connect(func(killed): ui.hit_marker(killed))

	kills = 0
	score = 0
	visited = {}
	visited_cells = {}
	exit_found = false
	exit_distance = _path_metres(DungeonGen.world_to_cell(layout.player_spawn), DungeonGen.world_to_cell(layout.exit_pos))
	kills_by_type = {"turret": 0, "brawler": 0, "pursuer": 0}
	drop_rng.seed = hash(current_seed() * 31 + 7)
	_index_doors()
	if enemies_enabled and not lab:
		spawn_enemies()
	spawn_crates()
	Sfx.start_ambience()
	state = "playing"
	ui.show_hud()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("[run] seed=%d difficulty=%d rooms=%d" % [current_seed(), difficulty, layout.rooms.size()])


func end_run(success: bool) -> void:
	if state != "playing":
		return
	state = "ended"
	player.input_enabled = false
	Sfx.stop_ambience()
	Sfx.play("win" if success else "lose")
	for e in get_tree().get_nodes_in_group("hostiles"):
		e.frozen = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.show_end(success, score, kills, visited.size(), layout.rooms.size(), difficulty)
	if success:
		difficulty += 1
	run_index += 1


func _clear_world() -> void:
	if world:
		world.queue_free()
		remove_child(world)
		world = null
		player = null


var _perf_t := 0.0


func _perf_log(delta: float) -> void:
	_perf_t += delta
	if _perf_t < 2.0:
		return
	_perf_t = 0.0
	var rs := RenderingServer
	print("[perf] fps=%d draw_calls=%d objects=%d primitives=%d lights=%d" % [
		Engine.get_frames_per_second(),
		rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		get_tree().get_nodes_in_group("culled_lights").filter(func(l): return l.visible).size()
			+ world.get_node("Lights").get_children().filter(func(l): return l.visible).size()])


func _process(_delta: float) -> void:
	if args.has("perf") and state == "playing":
		_perf_log(_delta)
	if state != "playing" or player == null:
		return
	var pc := DungeonGen.world_to_cell(player.global_position)
	var r := layout.room_at(pc)
	if r >= 0 and not visited.has(r):
		visited[r] = true
	if layout.is_floor(pc):
		visited_cells[pc] = true
	_exit_timer -= _delta
	if _exit_timer <= 0.0:
		_exit_timer = 0.25
		if layout.is_floor(pc):
			exit_distance = _path_metres(pc, DungeonGen.world_to_cell(layout.exit_pos))
		if not exit_found:
			exit_found = r == layout.exit_room or _sees_portal()
	ui.update_hud(self)
	_cull_timer -= _delta
	if _cull_timer <= 0.0:
		_cull_timer = 0.15
		cull_lights()


func spawn_enemies() -> void:
	var holder := Node3D.new()
	holder.name = "Enemies"
	world.add_child(holder)
	var mult := 1.0 + HP_PER_DIFFICULTY * difficulty
	for sp in layout.enemy_spawns:
		var e: Enemy = ENEMY_SCRIPTS[sp.type].new()
		e.setup(self, sp.room, mult)
		e.position = sp.pos
		e.rotation.y = randf() * TAU
		e.died.connect(_on_enemy_died)
		holder.add_child(e)


func spawn_crates() -> void:
	var holder := Node3D.new()
	holder.name = "Crates"
	world.add_child(holder)
	for l in layout.loot_spawns:
		var c := LootCrate.new()
		c.payoff = l.payoff
		c.main = self
		c.position = l.pos
		c.rotation.y = l.yaw
		holder.add_child(c)


func spawn_enemy(kind: String, pos: Vector3, room: int = -1) -> Enemy:
	var e: Enemy = ENEMY_SCRIPTS[kind].new()
	e.setup(self, room, 1.0 + HP_PER_DIFFICULTY * difficulty)
	e.position = pos
	e.died.connect(_on_enemy_died)
	var holder := world.get_node_or_null("Enemies")
	if holder == null:
		holder = Node3D.new()
		holder.name = "Enemies"
		world.add_child(holder)
	holder.add_child(e)
	return e


func _on_enemy_died(e: Enemy) -> void:
	kills += 1
	score += e.score_value
	kills_by_type[e.kind] += 1
	if drop_rng.randf() < DROP_CHANCE:
		spawn_pickup(roll_payoff(drop_rng), Vector3(e.global_position.x, 0, e.global_position.z))


## Payoff table shared by drops (and containers in step 6): kits thin with difficulty.
func roll_payoff(rng: RandomNumberGenerator) -> String:
	var kit_w := maxi(1, 4 - difficulty)
	var weights := [kit_w, 4, 3]
	var roll := rng.randi_range(1, kit_w + 7)
	for i in 3:
		roll -= weights[i]
		if roll <= 0:
			return DungeonGen.LOOT_PAYOFFS[i]
	return "health"


func spawn_pickup(payoff: String, pos: Vector3) -> Pickup:
	var p := Pickup.new()
	p.payoff = payoff
	p.position = pos
	world.add_child(p)
	return p


func hostiles_alive() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("hostiles"):
		if not e.dead:
			n += 1
	return n


func _index_doors() -> void:
	closed_edges = {}
	for door: Door in world.get_node("Doors").get_children():
		var a: Vector2i = door.get_meta("room_cell")
		var b: Vector2i = door.get_meta("corr_cell")
		closed_edges[[a, b]] = door
		closed_edges[[b, a]] = door
		door.opened.connect(func():
			closed_edges.erase([a, b])
			closed_edges.erase([b, a])
			Sfx.play_at("door", door.global_position + Vector3.UP * 1.5))


## Next cell on a shortest floor path from `from` to `to`, not crossing closed doors.
## Returns `from` when already there or unreachable.
func nav_next_cell(from: Vector2i, to: Vector2i) -> Vector2i:
	if from == to or not layout.is_floor(from) or not layout.is_floor(to):
		return from
	var prev := {from: from}
	var q: Array[Vector2i] = [from]
	var found := false
	while q.size() > 0:
		var c: Vector2i = q.pop_front()
		if c == to:
			found = true
			break
		for d in DungeonGen.DIRS:
			var n: Vector2i = c + d
			if prev.has(n) or not layout.is_floor(n) or closed_edges.has([c, n]):
				continue
			prev[n] = c
			q.append(n)
	if not found:
		return from
	var c := to
	while prev[c] != from:
		c = prev[c]
	return c


func _path_metres(from: Vector2i, to: Vector2i) -> float:
	## Grid walking distance (doors count as passable: they can be opened).
	if not layout.is_floor(from):
		return exit_distance
	var dist := {from: 0}
	var q: Array[Vector2i] = [from]
	while q.size() > 0:
		var c: Vector2i = q.pop_front()
		if c == to:
			return dist[c] * DungeonGen.CELL
		for d in DungeonGen.DIRS:
			var n: Vector2i = c + d
			if layout.is_floor(n) and not dist.has(n):
				dist[n] = dist[c] + 1
				q.append(n)
	return 0.0


func _sees_portal() -> bool:
	var eye := player.camera.global_position
	var target := layout.exit_pos + Vector3.UP * 1.4
	if eye.distance_to(target) > 40.0:
		return false
	var q := PhysicsRayQueryParameters3D.create(eye, target, Layers.WORLD)
	return player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Living hostiles per room, by where they are now (pursuers and brawlers roam).
func hostiles_by_room() -> Dictionary:
	var out := {}
	for e in get_tree().get_nodes_in_group("hostiles"):
		if e.dead:
			continue
		var r := layout.room_at(DungeonGen.world_to_cell(e.global_position))
		if r >= 0:
			out[r] = out.get(r, 0) + 1
	return out


## True when the centre of the screen is on a hostile with nothing in between.
func crosshair_on_hostile() -> bool:
	var cam := player.camera
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_transform.basis.z * 60.0, Layers.WORLD | Layers.HOSTILE)
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit.collider is Enemy


func cull_lights() -> void:
	var lights := world.get_node_or_null("Lights")
	if lights == null:
		return
	var eye := player.global_position
	for l: OmniLight3D in lights.get_children():
		l.visible = not light_cull_enabled or l.global_position.distance_to(eye) < l.omni_range + LIGHT_CULL_MARGIN
	for l: OmniLight3D in get_tree().get_nodes_in_group("culled_lights"):
		l.visible = not light_cull_enabled or l.global_position.distance_to(eye) < l.omni_range + LIGHT_CULL_MARGIN


func _input(event: InputEvent) -> void:
	# Lab only (the GDD game has no pause): Esc pauses and frees the mouse.
	if lab and state == "playing" and event.is_action_pressed("pause"):
		set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
		return
	if get_tree().paused:
		return
	# Browsers release pointer lock on Esc; a click while playing takes it back.
	if state == "playing" and event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if player:
			player.hold_look()
		get_viewport().set_input_as_handled()


func _setup_environment() -> void:
	## Lighting / post: dark background, cool ambient fill, a dim sky used only for
	## metal reflections, depth fog, ACES tonemap and HDR glow so neon blooms.
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.01, 0.016)
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.1, 0.16, 0.2)
	sm.sky_horizon_color = Color(0.25, 0.32, 0.38)
	sm.ground_bottom_color = Color(0.03, 0.035, 0.04)
	sm.ground_horizon_color = Color(0.2, 0.26, 0.3)
	sm.sun_angle_max = 0.0
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.72)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_strength = 1.0
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.3
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.06, 0.08)
	env.fog_density = 0.006
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.05
	we.environment = env
	add_child(we)


func _parse_args() -> Dictionary:
	var out := {}
	var list := OS.get_cmdline_user_args()
	for a in list:
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		if typeof(q) == TYPE_STRING and q.length() > 1:
			for pair in q.substr(1).split("&"):
				var kv: PackedStringArray = pair.split("=", true, 1)
				out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out


static func _setup_input() -> void:
	var keys := {
		"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
		"reload": KEY_R, "interact": KEY_E, "use_kit": KEY_Q,
		"weapon_1": KEY_1, "weapon_2": KEY_2, "map": KEY_TAB,
		"sprint": KEY_SHIFT, "jump": KEY_SPACE, "pause": KEY_ESCAPE,
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.physical_keycode = keys[action]
			InputMap.action_add_event(action, ev)
	# Crouch: Cmd (Mac), Ctrl or C.
	if not InputMap.has_action("crouch"):
		InputMap.add_action("crouch")
		for k in [KEY_META, KEY_CTRL, KEY_C]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event("crouch", ev)
	var mouse := {"fire": MOUSE_BUTTON_LEFT, "aim": MOUSE_BUTTON_RIGHT}
	for action in mouse:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventMouseButton.new()
			ev.button_index = mouse[action]
			InputMap.action_add_event(action, ev)
