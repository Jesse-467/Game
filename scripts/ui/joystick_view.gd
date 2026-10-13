extends Node2D
var controls: RefCounted
var active = false

func _draw() -> void:
	if not controls or not active: return
	var center: Vector2 = controls.joystick_center
	var radius: float = controls.joystick_radius
	draw_circle(center, radius, Color(0.14, 0.24, 0.3, 0.65))
	draw_arc(center, radius, 0, TAU, 48, Color("8bafb8"), 2, true)
	draw_circle(center + controls.joystick_vector * radius * 0.7, radius * 0.36, Color("789aa8"))
