class_name CaptureTour
extends Node
## Scripted screenshot tour for a fixed seed. Launched by `--capture=DIR`
## (see tools/capture.sh). Each view places the player camera deterministically
## from the layout, waits for the frame to settle and saves DIR/<name>.png.
## Views that need features not built yet are skipped, so the list only grows.

var main
var dir: String


func run(p_main, p_dir: String) -> void:
	main = p_main
	dir = p_dir
	DirAccess.make_dir_recursive_absolute(dir)
	await _settle(4)
	main.ui.show_title()
	await shot("00_title")

	main.start_run()
	var p: Player = main.player
	p.input_enabled = false
	await _settle(6)
	await shot("01_spawn")

	var g: DungeonGen = main.layout
	var doors: Array = main.world.get_node("Doors").get_children()
	if doors.size() > 0:
		var door: Door = doors[0]
		_place(door.global_position + door.global_transform.basis.z * 3.6, door.interact_point())
		await shot("02_door_closed")
		door.interact(p)
		await _wait(1.0)
		await shot("03_door_open")

	# Longest corridor, standing at one end looking down its length.
	var best: DungeonGen.Corridor = g.corridors[0]
	for co in g.corridors:
		if co.cells.size() > best.cells.size():
			best = co
	var a := DungeonGen.cell_center(best.cells[0])
	var d := Vector3(best.dir.x, 0, best.dir.y)
	_open_doors()
	_place(a - d * 1.5, a + d * 20.0 + Vector3.UP * 1.6)
	await shot("04_corridor")

	# Exit room seen from its entrance.
	var er = g.rooms[g.exit_room]
	var entry := DungeonGen.cell_center(er.doorway_cells[0])
	_place(entry, g.exit_pos + Vector3.UP * 1.4)
	await shot("05_exit_room")

	await _overview(g)

	# Walk into the portal: proves the trigger, then the end screen.
	p.global_position = g.exit_pos
	await _wait(0.5)
	if main.state != "ended":
		push_error("capture: stepping into the portal did not end the run")
	await shot("06_end_screen")
	print("[capture] done -> ", dir)
	get_tree().quit()


func _overview(g: DungeonGen) -> void:
	## Top-down orthographic view of the whole layout, ceilings culled.
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in g.cells:
		lo = Vector2(minf(lo.x, c.x), minf(lo.y, c.y))
		hi = Vector2(maxf(hi.x, c.x + 1), maxf(hi.y, c.y + 1))
	var size := (hi - lo) * DungeonGen.CELL
	var mid := (lo + hi) * 0.5 * DungeonGen.CELL
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(size.y, size.x * 720.0 / 1280.0) + 8.0
	cam.cull_mask = 0xFFFFF & ~DungeonBuilder.CEILING_LAYER
	cam.far = 200.0
	main.world.add_child(cam)
	cam.global_position = Vector3(mid.x, 60, mid.y)
	cam.rotation_degrees.x = -90
	cam.current = true
	var env: Environment = main.get_node("WorldEnvironment").environment
	var amb := env.ambient_light_energy
	env.ambient_light_energy = 1.5
	main.ui.hud.hide()
	await shot("07_overview")
	main.ui.hud.show()
	env.ambient_light_energy = amb
	cam.queue_free()
	main.player.camera.current = true


func _place(pos: Vector3, look: Vector3) -> void:
	var p: Player = main.player
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.look_at_point(look)


func _open_doors() -> void:
	for door in main.world.get_node("Doors").get_children():
		if not door.is_open:
			door.interact(main.player)


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func shot(name: String) -> void:
	await _settle(4)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := dir.path_join(name + ".png")
	img.save_png(path)
	print("[capture] ", path)
