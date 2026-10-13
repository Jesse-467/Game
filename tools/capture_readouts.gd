extends SceneTree

class PreviewGame extends "res://scripts/main.gd":
	func create_active_store() -> RefCounted:
		return preload("res://tests/support/memory_run_store.gd").new()
	func load_progress() -> void:
		meta = progression_store.defaults()
	func save_progress() -> bool:
		return true

var preview_game: Node2D

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(1280, 720)
	var game = PreviewGame.new()
	preview_game = game
	root.add_child(game)
	game.set_physics_process(false)
	DirAccess.make_dir_recursive_absolute("res://builds/readout-probe")
	await take_picture("camp-first")
	game.on_action("records")
	await take_picture("records-empty")
	game.on_action("camp")
	game.start_run()
	game.consume_events()
	game.show_camp()
	await take_picture("camp-continue")
	game.continue_saved_run()
	for entry in game.session.upgrades.definitions:
		if entry.id not in ["heal", "ember", "endurance"]:
			for i in int(entry.max_stacks): game.session.combat.stats = game.session.upgrades.apply(entry.id, game.session.combat.stats)
	game.session.level = 40
	game.session.combat.stats.level = 40
	var field = game.session.combat.field
	field.configure_node(6)
	field.definition = field.find_definition("keen_ground")
	field.prepare_zones()
	field.phase = "active"
	game.session.combat.player = field.zones[0].pos
	game.on_action("build")
	await take_picture("build-top")
	for child in game.game_ui.content.get_children():
		if child is ScrollContainer: child.scroll_vertical = int(child.get_v_scroll_bar().max_value)
	await take_picture("build-bottom")
	game.on_action("paused_menu")
	game.session.resume()
	game.session.xp = game.session.xp_required()
	game.session.begin_level_up()
	game.consume_events()
	await take_picture("upgrade")
	game.session.director.elapsed = 1865.0
	game.session.director.node_index = 51
	game.session.kills = 1832
	game.session.director.bosses_defeated = 10
	game.session.combat.death_source = "骸骨君主 · 灵魂环阵"
	game.session.finish()
	game.consume_events()
	game.on_action("camp")
	game.on_action("records")
	await take_picture("records-filled")
	game.audio_service.music.stop()
	await create_timer(0.1).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("PASS: captured camp, full build, upgraded choice and completed-run records")
	quit()

func take_picture(name: String) -> void:
	preview_game.battle_view.sync()
	preview_game.game_ui.sync(preview_game.session, 0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://builds/readout-probe/%s.png" % name)
