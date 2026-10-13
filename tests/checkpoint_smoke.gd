extends SceneTree

const Catalog = preload("res://scripts/core/content_catalog.gd")
const Session = preload("res://scripts/core/run_session.gd")
const Store = preload("res://scripts/core/active_run_store.gd")

class TestGame extends "res://scripts/main.gd":
	var allow_progress_writes = true
	var initial_checkpoint: Dictionary = {}
	var settled_id = ""
	func create_active_store() -> RefCounted:
		var store = preload("res://tests/support/memory_run_store.gd").new()
		store.document = initial_checkpoint.duplicate(true)
		return store
	func load_progress() -> void:
		meta = progression_store.defaults()
		meta.last_settled_run_id = settled_id
	func save_progress() -> bool:
		return allow_progress_writes

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
	var content = Catalog.new()
	content.load_content()
	var original = Session.new(content)
	original.start("mage", 2, 4141)
	original.director.node_index = 12
	original.combat.field.configure_node(12)
	original.combat.spawn_enemy("boss_lich", Vector2(800, 220))
	original.combat.spawn_enemy("charger", Vector2(430, 350))
	original.combat.cast_skill()
	original.combat.attack()
	original.combat.add_gem(Vector2(500, 290), 3)
	for i in 90: original.step(1.0 / 60, Vector2.RIGHT, true)
	check(original.state == "playing", "Checkpoint fixture has an active living run")
	var snapshot = original.checkpoint()
	var store = Store.new()
	DirAccess.make_dir_recursive_absolute("res://builds/test-saves")
	store.path = "res://builds/test-saves/active-run-test.save"
	store.clear_checkpoint()
	check(store.save_checkpoint(snapshot) == OK, "Checkpoint writes native simulation values")
	var loaded = store.load_checkpoint()
	check(var_to_bytes(snapshot) == var_to_bytes(loaded), "Disk roundtrip preserves vectors, colors, typed arrays and RNG integers exactly")
	var restored = Session.new(content)
	check(restored.restore_checkpoint(loaded) and restored.state == "paused", "Active run restores safely paused")
	check(restored.level == original.level and restored.combat.stats == original.combat.stats, "Existing level and build are retained for the same run")
	check(restored.rng.state == original.rng.state and restored.combat.field.rng.state == original.combat.field.rng.state, "Combat and terrain RNG states survive restoration")
	check(restored.combat.enemies == original.combat.enemies and restored.combat.projectiles == original.combat.projectiles, "Enemy telegraphs, charges and existing projectiles survive restoration")
	var previous_time = restored.director.elapsed
	restored.step(2, Vector2.RIGHT, true)
	check(restored.director.elapsed == previous_time, "Restored run waits for explicit resume")
	restored.resume()
	for i in 600:
		var movement = Vector2.from_angle(i * 0.01)
		original.step(1.0 / 60, movement, true)
		restored.step(1.0 / 60, movement, true)
		if original.state == "upgrade":
			original.apply_upgrade(original.selected_upgrades[0].id)
			restored.apply_upgrade(restored.selected_upgrades[0].id)
	check(var_to_bytes(original.checkpoint()) == var_to_bytes(restored.checkpoint()), "Continuation reproduces the exact simulation and future RNG trajectory")
	original.start("ranger", 0, 5252)
	original.xp = original.xp_required()
	original.begin_level_up()
	var upgrade_checkpoint = original.checkpoint()
	check(restored.restore_checkpoint(upgrade_checkpoint) and restored.state == "upgrade", "Pending upgrade choice remains pending after reload")
	check(restored.selected_upgrades == original.selected_upgrades and restored.rng.state == original.rng.state, "Reload does not reroll upgrade offers")
	var selected: String = restored.selected_upgrades[0].id
	restored.apply_upgrade(selected)
	check(restored.state == "playing" and restored.upgrades.stacks[selected] == 1, "Restored offer applies once and continues the run")
	store.save_checkpoint(snapshot)
	store.save_checkpoint(upgrade_checkpoint)
	var file = FileAccess.open(store.path, FileAccess.WRITE)
	file.store_var({"schema_version": 1, "checkpoint": {"schema_version": 1, "state": "playing"}}, false)
	file.close()
	check(store.load_checkpoint() == snapshot, "Incomplete primary snapshot falls back to the previous valid checkpoint")
	var unsupported = snapshot.duplicate(true)
	unsupported.schema_version = 999
	check(not restored.restore_checkpoint(unsupported), "Unknown checkpoint format is not partly applied")
	store.clear_checkpoint()
	check(store.load_checkpoint().is_empty() and not FileAccess.file_exists(store.path + ".bak"), "Clearing a run also clears backups so death cannot resurrect an older checkpoint")
	var game = TestGame.new()
	root.add_child(game)
	game.set_physics_process(false)
	# Give the audio mix thread a real frame before rapid lifecycle fixtures.
	await create_timer(0.05).timeout
	game.start_run()
	game.checkpoint_left = 0
	game._physics_process(1.0 / 60)
	check(game.saved_checkpoint.director.elapsed == game.session.director.elapsed and game.checkpoint_left > 19, "Periodic checkpoint records current simulation time and resets its interval")
	game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.saved_checkpoint.state == "paused" and game.session.state == "paused", "Background notification saves the paused living run immediately")
	game.session.resume()
	game.consume_events()
	game.session.kills = 50
	game.session.finish()
	game.consume_events()
	check(game.meta.crystals == 5 and game.meta.total_runs == 1 and game.saved_checkpoint.is_empty(), "Death commits one reward and removes the active run")
	game.session.reward_paid = false
	game.settle_run(game.session.result())
	check(game.meta.crystals == 5 and game.meta.total_runs == 1, "Persistent run ID prevents reward duplication after repeated settlement")
	game.start_run()
	game.session.xp = game.session.xp_required()
	game.session.begin_level_up()
	game.consume_events()
	game.on_action("save_camp")
	check(game.session.state == "menu" and not game.saved_checkpoint.is_empty(), "Save-and-camp retains an unfinished run")
	game.on_action("continue_saved")
	check(game.session.state == "upgrade", "Camp continuation restores the original pending choice")
	game.session.apply_upgrade(game.session.selected_upgrades[0].id)
	game.consume_events()
	game._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	game._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(game.session.state == "paused", "Duplicate OS back callbacks perform only one navigation step")
	var next_back_time = Time.get_ticks_msec() + 220
	while Time.get_ticks_msec() < next_back_time: await process_frame
	game._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(game.session.state == "menu" and not game.saved_checkpoint.is_empty(), "A separate back press saves and returns to camp")
	game.start_run()
	check(game.session.level == 1 and game.session.xp == 0, "Starting a new expedition still resets to level one")
	game.allow_progress_writes = false
	game.session.kills = 10
	game.session.finish()
	game.consume_events()
	var pending_crystals = game.meta.crystals
	check(not game.session.reward_paid and not game.saved_checkpoint.is_empty(), "Failed meta commit retains a checkpoint rather than erasing recovery data")
	game.allow_progress_writes = true
	game.settle_run(game.session.result())
	check(game.session.reward_paid and game.meta.crystals == pending_crystals and game.saved_checkpoint.is_empty(), "Retry commits an existing settlement without awarding it twice")
	var restart = TestGame.new()
	restart.initial_checkpoint = snapshot
	restart.settled_id = snapshot.session.run_id
	root.add_child(restart)
	restart.set_physics_process(false)
	check(restart.saved_checkpoint.is_empty() and restart.active_store.load_checkpoint().is_empty(), "App restart ignores a stale active file whose reward was already committed")
	await create_timer(0.05).timeout
	restart.queue_free()
	game.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	if failures.is_empty(): print("PASS: %d checkpoint, exact continuation, upgrade and settlement checks" % checks)
	quit(0 if failures.is_empty() else 1)
