extends RefCounted
## Content selects phases; one geometry plan drives telegraphs and damage checks.
const Config = preload("res://scripts/core/gameplay_config.gd")

static func boss_phase(definition: Dictionary, hp_fraction: float, rotation: int) -> Dictionary:
	var result = {"id": "opening", "name": "", "attacks": definition.attacks}
	for phase in definition.get("phases", []):
		if hp_fraction <= float(phase.hp_below) and rotation >= int(phase.get("min_rotation", 0)):
			result = phase
	return result

static func telegraph(origin: Vector2, target: Vector2, action: Dictionary) -> Array[Dictionary]:
	var shapes: Array[Dictionary] = []
	match action.type:
		"combo":
			for i in action.attacks.size():
				for shape in telegraph(origin, target, action.attacks[i]):
					shape.part_index = i
					shapes.append(shape)
		"slam", "leap", "hazard":
			var offsets: Array = action.get("offsets", [[0.0, 0.0]])
			for offset in offsets:
				shapes.append({"kind": "circle", "pos": target + Vector2(offset[0], offset[1]), "radius": float(action.radius)})
		"shockwave":
			shapes.append({"kind": "ring", "pos": origin, "inner_radius": float(action.inner_radius), "radius": float(action.radius)})
		"radial_burst":
			for i in int(action.count):
				var direction = Vector2.from_angle(float(action.get("angle_offset", 0)) + i * TAU / float(action.count))
				shapes.append({"kind": "line", "pos": origin, "end": origin + direction * float(Config.section("combat").warning_ray_length)})
		"bolt", "fan":
			var direction = origin.direction_to(target)
			var count = int(action.get("count", 1))
			for i in count:
				var angle = 0.0 if count == 1 else (float(i) / float(count - 1) - 0.5) * float(action.spread)
				shapes.append({"kind": "line", "pos": origin, "end": origin + direction.rotated(angle) * float(Config.section("combat").warning_ray_length)})
		"summon":
			for i in int(action.count):
				shapes.append({"kind": "spawn", "pos": origin + Vector2.from_angle(i * TAU / float(action.count)) * float(Config.section("combat").summon_ring_radius), "radius": float(Config.section("combat").summon_marker_radius)})
		_:
			shapes.append({"kind": "line", "pos": origin, "end": target})
	return shapes

static func hits(shape: Dictionary, point: Vector2, body_radius: float = -1.0) -> bool:
	if body_radius < 0: body_radius = float(Config.section("combat").player_body_radius)
	var distance: float = shape.pos.distance_to(point)
	if shape.kind == "circle": return distance < float(shape.radius) + body_radius
	if shape.kind == "ring": return distance > float(shape.inner_radius) - body_radius and distance < float(shape.radius) + body_radius
	return false
