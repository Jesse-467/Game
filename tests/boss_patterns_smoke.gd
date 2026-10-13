extends SceneTree
## Verify readable escape routes, locked warning geometry and phase/save behavior.

const Catalog = preload("res://scripts/core/content_catalog.gd")
const Session = preload("res://scripts/core/run_session.gd")
const Patterns = preload("res://scripts/core/enemy_attack_patterns.gd")
var content: RefCounted
var failures: Array[String] = []
var checks = 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func fixture(id: String, node: int = 5) -> RefCounted:
	var run = Session.new(content)
	run.start("knight", 0, 42)
	run.director.node_index = node
	run.combat.spawn_enemy(id, Vector2(640, 335))
	run.combat.enemies[0].born = 0.0
	run.combat.player = Vector2(940, 335)
	return run

func run_checks() -> void:
	content = Catalog.new()
	content.load_content()
	for id in content.bosses:
		var definition: Dictionary = content.enemies[id]
		check(Patterns.boss_phase(definition, 0.51, 0).id == "opening", id + " opens with its original readable pattern")
		check(Patterns.boss_phase(definition, 0.5, 0).id == definition.phases[0].id, id + " changes at half health")
		check(Patterns.boss_phase(definition, 0.5, 1).id == definition.phases[1].id, id + " has a distinct repeat-rotation phase")
		var warnings_readable = true
		for phase in definition.phases:
			for action in phase.attacks:
				warnings_readable = warnings_readable and float(action.warning) >= 1.1 and float(action.interval) >= 3.8
		check(warnings_readable, id + " later complexity retains warning and recovery windows")
	var run = fixture("boss_ogre")
	for node in [5, 10, 15]:
		run.director.node_index = node
		check(run.director.boss_rotation_index() == 0, "The first three bosses use rotation zero at node%d" % node)
	run.director.node_index = 20
	check(run.director.boss_rotation_index() == 1, "The fourth boss begins the repeat rotation")
	run = fixture("boss_ogre")
	var enemy: Dictionary = run.combat.enemies[0]
	enemy.hp = enemy.max_hp * 0.5
	enemy.timer = 0.0
	run.combat.update_enemies(0.0)
	check(enemy.phase_id == "fracture" and enemy.telegraph == 0 and enemy.timer >= 0.8, "A phase change grants an extra preparation window")
	check(run.combat.events.size() == 1 and run.combat.events[0].type == "boss_phase", "A phase change produces a player-facing announcement")
	run.combat.update_enemies(0.1)
	check(run.combat.events.size() == 1, "The phase announcement is emitted once")
	enemy.timer = 0.0
	run.combat.update_enemies(0.0)
	var ring: Dictionary = run.combat.attack_telegraph(enemy)[0]
	check(enemy.active_attack.type == "shockwave" and ring.kind == "ring", "The warning uses the phase's first attack plan")
	check(not Patterns.hits(ring, ring.pos + Vector2(80, 0)), "The inner core remains safe from the shockwave")
	check(Patterns.hits(ring, ring.pos + Vector2(150, 0)), "The ring damages a player standing in its annulus")
	check(not Patterns.hits(ring, ring.pos + Vector2(220, 0)), "The outer escape route remains safe")
	check(not Patterns.hits(ring, ring.pos + Vector2(95, 0)) and Patterns.hits(ring, ring.pos + Vector2(96, 0)), "Ring collision accounts for the player's body radius at the inner edge")
	run.combat.player = ring.pos + Vector2(150, 0)
	run.combat.update_enemies(1.29)
	check(run.combat.stats.hp == 100, "Shockwave causes no area damage before its full warning expires")
	enemy.pos += Vector2(12, 0)
	run.combat.update_enemies(0.02)
	check(run.combat.stats.hp == 80 and run.combat.effects[-1].kind == "ring", "Resolution uses the locked ring plan even if the boss was displaced")
	check(run.combat.effects[-1].inner_radius == ring.inner_radius, "Impact presentation keeps the safe core visible")
	run = fixture("boss_wyrm", 30)
	enemy = run.combat.enemies[0]
	enemy.hp *= 0.4
	run.combat.update_enemies(0.0)
	enemy.timer = 0.0
	run.combat.update_enemies(0.0)
	var cluster = run.combat.attack_telegraph(enemy)
	check(cluster.size() == 5, "Repeat wyrm shows all five slam locations")
	check(cluster[0].pos == Vector2(840, 335) and cluster[4].pos == Vector2(940, 435), "Slam offsets lock to the original player position")
	run.combat.player = Vector2(1150, 200)
	check(run.combat.attack_telegraph(enemy) == cluster, "Moving after the warning cannot retarget the cluster")
	run.combat.update_enemies(1.41)
	check(run.combat.stats.hp == 100, "A player can leave the marked cluster without taking its damage")
	run = fixture("boss_wyrm")
	enemy = run.combat.enemies[0]
	enemy.active_attack = {"type": "slam", "radius": 55.0, "damage": 20.0, "offsets": [[0, 0], [20, 0]]}
	enemy.target = run.combat.player
	enemy.telegraph_shapes = Patterns.telegraph(enemy.pos, enemy.target, enemy.active_attack)
	var summons: Array[Dictionary] = []
	run.combat.resolve_attack(enemy, summons)
	check(run.combat.stats.hp == 80, "Overlapping slam circles respect immunity and cannot multiply a single impact")
	run = fixture("boss_lich", 25)
	enemy = run.combat.enemies[0]
	enemy.hp *= 0.4
	run.combat.update_enemies(0.0)
	enemy.timer = 0.0
	run.combat.update_enemies(0.0)
	var spokes = run.combat.attack_telegraph(enemy)
	check(spokes.size() == 10, "Repeat lich exposes all ten radial firing directions")
	run.combat.update_enemies(1.31)
	var directions_match = run.combat.projectiles.size() == 10
	for i in run.combat.projectiles.size():
		directions_match = directions_match and run.combat.projectiles[i].velocity.normalized().is_equal_approx(spokes[i].pos.direction_to(spokes[i].end))
	check(directions_match, "Radial bullets follow the exact warned directions")
	var gap_direction: Vector2 = spokes[0].pos.direction_to(spokes[0].end).rotated(PI / 10.0)
	check(absf(gap_direction.cross(run.combat.projectiles[0].velocity.normalized())) * 120.0 > 19.0, "A radial gap at 120px has room for the player's bullet collision body")
	enemy.active_attack = content.enemies.boss_lich.phases[1].attacks[1]
	enemy.telegraph_shapes = Patterns.telegraph(enemy.pos, run.combat.player, enemy.active_attack)
	summons.clear()
	run.combat.resolve_attack(enemy, summons)
	check(summons.size() == 4 and summons[0].id == "shaman" and summons[0].pos == enemy.telegraph_shapes[0].pos, "Summoned enemies use the warned spawn markers")
	enemy.active_attack = content.enemies.boss_lich.phases[1].attacks[2]
	enemy.telegraph_shapes = Patterns.telegraph(enemy.pos, run.combat.player, enemy.active_attack)
	var fan_plan: Array = enemy.telegraph_shapes.duplicate(true)
	enemy.pos += Vector2(12, 0)
	run.combat.projectiles.clear()
	run.combat.resolve_attack(enemy, summons)
	check(fan_plan.size() == 9 and run.combat.projectiles.size() == 9, "The fan warns and fires its full configured projectile count")
	var fan_matches = true
	for i in fan_plan.size():
		fan_matches = fan_matches and run.combat.projectiles[i].pos == fan_plan[i].pos and run.combat.projectiles[i].velocity.normalized().is_equal_approx(fan_plan[i].pos.direction_to(fan_plan[i].end))
	check(fan_matches, "Fan origin and directions remain locked even after boss displacement")
	enemy.erase("telegraph_shapes")
	check(run.combat.attack_telegraph(enemy).size() == 9, "Legacy pending fan attacks reconstruct every firing direction")
	run = fixture("boss_wyrm")
	enemy = run.combat.enemies[0]
	enemy.active_attack = content.enemies.boss_wyrm.attacks[0]
	enemy.target = run.combat.player
	enemy.telegraph = 0.5
	enemy.hp *= 0.4
	run.combat.update_enemies(0.1)
	check(not enemy.has("phase_id") and enemy.active_attack.radius == 105, "Crossing half health never interrupts an existing warning")
	run.combat.player = Vector2(1150, 200)
	run.combat.update_enemies(0.5)
	run.combat.update_enemies(0.01)
	check(enemy.phase_id == "ember_cluster", "The new phase begins after the old attack finishes")
	var legacy_plan = run.combat.attack_telegraph(enemy)
	check(legacy_plan.size() == 1 and legacy_plan[0].radius == 105, "A legacy v1 pending attack reconstructs its original warning plan")
	run = fixture("boss_ogre")
	enemy = run.combat.enemies[0]
	enemy.active_attack = content.enemies.boss_ogre.attacks[1]
	enemy.charge_left = 0.3
	enemy.pos = run.combat.player - Vector2(20, 0)
	run.combat.update_enemies(0.01)
	check(run.combat.stats.hp == 82, "Charge contact uses the attack's declared damage rather than idle contact damage")
	run = fixture("boss_wyrm", 30)
	enemy = run.combat.enemies[0]
	enemy.hp *= 0.4
	run.combat.update_enemies(0.0)
	enemy.timer = 0.0
	run.combat.update_enemies(0.0)
	run.combat.update_enemies(0.3)
	var saved = run.checkpoint()
	var restored = Session.new(content)
	check(restored.restore_checkpoint(saved) and restored.state == "paused", "A mid-warning checkpoint restores safely paused")
	check(restored.combat.attack_telegraph(restored.combat.enemies[0]) == run.combat.attack_telegraph(enemy), "The checkpoint preserves all locked warning geometry")
	check(restored.combat.enemies[0].phase_id == "ember_cluster_return" and restored.combat.enemies[0].telegraph == enemy.telegraph, "Phase identity and remaining warning time survive recovery")
	var old_save = saved.duplicate(true)
	old_save.combat.enemies[0].erase("telegraph_shapes")
	old_save.combat.enemies[0].erase("phase_id")
	check(restored.restore_checkpoint(old_save) and restored.combat.attack_telegraph(restored.combat.enemies[0]).size() == 5, "Existing schema v1 checkpoints remain loadable without new optional fields")
	run = fixture("boss_ogre")
	run.combat.damage_enemy(run.combat.enemies[0], 10000.0, false, 0.0)
	run.combat.update_enemies(0.0)
	check(run.combat.enemies.is_empty() and run.combat.events[-1].type == "kill", "A powerful build can defeat a boss directly without forced phase invulnerability")
	if failures.is_empty():
		print("PASS: %d boss phase, escape-route, warning geometry and checkpoint checks" % checks)
		quit(0)
	else:
		print("FAILED: %s" % failures)
		quit(1)
