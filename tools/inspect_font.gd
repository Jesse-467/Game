extends SceneTree

func _initialize() -> void:
	var font = FontVariation.new()
	font.base_font = load("res://assets/fonts/NotoSansSC.ttf")
	var server = TextServerManager.get_primary_interface()
	font.variation_opentype = {server.name_to_tag("wght"): 500.0}
	print("Supported font axes: ", font.get_supported_variation_list())
	for rid in font.get_rids():
		print("Selected font axes: ", server.font_get_variation_coordinates(rid))
	quit()
