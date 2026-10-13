extends RefCounted
## Endless node pacing and spawn selection. Does not perform combat or drawing.

var catalog: RefCounted
var elapsed = 0.0
var node_time = 0.0
var node_index = 1
var bosses_defeated = 0
var spawn_timer = 0.7

func _init(content: RefCounted) -> void:
	catalog = content

func reset() -> void:
	elapsed = 0.0
	node_time = 0.0
	node_index = 1
	bosses_defeated = 0
	spawn_timer = 0.7

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
	spawn_timer = 1.4
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
	return 1.0 + int(cycle_index() / catalog.bosses.size()) * float(catalog.balance.difficulty.boss_hp_growth_per_rotation)

func boss_rotation_index() -> int:
	return int(cycle_index() / catalog.bosses.size())

func damage_multiplier() -> float:
	return 1.0 + elapsed / 60.0 * float(catalog.balance.difficulty.damage_growth_per_minute)

func consume_spawn(rng: RandomNumberGenerator) -> String:
	var phase = node_index % int(catalog.balance.difficulty.boss_every_nodes)
	var pacing = catalog.balance.difficulty
	var base_interval = maxf(pacing.spawn_interval_floor_seconds, float(pacing.spawn_interval_start_seconds) / (1.0 + elapsed / 60.0 * float(pacing.spawn_growth_per_minute)))
	spawn_timer = base_interval * population_multiplier()
	if phase == int(catalog.balance.difficulty.elite_node_in_cycle) and rng.randf() < float(catalog.balance.difficulty.elite_spawn_chance):
		return "elite_guard"
	var pool: Array[Dictionary] = []
	var total = 0.0
	for entry in catalog.enemies.values():
		if entry.kind == "normal" and node_index >= int(entry.min_node):
			pool.append(entry)
			total += float(entry.weight)
	var roll = rng.randf() * total
	for entry in pool:
		roll -= float(entry.weight)
		if roll <= 0:
			return entry.id
	return "slime"

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
	return lerpf(1.15, 0.85, inverse_lerp(float(pacing.pacing_recovery_seconds), float(pacing.pacing_peak_start_seconds), node_time))
