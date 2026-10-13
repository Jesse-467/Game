extends SceneTree
## Produce isolated checkpoints for installing into this game's emulator sandbox.
## No fixture loading path or developer combat switches exist in the shipped app.

const Catalog = preload("res://scripts/core/content_catalog.gd")
const Session = preload("res://scripts/core/run_session.gd")
const Store = preload("res://scripts/core/active_run_store.gd")

func _initialize() -> void:
	call_deferred("write_fixtures")

func write_fixtures() -> void:
	var content = Catalog.new()
	content.load_content()
	DirAccess.make_dir_recursive_absolute("res://builds/boss-probe")
	for id in ["boss_ogre", "boss_lich", "boss_wyrm"]:
		var run = Session.new(content)
		run.start("knight", 0, 42)
		run.director.node_index = {"boss_ogre": 20, "boss_lich": 25, "boss_wyrm": 30}[id]
		run.director.spawn_timer = 15.0
		run.director.elapsed = {"boss_ogre": 650.0, "boss_lich": 815.0, "boss_wyrm": 980.0}[id]
		run.combat.player = Vector2(855, 350)
		run.combat.spawn_enemy(id, Vector2(640, 335))
		var enemy: Dictionary = run.combat.enemies[0]
		enemy.born = 0.0
		enemy.hp *= 0.4
		enemy.timer = 0.0
		var store = Store.new()
		store.path = "res://builds/boss-probe/%s.save" % id
		if store.save_checkpoint(run.checkpoint()) != OK:
			push_error("Cannot write emulator fixture " + id)
			quit(1)
			return
	print("PASS: wrote three isolated boss checkpoints for emulator validation")
	quit()
