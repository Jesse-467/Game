extends "res://scripts/core/active_run_store.gd"
## Test double: UI/graphics tests never read, clear or write a player's active run.

var document: Dictionary = {}

func load_checkpoint() -> Dictionary:
	return document.duplicate(true)

func save_checkpoint(checkpoint: Dictionary) -> Error:
	document = checkpoint.duplicate(true)
	return OK

func clear_checkpoint() -> Error:
	document.clear()
	return OK
