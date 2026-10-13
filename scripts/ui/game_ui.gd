extends CanvasLayer
## HUD and menus emit player choices; they do not modify combat state.

signal action_requested(action: String, argument: String)
signal setting_changed(key: String, value: float)

const Readout = preload("res://scripts/ui/run_readout.gd")
const RoundButton = preload("res://scripts/ui/round_action_button.gd")
const Layout = preload("res://scripts/input/control_layout.gd")
const JoystickView = preload("res://scripts/ui/joystick_view.gd")

var ui_theme: Theme
var panel: PanelContainer
var content: VBoxContainer
var shade: ColorRect
var portrait: TextureRect
var title: Label
var hud: Label
var hp_bar: ProgressBar
var xp_bar: ProgressBar
var node_bar: ProgressBar
var status: Label
var field_status: Label
var attack_button: Button
var skill_button: Button
var dash_button: Button
var pause_button: Button
var banner: Label
var banner_left = 0.0
var boss_bar: ProgressBar
var boss_label: Label
var pacing_label: Label
var joystick_view: Node2D

func _ready() -> void:
	ui_theme = Theme.new()
	var font = FontVariation.new()
	font.base_font = load("res://assets/fonts/NotoSansSC.ttf")
	var weight_tag = TextServerManager.get_primary_interface().name_to_tag("wght")
	font.variation_opentype = {weight_tag: 500.0}
	ui_theme.default_font = font
	ui_theme.default_font_size = 20
	ui_theme.set_stylebox("normal", "Button", style(Color("223342"), Color("73869b")))
	ui_theme.set_stylebox("hover", "Button", style(Color("354858"), Color("e5c17e")))
	ui_theme.set_stylebox("pressed", "Button", style(Color("675534"), Color("f4d490")))
	ui_theme.set_stylebox("disabled", "Button", style(Color("1b2835"), Color("45505c")))
	ui_theme.set_color("font_color", "Button", Color("f3ead9"))
	ui_theme.set_color("font_color", "Label", Color("f1e8d8"))
	ui_theme.set_stylebox("panel", "PanelContainer", style(Color("14212f"), Color("a88f64")))
	for rect in [Rect2(0, 0, 1280, 128), Rect2(0, 558, 1280, 162)]:
		var backdrop = ColorRect.new()
		backdrop.position = rect.position
		backdrop.size = rect.size
		backdrop.color = Color(0.04, 0.08, 0.11, 0.72 if rect.position.y == 0 else 0.4)
		backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(backdrop)
	joystick_view = JoystickView.new()
	add_child(joystick_view)
	hud = label_at("", Vector2(34, 18), 22)
	hp_bar = bar_at(Vector2(34, 62), Vector2(310, 14), Color("da866e"))
	xp_bar = bar_at(Vector2(365, 62), Vector2(310, 14), Color("8cdacb"))
	node_bar = bar_at(Vector2(698, 62), Vector2(305, 14), Color("dfbd79"))
	status = label_at("", Vector2(300, 588), 19)
	field_status = label_at("", Vector2(300, 657), 17)
	field_status.size = Vector2(600, 42)
	field_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pause_button = button_at("暂停", Rect2(1125, 18, 115, 62))
	pause_button.pressed.connect(func(): action_requested.emit("pause", ""))
	attack_button = round_button_at(shortcut("按住攻击", "J"), Layout.ATTACK, "attack")
	skill_button = round_button_at(shortcut("技能", "K"), Layout.SKILL, "skill")
	dash_button = round_button_at(shortcut("闪避", "空格"), Layout.DASH, "dash")
	skill_button.pressed.connect(func(): action_requested.emit("skill", ""))
	dash_button.pressed.connect(func(): action_requested.emit("dash", ""))
	boss_label = label_at("", Vector2(340, 80), 18)
	boss_label.size = Vector2(600, 24)
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_bar = bar_at(Vector2(365, 108), Vector2(550, 8), Color("db7a70"))
	pacing_label = label_at("", Vector2(700, 80), 17)
	shade = ColorRect.new()
	shade.color = Color(0.025, 0.045, 0.08, 0.86)
	shade.size = Vector2(1280, 720)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	portrait = TextureRect.new()
	portrait.position = Vector2(42, 220)
	portrait.size = Vector2(290, 375)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(portrait)
	title = label_at("勇者余烬", Vector2(42, 112), 48)
	panel = PanelContainer.new()
	panel.theme = ui_theme
	panel.position = Vector2(365, 92)
	panel.custom_minimum_size = Vector2(830, 548)
	add_child(panel)
	var margin = MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 22)
	panel.add_child(margin)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 13)
	margin.add_child(content)
	banner = label_at("", Vector2(340, 133), 22)
	banner.size = Vector2(600, 36)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func shortcut(text: String, key: String) -> String:
	return text if OS.has_feature("mobile") else text + "\n" + key

func style(background: Color, border: Color) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(12)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box

func label_at(text: String, pos: Vector2, font_size: int) -> Label:
	var label = Label.new()
	label.theme = ui_theme
	label.text = text
	label.position = pos
	label.add_theme_font_size_override("font_size", font_size)
	add_child(label)
	return label

func button_at(text: String, rect: Rect2) -> Button:
	var button = Button.new()
	button.theme = ui_theme
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_NONE
	add_child(button)
	return button

func round_button_at(text: String, rect: Rect2, icon: String) -> Button:
	var button = RoundButton.new()
	button.theme = ui_theme
	button.action_icon = icon
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_NONE
	add_child(button)
	return button

func bar_at(pos: Vector2, dimensions: Vector2, color: Color) -> ProgressBar:
	var bar = ProgressBar.new()
	bar.position = pos
	bar.size = dimensions
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", style(Color("182536"), Color("35465a")))
	bar.add_theme_stylebox_override("fill", style(color, color))
	add_child(bar)
	return bar

func clear_panel(heading: String, camp: bool = false) -> void:
	if banner: banner.hide()
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	var label = Label.new()
	label.text = heading
	label.add_theme_font_size_override("font_size", 27)
	content.add_child(label)
	panel.show()
	shade.show()
	portrait.visible = camp
	title.visible = camp
	panel.position = Vector2(365, 72) if camp else Vector2(230, 150)
	panel.custom_minimum_size = Vector2(830, 548) if camp else Vector2(820, 380)
	panel.size = panel.custom_minimum_size

func paragraph(text: String) -> void:
	var label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 760
	label.add_theme_font_size_override("font_size", 18)
	content.add_child(label)

func make_menu_button(text: String, action: String, argument: String = "", enabled: bool = true) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(760, 54)
	button.disabled = not enabled
	button.pressed.connect(func(): action_requested.emit(action, argument))
	return button

func menu_button(text: String, action: String, argument: String = "", enabled: bool = true) -> void:
	content.add_child(make_menu_button(text, action, argument, enabled))

func scroll_rows(rows: Array[String], height: float = 160.0) -> ScrollContainer:
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(760, height)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	for text in rows:
		var label = Label.new()
		label.text = text
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 18)
		list.add_child(label)
	content.add_child(scroll)
	return scroll

func show_camp(catalog: RefCounted, progress: Dictionary, selected: String, checkpoint: Dictionary = {}) -> void:
	clear_panel("远征营地  ·  水晶 %d" % progress.crystals, true)
	portrait.texture = load("res://assets/characters/%s.png" % selected)
	paragraph("选择你的勇者。每局从1级出发，每5节点挑战一位灾厄领主，击败后继续远征。")
	for id in catalog.character_order:
		var entry: Dictionary = catalog.characters[id]
		var unlocked: bool = progress.unlocks.has(id)
		var text = ("◆ " if selected == id else "") + entry.name + " · " + entry.description
		if not unlocked:
			text += " · 解锁 %d 水晶" % entry.unlock_cost
		menu_button(text, "select" if unlocked else "unlock", id, unlocked or progress.crystals >= int(entry.unlock_cost))
	if not checkpoint.is_empty():
		var seconds = int(checkpoint.director.elapsed)
		var saved_character = catalog.characters.get(checkpoint.combat.character_id, {}).get("name", checkpoint.combat.character_id)
		menu_button("继续%s远征 · 等级%d · 节点%d · %02d:%02d" % [saved_character, checkpoint.session.level, checkpoint.director.node_index, seconds / 60, seconds % 60], "continue_saved")
	menu_button("开始远征" if checkpoint.is_empty() else "放弃已保存远征，从1级重新出发", "start")
	var cost = 10 + int(progress.vitality) * 5
	menu_button("营地生命 +2%%  (%d/10)  ·  %d 水晶" % [progress.vitality, cost], "vitality", "", progress.vitality < 10 and progress.crystals >= cost)
	var actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 13)
	content.add_child(actions)
	for entry in [{"title": "远征记录", "action": "records"}, {"title": "设置与操作说明", "action": "settings"}]:
		var button = make_menu_button(entry.title, entry.action)
		button.custom_minimum_size.x = 370
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(button)

func show_upgrades(run: RefCounted) -> void:
	clear_panel("升至 %d 级  ·  选择你的祝福" % run.level)
	paragraph("战斗已暂停。祝福只在本局生效；不同铭文会改变你的战斗方式。")
	var current = Readout.current(run)
	paragraph("当前新攻击：单枚 %.1f  ·  暴击 %.0f%%  ·  弹体 %d 枚" % [current.damage, float(current.crit) * 100, run.combat.stats.projectile_count])
	for entry in run.selected_upgrades:
		var stacks = int(run.upgrades.stacks.get(entry.id, 0))
		menu_button("%s   ·   %s   [已选%d次]" % [entry.title, entry.description, stacks], "upgrade", entry.id)
	menu_button("查看属性与已获祝福", "build", "upgrades_menu")

func show_paused() -> void:
	clear_panel("远征暂停")
	if OS.has_feature("mobile"):
		paragraph("左侧摇杆移动，右侧按住普攻。\n点击技能与闪避；升级选择时战斗自动暂停。")
	else:
		paragraph("WASD / 方向键移动；按住J攻击。\nK释放技能，空格闪避；Esc暂停。")
	menu_button("继续远征", "resume")
	menu_button("勇者属性与祝福", "build", "paused_menu")
	menu_button("设置", "settings_run")
	menu_button("保存远征并返回营地", "save_camp")

func show_checkpoint_error() -> void:
	clear_panel("这份远征记录暂时无法恢复")
	paragraph("记录格式或内容版本不同。你可以返回营地，或放弃旧远征开始新的一局。")
	menu_button("返回营地", "camp")

func show_result(result: Dictionary) -> void:
	clear_panel("远征结束  ·  勇者的旅程仍将继续")
	paragraph("存活 %02d:%02d  ·  节点 %d  ·  等级 %d\n击杀 %d  ·  击败Boss %d  ·  获得水晶 %d\n最后受到的伤害：%s" % [int(result.seconds) / 60, int(result.seconds) % 60, result.node, result.level, result.kills, result.bosses, result.crystals, result.death_source])
	menu_button("再次远征", "start")
	menu_button("返回营地", "camp")

func show_build(run: RefCounted, return_action: String) -> void:
	clear_panel("%s  ·  等级%d  ·  勇者与祝福" % [run.catalog.characters[run.combat.character_id].name, run.level])
	panel.position.y = 72
	panel.custom_minimum_size.y = 570
	paragraph(Readout.stat_text(run))
	paragraph(Readout.field_text(run))
	scroll_rows(Readout.blessings(run.upgrades, run.upgrades.stacks))
	menu_button("返回升级选择" if return_action == "upgrades_menu" else "返回暂停菜单", return_action)

func show_records(run: RefCounted, progress: Dictionary) -> void:
	clear_panel("远征记录  ·  已完成%d局" % progress.total_runs)
	panel.position.y = 72
	panel.custom_minimum_size.y = 570
	paragraph("最久存活 %s  ·  营地生命成长 %d/10" % [Readout.clock(progress.best_seconds), progress.vitality])
	var result: Dictionary = progress.last_run
	if result.is_empty():
		paragraph("每次远征结束后，会在这里保留上一局的成绩和祝福。你可以回看成长选择，再尝试不同搭配。")
	else:
		var character = run.catalog.characters.get(result.get("character", "knight"), {}).get("name", "勇者")
		paragraph("上一局 · %s\n存活 %s  ·  等级%d  ·  节点%d\n击杀%d  ·  击败Boss%d  ·  水晶%d\n最后受到的伤害：%s" % [character, Readout.clock(result.seconds), result.level, result.node, result.kills, result.bosses, result.crystals, result.get("death_source", "")])
		scroll_rows(Readout.blessings(run.upgrades, result.get("build", {})))
	menu_button("返回营地", "camp")

func show_settings(settings: Dictionary, return_action: String) -> void:
	clear_panel("设置与操作")
	paragraph("左手移动；右手按住普攻，点击技能与闪避。攻击自动选择近处敌人。升级时暂停；切到后台后请手动继续。")
	for key in ["volume", "control_scale"]:
		var label = Label.new()
		label.text = "总音量" if key == "volume" else "触控按钮尺寸"
		content.add_child(label)
		var slider = HSlider.new()
		slider.min_value = 0.0 if key == "volume" else 0.85
		slider.max_value = 1.0 if key == "volume" else 1.15
		slider.step = 0.05
		slider.value = settings[key]
		slider.custom_minimum_size = Vector2(760, 38)
		slider.value_changed.connect(func(value: float): setting_changed.emit(key, value))
		content.add_child(slider)
	menu_button("素材与制作署名", "credits", return_action)
	menu_button("返回", return_action)

func show_credits(return_action: String) -> void:
	clear_panel("素材与制作")
	paragraph("勇者余烬 · 离线西幻肉鸽\n角色与动作美术：OpenAI imagegen\n配乐与战斗音效：本项目原创合成\n中文字体：Noto Sans SC，SIL Open Font License 1.1\n引擎：Godot Engine，MIT")
	menu_button("返回", return_action)

func hide_panel() -> void:
	panel.hide()
	shade.hide()
	portrait.hide()
	title.hide()

func sync(run: RefCounted, delta: float, held_attack: bool = false) -> void:
	var active = run.state in ["playing", "paused", "upgrade"]
	for control in [attack_button, skill_button, dash_button, pause_button, hud, hp_bar, xp_bar, node_bar, status, field_status, boss_bar, boss_label, pacing_label]:
		control.visible = active
	joystick_view.active = active
	joystick_view.queue_redraw()
	if run.combat.stats.is_empty():
		return
	var stats: Dictionary = run.combat.stats
	attack_button.modulate = Color("f4d794") if held_attack else Color.WHITE
	skill_button.disabled = run.combat.skill_cooldown > 0
	dash_button.disabled = run.combat.dash_cooldown > 0
	hud.text = "生命 %d/%d      等级 %d      节点 %d%s      %02d:%02d" % [stats.hp, stats.max_hp, run.level, run.director.node_index, " · Boss" if run.director.is_boss_node() else "", int(run.director.elapsed) / 60, int(run.director.elapsed) % 60]
	hp_bar.value = 100.0 * float(stats.hp) / float(stats.max_hp)
	xp_bar.value = 100.0 * float(run.xp) / float(run.xp_required())
	node_bar.value = 100.0 * minf(1, run.director.node_time / float(run.catalog.balance.difficulty.node_duration_seconds))
	var boss: Dictionary = {}
	for enemy in run.combat.enemies:
		if enemy.kind == "boss" and enemy.hp > 0:
			boss = enemy
			break
	boss_label.visible = active and not boss.is_empty()
	boss_bar.visible = boss_label.visible
	pacing_label.visible = active and boss.is_empty()
	pacing_label.text = "节点进度 · " + run.director.pacing_name()
	if not boss.is_empty():
		boss_bar.value = clampf(float(boss.hp) / float(boss.max_hp), 0, 1) * 100
		boss_label.text = "%s  ·  %d/%d  ·  %.0f%%" % [run.catalog.enemies[boss.id].name, boss.hp, boss.max_hp, boss_bar.value]
		var view = preload("res://scripts/core/world_geometry.gd").visible_rect(run.combat.player)
		if not view.has_point(boss.pos):
			var direction: Vector2 = run.combat.player.direction_to(boss.pos)
			boss_label.text += " · " + ("东" if direction.x > 0.35 else ("西" if direction.x < -0.35 else "")) + ("南" if direction.y > 0.35 else ("北" if direction.y < -0.35 else "")) + "方"
	skill_button.text = "技能 %.1fs" % run.combat.skill_cooldown if run.combat.skill_cooldown > 0 else shortcut(run.catalog.characters[run.combat.character_id].skill_name, "K")
	dash_button.text = "闪避 %.1fs" % run.combat.dash_cooldown if run.combat.dash_cooldown > 0 else shortcut("闪避", "空格")
	skill_button.cooldown_fraction = clampf(float(run.combat.skill_cooldown) / float(stats.skill_cooldown), 0, 1)
	dash_button.cooldown_fraction = clampf(float(run.combat.dash_cooldown) / float(run.catalog.balance.abilities.dash_cooldown_seconds), 0, 1)
	for button in [attack_button, skill_button, dash_button]: button.queue_redraw()
	status.text = "%s\n经验 %d/%d   ·   已获祝福 %d 种" % [run.catalog.characters[run.combat.character_id].name, run.xp, run.xp_required(), run.upgrades.stacks.size()]
	field_status.text = run.combat.field.ui_description(run.combat.player)
	field_status.modulate = Color("abc0c9")
	if not run.combat.field.modifiers_at(run.combat.player).affliction.is_empty():
		field_status.modulate = Color("e8dca1") if run.combat.field.definition.kind == "buff" else Color("f3c8a4")
	banner_left = maxf(0, banner_left - delta)
	banner.visible = banner_left > 0 and run.state == "playing" and not panel.visible

func show_banner(text: String) -> void:
	banner.text = text
	banner_left = 3.0

func apply_control_scale(scale_value: float, controls: RefCounted) -> void:
	joystick_view.controls = controls
	controls.joystick_radius = 72 * scale_value
	for entry in [{"button": attack_button, "rect": Layout.ATTACK}, {"button": skill_button, "rect": Layout.SKILL}, {"button": dash_button, "rect": Layout.DASH}]:
		var rect: Rect2 = entry.rect
		var size = rect.size * scale_value
		entry.button.position = rect.get_center() - size / 2
		entry.button.size = size
	controls.attack_rect = Rect2(attack_button.position, attack_button.size)
	controls.skill_rect = Rect2(skill_button.position, skill_button.size)
	controls.dash_rect = Rect2(dash_button.position, dash_button.size)
