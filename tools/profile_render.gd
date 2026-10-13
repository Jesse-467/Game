extends SceneTree
## Desktop GL benchmark using the production game scene and explicit test populations.
## Fixture HP/population are synthetic. Results describe rendering cost, not difficulty.

class ProfileGame extends "res://scripts/main.gd":
	func create_active_store() -> RefCounted:
		return preload("res://tests/support/memory_run_store.gd").new()
	var population: Dictionary = {}
	var fixture_rng = RandomNumberGenerator.new()
	var scene_update_ms = 0.0
	var fixture_ms = 0.0
	var freeze_simulation = false

	func load_progress() -> void:
		meta = progression_store.defaults()
	func save_progress() -> bool:
		return true
	func _notification(_what: int) -> void:
		# A hidden benchmark window must remain active while desktop focus is elsewhere.
		pass
	func _physics_process(delta: float) -> void:
		if population.is_empty(): return
		var setup_start = Time.get_ticks_usec()
		var combat: RefCounted = session.combat
		while combat.enemies.size() < int(population.enemies):
			var id = "boss_ogre" if combat.enemies.is_empty() else ["slime", "bat", "skeleton", "shaman", "charger", "elite_guard"][combat.enemies.size() % 6]
			combat.spawn_enemy(id, random_position())
			combat.enemies[-1].hp = 1000000.0
			combat.enemies[-1].max_hp = 1000000.0
			combat.enemies[-1].born = 0.0
		while combat.projectiles.size() < int(population.projectiles):
			var hostile = combat.projectiles.size() % 3 == 0
			combat.projectiles.append({"pos": random_position(), "velocity": Vector2.from_angle(fixture_rng.randf() * TAU) * 170.0, "life": 2.5, "damage": 0.5, "hostile": hostile, "source": "render fixture", "pierce": 4, "hit_ids": [], "crit_chance": 0.7, "control_multiplier": 1.0, "color": "f1cc78"})
		while combat.effects.size() < int(population.effects):
			combat.effects.append({"pos": random_position(), "radius": 36.0, "life": 0.8, "color": Color("f1cc78"), "kind": "text", "text": "12!"})
		combat.stats.hp = combat.stats.max_hp
		controls.mouse_attack = true
		controls.joystick_vector = Vector2.from_angle(session.director.elapsed * 0.45)
		fixture_ms = (Time.get_ticks_usec() - setup_start) / 1000.0
		var started = Time.get_ticks_usec()
		if freeze_simulation:
			battle_view.sync()
			game_ui.sync(session, delta)
		else:
			if population.get("full_build", false) and combat.skill_cooldown <= 0:
				session.cast_skill()
			super._physics_process(delta)
		scene_update_ms = (Time.get_ticks_usec() - started) / 1000.0

	func random_position() -> Vector2:
		var view = preload("res://scripts/core/world_geometry.gd").visible_rect(session.combat.player)
		return (view.position + Vector2(fixture_rng.randf_range(70, 1210), fixture_rng.randf_range(150, 550))).clamp(Vector2(75, 75), preload("res://scripts/core/world_geometry.gd").BOUNDS.end - Vector2(75, 75))

var cases = [
	{"name": "typical", "enemies": 20, "projectiles": 28, "effects": 24},
	{"name": "configured_limits", "enemies": 120, "projectiles": 240, "effects": 128},
	{"name": "full_build_limits", "enemies": 120, "projectiles": 240, "effects": 128, "full_build": true},
	{"name": "paused_limits", "enemies": 120, "projectiles": 240, "effects": 128}
]
var profile_game: ProfileGame
var collecting = false
var last_draw_usec = 0
var frame_intervals: Array[float] = []
var scene_costs: Array[float] = []
var setup_costs: Array[float] = []
var minimum_counts = Vector3i(100000, 100000, 100000)
var maximum_counts = Vector3i.ZERO
var requested_case = ""
var sample_duration_ms = 8000
var requested_report = ""

func _initialize() -> void:
	Engine.max_fps = 60
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--case="): requested_case = argument.trim_prefix("--case=")
		elif argument.begins_with("--seconds="): sample_duration_ms = maxi(8000, int(float(argument.trim_prefix("--seconds=")) * 1000))
		elif argument.begins_with("--report="): requested_report = argument.trim_prefix("--report=")
	call_deferred("profile")

func on_frame_drawn() -> void:
	var now = Time.get_ticks_usec()
	if collecting:
		frame_intervals.append((now - last_draw_usec) / 1000.0)
		scene_costs.append(profile_game.scene_update_ms)
		setup_costs.append(profile_game.fixture_ms)
		var combat: RefCounted = profile_game.session.combat
		var counts = Vector3i(combat.enemies.size(), combat.projectiles.size(), combat.effects.size())
		minimum_counts = minimum_counts.min(counts)
		maximum_counts = maximum_counts.max(counts)
	last_draw_usec = now

func percentile(samples: Array[float], fraction: float) -> float:
	var ordered = samples.duplicate()
	ordered.sort()
	return ordered[clampi(roundi((ordered.size() - 1) * fraction), 0, ordered.size() - 1)]

func profile() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Rendering benchmark requires a real desktop rendering driver")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var game = ProfileGame.new()
	profile_game = game
	root.add_child(game)
	RenderingServer.frame_post_draw.connect(on_frame_drawn)
	game.fixture_rng.seed = 4421
	DirAccess.make_dir_recursive_absolute("res://builds/reports/render")
	var results: Array[Dictionary] = []
	for population in cases:
		if not requested_case.is_empty() and population.name != requested_case: continue
		game.population = population
		game.freeze_simulation = false
		game.start_run()
		game.session.combat.stats.damage = 0.5
		if population.get("full_build", false):
			game.session.combat.stats.merge({"projectile_count": 3, "attack_interval": 0.22, "pierce": 3, "crit_chance": 0.7, "blast_fraction": 0.7, "slow_fraction": 0.35, "slow_duration": 2.0, "elite_bonus": 1.0, "skill_cooldown": 3.0}, true)
		game.session.combat.stats.max_hp = 10000.0
		game.session.director.node_index = 20
		game.session.combat.field.configure_node(20)
		game.session.combat.field.prepare_zones()
		game.session.combat.field.phase = "active"
		game.session.combat.field.phase_left = 10000.0
		print("Warm up: %s" % population.name)
		var warmup = Time.get_ticks_msec()
		while Time.get_ticks_msec() - warmup < 2000:
			await process_frame
			await RenderingServer.frame_post_draw
		if population.name == "paused_limits":
			game.session.pause()
			game.consume_events()
			game.freeze_simulation = true
		frame_intervals.clear()
		scene_costs.clear()
		setup_costs.clear()
		minimum_counts = Vector3i(100000, 100000, 100000)
		maximum_counts = Vector3i.ZERO
		var drawn_before = Engine.get_frames_drawn()
		var simulation_before = game.session.director.elapsed
		var stability_samples: Array[Dictionary] = []
		var next_sample_ms = 0
		collecting = true
		var started = Time.get_ticks_msec()
		while Time.get_ticks_msec() - started < sample_duration_ms:
			var elapsed = Time.get_ticks_msec() - started
			if elapsed >= next_sample_ms:
				var sample = {"wall_seconds": elapsed / 1000.0, "simulation_seconds": game.session.director.elapsed - simulation_before, "state": game.session.state, "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "objects": Performance.get_monitor(Performance.OBJECT_COUNT), "static_memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC), "drawn_frames": Engine.get_frames_drawn() - drawn_before}
				stability_samples.append(sample)
				print("STABILITY: " + JSON.stringify(sample))
				next_sample_ms += 60000
			await process_frame
		collecting = false
		var frames_drawn = Engine.get_frames_drawn() - drawn_before
		var elapsed_ms = Time.get_ticks_msec() - started
		var simulation_elapsed = game.session.director.elapsed - simulation_before
		var result = {"case": population.name, "test_population": population, "observed_min_counts": [minimum_counts.x, minimum_counts.y, minimum_counts.z], "observed_max_counts": [maximum_counts.x, maximum_counts.y, maximum_counts.z], "frames": frames_drawn, "frame_samples": frame_intervals.size(), "mean_frame_ms": elapsed_ms / float(frames_drawn), "frame_p95_ms": percentile(frame_intervals, 0.95), "frame_max_ms": frame_intervals.max(), "scene_update_p95_ms": percentile(scene_costs, 0.95), "fixture_p95_ms": percentile(setup_costs, 0.95), "simulation_elapsed_seconds": simulation_elapsed, "run_state": game.session.state, "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "static_memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC)}
		results.append(result)
		result.stability_samples = stability_samples
		root.get_texture().get_image().save_png("res://builds/reports/render/%s.png" % population.name)
		print(JSON.stringify(result))
	var report_path = "res://builds/reports/render/profile.json" if requested_case.is_empty() else "res://builds/reports/render/%s.json" % requested_case
	if not requested_report.is_empty(): report_path = requested_report
	var file = FileAccess.open(report_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope": "desktop GL; hidden test window; synthetic populations; 60FPS cap; vsync disabled; per-render-frame samples", "adapter": RenderingServer.get_video_adapter_name(), "results": results}, "\t"))
	file.close()
	game.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	quit()
