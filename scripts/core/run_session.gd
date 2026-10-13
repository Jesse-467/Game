extends RefCounted
## Run lifecycle and growth rules. Owns simulation services, emits presentation events.

const Director = preload("res://scripts/core/run_director.gd")
const Combat = preload("res://scripts/core/combat_system.gd")
const Upgrades = preload("res://scripts/core/upgrade_catalog.gd")
const Snapshot = preload("res://scripts/core/run_snapshot.gd")
var catalog: RefCounted
var director: RefCounted
var combat: RefCounted
var upgrades = Upgrades.new()
var rng = RandomNumberGenerator.new()
var state = "menu"
var level = 1
var xp = 0
var kills = 0
var selected_upgrades: Array[Dictionary] = []
var events: Array[Dictionary] = []
var minute_records: Array[Dictionary] = []
var recorded_minute = -1
var reward_paid = false
var run_id = ""

func _init(content: RefCounted) -> void:
	catalog = content
	director = Director.new(content)
	combat = Combat.new(content, director, rng)
	upgrades.load_content()

func start(character: String, camp_rank: int, seed_value: int = -1) -> void:
	run_id = Crypto.new().generate_random_bytes(16).hex_encode()
	if seed_value < 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	director.reset()
	combat.reset(character, camp_rank)
	upgrades.reset_run()
	level = 1
	xp = 0
	kills = 0
	selected_upgrades.clear()
	minute_records.clear()
	events.clear()
	recorded_minute = -1
	reward_paid = false
	state = "playing"
	events.append({"type": "started"})

func step(delta: float, movement: Vector2, held_attack: bool) -> void:
	if state != "playing":
		return
	if director.tick(delta):
		advance_node()
	if director.is_boss_node() and not combat.enemies.any(func(enemy): return enemy.kind == "boss"):
		combat.spawn_enemy(director.current_boss_id())
	if director.spawn_timer <= 0 and combat.enemies.size() < int(catalog.balance.difficulty.max_active_enemies):
		combat.spawn_enemy(director.consume_spawn(rng))
	combat.step(delta, movement, held_attack)
	consume_combat_events()
	if combat.stats.hp <= 0:
		finish()
	elif xp >= xp_required():
		begin_level_up()
	var minute = int(director.elapsed / 60)
	if minute > recorded_minute:
		recorded_minute = minute
		minute_records.append({"minute": minute, "level": level, "node": director.node_index, "kills": kills, "damage_dealt": combat.damage_dealt, "damage_taken": combat.damage_taken, "enemies": combat.enemies.size(), "projectiles": combat.projectiles.size()})

func consume_combat_events() -> void:
	for event in combat.events:
		match event.type:
			"kill":
				kills += 1
				if event.kind == "boss":
					director.bosses_defeated += 1
					# Reward pickup is guaranteed before transition, even when player is far away.
					for gem in combat.gems:
						xp += gem.value
					combat.gems.clear()
					if combat.stats.hp > 0:
						advance_node()
			"xp": xp += int(event.value)
		events.append(event)
	combat.events.clear()

func advance_node() -> void:
	var boss = director.advance()
	combat.field.configure_node(director.node_index)
	if combat.stats.hp > 0:
		combat.stats.hp = minf(combat.stats.max_hp, combat.stats.hp + combat.stats.max_hp * float(catalog.balance.difficulty.node_heal_fraction))
	if not boss.is_empty():
		# Release a slot so a saturated wave cannot prevent mandatory boss creation.
		if combat.enemies.size() >= int(catalog.balance.difficulty.max_active_enemies):
			var removed = combat.enemies.pop_front()
			combat.add_gem(removed.pos, int(catalog.enemies[removed.id].xp))
		combat.spawn_enemy(boss)
	events.append({"type": "node", "index": director.node_index, "boss": boss})

func xp_required() -> int:
	var n = float(level - 1)
	var data: Dictionary = catalog.balance.experience
	return roundi(data.base + data.linear_per_level * n + data.power_coefficient * pow(n, data.power_exponent))

func begin_level_up() -> void:
	if state != "playing" or xp < xp_required():
		return
	xp -= xp_required()
	level += 1
	combat.stats.level = level
	selected_upgrades = upgrades.generate_offers(rng, combat.stats)
	state = "upgrade"
	events.append({"type": "upgrade", "level": level})

func apply_upgrade(id: String) -> bool:
	if state != "upgrade":
		return false
	var offered = false
	for choice in selected_upgrades:
		if choice.id == id:
			offered = true
	if not offered:
		return false
	combat.stats = upgrades.apply(id, combat.stats)
	selected_upgrades.clear()
	state = "playing"
	events.append({"type": "chosen", "id": id})
	if xp >= xp_required():
		begin_level_up()
	return true

func dash(direction: Vector2 = Vector2.ZERO) -> bool:
	return state == "playing" and combat.dash(direction)

func cast_skill() -> bool:
	return state == "playing" and combat.cast_skill()

func pause() -> void:
	if state == "playing":
		state = "paused"
		events.append({"type": "paused"})

func resume() -> void:
	if state == "paused":
		state = "playing"
		events.append({"type": "resumed"})

func finish() -> void:
	if state == "dead":
		return
	state = "dead"
	events.append({"type": "dead", "result": result()})

func result() -> Dictionary:
	return {"run_id": run_id, "state": state, "seconds": director.elapsed, "node": director.node_index, "level": level, "kills": kills, "bosses": director.bosses_defeated, "crystals": int(kills / 10) + director.bosses_defeated * 5, "character": combat.character_id, "death_source": combat.death_source if state == "dead" else "", "terrain_damage_taken": combat.terrain_damage_taken, "build": upgrades.stacks.duplicate(), "minutes": minute_records.duplicate(true)}

func checkpoint() -> Dictionary:
	return Snapshot.capture(self)

func restore_checkpoint(document: Dictionary) -> bool:
	return Snapshot.restore(self, document)
