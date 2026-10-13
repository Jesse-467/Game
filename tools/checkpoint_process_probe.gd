extends SceneTree
## Separate process phases exercise production bootstrap and checkpoint persistence.

class ProbeGame extends "res://scripts/main.gd":
	func create_active_store() -> RefCounted:
		var store = preload("res://scripts/core/active_run_store.gd").new()
		store.path = "res://builds/checkpoint-probe/active-run.save"
		return store
	func load_progress() -> void:
		meta = progression_store.defaults()
	func save_progress() -> bool:
		return true

func _initialize() -> void:
	Engine.max_fps = 60
	call_deferred("probe")

func probe() -> void:
	DirAccess.make_dir_recursive_absolute("res://builds/checkpoint-probe")
	var game = ProbeGame.new()
	root.add_child(game)
	game.set_physics_process(false)
	var phase = OS.get_cmdline_user_args()[0]
	await create_timer(0.05).timeout
	var result: Dictionary = {}
	if phase == "write":
		game.start_run()
		for i in 180:
			game.session.step(1.0 / 60, Vector2.RIGHT, true)
		game.session.xp = game.session.xp_required()
		game.session.begin_level_up()
		game.consume_events()
		game.save_checkpoint()
		result = {"run_id": game.session.run_id, "level": game.session.level, "xp": game.session.xp, "seconds": game.session.director.elapsed, "offers": game.session.selected_upgrades, "rng_state": game.session.rng.state, "checkpoint_sha256": FileAccess.get_sha256(game.active_store.path)}
		var file = FileAccess.open("res://builds/checkpoint-probe/expected.save", FileAccess.WRITE)
		file.store_var(result, false)
		file.close()
	else:
		var file = FileAccess.open("res://builds/checkpoint-probe/expected.save", FileAccess.READ)
		var expected: Dictionary = file.get_var(false)
		file.close()
		game.continue_saved_run()
		if game.session.state != "upgrade" or game.session.run_id != expected.run_id or game.session.level != expected.level or game.session.rng.state != expected.rng_state or game.session.selected_upgrades != expected.offers:
			push_error("Separate process did not restore the same expedition and offers")
			quit(1)
			return
		result = {"restored_same_run": true, "run_id": game.session.run_id, "level": game.session.level, "state": game.session.state, "seconds": game.session.director.elapsed, "checkpoint_sha256": FileAccess.get_sha256(game.active_store.path)}
	print(JSON.stringify(result))
	game.audio_service.music.stop()
	await create_timer(0.1).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("PASS: checkpoint process phase " + phase)
	quit()
