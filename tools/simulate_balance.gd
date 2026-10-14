extends SceneTree
## Run the actual combat model with a repeatable kiting policy; not a fun rating.

const Catalog = preload("res://scripts/core/content_catalog.gd")
const Session = preload("res://scripts/core/run_session.gd")
const Policy = preload("res://tools/playtest_policy.gd")
const STRATEGIES = Policy.STRATEGIES
var terrain_aware = true
var report_path = "res://builds/reports/balance-simulation.json"
var limit_seconds = 1800.0
var character = "knight"

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--ignore-terrain": terrain_aware = false
		elif argument.begins_with("--report="): report_path = argument.trim_prefix("--report=")
		elif argument.begins_with("--seconds="): limit_seconds = float(argument.trim_prefix("--seconds="))
		elif argument.begins_with("--character="): character = argument.trim_prefix("--character=")
	call_deferred("simulate")

func simulate() -> void:
	var content = Catalog.new()
	content.load_content()
	var report: Array[Dictionary] = []
	for strategy in STRATEGIES:
		for seed_value in [11, 29, 47]:
			var run = Session.new(content)
			run.start(character, 0, seed_value)
			var first_level = -1.0
			var first_boss = -1.0
			var max_enemies = 0
			var max_projectiles = 0
			var max_step_microseconds = 0
			var total_step_microseconds = 0
			var steps = 0
			var phase_counts: Dictionary = {}
			while run.director.elapsed < limit_seconds and run.state != "dead":
				if run.state == "equipment":
					run.choose_equipment(Policy.equipment_choice(run))
					continue
				if run.state == "upgrade":
					run.apply_upgrade(Policy.upgrade(run, strategy))
					continue
				var combat: RefCounted = run.combat
				var movement = Policy.prepare(run, terrain_aware)
				var started = Time.get_ticks_usec()
				run.step(1.0 / 60.0, movement, true)
				var spent = Time.get_ticks_usec() - started
				total_step_microseconds += spent
				max_step_microseconds = maxi(max_step_microseconds, spent)
				steps += 1
				if first_level < 0 and run.level > 1: first_level = run.director.elapsed
				if first_boss < 0 and run.director.bosses_defeated > 0: first_boss = run.director.elapsed
				max_enemies = maxi(max_enemies, combat.enemies.size())
				max_projectiles = maxi(max_projectiles, combat.projectiles.size())
				for event in run.events:
					if event.type == "boss_phase":
						phase_counts[event.phase_id] = int(phase_counts.get(event.phase_id, 0)) + 1
				run.events.clear()
			var result = run.result()
			result.strategy = strategy
			result.terrain_aware = terrain_aware
			result.seed = seed_value
			result.first_level_seconds = first_level
			result.first_boss_seconds = first_boss
			result.max_enemies = max_enemies
			result.max_projectiles = max_projectiles
			result.mean_step_ms = total_step_microseconds / maxf(1, steps) / 1000.0
			result.max_step_ms = max_step_microseconds / 1000.0
			result.boss_phase_counts = phase_counts
			report.append(result)
			print("%s %s seed%d: %.0fs, lv%d, boss%d, first level %.1fs, first boss %.1fs" % [character, strategy, seed_value, result.seconds, result.level, result.bosses, first_level, first_boss])
	DirAccess.make_dir_recursive_absolute("res://builds/reports")
	var file = FileAccess.open(report_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"profile":"release-hard", "method": "actual60Hz simulation, nearby XP/loot collection, upgrade and equipment choices, boss engagement, warning/contact/hazard avoidance and emergency dodge, zero camp growth; automated policy is not a human skill estimate", "terrain_aware": terrain_aware, "limit_seconds": limit_seconds, "runs": report}, "\t"))
	file.close()
	quit()
