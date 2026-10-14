extends RefCounted
## Eight atlas regions share one mobile-sized texture.
var textures: Array[AtlasTexture] = []

func texture(index: int) -> Texture2D:
	if textures.is_empty():
		var atlas: Texture2D = load("res://assets/items/loot-atlas.png")
		var cell = Vector2(atlas.get_width() / 4.0, atlas.get_height() / 2.0)
		for i in 8:
			var tile = AtlasTexture.new()
			tile.atlas = atlas
			tile.region = Rect2(Vector2(i % 4, int(i / 4)) * cell, cell)
			tile.filter_clip = true
			textures.append(tile)
	return textures[clampi(index, 0, 7)]
