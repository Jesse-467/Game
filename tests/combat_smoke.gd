extends SceneTree

const Catalog = preload("res://scripts/core/content_catalog.gd")
const Session = preload("res://scripts/core/run_session.gd")
const Controls = preload("res://scripts/input/touch_controller.gd")
const Store = preload("res://scripts/core/progression_store.gd")
var failures: Array[String] = []
var checks = 0

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func _initialize() -> void:
	call_deferred("run_checks")

func touch(index: int, pos: Vector2, pressed: bool = true) -> InputEventScreenTouch:
	var event = InputEventScreenTouch.new()
	event.index = index
	event.position = pos
	event.pressed = pressed
	return event

func run_checks() -> void:
	var content = Catalog.new()
	content.load_content()
	var run = Session.new(content)
	run.start("knight", 0, 42)
	var combat = run.combat
	check(run.level == 1 and combat.stats.hp == 100, "Run starts from level one and base health")
	combat.take_damage(8)
	combat.take_damage(8)
	check(combat.stats.hp == 92, "Simultaneous enemy hits respect damage immunity")
	combat.hurt_timer = 0
	check(run.dash(), "Available dodge can be activated")
	combat.take_damage(8)
	check(combat.stats.hp == 92 and not run.dash(), "Dodge grants immunity and cannot bypass cooldown")
	combat.enemies.clear()
	combat.spawn_enemy("slime", combat.player + Vector2(35, 0))
	combat.enemies[0].born = 0
	combat.stats.damage = 100
	combat.attack()
	combat.update_projectiles(0.10)
	combat.update_enemies(0.01)
	run.consume_combat_events()
	check(run.kills == 1 and combat.gems.size() == 1, "Swept projectile hit kills a target and drops experience")
	combat.gems[0].pos = combat.player
	combat.update_gems(0.01)
	run.consume_combat_events()
	check(run.xp == 3, "Experience is earned from pickup")
	run.xp = run.xp_required() + 20
	run.begin_level_up()
	check(run.state == "upgrade" and run.level == 2 and run.selected_upgrades.size() == 3, "Level-up pauses and offers three choices")
	check(not run.apply_upgrade("nonexistent"), "Only an offered upgrade can be chosen")
	check(run.apply_upgrade(run.selected_upgrades[0].id), "Offered upgrade is accepted")
	check(run.level == 3 and run.state == "upgrade", "Overflow experience opens the next level-up without losing XP")
	run.apply_upgrade(run.selected_upgrades[0].id)
	run.start("knight", 0, 9)
	run.director.node_index = 4
	for i in int(content.balance.difficulty.max_active_enemies):
		combat.spawn_enemy("slime", combat.player + Vector2((i % 12) * 70 - 420, int(i / 12) * 70 - 350))
		combat.enemies[-1].born = 0.0
	run.advance_node()
	var boss: Dictionary = {}
	for enemy in combat.enemies:
		if enemy.kind == "boss": boss = enemy
	check(not boss.is_empty() and run.director.node_index == 5, "Mandatory boss spawns even at the enemy cap")
	boss.hp = 0
	combat.update_enemies(0.01)
	run.consume_combat_events()
	check(run.director.bosses_defeated == 1 and run.director.node_index == 6, "Boss death continues endless nodes")
	check(run.xp >= 40 and combat.gems.is_empty(), "Boss victory collects reward XP before transition")
	run.start("knight", 0, 10)
	combat.stats.pierce = 1
	combat.stats.damage = 10
	combat.spawn_enemy("slime", combat.player + Vector2(50, 0))
	combat.spawn_enemy("slime", combat.player + Vector2(100, 0))
	for enemy in combat.enemies: enemy.born = 0
	combat.attack()
	combat.update_projectiles(0.10)
	combat.update_projectiles(0.10)
	check(combat.enemies[0].hp == 14 and combat.enemies[1].hp == 14, "Pierce hits two distinct targets once each")
	combat.stats.projectile_count = 3
	combat.attack()
	check(combat.projectiles.size() == 3, "Multishot produces three separate trajectories")
	run.start("mage", 0, 11)
	combat.spawn_enemy("slime", combat.player + Vector2(50, 0))
	combat.spawn_enemy("slime", combat.player + Vector2(70, 20))
	combat.stats.blast_fraction = 0.35
	combat.damage_enemy(combat.enemies[0], 10)
	check(combat.enemies[0].slow_timer > 0 and combat.enemies[1].hp < 24, "Frost and explosion change hit behavior")
	check(run.cast_skill() and combat.enemies[0].slow == 0.55, "Mage active skill strengthens crowd control")
	run.start("ranger", 0, 12)
	check(combat.stats.pierce == 1 and run.cast_skill() and combat.projectiles.size() == 9, "Ranger has distinct piercing attack and volley skill")
	run.start("knight", 0, 13)
	combat.spawn_enemy("boss_ogre", combat.player + Vector2(160, 0))
	boss = combat.enemies[0]
	boss.born = 0
	boss.timer = 0
	combat.update_enemies(0.01)
	var hp_before = combat.stats.hp
	combat.update_enemies(0.50)
	check(boss.telegraph > 0 and combat.stats.hp == hp_before, "Boss windup is visible and does not deal premature damage")
	combat.player += Vector2(0, 160)
	combat.update_enemies(0.70)
	check(combat.stats.hp == hp_before, "Moving away from locked telegraph avoids boss strike")
	var time_before = run.director.elapsed
	run.pause()
	run.step(3, Vector2.RIGHT, true)
	check(run.director.elapsed == time_before and run.state == "paused", "Pause freezes the complete simulation")
	run.resume()
	check(run.state == "playing", "Resume continues the existing run")
	for i in 220:
		combat.add_gem(Vector2(i, 120), 3)
	var total = 0
	for gem in combat.gems: total += gem.value
	check(combat.gems.size() <= 180 and total == 660, "Pickup merging bounds entity count without losing XP")
	var controls = Controls.new()
	controls.handle(touch(0, Vector2(205, 610)), true)
	controls.handle(touch(1, Vector2(1160, 630)), true)
	controls.handle(touch(2, Vector2(980, 650)), true)
	check(controls.joystick_touch == 0 and controls.attack_touch == 1 and controls.commands == ["skill"], "Three touches maintain movement, held attack and skill intent")
	controls.handle(touch(1, Vector2.ZERO, false), true)
	check(controls.attack_touch == -1 and controls.joystick_touch == 0, "Releasing attack keeps movement touch")
	controls.clear()
	check(controls.joystick_touch == -1 and controls.joystick_vector == Vector2.ZERO, "Pause clears touch ownership")
	check(content.characters.size() == 3 and content.enemies.size() == 9, "Content catalog includes three characters, six mobs and three bosses")
	run.start("ranger", 0, 14)
	combat.facing = Vector2.RIGHT
	combat.spawn_enemy("slime", combat.player - Vector2(150, 0))
	run.cast_skill()
	check(combat.projectiles.size() == 9 and combat.projectiles[4].velocity.x < 0, "Ranger volley targets nearby enemies while the player moves away")
	run.start("knight", 0, 15)
	run.director.node_index = 5
	combat.spawn_enemy("boss_ogre")
	combat.enemies[0].hp = 0
	combat.take_damage(200, "致命伤害")
	run.step(0, Vector2.ZERO, false)
	check(run.state == "dead" and combat.stats.hp == 0 and run.director.node_index == 5, "Simultaneous boss defeat and fatal damage cannot revive the player through node healing")
	check(run.result().bosses == 1 and run.result().death_source == "致命伤害", "Simultaneous defeat still records earned boss credit and the fatal cause")
	var store = Store.new()
	DirAccess.make_dir_recursive_absolute("res://builds/test-saves")
	store.path = "res://builds/test-saves/progression.json"
	var progress = store.defaults()
	progress.crystals = 25
	check(store.save_progress(progress) == OK, "Versioned progression save succeeds")
	progress.crystals = 40
	progress.unlocks.append("mage")
	progress.settings.control_scale = 1.1
	check(store.save_progress(progress) == OK, "Replacing existing save succeeds and retains backup")
	var restored = store.load_progress()
	check(restored.crystals == 40 and restored.unlocks.has("mage") and restored.settings.control_scale == 1.1, "Settings and unlocks survive reload")
	var file = FileAccess.open(store.path, FileAccess.WRITE)
	file.store_string("null")
	file.close()
	check(store.load_progress().crystals == 25, "Previous save recovers an unreadable primary document")
	if failures.is_empty():
		print("PASS: %d combat, build, node, persistence and touch checks" % checks)
	quit(0 if failures.is_empty() else 1)
