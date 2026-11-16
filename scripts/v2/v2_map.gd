class_name V2Map
extends Control
## The game's map (Tab; the game goes on behind it): the rooms the player has been in, with the number of robots
## still working in each, the corridors walked, the doorways of what is known (amber = a shut door, green = an open
## one, grey = no door), the exit portal once its room has been entered, and where the player stands and looks.
## Drawn from the dungeon's layout (cells of 4 m); the whole dungeon's extent sets the scale, so the map does not
## grow as rooms are found, and how much of the panel is still empty says how much is left to find.

var game: Node


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if game == null or game.gen == null:
		return
	var gen: DungeonGen = game.gen
	var view := get_viewport_rect().size
	var panel := Rect2(view * 0.16, view * 0.68)
	draw_rect(panel, Color(0.02, 0.03, 0.045, 0.86))
	draw_rect(panel, V2Ui.CYAN, false, 2.0)
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for c in gen.cells:
		lo = lo.min(Vector2(c))
		hi = hi.max(Vector2(c) + Vector2.ONE)
	var inner := panel.grow(-34.0)
	var k := minf(inner.size.x / (hi.x - lo.x), inner.size.y / (hi.y - lo.y))
	var origin := inner.get_center() - (lo + hi) / 2.0 * k
	var font := ThemeDB.fallback_font
	for co in gen.corridors:
		if game.walked.has(co.id):
			for c in co.cells:
				draw_rect(Rect2(origin + Vector2(c) * k, Vector2(k, k)).grow(-k * 0.18), Color(0.3, 0.5, 0.58, 0.7))
	for r in gen.rooms:
		if not game.explored.has(r.id):
			continue
		var rect := Rect2(origin + Vector2(r.rect.position) * k, Vector2(r.rect.size) * k)
		draw_rect(rect, Color(0.13, 0.42, 0.5, 0.55))
		draw_rect(rect, V2Ui.CYAN, false, 1.5)
		var hostiles := 0
		for robot in game.robots:
			if robot.state != V2Robot.DEAD and gen.room_at(V2Dungeon.cell_of(robot.global_position)) == r.id:
				hostiles += 1
		if hostiles > 0:
			draw_string(font, rect.get_center() + Vector2(-6, 7), str(hostiles), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, V2Ui.RED)
		if r.id == gen.exit_room and game.exit_found:
			var e: Vector2 = origin + Vector2(gen.exit_pos.x, gen.exit_pos.z) / V2Dungeon.CELL * k
			draw_colored_polygon(PackedVector2Array([e + Vector2(0, -9), e + Vector2(9, 0), e + Vector2(0, 9), e + Vector2(-9, 0)]), V2Ui.VIOLET)
	for d in game.dungeon.doors:
		var room_id: int = gen.room_at(d.a)
		var corr_id: int = gen.cells[d.b].id
		if not (game.explored.has(room_id) or game.walked.has(corr_id)):
			continue
		var mid: Vector2 = origin + (Vector2(d.a) + Vector2(0.5, 0.5) + Vector2(d.dir) * 0.5) * k
		var along := Vector2(-d.dir.y, d.dir.x) * k * 0.3
		draw_line(mid - along, mid + along, (V2Ui.GREEN if d.open else Color(1.0, 0.6, 0.15)) if d.door else Color(0.6, 0.66, 0.7), 3.0)
	# the player: an arrow where they stand, pointing where they look
	var at: Vector2 = origin + Vector2(game.player.global_position.x, game.player.global_position.z) / V2Dungeon.CELL * k
	var yaw: float = game.player._yaw
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(-fwd.y, fwd.x)
	draw_colored_polygon(PackedVector2Array([at + fwd * 10.0, at - fwd * 6.0 + side * 6.0, at - fwd * 6.0 - side * 6.0]), Color(1, 1, 1))
	draw_string(font, panel.position + Vector2(16, 24), "MAP   rooms %d / %d   ·   red number: robots in a room   ·   violet: the exit   ·   Tab closes" % [
		game.explored.size(), gen.rooms.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.78, 0.86, 0.9))
