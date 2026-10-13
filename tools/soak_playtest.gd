extends SceneTree
## Real wall-clock rendering of normal gameplay with isolated progress and bounded samples.
const Policy = preload("res://tools/playtest_policy.gd")

class SoakGame extends "res://scripts/main.gd":
	var strategy = "volley"
	var update_ms = 0.0
	var choice_count = 0
	func create_active_store() -> RefCounted: return preload("res://tests/support/memory_run_store.gd").new()
	func load_progress() -> void: meta = progression_store.defaults()
	func save_progress() -> bool: return true
	func _notification(_what: int) -> void: pass
	func _physics_process(delta: float) -> void:
		var start = Time.get_ticks_usec()
		if session.state == "upgrade":
			on_action("upgrade", Policy.upgrade(session, strategy))
			choice_count += 1
		if session.state == "playing":
			controls.joystick_vector = Policy.prepare(session)
			controls.mouse_attack = true
		super._physics_process(delta)
		update_ms = (Time.get_ticks_usec() - start) / 1000.0

var game: SoakGame
var seconds = 1800.0
var seed_value = 11
var collecting = false
var last_draw_usec = 0
var frame_count = 0
var interval_total = 0.0
var frame_max = 0.0
var interval_histogram: Array[int] = []
var update_histogram: Array[int] = []
var min_counts = Vector3i(100000, 100000, 100000)
var max_counts = Vector3i.ZERO
var samples: Array[Dictionary] = []
var started_ms = 0
var report_path = "res://builds/reports/render/soak-gameplay.json"

func _initialize() -> void:
	Engine.max_fps = 60
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seconds="): seconds = float(argument.trim_prefix("--seconds="))
		elif argument.begins_with("--seed="): seed_value = int(argument.trim_prefix("--seed="))
		elif argument.begins_with("--report="): report_path = argument.trim_prefix("--report=")
	interval_histogram.resize(2001)
	interval_histogram.fill(0)
	update_histogram.resize(2001)
	update_histogram.fill(0)
	call_deferred("playtest")

func record_frame() -> void:
	var now = Time.get_ticks_usec()
	if collecting:
		var interval = (now - last_draw_usec) / 1000.0
		frame_count += 1
		interval_total += interval
		frame_max = maxf(frame_max, interval)
		interval_histogram[clampi(roundi(interval * 10), 0, 2000)] += 1
		update_histogram[clampi(roundi(game.update_ms * 10), 0, 2000)] += 1
		var combat: RefCounted = game.session.combat
		var counts = Vector3i(combat.enemies.size(), combat.projectiles.size(), combat.effects.size())
		min_counts = min_counts.min(counts)
		max_counts = max_counts.max(counts)
	last_draw_usec = now

func percentile(histogram: Array[int], fraction: float) -> float:
	var count = 0
	for value in histogram: count += value
	var target = ceili(count * fraction)
	var cumulative = 0
	for i in histogram.size():
		cumulative += histogram[i]
		if cumulative >= target: return i / 10.0
	return 200.0

func sample() -> Dictionary:
	var run: RefCounted = game.session
	var result = {"wall_seconds": (Time.get_ticks_msec() - started_ms) / 1000.0, "game_seconds": run.director.elapsed, "state": run.state, "level": run.level, "node": run.director.node_index, "bosses": run.director.bosses_defeated, "hp": run.combat.stats.hp, "counts": [run.combat.enemies.size(), run.combat.projectiles.size(), run.combat.effects.size(), run.combat.gems.size()], "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "objects": Performance.get_monitor(Performance.OBJECT_COUNT), "static_memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC), "frames_drawn": frame_count}
	samples.append(result)
	print("SOAK: " + JSON.stringify(result))
	var progress = FileAccess.open("res://builds/reports/render/soak-progress.json", FileAccess.WRITE)
	progress.store_string(JSON.stringify(result, "\t"))
	progress.close()
	return result

func playtest() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Soak playtest needs an actual rendering driver")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute("res://builds/reports/render")
	game = SoakGame.new()
	root.add_child(game)
	game.set_physics_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	game.start_run()
	game.session.start("knight", 0, seed_value)
	game.save_checkpoint()
	game.battle_view.reset_actor_views()
	game.consume_events()
	RenderingServer.frame_post_draw.connect(record_frame)
	await process_frame
	await RenderingServer.frame_post_draw
	started_ms = Time.get_ticks_msec()
	last_draw_usec = Time.get_ticks_usec()
	collecting = true
	game.set_physics_process(true)
	var next_sample = 0
	while Time.get_ticks_msec() - started_ms < seconds * 1000 and game.session.state != "dead":
		var elapsed = Time.get_ticks_msec() - started_ms
		if elapsed >= next_sample:
			sample()
			root.get_texture().get_image().save_png("res://builds/reports/render/soak-%02d.png" % int(elapsed / 60000))
			next_sample += 60000
		await process_frame
	collecting = false
	game.set_physics_process(false)
	var final_sample = sample()
	root.get_texture().get_image().save_png("res://builds/reports/render/soak-final.png")
	var completed = final_sample.wall_seconds >= seconds and game.session.state != "dead"
	var report = {"completed": completed, "scope": "normal gameplay, real desktop GL, real wall clock, automated volley policy, seed fixed, zero camp growth; no general bullet dodging; bounded0.1ms histograms", "source_version": ProjectSettings.get_setting("application/config/version"), "seed": seed_value, "requested_seconds": seconds, "adapter": RenderingServer.get_video_adapter_name(), "frames": frame_count, "mean_frame_ms": interval_total / maxf(1, frame_count), "frame_p95_ms": percentile(interval_histogram, 0.95), "frame_max_ms": frame_max, "update_p95_ms": percentile(update_histogram, 0.95), "observed_min_counts": [min_counts.x, min_counts.y, min_counts.z], "observed_max_counts": [max_counts.x, max_counts.y, max_counts.z], "choice_count": game.choice_count, "result": game.session.result(), "samples": samples}
	var file = FileAccess.open(report_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	game.audio_service.music.stop()
	await create_timer(0.1).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print(("PASS" if completed else "FAILED") + ": sustained normal-gameplay rendering")
	quit(0 if completed else 1)
