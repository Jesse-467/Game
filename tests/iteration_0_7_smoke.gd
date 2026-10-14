extends SceneTree
const Catalog = preload("res://scripts/core/content_catalog.gd")
const Session = preload("res://scripts/core/run_session.gd")
const World = preload("res://scripts/core/world_geometry.gd")
const Field = preload("res://scripts/core/arena_field.gd")
var failures: Array[String] = []
var checks = 0

class TestGame extends "res://scripts/main.gd":
	func create_active_store() -> RefCounted: return preload("res://tests/support/memory_run_store.gd").new()
	func load_progress() -> void: meta = progression_store.defaults()
	func save_progress() -> bool: return true

func _initialize() -> void: call_deferred("run_checks")
func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		push_error(description)

func item(id: String, slot: String, values: Dictionary) -> Dictionary:
	return {"id":id,"slot":slot,"rarity":0,"tier":1,"stats":values}

func run_checks() -> void:
	var catalog = Catalog.new()
	catalog.load_content()
	var run = Session.new(catalog)
	run.start("knight", 0, 707)
	var combat = run.combat
	combat.stats = run.upgrades.apply("power", combat.stats)
	combat.stats = run.upgrades.apply("power", combat.stats)
	check(is_equal_approx(combat.stats.damage, 16.8), "Two20% attack blessings add to40% inside one bucket")
	combat.equipment.equip(item("iron_sword","weapon",{"damage":5.0}))
	combat.rebuild_equipment(run.upgrades)
	check(is_equal_approx(combat.stats.damage, 23.8) and combat.stats.base_damage == 17, "Equipment contributes to base attack before the40% blessing bucket")
	combat.equipment.equip(item("iron_sword","weapon",{"damage":2.0}))
	combat.rebuild_equipment(run.upgrades)
	check(is_equal_approx(combat.stats.damage, 19.6), "Replacing equipment removes the previous flat base contribution")
	combat.stats.hp = 40
	combat.equipment.equip(item("guard_mail","armor",{"max_hp":30.0,"armor":25.0}))
	combat.rebuild_equipment(run.upgrades)
	check(combat.stats.hp == 40 and combat.stats.max_hp == 130, "Equipping health gear does not heal")
	combat.take_damage(25)
	check(is_equal_approx(combat.stats.hp, 20), "Flat armor uses an independent incoming damage factor")
	for i in 20:
		combat.equipment.equip(item("guard_mail","armor",{"max_hp":0.0,"armor":0.0}))
		combat.rebuild_equipment(run.upgrades)
		combat.equipment.equip(item("guard_mail","armor",{"max_hp":30.0,"armor":25.0}))
		combat.rebuild_equipment(run.upgrades)
	check(combat.stats.hp == 20, "Repeated swapping cannot manufacture healing")
	run.start("knight",0,7071)
	var plain = run.director.enemy_stats(catalog.enemies.slime)
	run.director.node_index = 2
	var fortified = run.director.enemy_stats(catalog.enemies.slime)
	check(plain.base_stats == fortified.base_stats and fortified.defense == plain.defense + 6, "A node state changes final defense without mutating same-level base stats")
	check(is_equal_approx(fortified.max_hp, plain.max_hp * 1.08), "The fortified health bonus applies after base growth")
	run.director.node_index = 3
	var frenzy = run.director.enemy_stats(catalog.enemies.slime)
	check(frenzy.level == 2 and frenzy.base_stats.max_hp > plain.base_stats.max_hp, "The level curve grows template-derived base health")
	check(is_equal_approx(frenzy.damage, frenzy.base_stats.damage * 1.12) and frenzy.defense == frenzy.base_stats.defense, "Changing nodes recomputes independent states rather than retaining prior fortification")
	check(catalog.enemies.slime.hp == 30 and catalog.enemies.slime.defense == 0, "Neither growth nor node states modify the shared monster template")
	run.start("knight",0,7072)
	combat.spawn_enemy("slime",combat.player + Vector2(70,0))
	combat.enemies[0].hp = 1000
	combat.enemies[0].defense = 100
	combat.enemies[0].crit_resistance = 1.0
	combat.damage_enemy(combat.enemies[0],10,false,1.0)
	check(combat.enemies[0].hp == 995, "Monster defense and anti-crit resistance both affect actual player damage")
	combat.spawn_enemy("slime",combat.player + Vector2(85,0))
	combat.enemies[1].hp = 1000
	combat.enemies[1].defense = 0
	combat.stats.blast_fraction = 0.2
	combat.damage_enemy(combat.enemies[0],10,true,0)
	check(combat.enemies[1].hp == 998, "Explosion resolves the second target's defense independently of the primary armor")
	run.start("knight", 0, 708)
	combat.health_drop_left = 0
	combat.roll_loot({"kind":"boss", "pos":combat.player})
	var health_count = combat.loot.filter(func(drop): return drop.kind == "health").size()
	check(health_count == 1, "A boss reward can produce one scarce health potion")
	for i in 50: combat.roll_loot({"kind":"boss", "pos":combat.player})
	check(combat.loot.filter(func(drop): return drop.kind == "health").size() == 1, "Health drop cooldown prevents repeated reward flooding")
	check(combat.loot.size() <= 5, "Ground loot count remains bounded")
	combat.loot.assign([{"uid":1,"kind":"health","pos":combat.player,"life":90.0}])
	combat.update_loot(0)
	check(combat.loot.size() == 1 and combat.health_packs_used == 0, "Full health leaves a potion on the ground")
	combat.take_damage(30)
	combat.update_loot(0)
	check(combat.loot.is_empty() and combat.stats.hp == 92 and combat.health_packs_used == 1, "A nearby potion restores22 of the missing30 health")
	combat.stats.hp = 0
	combat.loot.append({"uid":2,"kind":"health","pos":combat.player,"life":90.0})
	combat.update_loot(0)
	check(combat.stats.hp == 0 and combat.loot.size() == 1, "Potions cannot revive a dead player")
	run.start("knight", 0, 709)
	var initial_unlocks = combat.equipment.unlocked.duplicate()
	check(not initial_unlocks.has("swift_blade") and combat.equipment.unlocked_for_bosses(1).has("swift_blade"), "Boss progress unlocks new equipment types rather than permanent power")
	var loot_valid = true
	for i in 200:
		var gear: Dictionary = combat.equipment.roll("knight", 5, combat.loot_rng)
		loot_valid = loot_valid and gear.id != "oak_staff" and gear.id != "hunter_bow"
	check(loot_valid, "200 equipment rolls respect the character's weapon pool")
	run.level = 3
	run.xp = run.xp_required()
	run.begin_level_up()
	check(run.level == 4 and run.selected_upgrades.size() == 3 and run.selected_upgrades[0].id == "train:nova", "Level4 presents training and replacement skill choices")
	combat.skill_cooldown = 5.0
	check(run.apply_upgrade("train:nova") and combat.skills.rank() == 2 and combat.skill_cooldown == 5.0, "Skill training changes rank without resetting cooldown")
	check(not run.apply_upgrade("skill:aegis"), "Skill choices require an active offered growth decision")
	combat.skills.choose("skill:aegis")
	check(combat.skills.active_id == "aegis" and combat.skill_cooldown == 5.0, "Skill replacement preserves the running cooldown")
	combat.skills.choose("skill:nova")
	check(combat.skills.rank() == 2, "Returning to a learned skill preserves its rank in the same run")
	for role in catalog.character_order:
		for entry in combat.skills.definitions.values():
			if entry.character != role: continue
			run.start(role, 0, 710)
			if combat.skills.active_id != entry.id: combat.skills.choose("skill:" + str(entry.id))
			combat.spawn_enemy("slime", combat.player + Vector2(80, 0))
			combat.enemies[0].hp = 1000
			check(run.cast_skill(), str(entry.id) + " can be cast at rank one")
			check(not run.cast_skill(), str(entry.id) + " enforces cooldown")
			if entry.kind == "projectiles": check(combat.projectiles.size() == int(entry.count), str(entry.id) + " creates its own projectile pattern")
			elif entry.kind == "hazard":
				combat.update_hazards(float(entry.tick) + 0.01)
				check(combat.hazards.size() == 1 and combat.enemies[0].hp < 1000, str(entry.id) + " creates a damaging persistent area")
			else: check(combat.enemies[0].hp < 1000, str(entry.id) + " produces close-range damage")
			if entry.kind == "shield": check(combat.shield_hp == 20 and combat.shield_left == 4, "Aegis grants its temporary shield rather than free permanent health")
	var field = Field.new()
	field.load_content()
	var coverage: Dictionary = {}
	var valid = true
	for seed_value in 80:
		field.reset(seed_value)
		field.configure_node(20)
		for position in [World.CENTER, Vector2(48,48), Vector2(3552,2352)]:
			field.prepare_zones(position)
			var seen: Dictionary = {}
			for zone in field.zones:
				valid = valid and not seen.has(zone.id)
				seen[zone.id] = true
				coverage[zone.id] = int(coverage.get(zone.id, 0)) + 1
				for other in field.zones:
					if other != zone: valid = valid and zone.pos.distance_to(other.pos) >= float(zone.radius) + float(other.radius) + 13.9
	check(valid, "240 mixed terrain generations contain unique types and separated circular areas")
	check(coverage.size() == field.rotation_order.size(), "Mixed terrain generation covers every configured type")
	run.start("knight", 0, 711)
	combat.skills.choose("skill:aegis")
	combat.skills.choose("train:aegis")
	combat.skill_cooldown = 4.5
	run.pending_equipment = item("iron_sword","weapon",{"damage":4.0})
	run.state = "equipment"
	var saved = run.checkpoint()
	var restored = Session.new(catalog)
	check(restored.restore_checkpoint(saved) and restored.state == "equipment", "Pending equipment comparison survives restart")
	check(restored.pending_equipment == run.pending_equipment and restored.combat.skills.rank() == 2 and restored.combat.skill_cooldown == 4.5, "Restore preserves exact rolled equipment, learned skill rank and cooldown")
	check(restored.combat.loot_rng.state == combat.loot_rng.state, "Loot randomness survives a checkpoint without rerolling")
	check(restored.choose_equipment(true) and restored.combat.equipment.equipped.weapon.stats.damage == 4, "Restored equipment can be selected exactly once")
	check(not restored.choose_equipment(true), "Equipment choice cannot apply twice")
	run.start("knight",0,7111)
	run.director.node_index = 5
	run.combat.spawn_enemy("boss_ogre", World.CENTER + Vector2(200,0))
	var legacy = run.checkpoint()
	legacy.schema_version = 2
	legacy.combat.enemies[0].max_hp = 360.0
	legacy.combat.enemies[0].hp = 180.0
	for key in ["defense","crit_resistance","slow_resistance","damage_scale","base_stats","level"]: legacy.combat.enemies[0].erase(key)
	check(restored.restore_checkpoint(legacy), "A v2 run with an old low-health boss remains loadable")
	var migrated_enemy: Dictionary = restored.combat.enemies[0]
	check(migrated_enemy.max_hp >= 1000 and is_equal_approx(migrated_enemy.hp / migrated_enemy.max_hp,0.5), "Old monsters adopt configured growth while preserving their health fraction")
	check(migrated_enemy.defense > 0 and migrated_enemy.crit_resistance > 0 and migrated_enemy.has("base_stats"), "Legacy monsters receive configured defense, anti-crit and separate base stats")
	restored.start("knight",0,712)
	check(restored.combat.equipment.equipped.is_empty() and restored.combat.skills.rank() == 1, "A new run resets equipment and learned skill ranks")
	root.size = Vector2i(1280,720)
	var game = TestGame.new()
	root.add_child(game)
	game.set_physics_process(false)
	await create_timer(0.05).timeout
	game.start_run()
	game.session.pending_equipment = item("guard_mail","armor",{"max_hp":12.0,"armor":8.0})
	game.session.state = "equipment"
	game.game_ui.show_equipment(game.session)
	await process_frame
	await process_frame
	check(game.game_ui.panel.get_global_rect().end.y <= 720, "Equipment comparison and all three actions fit the landscape screen")
	game.on_action("build")
	game.on_action("pause")
	check(game.session.state == "equipment" and game.panel_return.is_empty(), "Back from equipment stats returns to the pending decision")
	game.on_action("equip")
	check(game.session.state == "playing" and not game.game_ui.panel.visible, "UI equipment selection resumes the same living run")
	game.session.level = 3
	game.session.xp = game.session.xp_required()
	game.session.begin_level_up()
	game.consume_events()
	await process_frame
	await process_frame
	check(game.game_ui.panel.get_global_rect().end.y <= 720, "Skill training and replacement cards fit the landscape screen")
	check(game.battle_view.loot_sprites.texture(6).atlas.get_width() == 1024, "Loot icons use the imported mobile1024px shared atlas")
	game.audio_service.music.stop()
	await create_timer(0.1).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	if failures.is_empty(): print("PASS: %d additive bucket, equipment, loot, skills, mixed terrain and UI checks" % checks)
	quit(0 if failures.is_empty() else 1)
