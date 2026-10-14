extends SceneTree

const Readout = preload("res://scripts/ui/run_readout.gd")

class TestGame extends "res://scripts/main.gd":
	func create_active_store() -> RefCounted:
		return preload("res://tests/support/memory_run_store.gd").new()
	func load_progress() -> void:
		meta = progression_store.defaults()
	func save_progress() -> bool:
		return true

var checks = 0
var failures: Array[String] = []

func _initialize() -> void:
	Engine.max_fps = 60
	call_deferred("run_checks")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func scrolling_content(ui: CanvasLayer) -> ScrollContainer:
	for child in ui.content.get_children():
		if child is ScrollContainer: return child
	return null

func run_checks() -> void:
	root.size = Vector2i(1280, 720)
	var game = TestGame.new()
	root.add_child(game)
	game.set_physics_process(false)
	await create_timer(0.05).timeout
	game.on_action("records")
	check(game.session.state == "menu" and game.panel_return == "camp", "An empty record page keeps the player in camp")
	game.on_action("pause")
	check(game.panel_return.is_empty() and game.session.state == "menu", "Escape returns from records to camp without starting combat")
	game.start_run()
	game.consume_events()
	check(game.game_ui.banner.text.contains("J") and game.game_ui.banner_left > 0, "A new desktop run shows its basic controls")
	game.session.pause()
	game.consume_events()
	var combat: RefCounted = game.session.combat
	combat.stats.crit_chance = 0.7
	var field: RefCounted = combat.field
	field.configure_node(6)
	field.definition = field.find_definition("keen_ground")
	field.prepare_zones()
	field.zones[0].id = "keen_ground"
	field.phase = "active"
	combat.player = field.zones[0].pos
	var before_stats = combat.stats.duplicate(true)
	var before_rng = game.session.rng.state
	var values = Readout.current(game.session)
	check(is_equal_approx(values.crit, 0.95) and values.base_crit == 0.7, "The readout distinguishes base crit from the active +25 point arena bonus")
	check(Readout.field_text(game.session).contains("95%"), "The player-facing field description reports the effective crit rate")
	field.configure_node(18)
	field.definition = field.find_definition("blind_ground")
	field.prepare_zones()
	field.zones[0].id = "blind_ground"
	field.phase = "active"
	combat.player = field.zones[0].pos
	combat.stats.crit_chance = 0.1
	check(Readout.current(game.session).crit == 0, "Crit debuff display respects the probability floor")
	combat.stats = before_stats.duplicate(true)
	field.configure_node(9)
	field.definition = field.find_definition("void_ground")
	field.prepare_zones()
	field.zones[0].id = "void_ground"
	field.phase = "active"
	combat.player = field.zones[0].pos
	check(is_equal_approx(Readout.current(game.session).damage, float(before_stats.damage) * 0.7), "The damage debuff display agrees with newly launched attacks")
	check(combat.stats == before_stats and game.session.rng.state == before_rng, "Reading stats never changes the character or battle random state")
	game.on_action("build")
	check(game.panel_return == "paused_menu" and game.session.state == "paused", "Opening build details does not resume a paused run")
	await process_frame
	await process_frame
	check(game.game_ui.panel.get_global_rect().end.y <= 720, "Build details fit the landscape screen")
	game.game_ui.sync(game.session, 0)
	check(not game.game_ui.banner.visible, "Combat banners cannot cover the details heading")
	game._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(game.panel_return.is_empty() and game.session.state == "paused", "Android Back returns from build details to the pause menu")
	game.session.resume()
	game.consume_events()
	game.session.xp = game.session.xp_required()
	game.session.begin_level_up()
	game.consume_events()
	var offers = game.session.selected_upgrades.duplicate(true)
	before_rng = game.session.rng.state
	var before_time = game.session.director.elapsed
	game.on_action("build")
	game._physics_process(1.0)
	game.on_action("pause")
	check(game.session.state == "upgrade" and game.session.selected_upgrades == offers and game.session.rng.state == before_rng, "Inspecting build and returning never rerolls pending upgrades")
	check(game.session.director.elapsed == before_time, "No combat time elapses while inspecting an upgrade")
	game.on_action("upgrade", offers[0].id)
	check(game.session.state == "playing" and game.panel_return.is_empty(), "An original offer remains selectable after inspection")
	game.session.pause()
	game.consume_events()
	game.on_action("settings_run")
	game.on_action("pause")
	check(game.session.state == "paused" and game.panel_return.is_empty(), "Escape from settings keeps combat paused")
	for entry in game.session.upgrades.definitions:
		game.session.upgrades.stacks[entry.id] = maxi(1, int(entry.max_stacks))
	game.on_action("build")
	await process_frame
	await process_frame
	var scroll = scrolling_content(game.game_ui)
	check(scroll != null and scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page, "All blessing types remain reachable through a scrollable list")
	check(Readout.blessings(game.session.upgrades, game.session.upgrades.stacks).size() == 15, "The list includes all combined mechanisms without slot filtering")
	game.on_action("paused_menu")
	game.session.finish()
	game.consume_events()
	game.show_camp()
	game.on_action("records")
	await process_frame
	await process_frame
	check(game.meta.total_runs == 1 and game.meta.last_run.build.size() == 15 and scrolling_content(game.game_ui) != null, "The completed run retains its full construct in records")
	check(game.game_ui.panel.get_global_rect().end.y <= 720, "A full recorded build fits the screen using a scrollable body")
	game.on_action("pause")
	game.start_run()
	game.show_camp()
	await process_frame
	await process_frame
	check(game.game_ui.panel.get_global_rect().end.y <= 720, "Camp with continuation and record/settings actions stays within landscape bounds")
	check(Readout.clock(3665) == "61:05", "Long-run records do not wrap after one hour")
	game.audio_service.music.stop()
	await create_timer(0.1).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	if failures.is_empty(): print("PASS: %d attribute, build, records and menu-navigation checks" % checks)
	quit(0 if failures.is_empty() else 1)
