extends RefCounted
## Versioned Variant checkpoints preserve Vector2, Color and exact RNG integers.
## Only data is decoded; objects are never deserialized.

const STORE_VERSION = 2
const Snapshot = preload("res://scripts/core/run_snapshot.gd")
var path = "user://active-run.save"

func load_checkpoint() -> Dictionary:
	for candidate in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate): continue
		var file = FileAccess.open(candidate, FileAccess.READ)
		if not file: continue
		var document = file.get_var(false)
		file.close()
		if document is Dictionary and int(document.get("schema_version", 0)) in [1, STORE_VERSION] and document.get("checkpoint") is Dictionary:
			var normalized = Snapshot.normalize(document.checkpoint)
			if not normalized.is_empty(): return normalized
	return {}

func save_checkpoint(checkpoint: Dictionary) -> Error:
	var temporary = path + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if not file: return FileAccess.get_open_error()
	file.store_var({"schema_version": STORE_VERSION, "checkpoint": checkpoint}, false)
	file.flush()
	var error = file.get_error()
	file.close()
	if error != OK: return error
	if FileAccess.file_exists(path):
		error = DirAccess.copy_absolute(path, path + ".bak")
		if error != OK: return error
	return DirAccess.rename_absolute(temporary, path)

func clear_checkpoint() -> Error:
	for candidate in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(candidate):
			var error = DirAccess.remove_absolute(candidate)
			if error != OK: return error
	return OK
