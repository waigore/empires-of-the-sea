extends SceneTree
## Headless playtest drive for the workshop: what a multi-turn recipe pays, what
## the ledger says while it serves, and when each unit lands (wiki:
## production-recipes § Turns per unit, § Recipe Catalog, § Acceptance Criteria;
## DR-20261112-11, DR-20261113-02). Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_workshop.gd
##
## The drive opens the turn-100 advanced start, stocks the anvil through the
## crown's own ledger, and presses the PRODUCTION tab's own buttons. Every turn
## goes through `MapPlayTurn` (answering whatever consent the court raises), so
## the tag, the "Next turn" promise, the toast and the stockpile are the game's
## reads, not the drive's.

const Launch = preload("res://playtests/playtest_launch.gd")
const SaveDrive = preload("res://playtests/playtest_save_drive.gd")
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
	await _stockpile_pass()
	await _counsel_pass()
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


## The stockpile itself, as the tab now reads it: holdings grouped by category,
## the phase's promise beside each one, and a manufacture row that stops at the
## ceiling labour and inputs leave (issue #453; wiki: commodity-catalog
## § Categories; stockpiles-and-production § Production flow).
func _stockpile_pass() -> void:
	_say("")
	_say("--- the stockpile: holdings, the phase's promise, the ceiling ---")
	_play.economy.open_panel()
	await process_frame
	var labels: PackedStringArray = PackedStringArray()
	SaveDrive.collect_text(_stockpile(), "", labels)
	for title: String in ["FOOD", "RAW MATERIALS", "MANUFACTURED", "RICHES"]:
		_check("the page groups %s" % title, labels.has(title))
	for id: String in ["grain", "timber", "wool", "gold"]:
		var holding: Dictionary = _holding(id)
		_say("%s: have %s, next %s" % [
			CommodityCatalog.label(id), String(holding["have"]), String(holding["next"]),
		])
		_check(
			"the %s row reads the store" % id,
			String(holding["have"]) == str(_play.economy.economy.quantity(id))
		)
	for widgets: Dictionary in _stockpile().recipe_rows().values():
		var stepper: int = int((widgets["stepper"] as Label).text)
		var allowance: int = int(widgets["allowance"])
		var inert: bool = (widgets["plus"] as Button).disabled
		_say("%s: set %d of a ceiling of %d (%s)" % [
			String((widgets["title"] as Label).text), stepper, allowance,
			(widgets["plus"] as Button).tooltip_text,
		])
		_check(
			"the %s row never offers past its ceiling" % String((widgets["title"] as Label).text),
			stepper <= allowance and inert == (stepper >= allowance)
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
		String(steel["stepper"]), _play.economy.economy.production.assignment_units("steel"),
	])
	_check("the stepper takes the order", String(steel["stepper"]) == "3")
	# The promise nets this phase's harvest, so the drive reads the same table:
	# a mine that yields a ton of the input this turn offsets a run's price.
	var gathered: Dictionary = _play.economy.projected().get("extraction", {}) as Dictionary
	var iron_gathered: int = int(gathered.get("iron", 0))
	var coal_gathered: int = int(gathered.get("coal", 0))
	_check("the promise pays iron this phase", promise.contains("Iron %+d" % (iron_gathered - 3)))
	_check("the promise pays coal this phase", promise.contains("Coal %+d" % (coal_gathered - 3)))
	_check("the promise lands no steel this phase", not promise.contains("Steel +"))
	var iron_before: int = _play.economy.economy.quantity("iron")
	var coal_before: int = _play.economy.economy.quantity("coal")
	_check("the calendar moves", _advance())
	_say("turn %d: steel %d, iron %d -> %d, coal %d -> %d, wip %s" % [
		_play.turn, _play.economy.economy.quantity("steel"), iron_before,
		_play.economy.economy.quantity("iron"), coal_before,
		_play.economy.economy.quantity("coal"), str(_play.economy.economy.production_wip),
	])
	_check(
		"a started run pays its iron",
		_play.economy.economy.quantity("iron") == iron_before + iron_gathered - 3
	)
	_check(
		"a started run pays its coal",
		_play.economy.economy.quantity("coal") == coal_before + coal_gathered - 3
	)
	steel = await _row("Steel")
	_say("Steel row one phase in: %s  ·  tips: %s" % [String(steel["tag"]), _tips(steel)])
	_check("nothing lands in the phase the run started", _play.economy.economy.quantity("steel") == 8)
	_check("the tag names three units and a one-phase wait", String(steel["tag"]) == "3→1t")
	_check("the workshop carries three units", _play.economy.economy.production.wip_units("steel") == 3)
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
	_check("no new run starts for a cleared row", _play.economy.economy.production.wip_units("steel") == 2)
	steel = await _row("Steel")
	# The landing's news is the row's own: the PRODUCTION ledger names what the
	# phase turned out ("Last phase it made 1 Steel."), which is where a crown
	# reads it since the bar's readings moved onto the chips (issue #1121).
	_check("the row names the landing", _tips(steel).contains("made 1 Steel"))
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
	_check("the workshop is spent", _play.economy.economy.production.wip_units("steel") == 0)
	_check("the row falls back to its idle wait", String(steel["tag"]) == "2t")


## The court's own plan on the page: one gold line naming the runs its economy
## pass would book, and the counsel's mark on every row it names, the heading
## printing the legend (wiki: stockpiles-and-production § Production flow;
## DR-20261121-07, DR-20261122-10). A line that books nothing is a gate: it marks
## no row and prints no legend.
func _counsel_pass() -> void:
	_say("")
	_say("--- the court's own plan: the line and the rows it marks ---")
	_play.economy.open_panel()
	await process_frame
	var page: LedgerProduction = _stockpile()
	var counsel: String = page.counsel_text()
	var marked: PackedStringArray = PackedStringArray()
	for widgets: Dictionary in page.recipe_rows().values():
		var title: Label = widgets["title"] as Label
		if title.text.begins_with(LedgerProduction.COURT_MARK):
			marked.append(title.text)
	_say("counsel: %s" % counsel)
	_say("marked rows: %s" % ("none" if marked.is_empty() else ", ".join(marked)))
	_check("the page opens with the court's own line", not counsel.is_empty())
	var books: bool = not counsel.contains("run nothing")
	_check("a plan that books runs marks its rows", marked.size() > 0 if books else marked.is_empty())
	var labels: PackedStringArray = PackedStringArray()
	SaveDrive.collect_text(_play.hud.panels.economy_panel, "", labels)
	_check(
		"the heading prints the mark's legend only when a row wears it",
		labels.has(LedgerProduction.COURT_LEGEND) == (marked.size() > 0)
	)


## The contrast: a one-turn row lands every unit in the phase it runs, and it
## never waits on the anvil — its tag is the last output the phase turned out,
## never a wait (wiki: production-recipes § Turns per unit; § Scope — the
## PRODUCTION ledger names a row's last output, "made 3").
func _one_turn_pass() -> void:
	_say("")
	_say("--- one-turn work: the whole order lands in its phase ---")
	_play.economy.economy.add("timber", 4)
	await _press("Lumber", "+", 2)
	var row: Dictionary = await _row("Lumber")
	var promise: String = _preview()
	_say("Lumber row: stepper %s, promise: %s" % [String(row["stepper"]), promise])
	# The promise is the whole stockpile's movement, so it names the two runs the
	# crown set beside the lumber its colonial towns make: the reading is held to
	# the projection it is worded from, never to a figure the seed picked.
	var seen: Dictionary = _play.economy.projected()
	var seen_delta: int = int(
		(seen.get("stockpile_delta", {}) as Dictionary).get("lumber", 0)
	)
	var far_made: int = int(
		(seen.get("extraction", {}) as Dictionary).get("lumber", 0)
	)
	_check(
		"the one-turn promise lands its units now",
		seen_delta >= 2 and promise.contains("Lumber +%d" % seen_delta)
	)
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
	_check("both units land in one phase", _play.economy.economy.quantity("lumber") == lumber_before + 2 + far_made)
	_check(
		"the timber is paid",
		_play.economy.economy.quantity("timber") == timber_before + harvested - 4
	)
	row = await _row("Lumber")
	_check(
		"a one-turn row's tag is its last output, never a wait",
		String(row["tag"]) == "made 2"
	)
	_check("the tag carries no bench count", not String(row["tag"]).contains("→"))


## Two batches on the anvil at once: the row lands two units a phase, and its
## note must say so instead of promising one. A run of two leaves one bench
## free, so the phase after it starts a second batch of two and the bench reads
## three (wiki: production-recipes § Workshop queue — three pieces at most;
## § Turns per unit; DR-20261113-02, DR-20261114-12). This is the run the
## previous copy got wrong — the note said one a turn while the promise beside
## it read "Steel +2".
func _batches_pass() -> void:
	_say("")
	_say("--- two batches: the row lands what the promise names ---")
	_seed_anvil()
	await _press("Steel", "+", 2)
	_check("the calendar moves", _advance())
	_check("the calendar moves", _advance())
	var row: Dictionary = await _row("Steel")
	var note: String = _tips(row)
	var promise: String = _preview()
	var steel_before: int = _play.economy.economy.quantity("steel")
	_say("Steel row with two batches: tag %s" % String(row["tag"]))
	_say("note: %s" % note)
	_say("promise: %s" % promise)
	_check("two batches serve the anvil", String(row["tag"]) == "3→1t")
	_check("the note counts the units this phase", note.contains("2 landing a turn"))
	_check("the promise names the same two units", promise.contains("Steel +2"))
	_check("the note does not promise a single-batch trickle", not note.contains("landing one a turn"))
	_check("the calendar moves", _advance())
	_say("turn %d: steel %d -> %d" % [
		_play.turn, steel_before, _play.economy.economy.quantity("steel"),
	])
	_check(
		"the phase delivers the two units both lines named",
		_play.economy.economy.quantity("steel") == steel_before + 2
	)
	await _press("Steel", "−", 2)
	# Let the pair drain, so the save pass starts from an idle anvil.
	for _phase in 4:
		if _play.economy.economy.production.wip_units("steel") == 0:
			break
		if not _advance():
			break
	_check("the pair is spent", _play.economy.economy.production.wip_units("steel") == 0)


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
	_check("the anvil comes back whole", _play.economy.economy.production.wip_units("steel") == 2)
	_check("the wait comes back", String(row["tag"]) == "2→1t")
	_check("the calendar moves", _advance())
	_say("turn %d: steel %d -> %d, toast: %s" % [
		_play.turn, steel_before, _play.economy.economy.quantity("steel"), _toast_line(),
	])
	_check(
		"the loaded batch lands one unit",
		_play.economy.economy.quantity("steel") == steel_before + 1
	)
	_check("the rest still serves", _play.economy.economy.production.wip_units("steel") == 1)


# --- ledger reads ----------------------------------------------------------


## The PRODUCTION tab's row for a recipe, as a player reads it: the title, the
## workshop tag (empty when the row never waits), the stepper and the tooltips.
## A row the court's own plan books leads its title with the counsel's mark
## (`▸ Steel`, DR-20261122-10), so the match reads past the mark and keeps it for
## the print.
func _row(title_prefix: String) -> Dictionary:
	_play.economy.open_panel()
	await process_frame
	var found: Dictionary = {}
	for widgets: Dictionary in _stockpile().recipe_rows().values():
		var title: Label = widgets["title"] as Label
		if not _without_mark(title.text).begins_with(title_prefix):
			continue
		found = {
			"title": title.text,
			"tag": (widgets["note"] as Label).text,
			"stepper": (widgets["stepper"] as Label).text,
			"tips": _tooltips(widgets["row"] as Control),
		}
		break
	if found.is_empty():
		_check("the ledger has a %s row" % title_prefix, false)
		return {"title": "", "tag": "", "stepper": "", "tips": ""}
	return found


## A row's title with the court's own mark taken off, so a sheet still finds a
## row the plan books (`LedgerProduction.COURT_MARK`, DR-20261122-10).
func _without_mark(title: String) -> String:
	var mark: String = LedgerProduction.COURT_MARK + " "
	if title.begins_with(mark):
		return title.substr(mark.length())
	return title


## Presses a row's own "−" or "+" `times` times. The panel rebuilds after every
## press, so the button is found again for each one (a player taps the live row).
func _press(title_prefix: String, glyph: String, times: int) -> void:
	for _i in times:
		_play.economy.open_panel()
		await process_frame
		var pressed: bool = false
		for widgets: Dictionary in _stockpile().recipe_rows().values():
			var title: Label = widgets["title"] as Label
			if not _without_mark(title.text).begins_with(title_prefix):
				continue
			var key: String = "plus" if glyph == "+" else "minus"
			(widgets[key] as Button).emit_signal("pressed")
			pressed = true
			break
		if not pressed:
			_check("the %s row answers %s" % [title_prefix, glyph], false)
			return


## The stockpile page the tab builds (LedgerProduction), read through the row
## accessors the page publishes instead of its children (REQ-P3-02).
func _stockpile() -> LedgerProduction:
	return (
		_play.hud.panels.economy_panel.page_body(EconomyPanel.TAB_PRODUCTION)
		as LedgerProduction
	)


## A holding as the page draws it: the units the court has and the figure the
## phase promises beside them.
func _holding(id: String) -> Dictionary:
	var widgets: Dictionary = _stockpile().holding_rows().get(id, {})
	if widgets.is_empty():
		_check("the stockpile has a %s row" % id, false)
		return {"have": "", "next": ""}
	return {
		"have": (widgets["have"] as Label).text,
		"next": (widgets["next"] as Label).text,
	}


func _preview() -> String:
	var labels: PackedStringArray = PackedStringArray()
	SaveDrive.collect_text(_play.hud.panels.economy_panel, "", labels)
	for text: String in labels:
		if text.begins_with("Next turn:"):
			return text
	return "no preview line"


## Every tooltip the row carries (title, workshop tag, stepper buttons): a long
## press or a hover is where the row's meaning is spelled out.
func _tooltips(row: Control) -> String:
	var found: Array[String] = []
	_collect_tips(row, found)
	return " | ".join(found)


func _tips(row: Dictionary) -> String:
	return String(row.get("tips", ""))


## The turn's own summary line from the toast box (LedgerReportText.turn_summary).
func _toast_line() -> String:
	var labels: PackedStringArray = PackedStringArray()
	SaveDrive.collect_text(_play.hud.despatches.box, "", labels)
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
