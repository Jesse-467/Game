extends RefCounted
## Explicit simulation state boundary; presentation resources and input are excluded.

const VERSION = 2
const SESSION_FIELDS = ["run_id", "level", "xp", "kills", "minute_records", "recorded_minute", "reward_paid"]
const DIRECTOR_FIELDS = ["elapsed", "node_time", "node_index", "bosses_defeated", "spawn_timer"]
const COMBAT_FIELDS = ["stats", "character_id", "player", "facing", "enemies", "projectiles", "gems", "effects", "attack_timer", "hurt_timer", "dash_timer", "dash_cooldown", "skill_cooldown", "next_enemy_id", "damage_dealt", "damage_taken", "death_source", "attack_animation_left", "attack_serial", "hurt_serial", "attack_direction", "terrain_damage_taken"]
const LEGACY_FIELD_FIELDS = ["zones", "definition", "phase", "phase_left", "node_index", "burn_exposure"]
const FIELD_FIELDS = LEGACY_FIELD_FIELDS + ["next_definition", "type_bag", "spatial_bag", "last_type", "last_cell", "cycle_count"]
const SPAWN_FIELDS = ["bag", "last_sector"]

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
	return {"schema_version": VERSION, "state": run.state, "session": capture_properties(run, SESSION_FIELDS), "director": capture_properties(run.director, DIRECTOR_FIELDS), "combat": capture_properties(run.combat, COMBAT_FIELDS), "field": capture_properties(run.combat.field, FIELD_FIELDS), "spawn_sampler": capture_properties(run.combat.spawn_sampler, SPAWN_FIELDS), "rng_seed": run.rng.seed, "rng_state": run.rng.state, "field_rng_seed": run.combat.field.rng.seed, "field_rng_state": run.combat.field.rng.state, "upgrade_stacks": run.upgrades.stacks.duplicate(true), "offers": offers}

static func has_fields(values: Variant, fields: Array) -> bool:
	if not values is Dictionary: return false
	for key in fields:
		if not values.has(key): return false
	return true

static func valid_structure(document: Dictionary) -> bool:
	var version = int(document.get("schema_version", 0))
	if version not in [1, VERSION] or document.get("state", "") not in ["playing", "paused", "upgrade"]: return false
	if not has_fields(document, ["session", "director", "combat", "field", "rng_seed", "rng_state", "field_rng_seed", "field_rng_state", "upgrade_stacks", "offers"]): return false
	if not has_fields(document.get("session"), SESSION_FIELDS) or not has_fields(document.get("director"), DIRECTOR_FIELDS) or not has_fields(document.get("combat"), COMBAT_FIELDS) or not has_fields(document.get("field"), LEGACY_FIELD_FIELDS if version == 1 else FIELD_FIELDS): return false
	if version == VERSION and not has_fields(document.get("spawn_sampler"), SPAWN_FIELDS): return false
	if not document.combat.stats is Dictionary or not document.combat.stats.has("hp") or not document.session.run_id is String or document.session.run_id.is_empty(): return false
	return document.combat.stats.hp > 0 and not document.session.reward_paid and document.offers is Array and document.upgrade_stacks is Dictionary

static func normalize(document: Dictionary) -> Dictionary:
	if not valid_structure(document): return {}
	if int(document.schema_version) == VERSION: return document
	var result = document.duplicate(true)
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
	for id in document.offers:
		var definition = run.upgrades.find_definition(id)
		if definition.is_empty(): return false
		offers.append(definition)
	if document.state == "upgrade" and offers.is_empty(): return false
	restore_properties(run, document.session, SESSION_FIELDS)
	restore_properties(run.director, document.director, DIRECTOR_FIELDS)
	restore_properties(run.combat, document.combat, COMBAT_FIELDS)
	restore_properties(run.combat.field, document.field, FIELD_FIELDS)
	restore_properties(run.combat.spawn_sampler, document.spawn_sampler, SPAWN_FIELDS)
	run.rng.seed = document.rng_seed
	run.rng.state = document.rng_state
	run.combat.field.rng.seed = document.field_rng_seed
	run.combat.field.rng.state = document.field_rng_state
	run.upgrades.stacks = document.upgrade_stacks.duplicate(true)
	run.selected_upgrades.assign(offers)
	run.events.clear()
	run.combat.events.clear()
	run.state = "upgrade" if document.state == "upgrade" else "paused"
	return true
