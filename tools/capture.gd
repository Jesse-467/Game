extends SceneTree

class PreviewGame extends "res://scripts/main.gd":
	func create_active_store() -> RefCounted:
		return preload("res://tests/support/memory_run_store.gd").new()
	func load_progress() -> void:
		meta = progression_store.defaults()
		meta.unlocks = ["knight", "mage", "ranger"]
	func save_progress() -> bool:
		return true

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(1280, 720)
	var game = PreviewGame.new()
	root.add_child(game)
	game.set_physics_process(false)
	DirAccess.make_dir_recursive_absolute("res://builds/previews")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://builds/previews/camp.png")
	game.start_run()
	for i in 12:
		game.session.combat.spawn_enemy(["slime", "bat", "skeleton", "shaman", "charger", "elite_guard"][i % 6], Vector2(280 + (i % 6) * 140, 235 + int(i / 6) * 230))
		game.session.combat.enemies[-1].born = 0
	game.battle_view.sync()
	game.game_ui.sync(game.session, 0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://builds/previews/combat.png")
	for index in [3, 6, 9, 12, 15, 18]:
		var field = game.session.combat.field
		field.configure_node(index)
		field.prepare_zones()
		field.phase = "active"
		field.phase_left = 8.0
		game.session.director.node_index = index
		game.game_ui.sync(game.session, 0)
		game.battle_view.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://builds/previews/field-%s.png" % field.definition.id)
	for action in ["idle", "move", "attack", "hurt"]:
		game.battle_view.hero_view.play(action)
		for frame in 4:
			game.battle_view.hero_view.frame = frame
			game.battle_view.hero_view.pause()
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://builds/previews/knight-%s-%d.png" % [action, frame])
	game.session.xp = game.session.xp_required()
	game.session.begin_level_up()
	game.consume_events()
	game.game_ui.sync(game.session, 0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://builds/previews/upgrade.png")
	game.game_ui.show_settings(game.meta.settings, "paused_menu")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://builds/previews/settings.png")
	game.on_action("save_camp")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://builds/previews/camp-continue.png")
	game.continue_saved_run()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://builds/previews/restored-choice.png")
	print("Captured camp, combat, upgrade, settings and all16 knight animation frames")
	game.queue_free()
	await process_frame
	quit()
