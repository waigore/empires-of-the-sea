extends SceneTree
## Headless free-playtest drive for the line the crown's raise sheets print under
## their one press (wiki: civilian-units § One press files what the realm can
## raise; DR-20261118-12, DR-20261118-17).
##
##   godot --headless --path . --script res://playtests/playtest_raise_line.gd
##
## The towns, the walls, the hospitals and the estates sheets price the line
## before the crown signs, so the one number a crown reads is a promise about what
## the second tap will spend and raise. The drive reads that promise the way a
## player does — off the printed line — and then holds the press to it: the raised
## count against the line's own "n of m wait", the materials the line names
## against the stores that actually leave, the hands it names against the crews
## that go to work.
##
## The state no rule test covers is the crown that holds a crew on each chart: the
## three crown sheets read both charts at once, and a Builder in the New World
## must never be spent on an Old World town (DR-20261118-17). The drive seats it
## the way a colonial crown reaches it — a charter town and one Builder across
## the water beside the home crews.
##
## Not a CI gate. A failure prints "FAIL: …" and the run exits non-zero.

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
## England: a Great Power that is not FactionCatalog.PLAYER_FACTION, so a sheet
## that reads a defaulted crown instead of the session's own is visible here.
const NATION: int = 1
## The first id the drive mints for the crews it seats; the campaign's own roster
## is well under this.
const FIRST_SEATED_ID: int = 900

var _steps: PackedStringArray = PackedStringArray()
var _failures: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null
var _play: PlaySession = null
var _next_crew_id: int = FIRST_SEATED_ID


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_screen = await Launch.open_map(self, SEED_TEXT, 0, "", NATION)
	if _screen == null:
		_finish()
		return
	_play = _screen.play
	_say("%s (faction %d), seed %s, turn %d, purse %d, idle crews %s" % [
		FactionCatalog.name_of(_play.player_faction), _play.player_faction, SEED_TEXT,
		_play.turn, int(_play.economy.economy.treasury), str(_idle_by_trade()),
	])
	# The opening towns sheet is all locked: a crown holds no town step before
	# National Bureaucracy. The drive seats the study rather than spending turns
	# on the tree — the line under the press is what is under test.
	_play.tech_unlocked()["national_bureaucracy"] = true
	_play.tech_unlocked()["fortification"] = true
	await _sheet_pass(HudLedgerDoors.TOWNS, "the opening town ledger", "builder")
	await _short_stores_pass()
	await _two_charts_pass()
	await _walls_pass()
	await _estates_pass()
	_handset_pass()
	_finish()


# --- the sheets' promise -----------------------------------------------------


## One raise sheet read as a player reads it: the face, the line, the two taps,
## the receipt — then the line's promise held against what the taps spent.
func _sheet_pass(door: String, title: String, trade: String) -> void:
	_say("")
	_say("--- %s ---" % title)
	HudLedgerDoors.open(_screen.hud, door)
	await process_frame
	var sheet: RaiseLedgerPanel = HudLedgerDoors.sheet_for(_screen.hud, door) as RaiseLedgerPanel
	if sheet == null:
		_check(false, "the %s is mounted" % title)
		return
	var read: Dictionary = _read_sheet(sheet, trade)
	if int(read["ready"]) == 0:
		_say("the sheet holds nothing ready this turn — pass skipped")
		sheet.close()
		return
	var receipt: String = await _press(sheet)
	_hold_the_promise(read, receipt, trade)
	sheet.close()
	await process_frame


## The towns sheet with the stores short: the line must name how many ready rows
## wait and why, and the press must file exactly the rest.
func _short_stores_pass() -> void:
	_say("")
	_say("--- the town ledger with the stores short ---")
	_seed_crews(0, 2)
	_play.economy.economy.stockpile["lumber"] = 5
	_play.economy.economy.stockpile["castIron"] = 5
	HudLedgerDoors.open(_screen.hud, HudLedgerDoors.TOWNS)
	await process_frame
	var sheet: TownLedgerPanel = _screen.hud.towns_ledger
	var read: Dictionary = _read_sheet(sheet, "builder")
	if int(read["ready"]) == 0:
		_say("the sheet holds nothing ready on five lumber — pass skipped")
		sheet.close()
		return
	_check(
		String(read["line"]).contains("Stores are short of"),
		"the line names the stores' own shortfall"
	)
	var receipt: String = await _press(sheet)
	_hold_the_promise(read, receipt, "builder")
	sheet.close()
	await process_frame


## A crown with crews on both charts: the towns sheet reads both at once, and the
## walk may only send each chart's own Builder to its own towns (DR-20261118-17).
func _two_charts_pass() -> void:
	_say("")
	_say("--- the town ledger with a Builder on each chart ---")
	var abroad: MapModel = _play.world.region(1)
	var host: int = -1
	if abroad != null:
		for province: ProvinceState in abroad.provinces:
			if province != null and province.has_town():
				host = province.id
				break
	if abroad == null or host < 0:
		_say("no New World town to charter — pass skipped")
		return
	# The charter: the province is the crown's, its town stands at I, and one
	# Builder works that chart, as a colonial crown keeps one.
	abroad.provinces[host].owner = _play.player_faction
	abroad.provinces[host].town_development = 1
	_seed_crews(1, 1)
	_seed_crews(0, 1)
	_play.economy.economy.stockpile["lumber"] = 40
	_play.economy.economy.stockpile["castIron"] = 40
	_say("charter %s at level I, one Builder across the water; idle crews %s" % [
		abroad.provinces[host].name, str(_idle_by_trade()),
	])
	_say("charts %d, kingdom's own provinces on the new chart %d" % [
		_play.world.region_count(), _owned_provinces(abroad),
	])
	HudLedgerDoors.open(_screen.hud, HudLedgerDoors.TOWNS)
	await process_frame
	var sheet: TownLedgerPanel = _screen.hud.towns_ledger
	var read: Dictionary = _read_sheet(sheet, "builder")
	if int(read["ready"]) == 0:
		_say("the sheet holds nothing ready with a charter — pass skipped")
		sheet.close()
		return
	# The claim the pooled walk broke: the line spends the hands of the charts its
	# ready rows stand on, never the realm's whole roll of that trade.
	var realm: int = int(_idle_by_trade().get("builder", 0))
	_check(
		int(read["crews"]) <= int(read["ready"]),
		"the line names %d Builder(s) for %d ready town(s)" % [
			int(read["crews"]), int(read["ready"]),
		]
	)
	_check(
		int(read["crews"]) <= realm,
		"the line never spends more hands than the realm holds (%d of %d)" % [
			int(read["crews"]), realm,
		]
	)
	var receipt: String = await _press(sheet)
	_hold_the_promise(read, receipt, "builder")
	sheet.close()
	await process_frame


## The walls sheet: the same line, the other trade.
func _walls_pass() -> void:
	_seed_crews(0, 1, "engineer")
	_play.economy.economy.stockpile["lumber"] = 40
	_play.economy.economy.stockpile["bronze"] = 12
	await _sheet_pass(HudLedgerDoors.WALLS, "the walls ledger", "engineer")


## The estates card: one chart, one Builder's worth of hands, and a price that
## moves with the stores as the orders file (the H8 bootstrap).
func _estates_pass() -> void:
	_say("")
	_say("--- the estates card ---")
	var estates: ImprovementPanel = _play.improvements
	if estates == null:
		_say("no estates card on this screen — pass skipped")
		return
	_seed_crews(0, 1)
	_play.economy.economy.stockpile["lumber"] = 4
	_play.economy.economy.stockpile["castIron"] = 0
	# The card is opened on the province a crown is reading; the drive takes the
	# first province whose estates its one Builder could start.
	var province: int = _first_ready_province(estates)
	if province < 0:
		_say("no province offers a ready estate — pass skipped")
		return
	estates.open(province)
	estates.refresh()
	await process_frame
	var tiles: Array[Vector2i] = estates._ready_tiles()
	var line: String = estates._line.text
	var stores: Dictionary = _play.economy.economy.stockpile.duplicate()
	var working: int = _working_crews()
	_say("province %d: %d ready estate(s), face \"%s\"" % [
		province, tiles.size(), estates._batch.text,
	])
	_say("line: \"%s\"" % line)
	if tiles.is_empty():
		_say("the card offers nothing ready — pass skipped")
		estates.close()
		return
	_check(not line.is_empty(), "the card prices the line under its press")
	var receipt: String = await _press(estates)
	_say("receipt: \"%s\"" % receipt)
	_check(
		_raised_from(receipt) == _promised(line, tiles.size()),
		"the card raised %d of the %d its line promised" % [
			_raised_from(receipt), _promised(line, tiles.size()),
		]
	)
	_check_shopping(line, stores, working, "builder")
	estates.close()
	await process_frame


# --- readings ----------------------------------------------------------------


## What a raise sheet prints before it is pressed: the face, the line, and the
## counts the line's words are held against.
func _read_sheet(sheet: RaiseLedgerPanel, trade: String) -> Dictionary:
	var line: String = sheet._line.text if sheet._line != null else ""
	var reading: Dictionary = {
		"ready": sheet._ready_targets().size(),
		"face": sheet._batch.text if sheet._batch != null else "",
		"line": line,
		"shown": sheet._line.visible if sheet._line != null else false,
		"crews": _named_crews(line, trade),
		"stores": _play.economy.economy.stockpile.duplicate(),
		"working": _working_crews(),
	}
	_say("rows ready %d (%s), face \"%s\"" % [
		int(reading["ready"]), str(_ready_by_chart(sheet)), String(reading["face"]),
	])
	_say("line: \"%s\" (shown %s)" % [line, str(reading["shown"])])
	_check(bool(reading["shown"]), "the sheet prices the line under its press")
	_check(
		String(reading["face"]).ends_with("all ready (%d)" % int(reading["ready"])),
		"the face names the ready rows the view prints"
	)
	return reading


## How the sheet's ready rows fall across the charts, one count per chart.
func _ready_by_chart(sheet: RaiseLedgerPanel) -> Dictionary:
	var counts: Dictionary = {}
	for target: Dictionary in sheet._ready_targets():
		var region: int = int(target.get("region", -1))
		counts[region] = int(counts.get(region, 0)) + 1
	return counts


## The two taps, as a player takes them: arm, then confirm.
func _press(press_host: Node) -> String:
	var press: RaiseBatchPress = press_host._batch
	press.pressed.emit()
	_check(press.is_armed(), "the first tap arms the press")
	press.pressed.emit()
	_check(not press.is_armed(), "the second tap files and stands the arm down")
	await process_frame
	return _last_toast()


## The line's promise held against the taps: what it said would wait, what the
## receipt says was raised, and what the stores and the pool actually gave up.
func _hold_the_promise(read: Dictionary, receipt: String, trade: String) -> void:
	var ready: int = int(read["ready"])
	var promised: int = _promised(String(read["line"]), ready)
	_say("receipt: \"%s\"" % receipt)
	var raised: int = _raised_from(receipt)
	_check(
		raised == promised,
		"the press raised %d of the %d its line promised (n=%d ready)" % [
			raised, promised, ready,
		]
	)
	_check_shopping(String(read["line"]), read["stores"] as Dictionary, int(read["working"]), trade)
	_check(
		int(read["crews"]) > 0,
		"the line names the hand(s) it spends (%d)" % int(read["crews"])
	)


## What the line said it would take against what left the stores and the pool.
func _check_shopping(line: String, stores: Dictionary, working: int, trade: String) -> void:
	var spent: Dictionary = {}
	for key: Variant in _play.economy.economy.stockpile.keys():
		var delta: int = int(stores.get(key, 0)) - int(_play.economy.economy.stockpile[key])
		if delta != 0:
			spent[String(key)] = delta
	var promised: Dictionary = _named_stores(line)
	_check(
		promised.is_empty() or promised == spent,
		"the stores gave up what the line named: line %s, spent %s" % [str(promised), str(spent)]
	)
	var hands: int = _named_crews(line, trade)
	_check(
		hands == 0 or hands == _working_crews() - working,
		"the line's %d hand(s) went to work: %d crew(s) rose" % [
			hands, _working_crews() - working,
		]
	)


## "… — 2 of 5 wait: …" promises three files; a line with no wait promises every
## ready row the view prints (DR-20261118-12).
func _promised(line: String, ready: int) -> int:
	var pattern := RegEx.new()
	pattern.compile("(\\d+) of (\\d+) wait")
	var found: RegExMatch = pattern.search(line)
	if found == null:
		return ready if not line.is_empty() else 0
	return int(found.get_string(2)) - int(found.get_string(1))


## The count a receipt names — "Raised 3 of 5 towns." or "Raised 2 towns" — and
## `0` for a receipt that only carries a refusal.
func _raised_from(receipt: String) -> int:
	if not receipt.begins_with("Raised "):
		return 0
	var tail: String = receipt.substr(7)
	var cut: int = tail.find(" ")
	return int(tail.substr(0, cut)) if cut > 0 else 0


## The commodities a line names, in the counts it names them: "4 Lumber · 1
## Builder" reads {lumber: 4}. A crew word is not a commodity and is dropped.
func _named_stores(line: String) -> Dictionary:
	var out: Dictionary = {}
	for part: String in _line_parts(line):
		var words: PackedStringArray = part.split(" ")
		if words.size() < 2 or not words[0].is_valid_int():
			continue
		var label: String = " ".join(words.slice(1))
		for raw: Variant in _play.economy.economy.stockpile.keys():
			if CommodityCatalog.label(String(raw)) == label:
				out[String(raw)] = int(words[0])
	return out


## The hands a line names for one trade: "2 Builders" reads 2, "1 Engineer" 1.
func _named_crews(line: String, trade: String) -> int:
	var word: String = CivilianCatalog.display_name(trade)
	for part: String in _line_parts(line):
		var words: PackedStringArray = part.split(" ")
		if words.size() != 2 or not words[0].is_valid_int():
			continue
		if words[1] == word or words[1] == word + "s":
			return int(words[0])
	return 0


## A printed line's priced parts: what is left of each "·"-separated piece once
## the aside after its dash is dropped.
func _line_parts(line: String) -> PackedStringArray:
	var parts: PackedStringArray = PackedStringArray()
	for raw: String in line.split("·"):
		var part: String = raw.strip_edges()
		var dash: int = part.find(" — ")
		if dash > 0:
			part = part.substr(0, dash).strip_edges()
		parts.append(part)
	return parts


func _idle_by_trade() -> Dictionary:
	var counts: Dictionary = {}
	for crew: CivilianState in _all_crews():
		if crew == null or crew.owner != _play.player_faction or not crew.is_idle():
			continue
		counts[crew.type_id] = int(counts.get(crew.type_id, 0)) + 1
	return counts


func _working_crews() -> int:
	var count: int = 0
	for crew: CivilianState in _all_crews():
		if crew != null and crew.owner == _play.player_faction and crew.is_working():
			count += 1
	return count


## Every crew the realm holds, on both charts: a press that files an order across
## the water switches the chart under the session, so one roster is not the realm.
func _all_crews() -> Array:
	var found: Array = []
	for raw: Variant in _play.civilian_layer.regions.values():
		if raw is Array:
			found.append_array(raw as Array)
	if found.is_empty():
		found.assign(_play.civilian_layer.units)
	return found


## Seats `count` idle crews of one trade on a chart, at a town site of the
## crown's: the drive's way to a mid-game roster without walking years of turns.
func _seed_crews(region: int, count: int, trade: String = "builder") -> void:
	var model: MapModel = _play.world.region(region)
	if model == null or count <= 0:
		return
	var site: Vector2i = CivilianState.NO_TILE
	for province: ProvinceState in model.provinces:
		if province == null:
			continue
		var owned: bool = province.owner == _play.player_faction and province.has_town()
		if owned:
			site = province.town_site()
			break
	var roster: Array = []
	roster.assign(_play.civilian_layer.regions.value(region, []))
	for _index in count:
		_next_crew_id += 1
		roster.append(CivilianState.create(_next_crew_id, _play.player_faction, trade, site))
	_play.civilian_layer.regions.set_region(region, roster)
	# The sheet reads the region table; the order reads the live roster. A seated
	# crew has to stand in both, exactly as `spawn` leaves them.
	if region == _play.region_index:
		_play.civilian_layer.units.assign(roster)


## The provinces of one chart the crown holds, so a pass can say what it seated.
func _owned_provinces(model: MapModel) -> int:
	var count: int = 0
	for province: ProvinceState in model.provinces:
		if province != null and province.owner == _play.player_faction:
			count += 1
	return count


## The first province whose estates the card would start, read off the card's own
## realm-wide view (a province's dossier opens the card on that province).
func _first_ready_province(estates: ImprovementPanel) -> int:
	estates.open(-1)
	estates.refresh()
	for raw: Variant in estates._data.get("groups", []):
		var group: Dictionary = raw
		for row: Variant in group.get("rows", []):
			if bool((row as Dictionary).get("can_build", false)):
				return int(group.get("id", -1))
	return -1


# --- the handset -------------------------------------------------------------


## A phone reads the line with the press, inside the sheet, never clipped
## (REQ-P1-07, REQ-P5-07).
func _handset_pass() -> void:
	_say("")
	_say("--- the line at handset width ---")
	_seed_crews(0, 1)
	HudLedgerDoors.open(_screen.hud, HudLedgerDoors.TOWNS)
	await process_frame
	var sheet: TownLedgerPanel = _screen.hud.towns_ledger
	if sheet._line == null or sheet._line.text.is_empty():
		_say("the view holds nothing ready — handset pass skipped")
		sheet.close()
		return
	_say("line: \"%s\"" % sheet._line.text)
	var line_rect: Rect2 = sheet._line.get_global_rect()
	var sheet_rect: Rect2 = sheet.get_global_rect()
	_say("line at %s inside the sheet at %s" % [str(line_rect), str(sheet_rect)])
	_check(
		line_rect.position.x >= sheet_rect.position.x - 1.0
		and line_rect.end.x <= sheet_rect.end.x + 1.0,
		"the line stands inside the sheet, not clipped off its edge"
	)
	_check(
		sheet._line.autowrap_mode != TextServer.AUTOWRAP_OFF,
		"the line wraps, so a narrow sheet reads it whole"
	)
	_check(sheet._line.size.y > 0.0, "the line prints a readable height")
	sheet.close()
	await process_frame


# --- reporting ---------------------------------------------------------------


func _last_toast() -> String:
	var box: VBoxContainer = _screen.hud._toast_box
	if box.get_child_count() == 0:
		return ""
	var plate: Control = box.get_child(box.get_child_count() - 1) as Control
	for child: Node in plate.get_children():
		if child is Label:
			return (child as Label).text
	return ""


func _check(ok: bool, what: String) -> void:
	if ok:
		_say("  ok   %s" % what)
		return
	_failures.append(what)
	_say("  FAIL %s" % what)


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	_say("")
	if _failures.is_empty():
		_say("%d checks passed — every raise sheet's line is the line its press files" % _steps.size())
	else:
		_say("%d checks FAILED:" % _failures.size())
		for failure: String in _failures:
			_say("  - %s" % failure)
	print("\n--- playtest_raise_line: %d steps, %d failures ---" % [_steps.size(), _failures.size()])
	quit(1 if not _failures.is_empty() else 0)