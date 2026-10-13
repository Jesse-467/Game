extends RefCounted
## Deterministic combat simulation; no UI, device input or asset dependencies.

const World = preload("res://scripts/core/world_geometry.gd")
const CENTER = World.CENTER
const ARENA = World.BOUNDS
const MAX_PROJECTILES = 240
const MAX_EFFECTS = 128
const MAX_GEMS = 180
const ArenaField = preload("res://scripts/core/arena_field.gd")
const EnemySpatialIndex = preload("res://scripts/core/enemy_spatial_index.gd")
const AttackPatterns = preload("res://scripts/core/enemy_attack_patterns.gd")
const SpawnSampler = preload("res://scripts/core/spawn_sampler.gd")

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

func _init(content: RefCounted, pacing: RefCounted, random: RandomNumberGenerator) -> void:
	catalog = content
	director = pacing
	rng = random
	field.load_content()

func reset(id: String, camp_rank: int) -> void:
	character_id = id
	stats = catalog.character_stats(id, camp_rank)
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
	var dashing = dash_timer > 0
	dash_timer = maxf(0, dash_timer - delta)
	movement = movement.limit_length()
	if movement.length() > 0.1 and not dashing:
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
	for i in range(effects.size() - 1, -1, -1):
		effects[i].life -= delta
		if effects[i].life <= 0:
			effects.remove_at(i)

func attack() -> void:
	attack_timer = float(stats.attack_interval) * float(field.modifiers_at(player).attack_interval_multiplier)
	attack_animation_left = 0.34
	attack_serial += 1
	var direction = aim_direction()
	var count = int(stats.projectile_count)
	attack_direction = direction
	for i in count:
		var angle = (float(i) - float(count - 1) / 2.0) * 0.20
		fire_player_shot(direction.rotated(angle), stats.damage)
	events.append({"type": "attack"})

func aim_direction() -> Vector2:
	var direction = facing
	var closest = 600.0
	for enemy in enemies:
		var distance = player.distance_to(enemy.pos)
		if enemy.hp > 0 and distance < closest:
			closest = distance
			direction = player.direction_to(enemy.pos)
	return direction

func fire_player_shot(direction: Vector2, amount: float) -> void:
	if projectiles.size() >= MAX_PROJECTILES:
		return
	var terrain = field.modifiers_at(player)
	var scaled_damage = amount * float(terrain.outgoing_damage_multiplier)
	var crit_chance = clampf(float(stats.crit_chance) + float(terrain.crit_chance_delta), 0, 1)
	projectiles.append({"pos": player + direction * 22, "velocity": direction * 560, "life": 1.2, "damage": scaled_damage, "crit_chance": crit_chance, "control_multiplier": terrain.control_duration_multiplier, "hostile": false, "pierce": int(stats.pierce), "hit_ids": [], "color": catalog.characters[character_id].color})

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
	skill_cooldown = stats.skill_cooldown
	attack_animation_left = 0.34
	attack_serial += 1
	var skill: String = catalog.characters[character_id].skill
	var terrain = field.modifiers_at(player)
	if skill == "volley":
		attack_direction = aim_direction()
		for i in 9:
			fire_player_shot(attack_direction.rotated((i - 4) * 0.16), stats.damage * 1.6)
	else:
		var radius = float(catalog.balance.abilities.skill_radius)
		add_effect(player, radius, Color("87d8f3") if skill == "frost" else Color("f5ce73"), "nova", 0.45)
		for enemy in enemies:
			if player.distance_to(enemy.pos) <= radius + enemy.radius:
				damage_enemy(enemy, float(stats.damage) * float(catalog.balance.abilities.skill_damage_multiplier) * float(terrain.outgoing_damage_multiplier), false, clampf(float(stats.crit_chance) + float(terrain.crit_chance_delta), 0, 1))
				enemy.pos += player.direction_to(enemy.pos) * (12.0 if enemy.kind == "boss" else 30.0)
				if skill == "frost":
					apply_slow(enemy, 0.55, 3.0 * float(terrain.control_duration_multiplier))
	events.append({"type": "skill"})
	return true

func spawn_enemy(id: String, explicit_position: Vector2 = Vector2.INF) -> void:
	if enemies.size() >= int(catalog.balance.difficulty.max_active_enemies):
		return
	var definition: Dictionary = catalog.enemies[id]
	var pos = explicit_position
	if pos == Vector2.INF:
		pos = spawn_sampler.sample(player, float(definition.radius), rng, enemies, catalog.balance.difficulty)
		if pos == Vector2.INF: return
	pos = pos.clamp(ARENA.position + Vector2.ONE * (float(definition.radius) + 15), ARENA.end - Vector2.ONE * (float(definition.radius) + 15))
	var hp_scale = director.boss_health_multiplier() if definition.kind == "boss" else director.health_multiplier()
	var enemy_hp = float(definition.hp) * hp_scale
	enemies.append({"uid": next_enemy_id, "id": id, "kind": definition.kind, "pos": pos, "hp": enemy_hp, "max_hp": enemy_hp, "speed": float(definition.speed) * minf(catalog.balance.difficulty.speed_multiplier_cap, 1.0 + director.elapsed / 1800.0), "radius": float(definition.radius), "timer": 1.6 + rng.randf() * 0.8, "telegraph": 0.0, "target": player, "charge_left": 0.0, "charge_direction": Vector2.ZERO, "attack_index": 0, "active_attack": {}, "slow": 0.0, "slow_timer": 0.0, "hit_flash": 0.0, "hit_serial": 0, "born": 0.65})
	next_enemy_id += 1

func update_enemies(delta: float) -> void:
	# Deaths are removed before iteration; their events are handled by the session.
	for i in range(enemies.size() - 1, -1, -1):
		if enemies[i].hp <= 0:
			var enemy = enemies[i]
			var definition: Dictionary = catalog.enemies[enemy.id]
			add_gem(enemy.pos, int(definition.xp))
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
			enemy.pos += enemy.charge_direction * float(enemy.active_attack.speed) * delta
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
					enemy.timer = maxf(enemy.timer, 0.8)
					events.append({"type": "boss_phase", "name": definition.name, "phase": boss_phase.name, "phase_id": boss_phase.id})
			var direction: Vector2 = enemy.pos.direction_to(player)
			var distance: float = enemy.pos.distance_to(player)
			if definition.behavior == "ranged":
				if distance < 190: direction = -direction
				elif distance < 300: direction = Vector2.ZERO
			var slow_scale = 1.0 - (float(enemy.slow) * (0.45 if enemy.kind == "boss" else 1.0) if enemy.slow_timer > 0 else 0.0)
			enemy.pos += direction * float(enemy.speed) * slow_scale * delta
			enemy.timer -= delta
			if enemy.timer <= 0 and definition.behavior != "chase":
				var actions: Array = boss_phase.get("attacks", [])
				var action: Dictionary = actions[int(enemy.attack_index) % actions.size()] if definition.behavior == "boss" else definition.attack
				enemy.active_attack = action
				enemy.target = player
				enemy.telegraph_shapes = AttackPatterns.telegraph(enemy.pos, player, action)
				enemy.telegraph = float(action.warning)
				enemy.timer = float(action.interval)
				enemy.attack_index += 1
		enemy.pos = enemy.pos.clamp(ARENA.position + Vector2.ONE * (float(enemy.radius) + 15), ARENA.end - Vector2.ONE * (float(enemy.radius) + 15))
		if player.distance_to(enemy.pos) < enemy.radius + 15:
			var amount = float(enemy.active_attack.get("damage", definition.damage)) if enemy.charge_left > 0 else float(definition.damage)
			take_damage(amount * director.damage_multiplier(), definition.name)
	for summon in summons:
		spawn_enemy(summon.id, summon.pos)

func resolve_attack(enemy: Dictionary, summons: Array[Dictionary]) -> void:
	var action: Dictionary = enemy.active_attack
	var definition: Dictionary = catalog.enemies[enemy.id]
	match action.type:
		"slam", "shockwave":
			for shape in attack_telegraph(enemy):
				if shape.kind == "ring":
					if effects.size() < MAX_EFFECTS:
						effects.append({"pos": shape.pos, "radius": shape.radius, "inner_radius": shape.inner_radius, "color": Color("ff926c"), "kind": "ring", "life": 0.35})
				else:
					add_effect(shape.pos, shape.radius, Color("ff926c"), "nova", 0.35)
				if AttackPatterns.hits(shape, player):
					take_damage(float(action.damage) * director.damage_multiplier(), definition.name + " · " + ("震波" if action.type == "shockwave" else "重击"))
		"charge":
			enemy.charge_direction = enemy.pos.direction_to(enemy.target)
			enemy.charge_left = float(action.duration)
		"bolt", "fan", "radial_burst":
			for shape in attack_telegraph(enemy):
				if projectiles.size() >= MAX_PROJECTILES: break
				projectiles.append({"pos": shape.pos, "velocity": shape.pos.direction_to(shape.end) * float(action.speed), "life": 5.0, "damage": float(action.get("damage", definition.damage)) * director.damage_multiplier(), "hostile": true, "source": definition.name})
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
	amount *= float(field.modifiers_at(player).incoming_damage_multiplier)
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
	if enemy.kind != "normal":
		amount *= 1.0 + float(stats.elite_bonus)
	var critical = rng.randf() < (float(stats.crit_chance) if crit_chance < 0 else crit_chance)
	if critical:
		amount *= 2.0
	damage_dealt += minf(enemy.hp, amount)
	enemy.hp -= amount
	enemy.hit_flash = 0.34
	enemy.hit_serial += 1
	if on_hit:
		apply_slow(enemy, stats.slow_fraction, float(stats.slow_duration) * control_multiplier)
		if stats.blast_fraction > 0:
			add_effect(enemy.pos, 48, Color("f5b678"), "blast", 0.18)
			for other in enemies:
				if other.uid != enemy.uid and other.hp > 0 and other.pos.distance_to(enemy.pos) < 48 + other.radius:
					var splash = amount * float(stats.blast_fraction)
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
			if player.distance_to(Geometry2D.get_closest_point_to_segment(player, previous, shot.pos)) < 19:
				take_damage(shot.damage, shot.source)
				shot.life = 0.0
		else:
			for enemy_id in enemy_index.query_segment(previous, shot.pos):
				var enemy = enemies[enemy_id]
				if enemy.hp <= 0 or shot.hit_ids.has(enemy.uid):
					continue
				if enemy.pos.distance_to(Geometry2D.get_closest_point_to_segment(enemy.pos, previous, shot.pos)) < enemy.radius + 7:
					damage_enemy(enemy, shot.damage, true, shot.get("crit_chance", -1.0), shot.get("control_multiplier", 1.0))
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
			gem.pos = gem.pos.move_toward(player, 380.0 * delta)
		if player.distance_to(gem.pos) < 20:
			events.append({"type": "xp", "value": gem.value})
			gems.remove_at(i)

func add_effect(pos: Vector2, radius: float, color: Color, kind: String, life: float) -> void:
	if effects.size() < MAX_EFFECTS:
		effects.append({"pos": pos, "radius": radius, "life": life, "color": color, "kind": kind})
