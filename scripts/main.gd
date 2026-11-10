extends Node
## Game flow: title -> run -> end screen -> run (harder) ...
##
## Command-line (after `--`):
##   --seed=N        first dungeon uses seed N (later runs use N+1, N+2, ...)
##   --autostart     skip the title screen
##   --capture=DIR   run the capture tour (scripts/capture.gd) and quit
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

# Run stats
var kills := 0
var score := 0
var visited: Dictionary = {}


func _ready() -> void:
	_setup_input()
	args = _parse_args()
	base_seed = int(args.seed) if args.has("seed") else int(Time.get_unix_time_from_system()) % 1000000
	ui = GameUI.new()
	ui.name = "UI"
	add_child(ui)
	ui.start_pressed.connect(start_run)
	ui.again_pressed.connect(start_run)
	_setup_environment()
	if args.has("capture"):
		var cap := CaptureTour.new()
		cap.name = "CaptureTour"
		add_child(cap)
		cap.run(self, args.capture)
	elif args.has("autostart"):
		start_run()
	else:
		ui.show_title()


func current_seed() -> int:
	return base_seed + run_index


func start_run() -> void:
	_clear_world()
	layout = DungeonGen.new().generate(current_seed(), difficulty)
	world = DungeonBuilder.new().build(layout)
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

	kills = 0
	score = 0
	visited = {}
	state = "playing"
	ui.show_hud()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("[run] seed=%d difficulty=%d rooms=%d" % [current_seed(), difficulty, layout.rooms.size()])


func end_run(success: bool) -> void:
	if state != "playing":
		return
	state = "ended"
	player.input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.show_end(success, score, kills, visited.size(), layout.rooms.size())
	if success:
		difficulty += 1
	run_index += 1


func _clear_world() -> void:
	if world:
		world.queue_free()
		remove_child(world)
		world = null
		player = null


func _process(_delta: float) -> void:
	if state != "playing" or player == null:
		return
	var r := layout.room_at(DungeonGen.world_to_cell(player.global_position))
	if r >= 0 and not visited.has(r):
		visited[r] = true
	ui.update_hud(self)


func _input(event: InputEvent) -> void:
	# Browsers release pointer lock on Esc; a click while playing takes it back.
	if state == "playing" and event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _setup_environment() -> void:
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.012, 0.018)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.42, 0.5)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.9
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
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.physical_keycode = keys[action]
			InputMap.action_add_event(action, ev)
	var mouse := {"fire": MOUSE_BUTTON_LEFT, "aim": MOUSE_BUTTON_RIGHT}
	for action in mouse:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventMouseButton.new()
			ev.button_index = mouse[action]
			InputMap.action_add_event(action, ev)
