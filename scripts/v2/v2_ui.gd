class_name V2Ui
## Small helpers for the V2 screens (title, the game's HUD and end screen, the Esc menu): labels, bars, buttons.
## Headings are in Kenney Future, which draws K and X like H: no heading may contain those letters. Body text is
## in the engine's own font. Everything ignores the mouse except buttons.

const CYAN := Color(0.133, 0.898, 1.0)
const GREEN := Color(0.224, 1.0, 0.533)
const VIOLET := Color(0.706, 0.549, 1.0)
const RED := Color(1.0, 0.29, 0.17)
const INK := Color(0.03, 0.04, 0.055)

static var _heading: Font


static func heading() -> Font:
	if _heading == null:
		_heading = load("res://assets/fonts/KenneyFuture.ttf")
	return _heading


## A label anchored at (ax, ay) of the screen (0..1), offset by (x, y) pixels.
static func label(parent: Node, text: String, ax: float, ay: float, x: float, y: float, size: int = 16,
		color: Color = Color(0.86, 0.93, 0.97), head: bool = false, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 4)
	if head:
		l.add_theme_font_override("font", heading())
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = align
	l.anchor_left = ax
	l.anchor_right = ax
	l.anchor_top = ay
	l.anchor_bottom = ay
	var w := 900.0
	l.offset_left = x - (w / 2.0 if align == HORIZONTAL_ALIGNMENT_CENTER else (w if align == HORIZONTAL_ALIGNMENT_RIGHT else 0.0))
	l.offset_right = l.offset_left + w
	l.offset_top = y
	parent.add_child(l)
	return l


static func rect(parent: Node, color: Color, ax: float, ay: float, x: float, y: float, w: float, h: float) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.anchor_left = ax
	r.anchor_right = ax
	r.anchor_top = ay
	r.anchor_bottom = ay
	r.offset_left = x
	r.offset_top = y
	r.offset_right = x + w
	r.offset_bottom = y + h
	parent.add_child(r)
	return r


static func full(parent: Node, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(r)
	return r


## A button centred at (ax, ay) + (x, y); `on` is called when it is pressed.
static func button(parent: Node, text: String, ax: float, ay: float, x: float, y: float, on: Callable, w: float = 260.0) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", heading())
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", Color(0.9, 0.97, 1.0))
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_focus_color", Color(0.9, 0.97, 1.0))
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.07, 0.09, 0.82) if state in ["normal", "focus"] else CYAN
		sb.border_color = CYAN
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(2)
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		b.add_theme_stylebox_override(state, sb)
	b.focus_mode = Control.FOCUS_NONE
	b.anchor_left = ax
	b.anchor_right = ax
	b.anchor_top = ay
	b.anchor_bottom = ay
	b.offset_left = x - w / 2.0
	b.offset_right = x + w / 2.0
	b.offset_top = y
	b.offset_bottom = y + 48.0
	b.pressed.connect(func() -> void:
		V2Sfx.play("ui")
		on.call())
	parent.add_child(b)
	return b
