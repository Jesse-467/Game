extends RefCounted
const ATTACK = Rect2(1097, 564, 136, 136)
const SKILL = Rect2(938, 600, 112, 112)
const DASH = Rect2(1117, 453, 96, 96)

static func circle_contains(rect: Rect2, point: Vector2) -> bool:
	return point.distance_squared_to(rect.get_center()) <= pow(minf(rect.size.x, rect.size.y) * 0.5, 2)
