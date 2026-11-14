extends GdToolsTest
## The crown's provinces: the whole-empire province ledger projects every
## province the crown holds in both charts (wiki: world-model § Provinces and
## Tiles; DR-20261115-09) and the panel drives it — seal, key, filters and
## Visit. One Godot boot: the projection suite reads small fixtures, the drive
## mounts the shared map screen (docs/testing.md).

const Naval = preload("res://tests/naval_fixture.gd")
const Fixture = preload("res://tests/map_fixture.gd")

var screen: MapScreen = null


func before_all() -> void:
	screen = Fixture.attach_screen(self)


func after_all() -> void:
	if is_instance_valid(screen):
		screen.hud.province_ledger.close()
		screen.free()
	screen = null


func before_each() -> void:
	if screen == null or not is_instance_valid(screen):
		screen = Fixture.attach_screen(self)
		return
	screen.hud.province_ledger.close()


# --- projection -------------------------------------------------------------


func test_snapshot_lists_every_own_province_in_both_charts() -> void:
	var snapshot: Dictionary = ProvinceLedger.snapshot(_regions(), 0)
	assert_eq(int(snapshot["total"]), 2, "one crown province per chart")
	assert_eq((snapshot["groups"] as Array).size(), 2, "one heading per chart")
	assert_eq(ProvinceLedger.count(snapshot, ProvinceLedger.REGION_OLD), 1)
	assert_eq(ProvinceLedger.count(snapshot, ProvinceLedger.REGION_NEW), 1)
	for raw: Variant in snapshot["rows"]:
		var row: Dictionary = raw
		assert_ne(String(row["name"]), "Coro", "the rival's province stays out")
		assert_ne(String(row["name"]), "", "every row names its province")


func test_the_seat_leads_the_reading() -> void:
	var snapshot: Dictionary = ProvinceLedger.snapshot(_regions(), 0)
	var first: Dictionary = (snapshot["rows"] as Array)[0]
	assert_eq(String(first["name"]), "Cádiz", "the seat is read first")
	assert_true(bool(first["capital"]), "and it is marked as the seat")
	assert_eq(String(first["place"]), "Harbour — Mar Caribe", "its own water is named")


func test_a_cut_off_province_is_flagged_and_counted() -> void:
	var snapshot: Dictionary = ProvinceLedger.snapshot(_regions(), 0)
	var overseas: Dictionary = _row(snapshot, FactionCatalog.NEW_WORLD)
	assert_false(bool(overseas["linked"]), "the overseas province has no road home")
	assert_true((overseas["flags"] as Array).has(ProvinceLedger.FILTER_CUT))
	assert_true(
		String(overseas["state"]).contains("Cut off — 3 road tiles to lay"),
		"the row names the gap it waits on"
	)
	var counts: Dictionary = ProvinceLedger.filter_counts(snapshot, ProvinceLedger.REGION_ALL)
	assert_eq(int(counts[ProvinceLedger.FILTER_CUT]), 1, "one province is cut off")


func test_a_blockaded_harbour_is_named_not_a_missing_road() -> void:
	var regions: Array[Dictionary] = _regions()
	(regions[0]["links"] as Dictionary)[0] = {
		"linked": false, "distance": -1, "blockaded": true,
	}
	var snapshot: Dictionary = ProvinceLedger.snapshot(regions, 0)
	var home: Dictionary = _row(snapshot, FactionCatalog.OLD_WORLD)
	assert_true(String(home["state"]).contains("Harbour blockaded"))


func test_an_ungarrisoned_province_is_flagged_and_a_rival_does_not_hold_it() -> void:
	var snapshot: Dictionary = ProvinceLedger.snapshot(_regions(), 0)
	var home: Dictionary = _row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(int(home["regiments"]), 2, "the crown's two regiments stand there")
	assert_false((home["flags"] as Array).has(ProvinceLedger.FILTER_UNGARRISONED))
	var overseas: Dictionary = _row(snapshot, FactionCatalog.NEW_WORLD)
	assert_eq(int(overseas["regiments"]), 0, "a rival's standard is not a garrison")
	assert_true((overseas["flags"] as Array).has(ProvinceLedger.FILTER_UNGARRISONED))
	assert_true(String(overseas["state"]).contains("Ungarrisoned"))


func test_estates_read_the_ledgers_own_yield_and_works() -> void:
	var snapshot: Dictionary = ProvinceLedger.snapshot(_regions(), 0)
	var home: Dictionary = _row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(int(home["estates"]), 2, "two estates in the seat")
	assert_eq(int(home["yield"]), 5, "3 + 2, the rows' own output")
	assert_true((home["flags"] as Array).has(ProvinceLedger.FILTER_WORKS))
	assert_true(String(home["line"]).contains("2 estates · 5 a turn"))
	var overseas: Dictionary = _row(snapshot, FactionCatalog.NEW_WORLD)
	assert_eq(int(overseas["estates"]), 0)
	assert_true(String(overseas["line"]).contains("No estates"))


func test_filters_narrow_the_ledger_and_keep_their_tallies() -> void:
	var snapshot: Dictionary = ProvinceLedger.snapshot(_regions(), 0)
	var counts: Dictionary = ProvinceLedger.filter_counts(snapshot, ProvinceLedger.REGION_ALL)
	assert_eq(int(counts[ProvinceLedger.FILTER_ALL]), 2)
	assert_eq(int(counts[ProvinceLedger.FILTER_UNGARRISONED]), 1)
	assert_eq(int(counts[ProvinceLedger.FILTER_WORKS]), 1)
	var cut: Array[Dictionary] = ProvinceLedger.groups(
		snapshot, ProvinceLedger.REGION_ALL, ProvinceLedger.FILTER_CUT
	)
	assert_eq(cut.size(), 1, "only the chart that holds a cut-off province")
	for group: Dictionary in cut:
		assert_eq(int(group["region"]), FactionCatalog.NEW_WORLD)
		assert_eq((group["rows"] as Array).size(), 1)
	assert_eq(
		ProvinceLedger.count(snapshot, ProvinceLedger.REGION_OLD, ProvinceLedger.FILTER_CUT),
		0,
		"the seat is not cut off"
	)


# --- the sheet --------------------------------------------------------------


func test_the_realm_door_opens_the_ledger_and_its_rows_visit_a_province() -> void:
	var panel: ProvinceLedgerPanel = screen.hud.province_ledger
	assert_not_null(panel, "the HUD mounts the province ledger")
	var door: Button = _realm_door()
	assert_not_null(door, "the province dossier carries the realm door")
	door.pressed.emit()
	assert_true(panel.is_open(), "the dossier's realm door opens it")
	assert_true(_row_widgets(panel) > 0, "the crown's provinces are listed")
	var row: ProvinceLedgerRow = _first_row(panel)
	assert_not_null(row)
	var tap := InputEventMouseButton.new()
	tap.pressed = true
	tap.button_index = MOUSE_BUTTON_LEFT
	row._gui_input(tap)
	assert_false(panel.is_open(), "a tap on the row visits the province")
	assert_true(screen.play.selected_province >= 0, "and the dossier is open on it")


func test_back_and_the_key_close_the_ledger() -> void:
	var panel: ProvinceLedgerPanel = screen.hud.province_ledger
	screen.hud.provinces_pressed.emit()
	assert_true(panel.is_open())
	assert_true(BackRequest.handle(screen.play, screen.play.improvements))
	assert_false(panel.is_open(), "back sets the ledger aside first")
	InputActions.ensure_actions()
	var toggle := InputEventAction.new()
	toggle.action = InputActions.PROVINCE_LEDGER
	toggle.pressed = true
	panel._unhandled_input(toggle)
	assert_true(panel.is_open(), "the key opens it from the map")
	panel._unhandled_input(toggle)
	assert_false(panel.is_open(), "and closes it again")


# --- fixtures ---------------------------------------------------------------


## Two charts of the naval fixture: the crown holds Cádiz at home and a
## renamed province abroad, with one rival province on each chart.
func _regions() -> Array[Dictionary]:
	var old: MapModel = Naval.build()
	var new: MapModel = Naval.build()
	new.region_id = FactionCatalog.NEW_WORLD
	new.provinces[0].name = "Veracruz"
	new.provinces[0].capital = false
	var armies: Array = [
		ArmyState.muster(1, 0, 0, true, ["pikemen", "arquebusiers"]),
		ArmyState.muster(2, 1, 0, false, ["pikemen"]),
	]
	var estates: Dictionary = {
		"groups": [
			{
				"id": 0,
				"name": "Cádiz",
				"count": 2,
				"rows": [
					{"output": 3, "working": true},
					{"output": 2, "working": false},
				],
			},
		],
	}
	return [
		{
			"region": FactionCatalog.OLD_WORLD,
			"model": old,
			"armies": armies,
			"estates": estates,
			"links": {0: {"linked": true, "distance": 0, "blockaded": false}},
		},
		{
			"region": FactionCatalog.NEW_WORLD,
			"model": new,
			"armies": [] as Array,
			"estates": {},
			"links": {0: {"linked": false, "distance": 3, "blockaded": false}},
		},
	]


func _row(snapshot: Dictionary, region: int) -> Dictionary:
	for raw: Variant in snapshot["rows"]:
		var row: Dictionary = raw
		if int(row["region"]) == region:
			return row
	return {}


func _first_row(panel: ProvinceLedgerPanel) -> ProvinceLedgerRow:
	for child: Node in panel._rows.get_children():
		if child is ProvinceLedgerRow:
			return child
	return null


## The province dossier's realm door, found by its word so the suite reads the
## button the player presses.
func _realm_door() -> Button:
	for node: Node in screen.hud._panel.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text == "Realm":
			return button
	return null


func _row_widgets(panel: ProvinceLedgerPanel) -> int:
	var total: int = 0
	for child: Node in panel._rows.get_children():
		if child is ProvinceLedgerRow:
			total += 1
	return total
