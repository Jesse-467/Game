extends Button
## Final code-drawn circular controls, including circular hit regions and cooldown arcs.

var action_icon = "attack"
var cooldown_fraction = 0.0

func _get_minimum_size() -> Vector2:
	return Vector2.ZERO

func _ready() -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color"]:
		add_theme_color_override(key, Color.TRANSPARENT)
	resized.connect(queue_redraw)

func _has_point(point: Vector2) -> bool:
	return preload("res://scripts/input/control_layout.gd").circle_contains(Rect2(Vector2.ZERO, size), point)

func _draw() -> void:
	var center = size * 0.5
	var radius = minf(size.x, size.y) * 0.5 - 2
	var base = Color("253847")
	if button_pressed: base = Color("695632")
	elif is_hovered(): base = Color("385060")
	if disabled: base = Color("192c38")
	draw_circle(center + Vector2(0, 3), radius, Color(0, 0, 0, 0.3))
	draw_circle(center, radius, base)
	draw_arc(center, radius - 1, 0, TAU, 64, Color("bdab80") if not disabled else Color("607385"), 2, true)
	draw_arc(center, radius - 7, 0, TAU, 64, Color("41596a"), 1, true)
	if cooldown_fraction > 0:
		draw_arc(center, radius - 3, -PI * 0.5, -PI * 0.5 + TAU * cooldown_fraction, 64, Color("e4c77e"), 4, true)
	var icon_center = center + Vector2(0, -12)
	var ink = Color("a9bbc2") if disabled else Color("f1dab2")
	if action_icon == "attack":
		draw_polyline(PackedVector2Array([icon_center + Vector2(-13, 13), icon_center + Vector2(13, -13), icon_center + Vector2(18, -18), icon_center + Vector2(15, -6), icon_center + Vector2(-9, 17)]), ink, 3, true)
		draw_line(icon_center + Vector2(-15, 4), icon_center + Vector2(-2, 17), ink, 3, true)
	elif action_icon == "skill":
		draw_arc(icon_center, 14, 0, TAU, 32, ink, 2, true)
		for i in 4:
			var direction = Vector2.from_angle(i * PI * 0.5)
			draw_line(icon_center + direction * 5, icon_center + direction * 19, ink, 2, true)
	else:
		for i in 2:
			var start = icon_center + Vector2(i * 12 - 13, 0)
			draw_polyline(PackedVector2Array([start + Vector2(-6, -9), start + Vector2(4, 0), start + Vector2(-6, 9)]), ink, 3, true)
	var font = get_theme_font("font")
	var lines = text.split("\n")
	for i in lines.size():
		var font_size = 16 if size.x < 120 else 18
		var width = font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, Vector2(center.x - width * 0.5, center.y + 20 + i * 19), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("f5ead8") if not disabled else Color("a6b6be"))
