extends RefCounted
## Shuffled angular sectors reduce repeated arrival directions; points stay visible.

const World = preload("res://scripts/core/world_geometry.gd")
const SECTORS = 12
var bag: Array[int] = []
var last_sector = -1

func reset() -> void:
	bag.clear()
	last_sector = -1

func refill(rng: RandomNumberGenerator) -> void:
	bag.assign(range(SECTORS))
	for i in range(bag.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var temporary = bag[i]
		bag[i] = bag[j]
		bag[j] = temporary
	if bag.back() == last_sector:
		var temporary = bag[0]
		bag[0] = bag[-1]
		bag[-1] = temporary

func sample(player: Vector2, radius: float, rng: RandomNumberGenerator, enemies: Array[Dictionary], settings: Dictionary) -> Vector2:
	var view = World.visible_rect(player)
	var legal_world = World.BOUNDS.grow(-maxf(24, radius + 15))
	var minimum = float(settings.spawn_distance_min)
	var maximum = float(settings.spawn_distance_max)
	for attempt in 96:
		if bag.is_empty(): refill(rng)
		var sector = bag.pop_back()
		var angle = (sector + rng.randf()) * TAU / float(SECTORS)
		var distance = sqrt(rng.randf_range(minimum * minimum, maximum * maximum))
		var point = player + Vector2.from_angle(angle) * distance
		if not legal_world.has_point(point) or not World.spawn_screen_allowed(point - view.position): continue
		var separated = true
		for enemy in enemies:
			if float(enemy.born) > 0 and point.distance_to(enemy.pos) < radius + float(enemy.radius) + 18:
				separated = false
				break
		if not separated: continue
		last_sector = sector
		return point
	# A crowded arrival ring postpones this spawn instead of violating its safety rules.
	return Vector2.INF
