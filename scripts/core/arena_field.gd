extends RefCounted
## Timed terrain cycles use shuffled type/cell bags and remain anchored in world space.

const World = preload("res://scripts/core/world_geometry.gd")
const ARENA = World.BOUNDS
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

func load_content() -> void:
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/arena_afflictions.json"))
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
		spatial_bag.assign(range(9))
		shuffle(spatial_bag)
		if spatial_bag.back() == last_cell:
			var temporary = spatial_bag[0]
			spatial_bag[0] = spatial_bag[-1]
			spatial_bag[-1] = temporary
	last_cell = spatial_bag.pop_back()
	return last_cell

func configure_node(index: int) -> void:
	node_index = index
	if index < int(schedule.starting_node):
		definition = {}
		next_definition = {}
		zones.clear()
		phase = "inactive"
		phase_left = 0.0
		burn_exposure = 0.0
	elif phase == "inactive":
		definition = take_type()
		next_definition = take_type()
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
				definition = next_definition if not next_definition.is_empty() else take_type()
				next_definition = take_type()
				phase = "recovery"
				phase_left = float(schedule.recovery_seconds) - overflow
		burn_exposure = 0.0
		exposure_delta = minf(delta, overflow)
	var result = modifiers_at(player)
	if result.tick_damage > 0:
		burn_exposure += exposure_delta
		if burn_exposure >= float(definition.tick_interval_seconds):
			burn_exposure = fmod(burn_exposure, float(definition.tick_interval_seconds))
			result.damage_due = result.tick_damage
	else: burn_exposure = 0.0
	return result

func prepare_zones(player: Vector2 = World.CENTER) -> void:
	zones.clear()
	var view = World.visible_rect(player)
	var placement = view.grow(-60).intersection(World.BOUNDS.grow(-float(schedule.radius_max)))
	var count = rng.randi_range(int(schedule.minimum_zone_count), int(schedule.early_maximum_zone_count if node_index < 10 else schedule.maximum_zone_count))
	var area_left: float = view.intersection(World.BOUNDS).get_area() * float(schedule.max_visible_coverage)
	for i in count:
		var cell = take_cell()
		var offset = Vector2((cell % 3 + rng.randf_range(0.24, 0.76)) / 3.0, (int(cell / 3) + rng.randf_range(0.24, 0.76)) / 3.0)
		var radius = minf(rng.randf_range(schedule.radius_min, schedule.radius_max), sqrt(maxf(0, area_left) / PI))
		if radius < float(schedule.radius_min) * 0.75: break
		var position = placement.position + placement.size * offset
		zones.append({"pos": position, "radius": radius, "cell": cell})
		area_left -= PI * radius * radius

func neutral_modifiers() -> Dictionary:
	return {"move_multiplier": 1.0, "outgoing_damage_multiplier": 1.0, "crit_chance_delta": 0.0, "control_duration_multiplier": 1.0, "attack_interval_multiplier": 1.0, "incoming_damage_multiplier": 1.0, "tick_damage": 0.0, "damage_due": 0.0, "affliction": ""}

func modifiers_at(player: Vector2) -> Dictionary:
	var result = neutral_modifiers()
	if phase != "active": return result
	for zone in zones:
		if player.distance_squared_to(zone.pos) <= pow(float(zone.radius), 2):
			for key in ["move_multiplier", "outgoing_damage_multiplier", "tick_damage", "crit_chance_delta", "control_duration_multiplier", "attack_interval_multiplier", "incoming_damage_multiplier"]:
				result[key] = definition.get(key, result[key])
			result.affliction = definition.name
			break
	return result

func ui_description(player: Vector2) -> String:
	if phase == "inactive": return "场地平静 · 自由搭配所有祝福"
	if phase != "active":
		return "%s · %s %.1fs · %s" % [definition.name, "预警" if phase == "warning" else "即将转场", maxf(0, phase_left), definition.summary]
	var text = "%s · %.1fs · %s%s" % [definition.name, maxf(0, phase_left), definition.summary, " [身处区域]" if not modifiers_at(player).affliction.is_empty() else ""]
	if phase_left <= float(schedule.preview_seconds) and not next_definition.is_empty(): text += " · 下一场地：" + str(next_definition.name)
	return text
