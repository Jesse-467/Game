extends SceneTree
## Validate the actual frame-region pipeline used by SpriteLibrary, not an ideal grid.

const SpriteLibrary = preload("res://scripts/presentation/sprite_library.gd")

func _initialize() -> void:
	call_deferred("inspect_sheets")

func inspect_sheets() -> void:
	var catalog = load("res://scripts/core/content_catalog.gd").new()
	catalog.load_content()
	var ids: Array = catalog.character_order.duplicate()
	ids.append_array(catalog.enemies.keys())
	var library = SpriteLibrary.new()
	var report: Array[Dictionary] = []
	var failures = 0
	for id in ids:
		var path = "res://assets/animations/%s.png" % id
		var metadata_path = "res://assets/animations/%s.json" % id
		var valid = FileAccess.file_exists(path) and FileAccess.file_exists(metadata_path)
		if not valid:
			failures += 1
			report.append({"id": id, "valid": false, "reason": "missing texture or frame metadata"})
			continue
		var source = Image.load_from_file(ProjectSettings.globalize_path(path))
		var texture: Texture2D = load(path)
		var runtime = texture.get_image()
		var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
		valid = metadata.source_sha256 == FileAccess.get_sha256(path) and metadata.regions.size() == 16 and source.detect_alpha() != Image.ALPHA_NONE and runtime.get_width() <= 512 and runtime.get_height() <= 512
		for bounds in metadata.regions:
			valid = valid and bounds[0] >= 0 and bounds[1] >= 0 and bounds[2] > 0 and bounds[3] > 0 and bounds[0] + bounds[2] <= source.get_width() and bounds[1] + bounds[3] <= source.get_height()
		var frames = library.frames_for(id)
		for animation in SpriteLibrary.ANIMATIONS:
			valid = valid and frames.get_frame_count(animation) == 4
		if not valid: failures += 1
		report.append({"id": id, "valid": valid, "source_size": [source.get_width(), source.get_height()], "runtime_size": [runtime.get_width(), runtime.get_height()], "animations": 4, "frames": 16, "source_sha256": metadata.source_sha256})
		print("%s: %s, runtime%s, 4 animations / 16 frames" % [id, "PASS" if valid else "FAIL", runtime.get_size()])
	DirAccess.make_dir_recursive_absolute("res://builds/reports")
	var file = FileAccess.open("res://builds/reports/art-validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures": failures, "sheets": report}, "\t"))
	file.close()
	quit(0 if failures == 0 else 1)
