extends AnimatedSprite2D
## Animation priorities mirror combat intent; hit feedback never changes simulation.

var actor_id = ""
var current_action = ""
var last_epoch = -1
var was_frozen = false

func configure(id: String, frames: SpriteFrames, display_size: float) -> void:
	actor_id = id
	sprite_frames = frames
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if frames:
		var size = frames.get_frame_texture("idle", 0).get_size()
		scale = Vector2.ONE * display_size / maxf(size.x, size.y)
		offset = Vector2(0, -size.y * 0.38)
		play("idle")

func present(pos: Vector2, action: String, direction: float, frozen: bool, flashing: bool, epoch: int = 0) -> void:
	position = pos
	flip_h = direction < -0.05
	z_index = int(pos.y)
	modulate = Color(1.3, 1.1, 1.0) if flashing else Color.WHITE
	if (action != current_action or (action in ["attack", "hurt"] and epoch != last_epoch)) and sprite_frames:
		current_action = action
		last_epoch = epoch
		stop()
		play(action)
	if frozen:
		pause()
	elif was_frozen or (not is_playing() and action in ["idle", "move"]):
		play(action)
	was_frozen = frozen
