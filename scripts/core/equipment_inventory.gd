extends RefCounted
## Four replaceable slots; equipment rolls flat base values, never buff multipliers.
const Config = preload("res://scripts/core/gameplay_config.gd")

var definitions: Dictionary = {}
var slots: Dictionary = {}
var rarities: Array = []
var equipped: Dictionary = {}
var unlocked: Array[String] = []

func _init() -> void:
	var document: Dictionary = Config.read("equipment")
	slots = document.slots
	rarities = document.rarities
	for entry in document.equipment: definitions[entry.id] = entry

func unlocked_for_bosses(bosses: int) -> Array[String]:
	var result: Array[String] = []
	for entry in definitions.values():
		if bosses >= int(entry.unlock_bosses): result.append(entry.id)
	return result

func reset(unlocks: Array = []) -> void:
	equipped.clear()
	unlocked.assign(unlocks if not unlocks.is_empty() else unlocked_for_bosses(0))

func roll(character: String, node: int, rng: RandomNumberGenerator, boss_reward: bool = false) -> Dictionary:
	var pool: Array[Dictionary] = []
	for entry in definitions.values():
		if unlocked.has(entry.id) and str(entry.get("character", character)) == character: pool.append(entry)
	if pool.is_empty(): return {}
	var definition: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	var rules = Config.section("equipment_rules")
	var chance = rng.randf()
	var rarity = 2 if node >= int(rules.epic_min_node) and chance < (float(rules.boss_epic_chance if boss_reward else rules.normal_epic_chance)) else (1 if chance < (float(rules.boss_rare_threshold if boss_reward else rules.normal_rare_threshold)) else 0)
	var tier = mini(int(rules.max_tier), 1 + int((node - 1) / int(rules.nodes_per_tier)))
	var factor = float(rarities[rarity].factor) * (1.0 + (tier - 1) * float(rules.base_growth_per_tier))
	var values: Dictionary = {}
	for key in definition.stats: values[key] = float(definition.stats[key]) * factor
	return {"id": definition.id, "slot": definition.slot, "rarity": rarity, "tier": tier, "stats": values}

func equip(item: Dictionary) -> bool:
	if not definitions.has(item.get("id", "")) or not slots.has(item.get("slot", "")): return false
	if definitions[item.id].slot != item.slot: return false
	equipped[item.slot] = item.duplicate(true)
	return true

func flat_stats() -> Dictionary:
	var result: Dictionary = {}
	for item in equipped.values():
		for key in item.stats: result[key] = float(result.get(key, 0)) + float(item.stats[key])
	return result

func item_name(item: Dictionary) -> String:
	if item.is_empty(): return "空部位"
	return "%s · %s +%d" % [rarities[int(item.rarity)].name, definitions[item.id].name, item.tier]

func stat_text(item: Dictionary) -> String:
	if item.is_empty(): return "尚未装备"
	var names = {"damage":"基础攻击", "max_hp":"基础生命", "armor":"护甲", "move_speed":"基础移速", "crit_chance":"基础暴击", "pickup_radius":"拾取范围", "attack_rate":"基础攻击频率"}
	var parts: Array[String] = []
	for key in item.stats:
		parts.append("%s %+.1f%s" % [names.get(key, key), float(item.stats[key]) * (100.0 if key == "crit_chance" else 1.0), "百分点" if key == "crit_chance" else ("次/秒" if key == "attack_rate" else "")])
	return " · ".join(parts)
