extends SceneTree
## Isolated native-APK scenario; no fixture loader is included in the game.
const Catalog = preload("res://scripts/core/content_catalog.gd")
const Session = preload("res://scripts/core/run_session.gd")
const Store = preload("res://scripts/core/active_run_store.gd")
const World = preload("res://scripts/core/world_geometry.gd")

func _initialize() -> void: call_deferred("write_fixture")

func write_fixture() -> void:
	var content = Catalog.new()
	content.load_content()
	var run = Session.new(content)
	run.start("knight", 0, 773)
	run.director.node_index = 20
	run.director.elapsed = 720.0
	run.director.spawn_timer = 15.0
	run.combat.spawn_enemy("boss_ogre", World.CENTER + Vector2(270, -40))
	run.combat.enemies[0].hp *= 0.6
	run.combat.enemies[0].born = 0.0
	run.combat.enemies[0].timer = 3.0
	run.combat.field.configure_node(20)
	run.combat.field.definition = run.combat.field.find_definition("keen_ground")
	run.combat.field.prepare_zones(run.combat.player)
	run.combat.field.phase = "active"
	run.combat.field.phase_left = 38.0
	DirAccess.make_dir_recursive_absolute("res://builds/world-probe")
	var store = Store.new()
	store.path = "res://builds/world-probe/native-world.save"
	if store.save_checkpoint(run.checkpoint()) != OK:
		push_error("Cannot write native world fixture")
		quit(1)
		return
	run.combat.player = World.BOUNDS.end - Vector2.ONE * World.PLAYER_MARGIN
	run.combat.enemies.clear()
	run.combat.spawn_enemy("boss_ogre", run.combat.player - Vector2(260, 100))
	run.combat.enemies[0].born = 0.0
	run.combat.enemies[0].hp *= 0.7
	run.combat.field.prepare_zones(run.combat.player)
	store.path = "res://builds/world-probe/native-boundary.save"
	if store.save_checkpoint(run.checkpoint()) != OK:
		push_error("Cannot write native boundary fixture")
		quit(1)
		return
	print("PASS: native APK world fixture ready")
	quit()
