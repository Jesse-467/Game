extends SceneTree
const Snapshot = preload("res://scripts/core/run_snapshot.gd")

func _initialize() -> void: call_deferred("inspect")

func inspect() -> void:
	var path = OS.get_cmdline_user_args()[0]
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Cannot inspect checkpoint file")
		quit(1)
		return
	var stored: Dictionary = file.get_var(false)
	file.close()
	var document = Snapshot.normalize(stored.checkpoint)
	if document.is_empty():
		push_error("Checkpoint is not valid")
		quit(1)
		return
	var player: Vector2 = document.combat.player
	print(JSON.stringify({"stored_schema": stored.checkpoint.schema_version, "normalized_schema": document.schema_version, "player": [player.x, player.y], "seconds": document.director.elapsed, "state": document.state, "level": document.session.level, "hp": document.combat.stats.hp, "skill_cooldown": document.combat.skill_cooldown, "node": document.director.node_index, "field": document.field.definition.get("id", ""), "field_phase": document.field.phase, "field_left": document.field.phase_left}))
	quit()
