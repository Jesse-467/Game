extends RefCounted
## One active button; learned ranks persist only within the run.
const Config = preload("res://scripts/core/gameplay_config.gd")

var definitions: Dictionary = {}
var active_id = "nova"
var ranks: Dictionary = {}
var character_id = "knight"

func _init() -> void:
	var document: Dictionary = Config.read("skills")
	for entry in document.skills: definitions[entry.id] = entry

func reset(character: String, starting_skill: String) -> void:
	character_id = character
	active_id = starting_skill
	ranks = {starting_skill: 1}

func rank() -> int:
	return int(ranks.get(active_id, 1))

func profile(id: String = "", value: int = -1) -> Dictionary:
	if id.is_empty(): id = active_id
	if value < 0: value = rank()
	var entry: Dictionary = definitions[id].duplicate(true)
	var n = value - 1
	entry.damage += float(entry.damage_per_rank) * n
	entry.radius = float(entry.get("radius", 0)) + float(entry.get("radius_per_rank", 0)) * n
	entry.count = int(entry.get("count", 1)) + int(entry.get("count_per_rank", 0)) * n
	entry.shield = float(entry.get("shield", 0)) + float(entry.get("shield_per_rank", 0)) * n
	return entry

func training_description() -> String:
	var before = profile()
	var after = profile(active_id, rank() + 1)
	var parts: Array[String] = ["伤害 ×%.2f → ×%.2f" % [before.damage, after.damage]]
	if before.kind == "projectiles": parts.append("弹体 %d → %d，贯穿%d" % [before.count, after.count, after.pierce])
	else: parts.append("范围 %.0f → %.0f" % [before.radius, after.radius])
	if before.kind == "shield": parts.append("护盾 %.0f → %.0f" % [before.shield, after.shield])
	return " · ".join(parts)

func cooldown(stats: Dictionary) -> float:
	return maxf(float(Config.section("abilities").skill_cooldown_floor), float(stats.skill_cooldown) * float(definitions[active_id].cooldown) / float(Config.section("skill_progression").base_cooldown_seconds))

func resolve_offer(id: String) -> Dictionary:
	var parts = id.split(":")
	if parts.size() != 2 or not definitions.has(parts[1]): return {}
	var entry: Dictionary = definitions[parts[1]]
	if entry.character != character_id: return {}
	if parts[0] == "train":
		if parts[1] != active_id or rank() >= int(Config.section("skill_progression").max_rank): return {}
		return {"id": id, "kind": "skill", "title": "%s → %d级" % [entry.name, rank() + 1], "description": training_description(), "tags": ["skill"]}
	if parts[0] == "skill" and parts[1] != active_id:
		return {"id": id, "kind": "skill", "title": "替换为%s · %d级" % [entry.name, int(ranks.get(parts[1], 1))], "description": entry.description, "tags": ["skill"]}
	return {}

func offers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var training = resolve_offer("train:" + active_id)
	if not training.is_empty(): result.append(training)
	for id in definitions:
		var offer = resolve_offer("skill:" + id)
		if not offer.is_empty(): result.append(offer)
	return result

func choose(id: String) -> bool:
	if resolve_offer(id).is_empty(): return false
	var parts = id.split(":")
	if parts[0] == "train": ranks[active_id] = rank() + 1
	else:
		active_id = parts[1]
		ranks[active_id] = int(ranks.get(active_id, 1))
	return true
