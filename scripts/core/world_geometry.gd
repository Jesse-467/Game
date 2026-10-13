extends RefCounted
## World coordinates are independent of the fixed logical HUD viewport.

const BOUNDS = Rect2(0, 0, 3600, 2400)
const VIEW_SIZE = Vector2(1280, 720)
const CAMERA_BOUNDS = Rect2(0, -132, 3600, 2694)
const CENTER = Vector2(1800, 1200)
const PLAYER_MARGIN = 48.0
const SPAWN_SCREEN = Rect2(44, 132, 1192, 462)

static func camera_center(player: Vector2) -> Vector2:
	return player.clamp(CAMERA_BOUNDS.position + VIEW_SIZE * 0.5, CAMERA_BOUNDS.end - VIEW_SIZE * 0.5)

static func visible_rect(player: Vector2) -> Rect2:
	return Rect2(camera_center(player) - VIEW_SIZE * 0.5, VIEW_SIZE)

static func spawn_screen_allowed(point: Vector2) -> bool:
	if not SPAWN_SCREEN.has_point(point): return false
	# Keep arrivals clear of the screen's touch controls.
	if Rect2(0, 450, 380, 270).has_point(point): return false
	if Rect2(1080, 430, 200, 290).has_point(point): return false
	return true
