class_name V2Hud
extends Control
## The game's HUD, after the UI concept (v2/reference/ui/README.md, screens/HudExplore.png and HudCombat.png): dark
## glass panels on the bright rooms, two signal colours (cyan = you, the system, good; orange = danger, low,
## hostiles). Built once in `setup`, bound to the game's state every frame in `update`. Nothing here takes the
## mouse. What the concept leaves open, and how it is answered here:
##   - the cursor is where the rounds will go (V2Player.aim_dot: it climbs with the recoil), not a fixed middle;
##     the interact prompt stays beside the middle of the screen;
##   - the med kit's key is H in this game (Q switches gun), so the key cap says H;
##   - in a corridor the objective line speaks of the corridor; in the exit's room it says so;
##   - a pickup is answered by a small chip at the bottom of the screen for two seconds (`say`);
##   - **ammunition is on the HUD, not on the guns** (the user, on seeing the concept's weapon screens: "no need
##     for that, let's show ammunition in the HUD"): a readout above the weapon tiles in the weapon screens'
##     styling (the concept's own fallback). The pistol of this game has a magazine of 15 and no end of them, so
##     it reads "12 / infinity", not the concept's bare infinity; the readout keeps its full strength while aiming.

const EDGE := Vector2(32, 28)
const SEGMENTS := 20
const KIT_KEY := "H"
const AMMO := Vector2(182, 56)
const RELOADS := ["Reload", "ReloadTactical", "ReloadEmpty"]

var game: Node                      # the V2 game (v2_game.gd)
var blur: ColorRect                 # under the HUD, in the game's effects layer
var vignette: ColorRect

var _panels: Control                # what fades while aiming
var _room_n: Label
var _room_of: Label
var _goal_icon: TextureRect
var _goal: Label
var _exit: Label
var _threat: Label
var _hp_box: StyleBoxFlat
var _hp_icon: TextureRect
var _hp_n: Label
var _hp_bar: Control
var _kits: Control
var _low: Label
var _tiles: Dictionary = {}         # weapon -> {panel, icon, bar}
var _ammo: Control
var _ammo_box: StyleBoxFlat
var _prompt: PanelContainer
var _prompt_text: Label
var _toast: PanelContainer
var _toast_icon: TextureRect
var _toast_text: Label
var _toast_t := 0.0
var _cross: Control
var perf: Label
var _train: PanelContainer           # the training's card: which step, what to do, how far along
var _train_n: Label
var _train_line: HBoxContainer
var _train_count: Label
var _train_shown := -1
var _train_flash := 0.0

var _shown_hp := 100.0              # what the bar showed last frame
var _ghost_from := 0                # segments lost a moment ago: [_ghost_from, _ghost_to)
var _ghost_to := 0
var _ghost_t := 0.0
var _heal_from := 0                 # segments just gained
var _heal_to := 0
var _heal_t := 0.0
var _hit_t := 0.0                   # 1 when hit, falls to 0 in 0.6 s: vignette and arc
var _blur_t := 0.0                  # 1 -> 0 in 0.5 s
var _hit_angle := 0.0               # where the hit came from: clockwise from straight ahead
var _last_flash := 0.0
var _lined := false                 # the next round would strike a robot
var _t := 0.0


func setup(game_node: Node, fx_layer: CanvasLayer) -> void:
	game = game_node
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	blur = V2Ui.full(fx_layer, Color.WHITE, "screen_blur")
	blur.visible = false
	vignette = V2Ui.full(fx_layer, Color.WHITE, "damage_vignette")
	vignette.visible = false
	_cross = Control.new()
	_cross.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cross.draw.connect(_draw_cross)
	add_child(_cross)
	_panels = Control.new()
	_panels.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panels)
	_build_room()
	_build_chips()
	_build_health()
	_build_weapons()
	_build_prompt()
	_build_toast()
	_build_training()
	perf = V2Ui.text(self, "", "medium", 13, UIPalette.ORANGE_PALE)
	perf.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	perf.add_theme_constant_override("outline_size", 4)
	V2Ui.at(perf, 0.0, 0.0, EDGE.x, 112.0)
	perf.visible = false


# ---------------------------------------------------------------------------------------------- building
func _build_room() -> void:
	var p := V2Ui.panel(_panels, UIPalette.hud_panel(), [0, 0, 0, 0])
	V2Ui.at(p, 0.0, 0.0, EDGE.x, EDGE.y)
	var cells := V2Ui.row(p, 0)
	var left := MarginContainer.new()
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in [["margin_left", 16], ["margin_right", 16], ["margin_top", 9], ["margin_bottom", 6]]:
		left.add_theme_constant_override(side[0], side[1])
	cells.add_child(left)
	var lc := V2Ui.column(left, -6)
	V2Ui.text(lc, "ROOM", "bold", 11, UIPalette.LABEL, 0.24)
	var num := V2Ui.row(lc, 4)
	_room_n = V2Ui.text(num, "01", "light", 40, UIPalette.TEXT)
	_room_of = V2Ui.text(num, "/ 08", "medium", 18, UIPalette.LABEL)
	_room_of.size_flags_vertical = Control.SIZE_SHRINK_END
	_room_of.add_theme_constant_override("line_spacing", 0)
	var pad := MarginContainer.new()                       # (the small figures sit on the big one's baseline)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_bottom", 7)
	num.remove_child(_room_of)
	pad.add_child(_room_of)
	pad.size_flags_vertical = Control.SIZE_SHRINK_END
	num.add_child(pad)
	V2Ui.rect(cells, UIPalette.HUD_GLASS_BORDER, 1, 0)
	var right := MarginContainer.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in [["margin_left", 18], ["margin_right", 18], ["margin_top", 10], ["margin_bottom", 10]]:
		right.add_theme_constant_override(side[0], side[1])
	cells.add_child(right)
	var rc := V2Ui.column(right, 6)
	rc.alignment = BoxContainer.ALIGNMENT_CENTER
	var goal := V2Ui.row(rc, 8)
	_goal_icon = V2Ui.icon(goal, "check", 14, UIPalette.CYAN)
	_goal = V2Ui.text(goal, "", "semibold", 16, UIPalette.TEXT)
	var ex := V2Ui.row(rc, 9)
	V2Ui.icon(ex, "exit_portal", 13, UIPalette.TEXT_SECONDARY)
	_exit = V2Ui.text(ex, "", "regular", 13, UIPalette.TEXT_SECONDARY, 0.02)


func _build_chips() -> void:
	var chips := V2Ui.row(_panels, 8)
	V2Ui.at(chips, 1.0, 0.0, -EDGE.x, EDGE.y)
	var a := V2Ui.row(V2Ui.panel(chips, UIPalette.hud_panel(), [14, 7, 14, 7]), 10)
	V2Ui.text(a, "THREAT", "bold", 12, UIPalette.TEXT, 0.22)
	_threat = V2Ui.text(a, "00", "medium", 18, UIPalette.TEXT)
	var b := V2Ui.row(V2Ui.panel(chips, UIPalette.hud_panel(), [12, 7, 14, 7]), 8)
	V2Ui.keycap(b, "TAB")
	V2Ui.text(b, "MAP", "bold", 12, UIPalette.TEXT, 0.22)


func _build_health() -> void:
	_hp_box = UIPalette.hud_panel()
	var p := V2Ui.panel(_panels, _hp_box, [16, 8, 16, 14])
	p.custom_minimum_size = Vector2(360, 0)
	V2Ui.at(p, 0.0, 1.0, EDGE.x, -EDGE.y)
	var col := V2Ui.column(p, 6)
	var top := V2Ui.row(col, 12)
	_hp_icon = V2Ui.icon(top, "health_cross", 22, UIPalette.CYAN)
	_hp_n = V2Ui.text(top, "100", "light", 44, UIPalette.TEXT)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(gap)
	_kits = Control.new()
	_kits.custom_minimum_size = Vector2(3 * 30 + 2 * 6, 30)
	_kits.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_kits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kits.draw.connect(_draw_kits)
	top.add_child(_kits)
	V2Ui.keycap(top, KIT_KEY)
	_hp_bar = Control.new()
	_hp_bar.custom_minimum_size = Vector2(0, 8)
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bar.draw.connect(_draw_bar)
	col.add_child(_hp_bar)
	_low = V2Ui.text(col, "LOW · BREAK LINE OF SIGHT", "semibold", 12, UIPalette.ORANGE_LIGHT, 0.14)
	_low.visible = false


func _build_weapons() -> void:
	var tiles := V2Ui.row(_panels, 6)
	tiles.alignment = BoxContainer.ALIGNMENT_END
	V2Ui.at(tiles, 1.0, 1.0, -EDGE.x, -EDGE.y)
	for spec in [["pistol", "1", 72.0, 34.0, 34.0], ["rifle", "2", 104.0, 70.0, 30.0]]:
		var tile := Panel.new()
		tile.custom_minimum_size = Vector2(spec[2], 52)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tiles.add_child(tile)
		var n := V2Ui.text(tile, spec[1], "bold", 11, UIPalette.LABEL)
		n.position = Vector2(8, 3)
		var ic := V2Ui.icon(tile, "weapon_" + spec[0], spec[3], UIPalette.TEXT, spec[4])
		ic.size = Vector2(spec[3], spec[4])
		ic.position = (Vector2(spec[2], 52) - ic.size) / 2.0 + Vector2(0, 2)
		var bar := V2Ui.rect(tile, UIPalette.CYAN)
		bar.position = Vector2(0, 49)
		bar.size = Vector2(spec[2], 3)
		_tiles[spec[0]] = {"panel": tile, "icon": ic, "bar": bar, "on": UIPalette.weapon_slot(true), "off": UIPalette.weapon_slot(false)}
	# the rounds of the gun in hand: above the tiles, as wide as the two of them (not in `_panels`: it does not
	# fade while aiming)
	_ammo_box = StyleBoxFlat.new()
	_ammo_box.set_corner_radius_all(4)
	_ammo_box.set_border_width_all(1)
	_ammo = Control.new()
	_ammo.custom_minimum_size = AMMO
	_ammo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ammo.draw.connect(_draw_ammo)
	add_child(_ammo)
	V2Ui.at(_ammo, 1.0, 1.0, -EDGE.x, -EDGE.y - 52.0 - 8.0)


func _build_prompt() -> void:
	var box := UIPalette.hud_panel(true, UIPalette.CYAN)
	_prompt = V2Ui.panel(self, box, [6, 5, 14, 5])
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.anchor_top = 0.5
	_prompt.anchor_bottom = 0.5
	_prompt.grow_vertical = Control.GROW_DIRECTION_BOTH
	_prompt.offset_left = 32.0
	_prompt.offset_right = 32.0
	var r := V2Ui.row(_prompt, 12)
	V2Ui.keycap(r, "E", true)
	_prompt_text = V2Ui.text(r, "OPEN DOOR", "bold", 14, UIPalette.TEXT, 0.18)
	_prompt.visible = false


func _build_toast() -> void:
	_toast = V2Ui.panel(self, UIPalette.hud_panel(true), [12, 7, 16, 7])
	V2Ui.at(_toast, 0.5, 1.0, 0.0, -EDGE.y - 8.0)
	var r := V2Ui.row(_toast, 10)
	_toast_icon = V2Ui.icon(r, "health_kit", 16, UIPalette.CYAN)
	_toast_text = V2Ui.text(r, "", "bold", 13, UIPalette.TEXT, 0.16)
	_toast.modulate.a = 0.0


## The training's card, top middle: "TRAINING 1 / 4", the step in words with its keys, and the count of hits.
## (Not in the concept: the same glass, cyan edge and key caps as its interact prompt.)
func _build_training() -> void:
	_train = V2Ui.panel(self, UIPalette.hud_panel(true, UIPalette.CYAN), [18, 9, 20, 10])
	V2Ui.at(_train, 0.5, 0.0, 0.0, EDGE.y)
	var r := V2Ui.row(_train, 18)
	var left := V2Ui.column(r, -4)
	V2Ui.text(left, "TRAINING", "bold", 11, UIPalette.CYAN_LIGHT, 0.24)
	_train_n = V2Ui.text(left, "1 / 4", "light", 26, UIPalette.TEXT)
	V2Ui.rect(r, UIPalette.HUD_GLASS_BORDER, 1, 0)
	_train_line = V2Ui.row(r, 9)
	_train_count = V2Ui.text(r, "", "light", 26, UIPalette.CYAN)
	_train.visible = false


## A step's line: words and key caps in turn ("[C]" = a key cap).
func _train_step(parts: Array) -> void:
	for ch in _train_line.get_children():
		ch.queue_free()
	for part: String in parts:
		if part.begins_with("["):
			V2Ui.keycap(_train_line, part.trim_prefix("[").trim_suffix("]"))
		else:
			V2Ui.text(_train_line, part, "semibold", 16, UIPalette.TEXT)


## A step was done: the card flashes.
func train_done() -> void:
	_train_flash = 1.0


const TRAIN_STEPS := [
	["[C]", "Hold to aim. Shoot the target with the pistol."],
	["[2]", "Take the rifle.", "[C]", "Aim and shoot the target."],
	["[E]", "Open the crate and take the health kit."],
	["[E]", "Open a door. The run starts."],
]


func _training(delta: float) -> void:
	var on: bool = game.training and game.state == game.PLAYING
	_train.visible = on or _train_flash > 0.0
	_train_flash = maxf(_train_flash - delta * 1.6, 0.0)
	_train.modulate = Color(1, 1, 1, 1).lerp(Color(1.6, 1.6, 1.6, 1), _train_flash) if on else Color(1, 1, 1, _train_flash)
	if not on:
		return
	var step: int = mini(game.train_step, TRAIN_STEPS.size() - 1)
	if step != _train_shown:
		_train_shown = step
		_train_step(TRAIN_STEPS[step])
		_train_n.text = "%d / %d" % [step + 1, TRAIN_STEPS.size()]
	_train_count.visible = step < 2
	if step < 2:
		_train_count.text = "%d / %d" % [game.train_hits, game.TRAIN_HITS[step]]


## What was just picked up (or could not be): a chip at the foot of the screen for two seconds.
func say(text: String, icon_name: String = "", warn: bool = false) -> void:
	_toast_text.text = text.to_upper()
	_toast_icon.visible = icon_name != ""
	if icon_name != "":
		_toast_icon.texture = V2Ui.icon_texture(icon_name)
	_toast_icon.modulate = UIPalette.ORANGE if warn else UIPalette.CYAN
	_toast_t = 2.2


# ---------------------------------------------------------------------------------------------- every frame
func update(delta: float) -> void:
	var player: V2Player = game.player
	var gen: DungeonGen = game.gen
	_t += delta
	var playing: bool = game.state == game.PLAYING
	# --- the room panel
	_room_n.text = "%02d" % game.explored.size()
	_room_of.text = "/ %02d" % gen.rooms.size()
	var here: int = game.here
	var in_room: bool = here >= 0 and game.dungeon.areas[here].room
	var place := "Room" if in_room else "Corridor"
	var hostiles: int = game.alive_in(here)
	if game.training:
		_goal_icon.texture = V2Ui.icon_texture("hazard")
		_goal_icon.modulate = UIPalette.CYAN
		_goal.text = "Training room"
	elif hostiles > 0:
		var kind := "spider"
		for r: V2Robot in game.robots:
			if r.state != V2Robot.DEAD and r.room == here:
				kind = r.kind
				break
		_goal_icon.texture = V2Ui.icon_texture({"turret": "enemy_turret", "spider": "enemy_brawler", "drone": "enemy_pursuer"}[kind])
		_goal_icon.modulate = UIPalette.ORANGE
		_goal.text = "%d hostile%s in this %s" % [hostiles, "" if hostiles == 1 else "s", place.to_lower()]
	else:
		_goal_icon.texture = V2Ui.icon_texture("check")
		_goal_icon.modulate = UIPalette.CYAN
		var in_exit_room: bool = in_room and int(game.dungeon.areas[here].id) == gen.exit_room
		_goal.text = "%s clear. %s" % [place, "Step into the exit portal." if in_exit_room else "Find the exit portal."]
	var away: int = rooms_to_exit()
	_exit.text = "Exit portal not located" if not game.exit_found else ("Exit portal: in this room" if away == 0
		else "Exit portal: %d room%s away" % [away, "" if away == 1 else "s"])
	_threat.text = "%02d" % game.missions
	# --- health
	var hp := int(ceil(player.hp))
	var low := hp <= UIPalette.HEALTH_LOW_THRESHOLD and playing
	var on := _segments(player.hp)
	var was := _segments(_shown_hp)
	if on < was:
		_ghost_from = on
		_ghost_to = maxi(was, _ghost_to if _ghost_t > 0.0 else 0)
		_ghost_t = 0.4
		_heal_t = 0.0
	elif on > was:
		_heal_from = was
		_heal_to = on
		_heal_t = 0.45
		_ghost_t = 0.0
	_shown_hp = player.hp
	_ghost_t = maxf(_ghost_t - delta, 0.0)
	_heal_t = maxf(_heal_t - delta, 0.0)
	_hp_n.text = str(hp)
	_hp_n.add_theme_color_override("font_color", UIPalette.ORANGE_LIGHT if low else UIPalette.TEXT)
	_hp_icon.modulate = UIPalette.health_color(hp)
	_hp_icon.modulate.a = (0.675 + 0.325 * cos(_t * TAU / 0.9)) if low else 1.0
	_hp_box.border_color = Color(UIPalette.ORANGE, 0.55) if low else UIPalette.HUD_GLASS_BORDER
	_low.visible = low
	_hp_bar.queue_redraw()
	_kits.queue_redraw()
	# --- weapons
	for w: String in _tiles:
		var tile: Dictionary = _tiles[w]
		var active := player.weapon == w
		(tile.panel as Panel).add_theme_stylebox_override("panel", tile.on if active else tile.off)
		(tile.icon as TextureRect).modulate = UIPalette.TEXT if active else UIPalette.LABEL
		(tile.bar as ColorRect).visible = active
	var aimed := player._aimed
	_ammo.visible = playing
	_ammo.queue_redraw()
	# --- aiming: the panels step back (a quiet sign of the slower walk)
	_panels.modulate.a = lerpf(1.0, 0.4, aimed) if playing else 1.0
	# --- the hit: blur, the glow on the side it came from, the arc round the cursor
	if player.hurt_flash > _last_flash + 0.2 and playing:
		_hit_t = 1.0
		_blur_t = 1.0
		var to := player.hurt_from - player.global_position
		_hit_angle = -angle_difference(player._yaw, atan2(-to.x, -to.z))
	_last_flash = player.hurt_flash
	_hit_t = maxf(_hit_t - delta / 0.6, 0.0)
	_blur_t = maxf(_blur_t - delta / 0.5, 0.0)
	if not game.ending:                                    # (the end screen takes the blur over)
		blur.visible = _blur_t > 0.02
		if blur.visible:
			(blur.material as ShaderMaterial).set_shader_parameter("amount", 3.0 * _blur_t)
	vignette.visible = _hit_t > 0.01
	if vignette.visible:
		var vm := vignette.material as ShaderMaterial
		vm.set_shader_parameter("intensity", _hit_t)
		vm.set_shader_parameter("hit_dir", Vector2(sin(_hit_angle), -cos(_hit_angle)))
	# --- the cursor: is a robot under it?
	_lined = false
	if playing and player.aim_dot.x >= 0.0:
		var from := player.cam.global_position
		var q := PhysicsRayQueryParameters3D.create(from, from + player.aim_dir() * 60.0)
		q.exclude = [player.get_rid()]
		var res := player.get_world_3d().direct_space_state.intersect_ray(q)
		if not res.is_empty() and res.collider.has_meta("robot"):
			_lined = (res.collider.get_meta("robot") as V2Robot).state != V2Robot.DEAD
	_cross.visible = playing
	_cross.queue_redraw()
	# --- E: only within reach of a shut door or an unopened crate
	var what: String = game.in_reach() if playing else ""
	_prompt.visible = what != ""
	if what != "":
		_prompt_text.text = "OPEN " + what.to_upper()
	_training(delta)
	# --- the chip
	_toast_t -= delta
	_toast.modulate.a = clampf(_toast_t * 2.0, 0.0, 1.0) if playing else 0.0


func _segments(hp: float) -> int:
	return clampi(roundi(hp / 100.0 * SEGMENTS), 1 if hp > 0.0 else 0, SEGMENTS)


## Rooms between the player and the exit's room along the corridors (0 = in it); from a corridor, the nearer of
## its two rooms plus one.
func rooms_to_exit() -> int:
	var gen: DungeonGen = game.gen
	var here: int = game.here
	if here < 0:
		return 0
	var area: Dictionary = game.dungeon.areas[here]
	if area.room:
		return _tree_distance(int(area.id), gen.exit_room)
	for co in gen.corridors:
		if co.id == int(area.id):
			return mini(_tree_distance(co.a, gen.exit_room), _tree_distance(co.b, gen.exit_room)) + 1
	return 0


func _tree_distance(a: int, b: int) -> int:
	var gen: DungeonGen = game.gen
	var up := {}
	var n := 0
	var k := a
	while k >= 0:
		up[k] = n
		n += 1
		k = gen.rooms[k].parent
	n = 0
	k = b
	while k >= 0:
		if up.has(k):
			return int(up[k]) + n
		n += 1
		k = gen.rooms[k].parent
	return n


# ---------------------------------------------------------------------------------------------- drawing
func _draw_bar() -> void:
	var w := _hp_bar.size.x
	var gap := 3.0
	var seg := (w - gap * (SEGMENTS - 1)) / SEGMENTS
	var on := _segments(_shown_hp)
	var color := UIPalette.health_color(int(ceil(_shown_hp)))
	for i in SEGMENTS:
		var c := color if i < on else UIPalette.SEGMENT_EMPTY
		if _ghost_t > 0.0 and i >= _ghost_from and i < _ghost_to:
			c = UIPalette.SEGMENT_LOST_GHOST
			c.a *= clampf(_ghost_t / 0.15, 0.0, 1.0)
			_hp_bar.draw_rect(Rect2(i * (seg + gap), 0, seg, 8), UIPalette.SEGMENT_EMPTY)
		elif _heal_t > 0.0 and i >= _heal_from and i < _heal_to:
			# (the white sweeps in from the left, then settles to the bar's colour)
			var k := clampf((0.45 - _heal_t) / 0.2 * (_heal_to - _heal_from) - (i - _heal_from), 0.0, 1.0)
			c = UIPalette.SEGMENT_EMPTY.lerp(Color.WHITE.lerp(color, clampf((0.25 - _heal_t) / 0.25, 0.0, 1.0)), k)
		_hp_bar.draw_rect(Rect2(i * (seg + gap), 0, seg, 8), c)


## The rounds of the gun in hand, as the concept's weapon screens show them: the magazine in big figures, what is
## carried after it, a thin bar for the magazine; orange when the magazine is down to a quarter; RELOAD and a bar
## filling while the hands are at it; "1 · PISTOL" when the machine gun has nothing left at all.
func _draw_ammo() -> void:
	var player: V2Player = game.player
	var w: String = player.weapon
	var mag: int = player.mag[w]
	var full: int = V2Player.MAG[w]
	var rifle := w == "rifle"
	var reloading := player.busy in RELOADS
	var dry := rifle and mag <= 0 and player.reserve <= 0 and not reloading
	var low := (mag <= full / 4 and not reloading) or dry
	var ink := UIPalette.ORANGE if low else UIPalette.CYAN
	var ink2 := UIPalette.ORANGE_LIGHT if low else UIPalette.CYAN_LIGHT
	_ammo_box.bg_color = Color(UIPalette.WEAPON_SCREEN_BG_LOW if low else UIPalette.WEAPON_SCREEN_BG, 0.92)
	_ammo_box.border_color = Color(ink, 0.4)
	_ammo.draw_style_box(_ammo_box, Rect2(Vector2.ZERO, AMMO))
	var bar := Rect2(14, AMMO.y - 12.0, AMMO.x - 28.0, 3)
	_ammo.draw_rect(bar, Color(ink, 0.22))
	if reloading:
		var ap := player._ap()
		var k := clampf(ap.current_animation_position / maxf(ap.current_animation_length, 0.01), 0.0, 1.0)
		_ammo.draw_string(V2Ui.font("bold", 16, 0.24), Vector2(14, 29), "RELOAD", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ink)
		_ammo.draw_rect(Rect2(bar.position, Vector2(bar.size.x * k, 3)), ink)
		return
	if dry:
		_ammo.draw_string(V2Ui.font("bold", 16, 0.2), Vector2(14, 29), "1 · PISTOL", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ink)
		return
	var big := V2Ui.font("semibold", 30)
	var n := "%02d" % mag
	for glow in [[4.0, 0.10], [2.0, 0.18]]:                 # a little light round the figures
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			_ammo.draw_string(big, Vector2(13, 35) + d * float(glow[0]) * 0.5, n, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(ink, glow[1]))
	_ammo.draw_string(big, Vector2(13, 35), n, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, ink)
	var x := 13.0 + big.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x + 8.0
	var small := V2Ui.font("medium", 15)
	_ammo.draw_string(small, Vector2(x, 34), "/", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ink2)
	if rifle:
		_ammo.draw_string(small, Vector2(x + 11.0, 34), str(player.reserve), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ink2)
	else:                                                  # the pistol's magazines never run out: the sign for it, drawn
		for cx in [x + 17.0, x + 26.0]:
			_ammo.draw_arc(Vector2(cx, 29), 4.5, 0.0, TAU, 20, ink2, 1.6, true)
	_ammo.draw_rect(Rect2(bar.position, Vector2(bar.size.x * mag / float(full), 3)), ink)
	# which gun: its sign at the right
	_ammo.draw_texture_rect(V2Ui.icon_texture("ammo_rifle"), Rect2(AMMO.x - 14.0 - 20.0, 12, 20, 20), false, Color(ink2, 0.8))


func _draw_kits() -> void:
	var have: int = game.player.kits
	var tex := V2Ui.icon_texture("health_kit")
	for i in V2Player.MAX_KITS:
		var r := Rect2(i * 36.0, 0, 30, 30)
		if i < have:
			_kits.draw_rect(r, Color(UIPalette.CYAN, 0.18))
			_kits.draw_rect(r.grow(-0.5), UIPalette.CYAN, false, 1.0)
			_kits.draw_texture_rect(tex, r.grow(-6.0), false, UIPalette.CYAN)
		else:
			var c := Color(1, 1, 1, 0.3)
			var q := r.grow(-0.5)
			for e in [[q.position, Vector2(q.end.x, q.position.y)], [Vector2(q.end.x, q.position.y), q.end],
					[q.end, Vector2(q.position.x, q.end.y)], [Vector2(q.position.x, q.end.y), q.position]]:
				_kits.draw_dashed_line(e[0], e[1], c, 1.0, 3.0)


func _draw_cross() -> void:
	var player: V2Player = game.player
	var mid := size / 2.0
	# the arc toward where a hit came from: round the middle of the screen
	if _hit_t > 0.0:
		var a := _hit_angle - PI / 2.0
		for glow in [[13.0, 0.10], [9.0, 0.16], [5.0, 1.0]]:
			_cross.draw_arc(mid, 60.0, a - PI / 4.0, a + PI / 4.0, 24, Color(UIPalette.ORANGE, float(glow[1]) * _hit_t), glow[0], true)
	var at := player.aim_dot
	if at.x < 0.0 or player.busy in V2Player.NO_CURSOR or game.map_open():
		return
	var aimed := player._aimed
	var hit := player.hit_confirm > 0.0
	if _lined:
		var r := lerpf(15.0, 10.0, aimed)
		_cross.draw_arc(at, r, 0.0, TAU, 40, Color(0, 0, 0, 0.3), 4.0, true)
		_cross.draw_arc(at, r, 0.0, TAU, 40, UIPalette.ORANGE, 2.0, true)
		var b := lerpf(23.0, 16.0, aimed)
		for side in [0.0, PI]:
			_cross.draw_arc(at, b, side - 0.75, side + 0.75, 14, UIPalette.ORANGE, 2.0, true)
		_cross.draw_circle(at, 2.5, UIPalette.ORANGE)
	else:
		var r := lerpf(13.0, 8.0, aimed)
		_cross.draw_arc(at, r + 1.4, 0.0, TAU, 40, Color(0, 0, 0, 0.35), 1.0, true)
		_cross.draw_arc(at, r, 0.0, TAU, 40, Color(UIPalette.TEXT, 0.85), 2.0, true)
		_cross.draw_circle(at, 2.0, UIPalette.ORANGE if hit else Color(UIPalette.TEXT, 0.95))
	if hit:                                                # a round went home: four ticks for a moment
		for k in 4:
			var d := Vector2.from_angle(PI / 4.0 + k * PI / 2.0)
			_cross.draw_line(at + d * 19.0, at + d * 25.0, UIPalette.ORANGE, 2.0, true)
