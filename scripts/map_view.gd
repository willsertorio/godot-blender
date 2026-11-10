class_name MapView
extends Control
## Tab map. Shows what the player knows: explored rooms (cyan), explored rooms that still
## hold hostiles (red, with a dot per hostile), the exit room and portal once found
## (violet), corridors walked, unexplored exits as stubs, closed doors, and the player.
## The game keeps running while it is open (no pause, as in the GDD).

const CYAN := Color("#22E5FF")
const RED := Color("#FF2D55")
const VIOLET := Color("#B48CFF")
const GREEN := Color("#39FF88")

var main
var font: Font  # headings (Kenney Future)
var font_body: Font = ThemeDB.fallback_font  # legend: Kenney Future draws X and K like H


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if main == null or main.layout == null or main.player == null:
		return
	var g: DungeonGen = main.layout
	var vp := get_viewport_rect().size
	var panel := Rect2(vp * 0.12, vp * 0.76)
	draw_rect(panel, Color(0.01, 0.03, 0.045, 0.88))
	draw_rect(panel, Color(CYAN, 0.6), false, 2.0)
	if font:
		draw_string(font, panel.position + Vector2(18, 30), "DATASPACE MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, CYAN)
		draw_string(font, panel.position + Vector2(panel.size.x - 18, 30), "TAB  CLOSE", HORIZONTAL_ALIGNMENT_RIGHT, -1, 14, Color(CYAN, 0.7))

	# Fit the whole layout's bounds (not just what is explored) so the map never rescales.
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in g.cells:
		lo = Vector2(minf(lo.x, c.x), minf(lo.y, c.y))
		hi = Vector2(maxf(hi.x, c.x + 1), maxf(hi.y, c.y + 1))
	var area := Rect2(panel.position + Vector2(30, 50), panel.size - Vector2(60, 100))
	var scale := minf(area.size.x / (hi.x - lo.x), area.size.y / (hi.y - lo.y))
	var origin := area.position + (area.size - (hi - lo) * scale) * 0.5 - lo * scale
	var cell_rect := func(c: Vector2i) -> Rect2:
		return Rect2(origin + Vector2(c) * scale, Vector2.ONE * scale)

	var visited: Dictionary = main.visited
	var walked: Dictionary = main.visited_cells
	var hostile_rooms: Dictionary = main.hostiles_by_room()

	# Corridors: walked cells, plus a one-cell stub where an explored room has an unexplored exit.
	for co in g.corridors:
		for i in co.cells.size():
			var c: Vector2i = co.cells[i]
			var stub: bool = (i == 0 and visited.has(co.a)) or (i == co.cells.size() - 1 and visited.has(co.b))
			if walked.has(c):
				draw_rect(cell_rect.call(c).grow(-scale * 0.18), Color(CYAN, 0.35))
			elif stub:
				draw_rect(cell_rect.call(c).grow(-scale * 0.3), Color(CYAN, 0.18))

	for r in g.rooms:
		var known: bool = visited.has(r.id) or (r.id == g.exit_room and main.exit_found)
		if not known:
			continue
		var rect := Rect2(origin + Vector2(r.rect.position) * scale, Vector2(r.rect.size) * scale).grow(-2)
		var col := CYAN
		var n: int = hostile_rooms.get(r.id, 0)
		if r.id == g.exit_room:
			col = VIOLET
		elif n > 0:
			col = RED
		draw_rect(rect, Color(col, 0.16))
		draw_rect(rect, Color(col, 0.85), false, 2.0)
		if n > 0:
			for k in n:
				draw_circle(rect.position + Vector2(10 + k * 12, 10), 4.0, RED)
		if r.id == g.exit_room:
			var pc := origin + Vector2(g.exit_pos.x, g.exit_pos.z) / DungeonGen.CELL * scale
			var d := scale * 0.35
			draw_colored_polygon(PackedVector2Array([pc + Vector2(0, -d), pc + Vector2(d, 0), pc + Vector2(0, d), pc + Vector2(-d, 0)]), VIOLET)

	# Closed doors on known ground.
	for door: Door in main.world.get_node("Doors").get_children():
		if door.is_open:
			continue
		var a: Vector2i = door.get_meta("room_cell")
		if not visited.has(g.room_at(a)) and not walked.has(door.get_meta("corr_cell")):
			continue
		var b: Vector2i = door.get_meta("corr_cell")
		var mid := origin + (Vector2(a) + Vector2(b) + Vector2.ONE) * 0.5 * scale
		var along := Vector2(absf(b.y - a.y), absf(b.x - a.x)) * scale * 0.3
		draw_line(mid - along, mid + along, CYAN, 4.0)

	# Player arrow.
	var p: Player = main.player
	var pp := origin + Vector2(p.global_position.x, p.global_position.z) / DungeonGen.CELL * scale
	var fwd := -p.global_transform.basis.z
	var f := Vector2(fwd.x, fwd.z).normalized()
	var side := Vector2(-f.y, f.x)
	var s := maxf(7.0, scale * 0.28)
	draw_colored_polygon(PackedVector2Array([pp + f * s * 1.4, pp - f * s * 0.7 + side * s * 0.8, pp - f * s * 0.3, pp - f * s * 0.7 - side * s * 0.8]), Color.WHITE)

	if font:
		var y := panel.end.y - 20
		var x := panel.position.x + 24
		for item in [[CYAN, "EXPLORED"], [RED, "HOSTILES"], [VIOLET, "EXIT"], [Color.WHITE, "YOU"]]:
			draw_rect(Rect2(Vector2(x, y - 11), Vector2(12, 12)), item[0])
			draw_string(font_body, Vector2(x + 18, y), item[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.92, 0.96))
			x += 130
