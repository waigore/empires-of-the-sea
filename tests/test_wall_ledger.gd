extends GdToolsTest
## The crown's walls: the whole-empire wall ledger reads every province the
## crown holds that can carry a fort, the wall it stands behind and the step the
## Engineer would take next (wiki: siege-mechanics § Fort Levels, § Wall
## Protection; DR-20261116-01) and the sheet drives it — the realm's door, the
## Raise press, back and the key. One Godot boot: the projection suite reads
## small fixtures, the drive mounts the shared map screen (docs/testing.md).

const Naval = preload("res://tests/naval_fixture.gd")
const Fixture = preload("res://tests/map_fixture.gd")
const TOWN_TILE: Vector2i = Vector2i(1, 0)

var screen: MapScreen = null


func before_all() -> void:
	screen = Fixture.attach_screen(self)


func after_all() -> void:
	if is_instance_valid(screen):
		screen.hud.walls_ledger.close()
		screen.hud.province_ledger.close()
		screen.free()
	screen = null


func before_each() -> void:
	if screen == null or not is_instance_valid(screen):
		screen = Fixture.attach_screen(self)
		return
	screen.hud.walls_ledger.close()
	screen.hud.province_ledger.close()


# --- projection -------------------------------------------------------------


func test_snapshot_lists_every_wall_the_crown_can_raise_in_both_charts() -> void:
	var snapshot: Dictionary = WallLedger.snapshot(_regions(_engineers()), 0)
	assert_eq(int(snapshot["total"]), 2, "one crown province per chart")
	assert_eq((snapshot["groups"] as Array).size(), 2, "one heading per chart")
	assert_eq(WallLedger.count(snapshot, LedgerRows.REGION_OLD), 1)
	assert_eq(WallLedger.count(snapshot, LedgerRows.REGION_NEW), 1)
	for raw: Variant in snapshot["rows"]:
		var row: Dictionary = raw
		assert_ne(String(row["name"]), "Coro", "the rival's shore stays out")


func test_a_bare_shore_names_the_step_it_waits_on_and_its_price() -> void:
	var snapshot: Dictionary = WallLedger.snapshot(_regions(_engineers()), 0)
	var home: Dictionary = _row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(String(home["state"]), WallLedger.STATE_READY, "a crew is free and no study is owed")
	assert_eq(String(home["level_text"]), "—", "an open shore is a dash, not a zero")
	assert_eq(String(home["line"]), "No fort")
	assert_eq(int(home["next_level"]), 1)
	assert_eq(String(home["cost_text"]), "3 lumber + 3 bronze", "the fort table's own price")
	assert_eq(int(home["turns"]), 1, "a wood wall is one turn")
	assert_eq(
		String(home["note"]),
		"Next: wood fort · 3 lumber + 3 bronze · 1 turn",
		"the row names the wall, the price and the wait"
	)


func test_a_wall_without_the_study_is_locked_and_names_it() -> void:
	var snapshot: Dictionary = WallLedger.snapshot(
		_regions(_engineers(), {"mine_engineering": false}), 0
	)
	var overseas: Dictionary = _row(snapshot, FactionCatalog.NEW_WORLD)
	assert_eq(String(overseas["state"]), WallLedger.STATE_LOCKED, "a wood wall is up; stone is gated")
	assert_true(
		String(overseas["note"]).contains("Mine Engineering"),
		"the row names the study that opens it"
	)
	assert_eq(
		int(WallLedger.filter_counts(snapshot, LedgerRows.REGION_ALL)[WallLedger.FILTER_READY]),
		1,
		"a locked wall is not counted as ready"
	)


## The third gate the order charges is the purse: a crown with no stores was
## offered a Raise the work order refused (wiki: siege-mechanics § Fort Levels —
## "a row that cannot be raised carries no press"; DR-20261116-01).
func test_a_shore_the_stores_cannot_pay_for_is_locked_and_names_the_shortfall() -> void:
	var snapshot: Dictionary = WallLedger.snapshot(_regions(_engineers(), {}, {}), 0)
	var home: Dictionary = _row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(String(home["state"]), WallLedger.STATE_LOCKED, "the order would refuse the wall")
	assert_eq(
		String(home["note"]),
		CivilianWorkPlan.fort_refusal(0, {"mine_engineering": true}, {}),
		"the row speaks the order's own refusal"
	)
	assert_true(
		String(home["note"]).contains("3 lumber + 3 bronze"),
		"the note names what the crown is short of"
	)
	assert_eq(
		int(WallLedger.filter_counts(snapshot, LedgerRows.REGION_ALL)[WallLedger.FILTER_READY]),
		0,
		"a wall the stores cannot pay for is not counted as ready"
	)
	var paid: Dictionary = WallLedger.snapshot(
		_regions(_engineers(), {}, {"lumber": 3, "bronze": 3}), 0
	)
	assert_eq(
		String(_row(paid, FactionCatalog.OLD_WORLD)["state"]), WallLedger.STATE_READY,
		"the materials, and nothing else, open the row"
	)


func test_a_shore_with_no_idle_crew_waits_on_an_engineer() -> void:
	var snapshot: Dictionary = WallLedger.snapshot(_regions([] as Array), 0)
	var home: Dictionary = _row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(String(home["state"]), WallLedger.STATE_NO_ENGINEER, "no crew musters")
	assert_true(String(home["note"]).contains("No idle Engineer"), "the row names the wait")


func test_an_engineer_already_at_work_is_read_from_its_own_record() -> void:
	var engineer: CivilianState = CivilianState.create(1, 0, "engineer", TOWN_TILE)
	engineer.start_work("build_fort", TOWN_TILE, 2, TOWN_TILE, {"fort_level": 2})
	var snapshot: Dictionary = WallLedger.snapshot(_regions([engineer]), 0)
	var home: Dictionary = _row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(String(home["state"]), WallLedger.STATE_AT_WORK)
	assert_eq(int(home["remaining"]), 2)
	assert_true(String(home["note"]).contains("raises the stone fort"), "the target wall is named")
	assert_true(String(home["note"]).contains("2 turns left"))


func test_a_modern_wall_reads_finished() -> void:
	var raised: Dictionary = _raised()
	assert_eq(int(raised["level"]), FortRules.MAX_LEVEL)
	assert_eq(String(raised["state"]), WallLedger.STATE_RAISED, "a citadel owes nothing")
	assert_eq(String(raised["note"]), "Fully walled — 3 guns, 30 wall hp.")
	assert_eq(String(raised["level_text"]), "III")


func test_filters_narrow_the_ledger_and_keep_their_tallies() -> void:
	var snapshot: Dictionary = WallLedger.snapshot(
		_regions(_engineers(), {"mine_engineering": false}), 0
	)
	var counts: Dictionary = WallLedger.filter_counts(snapshot, LedgerRows.REGION_ALL)
	assert_eq(int(counts[WallLedger.FILTER_ALL]), 2)
	assert_eq(int(counts[WallLedger.FILTER_READY]), 1)
	assert_eq(int(counts[WallLedger.FILTER_RAISED]), 0)
	assert_eq(int(counts[WallLedger.FILTER_AT_WORK]), 0)
	var ready: Array[Dictionary] = WallLedger.groups(
		snapshot, LedgerRows.REGION_ALL, WallLedger.FILTER_READY
	)
	assert_eq(ready.size(), 1, "only the chart that holds a ready wall")
	assert_eq(int(ready[0]["region"]), FactionCatalog.OLD_WORLD)
	assert_eq(WallLedger.count(snapshot, LedgerRows.REGION_NEW, WallLedger.FILTER_READY), 0)


func test_the_reading_leads_with_what_can_be_raised_now() -> void:
	var rows: Array = _raised_snapshot()["rows"]
	assert_eq(String((rows[0] as Dictionary)["state"]), WallLedger.STATE_READY, "the open shore leads")
	assert_eq(String((rows[1] as Dictionary)["state"]), WallLedger.STATE_RAISED, "the citadel follows")


func test_the_summary_names_where_nothing_stands() -> void:
	var snapshot: Dictionary = WallLedger.snapshot(_regions(_engineers(), _wide_tech()), 0)
	var reading: Dictionary = WallLedger.summary(snapshot, LedgerRows.REGION_ALL)
	assert_eq(int(reading["total"]), 2)
	assert_eq(int(reading["bare"]), 1, "one open shore")
	assert_eq(int(reading["walled"]), 1, "one wood or stone wall")
	assert_eq(int(reading["citadel"]), 0)
	var built: Dictionary = WallLedger.summary(_raised_snapshot(), LedgerRows.REGION_ALL)
	assert_eq(int(built["citadel"]), 1, "a modern wall is a citadel")


func test_the_rule_note_states_what_a_wall_buys() -> void:
	var note: String = WallLedger.rule_note()
	assert_true(note.contains("10 / 20 / 30 wall hp"), "the wall's soak is printed")
	assert_true(note.contains("emplaced guns"), "the battery is printed")


# --- the sheet --------------------------------------------------------------


func test_the_realm_door_opens_the_walls_ledger() -> void:
	var panel: WallLedgerPanel = screen.hud.walls_ledger
	assert_not_null(panel, "the HUD mounts the walls ledger")
	var door: Button = _walls_door()
	assert_not_null(door, "the realm ledger carries the walls door")
	door.pressed.emit()
	assert_true(panel.is_open(), "the realm's walls door opens it")
	assert_true(_row_widgets(panel) > 0, "the crown's walls are listed")


func test_raise_files_the_engineers_order_on_the_provinces_chart() -> void:
	var panel: WallLedgerPanel = screen.hud.walls_ledger
	var province: ProvinceState = _crown_wall()
	assert_not_null(province, "the campaign seats the crown on ground that can carry a wall")
	screen.play.tech_unlocked()["mine_engineering"] = true
	screen.play.tech_unlocked()["modern_forts"] = true
	var stock: Dictionary = screen.play.stockpile()
	stock["lumber"] = 40
	stock["bronze"] = 40
	stock["steel"] = 40
	var site: Vector2i = FortRules.site_tile(screen.play.model, province.id)
	var price: Dictionary = FortRules.cost(FortRules.next_level(province.fort_level))
	var lumber: int = int(stock["lumber"])
	panel.open()
	var row: WallLedgerRow = _row_for(panel, province.id)
	assert_not_null(row, "the province is on the sheet")
	assert_eq(String(row.data.get("state", "")), WallLedger.STATE_READY, "the row offers the press")
	row.press_raise()
	var crew: CivilianState = _wall_crew(site)
	assert_not_null(crew, "the press sends an Engineer")
	assert_eq(crew.work_action(), "build_fort", "and files the wall order")
	assert_eq(crew.work_tile(), site, "on the province's own town tile")
	assert_eq(
		int(stock["lumber"]), lumber - int(price.get("lumber", 0)),
		"the price is the fort table's own"
	)
	assert_eq(_state_of(_row_for(panel, province.id)), "at_work", "and the row reads it")


## The purse is the third gate on the sheet itself: with every store at zero the
## row reads LOCKED and carries no press, and the materials arriving open it —
## no press the order would refuse (wiki: siege-mechanics § Fort Levels;
## DR-20261116-01, REQ-P2-03, REQ-P5-05).
func test_a_short_purse_leaves_the_raise_press_off_the_sheet() -> void:
	var panel: WallLedgerPanel = screen.hud.walls_ledger
	screen.play.tech_unlocked()["mine_engineering"] = true
	screen.play.tech_unlocked()["modern_forts"] = true
	_cancel_works()
	var province: ProvinceState = _crown_wall()
	assert_not_null(province, "the campaign seats the crown on ground that can carry a wall")
	var stock: Dictionary = screen.play.stockpile()
	for key: Variant in stock.keys():
		stock[key] = 0
	panel.open()
	var row: WallLedgerRow = _row_for(panel, province.id)
	assert_not_null(row, "the province is on the sheet")
	assert_eq(String(row.data.get("state", "")), WallLedger.STATE_LOCKED, "the order would refuse")
	assert_false(row._raise.visible, "a row that cannot be raised carries no press")
	assert_true(String(row.data.get("note", "")).contains("Stores are short of"), row.data.get("note", ""))
	## The materials arrive: the same row opens without the sheet reopening.
	var price: Dictionary = FortRules.cost(FortRules.next_level(province.fort_level))
	for key: Variant in price.keys():
		stock[key] = int(price[key])
	panel.refresh()
	var paid: WallLedgerRow = _row_for(panel, province.id)
	assert_eq(String(paid.data.get("state", "")), WallLedger.STATE_READY, "paid, the step opens")
	assert_true(paid._raise.visible, "and the press returns")


## The map hooks answer a missing session and an unreadable province without
## folding: a sheet that opens before the campaign seats reads an empty roll.
func test_the_map_hooks_guard_a_missing_session() -> void:
	assert_eq(int(MapPlayWalls.snapshot(null).get("total", -1)), 0, "no session, no walls")
	MapPlayWalls.raise(null, FactionCatalog.OLD_WORLD, 0)
	MapPlayWalls.raise(screen.play, FactionCatalog.OLD_WORLD, -1)
	MapPlayWalls.raise(screen.play, 99, 0)
	assert_eq(int(MapPlayWalls.snapshot(screen.play).get("total", 0)), _crown_walls())


func test_back_and_the_key_close_the_walls_ledger() -> void:
	var panel: WallLedgerPanel = screen.hud.walls_ledger
	screen.hud.walls_pressed.emit()
	assert_true(panel.is_open())
	assert_true(BackRequest.handle(screen.play, screen.play.improvements))
	assert_false(panel.is_open(), "back sets the ledger aside first")
	InputActions.ensure_actions()
	var toggle := InputEventAction.new()
	toggle.action = InputActions.WALLS_LEDGER
	toggle.pressed = true
	panel._unhandled_input(toggle)
	assert_true(panel.is_open(), "the key opens it from the map")
	panel._unhandled_input(toggle)
	assert_false(panel.is_open(), "and closes it again")


# --- fixtures ---------------------------------------------------------------


## Two charts of the naval fixture: the crown holds Cádiz at home (a bare town)
## and Veracruz abroad (a wood wall), and the rival's Coro carries a town of its
## own that must never reach the reading.
func _regions(
	units: Array, tech: Dictionary = {"mine_engineering": true}, stockpile: Variant = null
) -> Array[Dictionary]:
	var old: MapModel = Naval.build()
	var new: MapModel = Naval.build()
	new.region_id = FactionCatalog.NEW_WORLD
	new.provinces[0].name = "Veracruz"
	new.provinces[0].capital = false
	new.provinces[0].town_tile = TOWN_TILE
	new.provinces[0].fort_level = 1
	old.provinces[0].town_tile = TOWN_TILE
	old.provinces[1].town_tile = Vector2i(5, 1)
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


## The gates a citadel owes: Mine Engineering for stone, Modern Forts for the
## third level, so a raised wall is a finished wall.
func _wide_tech() -> Dictionary:
	return {"mine_engineering": true, "modern_forts": true}


## One idle Engineer on the crown's own ground, so a ready shore has a crew free.
func _engineers() -> Array:
	return [CivilianState.create(1, 0, "engineer", TOWN_TILE)]


## The crown's province at home, walled to the third level, so the finished
## reading has a row of its own.
func _raised_snapshot() -> Dictionary:
	var regions: Array[Dictionary] = _regions(_engineers(), _wide_tech())
	(regions[0]["model"] as MapModel).provinces[0].fort_level = FortRules.MAX_LEVEL
	return WallLedger.snapshot(regions, 0)


func _raised() -> Dictionary:
	return _row(_raised_snapshot(), FactionCatalog.OLD_WORLD)


func _row(snapshot: Dictionary, region: int) -> Dictionary:
	for raw: Variant in snapshot["rows"]:
		var row: Dictionary = raw
		if int(row["region"]) == region:
			return row
	return {}


## The first crown province of the mounted campaign that can carry a wall and
## has not been finished yet.
func _crown_wall() -> ProvinceState:
	for province: ProvinceState in screen.play.model.provinces:
		if province.owner != screen.play.player_faction:
			continue
		if province.fort_level >= FortRules.MAX_LEVEL:
			continue
		if FortRules.site_tile(screen.play.model, province.id).x >= 0:
			return province
	return null


## The realm ledger's walls door, found by its word so the suite reads the
## button the player presses.
func _walls_door() -> Button:
	for node: Node in screen.hud.province_ledger.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text == "Walls ›":
			return button
	return null


## Frees every crew this suite put to work, so a case that reads a row does not
## inherit the order an earlier case filed.
func _cancel_works() -> void:
	for unit: CivilianState in screen.play.civilian_layer.units:
		if unit != null and unit.owner == screen.play.player_faction and unit.is_working():
			unit.cancel_work()


## The Engineer the sheet sent: the crown's crew with a wall order on this site.
func _wall_crew(site: Vector2i) -> CivilianState:
	for unit: CivilianState in screen.play.civilian_layer.units:
		if unit.owner != screen.play.player_faction or not unit.is_working():
			continue
		if unit.work_action() == "build_fort" and unit.work_tile() == site:
			return unit
	return null


func _row_for(panel: WallLedgerPanel, province_id: int) -> WallLedgerRow:
	for child: Node in panel._rows.get_children():
		var row := child as WallLedgerRow
		if row != null and int(row.data.get("id", -1)) == province_id:
			return row
	return null


func _state_of(row: WallLedgerRow) -> String:
	if row == null:
		return ""
	return String(row.data.get("state", ""))


## How many provinces the mounted campaign's crown holds that can carry a wall,
## so the sheet's own total is checked against the chart rather than a hand
## count.
func _crown_walls() -> int:
	var total: int = 0
	for region: int in screen.play.world.region_count():
		var model: MapModel = screen.play.world.region(region)
		if model == null:
			continue
		for province: ProvinceState in model.provinces:
			if province == null or province.owner != screen.play.player_faction:
				continue
			if FortRules.site_tile(model, province.id).x >= 0:
				total += 1
	return total


func _row_widgets(panel: WallLedgerPanel) -> int:
	var total: int = 0
	for child: Node in panel._rows.get_children():
		if child is WallLedgerRow:
			total += 1
	return total
