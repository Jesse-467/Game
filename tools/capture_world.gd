extends SceneTree

const World = preload("res://scripts/core/world_geometry.gd")

class PreviewGame extends "res://scripts/main.gd":
	func create_active_store() -> RefCounted: return preload("res://tests/support/memory_run_store.gd").new()
	func load_progress() -> void: meta = progression_store.defaults()
	func save_progress() -> bool: return true

var game: Node2D

func _initialize() -> void: call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(1280, 720)
	game = PreviewGame.new()
	root.add_child(game)
	game.set_physics_process(false)
	DirAccess.make_dir_recursive_absolute("res://builds/world-probe")
	game.start_run()
	game.consume_events()
	game.game_ui.banner_left = 0
	var combat: RefCounted = game.session.combat
	for i in 24:
		combat.spawn_enemy(["slime", "bat", "skeleton", "charger", "shaman", "elite_guard"][i % 6])
		if combat.enemies.size() > i: combat.enemies[i].born = 0.0
	await picture("center")
	combat.player += Vector2(650, 430)
	combat.enemies.clear()
	for i in 18:
		combat.spawn_enemy(["slime", "bat", "skeleton", "shaman"][i % 4])
		if combat.enemies.size() > i: combat.enemies[i].born = 0.0
	await picture("camera-moved")
	combat.enemies.clear()
	combat.player = Vector2(3552, 2352)
	await picture("world-boundary")
	combat.player = World.CENTER
	game.session.director.node_index = 20
	combat.spawn_enemy("boss_ogre", World.CENTER + Vector2(280, -60))
	combat.enemies[0].born = 0.0
	combat.enemies[0].hp *= 0.4
	combat.update_enemies(0.0)
	combat.enemies[0].timer = 0.0
	combat.update_enemies(0.0)
	await picture("boss-health")
	combat.enemies.clear()
	game.session.director.node_index = 23
	game.session.director.node_time = 29
	for entry in combat.field.definitions:
		combat.field.configure_node(23)
		combat.field.definition = entry
		combat.field.prepare_zones(combat.player)
		combat.field.phase = "active"
		combat.field.phase_left = 38
		await picture("field-" + str(entry.id))
	combat.field.phase = "warning"
	combat.field.phase_left = 3
	await picture("field-warning")
	game.audio_service.music.stop()
	await create_timer(0.1).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("PASS: rendered expanded world, moved camera, boundary, round controls, boss health and all8 terrains")
	quit()

func picture(name: String) -> void:
	game.battle_view.sync()
	game.game_ui.sync(game.session, 0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://builds/world-probe/%s.png" % name)
