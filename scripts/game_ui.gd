class_name GameUI
extends CanvasLayer
## Title screen, in-play HUD and end screen, all built in code.

signal start_pressed
signal again_pressed

const CYAN := Color("#22E5FF")
const RED := Color("#FF2D55")
const GREEN := Color("#39FF88")
const VIOLET := Color("#B48CFF")

var title: Control
var hud: Control
var end: Control
var flash: ColorRect
var room_label: Label
var objective_label: Label
var health_label: Label
var ammo_label: Label
var weapon_label: Label
var kits_label: Label
var crosshair: Control
var end_title: Label
var end_stats: Label


func _ready() -> void:
	layer = 10
	_build_title()
	_build_hud()
	_build_end()
	title.hide()
	hud.hide()
	end.hide()


func show_title() -> void:
	title.show()
	hud.hide()
	end.hide()


func show_hud() -> void:
	title.hide()
	end.hide()
	hud.show()


func show_end(success: bool, score: int, kills: int, rooms_seen: int, rooms_total: int) -> void:
	hud.hide()
	end.show()
	end_title.text = "MISSION COMPLETE" if success else "CONNECTION LOST"
	end_title.add_theme_color_override("font_color", CYAN if success else RED)
	end_stats.text = "SCORE  %d\nENEMIES KILLED  %d\nROOMS EXPLORED  %d / %d" % [score, kills, rooms_seen, rooms_total]


func update_hud(main) -> void:
	var p: Player = main.player
	health_label.text = "HEALTH  %d" % ceili(p.health)
	kits_label.text = "KITS  %d / %d" % [p.kits, Player.MAX_KITS]
	var w: WeaponHolder = p.weapons
	if w.current == "pistol":
		weapon_label.text = "[1] PISTOL"
		ammo_label.text = "∞"
	else:
		weapon_label.text = "[2] RIFLE" + ("  RELOADING" if w.reloading > 0.0 else "")
		ammo_label.text = "%d / %d" % [w.mag, w.reserve]
		ammo_label.add_theme_color_override("font_color", RED if w.mag == 0 else Color.WHITE)
	room_label.text = "ROOMS  %d / %d" % [main.visited.size(), main.layout.rooms.size()]
	objective_label.text = "OBJECTIVE  Reach the exit portal"


func hit_marker(killed: bool) -> void:
	crosshair.hit(killed)


func flash_damage() -> void:
	flash.color.a = 0.45
	var tw := create_tween()
	tw.tween_property(flash, "color:a", 0.0, 0.4)


# --- builders ---------------------------------------------------------------

func _label(text: String, size: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _full() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 26)
	b.custom_minimum_size = Vector2(320, 64)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.08, 0.1, 0.9)
	sb.border_color = CYAN
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	var hv := sb.duplicate() as StyleBoxFlat
	hv.bg_color = Color(0.05, 0.25, 0.3, 0.95)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", hv)
	b.add_theme_stylebox_override("focus", sb)
	b.add_theme_color_override("font_color", CYAN)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	return b


func _centered_column(parent: Control) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 18)
	center.add_child(v)
	return v


func _build_title() -> void:
	title = _full()
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.015, 0.025)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.add_child(bg)
	var v := _centered_column(title)
	var t := _label("PROJECT FIREWALL", 64, CYAN)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var l1 := _label("WASD move  ·  Mouse look  ·  Left click fire  ·  Right click aim  ·  1 / 2 weapon  ·  R reload", 18, Color(0.8, 0.9, 0.95))
	var l2 := _label("E open doors and containers  ·  Q use health kit  ·  Tab map", 18, Color(0.8, 0.9, 0.95))
	for l in [l1, l2]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 24
	v.add_child(spacer)
	var b := _button("ENTER DATASPACE")
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func(): start_pressed.emit())
	v.add_child(b)


func _build_hud() -> void:
	hud = _full()
	flash = ColorRect.new()
	flash.color = Color(RED, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(flash)

	crosshair = Crosshair.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	hud.add_child(crosshair)

	health_label = _label("", 24, Color.WHITE)
	health_label.position = Vector2(28, 0)
	health_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 28)
	hud.add_child(health_label)

	kits_label = _label("", 20, GREEN)
	kits_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 28)
	kits_label.position.y -= 34
	hud.add_child(kits_label)
	ammo_label = _label("", 30, Color.WHITE)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 28)
	ammo_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hud.add_child(ammo_label)
	weapon_label = _label("", 18, CYAN)
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weapon_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 28)
	weapon_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	weapon_label.position.y -= 38
	hud.add_child(weapon_label)

	room_label = _label("", 20, CYAN)
	room_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 24)
	hud.add_child(room_label)
	objective_label = _label("", 18, Color(0.8, 0.9, 0.95))
	objective_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 24)
	objective_label.position.y += 30
	hud.add_child(objective_label)


func _build_end() -> void:
	end = _full()
	end.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.015, 0.025, 0.88)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	end.add_child(bg)
	var v := _centered_column(end)
	end_title = _label("", 56, CYAN)
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(end_title)
	end_stats = _label("", 26, Color.WHITE)
	end_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(end_stats)
	var b := _button("PLAY AGAIN")
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func(): again_pressed.emit())
	v.add_child(b)


class Crosshair:
	extends Control
	## Tick marks plus a diagonal hit marker that flashes when a shot lands on a hostile
	## (red and larger on a kill).

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
		var c := Color(0.85, 0.97, 1.0, 0.9)
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			draw_line(d * 5.0, d * 13.0, c, 2.0)
		draw_circle(Vector2.ZERO, 1.5, c)
		if _hit > 0.0:
			var hc := Color("#FF2D55") if _kill else Color(1, 1, 1)
			hc.a = _hit
			var r0 := 8.0 if not _kill else 10.0
			var r1 := 15.0 if not _kill else 20.0
			for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				draw_line(d.normalized() * r0, d.normalized() * r1, hc, 2.5)
