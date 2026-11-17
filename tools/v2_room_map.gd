extends SceneTree
## Prints the concept room's floor plan as text: where the player's capsule fits (0.2 m grid). Needs a display:
##   xvfb-run -a godot --rendering-driver opengl3 --path . -s tools/v2_room_map.gd
func _init():
	var shell: Node3D = (load("res://assets/models/v2/room.glb") as PackedScene).instantiate()
	root.add_child(shell)
	for n in shell.find_children("*", "MeshInstance3D", true, false):
		var nm := String(n.name)
		var skip := false
		for p in ["Cable", "TrayCable", "Loop", "Bubbles", "CoveLights", "LightStrips", "CeilingLights", "Screens", "FloorTiles", "FloorBase", "FloorPaint", "Drains"]:
			if nm.begins_with(p):
				skip = true
		if not skip:
			(n as MeshInstance3D).create_trimesh_collision()
	await physics_frame
	await physics_frame
	var space := root.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.6
	var head := "       "
	var x := -4.4
	while x < 6.3:
		head += ("%d" % int(abs(round(x)))) if abs(x - round(x)) < 0.01 else " "
		x += 0.2
	print(head, "   (x from -4.4, step 0.2; digits = |x|; # = the player's capsule does not fit)")
	var z := 2.8
	while z > -13.9:
		var line := "%6.2f " % z
		x = -4.4
		while x < 6.3:
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = cap
			q.transform = Transform3D(Basis.IDENTITY, Vector3(x, 0.95, z))
			line += "." if space.intersect_shape(q, 1).is_empty() else "#"
			x += 0.2
		print(line)
		z -= 0.2
	quit()
