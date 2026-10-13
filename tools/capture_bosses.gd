extends SceneTree
## Render exact simulation warnings, using isolated player progress/checkpoints.

class PreviewGame extends "res://scripts/main.gd":
	func create_active_store() -> RefCounted:
		return preload("res://tests/support/memory_run_store.gd").new()
	func load_progress() -> void:
		meta = progression_store.defaults()
	func save_progress() -> bool:
		return true

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(1280, 720)
	var game = PreviewGame.new()
	root.add_child(game)
	game.set_physics_process(false)
	DirAccess.make_dir_recursive_absolute("res://builds/boss-probe")
	await process_frame
	for id in ["boss_ogre", "boss_lich", "boss_wyrm"]:
		game.start_run()
		var combat: RefCounted = game.session.combat
		game.session.director.node_index = {"boss_ogre": 20, "boss_lich": 25, "boss_wyrm": 30}[id]
		combat.player = Vector2(855, 350)
		combat.spawn_enemy(id, Vector2(640, 335))
		var enemy: Dictionary = combat.enemies[0]
		enemy.born = 0.0
		enemy.hp *= 0.4
		combat.update_enemies(0.0)
		game.session.consume_combat_events()
		game.consume_events()
		enemy.timer = 0.0
		combat.update_enemies(0.0)
		combat.update_enemies(0.5)
		game.battle_view.sync()
		game.game_ui.sync(game.session, 0)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://builds/boss-probe/%s-warning.png" % id)
	game.audio_service.music.stop()
	await create_timer(0.1).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("PASS: captured all three repeat-rotation phase warnings using the actual renderer")
	quit()
