extends SceneTree

func _initialize() -> void:
	call_deferred("configure")

func configure() -> void:
	var settings = EditorInterface.get_editor_settings()
	settings.set_setting("export/android/android_sdk_path", OS.get_environment("EMBER_ANDROID_SDK"))
	settings.set_setting("export/android/java_sdk_path", OS.get_environment("EMBER_JAVA_SDK"))
	settings.set_setting("export/android/debug_keystore", ProjectSettings.globalize_path("res://.tools/debug.keystore"))
	print("Configured Android SDK, Java SDK and debug keystore")
	for frame in 10:
		await process_frame
	while EditorInterface.get_resource_filesystem().is_scanning():
		await process_frame
	quit()
