class_name V2Music
## The menu's music (**user: music in the menu; "when game starts, we only hear the lab sounds, no more music"**).
## It plays on the title and fades out when a run (or the lab) starts; the game itself has the room tone only.
## One piece: Exploration Theme by Cleyton Kauffman (CC0, opengameart.org), which the user chose of three
## candidates ("first music is fine"). File: assets/audio/v2/music (tools/build_v2_music.sh: -23 LUFS), looping.
## The player hangs from the scene tree's root, not from a scene, so that it can fade across the change of scene.

const FILE := "res://assets/audio/v2/music/menu_exploration_theme.ogg"
const LEVEL := -5.0                 # dB: under the game's sounds

static var enabled := true
static var _player: AudioStreamPlayer


## The title is up: the music starts (or goes on, if it was already playing).
static func start(tree: SceneTree) -> void:
	if not enabled or DisplayServer.get_name() == "headless":
		return
	if is_instance_valid(_player) and _player.playing and not _player.has_meta("leaving"):
		return
	_drop()
	_player = AudioStreamPlayer.new()
	_player.stream = load(FILE)
	_player.volume_db = -40.0
	tree.root.add_child.call_deferred(_player)
	_player.ready.connect(func() -> void:
		_player.play()
		_player.create_tween().tween_property(_player, "volume_db", LEVEL, 1.5))


## A run starts: the music fades and is gone.
static func stop(seconds: float = 1.4) -> void:
	if not is_instance_valid(_player) or _player.has_meta("leaving"):
		return
	var p := _player
	p.set_meta("leaving", true)
	if not p.is_inside_tree():
		p.queue_free()
		return
	var tw := p.create_tween()
	tw.tween_property(p, "volume_db", -50.0, seconds)
	tw.tween_callback(p.queue_free)


static func _drop() -> void:
	if is_instance_valid(_player):
		_player.queue_free()
	_player = null
