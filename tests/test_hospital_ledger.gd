extends GdToolsTest
## The crown's hospitals: the whole-empire ward ledger reads every province the
## crown holds that can carry a ward, the level it stands at, whether its staff
## ate and the step the Engineer would take next (wiki: combat § Regiment
## condition; DR-20261116-02) and the sheet drives it — the realm's door, the
## Raise press and back. One Godot boot: the projection suite reads small
## fixtures, the drive mounts the shared map screen (docs/testing.md).

const Naval = preload("res://tests/naval_fixture.gd")
const Fixture = preload("res://tests/map_fixture.gd")
const TOWN_TILE: Vector2i = Vector2i(1, 0)

var screen: MapScreen = null


func before_all() -> void:
	screen = Fixture.attach_screen(self)


func after_all() -> void:
	if is_instance_valid(screen):
		screen.hud.hospitals_ledger.close()
		screen.hud.province_ledger.close()
		screen.free()
	screen = null


func before_each() -> void:
	if screen == null or not is_instance_valid(screen):
		screen = Fixture.attach_screen(self)
		return
	screen.hud.hospitals_ledger.close()
	screen.hud.province_ledger.close()


# --- projection -------------------------------------------------------------


func test_snapshot_lists_every_ward_the_crown_can_raise_in_both_charts() -> void:
	var snapshot: Dictionary = HospitalLedger.snapshot(_regions(_engineers()), 0)
	assert_eq(int(snapshot["total"]), 2, "one crown province per chart")
	assert_eq((snapshot["groups"] as Array).size(), 2, "one heading per chart")
	assert_eq(HospitalLedger.count(snapshot, LedgerRows.REGION_OLD), 1)
	assert_eq(HospitalLedger.count(snapshot, LedgerRows.REGION_NEW), 1)
	for raw: Variant in snapshot["rows"]:
		var row: Dictionary = raw
		assert_ne(String(row["name"]), "Coro", "the rival's shore stays out")


func test_a_bare_shore_names_the_step_it_waits_on_and_its_price() -> void:
	var snapshot: Dictionary = HospitalLedger.snapshot(_regions(_engineers()), 0)
	var home: Dictionary = _row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(String(home["state"]), HospitalLedger.STATE_READY, "a crew is free and no study is owed")
	assert_eq(String(home["level_text"]), "—", "an empty shore is a dash, not a zero")
	assert_eq(String(home["line"]), "No hospital")
	assert_eq(int(home["next_level"]), 1)
	assert_eq(String(home["cost_text"]), "3 lumber + 2 fabric", "the ward table's own price")
	assert_eq(int(home["turns"]), 1, "a field ward is one turn")
	assert_eq(
		String(home["note"]),
		"Next: field hospital · 3 lumber + 2 fabric · 1 turn",
		"the row names the ward, the price and the wait"
	)


func test_a_ward_without_the_study_is_locked_and_names_it() -> void:
	var snapshot: Dictionary = HospitalLedger.snapshot(
		_regions(_engineers(), {"organised_regiments": true, "modern_military_funding": false}), 0
	)
	var overseas: Dictionary = _row(snapshot, FactionCatalog.NEW_WORLD)
	assert_eq(String(overseas["state"]), HospitalLedger.STATE_LOCKED, "a field ward is up; the general one is gated")
	assert_true(
		String(overseas["note"]).contains("Modern Military Funding"),
		"the row names the study that opens it"
	)
	assert_eq(
		int(HospitalLedger.filter_counts(snapshot, LedgerRows.REGION_ALL)[HospitalLedger.FILTER_READY]),
		1,
		"a locked ward is not counted as ready"
	)


func test_a_shore_with_no_idle_crew_waits_on_an_engineer() -> void:
	var snapshot: Dictionary = HospitalLedger.snapshot(_regions([] as Array), 0)
	var home: Dictionary = _row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(String(home["state"]), HospitalLedger.STATE_NO_ENGINEER, "no crew musters")
	assert_true(String(home["note"]).contains("No idle Engineer"), "the row names the wait")


func test_an_engineer_already_at_work_is_read_from_its_own_record() -> void:
	var engineer: CivilianState = CivilianState.create(1, 0, "engineer", TOWN_TILE)
	engineer.start_work("build_hospital", TOWN_TILE, 2, TOWN_TILE, {"hospital_level": 1})
	var snapshot: Dictionary = HospitalLedger.snapshot(_regions([engineer]), 0)
	var home: Dictionary = _row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(String(home["state"]), HospitalLedger.STATE_AT_WORK)
	assert_eq(int(home["remaining"]), 2)
	assert_true(String(home["note"]).contains("raises the field hospital"), "the target ward is named")
	assert_true(String(home["note"]).contains("2 turns left"))


func test_a_general_hospital_reads_finished() -> void:
	var raised: Dictionary = _raised()
	assert_eq(int(raised["level"]), HospitalRules.MAX_LEVEL)
	assert_eq(String(raised["state"]), HospitalLedger.STATE_RAISED, "a general ward owes nothing")
	assert_eq(
		String(raised["note"]),
		"Fully warded — rest 55%, wear 65%, staff 4 food a turn."
	)
	assert_eq(String(raised["level_text"]), "II")


func test_a_ward_that_went_unfed_says_so_and_leads_its_state() -> void:
	var regions: Array[Dictionary] = _regions(_engineers())
	(regions[0]["model"] as MapModel).provinces[0].hospital_level = 1
	(regions[0]["model"] as MapModel).provinces[0].hospital_staffed = false
	var snapshot: Dictionary = HospitalLedger.snapshot(regions, 0)
	var home: Dictionary = _row(snapshot, FactionCatalog.OLD_WORLD)
	assert_false(bool(home["staffed"]), "the row knows the staff went unfed")
	assert_true(
		String(home["line"]).contains("unstaffed — no rations this turn"),
		"the line names the hunger"
	)
	var reading: Dictionary = HospitalLedger.summary(snapshot, LedgerRows.REGION_ALL)
	assert_eq(int(reading["unfed"]), 1, "the count line names it too")
	assert_eq(int(reading["ration"]), 4, "a hungry ward still owes its ration")


func test_the_stores_gate_closes_a_row_the_order_would_refuse() -> void:
	var broke: Dictionary = HospitalLedger.snapshot(_regions(_engineers()), 0, {})
	var home: Dictionary = _row(broke, FactionCatalog.OLD_WORLD)
	assert_eq(String(home["state"]), HospitalLedger.STATE_LOCKED, "an empty purse offers no press")
	assert_true(
		String(home["note"]).contains("Stores are short of 3 lumber + 2 fabric"),
		"the row names the shortfall"
	)
	var paid: Dictionary = HospitalLedger.snapshot(
		_regions(_engineers()), 0, {"lumber": 3, "fabric": 2}
	)
	assert_eq(
		String(_row(paid, FactionCatalog.OLD_WORLD)["state"]),
		HospitalLedger.STATE_READY,
		"paying the price opens the press"
	)
	var unpriced: Dictionary = HospitalLedger.snapshot(_regions(_engineers()), 0)
	assert_eq(
		String(_row(unpriced, FactionCatalog.OLD_WORLD)["state"]),
		HospitalLedger.STATE_READY,
		"a projection that prices no spend never reads LOCKED on an empty purse"
	)


func test_filters_narrow_the_ledger_and_keep_their_tallies() -> void:
	var snapshot: Dictionary = HospitalLedger.snapshot(
		_regions(_engineers(), {"organised_regiments": true, "modern_military_funding": false}), 0
	)
	var counts: Dictionary = HospitalLedger.filter_counts(snapshot, LedgerRows.REGION_ALL)
	assert_eq(int(counts[HospitalLedger.FILTER_ALL]), 2)
	assert_eq(int(counts[HospitalLedger.FILTER_READY]), 1)
	assert_eq(int(counts[HospitalLedger.FILTER_RAISED]), 0)
	assert_eq(int(counts[HospitalLedger.FILTER_AT_WORK]), 0)
	var ready: Array[Dictionary] = HospitalLedger.groups(
		snapshot, LedgerRows.REGION_ALL, HospitalLedger.FILTER_READY
	)
	assert_eq(ready.size(), 1, "only the chart that holds a ready ward")
	assert_eq(int(ready[0]["region"]), FactionCatalog.OLD_WORLD)
	assert_eq(
		HospitalLedger.count(snapshot, LedgerRows.REGION_NEW, HospitalLedger.FILTER_READY), 0
	)


func test_the_reading_leads_with_what_can_be_raised_now() -> void:
	var rows: Array = _raised_snapshot()["rows"]
	assert_eq(
		String((rows[0] as Dictionary)["state"]),
		HospitalLedger.STATE_READY,
		"the empty shore leads"
	)
	assert_eq(
		String((rows[1] as Dictionary)["state"]),
		HospitalLedger.STATE_RAISED,
		"the general ward follows"
	)


func test_the_summary_names_where_nothing_heals_and_what_the_staffs_eat() -> void:
	var snapshot: Dictionary = HospitalLedger.snapshot(_regions(_engineers(), _wide_tech()), 0)
	var reading: Dictionary = HospitalLedger.summary(snapshot, LedgerRows.REGION_ALL)
	assert_eq(int(reading["total"]), 2)
	assert_eq(int(reading["bare"]), 1, "one empty shore")
	assert_eq(int(reading["standing"]), 1, "one field ward")
	assert_eq(int(reading["ration"]), 2, "a field ward eats 2 food a turn")
	var built: Dictionary = _raised_snapshot()
	var home: Dictionary = _row(built, FactionCatalog.OLD_WORLD)
	assert_eq(int(home["level"]), HospitalRules.MAX_LEVEL, "the general ward stands")
	assert_eq(int(home["demand"]), 4, "and eats 4")
	assert_eq(
		int(HospitalLedger.summary(built, LedgerRows.REGION_ALL)["ration"]),
		6,
		"the whole staff's bill is the sum of the wards"
	)


func test_the_rule_note_states_what_a_ward_buys() -> void:
	var note: String = HospitalLedger.rule_note()
	assert_true(note.contains("rest 40%"), "the field ward's rest is printed")
	assert_true(note.contains("55%"), "the general ward's rest is printed")
	assert_true(note.contains("2 food a turn per level"), "the ration is printed")
	assert_true(note.contains("unfed"), "and what a hungry ward costs")


# --- the sheet --------------------------------------------------------------


func test_the_realm_door_opens_the_hospitals_ledger() -> void:
	var panel: HospitalLedgerPanel = screen.hud.hospitals_ledger
	assert_not_null(panel, "the HUD mounts the hospitals ledger")
	var door: Button = _hospitals_door()
	assert_not_null(door, "the realm ledger carries the hospitals door")
	door.pressed.emit()
	assert_true(panel.is_open(), "the realm's hospitals door opens it")
	assert_true(_row_widgets(panel) > 0, "the crown's wards are listed")


func test_raise_files_the_engineers_order_on_the_provinces_chart() -> void:
	var panel: HospitalLedgerPanel = screen.hud.hospitals_ledger
	var province: ProvinceState = _crown_ward()
	assert_not_null(province, "the campaign seats the crown on ground that can carry a ward")
	screen.play.tech_unlocked()["organised_regiments"] = true
	screen.play.tech_unlocked()["modern_military_funding"] = true
	var stock: Dictionary = screen.play.stockpile()
	stock["lumber"] = 40
	stock["fabric"] = 40
	stock["steel"] = 40
	var site: Vector2i = HospitalRules.site_tile(screen.play.model, province.id)
	var price: Dictionary = HospitalRules.cost(HospitalRules.next_level(province.hospital_level))
	var lumber: int = int(stock["lumber"])
	panel.open()
	var row: HospitalLedgerRow = _row_for(panel, province.id)
	assert_not_null(row, "the province is on the sheet")
	assert_eq(String(row.data.get("state", "")), HospitalLedger.STATE_READY, "the row offers the press")
	row._raise_ward()
	var crew: CivilianState = _ward_crew(site)
	assert_not_null(crew, "the press sends an Engineer")
	assert_eq(crew.work_action(), "build_hospital", "and files the ward order")
	assert_eq(crew.work_tile(), site, "on the province's own town tile")
	assert_eq(
		int(stock["lumber"]), lumber - int(price.get("lumber", 0)),
		"the price is the ward table's own"
	)
	assert_eq(_state_of(_row_for(panel, province.id)), "at_work", "and the row reads it")


## The map hooks answer a missing session and an unreadable province without
## folding: a sheet that opens before the campaign seats reads an empty roll.
func test_the_map_hooks_guard_a_missing_session() -> void:
	assert_eq(int(MapPlayHospitals.snapshot(null).get("total", -1)), 0, "no session, no wards")
	MapPlayHospitals.raise(null, FactionCatalog.OLD_WORLD, 0)
	MapPlayHospitals.raise(screen.play, FactionCatalog.OLD_WORLD, -1)
	MapPlayHospitals.raise(screen.play, 99, 0)
	assert_eq(int(MapPlayHospitals.snapshot(screen.play).get("total", 0)), _crown_wards())


func test_back_closes_the_hospitals_ledger() -> void:
	var panel: HospitalLedgerPanel = screen.hud.hospitals_ledger
	screen.hud.hospitals_pressed.emit()
	assert_true(panel.is_open())
	assert_true(BackRequest.handle(screen.play, screen.play.improvements))
	assert_false(panel.is_open(), "back sets the ledger aside first")


func test_the_ration_the_sheet_prints_is_the_larder_demand_the_turn_pays() -> void:
	## The count line's "staffs eat N food a turn" must be the same number the
	## Consumption phase takes from the larder (`HospitalRules.demand_list`), or
	## the sheet prices a bill the turn never charges.
	var paid: int = 0
	for demand: int in HospitalRules.demand_list(screen.play.world, screen.play.player_faction):
		paid += demand
	var reading: Dictionary = HospitalLedger.summary(
		MapPlayHospitals.snapshot(screen.play), LedgerRows.REGION_ALL
	)
	assert_eq(int(reading["ration"]), paid, "the sheet's bill is the larder's own")


func test_the_sheet_offers_no_press_the_stores_refuse() -> void:
	## The walls/towns sheets shipped this defect once: a `READY` row whose
	## Raise the order refuses for want of materials. The ward sheet reads the
	## same purse the order charges, so a broke crown sees `LOCKED` and no press.
	var panel: HospitalLedgerPanel = screen.hud.hospitals_ledger
	var province: ProvinceState = _crown_ward()
	assert_not_null(province, "the campaign seats the crown on ground that can carry a ward")
	screen.play.tech_unlocked()["organised_regiments"] = true
	var stock: Dictionary = screen.play.stockpile()
	stock["lumber"] = 0
	stock["fabric"] = 0
	stock["steel"] = 0
	panel.open()
	var row: HospitalLedgerRow = _row_for(panel, province.id)
	assert_not_null(row, "the province is on the sheet")
	assert_eq(
		String(row.data.get("state", "")),
		HospitalLedger.STATE_LOCKED,
		"a broke crown is offered no ward"
	)
	assert_true(
		String(row.data.get("note", "")).contains("Stores are short of"),
		"the row names the shortfall the order would refuse on"
	)
	assert_false(_raise_visible(row), "and carries no press")
	var order: Dictionary = ImprovementOrders.build_hospital(
		screen.play.model, screen.play.civilian_layer.units, screen.play.land_works,
		stock, screen.play.visibility, screen.play.player_faction, province.id,
		screen.play.tech_caps(), screen.play.tech_unlocked()
	)
	assert_false(bool(order.get("ok", true)), "the order refuses too, so the two agree")


# --- fixtures ---------------------------------------------------------------


## Two charts of the naval fixture: the crown holds Cádiz at home (a bare town)
## and Veracruz abroad (a field ward), and the rival's Coro carries a town of its
## own that must never reach the reading.
func _regions(units: Array, tech: Dictionary = {"organised_regiments": true}) -> Array[Dictionary]:
	var old: MapModel = Naval.build()
	var new: MapModel = Naval.build()
	new.region_id = FactionCatalog.NEW_WORLD
	new.provinces[0].name = "Veracruz"
	new.provinces[0].capital = false
	new.provinces[0].town_tile = TOWN_TILE
	new.provinces[0].hospital_level = 1
	old.provinces[0].town_tile = TOWN_TILE
	old.provinces[1].town_tile = Vector2i(5, 1)
	return [
		{
			"region": FactionCatalog.OLD_WORLD,
			"model": old,
			"units": units,
			"tech_unlocked": tech,
		},
		{
			"region": FactionCatalog.NEW_WORLD,
			"model": new,
			"units": units,
			"tech_unlocked": tech,
		},
	]


## The gates a general ward owes: Organised Regiments for the field ward, Modern
## Military Funding for the general one, so a raised ward is a finished ward.
func _wide_tech() -> Dictionary:
	return {"organised_regiments": true, "modern_military_funding": true}


## One idle Engineer on the crown's own ground, so a ready shore has a crew free.
func _engineers() -> Array:
	return [CivilianState.create(1, 0, "engineer", TOWN_TILE)]


## The crown's province at home, warded to the second level, so the finished
## reading has a row of its own.
func _raised_snapshot() -> Dictionary:
	var regions: Array[Dictionary] = _regions(_engineers(), _wide_tech())
	(regions[0]["model"] as MapModel).provinces[0].hospital_level = HospitalRules.MAX_LEVEL
	return HospitalLedger.snapshot(regions, 0)


func _raised() -> Dictionary:
	return _row(_raised_snapshot(), FactionCatalog.OLD_WORLD)


func _row(snapshot: Dictionary, region: int) -> Dictionary:
	for raw: Variant in snapshot["rows"]:
		var row: Dictionary = raw
		if int(row["region"]) == region:
			return row
	return {}


## The first crown province of the mounted campaign that can carry a ward, has
## not been finished yet and has no crew already at work on its site — so a case
## that raises a ward never leaves the next one reading `AT WORK`.
func _crown_ward() -> ProvinceState:
	for province: ProvinceState in screen.play.model.provinces:
		if province.owner != screen.play.player_faction:
			continue
		if province.hospital_level >= HospitalRules.MAX_LEVEL:
			continue
		var site: Vector2i = HospitalRules.site_tile(screen.play.model, province.id)
		if site.x < 0:
			continue
		if _ward_crew(site) != null:
			continue
		return province
	return null


## The realm ledger's hospitals door, found by its word so the suite reads the
## button the player presses.
func _hospitals_door() -> Button:
	for node: Node in screen.hud.province_ledger.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text == "Hospitals ›":
			return button
	return null


## The Engineer the sheet sent: the crown's crew with a ward order on this site.
func _ward_crew(site: Vector2i) -> CivilianState:
	for unit: CivilianState in screen.play.civilian_layer.units:
		if unit.owner != screen.play.player_faction or not unit.is_working():
			continue
		if unit.work_action() == "build_hospital" and unit.work_tile() == site:
			return unit
	return null


func _row_for(panel: HospitalLedgerPanel, province_id: int) -> HospitalLedgerRow:
	for child: Node in panel._rows.get_children():
		var row := child as HospitalLedgerRow
		if row != null and int(row.data.get("id", -1)) == province_id:
			return row
	return null


func _state_of(row: HospitalLedgerRow) -> String:
	if row == null:
		return ""
	return String(row.data.get("state", ""))


## Whether the row carries the Raise press at all — a row the order would refuse
## must not (REQ-P2-03).
func _raise_visible(row: HospitalLedgerRow) -> bool:
	return row != null and row._raise != null and row._raise.visible


## How many provinces the mounted campaign's crown holds that can carry a ward,
## so the sheet's own total is checked against the chart rather than a hand
## count.
func _crown_wards() -> int:
	var total: int = 0
	for region: int in screen.play.world.region_count():
		var model: MapModel = screen.play.world.region(region)
		if model == null:
			continue
		for province: ProvinceState in model.provinces:
			if province == null or province.owner != screen.play.player_faction:
				continue
			if HospitalRules.site_tile(model, province.id).x >= 0:
				total += 1
	return total


func _row_widgets(panel: HospitalLedgerPanel) -> int:
	var total: int = 0
	for child: Node in panel._rows.get_children():
		if child is HospitalLedgerRow:
			total += 1
	return total
