extends SceneTree

class TestGame extends "res://scripts/main.gd":
	func create_active_store() -> RefCounted:
		return preload("res://tests/support/memory_run_store.gd").new()
	func load_progress() -> void:
		meta = progression_store.defaults()
	func save_progress() -> bool:
		return true

var failures: Array[String] = []
var checks = 0

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func _initialize() -> void:
	Engine.max_fps = 60
	call_deferred("run_checks")

func run_checks() -> void:
	var game = TestGame.new()
	root.add_child(game)
	game.set_physics_process(false)
	var server = TextServerManager.get_primary_interface()
	var weight_tag = server.name_to_tag("wght")
	var selected_axes = server.font_get_variation_coordinates(game.game_ui.ui_theme.default_font.get_rids()[0])
	check(selected_axes.get(weight_tag, 100) == 500.0, "Readable Chinese UI weight reaches the actual text renderer")
	check(game.session.state == "menu" and game.game_ui.panel.visible, "Camp opens on application startup")
	game.meta.crystals = 25
	game.unlock_character("mage")
	check(game.meta.unlocks.has("mage") and game.meta.crystals == 0, "Unlock spends crystals and selects mage")
	game.start_run()
	check(game.session.level == 1 and game.session.combat.character_id == "mage", "Starting selected unlocked character resets level")
	game.battle_view.sync()
	var view = game.battle_view.hero_view
	view.present(Vector2(640, 335), "move", 1, false, false)
	var frame_before = view.frame
	await create_timer(0.18).timeout
	check(view.frame != frame_before, "Movement animation advances actual frames")
	view.present(Vector2(640, 335), "move", 1, true, false)
	frame_before = view.frame
	await create_timer(0.18).timeout
	check(view.frame == frame_before, "Paused actor freezes animation")
	view.present(Vector2(640, 335), "attack", 1, false, false, 1)
	await create_timer(0.18).timeout
	check(view.animation == "attack" and view.frame > 0, "Attack animation advances distinct frames")
	view.present(Vector2(640, 335), "hurt", 1, false, true, 1)
	await create_timer(0.18).timeout
	check(view.animation == "hurt" and view.frame > 0, "Hurt animation advances distinct frames")
	game.on_setting("control_scale", 1.1)
	check(game.controls.attack_rect.size.x > preload("res://scripts/input/control_layout.gd").ATTACK.size.x and game.controls.joystick_radius > 72, "Touch scale updates visual controls and hit regions together")
	game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	game.consume_events()
	check(game.session.state == "paused" and game.game_ui.panel.visible, "Background transition opens paused menu")
	game.on_action("resume")
	game.consume_events()
	check(game.session.state == "playing" and not game.game_ui.panel.visible, "Manual resume closes pause panel")
	game.session.finish()
	game.consume_events()
	var crystals = game.meta.crystals
	game.settle_run(game.session.result())
	check(game.meta.crystals == crystals and game.meta.total_runs == 1, "UI settlement credits a run only once")
	game.start_run()
	check(game.session.level == 1 and not game.session.reward_paid, "Retry resets transient state while retaining unlock")
	var held_left = InputEventScreenTouch.new()
	held_left.index = 0
	held_left.position = Vector2(205, 610)
	held_left.pressed = true
	game._input(held_left)
	game.session.xp = game.session.xp_required()
	game.session.begin_level_up()
	game.consume_events()
	var drag = InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(220, 610)
	game._input(drag)
	check(game.controls.joystick_touch == -1 and game.controls.joystick_vector == Vector2.ZERO, "Dragging during upgrade selection cannot move the player")
	game.on_action("upgrade", game.session.selected_upgrades[0].id)
	game._input(drag)
	check(game.controls.joystick_touch == 0 and game.controls.movement().x > 0, "Fresh drag after upgrade restores movement without lifting the held finger")
	drag.index = 1
	drag.position = Vector2(1160, 630)
	game._input(drag)
	check(game.controls.attack_touch == 1 and game.controls.joystick_touch == 0, "Held attack can resume by dragging independently of movement")
	game.session.combat.facing = Vector2.LEFT
	game.session.combat.dash_cooldown = 0
	game.controls.joystick_vector = Vector2.RIGHT
	var dash_start: Vector2 = game.session.combat.player
	game.on_action("dash")
	game.session.combat.step(0.1, Vector2.RIGHT, false)
	check(game.session.combat.player.x > dash_start.x and game.session.combat.facing.x > 0, "Same-frame direction change and dodge use current movement intent")
	game.queue_free()
	await process_frame
	# Audio playback disposal is queued on the mix thread; finish teardown before exit.
	await create_timer(0.1).timeout
	if failures.is_empty(): print("PASS: %d UI, animation, unlock and lifecycle checks" % checks)
	quit(0 if failures.is_empty() else 1)
