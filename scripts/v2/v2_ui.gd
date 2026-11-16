class_name V2Ui
## What the V2 screens are built from, after the user's UI concept (v2/reference/ui/README.md: the spec, with its
## pictures in screens/). Every pixel value there is at 1440 x 810, which is the canvas the V2 scenes set
## (V2World._render_setup). Colours and panel styles: UIPalette (the concept's own file). Fonts: Barlow and Barlow
## Condensed (SIL OFL, assets/ui/fonts). Icons: white SVGs (assets/ui/icons), tinted here.
## Nothing made here takes the mouse, except buttons.

const DIR := "res://assets/ui/"
const FONTS := {
	"light": "Barlow-Light", "regular": "Barlow-Regular", "medium": "Barlow-Medium", "semibold": "Barlow-SemiBold",
	"bold": "Barlow-Bold", "extrabold": "Barlow-ExtraBold",
	"c_semibold": "BarlowCondensed-SemiBold", "c_bold": "BarlowCondensed-Bold", "c_extrabold": "BarlowCondensed-ExtraBold",
}

static var _fonts: Dictionary = {}
static var _icons: Dictionary = {}


## A Barlow font of that weight, its letters `tracking` em apart at `size` px (the concept gives tracking in em),
## with figures of one width (numbers do not jump as they change).
static func font(weight: String, size: int = 16, tracking: float = 0.0) -> Font:
	var space := roundi(tracking * size)
	var key := "%s/%d" % [weight, space]
	if not _fonts.has(key):
		var fv := FontVariation.new()
		fv.base_font = load(DIR + "fonts/" + FONTS[weight] + ".ttf")
		fv.spacing_glyph = space
		fv.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("tnum"): 1}
		_fonts[key] = fv
	return _fonts[key]


static func icon_texture(icon_name: String) -> Texture2D:
	if not _icons.has(icon_name):
		_icons[icon_name] = load(DIR + "icons/" + icon_name + ".svg")
	return _icons[icon_name]


## A line of text. For a container, or to be placed with `at`.
static func text(parent: Node, s: String, weight: String, size: int, color: Color, tracking: float = 0.0) -> Label:
	var l := Label.new()
	l.text = s
	l.add_theme_font_override("font", font(weight, size, tracking))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent != null:
		parent.add_child(l)
	return l


## An icon of the set, `w` x `h` px, tinted.
static func icon(parent: Node, icon_name: String, w: float, color: Color, h: float = -1.0) -> TextureRect:
	var t := TextureRect.new()
	t.texture = icon_texture(icon_name)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	t.custom_minimum_size = Vector2(w, w if h < 0.0 else h)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.modulate = color
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent != null:
		parent.add_child(t)
	return t


## A key cap: an outlined box with the key's name (the concept's [TAB], [H]); filled = the interact prompt's E.
static func keycap(parent: Node, key: String, filled: bool = false) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UIPalette.CYAN if filled else Color(0, 0, 0, 0)
	if not filled:
		sb.set_border_width_all(1)
		sb.border_color = Color(1, 1, 1, 0.5)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 5.0
	sb.content_margin_right = 5.0
	sb.content_margin_top = 0.0
	sb.content_margin_bottom = 1.0
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := text(p, key, "extrabold" if filled else "bold", 15 if filled else 11, UIPalette.GRAPHITE if filled else UIPalette.TEXT, 0.0 if filled else 0.06)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if filled:
		p.custom_minimum_size = Vector2(26, 26)
	if parent != null:
		parent.add_child(p)
	return p


## A panel with one of UIPalette's boxes, and its margins (left, top, right, bottom) if given.
static func panel(parent: Node, box: StyleBoxFlat, margins: Array = []) -> PanelContainer:
	var p := PanelContainer.new()
	if margins.size() == 4:
		box.content_margin_left = margins[0]
		box.content_margin_top = margins[1]
		box.content_margin_right = margins[2]
		box.content_margin_bottom = margins[3]
	p.add_theme_stylebox_override("panel", box)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent != null:
		parent.add_child(p)
	return p


static func row(parent: Node, gap: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent != null:
		parent.add_child(h)
	return h


static func column(parent: Node, gap: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent != null:
		parent.add_child(v)
	return v


## Pin a control to a point of the screen: (ax, ay) = 0..1 across and down, (x, y) px from there; it grows away
## from the edge it is pinned to (a panel at the right edge grows leftward as its text gets longer).
static func at(c: Control, ax: float, ay: float, x: float, y: float) -> Control:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN if ax > 0.75 else (Control.GROW_DIRECTION_BOTH if ax > 0.25 else Control.GROW_DIRECTION_END)
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN if ay > 0.75 else (Control.GROW_DIRECTION_BOTH if ay > 0.25 else Control.GROW_DIRECTION_END)
	c.offset_left = x
	c.offset_right = x
	c.offset_top = y
	c.offset_bottom = y
	return c


static func rect(parent: Node, color: Color, w: float = 0.0, h: float = 0.0) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(w, h)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent != null:
		parent.add_child(r)
	return r


## A rectangle over the whole screen (a wash, or a shader's canvas).
static func full(parent: Node, color: Color, shader: String = "") -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if shader != "":
		var m := ShaderMaterial.new()
		m.shader = load(DIR + "shaders/" + shader + ".gdshader")
		r.material = m
	if parent != null:
		parent.add_child(r)
	return r


## A button of the end screens: filled with `fill` (graphite text, an icon after it) or, with no fill, outlined.
## `on` is called when it is pressed.
static func button(parent: Node, label: String, on: Callable, fill: Color = Color(0, 0, 0, 0), icon_name: String = "") -> Button:
	var b := Button.new()
	var filled := fill.a > 0.0
	var ink := UIPalette.GRAPHITE if filled else UIPalette.TEXT
	var f := font("extrabold" if filled else "bold", 17, 0.2)
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := UIPalette.button_filled(fill) if filled else UIPalette.button_outline()
		if state in ["hover", "pressed"]:
			if filled:
				sb.bg_color = fill.lightened(0.18)
			else:
				sb.bg_color = Color(1, 1, 1, 0.1)
				sb.border_color = UIPalette.TEXT
		b.add_theme_stylebox_override(state, sb)
	# (the words and the icon are the button's children: a Button's own icon is drawn at the texture's size)
	var inner := row(b, 14)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var l := text(inner, label, "extrabold" if filled else "bold", 17, ink, 0.2)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 44.0
	if icon_name != "":
		icon(inner, icon_name, 20, ink)
		w += 34.0
	b.custom_minimum_size = Vector2(w, 56)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void:
		V2Sfx.play("ui")
		on.call())
	if parent != null:
		parent.add_child(b)
	return b


## 1,240
static func thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
