extends SceneTree
## Headless free-playtest drive for the crown's raise and its realm reading, after
## the town, wall and ward sheets were folded into the realm (issue #1164;
## wiki: world-map § Provinces, extraction-and-improvements § Town development).
##
##   godot --headless --path . --script res://playtests/playtest_raise_line.gd
##
## Three things no rule test covers on the live screen:
##   - the realm's **Defence** view prints the seat's town, its figure and its guns;
##   - the province dossier's **Upgrade Town** press still files the one order the
##     town sheet used to send — a Builder goes to the town step;
##   - the estates card still prices the line under its batch press, and the taps
##     spend what the line named.
##
## Not a CI gate. A failure prints "FAIL: …" and the run exits non-zero.

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
## England: a Great Power that is not FactionCatalog.PLAYER_FACTION, so a reading
## that defaults to the crown instead of the session's own is visible here.
const NATION: int = 1

var _steps: PackedStringArray = PackedStringArray()
var _failures: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null
var _play: PlaySession = null
## The first id the drive mints for the crew it seats; the campaign's own roster
## is well under this.
var _next_crew_id: int = 900


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_screen = await Launch.open_map(self, SEED_TEXT, 0, "", NATION)
	if _screen == null:
		_finish()
		return
	_play = _screen.play
	_say("%s (faction %d), seed %s, turn %d, capital province %d" % [
		FactionCatalog.name_of(_play.player_faction), _play.player_faction, SEED_TEXT,
		_play.turn, _play.selected_province,
	])
	# A crown holds no town step before National Bureaucracy: the drive seats the
	# study rather than spending turns on the tree.
	_play.tech_unlocked()["national_bureaucracy"] = true
	_seed_builder()
	await _realm_pass("the realm before the order")
	await _order_pass()
	await _realm_pass("the realm after the order")
	await _estates_pass()
	_finish()


# --- the realm's three readings ----------------------------------------------


## The realm's Defence view: the seat's row names its town and its figure, and
## the same sheet still answers on the other two views.
func _realm_pass(title: String) -> void:
	_say("")
	_say("--- %s ---" % title)
	_screen.hud.ledger_door_pressed.emit(HudLedgerDoors.PROVINCES)
	await process_frame
	var panel: ProvinceLedgerPanel = _screen.hud.province_ledger
	if panel == null or not panel.is_open():
		_check(false, "the realm opens from the bar seal")
		return
	panel._on_filter(ProvinceLedger.VIEW_DEFENCE, false)
	await process_frame
	var row: ProvinceLedgerRow = _seat_row(panel)
	if row == null:
		_check(false, "the realm prints the seat")
		panel.close()
		return
	var defence: Dictionary = row.data.get("defence", {})
	_say("the seat reads %s — defence %d, %d strength, %d guns, town %d" % [
		String(row.data.get("name", "")), int(defence.get("figure", 0)),
		roundi(float(defence.get("strength", 0.0))), int(defence.get("guns", 0)),
		int(row.data.get("town", 0)),
	])
	_check(
		String(row._reading.text).contains("Town "),
		"the defence line names the town the province is built to"
	)
	_check(
		String(row._standing.text).begins_with("Defence "),
		"and the standing line leads with the one figure"
	)
	for view: String in [ProvinceLedger.VIEW_ECONOMY, ProvinceLedger.VIEW_CONNECTIVITY]:
		panel._on_filter(view, false)
		await process_frame
		_check(
			_seat_row(panel) != null,
			"the %s view still prints the seat" % ProvinceLedger.view_label(view).to_lower()
		)
	panel.close()
	await process_frame


# --- the dossier's one press -------------------------------------------------


## The province dossier's Upgrade Town order: a Builder is sent and the work is
## filed on the town step.
func _order_pass() -> void:
	_say("")
	_say("--- the dossier's Upgrade Town press ---")
	_play.economy.economy.stockpile["lumber"] = 40
	_play.economy.economy.stockpile["castIron"] = 40
	# The seat itself is often already at the top step: the drive takes the
	# crown's first town with a level still to raise.
	var target: int = _raisable_town()
	if target < 0:
		_say("no town of the crown's can be raised — pass skipped")
		return
	MapPlayInput.select_province(_play, target, Vector2.ZERO)
	await process_frame
	_say("the order is read on province %d (%s)" % [
		target, String(_play.model.province_name(target)),
	])
	var orders: ProvinceOrdersSection = _screen.hud._panel._orders
	if orders == null or orders.town_press() == null:
		_check(false, "the dossier carries the town order")
		return
	var town_press: Button = orders.town_press()
	_say("the order reads: %s" % town_press.text)
	if town_press.disabled:
		_say("the order is gated this turn — %s" % town_press.tooltip_text)
		return
	town_press.pressed.emit()
	await process_frame
	_say("the court reads: \"%s\"" % _last_toast())
	var working: int = 0
	for unit: CivilianState in _play.civilian_layer.units:
		if unit == null or unit.owner != _play.player_faction:
			continue
		if unit.work_action() == "upgrade_town":
			working += 1
	_check(working > 0, "a Builder is on the town's step")
	_say("%d Builder(s) at the town step after the press" % working)
	# The step in hand reads as taken: the same dossier, re-read once the Builder
	# is at the town, offers no second press and prints the Builder raising it
	# instead of the payoff (wiki: extraction-and-improvements § Town
	# manufacturing bonus; DR-20261125-05; REQ-P2-03, REQ-P5-07).
	MapPlaySetup.refresh_dossier(_play)
	await process_frame
	town_press = orders.town_press()
	_check(town_press.disabled, "the ordered town offers no second press")
	_check(
		town_press.tooltip_text.contains("already at work"),
		"and names the Builder raising it: %s" % town_press.tooltip_text
	)
	_say("the same press after the order reads: %s" % town_press.tooltip_text)


## One idle Builder at the seat's own town site: the press needs a hand, and a
## crown at turn 1 has none (the old town sheet was read after seeding one).
func _seed_builder() -> void:
	var model: MapModel = _play.model
	if model == null:
		return
	var site: Vector2i = CivilianState.NO_TILE
	for province: ProvinceState in model.provinces:
		if province == null or province.owner != _play.player_faction:
			continue
		if province.has_town():
			site = province.town_site()
			break
	if site == CivilianState.NO_TILE:
		return
	_next_crew_id += 1
	var crew := CivilianState.create(_next_crew_id, _play.player_faction, "builder", site)
	_play.civilian_layer.units.append(crew)
	if _play.civilian_layer.regions != null:
		var roster: Array = []
		roster.assign(_play.civilian_layer.regions.value(_play.region_index, []))
		roster.append(crew)
		_play.civilian_layer.regions.set_region(_play.region_index, roster)


## The crown's first town still below the top step.
func _raisable_town() -> int:
	for province: ProvinceState in _play.model.provinces:
		if province == null or province.owner != _play.player_faction:
			continue
		if province.has_town() and province.town_level() < TownIndustry.MAX_LEVEL:
			return province.id
	return -1


# --- the estates card --------------------------------------------------------


## The estates card: one chart, one Builder's worth of hands, and a price that
## moves with the stores as the orders file (the H8 bootstrap).
func _estates_pass() -> void:
	_say("")
	_say("--- the estates card ---")
	var estates: ImprovementPanel = _play.improvements
	if estates == null:
		_say("no estates card on this screen — pass skipped")
		return
	_play.economy.economy.stockpile["lumber"] = 4
	_play.economy.economy.stockpile["castIron"] = 0
	var province: int = _first_ready_province(estates)
	if province < 0:
		_say("no province offers a ready estate — pass skipped")
		return
	estates.open(province)
	estates.refresh()
	await process_frame
	var tiles: Array[Vector2i] = estates.ready_tiles()
	var line: String = estates._line.text
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
	estates.close()
	await process_frame


# --- readings ----------------------------------------------------------------


## The two taps, as a player takes them: arm, then confirm.
func _press(press_host: Node) -> String:
	var press: RaiseBatchPress = press_host._batch
	press.pressed.emit()
	_check(press.is_armed(), "the first tap arms the press")
	press.pressed.emit()
	_check(not press.is_armed(), "the second tap files and stands the arm down")
	await process_frame
	return _last_toast()


## "… — 2 of 5 wait: …" promises three files; a line with no wait promises every
## ready row the view prints (DR-20261118-12).
func _promised(line: String, ready: int) -> int:
	var pattern := RegEx.new()
	pattern.compile("(\\d+) of (\\d+) wait")
	var found: RegExMatch = pattern.search(line)
	if found == null:
		return ready if not line.is_empty() else 0
	return int(found.get_string(2)) - int(found.get_string(1))


## The count a receipt names — "Raised 3 of 5 estates." or "Raised 2 estates".
func _raised_from(receipt: String) -> int:
	if not receipt.begins_with("Raised "):
		return 0
	var tail: String = receipt.substr(7)
	var cut: int = tail.find(" ")
	return int(tail.substr(0, cut)) if cut > 0 else 0


## The seat's own row in the painted realm, found by the capital flag the
## projection carries.
func _seat_row(panel: ProvinceLedgerPanel) -> ProvinceLedgerRow:
	for child: Node in panel._rows.get_children():
		var row := child as ProvinceLedgerRow
		if row != null and bool(row.data.get("capital", false)):
			return row
	return null


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


# --- reporting ---------------------------------------------------------------


func _last_toast() -> String:
	var box: VBoxContainer = _screen.hud.despatches.box
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
		_say("%d checks passed — the realm reads and the raise still files" % _steps.size())
	else:
		_say("%d checks FAILED:" % _failures.size())
		for failure: String in _failures:
			_say("  - %s" % failure)
	print("\n--- playtest_raise_line: %d steps, %d failures ---" % [
		_steps.size(), _failures.size(),
	])
	quit(1 if not _failures.is_empty() else 0)
