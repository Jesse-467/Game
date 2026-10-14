extends SceneTree
## Exercise actual warnings, combined resolutions, escape paths and checkpoint states.
const Catalog = preload("res://scripts/core/content_catalog.gd")
const Session = preload("res://scripts/core/run_session.gd")
const Patterns = preload("res://scripts/core/enemy_attack_patterns.gd")
const World = preload("res://scripts/core/world_geometry.gd")
var content: RefCounted
var checks = 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run_checks")
func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		push_error(description)

func fixture(id: String, node: int = 5) -> RefCounted:
	var run = Session.new(content)
	run.start("knight", 0, 42)
	run.director.node_index = node
	run.combat.spawn_enemy(id, World.CENTER)
	run.combat.enemies[0].born = 0
	run.combat.player = World.CENTER + Vector2(300, 0)
	return run

func run_checks() -> void:
	content = Catalog.new()
	content.load_content()
	for id in content.bosses:
		var definition: Dictionary = content.enemies[id]
		check(Patterns.boss_phase(definition, 0.66, 0).id == "opening", id + " retains its opening above65% health")
		check(Patterns.boss_phase(definition, 0.5, 0).id == definition.phases[0].id, id + " enters a distinct pressure phase")
		check(Patterns.boss_phase(definition, 0.5, 1).id == definition.phases[1].id, id + " changes the pressure pattern in repeat rotations")
		check(Patterns.boss_phase(definition, 0.24, 0).id == definition.phases[-1].id, id + " has a third rage phase")
		var readable = true
		var combinations = 0
		for phase in definition.phases:
			for action in phase.attacks:
				readable = readable and float(action.warning) >= 0.8 and float(action.interval) >= 2.0
				if action.type == "combo": combinations += 1
		check(readable and combinations >= 2, id + " combines threats with visible preparation and recovery")
		check(float(definition.hp) >= 1000 and float(definition.damage) >= 27, id + " has the strengthened baseline rather than the old low-health encounter")
	var run = fixture("boss_ogre")
	var enemy: Dictionary = run.combat.enemies[0]
	enemy.hp *= 0.5
	enemy.timer = 0
	run.combat.update_enemies(0)
	check(enemy.phase_id == "fracture" and enemy.timer >= 0.8 and enemy.telegraph == 0, "Phase entry grants extra preparation before combined threats")
	check(run.combat.events.size() == 1 and run.combat.events[0].type == "boss_phase", "Phase change emits one visible announcement")
	enemy.timer = 0
	run.combat.update_enemies(0)
	var plan: Array = run.combat.attack_telegraph(enemy).duplicate(true)
	var ring: Dictionary = plan[0]
	check(enemy.active_attack.type == "combo" and ring.kind == "ring" and plan.size() == 8, "Ogre warns both a shockwave ring and its seven fan rays")
	check(not Patterns.hits(ring, ring.pos + Vector2(70, 0)), "Shockwave retains a safe inner core")
	check(Patterns.hits(ring, ring.pos + Vector2(150, 0)), "Shockwave annulus is hazardous")
	check(not Patterns.hits(ring, ring.pos + Vector2(245, 0)), "Shockwave retains an outer escape route")
	run.combat.player = ring.pos + Vector2(150, 0)
	run.combat.update_enemies(1.0)
	check(run.combat.stats.hp == 100 and run.combat.projectiles.is_empty(), "Combined warning does not apply damage before it finishes")
	enemy.pos += Vector2(12, 0)
	run.combat.update_enemies(0.06)
	check(is_equal_approx(run.combat.stats.hp, 100.0 - 32.0 * float(enemy.damage_scale)) and run.combat.effects[-1].pos == ring.pos, "Combined shockwave resolves scaled damage at its original warned origin after displacement")
	check(run.combat.projectiles.size() == 7, "Combined fan resolves all seven projectiles")
	var matching = true
	for i in 7:
		var shape: Dictionary = plan[i + 1]
		var shot: Dictionary = run.combat.projectiles[i]
		matching = matching and shot.pos == shape.pos and shot.velocity.normalized().is_equal_approx(shape.pos.direction_to(shape.end))
	check(matching, "Combined projectile origin and directions match the original warning")
	run = fixture("boss_wyrm", 30)
	enemy = run.combat.enemies[0]
	enemy.hp *= 0.4
	run.combat.update_enemies(0)
	enemy.timer = 0
	run.combat.update_enemies(0)
	plan = run.combat.attack_telegraph(enemy).duplicate(true)
	var circles = plan.filter(func(shape): return shape.kind == "circle")
	check(circles.size() == 5 and plan.size() == 19, "Repeat wyrm warns five slam locations and fourteen radial directions")
	run.combat.player += Vector2(0, -250)
	check(run.combat.attack_telegraph(enemy) == plan, "Movement after warning cannot retarget the attack cluster")
	run.combat.update_enemies(1.21)
	check(run.combat.stats.hp == 100, "Leaving the marked cluster avoids its direct area damage")
	run = fixture("boss_lich", 25)
	enemy = run.combat.enemies[0]
	enemy.hp *= 0.4
	run.combat.update_enemies(0)
	enemy.timer = 0
	run.combat.update_enemies(0)
	plan = run.combat.attack_telegraph(enemy).duplicate(true)
	check(plan.size() == 17 and plan[-1].kind == "circle", "Repeat lich warns sixteen radial rays and a persistent danger area")
	run.combat.update_enemies(1.06)
	check(run.combat.projectiles.size() == 16 and run.combat.hazards.size() == 1, "The warned combination creates both bullets and a timed danger area")
	var hazard: Dictionary = run.combat.hazards[0]
	run.combat.player = hazard.pos
	run.combat.update_hazards(0.5)
	check(run.combat.stats.hp == 100, "Persistent area grants time before its first damage tick")
	run.combat.update_hazards(0.36)
	check(is_equal_approx(run.combat.stats.hp, 100.0 - float(hazard.damage)), "Persistent area deals its declared first tick")
	enemy.active_attack = content.enemies.boss_lich.phases[1].attacks[1]
	enemy.target = run.combat.player
	enemy.telegraph_shapes = Patterns.telegraph(enemy.pos, enemy.target, enemy.active_attack)
	var summons: Array[Dictionary] = []
	run.combat.resolve_attack(enemy, summons)
	check(summons.size() == 3 and summons[0].id == "shaman" and summons[0].pos == enemy.telegraph_shapes[0].pos, "Summons appear at their warned markers")
	run = fixture("boss_ogre")
	enemy = run.combat.enemies[0]
	enemy.active_attack = content.enemies.boss_ogre.attacks[1]
	enemy.charge_left = 0.3
	enemy.pos = run.combat.player - Vector2(20, 0)
	run.combat.update_enemies(0.01)
	check(is_equal_approx(run.combat.stats.hp, 100.0 - 32.0 * float(enemy.damage_scale)), "Charge contact uses scaled attack damage rather than idle contact damage")
	run = fixture("boss_wyrm", 30)
	enemy = run.combat.enemies[0]
	enemy.hp *= 0.4
	run.combat.update_enemies(0)
	enemy.timer = 0
	run.combat.update_enemies(0)
	run.combat.update_enemies(0.3)
	var saved = run.checkpoint()
	var restored = Session.new(content)
	check(restored.restore_checkpoint(saved) and restored.state == "paused", "Combined mid-warning checkpoint restores paused")
	check(restored.combat.attack_telegraph(restored.combat.enemies[0]) == run.combat.attack_telegraph(enemy), "Checkpoint preserves every combined warning shape")
	check(restored.combat.enemies[0].phase_id == "ember_cluster_return" and restored.combat.enemies[0].telegraph == enemy.telegraph, "Checkpoint preserves phase identity and remaining warning")
	var legacy = enemy.duplicate(true)
	legacy.active_attack = {"type":"slam", "radius":105.0, "damage":26.0}
	legacy.erase("telegraph_shapes")
	check(run.combat.attack_telegraph(legacy).size() == 1 and run.combat.attack_telegraph(legacy)[0].radius == 105, "Legacy simple pending attacks reconstruct their original geometry")
	run = fixture("boss_ogre")
	run.combat.damage_enemy(run.combat.enemies[0], 100000, false, 0)
	run.combat.update_enemies(0)
	check(run.combat.enemies.is_empty(), "Strong builds can kill a boss without forced invulnerability or phase gates")
	if failures.is_empty(): print("PASS: %d boss phase, combination, hazard, escape and checkpoint checks" % checks)
	quit(0 if failures.is_empty() else 1)
