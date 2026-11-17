class_name V2Map
extends Control
## The game's map (Tab; the run keeps going behind it), after the UI concept (v2/reference/ui/screens/Map.png):
## a white sign board with the floor plan drawn from the dungeon's layout, a ROUTE card and a KEY card on glass.
##   - a room that was entered: graphite, numbered in the order the rooms were found; the one the player is in: cyan,
##     with an arrow where they stand, turned the way they look;
##   - a room not yet entered: a dashed outline and "?" (the plan shows where rooms are, not what is in them);
##   - a corridor: solid between two rooms that were entered, dashed otherwise; a shut door: a bar across it;
##   - robots still working in a room that was entered: an orange badge with their number;
##   - the exit portal: its sign in its room, once that room was entered.
## The whole dungeon's extent sets the scale, so the plan does not move as rooms are found.
## What the concept leaves open: in a corridor no room is "current", so the arrow stands on the corridor in a cyan disc.

const BOARD := Rect2(48, 44, 920, 722)
const PLAN := Vector2(840, 560)
const WORDS := ["No", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Eleven", "Twelve"]

var game: Node

var _plan: Control
var _seen: Label
var _route: Label
var _route_help: Label
var _route_icon: TextureRect
var _room_box: StyleBoxFlat
var _here_box: StyleBoxFlat


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	V2Ui.full(self, Color(0, 0, 0, 0.55))                  # the view behind, darkened
	_room_box = StyleBoxFlat.new()
	_room_box.bg_color = UIPalette.GRAPHITE
	_room_box.set_corner_radius_all(3)
	_here_box = _room_box.duplicate()
	_here_box.bg_color = UIPalette.CYAN
	# --- the board
	var board := V2Ui.panel(self, UIPalette.sign_panel(), [32, 26, 32, 26])
	board.anchor_top = 0.5
	board.anchor_bottom = 0.5
	board.offset_left = BOARD.position.x
	board.offset_right = BOARD.end.x
	board.offset_top = BOARD.position.y - 405.0
	board.offset_bottom = BOARD.end.y - 405.0
	var col := V2Ui.column(board, 0)
	var head := V2Ui.row(col, 0)
	var title := V2Ui.text(head, "MAP", "c_extrabold", 44, UIPalette.GRAPHITE, 0.01)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seen = V2Ui.text(head, "", "semibold", 14, UIPalette.GRAPHITE, 0.12)
	_seen.size_flags_vertical = Control.SIZE_SHRINK_END
	var rule_gap := V2Ui.rect(col, Color(0, 0, 0, 0), 0, 2)
	rule_gap.custom_minimum_size = Vector2(0, 2)
	V2Ui.rect(col, UIPalette.GRAPHITE, 0, 2)
	V2Ui.rect(col, Color(0, 0, 0, 0), 0, 30)
	_plan = Control.new()
	_plan.custom_minimum_size = PLAN
	_plan.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_plan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plan.clip_contents = true
	_plan.draw.connect(_draw_plan)
	col.add_child(_plan)
	# --- the cards
	var side := V2Ui.column(self, 14)
	side.anchor_left = 1.0
	side.anchor_right = 1.0
	side.anchor_top = 0.5
	side.anchor_bottom = 0.5
	side.offset_left = -48.0 - 380.0
	side.offset_right = -48.0
	side.offset_top = BOARD.position.y - 405.0
	var glass := UIPalette.hud_panel(true)
	glass.bg_color.a = 0.82
	var route := V2Ui.column(V2Ui.panel(side, glass.duplicate(), [20, 18, 20, 20]), 12)
	V2Ui.text(route, "ROUTE", "bold", 11, UIPalette.LABEL, 0.24)
	var line := V2Ui.row(route, 12)
	_route_icon = V2Ui.icon(line, "exit_portal", 20, UIPalette.TEXT_SECONDARY)
	_route = V2Ui.text(line, "", "semibold", 16, UIPalette.TEXT)
	_route_help = V2Ui.text(route, "", "regular", 14, UIPalette.TEXT_SECONDARY)
	_route_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_route_help.custom_minimum_size = Vector2(338, 0)
	var key := V2Ui.column(V2Ui.panel(side, glass.duplicate(), [20, 18, 20, 20]), 10)
	V2Ui.text(key, "KEY", "bold", 11, UIPalette.LABEL, 0.24)
	for entry in ["You are here", "Explored", "Unexplored", "Hostiles seen", "Closed door", "Exit portal, once found"]:
		var r := V2Ui.row(key, 12)
		var sw := Control.new()
		sw.custom_minimum_size = Vector2(28, 20)
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sw.draw.connect(_draw_swatch.bind(sw, entry))
		r.add_child(sw)
		V2Ui.text(r, entry, "regular", 14, UIPalette.TEXT)
	var foot := V2Ui.row(side, 10)
	V2Ui.keycap(foot, "TAB")
	V2Ui.text(foot, "CLOSE · the run keeps going", "regular", 13, UIPalette.TEXT_SECONDARY, 0.06)
	visibility_changed.connect(_refresh)


func _process(_delta: float) -> void:
	if visible:
		_refresh()
		_plan.queue_redraw()


func _refresh() -> void:
	if game == null or game.gen == null or not visible:
		return
	var gen: DungeonGen = game.gen
	var seen: int = game.explored.size()
	var total := gen.rooms.size()
	_seen.text = "%d OF %d ROOMS SEEN" % [seen, total]
	var left := total - seen
	var unseen := "Every room has been seen." if left == 0 else "%s room%s still unseen." % [WORDS[mini(left, 12)], " is" if left == 1 else "s are"]
	if game.exit_found:
		var away: int = game.hud.rooms_to_exit()
		_route.text = "Exit portal: in this room" if away == 0 else "Exit portal: %d room%s away" % [away, "" if away == 1 else "s"]
		_route_help.text = "It stands in room %02d. %s" % [int(game.order.get(gen.exit_room, 0)), unseen]
		_route_icon.modulate = UIPalette.CYAN
	else:
		_route.text = "Exit portal not located"
		_route_help.text = "The exit waits in the final room. " + unseen
		_route_icon.modulate = UIPalette.TEXT_SECONDARY


# ---------------------------------------------------------------------------------------------- the floor plan
func _draw_plan() -> void:
	if game == null or game.gen == null:
		return
	var gen: DungeonGen = game.gen
	var c := _plan
	for i in range(0, int(PLAN.x) + 1, 20):                 # the faint grid
		c.draw_line(Vector2(i, 0), Vector2(i, PLAN.y), Color(UIPalette.GRAPHITE, 0.06), 1.0)
	for i in range(0, int(PLAN.y) + 1, 20):
		c.draw_line(Vector2(0, i), Vector2(PLAN.x, i), Color(UIPalette.GRAPHITE, 0.06), 1.0)
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for cell in gen.cells:
		lo = lo.min(Vector2(cell))
		hi = hi.max(Vector2(cell) + Vector2.ONE)
	var k := minf(minf((PLAN.x - 40.0) / (hi.x - lo.x), (PLAN.y - 40.0) / (hi.y - lo.y)), 34.0)
	var origin := PLAN / 2.0 - (lo + hi) / 2.0 * k
	var unseen_line := Color("8A9499")
	# --- corridors, then the doors across them
	for co in gen.corridors:
		var first: Vector2i = co.cells[0]
		var last: Vector2i = co.cells[co.cells.size() - 1]
		var along := Vector2(last - first).normalized() if co.cells.size() > 1 else Vector2(co.dir)
		var p0 := origin + (Vector2(first) + Vector2(0.5, 0.5) - along * 0.5) * k
		var p1 := origin + (Vector2(last) + Vector2(0.5, 0.5) + along * 0.5) * k
		if game.explored.has(co.a) and game.explored.has(co.b):
			c.draw_line(p0, p1, UIPalette.GRAPHITE, 6.0)
		else:
			c.draw_dashed_line(p0, p1, unseen_line, 3.0, 7.0)
	for d in game.dungeon.doors:
		if not d.door or d.open:
			continue
		var co_id: int = gen.cells[d.b].id
		var known := false
		for co in gen.corridors:
			if co.id == co_id:
				known = game.explored.has(co.a) or game.explored.has(co.b)
		if not known:
			continue
		# (drawn a little way out of the room's wall, where the mock-up has it)
		var mid: Vector2 = origin + (Vector2(d.a) + Vector2(0.5, 0.5) + Vector2(d.dir) * 0.5) * k + Vector2(d.dir) * 16.0
		var bar := Vector2(8, 26) if d.dir.x != 0 else Vector2(26, 8)
		c.draw_style_box(_room_box, Rect2(mid - bar / 2.0, bar))
	# --- rooms
	var here_room := -1
	if game.here >= 0 and game.dungeon.areas[game.here].room:
		here_room = int(game.dungeon.areas[game.here].id)
	for r in gen.rooms:
		var rect := Rect2(origin + Vector2(r.rect.position) * k, Vector2(r.rect.size) * k).grow(-1.0)
		if not game.explored.has(r.id):
			c.draw_rect(rect, UIPalette.FACILITY_WHITE)        # (a corridor's line stops at the outline)
			var q := rect.grow(-1.0)
			for e in [[q.position, Vector2(q.end.x, q.position.y)], [Vector2(q.end.x, q.position.y), q.end],
					[q.end, Vector2(q.position.x, q.end.y)], [Vector2(q.position.x, q.end.y), q.position]]:
				c.draw_dashed_line(e[0], e[1], unseen_line, 2.0, 6.0)
			c.draw_string(V2Ui.font("regular"), rect.position + Vector2(12, 29), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("6B757A"))
			continue
		var here := r.id == here_room
		c.draw_style_box(_here_box if here else _room_box, rect)
		var n := "%02d" % int(game.order.get(r.id, 0))
		c.draw_string(V2Ui.font("semibold" if here else "light"), rect.position + Vector2(12, 31), n, HORIZONTAL_ALIGNMENT_LEFT, -1, 22,
			UIPalette.GRAPHITE if here else UIPalette.TEXT)
		if r.id == gen.exit_room and game.exit_found:
			var e: Vector2 = origin + Vector2(gen.exit_pos.x, gen.exit_pos.z) / V2Dungeon.CELL * k
			c.draw_texture_rect(V2Ui.icon_texture("exit_portal"), Rect2(e - Vector2(13, 13), Vector2(26, 26)), false,
				UIPalette.GRAPHITE if here else UIPalette.CYAN)
		var hostiles := 0
		for robot: V2Robot in game.robots:
			if robot.state != V2Robot.DEAD and gen.room_at(V2Dungeon.cell_of(robot.global_position)) == r.id:
				hostiles += 1
		if hostiles > 0:
			var text := str(hostiles)
			var w := maxf(22.0, 12.0 + 8.0 * text.length())
			var pill := StyleBoxFlat.new()
			pill.bg_color = UIPalette.ORANGE
			pill.set_corner_radius_all(10)
			var pr := Rect2(rect.end.x - w - 8.0, rect.position.y + 8.0, w, 20)
			c.draw_style_box(pill, pr)
			c.draw_string(V2Ui.font("extrabold"), pr.position + Vector2(0, 15), text, HORIZONTAL_ALIGNMENT_CENTER, w, 13, UIPalette.GRAPHITE)
	# --- the player
	var at: Vector2 = origin + Vector2(game.player.global_position.x, game.player.global_position.z) / V2Dungeon.CELL * k
	var yaw: float = game.player._yaw
	if here_room < 0:
		c.draw_circle(at, 17.0, UIPalette.CYAN)
	# (the icon points up; yaw 0 looks along -z, which is up on the plan; a turn to the left is anticlockwise)
	c.draw_set_transform(at, -yaw)
	c.draw_texture_rect(V2Ui.icon_texture("player_arrow"), Rect2(-15, -15, 30, 30), false, UIPalette.GRAPHITE)
	c.draw_set_transform(Vector2.ZERO, 0.0)


func _draw_swatch(sw: Control, entry: String) -> void:
	var r := Rect2(0, 3, 28, 15)
	match entry:
		"You are here":
			sw.draw_rect(r, UIPalette.CYAN)
		"Explored":                                            # (graphite, as on the board; edged so it shows on the glass)
			sw.draw_rect(r, UIPalette.GRAPHITE)
			sw.draw_rect(r.grow(-0.5), UIPalette.TEXT_SECONDARY, false, 1.0)
		"Unexplored":
			var q := r.grow(-1.0)
			for e in [[q.position, Vector2(q.end.x, q.position.y)], [Vector2(q.end.x, q.position.y), q.end],
					[q.end, Vector2(q.position.x, q.end.y)], [Vector2(q.position.x, q.end.y), q.position]]:
				sw.draw_dashed_line(e[0], e[1], UIPalette.TEXT_SECONDARY, 2.0, 5.0)
		"Hostiles seen":
			var pill := StyleBoxFlat.new()
			pill.bg_color = UIPalette.ORANGE
			pill.set_corner_radius_all(8)
			sw.draw_style_box(pill, Rect2(4, 2, 20, 16))
			sw.draw_string(V2Ui.font("extrabold"), Vector2(4, 14), "1", HORIZONTAL_ALIGNMENT_CENTER, 20, 12, UIPalette.GRAPHITE)
		"Closed door":
			sw.draw_rect(Rect2(11, 1, 6, 18), UIPalette.TEXT)
		_:
			sw.draw_texture_rect(V2Ui.icon_texture("exit_portal"), Rect2(4, 0, 20, 20), false, UIPalette.CYAN)
