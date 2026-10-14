extends RefCounted
## Small exported documents are cached once. Excel is a build-time source only.
static var documents: Dictionary = {}
static var profile_id = "release-hard"
static var data_root = "res://data"

static func read(id: String) -> Dictionary:
	if not documents.has(id):
		documents[id] = JSON.parse_string(FileAccess.get_file_as_string("%s/%s.json" % [data_root,id]))
	return documents[id]

static func section(id: String) -> Dictionary:
	return read("balance")[id]

static func use_qa_profile() -> void:
	# Called only by desktop QA scripts; this file and those scripts are excluded from APKs.
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://design/profiles/qa-easy.json"))
	profile_id = profile.id
	var balance = read("balance")
	balance.player.max_hp *= float(profile.player_hp_factor)
	balance.player.attack_damage *= float(profile.player_damage_factor)
	for entry in read("enemies").enemies:
		entry.hp *= float(profile.enemy_hp_factor)
		entry.damage *= float(profile.enemy_damage_factor)
		entry.defense *= float(profile.enemy_defense_factor)
		for action in entry.get("attacks", []): scale_test_attack(action, float(profile.enemy_damage_factor))
		if entry.has("attack"): scale_test_attack(entry.attack, float(profile.enemy_damage_factor))
		for phase in entry.get("phases", []):
			for action in phase.attacks: scale_test_attack(action, float(profile.enemy_damage_factor))

static func scale_test_attack(action: Dictionary, factor: float) -> void:
	if action.has("damage"): action.damage *= factor
	for part in action.get("attacks", []): scale_test_attack(part, factor)
