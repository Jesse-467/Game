extends RefCounted
## Each finger owns an action; GUI mouse emulation never clears touch-held attack.

var joystick_center = Vector2(160, 610)
var joystick_radius = 72.0
var joystick_region = Rect2(0, 450, 400, 270)
const Layout = preload("res://scripts/input/control_layout.gd")
var attack_rect = Layout.ATTACK
var skill_rect = Layout.SKILL
var dash_rect = Layout.DASH
var joystick_touch = -1
var attack_touch = -1
var joystick_vector = Vector2.ZERO
var mouse_joystick = false
var mouse_attack = false
var commands: Array[String] = []

func clear() -> void:
	joystick_touch = -1
	attack_touch = -1
	joystick_vector = Vector2.ZERO
	mouse_joystick = false
	mouse_attack = false
	commands.clear()

func handle(event: InputEvent, playing: bool) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_ESCAPE, KEY_P]:
			commands.append("pause")
		elif playing and event.physical_keycode == KEY_SPACE:
			commands.append("dash")
		elif playing and event.physical_keycode == KEY_K:
			commands.append("skill")
	if event is InputEventScreenTouch:
		if not event.pressed:
			if event.index == joystick_touch:
				joystick_touch = -1
				joystick_vector = Vector2.ZERO
				return true
			if event.index == attack_touch:
				attack_touch = -1
				return true
		elif playing:
			if Layout.circle_contains(attack_rect, event.position):
				attack_touch = event.index
				return true
			if Layout.circle_contains(skill_rect, event.position):
				commands.append("skill")
				return true
			if Layout.circle_contains(dash_rect, event.position):
				commands.append("dash")
				return true
			if joystick_region.has_point(event.position) and joystick_touch == -1:
				joystick_touch = event.index
				joystick_vector = ((event.position - joystick_center) / joystick_radius).limit_length()
				return true
	elif event is InputEventScreenDrag and playing:
		if event.index == joystick_touch:
			joystick_vector = ((event.position - joystick_center) / joystick_radius).limit_length()
			return true
		# A choice menu clears intent, but the physical finger can remain on screen.
		# Fresh dragging resumes control without requiring the player to lift it.
		if joystick_touch == -1 and event.index != attack_touch and joystick_region.has_point(event.position):
			joystick_touch = event.index
			joystick_vector = ((event.position - joystick_center) / joystick_radius).limit_length()
			return true
		if attack_touch == -1 and event.index != joystick_touch and Layout.circle_contains(attack_rect, event.position):
			attack_touch = event.index
			return true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != -1:
		if not event.pressed:
			mouse_joystick = false
			mouse_attack = false
			if joystick_touch == -1:
				joystick_vector = Vector2.ZERO
		elif playing and joystick_region.has_point(event.position):
			mouse_joystick = true
			joystick_vector = ((event.position - joystick_center) / joystick_radius).limit_length()
			return true
	elif event is InputEventMouseMotion and mouse_joystick and event.device != -1:
		joystick_vector = ((event.position - joystick_center) / joystick_radius).limit_length()
		return true
	return false

func movement() -> Vector2:
	if joystick_vector.length() > 0.1:
		return joystick_vector
	var x = float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	var y = float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	return Vector2(x, y).limit_length()

func attacking() -> bool:
	return attack_touch != -1 or mouse_attack or Input.is_physical_key_pressed(KEY_J)
