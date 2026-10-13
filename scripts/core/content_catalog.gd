extends RefCounted
## Stable content IDs shared by simulation, presentation and saved unlocks.

var enemies: Dictionary = {}
var characters: Dictionary = {}
var character_order: Array[String] = []
var bosses: Array[String] = []
var balance: Dictionary = {}

func load_content() -> void:
	balance = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	var enemy_document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemies.json"))
	var character_document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/characters.json"))
	for entry in enemy_document.enemies:
		enemies[entry.id] = entry
		if entry.kind == "boss":
			bosses.append(entry.id)
	for entry in character_document.characters:
		characters[entry.id] = entry
		character_order.append(entry.id)

func character_stats(id: String, camp_rank: int) -> Dictionary:
	var entry: Dictionary = characters[id]
	var stats = {"max_hp": float(balance.player.max_hp) * float(entry.hp_multiplier) * (1.0 + camp_rank * 0.02), "damage": float(balance.player.attack_damage) * float(entry.damage_multiplier), "move_speed": float(balance.player.move_speed), "attack_interval": float(balance.player.attack_interval_seconds) * float(entry.interval_multiplier), "pickup_radius": float(balance.player.pickup_radius), "skill_cooldown": float(balance.abilities.skill_cooldown_seconds), "projectile_count": 1, "pierce": 0, "crit_chance": 0.0, "elite_bonus": 0.0, "slow_fraction": 0.0, "slow_duration": 0.0, "blast_fraction": 0.0}
	stats.merge(entry.starting_stats, true)
	stats.hp = stats.max_hp
	return stats
