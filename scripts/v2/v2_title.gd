extends V2World
## The title: PLAY starts the game's level (scenes/v2_game.tscn), LAB opens the test lab (scenes/v2_lab.tscn: the
## three studio rooms with one robot each, for looking at the animations). Behind the menu: one room of the level.
## Command-line options meant for the lab or the game skip the menu:
##   -- --lab, --enemy-test, --gun-test, --input-test, --capture=DIR, --perf, --preview, --concept   -> the lab
##   -- --play, --game-test, --bot[=N], --game-capture=DIR                                          -> the game
##   -- --v1                                                                                        -> the V1 game
const LAB := "res://scenes/v2_lab.tscn"
const GAME := "res://scenes/v2_game.tscn"
const LAB_ARGS := ["--lab", "--enemy-test", "--gun-test", "--input-test", "--perf", "--preview", "--concept", "--doors", "--quick"]
const GAME_ARGS := ["--play", "--game-test"]

var _cam: Camera3D
var _t := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var to := ""
	if "--v1" in args:
		to = "res://scenes/main.tscn"
	for a in args:
		if a in LAB_ARGS or a.begins_with("--capture=") or a.begins_with("--only="):
			to = LAB
		elif a in GAME_ARGS or a.begins_with("--game-capture=") or a.begins_with("--bot"):
			to = GAME
	if to != "" and not ("--title" in args):
		get_tree().change_scene_to_file.call_deferred(to)
		return
	V2Fx.root = self
	V2Fx.reset()
	V2Sfx.root = self
	V2Sfx.enabled = not ("--no-sound" in args)
	_low = "--quality=low" in args
	_concept = true
	_environment()
	var room := _room_shell(0, "Room")
	var robot := V2Robot.new()
	room.add_child(robot)
	robot.setup("spider")
	robot.set_ai(false)
	robot.auto = false
	robot.play("Idle")
	robot._label.visible = false
	_set_layer(room, _layer(0))
	_cam = Camera3D.new()
	_cam.fov = 62.0
	add_child(_cam)
	_cam.make_current()
	_menu()
	V2Sfx.ambience("room_tone")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for a in args:
		if a.begins_with("--title-capture="):
			_shot(a.trim_prefix("--title-capture="))


func _menu() -> void:
	var ui := CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	V2Ui.rect(ui, Color(0.02, 0.03, 0.045, 0.72), 0.0, 0.0, 0.0, 0.0, 520.0, 4000.0)
	V2Ui.rect(ui, V2Ui.CYAN, 0.0, 0.0, 520.0, 0.0, 2.0, 4000.0)
	V2Ui.label(ui, "PROJECT", 0.0, 0.0, 60.0, 90.0, 30, V2Ui.CYAN, true)
	V2Ui.label(ui, "FIREWALL", 0.0, 0.0, 60.0, 124.0, 58, Color(0.95, 0.98, 1.0), true)
	V2Ui.label(ui, "One level. Find the exit gate.", 0.0, 0.0, 62.0, 204.0, 17, Color(0.72, 0.8, 0.86))
	V2Ui.button(ui, "PLAY", 0.0, 0.0, 200.0, 270.0, func() -> void: get_tree().change_scene_to_file(GAME), 280.0)
	V2Ui.button(ui, "LAB", 0.0, 0.0, 200.0, 334.0, func() -> void: get_tree().change_scene_to_file(LAB), 280.0)
	V2Ui.button(ui, "QUIT", 0.0, 0.0, 200.0, 398.0, func() -> void: get_tree().quit(), 280.0)
	V2Ui.label(ui, "PLAY: the level, four sectors, to the exit gate.\nLAB: three test rooms, one robot each, to try the guns and\nwatch the animations (M: clip preview, N: next clip).",
		0.0, 0.0, 62.0, 470.0, 14, Color(0.62, 0.7, 0.76))
	V2Ui.label(ui, "WASD move  ·  mouse look  ·  LMB fire  ·  C or RMB aim  ·  R reload\nQ or 1 / 2 switch gun  ·  E open  ·  H med kit  ·  Shift sprint\nX crouch  ·  Space jump  ·  Esc menu",
		0.0, 1.0, 62.0, -96.0, 14, Color(0.62, 0.7, 0.76))


func _process(delta: float) -> void:
	if _cam == null:
		return
	_t += delta
	# the camera drifts across the room's front, looking at the robot in the middle of the hall
	var at := Vector3(1.0 + sin(_t * 0.11) * 2.2, 1.5 + sin(_t * 0.17) * 0.12, 1.4)
	_cam.look_at_from_position(at, Vector3(-0.6, 1.0, -5.5), Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_P]:
			get_tree().change_scene_to_file(GAME)
		elif event.keycode == KEY_L:
			get_tree().change_scene_to_file(LAB)


func _shot(path: String) -> void:
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[title] ", path)
	get_tree().quit()
