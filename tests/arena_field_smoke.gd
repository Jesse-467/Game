extends SceneTree

const Catalog = preload("res://scripts/core/content_catalog.gd")
const Session = preload("res://scripts/core/run_session.gd")
var failures: Array[String] = []
var checks = 0

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func _initialize() -> void:
	call_deferred("run_checks")

func activate(field: RefCounted, node: int, center: Vector2) -> void:
	field.configure_node(node)
	field.definition = field.find_definition({3: "frost_ground", 6: "keen_ground", 9: "void_ground", 12: "control_ground", 15: "ember_ground", 18: "blind_ground"}[node])
	field.zones.clear()
	field.zones.append({"pos": center, "radius": 88.0})
	field.phase = "active"
	field.phase_left = 11.0

func run_checks() -> void:
	var content = Catalog.new()
	content.load_content()
	var run = Session.new(content)
	run.start("knight", 0, 44)
	var combat = run.combat
	var field = combat.field
	check(field.phase == "inactive", "First two nodes teach combat without terrain debuffs")
	field.configure_node(3)
	field.definition = field.find_definition("frost_ground")
	field.step(field.schedule.node_grace_seconds, combat.player)
	field.zones[0].id = "frost_ground"
	check(field.phase == "warning" and field.zones.size() >= 3, "Terrain appears with warning after its initial grace period")
	var center: Vector2 = field.zones[0].pos
	check(field.modifiers_at(center).move_multiplier == 1.0, "Warning terrain does not apply its debuff")
	field.step(field.schedule.warning_seconds, center)
	check(field.phase == "active" and field.modifiers_at(center).move_multiplier == 0.75, "Frost debuff starts after the full warning")
	combat.player = center
	combat.step(0.1, Vector2.RIGHT, false)
	check(is_equal_approx(combat.player.x - center.x, 17.25) and combat.stats.move_speed == 230.0, "Frost temporarily scales movement without altering base stats")
	check(run.dash() and combat.stats.pierce == 0, "Terrain leaves dodge and build mechanisms available")
	combat.step(0.1, Vector2.RIGHT, false)
	check(combat.player.x - center.x > 80, "Dodge retains its speed inside frost")
	combat.player = Vector2(100, 150)
	check(field.modifiers_at(combat.player).move_multiplier == 1.0, "Leaving frost immediately removes its effect")
	field.step(field.phase_left, center)
	check(field.phase == "recovery" and field.zones.is_empty(), "Active zones expire and provide a clear recovery window")
	run.start("knight", 0, 45)
	activate(field, 9, combat.player)
	combat.attack()
	check(is_equal_approx(combat.projectiles[0].damage, 8.4) and combat.stats.damage == 12.0, "Void weakens fired projectiles without erasing permanent damage upgrades")
	combat.spawn_enemy("skeleton", combat.player + Vector2(40, 0))
	combat.enemies[0].hp = 100
	combat.enemies[0].max_hp = 100
	run.cast_skill()
	check(is_equal_approx(combat.enemies[0].hp, 100.0 - 12.0 * 2.8 * 0.7 / 1.1), "Void and the target's defense both apply to the active skill")
	combat.player = Vector2(100, 150)
	combat.attack()
	check(is_equal_approx(combat.projectiles[-1].damage, 12.0) and is_equal_approx(combat.projectiles[0].damage, 8.4), "Leaving void restores new attacks; shots retain their launch strength")
	run.start("knight", 0, 46)
	activate(field, 15, combat.player)
	for i in 30: combat.step(1.0 / 60.0, Vector2.ZERO, false)
	check(combat.stats.hp == 100, "Ember exposure has no immediate damage burst")
	for i in 31: combat.step(1.0 / 60.0, Vector2.ZERO, false)
	check(combat.stats.hp == 94 and combat.terrain_damage_taken == 6, "Ember damages an exposed player once per second")
	var time_before = field.phase_left
	run.pause()
	run.step(3.0, Vector2.ZERO, false)
	check(field.phase_left == time_before and combat.stats.hp == 94, "Upgrade or pause suspends terrain timers and damage")
	run.start("knight", 0, 47)
	check(field.phase == "inactive" and combat.terrain_damage_taken == 0, "Retry clears terrain and its damage counters")
	for id in ["multishot", "pierce", "frost", "blast", "crit", "execution", "cooldown"]:
		combat.stats = run.upgrades.apply(id, combat.stats)
	check(run.upgrades.stacks.size() == 7 and combat.stats.projectile_count == 2 and combat.stats.blast_fraction > 0 and combat.stats.slow_fraction > 0, "All mechanisms can coexist without rune-slot restrictions")
	run.start("knight", 0, 48)
	combat.stats.crit_chance = 0.12
	activate(field, 6, combat.player)
	combat.attack()
	check(is_equal_approx(combat.projectiles[0].crit_chance, 0.37) and is_equal_approx(combat.stats.crit_chance, 0.12), "Keen ground adds 25 percentage points without rewriting build crit chance")
	activate(field, 18, combat.player)
	combat.attack()
	check(combat.projectiles[-1].crit_chance == 0, "Blind ground can reduce effective crit chance to zero but never below zero")
	combat.stats.crit_chance = 0.95
	activate(field, 6, combat.player)
	combat.attack()
	check(combat.projectiles[-1].crit_chance == 1.0, "Terrain crit bonuses are bounded by 100 percent")
	run.start("mage", 0, 49)
	activate(field, 12, combat.player)
	combat.attack()
	combat.spawn_enemy("skeleton", combat.player + Vector2(35, 0))
	combat.enemies[0].born = 0
	combat.update_projectiles(0.05)
	check(is_equal_approx(combat.enemies[0].slow_timer, 1.8), "Resonance extends the mage's projectile control duration by 50 percent")
	run.cast_skill()
	check(is_equal_approx(combat.enemies[0].slow_timer, 3.6), "Resonance extends the frost active skill using the same rule")
	combat.damage_enemy(combat.enemies[0], 1.0)
	check(is_equal_approx(combat.enemies[0].slow, 0.55) and is_equal_approx(combat.enemies[0].slow_timer, 3.6), "Weaker normal attacks do not cancel a stronger active control effect")
	for node in [3, 6, 9, 12, 20, 100]:
		field.configure_node(node)
		field.prepare_zones()
		var occupied_bound = 0.0
		for zone in field.zones: occupied_bound += PI * zone.radius * zone.radius
		check(occupied_bound <= preload("res://scripts/core/world_geometry.gd").VIEW_SIZE.x * preload("res://scripts/core/world_geometry.gd").VIEW_SIZE.y * 0.38 + 0.1, "Node %d terrain preserves at least62 percent clear visible space" % node)
	if failures.is_empty(): print("PASS: %d terrain, freedom-of-build and safety-window checks" % checks)
	quit(0 if failures.is_empty() else 1)
