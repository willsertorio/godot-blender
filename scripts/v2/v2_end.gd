class_name V2End
extends Control
## The two end screens, after the UI concept (v2/reference/ui/screens/Complete.png and Failure.png). These are
## the only places where the picture "corrupts": the title is split into an orange and a cyan copy and jumps
## sideways every few seconds, in steps.
##   Mission complete: a plain graphite-grey page: the kicker, the title, three figures, the threat going up, and
##     ENTER DATASPACE nn (the next, harder dungeon) / STOP HERE (the title).
##   Signal lost: the view (the robots standing over the player) blurred, darkened toward the edges, scan lines,
##     an orange band; the title, the same three figures, RE-ASSEMBLE (a new dungeon at the same threat) / STOP HERE.
## Enter presses the first button.

const JITTER := [-14.0, 10.0, -4.0, 0.0]

var game: Node
var won := false
var _title: Control
var _lines: PackedStringArray
var _size := 104
var _split := 4.0
var _t := 0.0
var _period := 3.2
var _shift := 0.0
var _band: TextureRect
var _primary: Callable


func setup(game_node: Node, is_won: bool, blur: ColorRect) -> void:
	game = game_node
	won = is_won
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.45 if won else 0.7)
	if won:
		_complete()
	else:
		_failure(blur)


func _process(delta: float) -> void:
	_t += delta
	var into := fmod(_t, _period)
	var step := int(into / 0.055)
	var shift: float = JITTER[step] if step < JITTER.size() and _t > _period else 0.0
	if shift != _shift:
		_shift = shift
		_title.queue_redraw()
	if _band != null:                                      # the orange band drifts a little
		_band.position = Vector2(0, size.y * (0.4 + 0.03 * sin(_t * 0.5)))
		_band.size = Vector2(size.x, 56)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER] and modulate.a > 0.6:
		V2Sfx.play("ui")
		_primary.call()


# ---------------------------------------------------------------------------------------------- the two screens
func _complete() -> void:
	V2Ui.full(self, UIPalette.COMPLETE_BG)
	var col := V2Ui.column(self, 22)
	col.position = Vector2(72, 92)
	col.custom_minimum_size = Vector2(600, 0)
	var kicker := V2Ui.row(col, 12)
	V2Ui.icon(kicker, "exit_portal", 15, UIPalette.CYAN_LIGHT)
	V2Ui.text(kicker, "EXIT PORTAL REACHED", "bold", 13, UIPalette.CYAN_LIGHT, 0.3)
	_lines = PackedStringArray(["MISSION", "COMPLETE"])
	_size = 104
	_split = 4.0
	_period = 3.2
	_title_block(col, HORIZONTAL_ALIGNMENT_LEFT)
	_stats(col, 600.0)
	# the threat going up
	var box := StyleBoxFlat.new()
	box.bg_color = Color(UIPalette.ORANGE, 0.12)
	box.border_color = Color(UIPalette.ORANGE, 0.6)
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	var bar := V2Ui.row(V2Ui.panel(col, box, [16, 10, 16, 12]), 16)
	V2Ui.text(bar, "THREAT", "bold", 12, UIPalette.ORANGE_LIGHT, 0.22)
	var gap := V2Ui.rect(bar, Color(0, 0, 0, 0), 2, 0)
	gap.custom_minimum_size = Vector2(2, 0)
	V2Ui.text(bar, "%02d" % (game.missions - 1), "light", 30, UIPalette.TEXT)
	V2Ui.icon(bar, "arrow_right", 20, UIPalette.ORANGE)
	V2Ui.text(bar, "%02d" % game.missions, "semibold", 30, Color("FF9A4D"))
	V2Ui.rect(bar, Color(0, 0, 0, 0), 6, 0)
	V2Ui.text(bar, "Tougher, more numerous hostiles. Fewer kits.", "regular", 13, UIPalette.ORANGE_PALE)
	var buttons := V2Ui.row(col, 12)
	_primary = game.again
	V2Ui.button(buttons, "ENTER DATASPACE %02d" % (game.missions + 1), game.again, UIPalette.CYAN, "chevron_right")
	V2Ui.button(buttons, "STOP HERE", game.to_title)


func _failure(blur: ColorRect) -> void:
	# the view behind: blurred, washed orange, darkened; then the edges, the band, the scan lines
	blur.visible = true
	var bm := blur.material as ShaderMaterial
	bm.set_shader_parameter("tint", Color(1.0, 0.353, 0.039, 0.16))
	var tw := create_tween()
	tw.tween_method(func(a: float) -> void: bm.set_shader_parameter("amount", a), 0.0, 4.5, 0.7)
	V2Ui.full(self, Color(0.13, 0.06, 0.02, 0.5))           # (a warm dark over it: the concept's brown, not grey)
	var grad := Gradient.new()
	grad.set_color(0, Color(UIPalette.FAILURE_BG, 0.0))
	grad.set_color(1, Color(UIPalette.FAILURE_BG, 0.92))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.42)
	tex.fill_to = Vector2(1.05, 1.05)
	tex.width = 256
	tex.height = 256
	var edges := TextureRect.new()
	edges.texture = tex
	edges.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	edges.stretch_mode = TextureRect.STRETCH_SCALE
	edges.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	edges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(edges)
	var bg := Gradient.new()
	bg.set_color(0, Color(UIPalette.ORANGE, 0.0))
	bg.set_color(1, Color(UIPalette.ORANGE, 0.0))
	bg.add_point(0.5, Color(UIPalette.ORANGE, 0.34))
	var bt := GradientTexture2D.new()
	bt.gradient = bg
	bt.fill_from = Vector2(0, 0)
	bt.fill_to = Vector2(0, 1)
	bt.width = 4
	bt.height = 64
	var band := TextureRect.new()
	band.texture = bt
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band.stretch_mode = TextureRect.STRETCH_SCALE
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)
	_band = band
	var col := V2Ui.column(self, 28)
	col.anchor_left = 0.5
	col.anchor_right = 0.5
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.offset_top = 150.0
	_lines = PackedStringArray(["SIGNAL LOST"])
	_size = 128
	_split = 5.0
	_period = 2.6
	_title_block(col, HORIZONTAL_ALIGNMENT_CENTER)
	var stats := V2Ui.row(col, 0)
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	_stats(stats, 600.0)
	var buttons := V2Ui.row(col, 12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_primary = game.again
	V2Ui.button(buttons, "RE-ASSEMBLE", game.again, UIPalette.ORANGE, "retry")
	V2Ui.button(buttons, "STOP HERE", game.to_title)
	V2Ui.full(self, Color.WHITE, "scanlines")


# ---------------------------------------------------------------------------------------------- parts
func _title_block(parent: Control, align: int) -> void:
	var f := V2Ui.font("c_extrabold", _size, 0.0)
	var w := 0.0
	for line in _lines:
		w = maxf(w, f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, _size).x)
	_title = Control.new()
	_title.custom_minimum_size = Vector2(w + 12.0, _lines.size() * _size * 0.86 + _size * 0.06)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if align == HORIZONTAL_ALIGNMENT_LEFT else Control.SIZE_SHRINK_CENTER
	_title.draw.connect(_draw_title)
	parent.add_child(_title)


func _draw_title() -> void:
	var f := V2Ui.font("c_extrabold", _size, 0.0)
	var line_h := _size * 0.86
	var base := _size * 0.78                               # (capitals are 0.7 em: this seats them in a 0.86 em line)
	for copy in [[-_split, Color(UIPalette.ORANGE, 0.85)], [_split, Color(UIPalette.CYAN, 0.85 if won else 0.6)], [0.0, UIPalette.TEXT]]:
		for i in _lines.size():
			_title.draw_string(f, Vector2(4.0 + _shift + float(copy[0]), base + i * line_h), _lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, _size, copy[1])


## SCORE / HOSTILES / ROOMS: a white rule, a small label, a thin big figure.
func _stats(parent: Control, width: float) -> void:
	var r := V2Ui.row(parent, 16)
	r.custom_minimum_size = Vector2(width, 0)
	for spec in [["SCORE", V2Ui.thousands(game.score), ""], ["HOSTILES", str(game.kills), ""],
			["ROOMS", str(game.explored.size()), "/ %d" % game.gen.rooms.size()]]:
		var c := V2Ui.column(r, 0)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		V2Ui.rect(c, UIPalette.TEXT, 0, 2)
		V2Ui.rect(c, Color(0, 0, 0, 0), 0, 9)
		V2Ui.text(c, spec[0], "bold", 11, Color("B4BEC3"), 0.24)
		var v := V2Ui.row(c, 6)
		var big := V2Ui.text(v, spec[1], "light", 44, UIPalette.TEXT)
		big.add_theme_constant_override("line_spacing", 0)
		if spec[2] != "":
			var pad := MarginContainer.new()
			pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pad.add_theme_constant_override("margin_bottom", 8)
			pad.size_flags_vertical = Control.SIZE_SHRINK_END
			V2Ui.text(pad, spec[2], "medium", 18, UIPalette.LABEL)
			v.add_child(pad)
