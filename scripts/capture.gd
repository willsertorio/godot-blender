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
	p.invulnerable = true
	for e in get_tree().get_nodes_in_group("hostiles"):
		e.frozen = true  # the tour stages fights itself; nobody else acts
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

	await _combat(g)
	await _crate()
	await _map_view(g)
	await _overview(g)

	# Walk into the portal: proves the trigger, then the end screen.
	p.global_position = g.exit_pos
	await _wait(0.5)
	if main.state != "ended":
		push_error("capture: stepping into the portal did not end the run")
	await shot("06_end_screen")
	print("[capture] done -> ", dir)
	get_tree().quit()


func _combat(g: DungeonGen) -> void:
	var p: Player = main.player
	# Each enemy type engaging: telegraph frozen at 75 % of its lock.
	var dist := {"turret": 9.0, "pursuer": 7.0, "brawler": 3.2}
	var n := 8
	for kind in ["turret", "brawler", "pursuer"]:
		var e: Enemy = await _stage_enemy(g, kind, dist[kind])
		if e:
			e.capture_frac = 0.75
			await _settle(3)
			await shot("%02d_%s_engaging" % [n, kind])
			e.capture_frac = -1.0
		n += 1

	# Firing each weapon at a frozen pursuer in the spawn room, muzzle flash and tracer held.
	_clear_frozen_staging()
	var sr = g.rooms[g.spawn_room]
	var target: Enemy = main.spawn_enemy("pursuer", sr.center() + Vector3(0, 0, -4.5), g.spawn_room)
	target.frozen = true
	target.max_hp = 1000.0  # survives the weapon shots; killed on purpose below
	target.hp = 1000.0
	_place(sr.center() + Vector3(1.2, 0, 3.5), target.eye_position())
	await _settle(3)
	var w: WeaponHolder = p.weapons
	w.hold_fx = true
	w.cooldown = 0.0
	w.try_fire()
	await shot("11_fire_pistol")
	w.switch_to("rifle")
	await _wait(0.45)
	for i in 3:
		w.cooldown = 0.0
		w.try_fire()
		await _settle(2)
	await shot("12_fire_rifle")
	w.hold_fx = false

	# Aiming down sights (real input action, so the Player applies FOV + slow).
	p.input_enabled = true
	Input.action_press("aim")
	await _wait(0.5)
	await shot("13_aim_down_sights")
	Input.action_release("aim")
	p.input_enabled = false
	await _wait(0.3)

	# A kill: shards and flash a few frames after the killing shot.
	if is_instance_valid(target):
		target.take_damage(9999)
	await shot("14_enemy_destroyed", 1)  # effects are real-time; software GL is slow
	w.switch_to("pistol")


var _staged: Array[Enemy] = []


func _clear_frozen_staging() -> void:
	for e in _staged:
		if is_instance_valid(e):
			e.queue_free()
	_staged.clear()


## The first enemy of `kind` from the layout (or a fresh one in the spawn room), with the
## player placed `d` metres away inside the same room, in clear sight, facing it.
func _stage_enemy(g: DungeonGen, kind: String, d: float) -> Enemy:
	var e: Enemy = null
	for h in get_tree().get_nodes_in_group("hostiles"):
		if h.kind == kind and not h.dead:
			e = h
			break
	if e == null:
		e = main.spawn_enemy(kind, g.rooms[g.spawn_room].center() + Vector3(0, 0, -4), g.spawn_room)
		e.frozen = true
		_staged.append(e)
		await _settle(2)
	var r = g.rooms[e.room if e.room >= 0 else g.spawn_room]
	var lo := Vector2(r.rect.position) * DungeonGen.CELL + Vector2(1.2, 1.2)
	var hi := Vector2(r.rect.end) * DungeonGen.CELL - Vector2(1.2, 1.2)
	var to_c := r.center() - e.global_position
	to_c.y = 0
	var dirs: Array[Vector3] = []
	if to_c.length() > 0.5:
		dirs.append(to_c.normalized())
	dirs.append_array([Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT])
	var best_pos := Vector3.INF
	var best_err := INF
	for dv in dirs:
		var pos := e.global_position + dv * d
		pos.x = clampf(pos.x, lo.x, hi.x)
		pos.z = clampf(pos.z, lo.y, hi.y)
		_place(pos, e.eye_position() + Vector3.DOWN * 0.15)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var flat := Vector2(pos.x - e.global_position.x, pos.z - e.global_position.z).length()
		if e.has_los() and absf(flat - d) < best_err:
			best_err = absf(flat - d)
			best_pos = pos
	if best_pos != Vector3.INF:
		_place(best_pos, e.eye_position() + Vector3.DOWN * 0.15)
	e.face_player_now()
	return e


func _crate() -> void:
	## A container before and after opening (payoff pops out of the lid).
	var crates := get_tree().get_nodes_in_group("crates")
	if crates.is_empty():
		return
	var c: LootCrate = crates[0]
	var front := c.global_position - c.global_transform.basis.z * 2.8
	front.y = 0
	_place(front + c.global_transform.basis.x * 0.6, c.global_position + Vector3.UP * 0.5)
	main.player.health = 60.0  # so a health payoff is taken, not left waiting
	await shot("15_container_closed")
	c.interact(main.player)
	await _wait(0.25)
	await shot("16_container_open", 1)
	main.player.health = 100.0


func _map_view(g: DungeonGen) -> void:
	## Tab map after the tour so far (several rooms explored, exit found).
	main.ui.map.visible = true
	await shot("17_map")
	main.ui.map.visible = false


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
	main.light_cull_enabled = false
	main.cull_lights()
	var env: Environment = main.get_node("WorldEnvironment").environment
	var amb := env.ambient_light_energy
	env.ambient_light_energy = 1.5
	main.ui.hud.hide()
	await shot("07_overview")
	main.ui.hud.show()
	env.ambient_light_energy = amb
	cam.queue_free()
	main.player.camera.current = true
	main.light_cull_enabled = true


func _place(pos: Vector3, look: Vector3) -> void:
	var p: Player = main.player
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.look_at_point(look)
	main.cull_lights()


func _open_doors() -> void:
	for door in main.world.get_node("Doors").get_children():
		if not door.is_open:
			door.interact(main.player)


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func shot(name: String, settle_frames: int = 4) -> void:
	await _settle(settle_frames)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := dir.path_join(name + ".png")
	img.save_png(path)
	print("[capture] ", path)
