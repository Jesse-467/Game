extends RefCounted
## Stable content IDs shared by simulation, presentation and saved unlocks.

var enemies: Dictionary = {}
var characters: Dictionary = {}
var character_order: Array[String] = []
var bosses: Array[String] = []
var balance: Dictionary = {}
var encounters: Dictionary = {}
const Config = preload("res://scripts/core/gameplay_config.gd")

func load_content() -> void:
	balance = Config.read("balance")
	encounters = Config.read("encounters")
	var enemy_document: Dictionary = Config.read("enemies")
	var character_document: Dictionary = Config.read("characters")
	characters.clear()
	enemies.clear()
	character_order.clear()
	bosses.assign(encounters.boss_rotation)
	for entry in enemy_document.enemies:
		enemies[entry.id] = entry
	for entry in character_document.characters:
		characters[entry.id] = entry
		character_order.append(entry.id)

func character_stats(id: String, camp_rank: int) -> Dictionary:
	var entry: Dictionary = characters[id]
	var stats = balance.starting_stats.duplicate(true)
	stats.merge({"max_hp": float(balance.player.max_hp) * float(entry.hp_multiplier) * (1.0 + camp_rank * float(balance.meta.vitality_fraction_per_rank)), "damage": float(balance.player.attack_damage) * float(entry.damage_multiplier), "move_speed": float(balance.player.move_speed), "attack_interval": float(balance.player.attack_interval_seconds) * float(entry.interval_multiplier), "pickup_radius": float(balance.player.pickup_radius), "skill_cooldown": float(balance.abilities.skill_cooldown_seconds)}, true)
	stats.merge(entry.starting_stats, true)
	stats.hp = stats.max_hp
	return stats
