extends SceneTree
## Headless playtest drive for the workshop: what a multi-turn recipe pays, what
## the ledger says while it serves, and when each unit lands (wiki:
## production-recipes § Turns per unit, § Recipe Catalog, § Acceptance Criteria;
## DR-20261112-11, DR-20261113-02). Not a CI gate — run it by hand:
##   godot --headless --path . --script res://tests/playtest_workshop.gd
##
## The drive opens the turn-100 advanced start, stocks the anvil through the
## crown's own ledger, and presses the PRODUCTION tab's own buttons. Every turn
## goes through `MapPlayTurn` (answering whatever consent the court raises), so
## the tag, the "Next turn" promise, the toast and the stockpile are the game's
## reads, not the drive's.

const Launch = preload("res://tests/playtest_launch.gd")
const SaveDrive = preload("res://tests/playtest_save_drive.gd")
const SEED_TEXT: String = "1500"
## A directory of its own, so a hand run never touches the player's slots.
const DIR: String = "user://playtest_workshop"
const SLOT: int = 1

var _steps: PackedStringArray = PackedStringArray()
var _failures: int = 0
var _screen: MapScreen = null
var _play: PlaySession = null
var _main: Node = null


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
	_say("seed %s — %s, turn %d, %d steel in the store" % [
		SEED_TEXT, FactionCatalog.name_of(_play.player_faction), _play.turn,
		_play.economy.economy.quantity("steel"),
	])
	await _idle_pass()
	await _start_pass()
	await _landing_pass()
	await _one_turn_pass()
	await _batches_pass()
	await _save_pass()
	_finish()


# --- passes ----------------------------------------------------------------


## The row as an idle player meets it: what a multi-turn recipe will cost, how
## long it waits, and what the tooltip promises before anything is ordered.
func _idle_pass() -> void:
	_say("")
	_say("--- an idle anvil: the row before anything is ordered ---")
	var steel: Dictionary = await _row("Steel")
	_say("Steel row: %s  ·  tag \\\"%s\\\"  ·  tips: %s" % [
		String(steel["title"]), String(steel["tag"]), _tips(steel),
	])
	_check("an idle alloy row names its wait (2t)", steel["tag"] == "2t")
	_check(
		"the tooltip says a run takes two turns",
		_tips(steel).contains("2 turns per run")
	)
	_check(
		"the tooltip promises one unit a turn once it is serving",
		_tips(steel).contains("lands one unit a turn")
	)
	var lumber: Dictionary = await _row("Lumber")
	_say("Lumber row: %s  ·  tag \\\"%s\\\"  ·  tips: %s" % [
		String(lumber["title"]), String(lumber["tag"]), _tips(lumber),
	])
	_check("a one-turn row carries no workshop tag", String(lumber["tag"]).is_empty())
	_check(
		"a one-turn tooltip never promises a wait",
		not _tips(lumber).contains("turns per run")
	)


## Three steel ordered from the row's own "+": the promise names the inputs this
## phase pays and lands no steel, and the close pays them exactly once.
func _start_pass() -> void:
	_say("")
	_say("--- ordering three steel: the price now, the unit later ---")
	_seed_anvil()
	await _press("Steel", "+", 3)
	var steel: Dictionary = await _row("Steel")
	var promise: String = _preview()
	_say("Steel row after the press: %s  ·  promise: %s" % [String(steel["title"]), promise])
	_say("stepper: %s, assignment: %d" % [
		String(steel["stepper"]), _play.economy.economy.assignment_units("steel"),
	])
	_check("the stepper takes the order", String(steel["stepper"]) == "3")
	_check("the promise pays iron this phase", promise.contains("Iron -3"))
	_check("the promise pays coal this phase", promise.contains("Coal -3"))
	_check("the promise lands no steel this phase", not promise.contains("Steel +"))
	var iron_before: int = _play.economy.economy.quantity("iron")
	var coal_before: int = _play.economy.economy.quantity("coal")
	_check("the calendar moves", _advance())
	_say("turn %d: steel %d, iron %d -> %d, coal %d -> %d, wip %s" % [
		_play.turn, _play.economy.economy.quantity("steel"), iron_before,
		_play.economy.economy.quantity("iron"), coal_before,
		_play.economy.economy.quantity("coal"), str(_play.economy.economy.production_wip),
	])
	_check("a started run pays its iron", _play.economy.economy.quantity("iron") == iron_before - 3)
	_check("a started run pays its coal", _play.economy.economy.quantity("coal") == coal_before - 3)
	steel = await _row("Steel")
	_say("Steel row one phase in: %s  ·  tips: %s" % [String(steel["tag"]), _tips(steel)])
	_check("nothing lands in the phase the run started", _play.economy.economy.quantity("steel") == 8)
	_check("the tag names three units and a one-phase wait", String(steel["tag"]) == "3→1t")
	_check("the workshop carries three units", _play.economy.economy.wip_units("steel") == 3)
	_check(
		"the serving tooltip says three units are on the anvil",
		_tips(steel).contains("3 units already in the workshop")
	)
	_check("the turn's toast names no steel yet", not _toast_line().contains("Steel +"))


## Cleared mid-batch: no new run starts, and the paid-for batch still lands one
## unit a Production phase until it is spent.
func _landing_pass() -> void:
	_say("")
	_say("--- clearing the assignment: the paid batch still lands ---")
	await _press("Steel", "−", 3)
	var steel: Dictionary = await _row("Steel")
	_say("Steel row with the order cleared: stepper %s, tag %s" % [
		String(steel["stepper"]), String(steel["tag"]),
	])
	_check("the stepper clears to zero", String(steel["stepper"]) == "0")
	_check("the batch keeps serving", String(steel["tag"]) == "3→1t")
	var iron_before: int = _play.economy.economy.quantity("iron")
	var steel_before: int = _play.economy.economy.quantity("steel")
	_check("the calendar moves", _advance())
	_say("turn %d: steel %d, iron %d, toast: %s" % [
		_play.turn, _play.economy.economy.quantity("steel"),
		_play.economy.economy.quantity("iron"), _toast_line(),
	])
	_check("one unit lands a phase", _play.economy.economy.quantity("steel") == steel_before + 1)
	_check("a carried batch pays nothing", _play.economy.economy.quantity("iron") == iron_before)
	_check("no new run starts for a cleared row", _play.economy.economy.wip_units("steel") == 2)
	_check("the toast names the landing", _toast_line().contains("Steel +1"))
	steel = await _row("Steel")
	_check("the tag walks down to two", String(steel["tag"]) == "2→1t")
	_check("the calendar moves", _advance())
	steel = await _row("Steel")
	_say("turn %d: steel %d, tag %s" % [
		_play.turn, _play.economy.economy.quantity("steel"), String(steel["tag"]),
	])
	_check("the second unit lands", _play.economy.economy.quantity("steel") == steel_before + 2)
	_check("the tag walks down to one", String(steel["tag"]) == "1→1t")
	_check("the calendar moves", _advance())
	steel = await _row("Steel")
	_say("turn %d: steel %d, tag %s, wip %s" % [
		_play.turn, _play.economy.economy.quantity("steel"), String(steel["tag"]),
		str(_play.economy.economy.production_wip),
	])
	_check("the last unit lands", _play.economy.economy.quantity("steel") == steel_before + 3)
	_check("the workshop is spent", _play.economy.economy.wip_units("steel") == 0)
	_check("the row falls back to its idle wait", String(steel["tag"]) == "2t")


## The contrast: a one-turn row lands every unit in the phase it runs, and no
## workshop tag ever appears for it (wiki: production-recipes § Turns per unit).
func _one_turn_pass() -> void:
	_say("")
	_say("--- one-turn work: the whole order lands in its phase ---")
	_play.economy.economy.add("timber", 4)
	await _press("Lumber", "+", 2)
	var row: Dictionary = await _row("Lumber")
	var promise: String = _preview()
	_say("Lumber row: stepper %s, promise: %s" % [String(row["stepper"]), promise])
	_check("the one-turn promise lands its units now", promise.contains("Lumber +2"))
	var lumber_before: int = _play.economy.economy.quantity("lumber")
	var timber_before: int = _play.economy.economy.quantity("timber")
	# The turn gathers timber before the workshop spends it, so the check reads the
	# promise's own harvest beside the order's price.
	var harvested: int = int(
		(_play.economy.projected().get("extraction", {}) as Dictionary).get("timber", 0)
	)
	_check("the calendar moves", _advance())
	_say("turn %d: lumber %d -> %d, timber %d -> %d (harvest +%d)" % [
		_play.turn, lumber_before, _play.economy.economy.quantity("lumber"),
		timber_before, _play.economy.economy.quantity("timber"), harvested,
	])
	_check("both units land in one phase", _play.economy.economy.quantity("lumber") == lumber_before + 2)
	_check(
		"the timber is paid",
		_play.economy.economy.quantity("timber") == timber_before + harvested - 4
	)
	row = await _row("Lumber")
	_check("a one-turn row never grows a workshop tag", String(row["tag"]).is_empty())


## Two batches ordered a phase apart: the row lands two units a phase, and its
## note must say so instead of promising one. This is the run the previous copy
## got wrong — the tag read 5→1t while the note said one a turn, and the promise
## beside it read "Steel +2" (wiki: production-recipes § Turns per unit;
## DR-20261113-02).
func _batches_pass() -> void:
	_say("")
	_say("--- two batches: the row lands what the promise names ---")
	_seed_anvil()
	await _press("Steel", "+", 3)
	_check("the calendar moves", _advance())
	_check("the calendar moves", _advance())
	var row: Dictionary = await _row("Steel")
	var note: String = _tips(row)
	var promise: String = _preview()
	var steel_before: int = _play.economy.economy.quantity("steel")
	_say("Steel row with two batches: tag %s" % String(row["tag"]))
	_say("note: %s" % note)
	_say("promise: %s" % promise)
	_check("two batches serve the anvil", String(row["tag"]) == "5→1t")
	_check("the note counts the units this phase", note.contains("2 land in 1 turn"))
	_check("the promise names the same two units", promise.contains("Steel +2"))
	_check("the note keeps the per-batch cadence", note.contains("Each batch lands one a turn"))
	_check("the calendar moves", _advance())
	_say("turn %d: steel %d -> %d" % [
		_play.turn, steel_before, _play.economy.economy.quantity("steel"),
	])
	_check(
		"the phase delivers the two units both lines named",
		_play.economy.economy.quantity("steel") == steel_before + 2
	)
	await _press("Steel", "−", 3)
	# Let the pair drain, so the save pass starts from an idle anvil.
	for _phase in 4:
		if _play.economy.economy.wip_units("steel") == 0:
			break
		if not _advance():
			break
	_check("the pair is spent", _play.economy.economy.wip_units("steel") == 0)


## A batch on the anvil rides the save: the loaded court keeps the units and the
## wait, and lands them on the same cadence (wiki: production-recipes
## § Acceptance Criteria).
func _save_pass() -> void:
	_say("")
	_say("--- the anvil in a save ---")
	_play.economy.economy.add("iron", 2)
	_play.economy.economy.add("coal", 2)
	await _press("Steel", "+", 2)
	_check("the calendar moves", _advance())
	var row: Dictionary = await _row("Steel")
	var steel_before: int = _play.economy.economy.quantity("steel")
	_say("turn %d: tag %s, wip %s" % [
		_play.turn, String(row["tag"]), str(_play.economy.economy.production_wip),
	])
	_check("two steel serve the anvil", String(row["tag"]) == "2→1t")
	_say("save: \\\"%s\\\"" % SaveDrive.save_slot(_screen, SLOT))
	_screen = SaveDrive.load_slot(_screen, _main, SLOT)
	if _screen == null:
		_check("the loaded campaign comes back", false)
		return
	_play = _screen.play
	await process_frame
	row = await _row("Steel")
	_say("after the load: turn %d, steel %d, tag %s, wip %s" % [
		_play.turn, _play.economy.economy.quantity("steel"), String(row["tag"]),
		str(_play.economy.economy.production_wip),
	])
	_check("the anvil comes back whole", _play.economy.economy.wip_units("steel") == 2)
	_check("the wait comes back", String(row["tag"]) == "2→1t")
	_check("the calendar moves", _advance())
	_say("turn %d: steel %d -> %d, toast: %s" % [
		_play.turn, steel_before, _play.economy.economy.quantity("steel"), _toast_line(),
	])
	_check(
		"the loaded batch lands one unit",
		_play.economy.economy.quantity("steel") == steel_before + 1
	)
	_check("the rest still serves", _play.economy.economy.wip_units("steel") == 1)


# --- ledger reads ----------------------------------------------------------


## The PRODUCTION tab's row for a recipe, as a player reads it: the title, the
## workshop tag (empty when the row never waits), the stepper and the tooltips.
func _row(title_prefix: String) -> Dictionary:
	_play.economy.open_panel()
	await process_frame
	var found: Dictionary = {}
	for child: Node in _body().get_children():
		if not (child is HBoxContainer):
			continue
		var labels: PackedStringArray = PackedStringArray()
		SaveDrive.collect_text(child, "", labels)
		if labels.size() < 4 or not labels[0].begins_with(title_prefix):
			continue
		var tips: Array[String] = []
		_collect_tips(child, tips)
		found = {
			"title": labels[0],
			"tag": labels[1] if labels.size() == 5 else "",
			"stepper": labels[labels.size() - 3],
			"tips": " | ".join(tips),
		}
		break
	if found.is_empty():
		_check("the ledger has a %s row" % title_prefix, false)
		return {"title": "", "tag": "", "stepper": "", "tips": ""}
	return found


## Presses a row's own "−" or "+" `times` times. The panel rebuilds after every
## press, so the button is found again for each one (a player taps the live row).
func _press(title_prefix: String, glyph: String, times: int) -> void:
	for _i in times:
		_play.economy.open_panel()
		await process_frame
		var pressed: bool = false
		for child: Node in _body().get_children():
			if not (child is HBoxContainer):
				continue
			var labels: PackedStringArray = PackedStringArray()
			SaveDrive.collect_text(child, "", labels)
			if labels.is_empty() or not labels[0].begins_with(title_prefix):
				continue
			for sub: Node in child.get_children():
				if sub is Button and (sub as Button).text == glyph:
					(sub as Button).emit_signal("pressed")
					pressed = true
			break
		if not pressed:
			_check("the %s row answers %s" % [title_prefix, glyph], false)
			return


func _body() -> Node:
	return _play.hud.panels.economy_panel.page_body("PRODUCTION")


func _preview() -> String:
	var labels: PackedStringArray = PackedStringArray()
	SaveDrive.collect_text(_play.hud.panels.economy_panel, "", labels)
	for text: String in labels:
		if text.begins_with("Next turn:"):
			return text
	return "no preview line"


func _tips(row: Dictionary) -> String:
	return String(row.get("tips", ""))


## The turn's own summary line from the toast box (LedgerText.turn_summary).
func _toast_line() -> String:
	var labels: PackedStringArray = PackedStringArray()
	SaveDrive.collect_text(_play.hud._toast_box, "", labels)
	var best: String = ""
	for text: String in labels:
		if text.contains("gathered") or text.contains("researched") \
				or text.contains("Steel +") or text.contains("Lumber +") \
				or text.contains("ducats") or text.contains("the ledgers balance"):
			best = text
	return best if not best.is_empty() else ("none" if labels.is_empty() else labels[labels.size() - 1])


func _collect_tips(node: Node, into: Array[String]) -> void:
	if node is Control:
		var control: Control = node
		if not control.tooltip_text.is_empty():
			into.append(control.tooltip_text)
	for child: Node in node.get_children():
		_collect_tips(child, into)


# --- turns -----------------------------------------------------------------


## Stocks the anvil with the raw inputs three steel and a lumber order need, so
## the run is affordable (the turn-100 court holds none of them).
func _seed_anvil() -> void:
	var economy: PlayerEconomy = _play.economy.economy
	economy.add("iron", maxi(6 - economy.quantity("iron"), 0))
	economy.add("coal", maxi(6 - economy.quantity("coal"), 0))
	_larder()
	_play.economy.refresh_panel()


## This drive reads the workshop, not the larder: fed workers keep the full
## labour a run needs, so a starving court cannot shrink an order mid-pass.
func _larder() -> void:
	var economy: PlayerEconomy = _play.economy.economy
	economy.add("grain", maxi(400 - economy.quantity("grain"), 0))
	economy.add("meat", maxi(60 - economy.quantity("meat"), 0))


## Closes one turn, answering whatever consent decision a rival court raised.
func _advance() -> bool:
	return SaveDrive.advance(_play)


# --- report ----------------------------------------------------------------


func _check(label: String, ok: bool) -> void:
	if ok:
		return
	_failures += 1
	_say("FAIL: %s" % label)


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_workshop: %d steps, %d failure(s) ---" % [_steps.size(), _failures])
	quit()
