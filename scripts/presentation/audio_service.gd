extends Node

var cues: Dictionary = {}
var players: Array[AudioStreamPlayer] = []
var next_player = 0
var music: AudioStreamPlayer

func _ready() -> void:
	for name in ["attack", "hurt", "dash", "skill", "upgrade", "boss", "death"]:
		cues[name] = load("res://assets/audio/%s.wav" % name)
	for i in 6:
		var player = AudioStreamPlayer.new()
		add_child(player)
		players.append(player)
	music = AudioStreamPlayer.new()
	music.stream = load("res://assets/audio/expedition.wav")
	music.volume_db = -8
	add_child(music)
	music.finished.connect(music.play)
	music.play()

func _exit_tree() -> void:
	# Release active playback before the application or a test scene exits.
	for player in players:
		player.stop()
		player.stream = null
	music.stop()
	music.stream = null

func play_cue(name: String) -> void:
	if not cues.has(name):
		return
	var player = players[next_player]
	next_player = (next_player + 1) % players.size()
	player.stream = cues[name]
	player.play()
