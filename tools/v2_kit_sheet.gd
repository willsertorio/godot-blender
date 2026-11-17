extends SceneTree
## Pictures of the dungeon kit's pieces, one each, in the game's materials (to check the modelling):
##   xvfb-run -a godot --rendering-driver opengl3 --resolution 640x480 --path . -s tools/v2_kit_sheet.gd -- DIR [first piece]
## then tile them (any image tool). Pieces stand 8 m apart in kit.glb, as in the .blend.

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0]
	var first := int(args[1]) if args.size() > 1 else 0
	var file: String = args[2] if args.size() > 2 else "kit.glb"       # (set.glb: the environment set)
	DirAccess.make_dir_recursive_absolute(dir)
	var kit := (load(V2Assets.DIR + file) as PackedScene).instantiate() as Node3D
	root.add_child(kit)
	V2Assets.apply(kit)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.32, 0.34, 0.37)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1, 1, 1)
	env.environment.ambient_light_energy = 0.45
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	root.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 50.0
	root.add_child(cam)
	cam.make_current()
	var i := 0
	for piece in kit.get_children():
		i += 1
		if i <= first:
			continue
		var box := AABB()
		var any := false
		for n in piece.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var b := mi.global_transform * mi.get_aabb()
			box = b if not any else box.merge(b)
			any = true
		var c := box.get_center()
		var r := box.size.length() * 0.5
		var pname := String(piece.name)
		# walls and floors are seen from the room's side (Godot +Z after the export); ceilings from below
		var dir3 := Vector3(0.55, 0.45, 1.0).normalized()
		if pname.to_lower().contains("ceiling"):
			dir3 = Vector3(0.5, -0.75, 1.0).normalized()
		elif pname.to_lower().begins_with("floor") or pname.begins_with("CFloor"):
			dir3 = Vector3(0.3, 1.0, 0.8).normalized()
		cam.global_position = c + dir3 * r * 2.3
		cam.look_at(c)
		for k in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(dir.path_join("%02d_%s.png" % [i, pname]))
	print("[kit] %d pieces" % i)
	quit()
