extends SceneTree
## Writes the V2 material tables the site's 3D gallery needs to rebuild the game's materials in three.js:
## materials.json (from the Blender export) + the constants that live in V2Assets (SPECIAL, SET_PAINT, SET_PLAIN,
## CALM, WEAR). Colours become linear [r, g, b, a] (three.js works in linear).
##   godot --headless -s tools/dump_v2_materials.gd -- site/data/materials.json

func _lin(c: Color) -> Array:
	var l := c.srgb_to_linear()
	return [l.r, l.g, l.b, c.a]


func _conv(v: Variant) -> Variant:
	match typeof(v):
		TYPE_COLOR:
			return _lin(v)
		TYPE_VECTOR3:
			return [v.x, v.y, v.z]
		TYPE_DICTIONARY:
			var o := {}
			for k in v:
				o[k] = _conv(v[k])
			return o
		TYPE_ARRAY:
			var a := []
			for x in v:
				a.append(_conv(x))
			return a
	return v


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "site/data/materials.json"
	var d: Dictionary = V2Assets.data().duplicate(true)
	d["special"] = _conv(V2Assets.SPECIAL)
	d["set_paint"] = _conv(V2Assets.SET_PAINT)
	d["set_plain"] = _conv(V2Assets.SET_PLAIN)
	d["calm"] = _conv(V2Assets.CALM)
	d["wear"] = _conv(V2Assets.WEAR)
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, " "))
	f.close()
	print("wrote ", out)
	quit()
