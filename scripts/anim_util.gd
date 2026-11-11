class_name AnimUtil
## Helpers for the Quaternius rigs: clips are named "<Name>_Rig" (or "<Name>_<Armature>").
## find() matches by prefix; cyclic clips are set to loop on first use.

const LOOPING := ["Idle", "Look", "Run", "Walk", "Hanging", "Charging", "Charge", "Idle_Open", "Idle_Closed"]


static func find(ap: AnimationPlayer, prefix: String) -> String:
	if ap == null:
		return ""
	for n in ap.get_animation_list():
		if n == prefix or n.begins_with(prefix + "_"):
			return n
	return ""


## From-scratch assets (blender/scripts/export_new_assets.py) carry one baked animation ("Scene", every
## frame keyed, time = frame / fps) plus <name>_clips.json {clips: {Name: [first, last]}, fps}. Cut them into
## named clips on `ap` (frames are Blender frames). `strip` = node paths whose tracks are dropped (e.g. the
## asset root, whose kick the game does procedurally); `extra` = more {Name: [first, last]} cuts.
static func split_clips(ap: AnimationPlayer, json_path: String, strip: Array = [], extra: Dictionary = {}) -> void:
	if ap == null or not ap.has_animation("Scene") or not FileAccess.file_exists(json_path):
		return
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	var fps: float = spec.get("fps", 30)
	var clips: Dictionary = spec.clips.duplicate()
	clips.merge(extra, true)
	var src := ap.get_animation("Scene")
	var lib := ap.get_animation_library("")
	for clip_name in clips:
		var r: Array = clips[clip_name]
		var t0 := float(r[0]) / fps
		var t1 := float(r[1]) / fps
		var a := Animation.new()
		a.length = maxf(t1 - t0, 1.0 / fps)
		for i in src.get_track_count():
			var path := src.track_get_path(i)
			if String(path.get_concatenated_names()) in strip:
				continue
			var j := a.add_track(src.track_get_type(i))
			a.track_set_path(j, path)
			a.track_set_interpolation_type(j, src.track_get_interpolation_type(i))
			for k in src.track_get_key_count(i):
				var t := src.track_get_key_time(i, k)
				if t >= t0 - 0.001 and t <= t1 + 0.001:
					a.track_insert_key(j, t - t0, src.track_get_key_value(i, k))
			if a.track_get_key_count(j) == 0:
				# Keyless in this range (the exporter only writes changing frames): hold the value at t0.
				var k0 := src.track_find_key(i, t0, Animation.FIND_MODE_NEAREST)
				if k0 >= 0:
					a.track_insert_key(j, 0.0, src.track_get_key_value(i, k0))
		if String(clip_name) in LOOPING:
			a.loop_mode = Animation.LOOP_LINEAR
		if lib.has_animation(clip_name):
			lib.remove_animation(clip_name)
		lib.add_animation(clip_name, a)


## Play the clip whose name starts with `prefix` (no-op if it is already playing).
static func play(ap: AnimationPlayer, prefix: String, blend: float = 0.15, speed: float = 1.0) -> bool:
	var n := find(ap, prefix)
	if n == "":
		return false
	var a := ap.get_animation(n)
	if prefix in LOOPING and a.loop_mode == Animation.LOOP_NONE:
		a.loop_mode = Animation.LOOP_LINEAR
	if ap.current_animation != n or not ap.is_playing():
		ap.play(n, blend, speed)
	return true
