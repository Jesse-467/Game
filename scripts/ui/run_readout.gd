extends RefCounted
## Read-only player-facing projection of simulation and saved results.

static func clock(seconds: float) -> String:
	var value = maxi(0, int(seconds))
	return "%02d:%02d" % [value / 60, value % 60]

static func current(run: RefCounted) -> Dictionary:
	var stats: Dictionary = run.combat.stats
	var field = run.combat.field.modifiers_at(run.combat.player)
	return {"base_damage": float(stats.damage), "damage": float(stats.damage) * float(field.outgoing_damage_multiplier), "base_crit": float(stats.crit_chance), "crit": clampf(float(stats.crit_chance) + float(field.crit_chance_delta), 0, 1), "move_speed": float(stats.move_speed) * float(field.move_multiplier), "control_multiplier": float(field.control_duration_multiplier), "attack_interval": float(stats.attack_interval) * float(field.attack_interval_multiplier), "incoming_damage_multiplier": float(field.incoming_damage_multiplier), "field_name": field.affliction}

static func stat_text(run: RefCounted) -> String:
	var stats: Dictionary = run.combat.stats
	return "生命 %d/%d  ·  普攻单枚 %.1f  ·  攻击间隔 %.2fs\n弹体 %d 枚  ·  额外贯穿 %d 次  ·  基础暴击 %.0f%%（双倍伤害）\n移速 %.0f  ·  技能冷却 %.1fs  ·  经验拾取范围 %.0f\n命中减速 %.0f%% / %.1fs  ·  爆炸伤害 %.0f%%  ·  精英/Boss增伤 %.0f%%" % [stats.hp, stats.max_hp, stats.damage, stats.attack_interval, stats.projectile_count, stats.pierce, float(stats.crit_chance) * 100, stats.move_speed, stats.skill_cooldown, stats.pickup_radius, float(stats.slow_fraction) * 100, stats.slow_duration, float(stats.blast_fraction) * 100, float(stats.elite_bonus) * 100]

static func field_text(run: RefCounted) -> String:
	var values = current(run)
	if str(values.field_name).is_empty():
		return "此处无场地加成。所有祝福可组合；只有新发起的攻击采用当前位置的场地效果。"
	return "%s：新攻击单枚 %.1f，暴击 %.0f%%，移速 %.0f，控制时长 ×%.2f。\n此处攻击间隔 %.2fs，承伤 ×%.2f；场地不会改写基础属性。" % [values.field_name, values.damage, float(values.crit) * 100, values.move_speed, values.control_multiplier, values.attack_interval, values.incoming_damage_multiplier]

static func blessings(upgrades: RefCounted, stacks: Dictionary) -> Array[String]:
	var rows: Array[String] = []
	for entry in upgrades.definitions:
		var count = int(stacks.get(entry.id, 0))
		if count > 0: rows.append("%s ×%d  ·  %s" % [entry.title, count, entry.description])
	if rows.is_empty(): rows.append("尚无祝福记录。击败敌人并拾取经验后，可在升级时选择成长。")
	return rows
