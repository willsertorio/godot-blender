class_name GameUI
extends CanvasLayer
## Title screen, in-play HUD, Tab map and end screen, all built in code.
## HUD (GDD section 5): health, ammo + reserve, kit count, active weapon, room count and
## exit proximity, crosshair (turns red on a lined-up hostile, hit marker), damage flash,
## objective line. Heading font: Kenney Future (CC0).

signal start_pressed
signal again_pressed
signal resume_pressed
signal quit_pressed

const CYAN := Color("#22E5FF")
const RED := Color("#FF2D55")
const GREEN := Color("#39FF88")
const VIOLET := Color("#B48CFF")
const TEXT := Color(0.84, 0.92, 0.96)

var font_head: Font
var font_body: Font
var theme_main: Theme

var title: Control
var hud: Control
var end: Control
var map: MapView
var flash: ColorRect
var vignette: ColorRect
var crosshair: Crosshair
var status: StatusPanel
var weapon_panel: WeaponPanel
var room_label: Label
var exit_label: Label
var exit_signal: SignalBars
var objective_label: Label
var end_title: Label
var end_stats: Label
var end_next: Label
var pause_panel: Control


func _ready() -> void:
	layer = 10
	font_head = load("res://assets/fonts/KenneyFuture.ttf")
	# Kenney Future draws K like H, so it is for headings without a K; body text uses
	# the engine's default font, which reads cleanly at small sizes.
	font_body = ThemeDB.fallback_font
	theme_main = Theme.new()
	theme_main.default_font = font_body
	_build_title()
	_build_hud()
	_build_end()
	_build_pause()
	title.hide()
	hud.hide()
	end.hide()


func _unhandled_input(event: InputEvent) -> void:
	if hud.visible and event.is_action_pressed("map"):
		map.visible = not map.visible
		get_viewport().set_input_as_handled()


func show_pause(on: bool) -> void:
	pause_panel.visible = on


func _build_pause() -> void:
	pause_panel = _full()
	pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.02, 0.03, 0.72)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_child(bg)
	var v := _centered_column(pause_panel)
	var t := _label("PAUSED", 56, CYAN, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var hint := _label("Lab  ·  Esc to resume  ·  H switches hands: hands only / full arms / none", 17, Color(CYAN, 0.75))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)
	var b1 := _button("RESUME")
	b1.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b1.pressed.connect(func(): resume_pressed.emit())
	v.add_child(b1)
	var b2 := _button("QUIT")
	b2.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b2.pressed.connect(func(): quit_pressed.emit())
	v.add_child(b2)
	pause_panel.hide()


func show_title() -> void:
	title.show()
	hud.hide()
	end.hide()


func show_hud() -> void:
	title.hide()
	end.hide()
	map.hide()
	hud.show()


func show_end(success: bool, score: int, kills: int, rooms_seen: int, rooms_total: int, threat: int = 0) -> void:
	hud.hide()
	end.show()
	end_title.text = "MISSION COMPLETE" if success else "CONNECTION LOST"
	end_title.add_theme_color_override("font_color", CYAN if success else RED)
	end_stats.text = "SCORE  %d\nENEMIES KILLED  %d\nROOMS EXPLORED  %d / %d" % [score, kills, rooms_seen, rooms_total]
	end_next.text = ("NEXT DUNGEON  THREAT LEVEL %d" % (threat + 1)) if success else ("RETRY  THREAT LEVEL %d" % threat)


func update_hud(main) -> void:
	map.main = main
	var p: Player = main.player
	status.health = p.health
	status.max_health = p.max_health
	status.kits = p.kits
	status.queue_redraw()
	weapon_panel.update_from(p.weapons)
	room_label.text = "ROOMS  %d / %d" % [main.visited.size(), main.layout.rooms.size()]
	var m: float = main.exit_distance
	exit_signal.bars = 5 if m < 10 else 4 if m < 22 else 3 if m < 38 else 2 if m < 60 else 1
	exit_signal.queue_redraw()
	exit_label.text = "EXIT SIGNAL" + ("   %d m" % roundi(m) if main.exit_found else "")
	objective_label.text = "OBJECTIVE  " + ("Reach the exit portal" if main.exit_found else "Locate the exit portal")
	crosshair.on_target = main.crosshair_on_hostile()
	vignette.color.a = clampf((40.0 - p.health) / 40.0, 0.0, 1.0) * 0.35 * (0.8 + 0.2 * sin(Time.get_ticks_msec() * 0.006))


func hit_marker(killed: bool) -> void:
	crosshair.hit(killed)


func flash_damage() -> void:
	flash.color.a = 0.42
	var tw := create_tween()
	tw.tween_property(flash, "color:a", 0.0, 0.45)


# --- builders ---------------------------------------------------------------

func _label(text: String, size: int, color: Color = TEXT, head := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font_head if head else font_body)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


func _full() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.theme = theme_main
	add_child(c)
	return c


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font_head)
	b.add_theme_font_size_override("font_size", 24)
	b.custom_minimum_size = Vector2(340, 62)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.08, 0.1, 0.9)
	sb.border_color = CYAN
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	sb.shadow_color = Color(CYAN, 0.25)
	sb.shadow_size = 8
	var hv := sb.duplicate() as StyleBoxFlat
	hv.bg_color = Color(0.05, 0.25, 0.3, 0.95)
	hv.shadow_size = 14
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", hv)
	b.add_theme_stylebox_override("focus", sb)
	b.add_theme_color_override("font_color", CYAN)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	return b


func _centered_column(parent: Control) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 16)
	center.add_child(v)
	return v


func _grid_bg(parent: Control, alpha: float) -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/shaders/ui_grid.gdshader")
	sm.set_shader_parameter("alpha", alpha)
	bg.material = sm
	parent.add_child(bg)


func _build_title() -> void:
	title = _full()
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	_grid_bg(title, 1.0)
	var v := _centered_column(title)
	var t := _label("PROJECT FIREWALL", 68, CYAN, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var sub := _label("INFILTRATE  ·  CLEAR  ·  EXTRACT", 16, Color(CYAN, 0.7))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 26
	v.add_child(spacer)
	# Every control in two short lines (GDD onboarding).
	var l1 := _label("WASD move  ·  Shift run  ·  Space jump  ·  Ctrl / Cmd crouch  ·  Mouse look  ·  Left click fire  ·  Right click aim", 19)
	var l2 := _label("1 / 2 weapon  ·  R reload  ·  E open doors and containers  ·  Q use health kit  ·  Tab map", 19)
	for l in [l1, l2]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
	var spacer2 := Control.new()
	spacer2.custom_minimum_size.y = 26
	v.add_child(spacer2)
	var b := _button("ENTER DATASPACE")
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func(): start_pressed.emit())
	v.add_child(b)


func _build_hud() -> void:
	hud = _full()
	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = load("res://assets/shaders/ui_vignette.gdshader")
	vignette.material = vm
	vignette.color = Color(RED, 0.0)
	hud.add_child(vignette)
	flash = ColorRect.new()
	flash.color = Color(RED, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.material = vm
	hud.add_child(flash)

	crosshair = Crosshair.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	hud.add_child(crosshair)

	status = StatusPanel.new()
	status.font = font_body
	status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	status.position = Vector2(26, -118)
	status.size = Vector2(320, 92)
	hud.add_child(status)
	weapon_panel = WeaponPanel.new()
	weapon_panel.font_head = font_head
	weapon_panel.font_body = font_body
	weapon_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	weapon_panel.position = Vector2(-306, -118)
	weapon_panel.size = Vector2(280, 92)
	hud.add_child(weapon_panel)

	var top := VBoxContainer.new()
	top.position = Vector2(26, 20)
	top.add_theme_constant_override("separation", 2)
	hud.add_child(top)
	room_label = _label("", 22, CYAN, true)
	top.add_child(room_label)
	var exit_row := HBoxContainer.new()
	exit_row.add_theme_constant_override("separation", 10)
	exit_signal = SignalBars.new()
	exit_signal.custom_minimum_size = Vector2(62, 18)
	exit_label = _label("", 17, VIOLET)
	exit_row.add_child(exit_label)
	exit_row.add_child(exit_signal)
	exit_row.move_child(exit_signal, 0)
	top.add_child(exit_row)
	objective_label = _label("", 17, TEXT)
	top.add_child(objective_label)

	map = MapView.new()
	map.font = font_head
	map.visible = false
	hud.add_child(map)


func _build_end() -> void:
	end = _full()
	end.mouse_filter = Control.MOUSE_FILTER_STOP
	_grid_bg(end, 0.92)
	var v := _centered_column(end)
	end_title = _label("", 58, CYAN, true)
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(end_title)
	end_stats = _label("", 28, Color.WHITE)
	end_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(end_stats)
	end_next = _label("", 17, Color(CYAN, 0.75))
	end_next.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(end_next)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 12
	v.add_child(spacer)
	var b := _button("PLAY AGAIN")
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func(): again_pressed.emit())
	v.add_child(b)


class SignalBars:
	extends Control
	## Exit proximity: five rising bars, lit by walking distance to the portal.
	var bars := 1

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var v := Color("#B48CFF")
		for i in 5:
			var h := 5.0 + i * 3.0
			var r := Rect2(i * 12, size.y - h, 8, h)
			draw_rect(r, v if i < bars else Color(v, 0.18))


class StatusPanel:
	extends Control
	## Health bar + number, and three kit slots.
	var font: Font
	var health := 100.0
	var max_health := 100.0
	var kits := 0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var frac := clampf(health / max_health, 0.0, 1.0)
		var col := Color("#22E5FF") if frac > 0.35 else Color("#FF2D55")
		draw_rect(Rect2(0, 0, size.x, 92), Color(0.0, 0.03, 0.05, 0.55))
		draw_string(font, Vector2(14, 28), "HEALTH", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.8, 0.9, 0.95))
		draw_string(font, Vector2(size.x - 14, 30), "%d" % ceili(health), HORIZONTAL_ALIGNMENT_RIGHT, -1, 28, col)
		var bar := Rect2(14, 40, size.x - 28, 12)
		draw_rect(bar, Color(1, 1, 1, 0.08))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), col)
		for i in 10:
			var x := bar.position.x + bar.size.x * i / 10.0
			draw_line(Vector2(x, bar.position.y), Vector2(x, bar.end.y), Color(0, 0, 0, 0.5), 1.0)
		draw_string(font, Vector2(14, 80), "KITS  Q", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.8, 0.9, 0.95))
		for i in Player.MAX_KITS:
			var r := Rect2(92 + i * 34, 62, 26, 22)
			var g := Color("#39FF88")
			draw_rect(r, Color(g, 0.9) if i < kits else Color(g, 0.12))
			draw_rect(r, Color(g, 0.9), false, 1.5)
			var c := r.get_center()
			var k := Color(0, 0.1, 0.05) if i < kits else Color(g, 0.5)
			draw_rect(Rect2(c - Vector2(7, 2), Vector2(14, 4)), k)
			draw_rect(Rect2(c - Vector2(2, 7), Vector2(4, 14)), k)


class WeaponPanel:
	extends Control
	## Active weapon, magazine / reserve (or infinity), reload progress, both weapon slots.
	var font_head: Font
	var font_body: Font
	var current := "pistol"
	var mag := 0
	var reserve := 0
	var reload_frac := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func update_from(w: WeaponHolder) -> void:
		current = w.current
		mag = w.mag
		reserve = w.reserve
		reload_frac = 1.0 - w.reloading / WeaponHolder.WEAPONS.rifle.reload if w.reloading > 0.0 else 0.0
		queue_redraw()

	func _draw() -> void:
		var cyan := Color("#22E5FF")
		var red := Color("#FF2D55")
		draw_rect(Rect2(0, 0, size.x, 92), Color(0.0, 0.03, 0.05, 0.55))
		var slots := [["1", "PISTOL"], ["2", "RIFLE"]]
		for i in 2:
			var on: bool = (current == "pistol") == (i == 0)
			var x := 14 + i * 96
			draw_string(font_body, Vector2(x, 26), "%s %s" % slots[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, cyan if on else Color(0.6, 0.7, 0.75, 0.5))
			if on:
				draw_rect(Rect2(x, 31, 80, 2), cyan)
		if current == "pistol":
			# Infinity drawn as two loops: browsers have no system font to fall back on for "∞".
			var c := Vector2(size.x - 44, 64)
			draw_arc(c + Vector2(-11, 0), 10.0, 0.0, TAU, 32, Color.WHITE, 3.0, true)
			draw_arc(c + Vector2(11, 0), 10.0, 0.0, TAU, 32, Color.WHITE, 3.0, true)
		else:
			var mc := red if mag == 0 else Color.WHITE
			draw_string(font_head, Vector2(size.x - 92, 78), "%d" % mag, HORIZONTAL_ALIGNMENT_RIGHT, -1, 38, mc)
			draw_string(font_body, Vector2(size.x - 14, 78), "/ %d" % reserve, HORIZONTAL_ALIGNMENT_RIGHT, -1, 20, red if reserve == 0 else Color(0.8, 0.9, 0.95))
			if reload_frac > 0.0:
				draw_string(font_body, Vector2(14, 60), "RELOADING", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, cyan)
				draw_rect(Rect2(14, 66, 100 * reload_frac, 4), cyan)
			elif mag == 0:
				draw_string(font_body, Vector2(14, 60), "R  RELOAD" if reserve > 0 else "NO AMMO", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, red)


class Crosshair:
	extends Control
	## Tick marks; red when a hostile is lined up; a diagonal hit marker flashes when a
	## shot lands (red and larger on a kill).
	var on_target := false:
		set(v):
			if v != on_target:
				on_target = v
				queue_redraw()
	var _hit := 0.0
	var _kill := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func hit(killed: bool) -> void:
		_hit = 1.0
		_kill = killed
		queue_redraw()

	func _process(delta: float) -> void:
		if _hit > 0.0:
			_hit = maxf(0.0, _hit - delta * 5.0)
			queue_redraw()

	func _draw() -> void:
		var c := Color("#FF2D55") if on_target else Color(0.85, 0.97, 1.0, 0.9)
		var gap := 4.0 if on_target else 5.0
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			draw_line(d * gap, d * (gap + 8.0), Color(0, 0, 0, 0.5), 4.0)
			draw_line(d * gap, d * (gap + 8.0), c, 2.0)
		draw_circle(Vector2.ZERO, 1.5, c)
		if _hit > 0.0:
			var hc := Color("#FF2D55") if _kill else Color(1, 1, 1)
			hc.a = _hit
			var r0 := 8.0 if not _kill else 10.0
			var r1 := 15.0 if not _kill else 20.0
			for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				draw_line(d.normalized() * r0, d.normalized() * r1, hc, 2.5)
