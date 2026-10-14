extends RefCounted
## Content definitions and offer generation; independent of UI and input.

const Stats = preload("res://scripts/core/stat_pipeline.gd")

var definitions: Array[Dictionary] = []
var stacks: Dictionary = {}

func load_content(path: String = "res://data/upgrades.json") -> void:
	var document: Dictionary = preload("res://scripts/core/gameplay_config.gd").read("upgrades") if path == "res://data/upgrades.json" else JSON.parse_string(FileAccess.get_file_as_string(path))
	definitions.clear()
	for entry in document.upgrades:
		definitions.append(entry)

func reset_run() -> void:
	stacks.clear()

func find_definition(id: String) -> Dictionary:
	for entry in definitions:
		if entry.id == id:
			return entry
	return {}

func generate_offers(rng: RandomNumberGenerator, stats: Dictionary, count: int = -1) -> Array[Dictionary]:
	if count < 0: count = int(preload("res://scripts/core/gameplay_config.gd").section("combat").upgrade_offer_count)
	var pool: Array[Dictionary] = []
	for entry in definitions:
		if int(stats.get("level", 1)) < int(entry.get("min_level", 1)):
			continue
		var limit = int(entry.max_stacks)
		if limit > 0 and int(stacks.get(entry.id, 0)) >= limit:
			continue
		if entry.effect == "attack_interval_multiplier" and stats.attack_interval <= float(entry.floor):
			continue
		if entry.effect == "move_speed_multiplier" and stats.move_speed >= float(entry.cap):
			continue
		if entry.effect == "frost" and stats.slow_fraction >= float(entry.value) and stats.slow_duration >= float(entry.duration):
			continue
		if entry.has("stat") and entry.has("cap") and stats.get(entry.stat, 0) >= float(entry.cap):
			continue
		pool.append(entry)
	var offers: Array[Dictionary] = []
	while not pool.is_empty() and offers.size() < count:
		var index = rng.randi_range(0, pool.size() - 1)
		offers.append(pool[index])
		pool.remove_at(index)
	return offers

func apply(id: String, stats: Dictionary) -> Dictionary:
	var entry = find_definition(id)
	if entry.is_empty(): return stats
	stacks[id] = int(stacks.get(id, 0)) + 1
	var result = Stats.evaluate(stats.get("_base_stats", stats), stats.get("_equipment_stats", {}), stacks, definitions)
	result.level = int(stats.get("level", 1))
	result.hp = float(stats.hp)
	if entry.effect == "max_hp_add": result.hp += float(entry.value)
	elif entry.effect == "heal_and_damage": result.hp += float(result.max_hp) * float(entry.value)
	result.hp = minf(result.hp, result.max_hp)
	return result
