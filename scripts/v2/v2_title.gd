extends V2World
## The title, after the UI concept (v2/reference/ui/screens/Main.png): a white page, PROJECT / FIREWALL, a cyan
## bar, PRESS ENTER pulsing. Nothing else: no menu. Enter, any other key or a click starts a run
## (scenes/v2_game.tscn). Not on the page, for whoever works on the game: L opens the test lab
## (scenes/v2_lab.tscn: three studio rooms with one robot each); Backspace there comes back here.
## Command-line options meant for the lab or the game skip the title:
##   -- --lab, --enemy-test, --gun-test, --input-test, --capture=DIR, --perf, --preview, --concept   -> the lab
##   -- --play, --game-test, --bot[=N], --game-capture=DIR                                          -> the game
##   -- --v1                                                                                        -> the V1 game
const LAB := "res://scenes/v2_lab.tscn"
const GAME := "res://scenes/v2_game.tscn"
const LAB_ARGS := ["--lab", "--enemy-test", "--gun-test", "--input-test", "--perf", "--preview", "--concept", "--doors", "--quick"]
const GAME_ARGS := ["--play", "--game-test", "--training", "--no-training", "--training-test"]

var _press: Label
var _leaving := false
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
	V2Robot.no_go = []
	V2Sfx.root = self
	V2Sfx.enabled = not ("--no-sound" in args)
	_render_setup()
	_page()
	V2Music.enabled = V2Sfx.enabled
	V2Music.start(get_tree())                              # (the menu has music; the game only its own sounds)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	V2World.preload_run(get_tree(), func() -> bool: return _leaving or not is_inside_tree())
	for a in args:
		if a.begins_with("--title-capture="):
			_shot(a.trim_prefix("--title-capture="))
		if a.begins_with("--open-capture="):               # the way into a run, frame by frame (the game goes on with it)
			# (filmed from the tree's root, so that the frames between the two scenes are in it too)
			V2World.film(get_tree().root, a.trim_prefix("--open-capture="), "title", 9.0)
			get_tree().create_timer(1.2).timeout.connect(_start)


func _page() -> void:
	var ui := CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	V2Ui.full(ui, UIPalette.FACILITY_WHITE)
	var stack := V2Ui.column(null, 22)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(stack)
	var project := V2Ui.text(stack, "PROJECT", "semibold", 18, UIPalette.GRAPHITE, 0.6)
	project.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var logo := V2Ui.text(stack, "FIREWALL", "c_extrabold", 168, UIPalette.GRAPHITE, 0.01)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# (the concept's line height 0.88: the label's own box is taller than the letters, so it is cut to their height)
	logo.clip_contents = false
	logo.custom_minimum_size = Vector2(0, 168 * 0.88)
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	logo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 168 * 0.72)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.remove_child(logo)
	holder.add_child(logo)
	logo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	logo.offset_top = -52.0
	logo.offset_bottom = 28.0
	stack.add_child(holder)
	var bar := V2Ui.rect(stack, UIPalette.CYAN, 120, 6)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_press = V2Ui.text(ui, "PRESS ENTER", "bold", 16, UIPalette.GRAPHITE_SECONDARY, 0.5)
	_press.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_press.anchor_right = 1.0
	_press.anchor_top = 1.0
	_press.anchor_bottom = 1.0
	_press.offset_top = -112.0 - 20.0
	_press.offset_bottom = -112.0
	# (pressing start: the letters fade into the page's own white, `V2World.cover`, and the run opens out of it)


func _process(delta: float) -> void:
	if _press == null:
		return
	_t += delta
	# 1.0 -> 0.25 -> 1.0 over 1.8 s, eased in and out
	_press.modulate.a = 0.625 + 0.375 * cos(_t * TAU / 1.8)



func _unhandled_input(event: InputEvent) -> void:
	if _press == null or _leaving:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_L:
			V2Music.stop()
			get_tree().change_scene_to_file(LAB)
		elif not (event.keycode in [KEY_ESCAPE, KEY_F3, KEY_F4, KEY_META, KEY_CTRL, KEY_ALT, KEY_SHIFT]):
			_start()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_start()


func _start() -> void:
	if _leaving:
		return
	_leaving = true
	# (the mouse is taken here, on the key or the click itself: a browser gives the pointer lock only in answer
	# to one, and the game would ask nine seconds too late)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	V2Sfx.play("ui")
	V2Music.stop(2.4)
	var tw := V2World.cover(get_tree(), UIPalette.FACILITY_WHITE, 1.3)
	tw.tween_interval(0.3)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(GAME))


func _shot(path: String) -> void:
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[title] ", path)
	get_tree().quit()
