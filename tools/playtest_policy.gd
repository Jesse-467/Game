extends RefCounted
## Shared deterministic input policy for CPU and real-render playtests.
const World = preload("res://scripts/core/world_geometry.gd")
const STRATEGIES = {
	"volley": ["multishot", "pierce", "haste", "power", "vitality"],
	"control": ["frost", "blast", "cooldown", "power", "vitality"],
	"hunter": ["crit", "execution", "power", "haste", "vitality"]
}

static func upgrade(run: RefCounted, strategy: String) -> String:
	var best: String = run.selected_upgrades[0].id
	var best_rank = 1000
	for choice in run.selected_upgrades:
		var rank: int = STRATEGIES[strategy].find(choice.id)
		if choice.id.begins_with("train:"): rank = -3
		var preferred = {"hunter":["skill:judgment", "skill:glacial_lance", "skill:aimed_shot"], "control":["skill:aegis", "skill:blizzard", "skill:thorn_trap"], "volley":[]}
		if preferred[strategy].has(choice.id): rank = -4
		if run.combat.stats.hp < run.combat.stats.max_hp * 0.45 and choice.id in ["heal", "vitality"]: rank = -2
		if rank >= -4 and rank != -1 and rank < best_rank:
			best_rank = rank
			best = choice.id
	return best

static func equipment_score(item: Dictionary) -> float:
	var score = 0.0
	var weights = {"damage":4.0,"attack_rate":24.0,"max_hp":0.5,"armor":0.8,"move_speed":0.8,"crit_chance":100.0,"pickup_radius":0.2}
	for key in item.get("stats", {}): score += float(item.stats[key]) * float(weights.get(key, 0.0))
	return score

static func equipment_choice(run: RefCounted) -> bool:
	var item: Dictionary = run.pending_equipment
	return equipment_score(item) >= equipment_score(run.combat.equipment.equipped.get(item.slot, {}))

static func prepare(run: RefCounted, terrain_aware: bool = true) -> Vector2:
	var combat: RefCounted = run.combat
	var angle = run.director.elapsed * 0.60
	var destination = World.CENTER + Vector2(cos(angle) * 850, sin(angle) * 580)
	var nearest_gem = 320.0
	for gem in combat.gems:
		var distance: float = combat.player.distance_to(gem.pos)
		if distance < nearest_gem:
			nearest_gem = distance
			destination = gem.pos
	if run.director.is_boss_node():
		for enemy in combat.enemies:
			if enemy.kind == "boss":
				destination = enemy.pos + Vector2.from_angle(run.director.elapsed * 0.7) * 190.0
				break
	var movement: Vector2 = combat.player.direction_to(destination)
	for item in combat.loot:
		if item.kind == "health" and combat.stats.hp > combat.stats.max_hp * 0.75: continue
		if combat.player.distance_to(item.pos) < 260: movement = combat.player.direction_to(item.pos)
	var avoidance = Vector2.ZERO
	var nearby = 0
	for enemy in combat.enemies:
		var distance: float = combat.player.distance_to(enemy.pos)
		if distance < 170:
			avoidance += enemy.pos.direction_to(combat.player) * pow(1.0 - distance / 170.0, 2) * 3.0
			nearby += 1
	movement = (movement + avoidance).normalized()
	if terrain_aware and combat.field.phase in ["warning", "active"]:
		for zone in combat.field.zones:
			if combat.field.zone_definition(zone).kind != "debuff": continue
			var distance: float = combat.player.distance_to(zone.pos)
			if distance < float(zone.radius) + 45.0:
				var away: Vector2 = zone.pos.direction_to(combat.player)
				if away.length_squared() < 0.1: away = Vector2.DOWN
				movement = (movement + away * 2.5 * (1.0 - distance / (float(zone.radius) + 45.0))).normalized()
	movement = avoid_warnings(combat, movement)
	var urgent = false
	for enemy in combat.enemies:
		if enemy.telegraph > 0 and enemy.telegraph < 0.25:
			for shape in combat.attack_telegraph(enemy):
				if shape.kind in ["circle", "ring"] and preload("res://scripts/core/enemy_attack_patterns.gd").hits(shape, combat.player): urgent = true
	if urgent: run.dash(movement)
	var boss_in_range = combat.enemies.any(func(enemy): return enemy.kind == "boss" and enemy.pos.distance_to(combat.player) < 320)
	if nearby >= 2 or boss_in_range: run.cast_skill()
	for enemy in combat.enemies:
		if enemy.pos.distance_to(combat.player) < 55:
			run.dash()
			break
	return movement

static func avoid_warnings(combat: RefCounted, movement: Vector2) -> Vector2:
	var circles: Array[Dictionary] = []
	var rings: Array[Dictionary] = []
	var lines: Array[Dictionary] = []
	for enemy in combat.enemies:
		if enemy.telegraph <= 0: continue
		for shape in combat.attack_telegraph(enemy):
			if shape.kind == "circle": circles.append(shape)
			elif shape.kind == "ring": rings.append(shape)
			elif shape.kind == "line": lines.append(shape)
	for hazard in combat.hazards:
		if hazard.hostile: circles.append({"pos":hazard.pos,"radius":hazard.radius})
	for shot in combat.projectiles:
		if shot.hostile and shot.pos.distance_to(combat.player) < 220:
			lines.append({"pos":shot.pos,"end":shot.pos + shot.velocity * 0.35})
	for line in lines:
		var nearest = Geometry2D.get_closest_point_to_segment(combat.player, line.pos, line.end)
		if nearest.distance_to(combat.player) < 40:
			var direction: Vector2 = line.pos.direction_to(line.end)
			var side = Vector2(-direction.y, direction.x)
			if side.dot(movement) < 0: side = -side
			movement = side
	for ring in rings:
		var distance: float = combat.player.distance_to(ring.pos)
		if distance > float(ring.inner_radius) - 30 and distance < float(ring.radius) + 30:
			var direction: Vector2 = ring.pos.direction_to(combat.player)
			movement = -direction if distance - float(ring.inner_radius) < float(ring.radius) - distance else direction
	var inside_circle = false
	for circle in circles:
		if combat.player.distance_to(circle.pos) < float(circle.radius) + 30: inside_circle = true
	var contact_danger = combat.enemies.any(func(enemy): return enemy.hp > 0 and enemy.born <= 0 and enemy.pos.distance_to(combat.player) < float(enemy.radius) + 65)
	if inside_circle or contact_danger:
		var best_score = -INF
		for i in 16:
			var candidate = Vector2.from_angle(i * TAU / 16.0)
			var endpoint: Vector2 = combat.player + candidate * 125.0
			if not World.BOUNDS.grow(-World.PLAYER_MARGIN).has_point(endpoint): continue
			var margin = INF
			for circle in circles: margin = minf(margin, endpoint.distance_to(circle.pos) - float(circle.radius) - 20)
			for enemy in combat.enemies:
				if enemy.hp > 0 and enemy.born <= 0: margin = minf(margin, endpoint.distance_to(enemy.pos) - float(enemy.radius) - 25)
			var score = margin + candidate.dot(movement) * 8.0
			if score > best_score:
				best_score = score
				movement = candidate
	return movement
