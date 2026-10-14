extends SceneTree
const World = preload("res://scripts/core/world_geometry.gd")
class PreviewGame extends "res://scripts/main.gd":
	func create_active_store() -> RefCounted: return preload("res://tests/support/memory_run_store.gd").new()
	func load_progress() -> void: meta = progression_store.defaults()
	func save_progress() -> bool: return true
	func _notification(_what: int) -> void: pass
var game: Node2D
func _initialize() -> void: call_deferred("capture")
func capture() -> void:
	root.size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute("res://builds/iteration-0.7/render")
	game = PreviewGame.new()
	root.add_child(game)
	game.set_physics_process(false)
	await picture("camp")
	game.on_action("equipment_collection")
	await picture("equipment-collection")
	game.start_run()
	game.consume_events()
	game.game_ui.banner_left = 0
	var combat: RefCounted = game.session.combat
	game.session.director.node_index = 20
	game.session.director.elapsed = 720
	combat.field.configure_node(20)
	combat.field.prepare_zones(combat.player)
	combat.field.phase = "active"
	combat.field.phase_left = 35
	for i in 9:
		combat.spawn_enemy(["slime","bat","skeleton","shaman","charger","elite_guard"][i%6],World.CENTER + Vector2.from_angle(i*TAU/9.0)*240)
		combat.enemies[-1].born = 0
	combat.loot.append({"uid":1,"kind":"health","pos":World.CENTER + Vector2(-110,80),"life":80.0})
	combat.loot.append({"uid":2,"kind":"equipment","pos":World.CENTER + Vector2(100,100),"life":80.0,"item":{"id":"iron_sword","slot":"weapon","rarity":1,"tier":2,"stats":{"damage":4.2}}})
	await picture("mixed-terrain-loot")
	game.session.level = 3
	game.session.xp = game.session.xp_required()
	game.session.begin_level_up()
	game.consume_events()
	await picture("skill-growth")
	game.on_action("upgrade","skill:aegis")
	game.session.pending_equipment = {"id":"guard_mail","slot":"armor","rarity":1,"tier":2,"stats":{"max_hp":18.816,"armor":12.544}}
	game.session.state = "equipment"
	game.game_ui.show_equipment(game.session)
	await picture("equipment-compare")
	game.on_action("equip")
	game.session.pause()
	game.consume_events()
	game.on_action("build")
	await picture("loadout")
	game.on_action("paused_menu")
	game.on_action("resume")
	game.consume_events()
	combat.enemies.clear()
	combat.spawn_enemy("boss_ogre",World.CENTER + Vector2(250,0))
	combat.enemies[0].born = 0
	combat.enemies[0].hp *= 0.5
	combat.update_enemies(0)
	combat.enemies[0].timer = 0
	combat.update_enemies(0)
	await picture("boss-combination")
	game.audio_service.music.stop()
	await create_timer(0.1).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("PASS: actual renderer captured seven0.7 gameplay and menu states using release-hard data")
	quit()
func picture(name: String) -> void:
	game.battle_view.sync()
	game.game_ui.sync(game.session,0)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://builds/iteration-0.7/render/%s.png" % name)
