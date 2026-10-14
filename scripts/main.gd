extends Node2D
## Composition root: persistence, input and presentation around an independent run.

const ContentCatalog = preload("res://scripts/core/content_catalog.gd")
const RunSession = preload("res://scripts/core/run_session.gd")
const ProgressionStore = preload("res://scripts/core/progression_store.gd")
const TouchController = preload("res://scripts/input/touch_controller.gd")
const GameUI = preload("res://scripts/ui/game_ui.gd")
const BattleView = preload("res://scripts/presentation/battle_view.gd")
const AudioService = preload("res://scripts/presentation/audio_service.gd")
const ActiveRunStore = preload("res://scripts/core/active_run_store.gd")
const CHECKPOINT_INTERVAL = 20.0

var catalog = ContentCatalog.new()
var progression_store = ProgressionStore.new()
var controls = TouchController.new()
var session: RefCounted
var game_ui: CanvasLayer
var battle_view: Node2D
var meta: Dictionary
var selected_character = "knight"
var settings_return = "camp"
var audio_service: Node
var active_store: RefCounted
var saved_checkpoint: Dictionary = {}
var checkpoint_left = CHECKPOINT_INTERVAL
var last_back_request_ms = -1000
var panel_return = ""

func _ready() -> void:
	catalog.load_content()
	if OS.is_debug_build():
		var config = preload("res://scripts/core/gameplay_config.gd")
		var manifest: Dictionary = config.read("config-manifest")
		var actual_hashes: Dictionary = {}
		for id in manifest.documents: actual_hashes[id] = FileAccess.get_sha256("res://data/%s.json" % id)
		print("CONFIG_RUNTIME:" + JSON.stringify({"profile":config.profile_id,"source_workbook":manifest.workbook_sha256,"actual_hashes":actual_hashes}))
	session = RunSession.new(catalog)
	active_store = create_active_store()
	load_progress()
	saved_checkpoint = active_store.load_checkpoint()
	if not saved_checkpoint.is_empty() and saved_checkpoint.get("session", {}).get("run_id", "") == meta.last_settled_run_id:
		clear_checkpoint()
	get_tree().auto_accept_quit = false
	get_tree().quit_on_go_back = false
	game_ui = GameUI.new()
	add_child(game_ui)
	game_ui.action_requested.connect(on_action)
	game_ui.setting_changed.connect(on_setting)
	game_ui.attack_button.button_down.connect(func(): controls.mouse_attack = true)
	game_ui.attack_button.button_up.connect(func(): controls.mouse_attack = false)
	battle_view = BattleView.new()
	add_child(battle_view)
	battle_view.configure(session, controls, game_ui.ui_theme.default_font)
	apply_settings()
	audio_service = AudioService.new()
	add_child(audio_service)
	show_camp()

func _physics_process(delta: float) -> void:
	var movement = controls.movement()
	while not controls.commands.is_empty():
		on_action(controls.commands.pop_front(), "")
	session.step(delta, movement, controls.attacking())
	consume_events()
	battle_view.movement = movement
	battle_view.sync()
	game_ui.sync(session, delta, controls.attacking())
	if session.state == "playing":
		checkpoint_left -= delta
		if checkpoint_left <= 0: save_checkpoint()

func _input(event: InputEvent) -> void:
	if not session:
		return
	if controls.handle(event, session.state == "playing"):
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED] and session:
		session.pause()
		controls.clear()
		save_checkpoint()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST and session:
		save_checkpoint()
		get_tree().quit()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST and session:
		var now = Time.get_ticks_msec()
		if now - last_back_request_ms < 200:
			if OS.is_debug_build(): print("Duplicate Android back request ignored")
			return
		last_back_request_ms = now
		if not panel_return.is_empty():
			on_action(panel_return)
			return
		if OS.is_debug_build(): print("Back navigation from state: " + session.state)
		if session.state == "playing":
			session.pause()
			save_checkpoint()
		elif session.state in ["paused", "upgrade", "equipment"]:
			if save_checkpoint(): show_camp()
		elif session.state == "dead": show_camp()
		else: get_tree().quit()

func consume_events() -> void:
	var checkpoint_changed = false
	for event in session.events:
		if event.type in ["upgrade", "chosen", "node", "boss_phase", "equipment", "equipment_chosen"]: checkpoint_changed = true
		if event.type in ["attack", "hurt", "dash", "skill", "upgrade"]:
			audio_service.play_cue(event.type)
		match event.type:
			"equipment":
				panel_return = ""
				controls.clear()
				game_ui.show_equipment(session)
			"equipped": game_ui.show_banner("已装备：" + event.name)
			"healed": game_ui.show_banner("生命药剂 · 恢复%d生命" % roundi(event.amount))
			"started":
				game_ui.show_banner("拖动左侧移动 · 按住右侧攻击" if OS.has_feature("mobile") else "WASD移动 · 按住J攻击 · K技能 · 空格闪避")
			"upgrade":
				panel_return = ""
				controls.clear()
				game_ui.show_upgrades(session)
			"paused":
				panel_return = ""
				controls.clear()
				game_ui.show_paused()
			"resumed":
				panel_return = ""
				game_ui.hide_panel()
			"boss_phase":
				game_ui.show_banner(event.name + " · " + event.phase)
				audio_service.play_cue("boss")
			"node":
				var rule: Dictionary = session.director.node_rule()
				var names: Array[String] = []
				for id in rule.modifiers: names.append(catalog.encounters.modifiers[id].name)
				var text = "节点 %d · %s%s" % [event.index, rule.name, " · " + "、".join(names) if not names.is_empty() else ""]
				if not event.boss.is_empty():
					text = catalog.enemies[event.boss].name
					audio_service.play_cue("boss")
				game_ui.show_banner(text)
			"dead":
				panel_return = ""
				audio_service.play_cue("death")
				controls.clear()
				settle_run(event.result)
				game_ui.show_result(event.result)
	session.events.clear()
	if checkpoint_changed: save_checkpoint()

func on_action(action: String, argument: String = "") -> void:
	match action:
		"equip", "discard_equipment":
			if session.choose_equipment(action == "equip"):
				game_ui.hide_panel()
				consume_events()
		"start": start_run()
		"continue_saved": continue_saved_run()
		"save_camp":
			if save_checkpoint(): show_camp()
		"camp": show_camp()
		"select":
			if meta.unlocks.has(argument):
				selected_character = argument
			show_camp()
		"unlock": unlock_character(argument)
		"vitality": buy_vitality()
		"upgrade":
			if session.apply_upgrade(argument):
				game_ui.hide_panel()
				consume_events()
		"dash": session.dash(controls.movement())
		"skill": session.cast_skill()
		"pause":
			if not panel_return.is_empty():
				on_action(panel_return)
				return
			if session.state == "paused": session.resume()
			else: session.pause()
		"resume": session.resume()
		"settings", "settings_run":
			settings_return = "camp" if action == "settings" else "paused_menu"
			panel_return = settings_return
			game_ui.show_settings(meta.settings, settings_return)
		"paused_menu":
			panel_return = ""
			game_ui.show_paused()
		"upgrades_menu":
			panel_return = ""
			game_ui.show_upgrades(session)
		"equipment_menu":
			panel_return = ""
			game_ui.show_equipment(session)
		"build":
			if session.state not in ["paused", "upgrade", "equipment"]: return
			panel_return = "equipment_menu" if session.state == "equipment" else ("upgrades_menu" if session.state == "upgrade" else "paused_menu")
			controls.clear()
			game_ui.show_build(session, panel_return)
		"records":
			if session.state != "menu": return
			panel_return = "camp"
			game_ui.show_records(session, meta)
		"equipment_collection":
			if session.state != "menu": return
			panel_return = "camp"
			game_ui.show_equipment_collection(session, meta)
		"credits":
			panel_return = argument
			game_ui.show_credits(argument)

func start_run() -> void:
	panel_return = ""
	clear_checkpoint()
	controls.clear()
	session.start(selected_character, int(meta.vitality), -1, meta.equipment_unlocks)
	game_ui.hide_panel()
	battle_view.reset_actor_views()
	save_checkpoint()

func continue_saved_run() -> void:
	if saved_checkpoint.is_empty(): return
	panel_return = ""
	if not session.restore_checkpoint(saved_checkpoint):
		game_ui.show_checkpoint_error()
		return
	selected_character = session.combat.character_id
	controls.clear()
	battle_view.reset_actor_views()
	battle_view.sync()
	if session.state == "upgrade": game_ui.show_upgrades(session)
	elif session.state == "equipment": game_ui.show_equipment(session)
	else: game_ui.show_paused()
	game_ui.sync(session, 0)
	checkpoint_left = CHECKPOINT_INTERVAL

func show_camp() -> void:
	panel_return = ""
	session.state = "menu"
	controls.clear()
	game_ui.show_camp(catalog, meta, selected_character, saved_checkpoint)
	game_ui.sync(session, 0)

func buy_vitality() -> void:
	var rules: Dictionary = catalog.balance.meta
	var cost = int(rules.vitality_price_base) + int(meta.vitality) * int(rules.vitality_price_per_rank)
	if meta.vitality < int(rules.max_vitality_rank) and meta.crystals >= cost:
		meta.crystals -= cost
		meta.vitality += 1
		save_progress()
	show_camp()

func unlock_character(id: String) -> void:
	if not catalog.characters.has(id) or meta.unlocks.has(id):
		return
	var cost = int(catalog.characters[id].unlock_cost)
	if meta.crystals >= cost:
		meta.crystals -= cost
		meta.unlocks.append(id)
		selected_character = id
		save_progress()
	show_camp()

func settle_run(result: Dictionary) -> void:
	if session.reward_paid:
		return
	if meta.last_settled_run_id != session.run_id:
		meta.crystals += int(result.crystals)
		meta.best_seconds = maxf(meta.best_seconds, result.seconds)
		meta.total_runs += 1
		meta.total_bosses += int(result.bosses)
		var before: Array = meta.equipment_unlocks.duplicate()
		meta.equipment_unlocks = session.combat.equipment.unlocked_for_bosses(meta.total_bosses)
		var unlocked_names: Array[String] = []
		for id in meta.equipment_unlocks:
			if not before.has(id): unlocked_names.append(session.combat.equipment.definitions[id].name)
		if not unlocked_names.is_empty(): result.equipment_unlocked = unlocked_names
		meta.last_run = result
		meta.last_settled_run_id = session.run_id
	# Meta settlement is written first; its run ID blocks stale-checkpoint resurrection.
	session.reward_paid = save_progress()
	if session.reward_paid: clear_checkpoint()

func on_setting(key: String, value: float) -> void:
	meta.settings[key] = value
	apply_settings()
	save_progress()

func apply_settings() -> void:
	var volume = float(meta.settings.volume)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, volume)))
	game_ui.apply_control_scale(meta.settings.control_scale, controls)

func load_progress() -> void:
	meta = progression_store.load_progress()

func save_progress() -> bool:
	var error = progression_store.save_progress(meta)
	if error != OK:
		push_error("Cannot save progression: %s" % error_string(error))
	return error == OK

func create_active_store() -> RefCounted:
	return ActiveRunStore.new()

func save_checkpoint() -> bool:
	if not active_store or not session or session.state not in ["playing", "paused", "upgrade", "equipment"] or session.combat.stats.hp <= 0: return false
	var document = session.checkpoint()
	var error = active_store.save_checkpoint(document)
	if error != OK:
		push_error("Cannot save active run: %s" % error_string(error))
		return false
	saved_checkpoint = document
	checkpoint_left = CHECKPOINT_INTERVAL
	return true

func clear_checkpoint() -> void:
	saved_checkpoint.clear()
	if active_store:
		var error = active_store.clear_checkpoint()
		if error != OK: push_error("Cannot clear active run: %s" % error_string(error))
