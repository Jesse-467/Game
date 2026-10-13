extends Node2D
## Environment, actor scene instances and combat effects are presentation only.

const ActorScene = preload("res://scenes/actor_view.tscn")
const SpriteLibrary = preload("res://scripts/presentation/sprite_library.gd")
const World = preload("res://scripts/core/world_geometry.gd")
const ARENA = World.BOUNDS
var session: RefCounted
var input_controller: RefCounted
var library = SpriteLibrary.new()
var actor_views: Dictionary = {}
var hero_view: AnimatedSprite2D
var background: Texture2D
var font: Font
var movement = Vector2.ZERO
var camera: Camera2D
var field_textures: Array[AtlasTexture] = []

func configure(run: RefCounted, controls: RefCounted, ui_font: Font) -> void:
	session = run
	input_controller = controls
	font = ui_font
	background = load("res://assets/environment/world-floor.png")
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var atlas: Texture2D = load("res://assets/environment/field-atlas.png")
	for i in 8:
		var tile = AtlasTexture.new()
		tile.atlas = atlas
		tile.region = Rect2(Vector2(i % 4, int(i / 4)) * Vector2(atlas.get_width() / 4.0, atlas.get_height() / 2.0), Vector2(atlas.get_width() / 4.0, atlas.get_height() / 2.0))
		tile.filter_clip = true
		field_textures.append(tile)
	camera = Camera2D.new()
	camera.position = World.CENTER
	camera.limit_left = int(World.CAMERA_BOUNDS.position.x)
	camera.limit_top = int(World.CAMERA_BOUNDS.position.y)
	camera.limit_right = int(World.CAMERA_BOUNDS.end.x)
	camera.limit_bottom = int(World.CAMERA_BOUNDS.end.y)
	camera.position_smoothing_enabled = false
	add_child(camera)
	camera.make_current()

func reset_actor_views() -> void:
	for actor in actor_views.values():
		remove_child(actor)
		actor.queue_free()
	actor_views.clear()
	if hero_view:
		remove_child(hero_view)
		hero_view.queue_free()
	hero_view = ActorScene.instantiate()
	hero_view.configure(session.combat.character_id, library.frames_for(session.combat.character_id), 96.0)
	add_child(hero_view)

func sync() -> void:
	if session.combat.stats.is_empty():
		queue_redraw()
		return
	var combat: RefCounted = session.combat
	camera.position = World.camera_center(combat.player)
	camera.force_update_scroll()
	var frozen = session.state != "playing"
	var active: Dictionary = {}
	for enemy in combat.enemies:
		active[enemy.uid] = true
		if not actor_views.has(enemy.uid):
			var view = ActorScene.instantiate()
			view.configure(enemy.id, library.frames_for(enemy.id), 140.0 if enemy.kind == "boss" else (92.0 if enemy.kind == "elite" else 76.0))
			add_child(view)
			actor_views[enemy.uid] = view
		var action = "hurt" if enemy.hit_flash > 0 else ("attack" if enemy.telegraph > 0 or enemy.charge_left > 0 else ("idle" if enemy.born > 0 else "move"))
		actor_views[enemy.uid].present(enemy.pos, action, combat.player.x - enemy.pos.x, frozen, enemy.hit_flash > 0, int(enemy.hit_serial) if action == "hurt" else int(enemy.attack_index))
	for uid in actor_views.keys():
		if not active.has(uid):
			var actor = actor_views[uid]
			remove_child(actor)
			actor.queue_free()
			actor_views.erase(uid)
	if hero_view:
		var attacking = combat.attack_animation_left > 0
		var action = "hurt" if combat.hurt_timer > 0.35 and combat.dash_timer <= 0 else ("attack" if attacking else ("move" if movement.length() > 0.1 or combat.dash_timer > 0 else "idle"))
		var direction = combat.attack_direction.x if action == "attack" else combat.facing.x
		hero_view.present(combat.player, action, direction, frozen, combat.hurt_timer > 0 and combat.dash_timer <= 0, int(combat.hurt_serial) if action == "hurt" else int(combat.attack_serial))
	queue_redraw()

func _draw() -> void:
	if background:
		draw_texture_rect(background, ARENA, true)
		# The ancient ward marks the actual world edge, not the viewport edge.
		draw_rect(ARENA.grow(-9), Color("384f68"), false, 18)
		draw_rect(ARENA.grow(-19), Color(0.47, 0.73, 0.86, 0.6), false, 3)
	if not session or session.combat.stats.is_empty():
		return
	var combat: RefCounted = session.combat
	draw_arc(combat.player, 20, 0, TAU, 32, Color(0.5, 0.86, 0.98, 0.6), 2)
	draw_field(combat.field)
	for gem in combat.gems:
		var color = Color("76e7d0") if gem.value < 10 else Color("dbb4ff")
		draw_colored_polygon(PackedVector2Array([gem.pos + Vector2(0, -7), gem.pos + Vector2(5, 0), gem.pos + Vector2(0, 7), gem.pos + Vector2(-5, 0)]), color)
	for enemy in combat.enemies:
		draw_set_transform(enemy.pos, 0, Vector2(1, 0.40))
		draw_circle(Vector2.ZERO, enemy.radius, Color(0.04, 0.04, 0.08, 0.35))
		draw_set_transform(Vector2.ZERO)
		if enemy.telegraph > 0:
			var progress = 1.0 - float(enemy.telegraph) / float(enemy.active_attack.warning)
			for shape in combat.attack_telegraph(enemy):
				draw_attack_warning(shape, progress)
		if enemy.born > 0:
			draw_arc(enemy.pos, enemy.radius + 12, 0, TAU, 32, Color("f2d185"), 3)
		if enemy.hp < enemy.max_hp or enemy.kind != "normal":
			var bar = Rect2(enemy.pos + Vector2(-enemy.radius, -enemy.radius * 2.3), Vector2(enemy.radius * 2, 4))
			draw_rect(bar, Color("1b1727"))
			bar.size.x *= clampf(enemy.hp / enemy.max_hp, 0, 1)
			draw_rect(bar, Color("e8a075"))
	for shot in combat.projectiles:
		var color = Color("ef807c") if shot.hostile else Color(shot.color)
		draw_circle(shot.pos, 7 if shot.hostile else 5, color)
		draw_line(shot.pos - shot.velocity.normalized() * 16, shot.pos, color.lightened(0.15), 4)
	for effect in combat.effects:
		if effect.kind == "text":
			draw_string(font, effect.pos + Vector2(0, -20 * (0.65 - effect.life)), effect.text, HORIZONTAL_ALIGNMENT_CENTER, -1, 19, effect.color)
		elif effect.kind == "ring":
			var color: Color = effect.color
			color.a = clampf(effect.life * 2.0, 0, 0.7)
			draw_annulus(effect.pos, effect.inner_radius, effect.radius, color, 0.3)
		else:
			var opacity = clampf(effect.life * 2.0, 0, 0.6)
			var color: Color = effect.color
			color.a = opacity
			draw_arc(effect.pos, effect.radius * (1.1 - opacity * 0.4), 0, TAU, 40, color, 5)
			color.a *= 0.25
			draw_circle(effect.pos, effect.radius, color)

func draw_annulus(center: Vector2, inner: float, outer: float, color: Color, fill_alpha: float) -> void:
	var fill = color
	fill.a *= fill_alpha
	draw_arc(center, (inner + outer) * 0.5, 0, TAU, 64, fill, outer - inner)
	draw_arc(center, outer, 0, TAU, 64, color, 3)
	draw_arc(center, inner, 0, TAU, 64, color, 3)

func draw_attack_warning(shape: Dictionary, progress: float) -> void:
	var border = Color("ff896c")
	border.a = 0.65 + clampf(progress, 0, 1) * 0.35
	match shape.kind:
		"circle":
			var fill = border
			fill.a *= 0.18
			draw_circle(shape.pos, shape.radius, fill)
			draw_arc(shape.pos, shape.radius, 0, TAU, 48, border, 3)
			draw_arc(shape.pos, shape.radius * 0.9, -PI * 0.5, -PI * 0.5 + TAU * progress, 48, border, 2)
		"ring":
			draw_annulus(shape.pos, shape.inner_radius, shape.radius, border, 0.18)
			draw_arc(shape.pos, float(shape.inner_radius) - 18, 0, TAU, 48, Color("9bddb2"), 2)
			var text_position: Vector2 = shape.pos + Vector2(-36, 72)
			draw_string(font, text_position, "内圈避震", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("c0efcc"))
		"spawn":
			draw_arc(shape.pos, shape.radius, 0, TAU, 24, Color("d6a4fa"), 3)
			draw_line(shape.pos + Vector2(-10, 0), shape.pos + Vector2(10, 0), Color("d6a4fa"), 2)
			draw_line(shape.pos + Vector2(0, -10), shape.pos + Vector2(0, 10), Color("d6a4fa"), 2)
		"line":
			draw_line(shape.pos, shape.end, border, 3)
			var direction: Vector2 = shape.pos.direction_to(shape.end)
			draw_line(shape.end, shape.end - direction.rotated(0.5) * 14, border, 3)
			draw_line(shape.end, shape.end - direction.rotated(-0.5) * 14, border, 3)

func draw_field(field: RefCounted) -> void:
	if field.phase not in ["warning", "active"]:
		return
	var color = Color(field.definition.color)
	var active = field.phase == "active"
	for zone in field.zones:
		var index = int(field.definition.get("atlas_index", field.find_definition(field.definition.id).get("atlas_index", 0)))
		draw_texture_rect(field_textures[index], Rect2(zone.pos - Vector2.ONE * zone.radius, Vector2.ONE * zone.radius * 2), false, Color(1, 1, 1, 0.62 if active else 0.22))
		var fill = color
		fill.a = 0.17 if active else 0.06
		draw_circle(zone.pos, zone.radius, fill)
		var border = color
		border.a = 0.85 if active else 0.55
		draw_arc(zone.pos, zone.radius, 0, TAU, 48, border, 3)
		draw_arc(zone.pos, zone.radius * 0.78, 0, TAU, 48, border, 1)
		for i in 6:
			var angle = i * TAU / 6.0
			var direction = Vector2.from_angle(angle)
			draw_line(zone.pos + direction * zone.radius * 0.84, zone.pos + direction * zone.radius * 0.94, border, 3)
		var center: Vector2 = zone.pos
		if field.definition.id == "frost_ground":
			for i in 3:
				var direction = Vector2.from_angle(i * PI / 3.0)
				draw_line(center - direction * 17, center + direction * 17, border, 2)
		elif field.definition.id == "void_ground":
			draw_arc(center, 17, 0, TAU, 24, border, 2)
			draw_line(center + Vector2(-12, -12), center + Vector2(12, 12), border, 2)
		elif field.definition.id == "ember_ground":
			draw_polyline(PackedVector2Array([center + Vector2(-13, 10), center + Vector2(-4, -11), center + Vector2(1, -2), center + Vector2(8, -18), center + Vector2(14, 10)]), border, 2)
		elif field.definition.id in ["keen_ground", "blind_ground"]:
			draw_set_transform(center, 0, Vector2(1, 0.55))
			draw_arc(Vector2.ZERO, 18, 0, TAU, 32, border, 2)
			draw_set_transform(Vector2.ZERO)
			draw_circle(center, 5, border)
			if field.definition.id == "blind_ground":
				draw_line(center + Vector2(-18, 14), center + Vector2(18, -14), border, 2)
		else:
			for i in 3:
				draw_arc(center, 6 + i * 6, -PI * 0.8, PI * 0.8, 24, border, 2)
