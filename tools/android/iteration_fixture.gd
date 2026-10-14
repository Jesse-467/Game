extends SceneTree
## Generate isolated checkpoints for testing the exported APK through normal UI.
const Catalog = preload("res://scripts/core/content_catalog.gd")
const Session = preload("res://scripts/core/run_session.gd")
const Store = preload("res://scripts/core/active_run_store.gd")
const World = preload("res://scripts/core/world_geometry.gd")

func _initialize() -> void: call_deferred("write_fixtures")

func write_fixtures() -> void:
	var catalog = Catalog.new()
	catalog.load_content()
	var run = Session.new(catalog)
	run.start("knight", 0, 47)
	run.director.node_index = 3
	run.director.elapsed = 85.0
	run.director.spawn_timer = 100.0
	run.level = 3
	run.combat.stats.level = 3
	run.combat.skills.ranks.nova = 2
	run.combat.equipment.equip({"id":"iron_sword", "slot":"weapon", "rarity":0, "tier":1, "stats":{"damage":3.0}})
	run.combat.rebuild_equipment(run.upgrades)
	run.combat.stats.hp = 40.0
	run.combat.field.configure_node(3)
	run.combat.field.prepare_zones(run.combat.player)
	run.combat.field.phase = "active"
	run.combat.field.phase_left = 35.0
	run.combat.loot.append({"uid":1, "kind":"health", "pos":World.CENTER+Vector2(70,0), "life":80.0})
	run.combat.next_loot_id = 2
	run.pending_equipment = {"id":"guard_mail", "slot":"armor", "rarity":1, "tier":2, "stats":{"max_hp":18.816, "armor":12.544}}
	run.state = "equipment"
	DirAccess.make_dir_recursive_absolute("res://builds/iteration-0.7/android")
	if not save(run, "native-equipment.save"): return
	run.choose_equipment(true)
	run.xp = run.xp_required()
	run.begin_level_up()
	if not save(run, "native-upgrade.save"): return
	print("PASS: native 0.7 equipment and skill-choice checkpoints generated with release-hard definitions")
	quit()

func save(run: RefCounted, filename: String) -> bool:
	var store = Store.new()
	store.path = "res://builds/iteration-0.7/android/"+filename
	if store.save_checkpoint(run.checkpoint()) != OK:
		push_error("Cannot save native iteration fixture")
		quit(1)
		return false
	return true
