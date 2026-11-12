extends SceneTree
## Headless playtest drive for a save taken from a campaign advanced by play:
## turns closed, a study started from the college's own row, an estate raised
## from the estates ledger. The slot is written and read back through the pause
## menu, and the drive then compares the two snapshots field by field and reads
## the surfaces a player would (college slots, estate row, purse chip, crown
## plan) — so a save that drops advanced state is named, not guessed at
## (wiki: campaign-persistence § Snapshot contract; research-state § Slot
## Occupancy Persistence; extraction-and-improvements). Not a CI gate — run it
## by hand:
##   godot --headless --path . --script res://tests/playtest_persistence_advanced.gd

const Launch = preload("res://tests/playtest_launch.gd")
const SaveDrive = preload("res://tests/playtest_save_drive.gd")
const SEED_TEXT: String = "1500"
## A directory of its own, so a hand run never touches the player's slots.
const DIR: String = "user://playtest_persistence_advanced"
const SLOT: int = 1
const TURNS: int = 3
## Snapshot keys that are expected to differ between two captures.
const VOLATILE: Array[String] = ["saved_at", "game_version"]

var _steps: PackedStringArray = PackedStringArray()
var _failures: int = 0
var _screen: MapScreen = null
var _play: PlaySession = null
var _main: Node = null
var _estate_tile: Vector2i = Vector2i(-1, -1)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	SaveDrive.clean_dir(DIR)
	_screen = await Launch.open_map(self, SEED_TEXT, 0, AdvancedStart.TURNS100)
	if _screen == null:
		_finish()
		return
	_main = _screen.get_parent()
	_screen.save_dir = DIR
	_play = _screen.play
	_say("seed %s — %s, turn %d, treasury %d" % [
		SEED_TEXT, FactionCatalog.name_of(_play.player_faction), _play.turn,
		_play.treasury(),
	])
	for _i in TURNS:
		if not SaveDrive.advance(_play):
			_say("the calendar never moved past turn %d" % _play.turn)
			break
	_say("after %d turns: turn %d, treasury %d" % [TURNS, _play.turn, _play.treasury()])
	await _start_study()
	await _build_estate()
	await process_frame
	var before: Dictionary = SaveCodec.capture(_play)
	var reads_before: Dictionary = _reads()
	var treasury_before: int = _play.treasury()
	_say("save: \"%s\"" % SaveDrive.save_slot(_screen, SLOT))
	_screen = SaveDrive.load_slot(_screen, _main, SLOT)
	if _screen == null:
		_say("the load replaced the screen with something else")
		_finish()
		return
	_play = _screen.play
	await process_frame
	var after: Dictionary = SaveCodec.capture(_play)
	_say("after the load: turn %d, treasury %d (saved %d)" % [
		_play.turn, _play.treasury(), treasury_before,
	])
	_check("the turn comes back", _play.turn == int((before["session"] as Dictionary)["turn"]))
	_check("the purse comes back", _play.treasury() == treasury_before)
	var drift: PackedStringArray = PackedStringArray()
	_diff("", before, after, drift)
	_say("snapshot drift: %s" % ("none" if drift.is_empty() else ", ".join(drift)))
	_check("the snapshot round-trips", drift.is_empty())
	var reads_after: Dictionary = _reads()
	for key: String in reads_before.keys():
		var was: String = String(reads_before[key])
		var now: String = String(reads_after.get(key, "<missing>"))
		_say("%s: %s" % [key, was if was == now else "CHANGED — was \"%s\", now \"%s\"" % [was, now]])
		_check("the %s reads the same after the load" % key, was == now)
	_finish()


# --- the advanced state ------------------------------------------------------


## Starts the first advance the college offers with a free slot, through the
## panel's own Research button (wiki: research-state § Research Slots).
func _start_study() -> void:
	_play.economy.open_research()
	await process_frame
	var button: Button = _find_open_study(_play.hud.panels.research_panel)
	if button == null:
		_say("the college offers no open advance")
	else:
		button.emit_signal("pressed")
		await process_frame
		_say("study started: %s" % " | ".join(_college_slots()))
	_play.hud.panels.hide_research()


func _find_open_study(node: Node) -> Button:
	if node is Button:
		var button: Button = node
		if button.text == "Research" and not button.disabled:
			return button
	for child: Node in node.get_children():
		var found: Button = _find_open_study(child)
		if found != null:
			return found
	return null


## Raises the first vacant estate the ledger says a Builder can take, and closes
## turns until the work lands (wiki: extraction-and-improvements).
func _build_estate() -> void:
	var snapshot: Dictionary = ImprovementLedger.snapshot(
		_play.model, _play.land_works, _play.civilian_layer.units, _play.stockpile(),
		_play.player_faction, _play.capital_tile, _play.tech_caps()
	)
	for group: Dictionary in snapshot["groups"]:
		for row: Dictionary in group["rows"]:
			if not bool(row["can_build"]) or int(row["level"]) > 0:
				continue
			var tile: Vector2i = row["tile"]
			var order: Dictionary = ImprovementOrders.build(
				_play.model, _play.civilian_layer.units, _play.land_works,
				_play.stockpile(), _play.visibility, _play.player_faction, tile,
				_play.tech_caps(), _play.tech_unlocked()
			)
			if not bool(order.get("ok", false)):
				continue
			_estate_tile = tile
			_say("builder sent to %s — %s" % [str(tile), String(order["message"])])
			for _i in 8:
				var live: Dictionary = _estate_row()
				if live.is_empty() or String(live["status"]) != "building":
					break
				if not SaveDrive.advance(_play):
					break
			_say("estate after the build: %s" % _estate_line())
			return
	_say("no estate could be built")


# --- reads -------------------------------------------------------------------


func _reads() -> Dictionary:
	var out: Dictionary = {}
	_play.economy.open_research()
	out["college"] = " | ".join(_college_slots())
	_play.hud.panels.hide_research()
	out["estate"] = _estate_line()
	out["purse"] = _chip_line()
	out["plan"] = _plan_line()
	return out


func _college_slots() -> Array[String]:
	var out: Array[String] = []
	for node: Node in _play.hud.panels.research_panel.find_children("*", "HBoxContainer", true, false):
		if not (node is ResearchSlotRow):
			continue
		var texts: PackedStringArray = PackedStringArray()
		SaveDrive.collect_text(node, "", texts)
		if not texts.is_empty():
			out.append(" / ".join(texts))
	return out


func _estate_row() -> Dictionary:
	if _estate_tile.x < 0:
		return {}
	var snapshot: Dictionary = ImprovementLedger.snapshot(
		_play.model, _play.land_works, _play.civilian_layer.units, _play.stockpile(),
		_play.player_faction, _play.capital_tile, _play.tech_caps()
	)
	for group: Dictionary in snapshot["groups"]:
		for row: Dictionary in group["rows"]:
			if Vector2i(row["tile"]) == _estate_tile:
				return row
	return {}


func _estate_line() -> String:
	var row: Dictionary = _estate_row()
	if row.is_empty():
		return "no estate"
	return "level %d, %s, output %d, %s" % [
		int(row["level"]), String(row["status"]), int(row["output"]),
		String(row["status_text"]),
	]


func _chip_line() -> String:
	return "%s / %s" % [_play.hud._treasury_label.text, _play.hud._income_label.text]


## The dossier line the player taps to cycle the crown's plan.
func _plan_line() -> String:
	var army: ArmyState = null
	for candidate: ArmyState in _play.army_layer.armies:
		if candidate.owner == _play.player_faction:
			army = candidate
			break
	if army == null:
		return "no army"
	MapPlayArmies.show_panel(_play, army)
	var parts: PackedStringArray = PackedStringArray()
	SaveDrive.collect_text(_play.hud.panels.army_panel, "Crown battle plan:", parts)
	_play.hud.panels.hide_army()
	return parts[0] if not parts.is_empty() else "no plan line"


# --- snapshot diff -----------------------------------------------------------


## Walks both captures and appends one line per field that differs. Volatile
## keys (the write time) are skipped at the top level.
func _diff(path: String, a: Variant, b: Variant, into: PackedStringArray) -> void:
	if typeof(a) != typeof(b):
		into.append("%s: type %s -> %s" % [path, type_string(typeof(a)), type_string(typeof(b))])
		return
	match typeof(a):
		TYPE_DICTIONARY:
			var da: Dictionary = a
			var db: Dictionary = b
			for key: Variant in da.keys():
				if path.is_empty() and VOLATILE.has(String(key)):
					continue
				if not db.has(key):
					into.append("%s/%s: missing after load" % [path, str(key)])
					continue
				_diff("%s/%s" % [path, str(key)], da[key], db[key], into)
			for key: Variant in db.keys():
				if path.is_empty() and VOLATILE.has(String(key)):
					continue
				if not da.has(key):
					into.append("%s/%s: new after load" % [path, str(key)])
		TYPE_ARRAY:
			var aa: Array = a
			var ab: Array = b
			if aa.size() != ab.size():
				into.append("%s: size %d -> %d" % [path, aa.size(), ab.size()])
				return
			for i in aa.size():
				_diff("%s[%d]" % [path, i], aa[i], ab[i], into)
		_:
			if str(a) != str(b):
				into.append("%s: %s -> %s" % [path, str(a), str(b)])


# --- reporting ---------------------------------------------------------------


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	_say("%s %s" % ["ok  " if ok else "FAIL", label])


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	_say("RESULT: %s" % ("PASS" if _failures == 0 else "%d FAILURE(S)" % _failures))
	print("\n--- playtest_persistence_advanced: %d steps ---" % _steps.size())
	SaveDrive.clean_dir(DIR)
	quit(0 if _failures == 0 else 1)
