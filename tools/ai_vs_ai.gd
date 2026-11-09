extends SceneTree
## Headless full-AI observer: pits every Great Power against the others under
## the same AI planners a live game uses, then writes a per-turn metrics stream
## plus a final standing (wiki: game-setup § Human/AI slot assignment — an empty
## human slot set is the full-AI observer; turn-trace-interpretation).
##
##   godot --headless --path . --script res://tools/ai_vs_ai.gd -- \
##       --turns=80 --seed=1500 --size=1 --runs=1
##
## Options: --turns=N (resolved turns per run, default 60), --seed=N (default
## 1500), --size=0|1|2 (GameConfig.SIZES, default 1 = Standard), --runs=N
## (seeds seed+i, default 1), --historical (stop at the calendar cap instead of
## the observer's endless campaign), --out=DIR (default user://ai_vs_ai).

const SCENE: PackedScene = preload("res://scenes/map_screen.tscn")
const OUT_DIR: String = "user://ai_vs_ai"
const BOOT_FRAMES: int = 3

var _turns: int = 60
var _seed: int = GameConfig.DEFAULT_SEED
var _size: int = GameConfig.DEFAULT_SIZE_INDEX
var _runs: int = 1
var _historical: bool = false
var _quiet: bool = false
var _out_dir: String = OUT_DIR
var _failures: PackedStringArray = []
var _wins: Dictionary = {}
var _unfinished: int = 0
var _old_total: Dictionary = {}
var _power_total: Dictionary = {}
var _falls: Dictionary = {}
var _appearances: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_parse_args()
	_ensure_dir()
	var seeds: PackedStringArray = []
	for run in _runs:
		var seed_value: int = _seed + run
		seeds.append(str(seed_value))
		var result: Dictionary = await _run_one(run, seed_value)
		_aggregate(result)
	_report(seeds)
	quit(0 if _failures.is_empty() else 1)


# --- one campaign ------------------------------------------------------------


func _run_one(run: int, seed_value: int) -> Dictionary:
	var entry: Dictionary = GameConfig.SIZES[_size]
	var screen: MapScreen = SCENE.instantiate()
	screen.map_seed = seed_value
	screen.map_width = int(entry["width"])
	screen.map_height = int(entry["height"])
	screen.observer_mode = true
	# Only a whole-game observer may run past the calendar cap
	# (wiki: game-setup § Campaign length; DR-20261108-05).
	screen.infinite_mode = not _historical
	root.add_child(screen)
	for _frame in BOOT_FRAMES:
		await process_frame
	var play: PlaySession = screen.play
	if play == null:
		_fail("run %d: MapScreen built no session" % run)
		screen.free()
		return {}
	# The tool owns the calendar here; the dashboard must not step behind it.
	var panel := screen.get_node_or_null("AiObserver") as AiObserverPanel
	if panel != null:
		panel.running = false
	var records: Array[Dictionary] = []
	while not play.campaign_over() and play.turn <= _turns:
		var before: int = play.turn
		MapPlayTurn.end_turn(play)
		await process_frame
		records.append(MapPlayObserver.snapshot(play))
		if play.turn == before and not play.campaign_over():
			_fail("run %d: turn %d stalled (a decision may be suspended)" % [run, before])
			break
	var final: Dictionary = MapPlayObserver.snapshot(play)
	_write_run(run, seed_value, records, final)
	if not _quiet:
		print(
			"run %d  seed %d  turn %d  %s"
			% [run, seed_value, int(final["turn"]), String(final["result"])]
		)
	screen.free()
	await process_frame
	return {"run": run, "seed": seed_value, "final": final, "turns": records.size()}


func _aggregate(result: Dictionary) -> void:
	if result.is_empty():
		return
	_appearances += 1
	var final: Dictionary = result.get("final", {})
	var winner: int = int(final.get("winner", MapModel.NO_ID))
	if winner == MapModel.NO_ID:
		_unfinished += 1
	else:
		_wins[winner] = int(_wins.get(winner, 0)) + 1
	for row: Dictionary in final.get("rows", []):
		var faction: int = int(row["faction"])
		_old_total[faction] = int(_old_total.get(faction, 0)) + int(row["provinces_old"])
		_power_total[faction] = int(_power_total.get(faction, 0)) + int(row["power"])
		if not bool(row["alive"]):
			_falls[faction] = int(_falls.get(faction, 0)) + 1


# --- output ------------------------------------------------------------------


func _write_run(
	run: int, seed_value: int, records: Array[Dictionary], final: Dictionary
) -> void:
	var stem: String = "%s/run_%02d" % [_out_dir, run]
	var handle := FileAccess.open("%s_turns.jsonl" % stem, FileAccess.WRITE)
	if handle == null:
		_fail("run %d: cannot write %s_turns.jsonl" % [run, stem])
		return
	for record: Dictionary in records:
		handle.store_line(JSON.stringify(record))
	handle.close()
	var summary: Dictionary = final.duplicate(true)
	summary["run"] = run
	summary["seed"] = seed_value
	summary["resolved_turns"] = records.size()
	var summary_file := FileAccess.open("%s_summary.json" % stem, FileAccess.WRITE)
	if summary_file == null:
		_fail("run %d: cannot write %s_summary.json" % [run, stem])
		return
	summary_file.store_string(JSON.stringify(summary, "  "))
	summary_file.close()


func _report(seeds: PackedStringArray) -> void:
	var rounds: int = maxi(_appearances, 1)
	print("")
	print(
		"AI VS AI — %d run(s) · seeds %s · limit %d turns · %s campaign"
		% [
			_appearances, ", ".join(seeds), _turns,
			"historical" if _historical else "endless",
		]
	)
	print("%-18s %5s %6s %8s %8s %6s" % ["crown", "wins", "falls", "avg OW", "avg power", "rate"])
	for faction: int in FactionCatalog.great_power_ids():
		print(
			"%-18s %5d %6d %8.1f %8.0f %5.0f%%"
			% [
				FactionCatalog.name_of(faction),
				int(_wins.get(faction, 0)),
				int(_falls.get(faction, 0)),
				float(int(_old_total.get(faction, 0))) / float(rounds),
				float(int(_power_total.get(faction, 0))) / float(rounds),
				100.0 * float(int(_wins.get(faction, 0))) / float(rounds),
			]
		)
	print("Unfinished / no declared winner: %d of %d" % [_unfinished, _appearances])
	print("Per-turn metrics: %s/run_NN_turns.jsonl · final standing: %s/run_NN_summary.json" % [
		ProjectSettings.globalize_path(_out_dir), ProjectSettings.globalize_path(_out_dir),
	])
	if not _failures.is_empty():
		printerr("ai_vs_ai: %d failure(s): %s" % [_failures.size(), ", ".join(_failures)])


# --- plumbing ----------------------------------------------------------------


func _parse_args() -> void:
	for raw: String in OS.get_cmdline_user_args():
		var argument: String = raw.strip_edges()
		if argument == "--historical":
			_historical = true
		elif argument == "--quiet":
			_quiet = true
		elif argument.begins_with("--turns="):
			_turns = maxi(argument.trim_prefix("--turns=").to_int(), 1)
		elif argument.begins_with("--seed="):
			_seed = argument.trim_prefix("--seed=").to_int()
		elif argument.begins_with("--size="):
			_size = clampi(
				argument.trim_prefix("--size=").to_int(), 0, GameConfig.SIZES.size() - 1
			)
		elif argument.begins_with("--runs="):
			_runs = maxi(argument.trim_prefix("--runs=").to_int(), 1)
		elif argument.begins_with("--out="):
			_out_dir = argument.trim_prefix("--out=")
		elif not argument.is_empty():
			_fail("unknown argument %s" % argument)


func _ensure_dir() -> void:
	var absolute: String = ProjectSettings.globalize_path(_out_dir)
	if DirAccess.dir_exists_absolute(absolute):
		return
	var error: int = DirAccess.make_dir_recursive_absolute(absolute)
	if error != OK:
		_fail("cannot create %s (error %d)" % [absolute, error])


func _fail(message: String) -> void:
	_failures.append(message)
	printerr("ai_vs_ai: %s" % message)
