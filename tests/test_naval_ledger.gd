extends GdToolsTest
## The crown's navy, hull by hull (wiki: ships-and-naval § Ship combat and cargo
## stats, § Ship instances; DR-20261115-14): the projection reads every hull the
## crown floats in both charts, squadron by squadron, and the sheet drives it —
## the fleet dossier's door, the readings, back and the key. One Godot boot: the
## projection cases read a tiny two-chart fixture, the sheet cases mount the
## shared map screen (docs/testing.md).

const Naval = preload("res://tests/naval_fixture.gd")
const Fixture = preload("res://tests/map_fixture.gd")

const OWNER: int = 0
const RIVAL: int = 1

var screen: MapScreen = null


func before_all() -> void:
	screen = Fixture.attach_screen(self)


func after_all() -> void:
	if is_instance_valid(screen):
		screen.hud.navy_ledger.close()
		screen.free()
	screen = null


func before_each() -> void:
	if screen == null or not is_instance_valid(screen):
		screen = Fixture.attach_screen(self)
		return
	screen.hud.navy_ledger.close()


# --- projection -------------------------------------------------------------


func test_the_ledger_reads_every_hull_of_both_charts() -> void:
	var data: Dictionary = NavalLedger.snapshot(_world(), _regions(), OWNER)
	assert_eq(int(data["total"]), 3, "one row per hull the crown floats")
	assert_eq((data["groups"] as Array).size(), 2, "one heading per squadron")
	assert_eq(NavalLedger.count(data, NavalLedger.REGION_OLD), 2)
	assert_eq(NavalLedger.count(data, NavalLedger.REGION_NEW), 1)
	assert_eq(NavalLedger.squadron_count(data, NavalLedger.REGION_ALL), 2)
	for raw: Variant in data["rows"]:
		var row: Dictionary = raw
		assert_ne(String(row["hull"]), "ship_9", "the rival's hull stays out")


func test_a_hull_row_reads_her_class_guns_and_holds() -> void:
	var data: Dictionary = NavalLedger.snapshot(_world(), _regions(), OWNER)
	var frigate: Dictionary = _row_of(data, "ship_2")
	assert_eq(String(frigate["class"]), "Frigate")
	assert_eq(String(frigate["role"]), NavalLedger.READING_WARSHIP)
	assert_eq(String(frigate["role_label"]), "WARSHIP")
	assert_eq(String(frigate["line"]), NavalStrength.hull_line("frigate"), "the catalogue's own line")
	assert_eq(int(frigate["holds"]), 0, "a warship carries none")
	assert_eq(String(frigate["state"]), "No holds — she fights in the line")
	var carrack: Dictionary = _row_of(data, "ship_1")
	assert_eq(String(carrack["role"]), NavalLedger.READING_MERCHANT)
	assert_eq(String(carrack["state"]), "3 holds for the world market")
	assert_eq(int(carrack["holds"]), 3)


func test_the_line_leads_every_squadron() -> void:
	var data: Dictionary = NavalLedger.snapshot(_world(), _regions(), OWNER)
	var rows: Array = data["rows"]
	var first: Dictionary = rows[0]
	assert_eq(String(first["role"]), NavalLedger.READING_WARSHIP, "the man-of-war leads her squadron")
	assert_eq(String(first["region_label"]), FactionCatalog.region_label(FactionCatalog.OLD_WORLD))


func test_the_squadron_heading_reads_where_she_sails_and_her_station() -> void:
	var data: Dictionary = NavalLedger.snapshot(_world(), _regions(), OWNER)
	var groups: Array[Dictionary] = NavalLedger.groups(data, NavalLedger.REGION_ALL)
	var home: Dictionary = groups[0]
	assert_true(String(home["heading"]).contains("SQUADRON — "), "the heading names the flagship")
	assert_eq(String(home["place"]), "In port at Cádiz")
	assert_eq(String(home["station"]), "Patrol", "the station is the rules' own word")
	assert_eq(int(home["holds"]), TradeCargo.fleet_holds(_home_fleet()), "her holds, not the ship's")
	assert_almost_eq(float(home["strength"]), NavalStrength.strength(_home_fleet()), 0.001)
	var abroad: Dictionary = groups[1]
	assert_eq(String(abroad["place"]), "At sea — Mar Caribe")
	assert_eq(String(abroad["station"]), "Awaiting orders")


func test_the_readings_narrow_the_ledger_and_keep_their_tallies() -> void:
	var data: Dictionary = NavalLedger.snapshot(_world(), _regions(), OWNER)
	var counts: Dictionary = NavalLedger.filter_counts(data, NavalLedger.REGION_ALL)
	assert_eq(int(counts[NavalLedger.READING_ALL]), 3)
	assert_eq(int(counts[NavalLedger.READING_WARSHIP]), 1)
	assert_eq(int(counts[NavalLedger.READING_MERCHANT]), 2)
	assert_eq(NavalLedger.count(data, NavalLedger.REGION_NEW, NavalLedger.READING_WARSHIP), 0)
	var warships: Array[Dictionary] = NavalLedger.groups(
		data, NavalLedger.REGION_ALL, NavalLedger.READING_WARSHIP
	)
	assert_eq(warships.size(), 1, "only the squadron that still has a standing hull")
	for row: Dictionary in warships[0]["rows"]:
		assert_eq(String(row["role"]), NavalLedger.READING_WARSHIP)


func test_the_count_line_and_the_note_print_the_rules_own_figures() -> void:
	var data: Dictionary = NavalLedger.snapshot(_world(), _regions(), OWNER)
	var line: String = NavalLedger.summary(data, NavalLedger.REGION_ALL)
	assert_true(line.contains("3 of 3 hulls in 2 squadrons"))
	assert_true(line.contains("1 warships, 2 merchant hulls"))
	assert_true(line.contains("8 holds"), "the merchant hulls' own cargo")
	assert_true(line.contains("strength"))
	var narrowed: String = NavalLedger.summary(
		data, NavalLedger.REGION_OLD, NavalLedger.READING_MERCHANT
	)
	assert_true(narrowed.contains("1 of 2 hulls in the Old World"), "the chart is the denominator")
	assert_true(narrowed.contains("merchant hulls only"))
	assert_true(NavalLedger.note().contains("holds cap"), "the rule a crown buys by is printed")


func test_a_chart_with_no_squadron_reads_empty_and_a_slip_reads_no_hull() -> void:
	assert_eq(int(NavalLedger.snapshot(null, _regions(), OWNER).get("total", -1)), 0)
	assert_eq(int(NavalLedger.snapshot(_world(), null, OWNER).get("total", -1)), 0)
	var slip := FleetState.empty_in_port(7, OWNER, 0)
	var table := MapRegionTable.new()
	table.set_region(FactionCatalog.OLD_WORLD, [slip])
	var data: Dictionary = NavalLedger.snapshot(_world(), table, OWNER)
	assert_eq(int(data["total"]), 0, "a slip has no hull to read")
	assert_eq(NavalLedger.squadron_count(data, NavalLedger.REGION_ALL), 1, "the yard is still counted")
	assert_eq((data["groups"] as Array).size(), 0, "an empty squadron prints no heading")
	assert_true(NavalLedger.summary(data, NavalLedger.REGION_ALL).contains("0 hulls"))


# --- the row ----------------------------------------------------------------


func test_a_row_prints_her_name_chip_and_her_own_line() -> void:
	var data: Dictionary = NavalLedger.snapshot(_world(), _regions(), OWNER)
	var row := NavalLedgerRow.new()
	row.setup(_row_of(data, "ship_2"))
	assert_ne(row._name.text, "", "every hull flies a name")
	assert_eq(row._chip.text, "WARSHIP")
	assert_true(row._detail.text.contains("In port at Cádiz"))
	assert_true(row._standing.text.contains("FRP"), "the catalogue's own line")
	assert_true(row._reading.text.contains("No holds"))
	row.free()


func test_a_compact_row_folds_her_class_into_the_detail_line() -> void:
	var data: Dictionary = NavalLedger.snapshot(_world(), _regions(), OWNER)
	var row := NavalLedgerRow.new()
	row.compact = true
	row.setup(_row_of(data, "ship_3"))
	assert_true(row._detail.text.contains("Trader"), "a phone row names the class")
	assert_true(row._detail.text.contains("At sea — Mar Caribe"))
	row.free()


func test_a_visit_asks_for_her_squadrons_chart() -> void:
	var data: Dictionary = NavalLedger.snapshot(_world(), _regions(), OWNER)
	var row := NavalLedgerRow.new()
	row.setup(_row_of(data, "ship_3"))
	var seen: Array = []
	row.visit_pressed.connect(func(region: int, fleet_id: int) -> void:
		seen.append([region, fleet_id])
	)
	row._on_visit()
	assert_eq(seen.size(), 1)
	assert_eq(int((seen[0] as Array)[0]), FactionCatalog.NEW_WORLD)
	assert_eq(int((seen[0] as Array)[1]), 2, "her squadron, not the hull")
	row.free()


# --- the sheet --------------------------------------------------------------


func test_the_muster_rolls_door_opens_the_ledger() -> void:
	var panel: NavalLedgerPanel = screen.hud.navy_ledger
	assert_not_null(panel, "the HUD mounts the navy ledger")
	screen.hud.muster_roll_pressed.emit()
	var door: Button = _navy_door()
	assert_not_null(door, "the muster roll carries the navy door")
	door.pressed.emit()
	assert_true(panel.is_open(), "the muster roll's navy door opens it")
	assert_true(_row_widgets(panel) > 0, "the crown's hulls are listed")
	assert_true(panel._subtitle.text.contains("hulls"), "the count line names the fleet")
	assert_true(_has_text(panel._rows, "holds"), "a squadron heading prints her holds")
	screen.hud.muster_roll.close()


func test_the_readings_narrow_the_sheet() -> void:
	var panel: NavalLedgerPanel = screen.hud.navy_ledger
	screen.hud.navy_pressed.emit()
	assert_true(panel.is_open())
	panel._on_filter(NavalLedger.READING_WARSHIP, false)
	assert_eq(panel._reading, NavalLedger.READING_WARSHIP)
	assert_true(panel._subtitle.text.contains("warships only"))
	for child: Node in panel._rows.get_children():
		var row := child as NavalLedgerRow
		if row != null:
			assert_eq(String(row.data["role"]), NavalLedger.READING_WARSHIP)
	panel._on_filter(NavalLedger.REGION_OLD, true)
	assert_eq(panel._region, NavalLedger.REGION_OLD)
	panel._on_filter(NavalLedger.REGION_ALL, true)
	panel._on_filter(NavalLedger.READING_ALL, false)


## The explanation a filter that empties the sheet earns: the crown may hold no
## hull yet, the filter may be hiding them, or the chart may hold none at all
## (REQ-P5-05).
func test_the_empty_view_names_why_no_hull_answers() -> void:
	var panel: NavalLedgerPanel = screen.hud.navy_ledger
	panel.bind(screen.play)
	# A chart the crown floats nothing in: the whole navy answers, this chart does not.
	panel._snapshot = NavalLedger.snapshot(_world(), _old_only(), OWNER)
	panel._region = NavalLedger.REGION_NEW
	panel._apply_filter()
	assert_true(panel._empty.visible, "an empty chart prints the empty line")
	assert_true(panel._empty.text.contains("No hull answers this view"))
	assert_true(panel._subtitle.text.contains("0 of 0 hulls"), "the count line stays honest")
	# Nothing afloat but a yard slip: the sheet names the yard rather than a gap.
	var slip := FleetState.empty_in_port(7, OWNER, 0)
	var table := MapRegionTable.new()
	table.set_region(FactionCatalog.OLD_WORLD, [slip])
	panel._snapshot = NavalLedger.snapshot(_world(), table, OWNER)
	panel._region = NavalLedger.REGION_ALL
	panel._apply_filter()
	assert_true(panel._empty.text.contains("the yard launches the first"))
	# No squadron at all: clearing a filter is the way back.
	panel._snapshot = NavalLedger.snapshot(_world(), MapRegionTable.new(), OWNER)
	panel._apply_filter()
	assert_true(panel._empty.text.contains("Clear a filter"))
	panel._snapshot = {}
	panel._region = NavalLedger.REGION_ALL
	panel._reading = NavalLedger.READING_ALL


func test_every_chip_names_its_own_reading() -> void:
	var panel: NavalLedgerPanel = screen.hud.navy_ledger
	var chart_row := panel._bar.get_child(0) as HBoxContainer
	var reading_row := panel._bar.get_child(1) as HBoxContainer
	assert_eq(_chip_captions(chart_row), ["Both charts", "Old World", "New World"])
	assert_eq(_chip_captions(reading_row), ["All hulls", "Warships", "Merchant hulls"])


func test_back_and_the_key_close_the_ledger() -> void:
	var panel: NavalLedgerPanel = screen.hud.navy_ledger
	screen.hud.navy_pressed.emit()
	assert_true(panel.is_open())
	assert_true(BackRequest.handle(screen.play, screen.play.improvements))
	assert_false(panel.is_open(), "back sets the ledger aside first")
	InputActions.ensure_actions()
	var toggle := InputEventAction.new()
	toggle.action = InputActions.NAVY_LEDGER
	toggle.pressed = true
	panel._unhandled_input(toggle)
	assert_true(panel.is_open(), "the key opens it from the map")
	panel._unhandled_input(toggle)
	assert_false(panel.is_open(), "and closes it again")


## A hull has no marker of her own: Visit frames the squadron that flies her and
## leaves the sheet, so the map a tap would have shown is the one under it.
func test_a_visit_frames_her_squadron_and_sets_the_sheet_aside() -> void:
	var panel: NavalLedgerPanel = screen.hud.navy_ledger
	panel.open()
	assert_true(panel.is_open())
	var row: NavalLedgerRow = _first_row(panel)
	assert_not_null(row, "the campaign floats a hull")
	if row == null:
		return
	row._on_visit()
	assert_false(panel.is_open(), "the sheet sets itself aside")
	assert_not_null(screen.play.ship_layer.selected(), "her squadron is the selection")


# --- fixtures ---------------------------------------------------------------


## Two charts of the naval fixture. The crown keeps a patrolling home squadron
## (frigate + carrack) in Cádiz and a lone trader at sea in the New World; the
## rival's squadron must never reach the reading.
func _world() -> WorldMap:
	var old: MapModel = Naval.build()
	var new: MapModel = Naval.build()
	new.region_id = FactionCatalog.NEW_WORLD
	var map := WorldMap.new()
	map.add_region(old)
	map.add_region(new)
	return map


func _regions() -> MapRegionTable:
	var table := MapRegionTable.new()
	table.set_region(FactionCatalog.OLD_WORLD, [_home_fleet(), _rival_fleet()])
	table.set_region(FactionCatalog.NEW_WORLD, [_trader_fleet()])
	return table


## The home chart alone: the New World holds no hull, so a one-chart view has an
## empty page and the whole navy still answers.
func _old_only() -> MapRegionTable:
	var table := MapRegionTable.new()
	table.set_region(FactionCatalog.OLD_WORLD, [_home_fleet()])
	return table


func _home_fleet() -> FleetState:
	var fleet := FleetState.in_port(1, OWNER, 0, ["ship_1", "ship_2"], {
		"ship_1": "carrack", "ship_2": "frigate",
	})
	fleet.mission = FleetState.Mission.PATROL
	return fleet


func _trader_fleet() -> FleetState:
	return FleetState.at_sea(2, OWNER, 0, ["ship_3"], {"ship_3": "trader"})


func _rival_fleet() -> FleetState:
	return FleetState.in_port(9, RIVAL, 1, ["ship_9"], {"ship_9": "frigate"})


func _row_of(data: Dictionary, hull_id: String) -> Dictionary:
	for raw: Variant in data["rows"]:
		var row: Dictionary = raw
		if String(row["hull"]) == hull_id:
			return row
	return {}


## The muster roll's navy door, found by its word so the suite reads the button
## the player presses.
func _navy_door() -> Button:
	for node: Node in screen.hud.muster_roll.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text.begins_with("The crown's navy"):
			return button
	return null


func _first_row(panel: NavalLedgerPanel) -> NavalLedgerRow:
	for child: Node in panel._rows.get_children():
		var row := child as NavalLedgerRow
		if row != null:
			return row
	return null


func _row_widgets(panel: NavalLedgerPanel) -> int:
	var total: int = 0
	for child: Node in panel._rows.get_children():
		if child is NavalLedgerRow:
			total += 1
	return total


func _chip_captions(row: HBoxContainer) -> Array[String]:
	var captions: Array[String] = []
	for child: Node in row.get_children():
		var chip := child as Button
		if chip != null:
			captions.append(chip.text)
	return captions


func _has_text(root: Node, needle: String) -> bool:
	for node: Node in root.find_children("*", "Label", true, false):
		var label := node as Label
		if label != null and label.text.contains(needle):
			return true
	return false
