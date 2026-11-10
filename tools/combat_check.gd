extends SceneTree
## Combat check: stages fights in the spawn room of a real dungeon and verifies the
## combat rules with real physics and the real weapon / enemy code.
##
##   godot --headless -s tools/combat_check.gd
##
## Checks: lock timer before damage, damage amounts, walls block sight and bullets both
## ways, pistol kill + score, first-hit-only, rifle magazine/reserve/reload, pistol never
## runs out, brawler closes to melee, pursuer hovers and fires, pickups and kits, death
## ends the run, and the expected sounds were triggered.

var main
var p: Player
var failures := 0
var checks := 0


func _initialize() -> void:
	_run()


func ok(cond: bool, what: String) -> void:
	checks += 1
	if cond:
		print("  ok   ", what)
	else:
		failures += 1
		printerr("  FAIL ", what)


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func seconds(s: float) -> void:
	await frames(int(s * Engine.physics_ticks_per_second))


## Wait until the player has lost health (or timeout). Returns seconds waited, -1 if none.
func wait_damage(timeout: float) -> float:
	var h := p.health
	var n := 0
	while n < int(timeout * 60):
		await physics_frame
		n += 1
		if p.health < h:
			return n / 60.0
	return -1.0


func clear_enemies() -> void:
	for e in get_root().get_tree().get_nodes_in_group("hostiles"):
		e.queue_free()
	await frames(2)


func reset_player(pos: Vector3) -> void:
	p.alive = true
	p.health = p.max_health
	p.global_position = pos
	p.velocity = Vector3.ZERO
	await frames(2)


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.base_seed = 1
	main.enemies_enabled = false
	main.start_run()
	p = main.player
	p.input_enabled = false
	await frames(3)
	# Spawn room is always the 4 x 4 cell room at the origin: x, z in 0..16 m.
	var near := Vector3(8, 0, 13.5)

	print("turret: lock timer, damage, line of sight")
	await reset_player(near)
	var t: Enemy = main.spawn_enemy("turret", Vector3(8, 0, 2.5), 0)
	p.look_at_point(t.eye_position())
	var dt := await wait_damage(4.0)
	ok(dt > 0.0, "turret damages the player with clear sight (after %.2fs)" % dt)
	ok(dt >= t.fire_time - 0.05, "no damage before the lock timer (%.2fs >= %.2fs)" % [dt, t.fire_time])
	ok(is_equal_approx(p.max_health - p.health, t.damage), "turret hit = %d" % t.damage)

	var wall := StaticBody3D.new()
	wall.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 4, 0.4)
	cs.shape = box
	wall.add_child(cs)
	main.world.add_child(wall)
	wall.global_position = Vector3(8, 2, 8)
	await reset_player(near)
	ok(await wait_damage(3.0) < 0.0, "a wall between them: no damage for 3 s")
	var hp_before: float = t.hp
	p.look_at_point(t.eye_position())
	p.weapons.cooldown = 0.0
	p.weapons.try_fire()
	await frames(2)
	ok(t.hp == hp_before, "a wall stops the player's bullet")
	wall.queue_free()
	await frames(2)

	print("pistol: kill, score")
	await reset_player(near)
	p.invulnerable = true
	var shots := 0
	while is_instance_valid(t) and not t.dead and shots < 10:
		p.look_at_point(t.eye_position())
		p.weapons.cooldown = 0.0
		if p.weapons.try_fire():
			shots += 1
		await frames(3)
	ok(not is_instance_valid(t) or t.dead, "pistol destroys the turret")
	ok(shots == ceili(70.0 / 25.0), "in %d shots (70 hp / 25 dmg)" % shots)
	ok(main.kills == 1 and main.score == 100, "kills=%d score=%d (turret = 100)" % [main.kills, main.score])

	print("hitscan hits only the first hostile")
	await clear_enemies()
	var a: Enemy = main.spawn_enemy("pursuer", Vector3(8, 0, 8), 0)
	var b: Enemy = main.spawn_enemy("pursuer", Vector3(8, 0, 4), 0)
	a.frozen = true
	b.frozen = true
	await frames(3)
	p.look_at_point(a.eye_position())
	p.weapons.cooldown = 0.0
	p.weapons.try_fire()
	await frames(2)
	ok(a.hp < a.max_hp and b.hp == b.max_hp, "near pursuer hit (%d), far one untouched (%d)" % [a.hp, b.hp])
	await clear_enemies()

	print("rifle: magazine, reserve, reload; pistol never runs out")
	var w: WeaponHolder = p.weapons
	w.switch_to("rifle")
	await seconds(0.4)
	var start_mag := w.mag
	var start_res := w.reserve
	var fired := 0
	for i in 40:
		w.cooldown = 0.0
		if w.try_fire():
			fired += 1
		await frames(1)
	ok(fired == start_mag and w.mag == 0, "rifle fires exactly its magazine (%d) then stops" % fired)
	ok(w.start_reload(), "R starts a reload")
	await seconds(WeaponHolder.WEAPONS.rifle.reload + 0.2)
	ok(w.mag == start_mag and w.reserve == start_res - start_mag, "reload moves %d from reserve (%d left)" % [start_mag, w.reserve])
	w.switch_to("pistol")
	await seconds(0.4)
	ok(not w.start_reload(), "the pistol does not reload")
	fired = 0
	for i in 60:
		w.cooldown = 0.0
		if w.try_fire():
			fired += 1
		await frames(1)
	ok(fired == 60, "pistol fired 60 of 60 shots (never runs out)")

	print("brawler: closes to melee")
	p.invulnerable = false
	await reset_player(near)
	var br: Enemy = main.spawn_enemy("brawler", Vector3(8, 0, 2.5), 0)
	dt = await wait_damage(5.0)
	ok(dt > 0.0, "brawler reaches and strikes the player in %.2fs" % dt)
	ok(is_equal_approx(p.max_health - p.health, br.damage), "melee hit = %d" % br.damage)
	await clear_enemies()

	print("pursuer: hovers, fires")
	await reset_player(near)
	var pu: Pursuer = main.spawn_enemy("pursuer", Vector3(8, 0, 2.5), 0)
	await frames(10)
	ok(pu.body.global_position.y > 1.8, "pursuer hovers at %.1f m" % pu.body.global_position.y)
	dt = await wait_damage(4.0) + 10.0 / 60.0  # include the frames waited above
	ok(dt >= pu.fire_time - 0.05, "pursuer hits after its lock (%.2fs since spawn)" % dt)
	await clear_enemies()

	print("drops, pickups, kits")
	await reset_player(near)
	p.health = 50
	var hp_pick: Node = main.spawn_pickup("health", near)
	await frames(4)
	ok(p.health == 50 + Pickup.HEALTH_AMOUNT and not is_instance_valid(hp_pick), "health pickup heals at once")
	var res0: int = w.reserve
	main.spawn_pickup("ammo", near)
	await frames(4)
	ok(w.reserve == res0 + Pickup.AMMO_AMOUNT, "ammo pickup adds rifle reserve")
	for i in 4:
		main.spawn_pickup("kit", near)
		await frames(4)
	ok(p.kits == 3, "kits cap at 3")
	ok(main.get_tree().get_nodes_in_group("pickups").size() == 1, "a 4th kit stays on the floor")
	p.health = 30
	ok(p.use_kit() and p.health == 70 and p.kits == 2, "Q spends a kit and heals 40")
	p.health = p.max_health
	ok(not p.use_kit(), "no kit spent at full health")
	for n in main.get_tree().get_nodes_in_group("pickups"):
		n.queue_free()

	main.drop_rng.seed = 12345
	var drops := 0
	for i in 40:
		var before: int = main.get_tree().get_nodes_in_group("pickups").size()
		var e: Enemy = main.spawn_enemy("brawler", Vector3(2.5 + (i % 5) * 2.5, 0, 2.5), 0)
		e.frozen = true
		await frames(1)
		e.take_damage(1000)
		await frames(1)
		if main.get_tree().get_nodes_in_group("pickups").size() > before:
			drops += 1
	ok(drops > 5 and drops < 25, "some fallen enemies drop loot (%d of 40)" % drops)
	for n in main.get_tree().get_nodes_in_group("pickups"):
		n.queue_free()

	print("death ends the run")
	await reset_player(near)
	p.health = 5
	main.spawn_enemy("turret", Vector3(8, 0, 2.5), 0)
	await seconds(2.5)
	ok(not p.alive and main.state == "ended", "zero health ends the run in failure")

	print("sounds")
	for k in ["pistol", "rifle", "reload_out", "reload_in", "dry", "switch", "enemy_fire", "melee",
			"hurt", "enemy_die", "hit_enemy", "hit_wall", "pickup_health", "pickup_ammo", "pickup_kit", "use_kit", "lose"]:
		ok(Sfx.log.has(k), "sound '%s' played" % k)

	print("combat_check: %d checks, %s" % [checks, "PASS" if failures == 0 else "FAIL (%d)" % failures])
	quit(0 if failures == 0 else 1)
