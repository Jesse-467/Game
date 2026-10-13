extends RefCounted
## One GPU texture per actor; 16 AtlasTexture regions share it across all instances.

const ANIMATIONS = ["idle", "move", "attack", "hurt"]
const FPS = [5.0, 9.0, 12.0, 12.0]
var cache: Dictionary = {}

func frames_for(id: String) -> SpriteFrames:
	if cache.has(id):
		return cache[id]
	var path = "res://assets/animations/%s.png" % id
	if not ResourceLoader.exists(path):
		push_error("Missing production animation sheet: " + path)
		return null
	var texture: Texture2D = load(path)
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/animations/%s.json" % id))
	var ratio = texture.get_size() / Vector2(metadata.source_size[0], metadata.source_size[1])
	var canvas_side = float(metadata.virtual_canvas) * ratio.x
	var canvas = Vector2.ONE * canvas_side
	var frames = SpriteFrames.new()
	frames.remove_animation("default")
	for row in 4:
		var animation: String = ANIMATIONS[row]
		frames.add_animation(animation)
		frames.set_animation_speed(animation, FPS[row])
		frames.set_animation_loop(animation, row < 2)
		for column in 4:
			var bounds: Array = metadata.regions[row * 4 + column]
			var region = AtlasTexture.new()
			region.atlas = texture
			region.region = Rect2(Vector2(bounds[0], bounds[1]) * ratio, Vector2(bounds[2], bounds[3]) * ratio)
			var margin_offset = Vector2((canvas_side - region.region.size.x) / 2, canvas_side * float(metadata.foot_baseline_fraction) - region.region.size.y)
			region.margin = Rect2(margin_offset, canvas - region.region.size)
			region.filter_clip = true
			frames.add_frame(animation, region)
	cache[id] = frames
	return frames
