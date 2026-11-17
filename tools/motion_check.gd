extends SceneTree
## Movement / motion check in the lab: run, crouch, jump, recoil springs settle, reload
## completes, wrecks persist, lab pause freezes the world.
##   godot --headless -s tools/motion_check.gd
var fails := 0
func ok(c: bool, what: String) -> void:
	print("  ", "ok   " if c else "FAIL ", what)
	if not c: fails += 1
func frames(n: int) -> void:
	for i in n: await physics_frame
func _initialize() -> void: _run()
func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames(10)
	ok(main.lab and main.layout.rooms.size() == 1, "default launch is the one-room lab")
	var p: Player = main.player
	p.global_position = main.layout.player_spawn + Vector3(0, 0, 4)
	p.rotation.y = 0.0
	await frames(5)
	Input.action_press("move_forward")
	await frames(30)
	var walk := Vector2(p.velocity.x, p.velocity.z).length()
	Input.action_press("crouch")
	await frames(30)
	var crouch := Vector2(p.velocity.x, p.velocity.z).length()
	var eye := p.head.position.y
	Input.action_release("crouch")
	p.global_position = main.layout.player_spawn + Vector3(0, 0, 4)
	Input.action_press("sprint")
	await frames(30)
	var run := Vector2(p.velocity.x, p.velocity.z).length()
	Input.action_release("sprint")
	Input.action_release("crouch")
	Input.action_release("move_forward")
	ok(run > walk * 1.4, "run is faster (%.1f vs %.1f m/s)" % [run, walk])
	ok(crouch < walk * 0.7 and eye < 1.3, "crouch is slower (%.1f m/s), eye at %.2f m" % [crouch, eye])
	await frames(40)
	ok(p.head.position.y > 1.5, "standing eye back to %.2f m" % p.head.position.y)
	var y0 := p.global_position.y
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	var peak := y0
	for i in 60:
		await physics_frame
		peak = maxf(peak, p.global_position.y)
	ok(peak > y0 + 0.5 and p.is_on_floor(), "jump rises %.2f m and lands" % (peak - y0))
	var w: WeaponHolder = p.weapons
	w.switch_to("rifle")
	await frames(30)
	w.cooldown = 0.0
	w.try_fire()
	await frames(3)
	var kicked := w.view_model.position.z
	await frames(60)
	ok(absf(w._rk_pos.z) < 0.01 and absf(w._rk_rot.x) < 0.2, "recoil springs settle (kick z %.3f)" % kicked)
	ok(absf(p.punch.x) < 0.002, "view punch recovers")
	w.mag = 3
	ok(w.start_reload(), "reload starts")
	await frames(int(WeaponHolder.WEAPONS.rifle.reload * 60) + 10)
	ok(w.mag == 30 and w.reloading == 0.0, "reload completes (mag %d)" % w.mag)
	ok(Sfx.log.has("reload_in"), "mag-in sound at the slam")
	var e: Enemy = get_nodes_in_group("hostiles")[0]
	e.take_damage(9999)
	await frames(200)
	ok(get_nodes_in_group("wrecks").size() >= 1, "killed enemy leaves a wreck (%d)" % get_nodes_in_group("wrecks").size())
	main.set_paused(true)
	var pos := p.global_position
	Input.action_press("move_forward")
	await process_frame
	await process_frame
	ok(p.global_position == pos and paused, "pause freezes the world")
	Input.action_release("move_forward")
	main.set_paused(false)
	print("motion_check: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)
