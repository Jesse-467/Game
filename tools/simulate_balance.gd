extends SceneTree
## Run the actual combat model with a repeatable kiting policy; not a fun rating.

const Catalog = preload("res://scripts/core/content_catalog.gd")
const Session = preload("res://scripts/core/run_session.gd")
const World = preload("res://scripts/core/world_geometry.gd")
const STRATEGIES = {
	"volley": ["multishot", "pierce", "haste", "power", "vitality"],
	"control": ["frost", "blast", "cooldown", "power", "vitality"],
	"hunter": ["crit", "execution", "power", "haste", "vitality"]
}
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
				if run.state == "upgrade":
					var best: String = run.selected_upgrades[0].id
					var best_rank = 1000
					for choice in run.selected_upgrades:
						var rank: int = STRATEGIES[strategy].find(choice.id)
						if run.combat.stats.hp < run.combat.stats.max_hp * 0.45 and choice.id in ["heal", "vitality"]:
							rank = -2
						if rank >= -2 and rank != -1 and rank < best_rank:
							best_rank = rank
							best = choice.id
					run.apply_upgrade(best)
					continue
				var combat: RefCounted = run.combat
				var angle = run.director.elapsed * 0.60
				var destination = World.CENTER + Vector2(cos(angle) * 850, sin(angle) * 580)
				# A player normally collects nearby XP and engages the announced boss.
				var nearest_gem = 320.0
				for gem in combat.gems:
					var gem_distance: float = combat.player.distance_to(gem.pos)
					if gem_distance < nearest_gem:
						nearest_gem = gem_distance
						destination = gem.pos
				if run.director.is_boss_node():
					for enemy in combat.enemies:
						if enemy.kind == "boss":
							destination = enemy.pos + Vector2.from_angle(run.director.elapsed * 0.7) * 190.0
							break
				var movement: Vector2 = combat.player.direction_to(destination)
				var avoidance = Vector2.ZERO
				var nearby = 0
				for enemy in combat.enemies:
					var distance: float = combat.player.distance_to(enemy.pos)
					if distance < 170:
						avoidance += enemy.pos.direction_to(combat.player) * pow(1.0 - distance / 170.0, 2) * 3.0
						nearby += 1
				movement = (movement + avoidance).normalized()
				if terrain_aware and combat.field.phase in ["warning", "active"] and combat.field.definition.kind == "debuff":
					for zone in combat.field.zones:
						var distance: float = combat.player.distance_to(zone.pos)
						if distance < float(zone.radius) + 45.0:
							var away: Vector2 = zone.pos.direction_to(combat.player)
							if away.length_squared() < 0.1: away = Vector2.DOWN
							movement = (movement + away * 2.5 * (1.0 - distance / (float(zone.radius) + 45.0))).normalized()
				movement = avoid_area_warnings(combat, movement)
				if nearby >= 3:
					run.cast_skill()
				for enemy in combat.enemies:
					if enemy.pos.distance_to(combat.player) < 55:
						run.dash()
						break
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
	file.store_string(JSON.stringify({"method": "actual 60Hz simulation, automated kiting, nearby XP collection, boss engagement and circle/ring avoidance, zero camp growth; no general projectile dodging", "terrain_aware": terrain_aware, "limit_seconds": limit_seconds, "runs": report}, "\t"))
	file.close()
	quit()

func avoid_area_warnings(combat: RefCounted, movement: Vector2) -> Vector2:
	var circles: Array[Dictionary] = []
	var rings: Array[Dictionary] = []
	for enemy in combat.enemies:
		if enemy.telegraph <= 0: continue
		for shape in combat.attack_telegraph(enemy):
			if shape.kind == "circle": circles.append(shape)
			elif shape.kind == "ring": rings.append(shape)
	for ring in rings:
		var distance: float = combat.player.distance_to(ring.pos)
		if distance > float(ring.inner_radius) - 30 and distance < float(ring.radius) + 30:
			var direction: Vector2 = ring.pos.direction_to(combat.player)
			movement = -direction if distance - float(ring.inner_radius) < float(ring.radius) - distance else direction
	var inside_circle = false
	for circle in circles:
		if combat.player.distance_to(circle.pos) < float(circle.radius) + 30:
			inside_circle = true
	if inside_circle:
		var best_score = -INF
		for i in 16:
			var candidate = Vector2.from_angle(i * TAU / 16.0)
			var endpoint: Vector2 = combat.player + candidate * 125.0
			if not World.BOUNDS.grow(-World.PLAYER_MARGIN).has_point(endpoint): continue
			var margin = INF
			for circle in circles:
				margin = minf(margin, endpoint.distance_to(circle.pos) - float(circle.radius) - 20)
			var score = margin + candidate.dot(movement) * 8.0
			if score > best_score:
				best_score = score
				movement = candidate
	return movement
