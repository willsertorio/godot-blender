class_name V2Sfx
## Sound of the V2 lab. One table: every interaction has a key; a key plays one of its files, picked at random, with
## a little pitch scatter, either in the listener's head (the player's own gun and body) or at a place in the room.
##   V2Sfx.play("rifle_shot")                 the player's own sounds
##   V2Sfx.play("impact_metal", point)        somewhere in the room
##   V2Sfx.loop("drone_rotor", node)          a looping source that rides on a node; the caller drives pitch / volume
## Files: `assets/audio/v2/<key>_*.ogg`, any number per key: real recordings, CC0, cut and levelled by
## `tools/build_v2_audio.py` (guns: The Free Firearm Sound Library; the rest: foley from opengameart.org).
## A key without files there falls back to its stand-in from V1's Kenney set (arcade sounds; none is in use now).
## Everything goes through one bus: a little room reverb (one shared space is what makes sounds from different
## recordings sit together; the guns carry their own room as well, built in), then a limiter (the machine gun's
## rounds pile up, an explosion beside the player is loud: the sum is held under full scale instead of clipping).
## `V2Sfx.log` lists the keys played, newest last (the container has no audio device: checks read this).
## `-- --no-sound` switches everything off.

const DIR := "res://assets/audio/v2/"
const OLD := "res://assets/audio/%s.ogg"

## key: [stand-in files, stand-in pitch, volume dB, pitch scatter, reach in metres (3D only)]
## The volume column IS the mix: tools/build_v2_audio.py brings every file to the same loudness, so a number here
## is how loud that sound is against the player's pistol (0). A sound at a place in the room loses 6 dB more for
## each doubling of its distance past 4 m. (The first mix was set on peak levels: measured as loudness, the
## pistol's slide was 7 dB louder than its shot, and a robot's servo only 5 dB under it.)
const SOUNDS := {
	# the player's guns (designed from The Free Firearm Sound Library: Walther PPQ 9 mm, AR-15 5.56)
	"pistol_shot": [["explosionCrunch_002"], 2.0, 0.0, 0.04, 0.0],
	"rifle_shot": [["explosionCrunch_000"], 2.5, -3.0, 0.05, 0.0],
	"rifle_tail": [[], 1.0, -11.0, 0.03, 0.0],                                                 # the last round dying away when the trigger is let go
	"casing": [["impactMetal_light_001", "impactMetal_light_004"], 2.6, -24.0, 0.2, 0.0],      # brass on the floor
	"pistol_mag_out": [["impactPlate_light_002"], 1.3, -15.0, 0.04, 0.0],
	"pistol_mag_in": [["impactMetal_medium_001"], 1.4, -13.0, 0.04, 0.0],
	"slide": [["impactMetal_light_004"], 1.6, -11.0, 0.04, 0.0],                                # pistol slide runs forward
	"rifle_mag_out": [["impactPlate_light_002"], 1.2, -15.0, 0.04, 0.0],
	"rifle_mag_in": [["impactMetal_medium_001"], 1.3, -12.0, 0.04, 0.0],
	"bolt": [["impactMetal_medium_004"], 1.5, -10.0, 0.04, 0.0],                                # machine gun charging handle
	"handling": [["switch_003"], 0.8, -24.0, 0.1, 0.0],                                        # the gun moved in the hands: draw, aim, inspect
	# rounds landing
	"impact_concrete": [["impactPlate_light_002"], 1.7, -9.0, 0.15, 22.0],
	"impact_metal": [["impactMetal_medium_002", "impactMetal_medium_004"], 1.2, -8.0, 0.12, 24.0],
	"ricochet": [[], 1.0, -10.0, 0.12, 24.0],                                                  # now and then a round glances off
	"flyby": [[], 1.0, -9.0, 0.15, 0.0],                                                       # a robot's round passing the head
	# the player's body
	"step": [["impactPlate_light_002"], 0.75, -25.0, 0.1, 0.0],
	"jump": [["impactPlate_light_002"], 0.6, -24.0, 0.05, 0.0],
	"land": [["impactPunch_heavy_002"], 0.8, -16.0, 0.05, 0.0],
	"crouch": [["switch_003"], 0.6, -25.0, 0.05, 0.0],
	"hurt": [["impactPlate_heavy_001"], 1.0, -7.0, 0.06, 0.0],
	"down": [["lowFrequency_explosion_000"], 1.2, -5.0, 0.0, 0.0],
	# the robots (their guns: Tikka .30-06, Carl Gustav M45 9 mm, AK-47, recorded a few metres off)
	# (user: "make the shot sound of the enemies more aggressive": rebuilt harder, and 3 dB up here; the turret's
	# rounds come twelve a second now, so each is lower than the others')
	"spider_shot": [["explosionCrunch_000"], 1.5, 6.0, 0.04, 50.0],
	"drone_shot": [["explosionCrunch_002"], 1.8, 3.0, 0.05, 50.0],
	"turret_shot": [["explosionCrunch_000"], 1.3, 1.0, 0.03, 50.0],
	"turret_tail": [[], 1.0, -3.0, 0.03, 50.0],                                                # the room after its burst
	"turret_spin_up": [[], 1.0, -4.0, 0.03, 32.0],                                             # its barrels run up: it is about to fire
	"turret_spin_down": [[], 1.0, -8.0, 0.03, 26.0],
	"spider_step": [["impactMetal_light_001", "impactMetal_light_004"], 0.8, -11.0, 0.1, 18.0],
	"servo": [[], 1.0, -19.0, 0.08, 16.0],                                                     # a joint driven round: aiming, turning
	"drone_rotor": [["spaceEngineSmall_003"], 1.4, -12.0, 0.0, 20.0],                          # loop
	"robot_hit": [["impactMetal_heavy_000"], 1.2, -5.0, 0.1, 26.0],                            # a round that hurt it
	"robot_break": [["explosionCrunch_000", "explosionCrunch_002"], 1.0, 2.0, 0.06, 45.0],    # destroyed
	"power_down": [["glitch_002"], 0.6, -7.0, 0.05, 22.0],
	"power_up": [[], 1.0, -9.0, 0.04, 22.0],                                                   # a robot back in service
	"crash": [["impactMetal_heavy_000"], 0.7, 0.0, 0.06, 32.0],                               # a wreck hits the floor
	"explosion": [["lowFrequency_explosion_000"], 1.0, 6.0, 0.04, 60.0],
	# the game: doors, crates, what is picked up, the exit, the menus
	"door": [[], 1.0, -9.0, 0.04, 26.0],
	"crate": [[], 1.0, -11.0, 0.05, 20.0],
	"pickup": [[], 1.0, -15.0, 0.06, 0.0],
	"dry": [[], 1.0, -13.0, 0.05, 0.0],                                                        # the click of an empty gun
	"heal": [[], 1.0, -13.0, 0.03, 0.0],                                                       # a med kit
	"ui": [[], 1.0, -17.0, 0.03, 0.0],
	"room_tone": [[], 1.0, -31.0, 0.0, 0.0],                                                   # loop, everywhere: the ventilation
	"exit_hum": [[], 1.0, -18.0, 0.0, 16.0],                                                   # loop: the exit gate's field
	"exit": [[], 1.0, -7.0, 0.0, 0.0],                                                         # through the gate
	"zap": [["glitch_002"], 1.6, -9.0, 0.2, 18.0],                                            # sparks
}
const LOOPS := ["drone_rotor", "exit_hum", "room_tone"]
const MAX_VOICES := 12                # per key: the oldest is cut off
const GAIN := 3.0                     # dB on everything, into the limiter (the files sit at -20 dB loudness: a pistol shot peaks near full scale)

static var root: Node                # where one-shot players are parented (the lab)
static var enabled := true
static var log: Array[String] = []
static var heard: Dictionary = {}     # every key played since the start (the checks read this)
static var _streams: Dictionary = {}  # key -> [streams]
static var _real: Dictionary = {}     # key -> true when its files come from assets/audio/v2
static var _voices: Dictionary = {}   # key -> [players]
static var _bus := ""


## The lab's bus: a short reverb for a hard-walled room of 11 x 17 m.
static func bus() -> String:
	# Web (Godot 4.3): sounds are played as Web Audio samples, and a bus added at runtime stays silent there.
	# The browser build plays everything on Master: no room reverb or limiter, 3 dB under the desktop mix.
	if OS.has_feature("web"):
		return "Master"
	if _bus == "":
		_bus = "V2Room"
		if AudioServer.get_bus_index(_bus) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, _bus)
			AudioServer.set_bus_send(i, "Master")
			var rv := AudioEffectReverb.new()
			rv.room_size = 0.38
			rv.damping = 0.55
			rv.spread = 0.8
			rv.hipass = 0.15
			rv.predelay_msec = 14.0
			rv.dry = 1.0
			rv.wet = 0.11
			AudioServer.add_bus_effect(i, rv)
			var lim := AudioEffectHardLimiter.new()
			lim.pre_gain_db = GAIN
			lim.ceiling_db = -0.5
			lim.release = 0.12
			AudioServer.add_bus_effect(i, lim)
	return _bus


static func _load(key: String) -> Array:
	if _streams.has(key):
		return _streams[key]
	var list: Array = []
	var dir := DirAccess.open(DIR)
	if dir != null:
		for f in dir.get_files():
			var name := f.trim_suffix(".import")
			if name.begins_with(key + "_") and (name.ends_with(".ogg") or name.ends_with(".wav")) and ResourceLoader.exists(DIR + name):
				var s: AudioStream = load(DIR + name)
				if s != null and not (s in list):
					list.append(s)
	_real[key] = not list.is_empty()
	if list.is_empty():
		for f in SOUNDS[key][0]:
			var s2: AudioStream = load(OLD % f)
			if s2 != null:
				list.append(s2)
	if key in LOOPS:
		for i in list.size():
			var d: AudioStream = (list[i] as AudioStream).duplicate()
			if d is AudioStreamOggVorbis:
				(d as AudioStreamOggVorbis).loop = true
			elif d is AudioStreamWAV:
				(d as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
			list[i] = d
	_streams[key] = list
	return list


## Which keys still play a stand-in (or nothing): for the report.
static func missing() -> Array:
	var out: Array = []
	for key in SOUNDS:
		_load(key)
		if not _real[key]:
			out.append(key)
	return out


static func _pitch(key: String, pitch: float) -> float:
	var sp: Array = SOUNDS[key]
	return pitch * (1.0 if _real.get(key, false) else float(sp[1])) * randf_range(1.0 - float(sp[3]), 1.0 + float(sp[3]))


## Play `key` once: at `at` (world) if given, else in the listener's head.
static func play(key: String, at: Vector3 = Vector3.INF, db: float = 0.0, pitch: float = 1.0) -> void:
	heard[key] = true
	log.append(key)
	if log.size() > 400:
		log = log.slice(200)
	if not enabled or root == null or not SOUNDS.has(key):
		return
	var list := _load(key)
	if list.is_empty():
		return
	var sp: Array = SOUNDS[key]
	var voices: Array = _voices.get(key, [])
	voices = voices.filter(func(v: Variant) -> bool: return is_instance_valid(v))
	if voices.size() >= MAX_VOICES:
		(voices.pop_front() as Node).queue_free()
	var player: Node
	if at == Vector3.INF:
		var p2 := AudioStreamPlayer.new()
		p2.stream = list[randi() % list.size()]
		p2.volume_db = float(sp[2]) + db
		p2.pitch_scale = _pitch(key, pitch)
		p2.bus = bus()
		player = p2
	else:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = list[randi() % list.size()]
		p3.volume_db = float(sp[2]) + db
		p3.pitch_scale = _pitch(key, pitch)
		p3.max_distance = maxf(float(sp[4]), 10.0)
		p3.unit_size = 4.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.attenuation_filter_db = -6.0                    # (the engine's default takes 24 dB off the treble with distance: across a room that is a blanket over a gun)
		p3.bus = bus()
		player = p3
	root.add_child(player)
	if player is AudioStreamPlayer3D:
		(player as AudioStreamPlayer3D).global_position = at
	player.connect("finished", player.queue_free)
	player.call("play")
	voices.append(player)
	_voices[key] = voices


## A looping source on `parent`; not playing yet. null if the key has no sound.
static func loop(key: String, parent: Node3D) -> AudioStreamPlayer3D:
	if not enabled or not SOUNDS.has(key):
		return null
	var list := _load(key)
	if list.is_empty():
		return null
	var sp: Array = SOUNDS[key]
	var p := AudioStreamPlayer3D.new()
	p.stream = list[0]
	p.volume_db = float(sp[2])
	p.pitch_scale = 1.0 if _real.get(key, false) else float(sp[1])
	p.max_distance = maxf(float(sp[4]), 10.0)
	p.unit_size = 3.0
	p.bus = bus()
	p.set_meta("pitch", p.pitch_scale)
	parent.add_child(p)
	return p


## A loop heard everywhere at the same level (the room's tone). Starts at once; null if the key has no sound.
static func ambience(key: String) -> AudioStreamPlayer:
	if not enabled or root == null or not SOUNDS.has(key):
		return null
	var list := _load(key)
	if list.is_empty():
		return null
	var p := AudioStreamPlayer.new()
	p.stream = list[0]
	p.volume_db = float(SOUNDS[key][2])
	p.bus = bus()
	root.add_child(p)
	p.play()
	heard[key] = true
	return p


## Run / stop a loop made by loop(), at `pitch` times its own pitch.
static func drive(p: AudioStreamPlayer3D, on: bool, pitch: float = 1.0) -> void:
	if p == null:
		return
	if on:
		p.pitch_scale = float(p.get_meta("pitch")) * pitch
		if not p.playing:
			p.play()
	elif p.playing:
		p.stop()
