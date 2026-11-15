extends GdToolsTest
## The crown's towns: the whole-empire town ledger reads every town the crown
## holds, the level it stands at and the step the Builder would take next
## (wiki: extraction-and-improvements § Town manufacturing bonus; DR-20261115-12)
## and the sheet drives it — the realm's door, the Raise press, back and the key.
## One Godot boot: the projection suite reads small fixtures, the drive mounts
## the shared map screen (docs/testing.md).

const Naval = preload("res://tests/naval_fixture.gd")
const Fixture = preload("res://tests/map_fixture.gd")
const TOWN_TILE: Vector2i = Vector2i(1, 0)

var screen: MapScreen = null


func before_all() -> void:
	screen = Fixture.attach_screen(self)


func after_all() -> void:
	if is_instance_valid(screen):
		screen.hud.towns_ledger.close()
		screen.hud.province_ledger.close()
		screen.free()
	screen = null


func before_each() -> void:
	if screen == null or not is_instance_valid(screen):
		screen = Fixture.attach_screen(self)
		return
	screen.hud.towns_ledger.close()
	screen.hud.province_ledger.close()


# --- projection -------------------------------------------------------------


func test_snapshot_lists_every_town_the_crown_holds_in_both_charts() -> void:
	var snapshot: Dictionary = TownLedger.snapshot(_regions(_builders()), 0)
	assert_eq(int(snapshot["total"]), 2, "one crown town per chart")
	assert_eq((snapshot["groups"] as Array).size(), 2, "one heading per chart")
	assert_eq(TownLedger.count(snapshot, LedgerRows.REGION_OLD), 1)
	assert_eq(TownLedger.count(snapshot, LedgerRows.REGION_NEW), 1)
	for raw: Variant in snapshot["rows"]:
		var row: Dictionary = raw
		assert_ne(String(row["name"]), "Coro", "the rival's town stays out")


func test_a_ready_town_names_the_step_it_waits_on_and_its_price() -> void:
	var snapshot: Dictionary = TownLedger.snapshot(_regions(_builders()), 0)
	var home: Dictionary = _row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(String(home["state"]), TownLedger.STATE_READY, "a crew is free and the study is known")
	assert_eq(String(home["level_text"]), "I", "the level reads as a numeral")
	assert_eq(int(home["next_level"]), 2)
	assert_eq(String(home["cost_text"]), "4 lumber + 4 cast iron", "the table's own price")
	assert_eq(int(home["turns"]), 2, "the target level is the wait")
	assert_eq(
		String(home["note"]),
		"Next: II · 4 lumber + 4 cast iron · 2 turns",
		"the row names the level, the price and the wait"
	)


func test_a_town_without_the_study_is_locked_and_names_it() -> void:
	var snapshot: Dictionary = TownLedger.snapshot(_regions(_builders(), {}), 0)
	var home: Dictionary = _row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(String(home["state"]), TownLedger.STATE_LOCKED)
	assert_true(
		String(home["note"]).contains("National Bureaucracy"),
		"the row names the study that opens it"
	)
	assert_eq(
		int(TownLedger.filter_counts(snapshot, LedgerRows.REGION_ALL)[TownLedger.FILTER_READY]),
		0,
		"a locked town is not counted as ready"
	)


## The third gate the order charges is the purse: a crown with no stores was
## offered a Raise the work order refused (wiki: civilian-units § Builder,
## extraction-and-improvements § Town manufacturing bonus; DR-20261115-12 —
## "a row that cannot be raised carries no press").
func test_a_town_the_stores_cannot_pay_for_is_locked_and_names_the_shortfall() -> void:
	var tech: Dictionary = {"national_bureaucracy": true}
	var regions: Array[Dictionary] = _regions(_builders(), tech, {})
	var snapshot: Dictionary = TownLedger.snapshot(regions, 0)
	var home: Dictionary = _row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(String(home["state"]), TownLedger.STATE_LOCKED, "the order would refuse the level")
	assert_eq(
		String(home["note"]),
		CivilianWorkPlan.town_upgrade_refusal(
			(regions[0]["model"] as MapModel).provinces[0], tech, {}
		),
		"the row speaks the order's own refusal"
	)
	assert_true(
		String(home["note"]).contains("4 lumber + 4 cast iron"),
		"the note names what the crown is short of: %s" % home["note"]
	)
	assert_eq(
		int(TownLedger.filter_counts(snapshot, LedgerRows.REGION_ALL)[TownLedger.FILTER_READY]),
		0,
		"a town the stores cannot pay for is not counted as ready"
	)
	var paid: Dictionary = TownLedger.snapshot(
		_regions(_builders(), tech, {"lumber": 4, "castIron": 4}), 0
	)
	assert_eq(
		String(_row(paid, FactionCatalog.OLD_WORLD)["state"]), TownLedger.STATE_READY,
		"the materials, and nothing else, open the row"
	)


func test_a_town_with_no_idle_crew_waits_on_a_builder() -> void:
	var snapshot: Dictionary = TownLedger.snapshot(_regions([] as Array), 0)
	var home: Dictionary = _row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(String(home["state"]), TownLedger.STATE_NO_BUILDER, "no crew musters")
	assert_true(String(home["note"]).contains("No idle Builder"), "the row names the wait")


func test_a_crew_already_at_work_is_read_from_its_own_record() -> void:
	var builder: CivilianState = CivilianState.create(1, 0, "builder", TOWN_TILE)
	builder.start_work("upgrade_town", TOWN_TILE, 2, TOWN_TILE, {"town_level": 2})
	var snapshot: Dictionary = TownLedger.snapshot(_regions([builder]), 0)
	var home: Dictionary = _row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(String(home["state"]), TownLedger.STATE_AT_WORK)
	assert_eq(int(home["remaining"]), 2)
	assert_true(String(home["note"]).contains("raises it to II"), "the target level is named")
	assert_true(String(home["note"]).contains("2 turns left"))


func test_a_developed_town_reads_finished() -> void:
	var snapshot: Dictionary = TownLedger.snapshot(_regions(_builders()), 0)
	var overseas: Dictionary = _row(snapshot, FactionCatalog.NEW_WORLD)
	assert_eq(int(overseas["level"]), 4)
	assert_eq(String(overseas["state"]), TownLedger.STATE_DEVELOPED)
	assert_true(String(overseas["note"]).contains("Fully developed"))


func test_filters_narrow_the_ledger_and_keep_their_tallies() -> void:
	var snapshot: Dictionary = TownLedger.snapshot(_regions(_builders()), 0)
	var counts: Dictionary = TownLedger.filter_counts(snapshot, LedgerRows.REGION_ALL)
	assert_eq(int(counts[TownLedger.FILTER_ALL]), 2)
	assert_eq(int(counts[TownLedger.FILTER_READY]), 1)
	assert_eq(int(counts[TownLedger.FILTER_DEVELOPED]), 1)
	assert_eq(int(counts[TownLedger.FILTER_AT_WORK]), 0)
	var ready: Array[Dictionary] = TownLedger.groups(
		snapshot, LedgerRows.REGION_ALL, TownLedger.FILTER_READY
	)
	assert_eq(ready.size(), 1, "only the chart that holds a ready town")
	assert_eq(int(ready[0]["region"]), FactionCatalog.OLD_WORLD)
	assert_eq(TownLedger.count(snapshot, LedgerRows.REGION_NEW, TownLedger.FILTER_READY), 0)


func test_the_reading_leads_with_what_can_be_raised_now() -> void:
	var snapshot: Dictionary = TownLedger.snapshot(_regions(_builders()), 0)
	var rows: Array = snapshot["rows"]
	assert_eq(String((rows[0] as Dictionary)["state"]), TownLedger.STATE_READY)
	assert_eq(String((rows[1] as Dictionary)["state"]), TownLedger.STATE_DEVELOPED)


func test_the_bonus_note_states_where_the_bonus_sits() -> void:
	var note: String = TownLedger.bonus_note()
	assert_true(note.contains("levels 2 and 4"), "the rule a crown pays by is printed")


# --- the shared raise spine -------------------------------------------------


## The spine under both raise sheets: a tally per state, the reading order and
## the state words each sheet passes in (DR-20261115-12, DR-20261116-01).
func test_the_spine_counts_every_state_a_row_can_carry() -> void:
	var counts: Dictionary = RaiseLedger.empty_counts(TownLedger.STATES)
	assert_eq(counts.size(), TownLedger.STATES.size(), "one tally per state")
	for state: String in TownLedger.STATES:
		assert_eq(int(counts[state]), 0, "a zero stays legible")


func test_the_spine_orders_a_ready_step_before_a_finished_one() -> void:
	var rows: Array[Dictionary] = [
		{"state": TownLedger.STATE_DEVELOPED, "level": 1, "region": 0, "id": 1},
		{"state": TownLedger.STATE_READY, "level": 3, "region": 1, "id": 2},
		{"state": TownLedger.STATE_READY, "level": 1, "region": 0, "id": 3},
	]
	RaiseLedger.sort_rows(rows, TownLedger.STATE_ORDER)
	assert_eq(int(rows[0]["id"]), 3, "the weakest ready step leads")
	assert_eq(int(rows[1]["id"]), 2, "then the stronger ready step")
	assert_eq(int(rows[2]["id"]), 1, "the finished work reads last")


func test_the_spine_reads_the_finished_and_no_crew_words_the_sheet_passes() -> void:
	assert_eq(
		RaiseLedger.state_for(
			4, 4, null, "", false, TownLedger.STATE_DEVELOPED, TownLedger.STATE_NO_BUILDER
		),
		TownLedger.STATE_DEVELOPED,
		"a finished work is the sheet's own word"
	)
	assert_eq(
		RaiseLedger.state_for(
			1, 4, null, "", false, TownLedger.STATE_DEVELOPED, TownLedger.STATE_NO_BUILDER
		),
		TownLedger.STATE_NO_BUILDER,
		"a missing crew is the sheet's own word"
	)


# --- the batch press ---------------------------------------------------------


## The press files exactly what the view prints: the ready rows, in the sheet's
## own order, and nothing a filter has hidden (REQ-P5-04; DR-20261116-03).
func test_the_batch_press_reads_only_the_ready_rows_the_view_prints() -> void:
	var snapshot: Dictionary = TownLedger.snapshot(_regions(_builders()), 0)
	var targets: Array[Dictionary] = RaiseLedger.ready_targets(snapshot, LedgerRows.REGION_ALL)
	assert_eq(targets.size(), 1, "one ready town, one target")
	assert_eq(int(targets[0]["region"]), FactionCatalog.OLD_WORLD, "the chart it stands on")
	assert_eq(
		RaiseLedger.ready_targets(snapshot, LedgerRows.REGION_NEW).size(),
		0,
		"a chart with nothing ready offers no target"
	)
	assert_eq(
		RaiseLedger.ready_targets(
			snapshot, LedgerRows.REGION_ALL, TownLedger.FILTER_DEVELOPED
		).size(),
		0,
		"a finished reading offers no press"
	)


## The walk stops at the first refusal — the rules' own answer — so a press never
## claims a step the order refused (REQ-P2-03, REQ-P5-05; DR-20261116-03).
func test_the_batch_walk_stops_at_the_first_refusal() -> void:
	_filed.clear()
	var targets: Array[Dictionary] = [
		{"region": 0, "id": 1},
		{"region": 0, "id": 2},
		{"region": 0, "id": 3},
	]
	var result: Dictionary = RaiseLedger.file_batch(targets, _refuse_second)
	assert_eq(_filed.size(), 2, "the walk stops at the refusal")
	assert_eq(_filed[0], 1, "the first target was filed")
	assert_eq(_filed[1], 2, "the refusing target was asked, and the walk stopped")
	assert_eq(int(result["raised"]), 1, "one order was filed")
	assert_eq(int(result["total"]), 3, "the view held three")
	assert_eq(String(result["refusal"]), "No idle Builder musters.", "the refusal is kept")


func test_the_receipt_names_what_the_press_left() -> void:
	assert_eq(
		RaiseLedger.batch_receipt({"raised": 3, "total": 3, "refusal": ""}, "towns"),
		"Raised 3 towns — every ready step in this view is ordered."
	)
	assert_eq(
		RaiseLedger.batch_receipt(
			{"raised": 1, "total": 3, "refusal": "No idle Builder musters."}, "towns"
		),
		"Raised 1 of 3 towns. The next waits: No idle Builder musters."
	)


## One arm, one confirm, and every ready town the view prints takes a Builder —
## the receipt is the one line the court reads (REQ-P5-04, REQ-P5-05;
## DR-20261116-03).
func test_the_batch_press_files_every_ready_town_in_one_confirmed_press() -> void:
	var panel: TownLedgerPanel = screen.hud.towns_ledger
	screen.play.tech_unlocked()["national_bureaucracy"] = true
	_cancel_works()
	var stock: Dictionary = screen.play.stockpile()
	stock["lumber"] = 400
	stock["castIron"] = 400
	panel.open()
	panel._on_filter(LedgerRows.REGION_OLD, true)
	var targets: Array[Dictionary] = panel._ready_targets()
	assert_true(
		targets.size() >= 2,
		"the campaign seats two towns the crown can raise: %d" % targets.size()
	)
	var added: Array[CivilianState] = []
	for index in targets.size():
		var province: ProvinceState = screen.play.model.province_data(int(targets[index]["id"]))
		var crew: CivilianState = CivilianState.create(
			300 + index, screen.play.player_faction, "builder", province.town_tile
		)
		screen.play.civilian_layer.units.append(crew)
		added.append(crew)
	panel.refresh()
	var press: RaiseBatchPress = panel._batch
	assert_not_null(press, "the sheet carries the batch press")
	assert_true(press.visible, "the press stands when the view holds a ready step")
	assert_eq(press.text, "Raise all ready (%d)" % targets.size(), "the press names the count")
	press.pressed.emit()
	assert_true(press.is_armed(), "the first tap only arms")
	assert_eq(
		press.text, "Confirm — raise %d towns" % targets.size(), "the second tap is named"
	)
	press.pressed.emit()
	assert_false(press.is_armed(), "the press forgets the arm once it files")
	assert_eq(_working_builders(), targets.size(), "every ready town took a Builder")
	assert_eq(panel._ready_targets().size(), 0, "the view holds no ready step after the press")
	assert_false(press.visible, "and the press stands down")
	# Leave the campaign as it was found: the crews this case added go, the orders
	# it filed are abandoned and the view is widened again, so a later case reads
	# the roster and the sheet it expects.
	_cancel_works()
	for crew: CivilianState in added:
		screen.play.civilian_layer.units.erase(crew)
	panel._on_filter(LedgerRows.REGION_ALL, true)


func test_the_batch_press_stands_down_when_the_view_holds_nothing_ready() -> void:
	var panel: TownLedgerPanel = screen.hud.towns_ledger
	panel.open()
	panel._on_filter(TownLedger.FILTER_DEVELOPED, false)
	assert_false(panel._batch.visible, "a reading with nothing ready carries no press")
	panel._on_filter(TownLedger.FILTER_ALL, false)


# --- the sheet --------------------------------------------------------------


func test_the_realm_door_opens_the_towns_ledger() -> void:
	var panel: TownLedgerPanel = screen.hud.towns_ledger
	assert_not_null(panel, "the HUD mounts the towns ledger")
	var door: Button = _towns_door()
	assert_not_null(door, "the realm ledger carries the towns door")
	door.pressed.emit()
	assert_true(panel.is_open(), "the realm's towns door opens it")
	assert_true(_row_widgets(panel) > 0, "the crown's towns are listed")


func test_raise_files_the_builders_order_on_the_provinces_chart() -> void:
	var panel: TownLedgerPanel = screen.hud.towns_ledger
	var province: ProvinceState = _crown_town()
	assert_not_null(province, "the campaign seats the crown in a town")
	screen.play.tech_unlocked()["national_bureaucracy"] = true
	var stock: Dictionary = screen.play.stockpile()
	stock["lumber"] = 40
	stock["castIron"] = 40
	var town: Vector2i = province.town_tile
	var builder: CivilianState = CivilianState.create(90, screen.play.player_faction, "builder", town)
	screen.play.civilian_layer.units.append(builder)
	panel.open()
	var row: TownLedgerRow = _row_for(panel, province.id)
	assert_not_null(row, "the province is on the sheet")
	row.press_raise()
	assert_true(builder.is_working(), "the press files the order")
	assert_eq(builder.work_action(), "upgrade_town", "the Builder raises the town")
	assert_eq(builder.work_tile(), town, "on the province's own town tile")
	assert_eq(int(stock["lumber"]), 36, "the price is the table's own")
	assert_true(_state_of(_row_for(panel, province.id)) == "at_work", "and the row reads it")


## The purse is the third gate on the sheet itself: with every store at zero the
## row reads LOCKED and carries no press, and the materials arriving open it —
## no press the order would refuse (wiki: civilian-units § Builder;
## DR-20261115-12, REQ-P2-03, REQ-P5-05).
func test_a_short_purse_leaves_the_raise_press_off_the_sheet() -> void:
	var panel: TownLedgerPanel = screen.hud.towns_ledger
	screen.play.tech_unlocked()["national_bureaucracy"] = true
	_cancel_works()
	var province: ProvinceState = _crown_town()
	assert_not_null(province, "the campaign seats the crown in a town")
	var stock: Dictionary = screen.play.stockpile()
	for key: Variant in stock.keys():
		stock[key] = 0
	panel.open()
	var row: TownLedgerRow = _row_for(panel, province.id)
	assert_not_null(row, "the province is on the sheet")
	assert_eq(String(row.data.get("state", "")), TownLedger.STATE_LOCKED, "the order would refuse")
	assert_false(row._raise.visible, "a row that cannot be raised carries no press")
	assert_true(
		String(row.data.get("note", "")).contains("Stores are short of"),
		String(row.data.get("note", ""))
	)
	## The materials arrive: the same row opens without the sheet reopening.
	var price: Dictionary = CivilianWork.cost_for(
		"upgrade_town", CivilianWorkPlan.town_upgrade_level(screen.play.model, province.town_tile)
	)
	for key: Variant in price.keys():
		stock[key] = int(price[key])
	panel.refresh()
	var paid: TownLedgerRow = _row_for(panel, province.id)
	assert_eq(String(paid.data.get("state", "")), TownLedger.STATE_READY, "paid, the step opens")
	assert_true(paid._raise.visible, "and the press returns")


## The map hooks answer a missing session and an unreadable province without
## folding: a sheet that opens before the campaign seats reads an empty roll.
func test_the_map_hooks_guard_a_missing_session() -> void:
	assert_eq(int(MapPlayTowns.snapshot(null).get("total", -1)), 0, "no session, no towns")
	MapPlayTowns.raise(null, FactionCatalog.OLD_WORLD, 0)
	MapPlayTowns.raise(screen.play, FactionCatalog.OLD_WORLD, -1)
	MapPlayTowns.raise(screen.play, 99, 0)
	assert_eq(int(MapPlayTowns.snapshot(screen.play).get("total", 0)), _crown_towns())


func test_back_and_the_key_close_the_towns_ledger() -> void:
	var panel: TownLedgerPanel = screen.hud.towns_ledger
	screen.hud.towns_pressed.emit()
	assert_true(panel.is_open())
	assert_true(BackRequest.handle(screen.play, screen.play.improvements))
	assert_false(panel.is_open(), "back sets the ledger aside first")
	InputActions.ensure_actions()
	var toggle := InputEventAction.new()
	toggle.action = InputActions.TOWNS_LEDGER
	toggle.pressed = true
	panel._unhandled_input(toggle)
	assert_true(panel.is_open(), "the key opens it from the map")
	panel._unhandled_input(toggle)
	assert_false(panel.is_open(), "and closes it again")


# --- fixtures ---------------------------------------------------------------


## Every target the batch walk asked for, in the order it asked: the pure walk's
## own record, so a refusal's cost is read (DR-20261116-03).
var _filed: Array[int] = []


## An order hook that files the first two targets and refuses the third the way a
## sheet with no free Builder would.
func _refuse_second(_region: int, province_id: int) -> Dictionary:
	_filed.append(province_id)
	if province_id == 2:
		return {"ok": false, "message": "No idle Builder musters."}
	return {"ok": true, "message": ""}


## How many of the crown's Builders in the mounted chart are raising a town now.
func _working_builders() -> int:
	var working: int = 0
	for unit: CivilianState in screen.play.civilian_layer.units:
		if unit == null or unit.owner != screen.play.player_faction:
			continue
		if unit.work_action() == "upgrade_town":
			working += 1
	return working


## Two charts of the naval fixture: the crown holds Cádiz at home (a level-1
## town) and Veracruz abroad (a finished town), and the rival's Coro carries a
## town of its own that must never reach the reading.
func _regions(
	units: Array, tech: Dictionary = {"national_bureaucracy": true}, stockpile: Variant = null
) -> Array[Dictionary]:
	var old: MapModel = Naval.build()
	var new: MapModel = Naval.build()
	new.region_id = FactionCatalog.NEW_WORLD
	new.provinces[0].name = "Veracruz"
	new.provinces[0].capital = false
	new.provinces[0].town_tile = TOWN_TILE
	new.provinces[0].town_development = 4
	old.provinces[0].town_tile = TOWN_TILE
	old.provinces[0].town_development = 1
	old.provinces[1].town_tile = Vector2i(5, 1)
	old.provinces[1].town_development = 2
	return [
		{
			"region": FactionCatalog.OLD_WORLD,
			"model": old,
			"units": units,
			"tech_unlocked": tech,
			"stockpile": stockpile,
		},
		{
			"region": FactionCatalog.NEW_WORLD,
			"model": new,
			"units": units,
			"tech_unlocked": tech,
			"stockpile": stockpile,
		},
	]


## One idle Builder on the crown's own land, so a ready town has a crew free.
func _builders() -> Array:
	return [CivilianState.create(1, 0, "builder", TOWN_TILE)]


func _row(snapshot: Dictionary, region: int) -> Dictionary:
	for raw: Variant in snapshot["rows"]:
		var row: Dictionary = raw
		if int(row["region"]) == region:
			return row
	return {}


## The first crown province of the mounted campaign that carries a town and has
## not been finished yet.
func _crown_town() -> ProvinceState:
	for province: ProvinceState in screen.play.model.provinces:
		if province.owner != screen.play.player_faction:
			continue
		if not province.has_town() or province.town_tile.x < 0:
			continue
		if province.town_level() < CivilianWorkPlan.MAX_TOWN:
			return province
	return null


## The realm ledger's towns door, found by its word so the suite reads the
## button the player presses.
func _towns_door() -> Button:
	for node: Node in screen.hud.province_ledger.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text == "Towns ›":
			return button
	return null


## Frees every crew this suite put to work, so a case that reads a row does not
## inherit the order an earlier case filed.
func _cancel_works() -> void:
	for unit: CivilianState in screen.play.civilian_layer.units:
		if unit != null and unit.owner == screen.play.player_faction and unit.is_working():
			unit.cancel_work()


func _row_for(panel: TownLedgerPanel, province_id: int) -> TownLedgerRow:
	for child: Node in panel._rows.get_children():
		var row := child as TownLedgerRow
		if row != null and int(row.data.get("id", -1)) == province_id:
			return row
	return null


func _state_of(row: TownLedgerRow) -> String:
	if row == null:
		return ""
	return String(row.data.get("state", ""))


## How many towns the mounted campaign's crown holds in both charts, so the
## sheet's own total is checked against the chart rather than a hand count.
func _crown_towns() -> int:
	var total: int = 0
	for region: int in screen.play.world.region_count():
		var model: MapModel = screen.play.world.region(region)
		if model == null:
			continue
		for province: ProvinceState in model.provinces:
			if province == null or province.owner != screen.play.player_faction:
				continue
			if province.has_town():
				total += 1
	return total


func _row_widgets(panel: TownLedgerPanel) -> int:
	var total: int = 0
	for child: Node in panel._rows.get_children():
		if child is TownLedgerRow:
			total += 1
	return total
