extends RefCounted
## Content definitions and offer generation; independent of UI and input.

var definitions: Array[Dictionary] = []
var stacks: Dictionary = {}

func load_content(path: String = "res://data/upgrades.json") -> void:
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
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

func generate_offers(rng: RandomNumberGenerator, stats: Dictionary, count: int = 3) -> Array[Dictionary]:
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
	var result = stats.duplicate()
	match entry.get("effect", ""):
		"damage_multiplier": result.damage *= float(entry.value)
		"attack_interval_multiplier": result.attack_interval = maxf(entry.floor, result.attack_interval * float(entry.value))
		"max_hp_add":
			result.max_hp += float(entry.value)
			result.hp = minf(result.max_hp, result.hp + float(entry.value))
		"heal_and_damage":
			result.hp = minf(result.max_hp, result.hp + result.max_hp * float(entry.value))
			result.damage += float(entry.damage_add)
		"move_speed_multiplier": result.move_speed = minf(entry.cap, result.move_speed * float(entry.value))
		"multishot":
			result.projectile_count += int(entry.value)
			result.damage *= 0.88
		"frost":
			result.slow_fraction = maxf(result.slow_fraction, entry.value)
			result.slow_duration = maxf(result.slow_duration, entry.duration)
		"stat_add":
			result[entry.stat] = result.get(entry.stat, 0) + entry.value
			if entry.has("cap"):
				result[entry.stat] = minf(result[entry.stat], entry.cap)
		"stat_multiply": result[entry.stat] = maxf(entry.get("floor", 0.0), result[entry.stat] * float(entry.value))
	stacks[id] = int(stacks.get(id, 0)) + 1
	return result
