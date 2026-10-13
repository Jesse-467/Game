extends SceneTree
## Isolated full-build and completed-run files for the computer emulator only.

const Catalog = preload("res://scripts/core/content_catalog.gd")
const Session = preload("res://scripts/core/run_session.gd")
const Store = preload("res://scripts/core/active_run_store.gd")
const Progress = preload("res://scripts/core/progression_store.gd")

func _initialize() -> void:
	call_deferred("write_fixture")

func write_fixture() -> void:
	var content = Catalog.new()
	content.load_content()
	var run = Session.new(content)
	run.start("knight", 0, 47)
	for entry in run.upgrades.definitions:
		for i in maxi(1, int(entry.max_stacks)):
			run.combat.stats = run.upgrades.apply(entry.id, run.combat.stats)
	run.level = 40
	run.combat.stats.level = 40
	run.combat.field.configure_node(6)
	run.combat.field.definition = run.combat.field.find_definition("keen_ground")
	run.combat.field.prepare_zones()
	run.combat.field.phase = "active"
	run.combat.field.phase_left = 8.0
	run.combat.player = run.combat.field.zones[0].pos
	run.pause()
	DirAccess.make_dir_recursive_absolute("res://builds/readout-probe")
	var store = Store.new()
	store.path = "res://builds/readout-probe/full-build.save"
	if store.save_checkpoint(run.checkpoint()) != OK:
		push_error("Cannot write full-build fixture")
		quit(1)
		return
	var progress = Progress.new()
	progress.path = "res://builds/readout-probe/records-progress.json"
	var meta = progress.defaults()
	meta.total_runs = 1
	meta.best_seconds = 1865.0
	meta.last_run = run.result()
	meta.last_run.run_id = "fixture-previous-run"
	meta.last_run.seconds = 1865.0
	meta.last_run.node = 51
	meta.last_run.kills = 1832
	meta.last_run.bosses = 10
	meta.last_run.death_source = "骸骨君主 · 灵魂环阵"
	if progress.save_progress(meta) != OK:
		push_error("Cannot write completed-run fixture")
		quit(1)
		return
	print("PASS: wrote isolated full-build and completed-run emulator fixtures")
	quit()
