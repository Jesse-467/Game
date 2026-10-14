extends RefCounted
## Equipment supplies flat base attributes. Same-source bonuses add within buckets.
## Damage = base * attack bucket * target bucket * field * skill * critical.

const Config = preload("res://scripts/core/gameplay_config.gd")

static func evaluate(base: Dictionary, equipment: Dictionary, stacks: Dictionary, definitions: Array) -> Dictionary:
	var rules = Config.section("stat_rules")
	var result = base.duplicate(true)
	var attack_bonus = 0.0
	var attack_speed_bonus = 0.0
	var movement_bonus = 0.0
	var cooldown_bonus = 0.0
	var projectile_penalty = 0.0
	for key in equipment:
		result[key] = float(result.get(key, 0.0)) + float(equipment[key])
	for entry in definitions:
		var count = int(stacks.get(entry.id, 0))
		if count <= 0: continue
		match entry.effect:
			"damage_multiplier": attack_bonus += (float(entry.value) - 1.0) * count
			"attack_interval_multiplier": attack_speed_bonus += (1.0 - float(entry.value)) * count
			"move_speed_multiplier": movement_bonus += (float(entry.value) - 1.0) * count
			"max_hp_add": result.max_hp += float(entry.value) * count
			"heal_and_damage": result.damage += float(entry.damage_add) * count
			"multishot":
				result.projectile_count += int(entry.value) * count
				projectile_penalty += float(entry.damage_penalty) * count
			"frost":
				result.slow_fraction = maxf(float(result.slow_fraction), float(entry.value))
				result.slow_duration = maxf(float(result.slow_duration), float(entry.duration))
			"stat_add":
				result[entry.stat] = float(result.get(entry.stat, 0)) + float(entry.value) * count
				if entry.has("cap"): result[entry.stat] = minf(result[entry.stat], float(entry.cap))
			"stat_multiply":
				if entry.stat == "skill_cooldown": cooldown_bonus += (1.0 - float(entry.value)) * count
	result.base_damage = result.damage
	result.attack_bonus = attack_bonus
	result.attack_speed_bonus = attack_speed_bonus
	result.damage *= (1.0 + attack_bonus) * maxf(float(rules.multishot_damage_floor), 1.0 - projectile_penalty)
	# Flat attack_rate is measured in attacks/second, before the haste bucket.
	var base_rate = 1.0 / float(result.attack_interval) + float(equipment.get("attack_rate", 0.0))
	result.attack_interval = maxf(float(rules.attack_interval_floor), 1.0 / (base_rate * (1.0 + attack_speed_bonus)))
	result.move_speed = minf(float(rules.movement_cap), float(result.move_speed) * (1.0 + movement_bonus))
	result.skill_cooldown = maxf(float(Config.section("abilities").skill_cooldown_floor), float(result.skill_cooldown) / (1.0 + cooldown_bonus))
	result.armor = maxf(0, float(result.get("armor", 0)))
	result.crit_chance = clampf(float(result.crit_chance), 0, float(rules.crit_cap))
	result.hp = minf(float(result.get("hp", result.max_hp)), float(result.max_hp))
	result._base_stats = base.duplicate(true)
	result._equipment_stats = equipment.duplicate(true)
	result._blessing_stacks = stacks.duplicate(true)
	return result

static func armor_multiplier(armor: float) -> float:
	var scale = float(Config.section("stat_rules").armor_scale)
	return scale / (scale + maxf(0, armor))
