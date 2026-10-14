extends RefCounted
## Deterministic combat simulation; no UI, device input or asset dependencies.

const World = preload("res://scripts/core/world_geometry.gd")
const Config = preload("res://scripts/core/gameplay_config.gd")
var CENTER = World.CENTER
var ARENA = World.BOUNDS
var MAX_PROJECTILES = int(Config.section("combat").max_projectiles)
var MAX_EFFECTS = int(Config.section("combat").max_effects)
var MAX_GEMS = int(Config.section("combat").max_gems)
const ArenaField = preload("res://scripts/core/arena_field.gd")
const EnemySpatialIndex = preload("res://scripts/core/enemy_spatial_index.gd")
const AttackPatterns = preload("res://scripts/core/enemy_attack_patterns.gd")
const SpawnSampler = preload("res://scripts/core/spawn_sampler.gd")
const StatPipeline = preload("res://scripts/core/stat_pipeline.gd")
const SkillBook = preload("res://scripts/core/skill_book.gd")
const Equipment = preload("res://scripts/core/equipment_inventory.gd")

var tuning = Config.section("combat")
var catalog: RefCounted
var director: RefCounted
var rng: RandomNumberGenerator
var stats: Dictionary = {}
var character_id = "knight"
var player = CENTER
var facing = Vector2.RIGHT
var enemies: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var gems: Array[Dictionary] = []
var effects: Array[Dictionary] = []
var events: Array[Dictionary] = []
var attack_timer = 0.0
var hurt_timer = 0.0
var dash_timer = 0.0
var dash_cooldown = 0.0
var skill_cooldown = 0.0
var next_enemy_id = 1
var damage_dealt = 0.0
var damage_taken = 0.0
var death_source = ""
var attack_animation_left = 0.0
var attack_serial = 0
var hurt_serial = 0
var attack_direction = Vector2.RIGHT
var field = ArenaField.new()
var terrain_damage_taken = 0.0
var enemy_index = EnemySpatialIndex.new()
var spawn_sampler = SpawnSampler.new()
var skills = SkillBook.new()
var equipment = Equipment.new()
var loot_rng = RandomNumberGenerator.new()
var loot: Array[Dictionary] = []
var hazards: Array[Dictionary] = []
var health_drop_left = float(tuning.health_drop_initial_delay)
var equipment_drop_left = float(tuning.gear_drop_initial_delay)
var health_drought = 0.0
var health_packs_used = 0
var healing_received = 0.0
var shield_hp = 0.0
var shield_left = 0.0
var next_loot_id = 1

func _init(content: RefCounted, pacing: RefCounted, random: RandomNumberGenerator) -> void:
	catalog = content
	director = pacing
	rng = random
	field.load_content()

func reset(id: String, camp_rank: int) -> void:
	character_id = id
	stats = StatPipeline.evaluate(catalog.character_stats(id, camp_rank), {}, {}, [])
	skills.reset(id, str(catalog.characters[id].skill))
	equipment.reset()
	loot_rng.seed = rng.seed ^ 0x36a972fb
	loot.clear()
	hazards.clear()
	health_drop_left = float(tuning.health_drop_initial_delay)
	equipment_drop_left = float(tuning.gear_drop_initial_delay)
	health_drought = 0.0
	health_packs_used = 0
	healing_received = 0.0
	shield_hp = 0.0
	shield_left = 0.0
	next_loot_id = 1
	player = CENTER
	facing = Vector2.RIGHT
	attack_timer = 0.0
	hurt_timer = 0.0
	dash_timer = 0.0
	dash_cooldown = 0.0
	skill_cooldown = 0.0
	next_enemy_id = 1
	damage_dealt = 0.0
	damage_taken = 0.0
	death_source = ""
	attack_animation_left = 0.0
	attack_serial = 0
	hurt_serial = 0
	attack_direction = Vector2.RIGHT
	terrain_damage_taken = 0.0
	field.reset(rng.seed)
	spawn_sampler.reset()
	enemies.clear()
	projectiles.clear()
	gems.clear()
	effects.clear()
	events.clear()

func step(delta: float, movement: Vector2, held_attack: bool) -> void:
	attack_timer = maxf(0, attack_timer - delta)
	hurt_timer = maxf(0, hurt_timer - delta)
	dash_cooldown = maxf(0, dash_cooldown - delta)
	skill_cooldown = maxf(0, skill_cooldown - delta)
	attack_animation_left = maxf(0, attack_animation_left - delta)
	health_drop_left = maxf(0, health_drop_left - delta)
	equipment_drop_left = maxf(0, equipment_drop_left - delta)
	health_drought += delta
	shield_left = maxf(0, shield_left - delta)
	if shield_left <= 0: shield_hp = 0.0
	var dashing = dash_timer > 0
	dash_timer = maxf(0, dash_timer - delta)
	movement = movement.limit_length()
	if movement.length() > float(tuning.player_facing_deadzone) and not dashing:
		facing = movement.normalized()
	var terrain = field.step(delta, player)
	player += (facing * float(catalog.balance.abilities.dash_speed) if dashing else movement * float(stats.move_speed) * float(terrain.move_multiplier)) * delta
	player = player.clamp(ARENA.position + Vector2.ONE * World.PLAYER_MARGIN, ARENA.end - Vector2.ONE * World.PLAYER_MARGIN)
	if terrain.damage_due > 0 and not field.modifiers_at(player).affliction.is_empty():
		if take_damage(terrain.damage_due, terrain.affliction):
			terrain_damage_taken += float(terrain.damage_due)
	if held_attack and attack_timer <= 0:
		attack()
	update_enemies(delta)
	update_projectiles(delta)
	update_gems(delta)
	update_hazards(delta)
	update_loot(delta)
	for i in range(effects.size() - 1, -1, -1):
		effects[i].life -= delta
		if effects[i].life <= 0:
			effects.remove_at(i)

func attack() -> void:
	attack_timer = float(stats.attack_interval) * float(field.modifiers_at(player).attack_interval_multiplier)
	attack_animation_left = float(tuning.attack_animation_seconds)
	attack_serial += 1
	var direction = aim_direction()
	var count = int(stats.projectile_count)
	attack_direction = direction
	for i in count:
		var angle = (float(i) - float(count - 1) / 2.0) * float(tuning.player_multishot_step)
		fire_player_shot(direction.rotated(angle), stats.damage)
	events.append({"type": "attack"})

func aim_direction() -> Vector2:
	var direction = facing
	var closest = float(tuning.aim_range)
	for enemy in enemies:
		var distance = player.distance_to(enemy.pos)
		if enemy.hp > 0 and distance < closest:
			closest = distance
			direction = player.direction_to(enemy.pos)
	return direction

func fire_player_shot(direction: Vector2, amount: float, extra: Dictionary = {}) -> void:
	if projectiles.size() >= MAX_PROJECTILES:
		return
	var terrain = field.modifiers_at(player)
	var scaled_damage = amount * float(terrain.outgoing_damage_multiplier)
	var crit_chance = clampf(float(stats.crit_chance) + float(terrain.crit_chance_delta), 0, 1)
	var shot = {"pos": player + direction * float(tuning.shot_offset), "velocity": direction * float(tuning.shot_speed), "life": float(tuning.shot_lifetime), "damage": scaled_damage, "crit_chance": crit_chance, "control_multiplier": terrain.control_duration_multiplier, "hostile": false, "pierce": int(stats.pierce), "hit_ids": [], "color": catalog.characters[character_id].color}
	shot.merge(extra, true)
	projectiles.append(shot)

func dash(direction: Vector2 = Vector2.ZERO) -> bool:
	if dash_cooldown > 0:
		return false
	if direction.length_squared() > 0.01:
		facing = direction.normalized()
	dash_cooldown = catalog.balance.abilities.dash_cooldown_seconds
	dash_timer = catalog.balance.abilities.dash_duration_seconds
	hurt_timer = maxf(hurt_timer, catalog.balance.abilities.dash_immunity_seconds)
	add_effect(player, 27, Color("b6dbff"), "dash", 0.24)
	events.append({"type": "dash"})
	return true

func cast_skill() -> bool:
	if skill_cooldown > 0:
		return false
	skill_cooldown = skills.cooldown(stats)
	attack_animation_left = float(tuning.attack_animation_seconds)
	attack_serial += 1
	var skill: Dictionary = skills.profile()
	var terrain = field.modifiers_at(player)
	var amount = float(stats.damage) * float(skill.damage)
	if skill.kind == "projectiles":
		attack_direction = aim_direction()
		for i in int(skill.count):
			var angle = 0.0 if int(skill.count) == 1 else (float(i) / float(skill.count - 1) - 0.5) * float(skill.spread)
			fire_player_shot(attack_direction.rotated(angle), amount, {"pierce": int(skill.pierce) + int(stats.pierce), "slow_fraction": skill.get("slow", 0.0), "slow_duration": skill.get("slow_duration", 0.0), "color": skill.color})
	elif skill.kind == "hazard":
		var target = player + aim_direction() * float(tuning.skill_target_offset)
		var closest = float(tuning.skill_target_range)
		for enemy in enemies:
			var distance: float = player.distance_to(enemy.pos)
			if enemy.hp > 0 and distance < closest:
				closest = distance
				target = enemy.pos
		add_hazard(target, skill, amount * float(terrain.outgoing_damage_multiplier), false, "", float(terrain.control_duration_multiplier))
	else:
		var radius = float(skill.radius)
		add_effect(player, radius, Color(skill.color), "nova", 0.45)
		if skill.kind == "shield":
			shield_hp = float(skill.shield)
			shield_left = float(skill.duration)
		for enemy in enemies:
			if player.distance_to(enemy.pos) <= radius + enemy.radius:
				damage_enemy(enemy, amount * float(terrain.outgoing_damage_multiplier), false, clampf(float(stats.crit_chance) + float(terrain.crit_chance_delta), 0, 1))
				enemy.pos += player.direction_to(enemy.pos) * (float(tuning.skill_knockback_boss if enemy.kind == "boss" else tuning.skill_knockback_normal))
				if skill.has("slow"):
					apply_slow(enemy, float(skill.slow), float(skill.slow_duration) * float(terrain.control_duration_multiplier))
	events.append({"type": "skill"})
	return true

func rebuild_equipment(upgrades: RefCounted) -> void:
	var hp = float(stats.hp)
	var level = int(stats.get("level", 1))
	stats = StatPipeline.evaluate(stats._base_stats, equipment.flat_stats(), upgrades.stacks, upgrades.definitions)
	stats.hp = minf(hp, stats.max_hp)
	stats.level = level

func spawn_enemy(id: String, explicit_position: Vector2 = Vector2.INF) -> void:
	if enemies.size() >= int(catalog.balance.difficulty.max_active_enemies):
		return
	var definition: Dictionary = catalog.enemies[id]
	var pos = explicit_position
	if pos == Vector2.INF:
		pos = spawn_sampler.sample(player, float(definition.radius), rng, enemies, catalog.balance.difficulty)
		if pos == Vector2.INF: return
	pos = pos.clamp(ARENA.position + Vector2.ONE * (float(definition.radius) + float(tuning.enemy_world_padding)), ARENA.end - Vector2.ONE * (float(definition.radius) + float(tuning.enemy_world_padding)))
	var enemy: Dictionary = director.enemy_stats(definition)
	enemy.merge({"uid": next_enemy_id, "id": id, "kind": definition.kind, "pos": pos, "hp": enemy.max_hp, "radius": float(definition.radius), "timer": rng.randf_range(float(tuning.enemy_timer_min), float(tuning.enemy_timer_max)), "telegraph": 0.0, "target": player, "charge_left": 0.0, "charge_direction": Vector2.ZERO, "attack_index": 0, "active_attack": {}, "slow": 0.0, "slow_timer": 0.0, "hit_flash": 0.0, "hit_serial": 0, "born": float(tuning.arrival_seconds)}, true)
	enemies.append(enemy)
	next_enemy_id += 1

func update_enemies(delta: float) -> void:
	# Deaths are removed before iteration; their events are handled by the session.
	for i in range(enemies.size() - 1, -1, -1):
		if enemies[i].hp <= 0:
			var enemy = enemies[i]
			var definition: Dictionary = catalog.enemies[enemy.id]
			add_gem(enemy.pos, int(definition.xp))
			roll_loot(enemy)
			add_effect(enemy.pos, enemy.radius * 1.7, Color("d8e7bd"), "death", 0.25)
			events.append({"type": "kill", "id": enemy.id, "kind": enemy.kind})
			enemies.remove_at(i)
	var summons: Array[Dictionary] = []
	for enemy in enemies:
		var definition: Dictionary = catalog.enemies[enemy.id]
		enemy.hit_flash = maxf(0, enemy.hit_flash - delta)
		enemy.slow_timer = maxf(0, enemy.slow_timer - delta)
		if enemy.born > 0:
			enemy.born = maxf(0, enemy.born - delta)
			continue
		if enemy.charge_left > 0:
			enemy.pos += enemy.charge_direction * float(enemy.get("charge_speed", enemy.active_attack.get("speed", 0))) * delta
			enemy.charge_left -= delta
		elif enemy.telegraph > 0:
			enemy.telegraph -= delta
			if enemy.telegraph <= 0:
				resolve_attack(enemy, summons)
		else:
			var boss_phase: Dictionary = {}
			if definition.behavior == "boss":
				boss_phase = AttackPatterns.boss_phase(definition, float(enemy.hp) / float(enemy.max_hp), director.boss_rotation_index())
				if enemy.get("phase_id", "opening") != boss_phase.id:
					enemy.phase_id = boss_phase.id
					enemy.attack_index = 0
					enemy.timer = maxf(enemy.timer, float(tuning.phase_grace_seconds))
					events.append({"type": "boss_phase", "name": definition.name, "phase": boss_phase.name, "phase_id": boss_phase.id})
			var direction: Vector2 = enemy.pos.direction_to(player)
			var distance: float = enemy.pos.distance_to(player)
			if definition.behavior == "flank":
				var offset = Vector2(-direction.y, direction.x) * sin(director.elapsed * float(tuning.flank_angular_speed) + float(enemy.uid)) * float(tuning.flank_radius)
				direction = enemy.pos.direction_to(player + offset)
			if definition.behavior == "ranged":
				if distance < float(tuning.ranged_retreat_distance): direction = -direction
				elif distance < float(tuning.ranged_hold_distance): direction = Vector2.ZERO
			var slow_scale = 1.0 - (float(enemy.slow) * (1.0 - float(enemy.get("slow_resistance", 0))) if enemy.slow_timer > 0 else 0.0)
			enemy.pos += direction * float(enemy.speed) * slow_scale * delta
			enemy.timer -= delta
			if enemy.timer <= 0 and definition.behavior != "chase" and (definition.behavior == "boss" or distance <= float(definition.attack.range)):
				var actions: Array = boss_phase.get("attacks", [])
				var action: Dictionary = actions[int(enemy.attack_index) % actions.size()] if definition.behavior == "boss" else definition.attack
				enemy.active_attack = action
				enemy.target = player
				enemy.telegraph_shapes = AttackPatterns.telegraph(enemy.pos, player, action)
				enemy.telegraph = float(action.warning)
				enemy.timer = float(action.interval) / (1.0 + float(enemy.get("attack_speed_bonus", 0)))
				enemy.attack_index += 1
		enemy.pos = enemy.pos.clamp(ARENA.position + Vector2.ONE * (float(enemy.radius) + float(tuning.enemy_world_padding)), ARENA.end - Vector2.ONE * (float(enemy.radius) + float(tuning.enemy_world_padding)))
		if player.distance_to(enemy.pos) < enemy.radius + float(tuning.player_body_radius):
			var amount = float(enemy.get("charge_damage", enemy.active_attack.get("damage", definition.damage))) * float(enemy.get("damage_scale", director.damage_multiplier())) if enemy.charge_left > 0 else float(enemy.get("damage", definition.damage * director.damage_multiplier()))
			take_damage(amount, definition.name)
	for summon in summons:
		spawn_enemy(summon.id, summon.pos)

func resolve_attack(enemy: Dictionary, summons: Array[Dictionary]) -> void:
	var action: Dictionary = enemy.active_attack
	var definition: Dictionary = catalog.enemies[enemy.id]
	if action.type == "combo":
		for i in action.attacks.size():
			var child = enemy.duplicate(true)
			child.active_attack = action.attacks[i]
			child.telegraph_shapes = []
			for shape in attack_telegraph(enemy):
				if int(shape.get("part_index", -1)) == i: child.telegraph_shapes.append(shape)
			resolve_attack(child, summons)
			if child.charge_left > enemy.charge_left:
				for key in ["charge_left", "charge_speed", "charge_damage", "charge_direction"]: enemy[key] = child[key]
		return
	match action.type:
		"slam", "shockwave":
			for shape in attack_telegraph(enemy):
				if shape.kind == "ring":
					if effects.size() < MAX_EFFECTS:
						effects.append({"pos": shape.pos, "radius": shape.radius, "inner_radius": shape.inner_radius, "color": Color("ff926c"), "kind": "ring", "life": 0.35})
				else:
					add_effect(shape.pos, shape.radius, Color("ff926c"), "nova", 0.35)
				if AttackPatterns.hits(shape, player):
					take_damage(float(action.damage) * float(enemy.get("damage_scale", director.damage_multiplier())), definition.name + " · " + ("震波" if action.type == "shockwave" else "重击"))
		"charge":
			enemy.charge_direction = enemy.pos.direction_to(enemy.target)
			enemy.charge_left = float(action.duration)
			enemy.charge_speed = float(action.speed)
			enemy.charge_damage = float(action.get("damage", definition.damage))
		"leap":
			enemy.pos = enemy.target.clamp(ARENA.position + Vector2.ONE * float(tuning.leap_world_margin), ARENA.end - Vector2.ONE * float(tuning.leap_world_margin))
			add_effect(enemy.pos, float(action.radius), Color("f6ab80"), "nova", 0.3)
			if AttackPatterns.hits({"kind":"circle", "pos":enemy.pos, "radius":action.radius}, player): take_damage(float(action.damage) * float(enemy.get("damage_scale", director.damage_multiplier())), definition.name + " · 跳扑")
		"hazard":
			add_hazard(enemy.target, action, float(action.damage) * float(enemy.get("damage_scale", director.damage_multiplier())), true, definition.name + " · 危险区域")
		"bolt", "fan", "radial_burst":
			for shape in attack_telegraph(enemy):
				if projectiles.size() >= MAX_PROJECTILES: break
				projectiles.append({"pos": shape.pos, "velocity": shape.pos.direction_to(shape.end) * float(action.speed), "life": float(tuning.hostile_shot_lifetime), "damage": float(action.get("damage", definition.damage)) * float(enemy.get("damage_scale", director.damage_multiplier())), "hostile": true, "source": definition.name})
		"summon":
			for shape in attack_telegraph(enemy):
				summons.append({"id": action.enemy_id, "pos": shape.pos})

func attack_telegraph(enemy: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if enemy.has("telegraph_shapes"):
		result.assign(enemy.telegraph_shapes)
	else:
		# Existing v1 checkpoints may contain a pending attack from before shape plans.
		result = AttackPatterns.telegraph(enemy.pos, enemy.target, enemy.active_attack)
	return result

func take_damage(amount: float, source: String = "接触伤害") -> bool:
	if hurt_timer > 0 or stats.hp <= 0:
		return false
	amount *= float(field.modifiers_at(player).incoming_damage_multiplier) * StatPipeline.armor_multiplier(float(stats.get("armor", 0)))
	var absorbed = minf(shield_hp, amount)
	shield_hp -= absorbed
	amount -= absorbed
	stats.hp = maxf(0, stats.hp - amount)
	hurt_timer = catalog.balance.player.hurt_invulnerability_seconds
	damage_taken += amount
	death_source = source
	hurt_serial += 1
	events.append({"type": "hurt", "amount": amount})
	return true

func damage_enemy(enemy: Dictionary, amount: float, on_hit: bool = true, crit_chance: float = -1.0, control_multiplier: float = 1.0) -> void:
	if enemy.hp <= 0:
		return
	var source_amount = amount
	if enemy.kind != "normal":
		amount *= 1.0 + float(stats.elite_bonus)
	amount *= StatPipeline.armor_multiplier(float(enemy.get("defense", 0)))
	var effective_crit = clampf((float(stats.crit_chance) if crit_chance < 0 else crit_chance) - float(enemy.get("crit_resistance", 0)), 0, 1)
	var critical = rng.randf() < effective_crit
	if critical:
		amount *= float(Config.section("stat_rules").critical_damage_multiplier)
	damage_dealt += minf(enemy.hp, amount)
	enemy.hp -= amount
	enemy.hit_flash = 0.34
	enemy.hit_serial += 1
	if on_hit:
		apply_slow(enemy, stats.slow_fraction, float(stats.slow_duration) * control_multiplier)
		if stats.blast_fraction > 0:
			add_effect(enemy.pos, float(tuning.blast_radius), Color("f5b678"), "blast", 0.18)
			for other in enemies:
				if other.uid != enemy.uid and other.hp > 0 and other.pos.distance_to(enemy.pos) < float(tuning.blast_radius) + other.radius:
					var splash = source_amount * float(stats.blast_fraction)
					if other.kind != "normal": splash *= 1.0 + float(stats.elite_bonus)
					if bool(tuning.blast_inherits_critical) and critical: splash *= float(Config.section("stat_rules").critical_damage_multiplier)
					splash *= StatPipeline.armor_multiplier(float(other.get("defense", 0)))
					damage_dealt += minf(other.hp, splash)
					other.hp -= splash
	if effects.size() < MAX_EFFECTS:
		effects.append({"pos": enemy.pos + Vector2(0, -25), "radius": 0, "life": 0.65, "color": Color("ffe49a") if critical else Color("fff4da"), "kind": "text", "text": str(roundi(amount)) + ("!" if critical else "")})

func apply_slow(enemy: Dictionary, fraction: float, duration: float) -> void:
	if fraction <= 0 or duration <= 0:
		return
	if enemy.slow_timer > 0 and fraction < float(enemy.slow):
		return
	var same_strength = is_equal_approx(fraction, float(enemy.slow))
	enemy.slow = fraction
	enemy.slow_timer = maxf(enemy.slow_timer, duration) if same_strength else duration

func update_projectiles(delta: float) -> void:
	enemy_index.rebuild(enemies)
	for i in range(projectiles.size() - 1, -1, -1):
		var shot = projectiles[i]
		var previous: Vector2 = shot.pos
		shot.pos += shot.velocity * delta
		shot.life -= delta
		if shot.hostile:
			if player.distance_to(Geometry2D.get_closest_point_to_segment(player, previous, shot.pos)) < float(tuning.hostile_hit_radius):
				take_damage(shot.damage, shot.source)
				shot.life = 0.0
		else:
			for enemy_id in enemy_index.query_segment(previous, shot.pos):
				var enemy = enemies[enemy_id]
				if enemy.hp <= 0 or shot.hit_ids.has(enemy.uid):
					continue
				if enemy.pos.distance_to(Geometry2D.get_closest_point_to_segment(enemy.pos, previous, shot.pos)) < enemy.radius + float(tuning.projectile_hit_radius):
					damage_enemy(enemy, shot.damage, true, shot.get("crit_chance", -1.0), shot.get("control_multiplier", 1.0))
					if float(shot.get("slow_fraction", 0)) > 0: apply_slow(enemy, float(shot.slow_fraction), float(shot.slow_duration) * float(shot.get("control_multiplier", 1.0)))
					shot.hit_ids.append(enemy.uid)
					if shot.pierce <= 0:
						shot.life = 0.0
						break
					shot.pierce -= 1
		if shot.life <= 0:
			projectiles.remove_at(i)

func add_gem(pos: Vector2, value: int) -> void:
	if gems.size() < MAX_GEMS:
		gems.append({"pos": pos, "value": value})
	else:
		var nearest = 0
		var distance = INF
		for i in gems.size():
			var candidate: float = pos.distance_squared_to(gems[i].pos)
			if candidate < distance:
				distance = candidate
				nearest = i
		gems[nearest].value += value

func update_gems(delta: float) -> void:
	for i in range(gems.size() - 1, -1, -1):
		var gem = gems[i]
		if player.distance_to(gem.pos) < float(stats.pickup_radius):
			gem.pos = gem.pos.move_toward(player, float(tuning.gem_homing_speed) * delta)
		if player.distance_to(gem.pos) < float(tuning.gem_collect_distance):
			events.append({"type": "xp", "value": gem.value})
			gems.remove_at(i)

func add_effect(pos: Vector2, radius: float, color: Color, kind: String, life: float) -> void:
	if effects.size() < MAX_EFFECTS:
		effects.append({"pos": pos, "radius": radius, "life": life, "color": color, "kind": kind})

func roll_loot(enemy: Dictionary) -> void:
	var data: Dictionary = catalog.balance.loot
	var health_count = 0
	var gear_count = 0
	for item in loot:
		if item.kind == "health": health_count += 1
		else: gear_count += 1
	var boss: bool = enemy.kind == "boss"
	var health_chance = float(data.health_elite_chance if enemy.kind == "elite" else data.health_chance)
	var pity: bool = health_drought >= float(data.health_pity_seconds) and stats.hp < stats.max_hp * float(tuning.health_pity_hp_fraction)
	if health_count < int(data.max_health_packs) and health_drop_left <= 0 and (boss or pity or loot_rng.randf() < health_chance):
		loot.append({"uid":next_loot_id, "kind":"health", "pos":enemy.pos + Vector2(-15, 0), "life":float(data.health_lifetime)})
		next_loot_id += 1
		health_drop_left = float(data.health_drop_cooldown)
		health_drought = 0.0
	var gear_chance = float(data.gear_elite_chance if enemy.kind == "elite" else data.gear_chance)
	if gear_count < int(data.max_ground_equipment) and (boss or equipment_drop_left <= 0) and (boss or loot_rng.randf() < gear_chance):
		var item = equipment.roll(character_id, director.node_index, loot_rng, boss)
		if not item.is_empty():
			loot.append({"uid":next_loot_id, "kind":"equipment", "item":item, "pos":enemy.pos + Vector2(20, 0), "life":float(data.gear_lifetime)})
			next_loot_id += 1
			equipment_drop_left = float(data.gear_drop_cooldown)

func update_loot(delta: float) -> void:
	for i in range(loot.size() - 1, -1, -1):
		var item = loot[i]
		item.life -= delta
		if item.life <= 0:
			loot.remove_at(i)
			continue
		if stats.hp <= 0 or player.distance_to(item.pos) >= float(tuning.loot_collect_distance): continue
		if item.kind == "health":
			if stats.hp >= stats.max_hp: continue
			var amount = minf(stats.max_hp - stats.hp, float(catalog.balance.loot.health_flat) + stats.max_hp * float(catalog.balance.loot.health_fraction))
			stats.hp += amount
			health_packs_used += 1
			healing_received += amount
			events.append({"type":"healed", "amount":amount})
		else: events.append({"type":"equipment_found", "item":item.item})
		loot.remove_at(i)
		# At most one gear decision per simulation tick.
		if item.kind == "equipment": break

func add_hazard(pos: Vector2, action: Dictionary, damage: float, hostile: bool, source: String = "", control: float = 1.0) -> void:
	if hazards.size() >= int(tuning.max_hazards): return
	hazards.append({"pos":pos, "radius":float(action.radius), "life":float(action.duration), "tick":float(action.tick), "timer":float(action.tick), "damage":damage, "hostile":hostile, "source":source, "color":str(action.get("color", "e77f65")), "slow":float(action.get("slow", 0)), "slow_duration":float(action.get("slow_duration", 0)) * control, "crit_chance":clampf(float(stats.crit_chance) + float(field.modifiers_at(player).crit_chance_delta), 0, 1)})

func update_hazards(delta: float) -> void:
	for i in range(hazards.size() - 1, -1, -1):
		var hazard = hazards[i]
		hazard.life -= delta
		hazard.timer -= delta
		if hazard.life <= 0:
			hazards.remove_at(i)
			continue
		if hazard.timer > 0: continue
		hazard.timer += hazard.tick
		if hazard.hostile:
			if player.distance_to(hazard.pos) < hazard.radius + float(tuning.player_body_radius): take_damage(hazard.damage, hazard.source)
		else:
			for enemy in enemies:
				if enemy.hp > 0 and enemy.pos.distance_to(hazard.pos) < hazard.radius + enemy.radius:
					damage_enemy(enemy, hazard.damage, false, hazard.crit_chance)
					apply_slow(enemy, hazard.slow, hazard.slow_duration)
