extends SceneTree
## Route real input events through the viewport: left finger stays held during upgrade.

class TestGame extends "res://scripts/main.gd":
	func create_active_store() -> RefCounted:
		return preload("res://tests/support/memory_run_store.gd").new()
	func load_progress() -> void:
		meta = progression_store.defaults()
	func save_progress() -> bool:
		return true

func _initialize() -> void:
	Engine.max_fps = 60
	call_deferred("run_checks")

func send_touch(index: int, pos: Vector2, pressed: bool) -> void:
	var event = InputEventScreenTouch.new()
	event.index = index
	event.position = pos
	event.pressed = pressed
	Input.parse_input_event(event)

func run_checks() -> void:
	root.size = Vector2i(1280, 720)
	var game = TestGame.new()
	root.add_child(game)
	game.set_physics_process(false)
	game.start_run()
	await process_frame
	send_touch(0, Vector2(205, 610), true)
	await process_frame
	game.session.xp = game.session.xp_required()
	game.session.begin_level_up()
	game.consume_events()
	for i in 3: await process_frame
	var button: Button
	for child in game.game_ui.content.get_children():
		if child is Button:
			button = child
			break
	var point = button.get_global_rect().get_center()
	send_touch(1, point, true)
	await process_frame
	send_touch(1, point, false)
	for i in 3: await process_frame
	var selected = game.session.state == "playing" and game.session.upgrades.stacks.size() == 1
	var drag = InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(220, 610)
	Input.parse_input_event(drag)
	for i in 2: await process_frame
	selected = selected and game.controls.joystick_touch == 0 and game.controls.movement().x > 0
	send_touch(0, Vector2(205, 610), false)
	game.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	if selected:
		print("PASS: secondary finger selects upgrade and held joystick resumes through viewport input")
	else:
		push_error("Upgrade requires releasing the held joystick finger")
	quit(0 if selected else 1)
