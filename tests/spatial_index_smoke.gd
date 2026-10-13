extends SceneTree

const Index = preload("res://scripts/core/enemy_spatial_index.gd")

func _initialize() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 6642
	var enemies: Array[Dictionary] = []
	for i in 120:
		enemies.append({"pos": Vector2(rng.randf_range(-128, 1400), rng.randf_range(-128, 850)), "radius": rng.randf_range(12, 70)})
	var index = Index.new()
	index.rebuild(enemies)
	for sample in 500:
		var start = Vector2(rng.randf_range(-200, 1500), rng.randf_range(-200, 950))
		var end = start + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0, 1000)
		var candidates = index.query_segment(start, end)
		var sorted = candidates.duplicate()
		sorted.sort()
		if sorted != candidates:
			push_error("Collision candidates changed hit ordering")
			quit(1)
			return
		for i in enemies.size():
			var enemy = enemies[i]
			var intersects: bool = enemy.pos.distance_to(Geometry2D.get_closest_point_to_segment(enemy.pos, start, end)) <= enemy.radius + 7
			if intersects and not candidates.has(i):
				push_error("Spatial lookup omitted a swept-circle collision")
				quit(1)
				return
	enemies.clear()
	enemies.append({"pos": Vector2(64, 64), "radius": 42.0})
	index.rebuild(enemies)
	if index.query_segment(Vector2(0, 64), Vector2(128, 64)) != [0]:
		push_error("Rebuilt spatial index retained stale enemy indices")
		quit(1)
		return
	print("PASS: 500 swept queries preserve collision coverage and ordering; rebuild discards stale indices")
	quit()
