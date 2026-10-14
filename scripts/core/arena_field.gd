extends RefCounted
## Timed terrain cycles use shuffled type/cell bags and remain anchored in world space.

const World = preload("res://scripts/core/world_geometry.gd")
const Config = preload("res://scripts/core/gameplay_config.gd")
var ARENA = World.BOUNDS
var schedule: Dictionary
var definitions: Array[Dictionary] = []
var rotation_order: Array[String] = []
var rng = RandomNumberGenerator.new()
var zones: Array[Dictionary] = []
var definition: Dictionary = {}
var next_definition: Dictionary = {}
var phase = "inactive"
var phase_left = 0.0
var node_index = 1
var burn_exposure = 0.0
var type_bag: Array[String] = []
var spatial_bag: Array[int] = []
var last_type = ""
var last_cell = -1
var cycle_count = 0
var next_types: Array[String] = []

func load_content() -> void:
	var document: Dictionary = Config.read("arena_afflictions")
	schedule = document.schedule
	rotation_order.assign(document.rotation)
	definitions.assign(document.afflictions)

func reset(seed_value: int) -> void:
	rng.seed = seed_value ^ 0x5f3759df
	type_bag.clear()
	spatial_bag.clear()
	last_type = ""
	last_cell = -1
	cycle_count = 0
	phase = "inactive"
	definition = {}
	next_definition = {}
	next_types.clear()
	configure_node(1)

func find_definition(id: String) -> Dictionary:
	for entry in definitions:
		if entry.id == id: return entry
	return {}

func shuffle(values: Array) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var temporary = values[i]
		values[i] = values[j]
		values[j] = temporary

func take_type() -> Dictionary:
	if type_bag.is_empty():
		type_bag.assign(rotation_order)
		shuffle(type_bag)
		if type_bag.back() == last_type:
			var temporary = type_bag[0]
			type_bag[0] = type_bag[-1]
			type_bag[-1] = temporary
	last_type = type_bag.pop_back()
	return find_definition(last_type)

func take_cell() -> int:
	if spatial_bag.is_empty():
		spatial_bag.assign(range(int(schedule.spatial_grid_size) * int(schedule.spatial_grid_size)))
		shuffle(spatial_bag)
		if spatial_bag.back() == last_cell:
			var temporary = spatial_bag[0]
			spatial_bag[0] = spatial_bag[-1]
			spatial_bag[-1] = temporary
	last_cell = spatial_bag.pop_back()
	return last_cell

func plan_types() -> Array[String]:
	var result: Array[String] = []
	var count = rng.randi_range(int(schedule.minimum_zone_count), int(schedule.early_maximum_zone_count if node_index < int(schedule.early_maximum_until_node) else schedule.maximum_zone_count))
	while result.size() < count:
		var id = str(take_type().id)
		if not result.has(id): result.append(id)
	return result

func zone_definition(zone: Dictionary) -> Dictionary:
	return find_definition(str(zone.id)) if zone.has("id") else definition

func configure_node(index: int) -> void:
	node_index = index
	if index < int(schedule.starting_node):
		definition = {}
		next_definition = {}
		next_types.clear()
		zones.clear()
		phase = "inactive"
		phase_left = 0.0
		burn_exposure = 0.0
	elif phase == "inactive":
		next_types = plan_types()
		definition = find_definition(next_types[0])
		next_definition = definition
		phase = "recovery"
		phase_left = float(schedule.node_grace_seconds)
	# Subsequent node changes do not restart the independent terrain clock.

func step(delta: float, player: Vector2) -> Dictionary:
	if phase == "inactive": return neutral_modifiers()
	phase_left -= delta
	var exposure_delta = delta
	while phase_left <= 0:
		var overflow = -phase_left
		match phase:
			"recovery":
				prepare_zones(player)
				phase = "warning"
				phase_left = float(schedule.warning_seconds) - overflow
			"warning":
				phase = "active"
				phase_left = rng.randf_range(schedule.active_min_seconds, schedule.active_max_seconds) - overflow
				cycle_count += 1
			"active":
				zones.clear()
				definition = next_definition
				phase = "recovery"
				phase_left = float(schedule.recovery_seconds) - overflow
		burn_exposure = 0.0
		exposure_delta = minf(delta, overflow)
	var result = modifiers_at(player)
	if result.tick_damage > 0:
		burn_exposure += exposure_delta
		if burn_exposure >= float(result.tick_interval_seconds):
			burn_exposure = fmod(burn_exposure, float(result.tick_interval_seconds))
			result.damage_due = result.tick_damage
	else: burn_exposure = 0.0
	return result

func prepare_zones(player: Vector2 = Vector2.INF) -> void:
	if player == Vector2.INF: player = World.CENTER
	zones.clear()
	var view = World.visible_rect(player)
	var placement = view.grow(-float(schedule.placement_view_margin)).intersection(World.BOUNDS.grow(-float(schedule.radius_max)))
	var types = next_types if not next_types.is_empty() else plan_types()
	var area_left: float = view.intersection(World.BOUNDS).get_area() * float(schedule.max_visible_coverage)
	for id in types:
		var radius = minf(rng.randf_range(schedule.radius_min, schedule.radius_max), sqrt(maxf(0, area_left) / PI))
		if radius < float(schedule.radius_min) * float(schedule.min_radius_fraction): break
		for attempt in int(schedule.placement_attempts):
			var cell = take_cell()
			var offset = Vector2((cell % int(schedule.spatial_grid_size) + rng.randf_range(schedule.cell_jitter_min, schedule.cell_jitter_max)) / float(schedule.spatial_grid_size), (int(cell / int(schedule.spatial_grid_size)) + rng.randf_range(schedule.cell_jitter_min, schedule.cell_jitter_max)) / float(schedule.spatial_grid_size))
			var position = placement.position + placement.size * offset
			var separated = true
			for other in zones:
				if position.distance_to(other.pos) < radius + float(other.radius) + float(schedule.zone_spacing):
					separated = false
					break
			if not separated: continue
			zones.append({"id": id, "pos": position, "radius": radius, "cell": cell})
			area_left -= PI * radius * radius
			break
	if not zones.is_empty(): definition = zone_definition(zones[0])
	next_types = plan_types()
	next_definition = find_definition(next_types[0])

func neutral_modifiers() -> Dictionary:
	return {"move_multiplier": 1.0, "outgoing_damage_multiplier": 1.0, "crit_chance_delta": 0.0, "control_duration_multiplier": 1.0, "attack_interval_multiplier": 1.0, "incoming_damage_multiplier": 1.0, "tick_damage": 0.0, "tick_interval_seconds": 1.0, "damage_due": 0.0, "affliction": "", "kind": ""}

func modifiers_at(player: Vector2) -> Dictionary:
	var result = neutral_modifiers()
	if phase != "active": return result
	for zone in zones:
		if player.distance_squared_to(zone.pos) <= pow(float(zone.radius), 2):
			var entry = zone_definition(zone)
			for key in ["move_multiplier", "outgoing_damage_multiplier", "tick_damage", "tick_interval_seconds", "crit_chance_delta", "control_duration_multiplier", "attack_interval_multiplier", "incoming_damage_multiplier"]:
				result[key] = entry.get(key, result[key])
			result.affliction = entry.name
			result.kind = entry.kind
			break
	return result

func ui_description(player: Vector2) -> String:
	if phase == "inactive": return "场地平静 · 自由搭配所有祝福"
	if phase != "active":
		return "混合地脉 · %s %.1fs · 每个区域效果不同" % ["预警" if phase == "warning" else "即将转场", maxf(0, phase_left)]
	var modifiers = modifiers_at(player)
	var text = "%d种地脉 · %.1fs · %s" % [zones.size(), maxf(0, phase_left), "区域外" if modifiers.affliction.is_empty() else modifiers.affliction]
	if phase_left <= float(schedule.preview_seconds): text += " · 即将更换区域与效果"
	return text
