class_name V2Fx
## V2 effects rebuilt for Godot (the Blender ones are Cycles-only): tracers, impact sparks, chips and dust, scorch
## marks, smoke, and the point lights that go with the muzzle-flash meshes of the glbs.
## Everything is unshaded (the rooms' lights only reach their own render layer) and alpha-blended, never additive.

static var root: Node3D            # where spawned effects are parented (the lab)
static var hold := 1.0             # > 1 keeps tracers and impact lights longer (screenshots)
static var _cache: Dictionary = {}
static var _marks: Array[MeshInstance3D] = []
static var _mark_i := 0

const YELLOW := Color(1.0, 0.82, 0.45)
const RED := Color(1.0, 0.3, 0.12)
const DUST := Color(0.74, 0.73, 0.7)
const SMOKE := Color(0.11, 0.11, 0.12)
const GUNSMOKE := Color(0.82, 0.82, 0.8)
const MAX_MARKS := 40


static func _unshaded(key: String, color: Color, energy: float, alpha: float = 1.0) -> StandardMaterial3D:
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, alpha)
		if alpha < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_cache[key] = m
	return _cache[key]


## A soft round blob: opaque in the middle, gone at the rim.
static func _soft() -> Texture2D:
	if not _cache.has("soft"):
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.5, Color(1, 1, 1, 0.5))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_cache["soft"] = t
	return _cache["soft"]


## A billow of smoke: a round puff broken up by noise (lumps and holes), not a clean disc. Built once.
static func _billow() -> Texture2D:
	if not _cache.has("billow"):
		var noise := FastNoiseLite.new()
		noise.seed = 7
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.fractal_octaves = 4
		noise.frequency = 0.035
		var n := 96
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var p := Vector2(x + 0.5, y + 0.5) / n * 2.0 - Vector2.ONE
				# (the rim is pushed in and out by the noise, the body has dense and thin patches)
				var r := p.length() + 0.22 * noise.get_noise_2d(x * 1.7 + 40.0, y * 1.7)
				var body := clampf(1.0 - r, 0.0, 1.0)
				var dens := clampf(0.62 + 0.75 * noise.get_noise_2d(x, y), 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, clampf(pow(body, 0.8) * 1.7 * dens, 0.0, 1.0)))
		_cache["billow"] = ImageTexture.create_from_image(img)
	return _cache["billow"]


static func _billow_material() -> StandardMaterial3D:
	if not _cache.has("billow_mat"):
		var m := (_puff_material().duplicate()) as StandardMaterial3D
		m.albedo_texture = _billow()
		_cache["billow_mat"] = m
	return _cache["billow_mat"]


## Material of smoke / dust particles: soft blobs facing the camera, coloured and faded per particle.
static func _puff_material() -> StandardMaterial3D:
	if not _cache.has("puff"):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_texture = _soft()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.vertex_color_use_as_albedo = true
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_cache["puff"] = m
	return _cache["puff"]


static func _later(seconds: float, node: Node) -> void:
	root.get_tree().create_timer(seconds).timeout.connect(node.queue_free)


static func _smoke_particles(color: Color, alpha: float, size: float, life: float, rise: float) -> CPUParticles3D:
	var s := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	s.mesh = quad
	s.material_override = _puff_material()
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.lifetime = life
	s.direction = Vector3.UP
	s.spread = 25.0
	s.initial_velocity_min = rise * 0.6
	s.initial_velocity_max = rise
	s.gravity = Vector3(0, rise * 0.25, 0)
	s.damping_min = 0.4
	s.damping_max = 0.8
	s.angle_min = 0.0
	s.angle_max = 360.0
	s.scale_amount_min = size * 0.7
	s.scale_amount_max = size * 1.2
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.3))
	grow.add_point(Vector2(0.4, 0.8))
	grow.add_point(Vector2(1, 1.0))
	s.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(color.r, color.g, color.b, 0.0))
	fade.add_point(0.15, Color(color.r, color.g, color.b, alpha))
	fade.set_color(2, Color(color.r, color.g, color.b, 0.0))
	s.color_ramp = fade
	return s


## A puff of smoke or dust that swells, drifts along `dir` and fades.
static func puff(pos: Vector3, dir: Vector3, color: Color, size: float, amount: int = 5, life: float = 0.9,
		alpha: float = 0.35, speed: float = 0.6) -> void:
	if root == null:
		return
	var s := _smoke_particles(color, alpha, size, life, speed)
	s.amount = amount
	s.one_shot = true
	s.explosiveness = 0.85
	s.direction = dir
	s.spread = 40.0
	root.add_child(s)
	s.global_position = pos
	s.emitting = true
	_later(life + 0.6, s)


## The smoke of a burning wreck; switch it with set_smoke(). Three layers and a light:
##  - a thick black roll at the base, lit orange from inside where it leaves the fire
##  - a column that climbs to the ceiling, slowing and spreading into a grey-black pall
##  - a few embers carried up with it
##  - a flickering orange light on the wreck
## Billowed sprites that turn slowly, black where it is dense (the old smoke was round grey blobs).
static func smoke_column(parent: Node3D, local_pos: Vector3, size: float = 0.7) -> CPUParticles3D:
	var s := _smoke_particles(Color(0.035, 0.035, 0.04), 0.96, size * 1.15, 5.2, 1.7)
	s.material_override = _billow_material()
	s.amount = 60
	s.spread = 9.0
	s.damping_min = 0.22                               # (it slows as it climbs: it gathers under the ceiling)
	s.damping_max = 0.34
	s.angular_velocity_min = -28.0
	s.angular_velocity_max = 28.0
	s.initial_velocity_min = 1.3
	s.initial_velocity_max = 1.9
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.28))
	grow.add_point(Vector2(0.25, 0.75))
	grow.add_point(Vector2(1, 1.9))
	s.scale_amount_curve = grow
	var fade := Gradient.new()                         # out of the fire: orange for a moment, black, thinning to dark grey
	fade.set_color(0, Color(0.9, 0.35, 0.06, 0.0))
	fade.add_point(0.03, Color(0.55, 0.2, 0.04, 0.9))
	fade.add_point(0.1, Color(0.03, 0.03, 0.035, 0.97))
	fade.add_point(0.55, Color(0.05, 0.05, 0.055, 0.8))
	fade.set_color(fade.get_point_count() - 1, Color(0.13, 0.13, 0.14, 0.0))
	s.color_ramp = fade
	s.emitting = false
	s.local_coords = false
	parent.add_child(s)
	s.position = local_pos
	var roll := _smoke_particles(Color(0.02, 0.02, 0.024), 0.98, size * 0.9, 1.5, 0.75)     # the black roll at the base
	roll.material_override = _billow_material()
	roll.amount = 22
	roll.spread = 55.0
	roll.angular_velocity_min = -50.0
	roll.angular_velocity_max = 50.0
	roll.emitting = false
	roll.local_coords = false
	s.add_child(roll)
	var embers := CPUParticles3D.new()
	var dot := BoxMesh.new()
	dot.size = Vector3(0.012, 0.012, 0.012)
	embers.mesh = dot
	embers.material_override = _unshaded("ember", Color(1.0, 0.5, 0.12), 4.0)
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	embers.amount = 14
	embers.lifetime = 1.6
	embers.direction = Vector3.UP
	embers.spread = 35.0
	embers.initial_velocity_min = 0.8
	embers.initial_velocity_max = 2.2
	embers.gravity = Vector3(0, 0.6, 0)
	embers.scale_amount_min = 0.5
	embers.scale_amount_max = 1.3
	embers.emitting = false
	embers.local_coords = false
	s.add_child(embers)
	var fire := OmniLight3D.new()
	fire.light_color = Color(1.0, 0.5, 0.18)
	fire.light_energy = 0.0
	fire.omni_range = 3.2
	fire.position = Vector3(0, 0.25, 0)
	fire.visible = false
	s.add_child(fire)
	s.set_meta("fire", fire)
	var crackle := V2Sfx.loop("fire", s)
	if crackle != null:
		s.set_meta("crackle", crackle)
	return s


static func set_smoke(s: CPUParticles3D, on: bool) -> void:
	if s == null:
		return
	s.emitting = on
	for c in s.get_children():
		if c is CPUParticles3D:
			(c as CPUParticles3D).emitting = on
	var fire := s.get_meta("fire") as OmniLight3D
	fire.visible = on
	if s.has_meta("crackle"):
		V2Sfx.drive(s.get_meta("crackle") as AudioStreamPlayer3D, on)
	if s.has_meta("flicker"):
		(s.get_meta("flicker") as Tween).kill()
		s.remove_meta("flicker")
	if on and s.is_inside_tree():
		var tw := s.create_tween().set_loops()
		for e in [1.5, 0.7, 1.2, 0.5, 1.6, 0.9, 1.3, 0.6]:
			tw.tween_property(fire, "light_energy", e, 0.07 + 0.05 * fmod(e * 7.0, 1.0))
		s.set_meta("flicker", tw)


## A bright streak along a bullet's path, gone after two frames.
static func tracer(from: Vector3, to: Vector3, color: Color) -> void:
	var d := to - from
	var ln := d.length()
	if ln < 0.4 or root == null:
		return
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.008, 0.008, 1.0)
	mi.mesh = box
	mi.material_override = _unshaded("tracer" + color.to_html(), color, 5.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var up := Vector3.RIGHT if absf(d.normalized().y) > 0.98 else Vector3.UP
	mi.global_transform = Transform3D(Basis.looking_at(d, up) * Basis.from_scale(Vector3(1, 1, ln * 0.8)), from + d * 0.55)
	_later(0.08 * hold, mi)


## A dark mark where a round hit a wall or the floor (a ring of them: the oldest is reused).
static func scorch(pos: Vector3, normal: Vector3, big: float = 0.0) -> void:
	var mi: MeshInstance3D
	if _marks.size() < MAX_MARKS:
		mi = MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(1, 1)
		mi.mesh = quad
		if not _cache.has("scorch"):
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_texture = _soft()
			m.albedo_color = Color(0.02, 0.02, 0.022, 0.8)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			_cache["scorch"] = m
		mi.material_override = _cache["scorch"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		_marks.append(mi)
	else:
		mi = _marks[_mark_i]
		_mark_i = (_mark_i + 1) % MAX_MARKS
	var up := Vector3.RIGHT if absf(normal.y) > 0.9 else Vector3.UP
	var size := big if big > 0.0 else randf_range(0.09, 0.16)
	mi.global_transform = Transform3D(Basis.looking_at(-normal, up).rotated(normal, randf() * TAU) * Basis.from_scale(Vector3.ONE * size),
		pos + normal * 0.004)


## Where a round lands: a shower of sparks, chips, a puff of dust, a short flash of light; a scorch mark on the room.
static func impact(pos: Vector3, normal: Vector3, metal: bool = false) -> void:
	if root == null:
		return
	V2Sfx.play("impact_metal" if metal else "impact_concrete", pos)
	var p := CPUParticles3D.new()
	var streak := BoxMesh.new()
	streak.size = Vector3(0.005, 0.07, 0.005)
	p.mesh = streak
	p.material_override = _unshaded("spark", Color(1.0, 0.62, 0.22), 6.0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.particle_flag_align_y = true
	p.amount = 34 if metal else 20
	p.lifetime = 0.35
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = normal
	p.spread = 65.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 7.5
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.2
	root.add_child(p)
	p.global_position = pos + normal * 0.02
	p.emitting = true
	_later(1.0, p)
	var c := CPUParticles3D.new()                      # chips knocked off
	var chip := BoxMesh.new()
	chip.size = Vector3(0.016, 0.008, 0.012)
	c.mesh = chip
	c.material_override = _unshaded("chip_metal" if metal else "chip", Color(0.12, 0.12, 0.13) if metal else Color(0.55, 0.55, 0.54), 1.0)
	c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.amount = 5
	c.lifetime = 0.75
	c.one_shot = true
	c.explosiveness = 1.0
	c.direction = normal
	c.spread = 55.0
	c.initial_velocity_min = 1.2
	c.initial_velocity_max = 3.2
	c.gravity = Vector3(0, -9.8, 0)
	c.scale_amount_min = 0.6
	c.scale_amount_max = 1.6
	root.add_child(c)
	c.global_position = pos + normal * 0.02
	c.emitting = true
	_later(1.4, c)
	puff(pos + normal * 0.06, normal, SMOKE if metal else DUST, 0.3 if metal else 0.42, 5, 0.9, 0.3 if metal else 0.38)
	if not metal:
		scorch(pos, normal)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.65, 0.3)
	l.light_energy = 2.0
	l.omni_range = 2.5
	root.add_child(l)
	l.global_position = pos + normal * 0.1
	_later(0.07 * hold, l)


## A shower of sparks only (a damaged machine shedding them).
static func sparks(pos: Vector3, dir: Vector3 = Vector3.UP, amount: int = 16) -> void:
	if root == null:
		return
	V2Sfx.play("zap", pos)
	var p := CPUParticles3D.new()
	var streak := BoxMesh.new()
	streak.size = Vector3(0.005, 0.07, 0.005)
	p.mesh = streak
	p.material_override = _unshaded("spark", Color(1.0, 0.62, 0.22), 6.0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.particle_flag_align_y = true
	p.amount = amount
	p.lifetime = 0.45
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = dir
	p.spread = 80.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 8.0
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.3
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	_later(1.2, p)


## It blows up: a fireball that turns to black smoke, sparks and debris in every direction, a hard flash, a burn
## mark on the floor under it.
static func explosion(pos: Vector3) -> void:
	if root == null:
		return
	V2Sfx.play("explosion", pos)
	for n in [Vector3.UP, Vector3(1, 0.4, 0).normalized(), Vector3(-0.5, 0.4, 0.8).normalized(), Vector3(-0.5, 0.4, -0.8).normalized(),
			Vector3(0.6, 0.2, 0.7).normalized(), Vector3(-0.7, 0.2, -0.3).normalized()]:
		impact(pos + n * 0.2, n, true)
	sparks(pos, Vector3.UP, 70)
	var ball := _smoke_particles(Color(1.0, 0.55, 0.15), 0.95, 1.5, 0.5, 2.6)      # the fireball
	ball.material_override = _billow_material()
	ball.amount = 14
	ball.one_shot = true
	ball.explosiveness = 0.95
	ball.spread = 180.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.9, 0.6, 0.95))
	fade.add_point(0.25, Color(1.0, 0.5, 0.12, 0.95))
	fade.add_point(0.6, Color(0.25, 0.08, 0.02, 0.9))
	fade.set_color(fade.get_point_count() - 1, Color(0.03, 0.03, 0.03, 0.0))
	ball.color_ramp = fade
	root.add_child(ball)
	ball.global_position = pos + Vector3(0, 0.2, 0)
	ball.emitting = true
	_later(1.4, ball)
	var cloud := _smoke_particles(Color(0.03, 0.03, 0.035), 0.95, 1.7, 2.6, 1.6)   # what it leaves
	cloud.material_override = _billow_material()
	cloud.amount = 16
	cloud.one_shot = true
	cloud.explosiveness = 0.85
	cloud.spread = 70.0
	root.add_child(cloud)
	cloud.global_position = pos + Vector3(0, 0.3, 0)
	cloud.emitting = true
	_later(3.4, cloud)
	for k in 3:
		scorch(Vector3(pos.x + randf_range(-0.35, 0.35), 0.0, pos.z + randf_range(-0.35, 0.35)), Vector3.UP, randf_range(0.7, 1.1))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.62, 0.28)
	l.light_energy = 9.0
	l.omni_range = 10.0
	root.add_child(l)
	l.global_position = pos + Vector3(0, 0.4, 0)
	_later(0.16 * hold, l)


## A robot is destroyed: sparks in every direction, a ball of dark smoke, a flash of light.
static func burst(pos: Vector3) -> void:
	if root == null:
		return
	V2Sfx.play("robot_break", pos)
	for n in [Vector3.UP, Vector3(1, 0.3, 0).normalized(), Vector3(-0.5, 0.3, 0.8).normalized(), Vector3(-0.5, 0.3, -0.8).normalized()]:
		impact(pos + n * 0.15, n, true)
	puff(pos, Vector3.UP, Color(0.04, 0.04, 0.045), 1.1, 9, 1.6, 0.9, 1.2)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.25)
	l.light_energy = 5.0
	l.omni_range = 6.0
	root.add_child(l)
	l.global_position = pos + Vector3(0, 0.2, 0)
	_later(0.12 * hold, l)


## The flash meshes under `scene` (shown by the animations through their scale), each with a point light beside it.
## Returns [{node, light, on}]; poll() switches the lights and returns the flashes that have just lit up.
static func flashes(scene: Node) -> Array:
	var out: Array = []
	for n in scene.find_children("*Flash*", "MeshInstance3D", true, false):
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.7, 0.4)
		l.light_energy = 2.5
		l.omni_range = 5.0
		l.visible = false
		n.get_parent().add_child(l)
		l.position = (n as Node3D).position
		out.append({"node": n, "light": l, "on": false})
	return out


## The flash nodes whose shot time the animation passed since the last call. events = V2Assets.flash_events(asset),
## st = a dictionary this function keeps the clip and position in, list = flashes(scene). Also switches the lights.
static func fired(ap: AnimationPlayer, events: Dictionary, st: Dictionary, list: Array) -> Array:
	poll(list)
	var out: Array = []
	var cur_clip := String(ap.current_animation)
	if not ap.is_playing() or cur_clip == "":
		return out
	var cur := ap.current_animation_position
	if cur_clip != st.get("clip", "") or cur < st.get("pos", 0.0):
		st["clip"] = cur_clip
		st["pos"] = -0.001
	for e in events.get(cur_clip, []):
		if e[0] > st["pos"] and e[0] <= cur:
			for f in list:
				if String((f.node as Node).name) == e[1]:
					out.append(f.node)
	st["pos"] = cur
	return out


static func poll(list: Array) -> Array:
	var fired: Array = []
	for f in list:
		var on: bool = (f.node as Node3D).scale.x > 0.01 and (f.node as Node3D).is_visible_in_tree()
		(f.light as OmniLight3D).visible = on
		if on and not f.on:
			fired.append(f.node)
		f.on = on
	return fired
