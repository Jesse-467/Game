extends RefCounted
## Endless node pacing and spawn selection. Does not perform combat or drawing.

var catalog: RefCounted
var elapsed = 0.0
var node_time = 0.0
var node_index = 1
var bosses_defeated = 0
var spawn_timer = 0.0

func _init(content: RefCounted) -> void:
	catalog = content
	spawn_timer = float(catalog.balance.difficulty.initial_spawn_delay)

func reset() -> void:
	elapsed = 0.0
	node_time = 0.0
	node_index = 1
	bosses_defeated = 0
	spawn_timer = float(catalog.balance.difficulty.initial_spawn_delay)

func tick(delta: float) -> bool:
	elapsed += delta
	node_time += delta
	spawn_timer -= delta
	return not is_boss_node() and node_time >= float(catalog.balance.difficulty.node_duration_seconds)

func is_boss_node() -> bool:
	return node_index % int(catalog.balance.difficulty.boss_every_nodes) == 0

func advance() -> String:
	node_index += 1
	node_time = 0.0
	spawn_timer = float(catalog.balance.difficulty.node_spawn_delay)
	return current_boss_id() if is_boss_node() else ""

func current_boss_id() -> String:
	return catalog.bosses[cycle_index() % catalog.bosses.size()]

func cycle_index() -> int:
	return int((node_index - 1) / int(catalog.balance.difficulty.boss_every_nodes))

func health_multiplier() -> float:
	# Linear per-cycle growth keeps late encounters readable. No forced end timer.
	return 1.0 + elapsed / 60.0 * float(catalog.balance.difficulty.hp_growth_per_minute)

func boss_health_multiplier() -> float:
	# Boss definitions already increase within each three-boss rotation.
	return 1.0 + cycle_index() * float(catalog.balance.difficulty.boss_hp_growth_per_encounter) + boss_rotation_index() * float(catalog.balance.difficulty.boss_hp_growth_per_rotation)

func boss_rotation_index() -> int:
	return int(cycle_index() / catalog.bosses.size())

func damage_multiplier() -> float:
	return 1.0 + elapsed / 60.0 * float(catalog.balance.difficulty.damage_growth_per_minute)

func consume_spawn(rng: RandomNumberGenerator, enemies: Array = []) -> String:
	var rule = node_rule()
	var pacing = catalog.balance.difficulty
	var base_interval = maxf(pacing.spawn_interval_floor_seconds, float(pacing.spawn_interval_start_seconds) / (1.0 + elapsed / 60.0 * float(pacing.spawn_growth_per_minute)))
	spawn_timer = base_interval * population_multiplier()
	var elite_count = enemies.filter(func(enemy): return enemy.kind == "elite" and enemy.hp > 0).size()
	if elite_count < int(rule.elite_max_active) and rng.randf() < float(rule.elite_chance):
		return rule.elite_id
	var pool: Array[Dictionary] = []
	var total = 0.0
	for entry in catalog.enemies.values():
		if entry.kind == "normal" and rule.enemies.has(entry.id) and node_index >= int(entry.min_node):
			pool.append(entry)
			total += float(entry.weight)
	var roll = rng.randf() * total
	for entry in pool:
		roll -= float(entry.weight)
		if roll <= 0:
			return entry.id
	return str(catalog.encounters.fallback_enemy)

func node_rule() -> Dictionary:
	return catalog.encounters.nodes[(node_index - 1) % catalog.encounters.nodes.size()]

func enemy_level() -> int:
	var curve: Dictionary = catalog.balance.enemy_growth
	return int(curve.starting_level) + floori((node_index - 1) * float(curve.levels_per_node))

func enemy_stats(definition: Dictionary) -> Dictionary:
	var curve: Dictionary = catalog.balance.enemy_growth
	var level = enemy_level()
	var n = level - int(curve.starting_level)
	var hp_scale = (boss_health_multiplier() + n * float(curve.boss_hp_per_level)) if definition.kind == "boss" else (health_multiplier() + n * float(curve.normal_hp_per_level))
	var damage_scale = damage_multiplier() + n * float(curve.damage_per_level)
	# This first stage contains only template and growth-curve values.
	var base = {"max_hp":float(definition.hp) * hp_scale, "damage":float(definition.damage) * damage_scale, "damage_scale":damage_scale, "speed":float(definition.speed) * minf(float(catalog.balance.difficulty.speed_multiplier_cap), 1.0 + elapsed / float(catalog.balance.combat.enemy_speed_growth_seconds) + n * float(curve.speed_per_level)), "defense":float(definition.defense) + n * float(curve.defense_per_level), "crit_resistance":minf(float(curve.crit_resistance_cap), float(definition.crit_resistance) + n * float(curve.crit_resistance_per_level)), "slow_resistance":float(definition.slow_resistance), "attack_speed_bonus":0.0}
	var result = base.duplicate(true)
	var bonuses: Dictionary = {}
	var names: Array[String] = []
	# Node modifiers never mutate the template or the first-stage base values.
	for id in node_rule().get("modifiers", []):
		var modifier: Dictionary = catalog.encounters.modifiers[id]
		if not modifier.targets.has(definition.kind): continue
		names.append(modifier.name)
		for key in modifier.values: bonuses[key] = float(bonuses.get(key, 0)) + float(modifier.values[key])
	result.max_hp *= 1.0 + float(bonuses.get("hp_bonus", 0))
	result.damage_scale *= 1.0 + float(bonuses.get("damage_bonus", 0))
	result.damage *= 1.0 + float(bonuses.get("damage_bonus", 0))
	result.speed *= 1.0 + float(bonuses.get("speed_bonus", 0))
	result.defense += float(bonuses.get("defense_add", 0))
	result.crit_resistance = clampf(float(result.crit_resistance) + float(bonuses.get("crit_resistance_add", 0)), 0, float(curve.crit_resistance_cap))
	result.slow_resistance = clampf(float(result.slow_resistance) + float(bonuses.get("slow_resistance_add", 0)), 0, float(curve.slow_resistance_cap))
	result.attack_speed_bonus = float(bonuses.get("attack_speed_bonus", 0))
	result.base_stats = base
	result.level = level
	result.modifier_names = names
	return result

func pacing_name() -> String:
	var pacing = catalog.balance.difficulty
	if is_boss_node(): return "Boss挑战"
	if node_time < float(pacing.pacing_recovery_seconds): return "蓄势"
	if node_time >= float(pacing.pacing_peak_end_seconds): return "喘息"
	if node_time >= float(pacing.pacing_peak_start_seconds): return "怪物潮"
	return "攻势渐强"

func population_multiplier() -> float:
	var pacing = catalog.balance.difficulty
	if is_boss_node(): return float(pacing.boss_mob_interval_multiplier)
	if node_time < float(pacing.pacing_recovery_seconds) or node_time >= float(pacing.pacing_peak_end_seconds): return float(pacing.pacing_recovery_multiplier)
	if node_time >= float(pacing.pacing_peak_start_seconds): return float(pacing.pacing_peak_multiplier)
	return lerpf(float(pacing.spawn_ramp_start_multiplier), float(pacing.spawn_ramp_end_multiplier), inverse_lerp(float(pacing.pacing_recovery_seconds), float(pacing.pacing_peak_start_seconds), node_time))
