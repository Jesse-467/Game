extends SceneTree
const Config = preload("res://scripts/core/gameplay_config.gd")
const Catalog = preload("res://scripts/core/content_catalog.gd")
const Director = preload("res://scripts/core/run_director.gd")
const Upgrades = preload("res://scripts/core/upgrade_catalog.gd")
const Stats = preload("res://scripts/core/stat_pipeline.gd")
const Equipment = preload("res://scripts/core/equipment_inventory.gd")

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--data-root="): Config.data_root = argument.trim_prefix("--data-root=")
	Config.documents.clear()
	var catalog = Catalog.new()
	catalog.load_content()
	var director = Director.new(catalog)
	var upgrades = Upgrades.new()
	upgrades.load_content()
	var gear = Equipment.new()
	var sword: Dictionary = gear.definitions.iron_sword.stats
	var stats = Stats.evaluate(catalog.character_stats("knight",0), sword, {"power":2}, upgrades.definitions)
	var enemy = director.enemy_stats(catalog.enemies.slime)
	print("CONFIG_PROBE:" + JSON.stringify({"player_max_hp":stats.max_hp,"player_damage":stats.damage,"enemy_base_hp":enemy.base_stats.max_hp,"enemy_final_hp":enemy.max_hp,"enemy_final_defense":enemy.defense,"node":director.node_index}))
	quit()
