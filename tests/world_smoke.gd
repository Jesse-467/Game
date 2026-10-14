extends SceneTree
## World/camera, arrival sampling, timed terrain, circular input and pacing contracts.

const World = preload("res://scripts/core/world_geometry.gd")
const Catalog = preload("res://scripts/core/content_catalog.gd")
const Session = preload("res://scripts/core/run_session.gd")
const Sampler = preload("res://scripts/core/spawn_sampler.gd")
const Field = preload("res://scripts/core/arena_field.gd")
const Layout = preload("res://scripts/input/control_layout.gd")
const Snapshot = preload("res://scripts/core/run_snapshot.gd")

class TestGame extends "res://scripts/main.gd":
	func create_active_store() -> RefCounted:
		return preload("res://tests/support/memory_run_store.gd").new()
	func load_progress() -> void: meta = progression_store.defaults()
	func save_progress() -> bool: return true

var failures: Array[String] = []
var checks = 0

func _initialize() -> void:
	Engine.max_fps = 60
	call_deferred("run_checks")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func run_checks() -> void:
	var content = Catalog.new()
	content.load_content()
	var run = Session.new(content)
	run.start("knight", 0, 42)
	check(World.BOUNDS.size.x > World.VIEW_SIZE.x * 2 and World.BOUNDS.size.y > World.VIEW_SIZE.y * 2, "World is substantially larger than one screen")
	run.combat.player = World.CENTER + Vector2(1100, 0)
	run.combat.step(1.0, Vector2.RIGHT, false)
	check(run.combat.player.x > 3000, "Moving past the old viewport edge does not stop the hero")
	run.combat.player = Vector2(60, 60)
	run.combat.step(2.0, Vector2(-1, -1), false)
	check(run.combat.player == Vector2.ONE * World.PLAYER_MARGIN, "Only actual world bounds stop movement")
	var a = Sampler.new()
	var b = Sampler.new()
	var random_a = RandomNumberGenerator.new()
	var random_b = RandomNumberGenerator.new()
	random_a.seed = 901
	random_b.seed = 901
	var directions: Dictionary = {}
	var sampling_valid = true
	var replay_equal = true
	var empty_enemies: Array[Dictionary] = []
	for anchor in [World.CENTER, Vector2(48, 48), Vector2(3552, 2352), Vector2(48, 1200), Vector2(1800, 2352)]:
		for i in 200:
			var point = a.sample(anchor, 38, random_a, empty_enemies, content.balance.difficulty)
			var other = b.sample(anchor, 38, random_b, empty_enemies, content.balance.difficulty)
			replay_equal = replay_equal and point == other
			if point == Vector2.INF:
				sampling_valid = false
				continue
			var distance: float = point.distance_to(anchor)
			sampling_valid = sampling_valid and World.BOUNDS.has_point(point) and World.spawn_screen_allowed(point - World.visible_rect(anchor).position) and distance >= 239.99 and distance <= 470.01
			if anchor == World.CENTER: directions[a.last_sector] = true
	check(sampling_valid, "1000 arrivals at center and map edges remain visible, outside safe distance and clear of controls")
	check(replay_equal, "Arrival positions are reproducible from seed and sector bag state")
	check(directions.size() >= 8, "Arrival directions vary across the available screen sectors")
	var field = Field.new()
	field.load_content()
	field.reset(991)
	field.configure_node(3)
	var ids: Array[String] = []
	var durations: Array[float] = []
	for i in 24:
		field.step(field.phase_left, World.CENTER)
		check(field.phase == "warning" and field.modifiers_at(World.CENTER).attack_interval_multiplier == 1, "Terrain cycle%d advertises before applying effects" % i)
		field.step(field.phase_left, World.CENTER)
		ids.append(field.definition.id)
		durations.append(field.phase_left)
		var before = field.phase_left
		field.configure_node(field.node_index + 1)
		check(field.phase == "active" and field.phase_left == before, "Node advance does not reset terrain cycle%d" % i)
		field.step(field.phase_left, World.CENTER)
	var bag_unique = true
	for block in 3:
		var unique: Dictionary = {}
		for i in range(block * 8, block * 8 + 8): unique[ids[i]] = true
		bag_unique = bag_unique and unique.size() == 8
	var shown: Dictionary = {}
	for id in ids: shown[id] = true
	check(shown.size() == 8, "Mixed terrain cycles expose all eight primary types over the sample")
	var no_repeats = true
	for i in range(1, ids.size()): no_repeats = no_repeats and ids[i] != ids[i - 1]
	check(field.type_bag.size() <= 8, "Terrain type bags remain bounded while mixed cycles consume several types")
	check(durations.min() >= 32 and durations.max() <= 48 and durations.min() != durations.max(), "Terrain duration varies within the advertised tens-of-seconds range")
	var cells: Array[int] = []
	field.spatial_bag.clear()
	for i in 18: cells.append(field.take_cell())
	var spatial_fair = true
	for block in 2:
		var unique: Dictionary = {}
		for i in range(block * 9, block * 9 + 9): unique[cells[i]] = true
		spatial_fair = spatial_fair and unique.size() == 9
	check(spatial_fair, "Spatial bags visit all nine grid regions before reusing a region")
	var counts: Dictionary = {}
	var radii: Dictionary = {}
	var coverage_valid = true
	field.node_index = 20
	for anchor in [World.CENTER, Vector2(48, 48), Vector2(3552, 2352)]:
		for i in 30:
			field.prepare_zones(anchor)
			var area = 0.0
			counts[field.zones.size()] = true
			for zone in field.zones:
				area += PI * zone.radius * zone.radius
				radii[roundi(zone.radius)] = true
				coverage_valid = coverage_valid and World.BOUNDS.has_point(zone.pos)
			coverage_valid = coverage_valid and area <= World.visible_rect(anchor).intersection(World.BOUNDS).get_area() * 0.38 + 0.1
	check(coverage_valid and counts.size() >= 2 and radii.size() >= 10, "Zone positions, count and size vary while leaving most visible map space clear")
	run.start("knight", 0, 55)
	run.combat.field.configure_node(3)
	run.combat.field.definition = run.combat.field.find_definition("fury_ground")
	run.combat.field.zones.assign([{"pos": run.combat.player, "radius": 130.0}])
	run.combat.field.phase = "active"
	run.combat.attack()
	check(is_equal_approx(run.combat.attack_timer, 0.52) and run.combat.stats.attack_interval == 0.65, "Fury changes current attack interval without changing permanent growth")
	run.combat.field.definition = run.combat.field.find_definition("ward_ground")
	run.combat.take_damage(20)
	check(run.combat.stats.hp == 85 and run.combat.damage_taken == 15, "Ward reduces real incoming damage by25 percent")
	run.start("knight", 0, 56)
	run.combat.spawn_enemy("slime", run.combat.player + Vector2(20, 0))
	run.combat.attack()
	run.combat.update_projectiles(0.05)
	run.combat.update_enemies(0.2)
	check(run.combat.enemies[0].hp == float(content.enemies.slime.hp) - 12 and run.combat.stats.hp == 100, "Players can hit arrivals while the arrival warning still prevents enemy attacks")
	check(Layout.circle_contains(Layout.ATTACK, Layout.ATTACK.get_center()) and not Layout.circle_contains(Layout.ATTACK, Layout.ATTACK.position), "Circular controls accept their centers and reject rectangle corners")
	run.director.node_index = 3
	run.director.node_time = 4
	var recovery = run.director.population_multiplier()
	run.director.node_time = 29
	var peak = run.director.population_multiplier()
	run.director.node_time = 37
	check(recovery > peak and run.director.population_multiplier() > peak and run.director.pacing_name() == "喘息", "Each normal node builds pressure then offers a recovery interval")
	run.director.node_index = 5
	check(run.director.population_multiplier() > recovery, "Boss encounters reduce background mob pressure")
	var legacy = run.checkpoint()
	legacy.schema_version = 1
	legacy.field = {"zones": [{"pos": Vector2(700, 335), "radius": 88.0}], "definition": run.combat.field.definition, "phase": "active", "phase_left": 4.0, "node_index": 5, "burn_exposure": 0.0}
	legacy.erase("spawn_sampler")
	legacy.combat.player = Vector2(640, 335)
	legacy.combat.enemies.clear()
	legacy.combat.projectiles.clear()
	legacy.combat.gems.clear()
	legacy.combat.effects.clear()
	var migrated = Snapshot.normalize(legacy)
	check(migrated.schema_version == 3 and migrated.combat.player == World.CENTER and migrated.field.zones[0].pos == World.CENTER + Vector2(60, 0), "Legacy checkpoints translate relative geometry into the expanded world")
	check(run.restore_checkpoint(legacy) and run.state == "paused" and run.combat.field.phase_left == 4.0, "Legacy recovery retains the run and pending terrain time")
	root.size = Vector2i(1280, 720)
	var game = TestGame.new()
	root.add_child(game)
	game.set_physics_process(false)
	game.start_run()
	check(game.battle_view.background.get_width() == 512, "World ground uses the mobile512px import size")
	check(game.battle_view.field_textures.size() == 8 and game.battle_view.field_textures[0].atlas.get_width() == 1024, "Eight terrain states share a single mobile1024px atlas")
	await create_timer(0.05).timeout
	for point in [World.CENTER, World.CENTER + Vector2(650, 400)]:
		game.session.combat.player = point
		game.battle_view.sync()
		await process_frame
		var screen = game.battle_view.get_global_transform_with_canvas() * point
		check(screen.distance_to(World.VIEW_SIZE * 0.5) < 1.0, "Actual Camera2D centers the player while inside map boundaries")
	game.session.combat.player = Vector2(3552, 2352)
	game.battle_view.sync()
	await process_frame
	check(game.battle_view.camera.position == World.camera_center(game.session.combat.player), "Actual camera stops at the true map boundary")
	check(game.game_ui.attack_button.get_global_rect() == Layout.ATTACK and game.game_ui.joystick_view.get_global_transform_with_canvas().origin == Vector2.ZERO, "Camera movement does not move combat buttons or joystick")
	game.session.combat.spawn_enemy("boss_ogre", game.session.combat.player - Vector2(200, 0))
	game.session.combat.enemies[-1].hp *= 0.5
	game.game_ui.sync(game.session, 0)
	check(game.game_ui.boss_bar.visible and is_equal_approx(game.game_ui.boss_bar.value, 50), "Boss HUD shows actual health independently of camera location")
	game.session.combat.enemies[-1].pos = World.CENTER
	game.game_ui.sync(game.session, 0)
	check(game.game_ui.boss_label.text.contains("西北方") and game.game_ui.boss_bar.visible, "An offscreen boss retains its health bar and a direction hint")
	game.audio_service.music.stop()
	await create_timer(0.1).timeout
	game.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	if failures.is_empty(): print("PASS: %d expanded-world, camera, spawn, terrain, controls and pacing checks" % checks)
	quit(0 if failures.is_empty() else 1)
