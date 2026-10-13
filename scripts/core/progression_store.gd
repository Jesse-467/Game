extends RefCounted
## Versioned local progression, atomic writes and a previous-save fallback.

const SAVE_VERSION = 1
const DEFAULT_PATH = "user://progress.json"
var path = DEFAULT_PATH

func defaults() -> Dictionary:
	return {"schema_version": SAVE_VERSION, "crystals": 0, "vitality": 0, "best_seconds": 0.0, "unlocks": ["knight"], "total_runs": 0, "last_run": {}, "last_settled_run_id": "", "settings": {"volume": 0.7, "control_scale": 1.0}}

func load_progress() -> Dictionary:
	for candidate in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var document = JSON.parse_string(FileAccess.get_file_as_string(candidate))
		if document is Dictionary and int(document.get("schema_version", 1)) == SAVE_VERSION:
			var result = defaults()
			result.crystals = maxi(0, int(document.get("crystals", 0)))
			result.vitality = clampi(int(document.get("vitality", 0)), 0, 10)
			result.best_seconds = maxf(0, float(document.get("best_seconds", 0)))
			result.unlocks = document.get("unlocks", ["knight"])
			result.total_runs = maxi(0, int(document.get("total_runs", 0)))
			result.last_run = document.get("last_run", {})
			result.last_settled_run_id = str(document.get("last_settled_run_id", ""))
			var settings: Dictionary = document.get("settings", {})
			result.settings.volume = clampf(float(settings.get("volume", 0.7)), 0, 1)
			result.settings.control_scale = clampf(float(settings.get("control_scale", 1.0)), 0.85, 1.15)
			return result
	return defaults()

func save_progress(progress: Dictionary) -> Error:
	var document = progress.duplicate(true)
	document.schema_version = SAVE_VERSION
	var temporary = path + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(document))
	file.flush()
	var write_error = file.get_error()
	file.close()
	if write_error != OK:
		return write_error
	if FileAccess.file_exists(path):
		var backup_error = DirAccess.copy_absolute(path, path + ".bak")
		if backup_error != OK:
			return backup_error
	return DirAccess.rename_absolute(temporary, path)
