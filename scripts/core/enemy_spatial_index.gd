extends RefCounted
## Broad-phase lookup only; exact collision and hit ordering stay in CombatSystem.

const CELL_SIZE = 64.0
var cells: Dictionary = {}
var max_radius = 0.0

func rebuild(enemies: Array[Dictionary]) -> void:
	cells.clear()
	max_radius = 0.0
	for index in enemies.size():
		var enemy = enemies[index]
		max_radius = maxf(max_radius, enemy.radius)
		var key = Vector2i(floori(enemy.pos.x / CELL_SIZE), floori(enemy.pos.y / CELL_SIZE))
		if not cells.has(key):
			var bucket: Array[int] = []
			cells[key] = bucket
		cells[key].append(index)

func query_segment(start: Vector2, end: Vector2, extra_radius: float = 7.0) -> Array[int]:
	var padding = max_radius + extra_radius
	var first = Vector2i(floori((minf(start.x, end.x) - padding) / CELL_SIZE), floori((minf(start.y, end.y) - padding) / CELL_SIZE))
	var last = Vector2i(floori((maxf(start.x, end.x) + padding) / CELL_SIZE), floori((maxf(start.y, end.y) + padding) / CELL_SIZE))
	var result: Array[int] = []
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			result.append_array(cells.get(Vector2i(x, y), []))
	# Preserve existing enemy-array order, including which target consumes a pierce.
	result.sort()
	return result
