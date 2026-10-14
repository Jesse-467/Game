extends RefCounted
## Explicit simulation state boundary; presentation resources and input are excluded.

const VERSION = 3
const LEGACY_SESSION_FIELDS = ["run_id", "level", "xp", "kills", "minute_records", "recorded_minute", "reward_paid"]
const SESSION_FIELDS = LEGACY_SESSION_FIELDS + ["pending_equipment"]
const DIRECTOR_FIELDS = ["elapsed", "node_time", "node_index", "bosses_defeated", "spawn_timer"]
const LEGACY_COMBAT_FIELDS = ["stats", "character_id", "player", "facing", "enemies", "projectiles", "gems", "effects", "attack_timer", "hurt_timer", "dash_timer", "dash_cooldown", "skill_cooldown", "next_enemy_id", "damage_dealt", "damage_taken", "death_source", "attack_animation_left", "attack_serial", "hurt_serial", "attack_direction", "terrain_damage_taken"]
const COMBAT_FIELDS = LEGACY_COMBAT_FIELDS + ["loot", "hazards", "health_drop_left", "equipment_drop_left", "health_drought", "health_packs_used", "healing_received", "shield_hp", "shield_left", "next_loot_id"]
const LEGACY_FIELD_FIELDS = ["zones", "definition", "phase", "phase_left", "node_index", "burn_exposure"]
const V2_FIELD_FIELDS = LEGACY_FIELD_FIELDS + ["next_definition", "type_bag", "spatial_bag", "last_type", "last_cell", "cycle_count"]
const FIELD_FIELDS = V2_FIELD_FIELDS + ["next_types"]
const SPAWN_FIELDS = ["bag", "last_sector"]
const SKILL_FIELDS = ["active_id", "ranks", "character_id"]
const EQUIPMENT_FIELDS = ["equipped", "unlocked"]

static func capture_properties(object: Object, fields: Array) -> Dictionary:
	var result: Dictionary = {}
	for key in fields:
		var value = object.get(key)
		result[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	return result

static func restore_properties(object: Object, values: Dictionary, fields: Array) -> void:
	for key in fields:
		var current = object.get(key)
		if current is Array:
			current.assign(values[key])
		else:
			object.set(key, values[key])

static func capture(run: RefCounted) -> Dictionary:
	var offers: Array[String] = []
	for choice in run.selected_upgrades: offers.append(choice.id)
	return {"schema_version": VERSION, "state": run.state, "session": capture_properties(run, SESSION_FIELDS), "director": capture_properties(run.director, DIRECTOR_FIELDS), "combat": capture_properties(run.combat, COMBAT_FIELDS), "field": capture_properties(run.combat.field, FIELD_FIELDS), "spawn_sampler": capture_properties(run.combat.spawn_sampler, SPAWN_FIELDS), "skills":capture_properties(run.combat.skills, SKILL_FIELDS), "equipment":capture_properties(run.combat.equipment, EQUIPMENT_FIELDS), "loot_rng_seed":run.combat.loot_rng.seed, "loot_rng_state":run.combat.loot_rng.state, "rng_seed": run.rng.seed, "rng_state": run.rng.state, "field_rng_seed": run.combat.field.rng.seed, "field_rng_state": run.combat.field.rng.state, "upgrade_stacks": run.upgrades.stacks.duplicate(true), "offers": offers}

static func has_fields(values: Variant, fields: Array) -> bool:
	if not values is Dictionary: return false
	for key in fields:
		if not values.has(key): return false
	return true

static func valid_structure(document: Dictionary) -> bool:
	var version = int(document.get("schema_version", 0))
	if version not in [1, 2, VERSION] or document.get("state", "") not in ["playing", "paused", "upgrade", "equipment"]: return false
	if not has_fields(document, ["session", "director", "combat", "field", "rng_seed", "rng_state", "field_rng_seed", "field_rng_state", "upgrade_stacks", "offers"]): return false
	if not has_fields(document.get("session"), SESSION_FIELDS if version == VERSION else LEGACY_SESSION_FIELDS) or not has_fields(document.get("director"), DIRECTOR_FIELDS) or not has_fields(document.get("combat"), COMBAT_FIELDS if version == VERSION else LEGACY_COMBAT_FIELDS) or not has_fields(document.get("field"), LEGACY_FIELD_FIELDS if version == 1 else (V2_FIELD_FIELDS if version == 2 else FIELD_FIELDS)): return false
	if version >= 2 and not has_fields(document.get("spawn_sampler"), SPAWN_FIELDS): return false
	if version == VERSION and (not has_fields(document.get("skills"), SKILL_FIELDS) or not has_fields(document.get("equipment"), EQUIPMENT_FIELDS) or not has_fields(document, ["loot_rng_seed", "loot_rng_state"])): return false
	if not document.combat.stats is Dictionary or not document.combat.stats.has("hp") or not document.session.run_id is String or document.session.run_id.is_empty(): return false
	return document.combat.stats.hp > 0 and not document.session.reward_paid and document.offers is Array and document.upgrade_stacks is Dictionary

static func normalize(document: Dictionary) -> Dictionary:
	if not valid_structure(document): return {}
	if int(document.schema_version) == VERSION: return document
	var result = document.duplicate(true)
	if int(result.schema_version) == 1:
		var shift = preload("res://scripts/core/world_geometry.gd").CENTER - Vector2(640, 335)
		result.combat.player += shift
		for list in ["enemies", "projectiles", "gems", "effects"]:
			for entity in result.combat[list]:
				for key in ["pos", "target"]:
					if entity.has(key): entity[key] += shift
				for shape in entity.get("telegraph_shapes", []):
					for key in ["pos", "end"]:
						if shape.has(key): shape[key] += shift
		for zone in result.field.zones: zone.pos += shift
		result.field.merge({"next_definition": {}, "type_bag": [], "spatial_bag": [], "last_type": str(result.field.definition.get("id", "")), "last_cell": -1, "cycle_count": 0})
		result.spawn_sampler = {"bag": [], "last_sector": -1}
	result.field.next_types = []
	result.session.pending_equipment = {}
	var tuning = preload("res://scripts/core/gameplay_config.gd").section("combat")
	result.combat.merge({"loot":[], "hazards":[], "health_drop_left":float(tuning.health_drop_initial_delay), "equipment_drop_left":float(tuning.gear_drop_initial_delay), "health_drought":0.0, "health_packs_used":0, "healing_received":0.0, "shield_hp":0.0, "shield_left":0.0, "next_loot_id":1})
	var catalog = preload("res://scripts/core/content_catalog.gd").new()
	catalog.load_content()
	var character: String = result.combat.character_id
	if not catalog.characters.has(character): return {}
	var director = preload("res://scripts/core/run_director.gd").new(catalog)
	restore_properties(director, result.director, DIRECTOR_FIELDS)
	for enemy in result.combat.enemies:
		if not catalog.enemies.has(enemy.id): return {}
		var hp_fraction = clampf(float(enemy.hp) / float(enemy.max_hp), 0, 1)
		var updated: Dictionary = director.enemy_stats(catalog.enemies[enemy.id])
		enemy.merge(updated, true)
		enemy.hp = float(enemy.max_hp) * hp_fraction
	var base_hp = float(catalog.balance.player.max_hp) * float(catalog.characters[character].hp_multiplier)
	var old_growth = float(result.upgrade_stacks.get("vitality", 0)) * 20.0 + float(result.upgrade_stacks.get("endurance", 0)) * 8.0
	var camp_rank = clampi(roundi(((float(result.combat.stats.max_hp) - old_growth) / base_hp - 1.0) / 0.02), 0, 10)
	var upgrades = preload("res://scripts/core/upgrade_catalog.gd").new()
	upgrades.load_content()
	var old_hp = float(result.combat.stats.hp)
	result.combat.stats = preload("res://scripts/core/stat_pipeline.gd").evaluate(catalog.character_stats(character, camp_rank), {}, result.upgrade_stacks, upgrades.definitions)
	result.combat.stats.hp = minf(old_hp, result.combat.stats.max_hp)
	result.combat.stats.level = result.session.level
	var skill: String = catalog.characters[character].skill
	result.skills = {"active_id":skill, "ranks":{skill:1}, "character_id":character}
	result.equipment = {"equipped":{}, "unlocked":preload("res://scripts/core/equipment_inventory.gd").new().unlocked_for_bosses(0)}
	result.loot_rng_seed = result.rng_seed ^ 0x36a972fb
	var loot_rng = RandomNumberGenerator.new()
	loot_rng.seed = result.loot_rng_seed
	result.loot_rng_state = loot_rng.state
	result.schema_version = VERSION
	return result

static func restore(run: RefCounted, saved_document: Dictionary) -> bool:
	var document = normalize(saved_document)
	if not valid_structure(document) or not run.catalog.characters.has(document.combat.character_id): return false
	for enemy in document.combat.enemies:
		if not run.catalog.enemies.has(enemy.id): return false
	for id in document.upgrade_stacks:
		if run.upgrades.find_definition(id).is_empty(): return false
	var offers: Array[Dictionary] = []
	var skills = preload("res://scripts/core/skill_book.gd").new()
	restore_properties(skills, document.skills, SKILL_FIELDS)
	if not skills.definitions.has(skills.active_id) or skills.definitions[skills.active_id].character != document.combat.character_id: return false
	for id in document.offers:
		var definition = run.upgrades.find_definition(id)
		if definition.is_empty(): definition = skills.resolve_offer(id)
		if definition.is_empty(): return false
		offers.append(definition)
	if document.state == "upgrade" and offers.is_empty(): return false
	if document.state == "equipment" and document.session.pending_equipment.is_empty(): return false
	restore_properties(run, document.session, SESSION_FIELDS)
	restore_properties(run.director, document.director, DIRECTOR_FIELDS)
	restore_properties(run.combat, document.combat, COMBAT_FIELDS)
	restore_properties(run.combat.field, document.field, FIELD_FIELDS)
	restore_properties(run.combat.spawn_sampler, document.spawn_sampler, SPAWN_FIELDS)
	restore_properties(run.combat.skills, document.skills, SKILL_FIELDS)
	restore_properties(run.combat.equipment, document.equipment, EQUIPMENT_FIELDS)
	run.combat.loot_rng.seed = document.loot_rng_seed
	run.combat.loot_rng.state = document.loot_rng_state
	run.rng.seed = document.rng_seed
	run.rng.state = document.rng_state
	run.combat.field.rng.seed = document.field_rng_seed
	run.combat.field.rng.state = document.field_rng_state
	run.upgrades.stacks = document.upgrade_stacks.duplicate(true)
	run.selected_upgrades.assign(offers)
	run.events.clear()
	run.combat.events.clear()
	run.state = str(document.state) if document.state in ["upgrade", "equipment"] else "paused"
	return true
