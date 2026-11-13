extends GdToolsTest
## The muster roll: the whole-empire force ledger projects every own army and
## squadron in both charts (wiki: military-armies § The muster roll;
## DR-20261113-12) and the panel drives it — seal, key, filters and Visit.
## One Godot boot: the projection suite reads small fixtures, the drive mounts
## the shared map screen (docs/testing.md).

const Naval = preload("res://tests/naval_fixture.gd")
const Fixture = preload("res://tests/map_fixture.gd")

var screen: MapScreen = null


func before_all() -> void:
	screen = Fixture.attach_screen(self)


func after_all() -> void:
	if is_instance_valid(screen):
		screen.hud.muster_roll.close()
		screen.free()
	screen = null


func before_each() -> void:
	if screen == null or not is_instance_valid(screen):
		screen = Fixture.attach_screen(self)
		return
	screen.hud.muster_roll.close()


# --- projection -------------------------------------------------------------


func test_snapshot_lists_every_own_force_in_both_regions() -> void:
	var snapshot: Dictionary = ForceLedger.snapshot(_world(), _armies(), _fleets(), 0)
	assert_eq(int(snapshot["total"]), 5, "three armies and two squadrons of the crown")
	assert_eq(int(snapshot["by_kind"][ForceLedger.KIND_ARMY]), 3, "the rival colours stay out")
	assert_eq(int(snapshot["by_kind"][ForceLedger.KIND_SQUADRON]), 2, "the rival hulls stay out")
	assert_eq((snapshot["groups"] as Array).size(), 2, "one heading per chart")
	assert_eq(ForceLedger.count(snapshot, ForceLedger.REGION_OLD), 3)
	assert_eq(ForceLedger.count(snapshot, ForceLedger.REGION_NEW), 2)
	var counts: Dictionary = ForceLedger.kind_counts(snapshot, ForceLedger.REGION_OLD)
	assert_eq(int(counts[ForceLedger.KIND_ARMY]), 2)
	assert_eq(int(counts[ForceLedger.KIND_SQUADRON]), 1)


func test_region_and_kind_filters_narrow_the_ledger() -> void:
	var snapshot: Dictionary = ForceLedger.snapshot(_world(), _armies(), _fleets(), 0)
	assert_eq(ForceLedger.count(snapshot, ForceLedger.REGION_OLD, ForceLedger.KIND_ARMY), 2)
	assert_eq(ForceLedger.count(snapshot, ForceLedger.REGION_OLD, ForceLedger.KIND_SQUADRON), 1)
	assert_eq(ForceLedger.count(snapshot, ForceLedger.REGION_NEW, ForceLedger.KIND_ARMY), 1)
	assert_eq(ForceLedger.count(snapshot, ForceLedger.REGION_NEW, ForceLedger.KIND_SQUADRON), 1)
	for group: Dictionary in ForceLedger.groups(snapshot, ForceLedger.REGION_NEW):
		assert_eq(int(group["region"]), FactionCatalog.NEW_WORLD)
		for raw: Variant in group["rows"]:
			assert_ne(String((raw as Dictionary)["kind"]), "", "every row names its kind")


func test_army_row_reads_standing_composition_and_strength() -> void:
	var snapshot: Dictionary = ForceLedger.snapshot(_world(), _armies(), _fleets(), 0)
	var home: Dictionary = _row(snapshot, ForceLedger.KIND_ARMY, 1)
	assert_eq(String(home["title"]), "Home Army")
	assert_eq(String(home["place"]), "Cádiz")
	assert_eq(int(home["region"]), FactionCatalog.OLD_WORLD)
	assert_true(String(home["line"]).contains("2 regiments"))
	var army: ArmyState = _army_of(_armies(), 1)
	var one: Array[ArmyState] = [army]
	assert_almost_eq(float(home["strength"]), ArmyForce.side_strength(one), 0.001)
	assert_true(String(home["state"]).contains("seat"), "the Home Army never marches")
	assert_true(String(home["line"]).contains("%.1f strength" % float(home["strength"])))


func test_embarked_army_reads_aboard_its_squadron() -> void:
	var snapshot: Dictionary = ForceLedger.snapshot(_world(), _armies(), _fleets(), 0)
	var embarked: Dictionary = _row(snapshot, ForceLedger.KIND_ARMY, 2)
	assert_true(String(embarked["place"]).contains("Aboard a squadron"))
	assert_true(String(embarked["place"]).contains("Cádiz"), "the carrying squadron's station")
	assert_true(String(embarked["state"]).contains("Embarked"))


func test_squadron_row_reads_port_sea_station_and_cargo() -> void:
	var snapshot: Dictionary = ForceLedger.snapshot(_world(), _armies(), _fleets(), 0)
	var in_port: Dictionary = _row(snapshot, ForceLedger.KIND_SQUADRON, 7)
	assert_true(String(in_port["title"]).begins_with("Squadron"))
	assert_eq(String(in_port["place"]), "In port at Cádiz")
	assert_true(String(in_port["line"]).contains("2 hulls"))
	assert_true(String(in_port["line"]).contains("6 holds"), "two carracks carry three apiece")
	assert_true(String(in_port["state"]).contains("carrying an army"))
	var afloat: Dictionary = _row(snapshot, ForceLedger.KIND_SQUADRON, 9)
	assert_eq(String(afloat["place"]), "At sea — Mar Caribe")
	assert_true(String(afloat["state"]).contains("Patrol"))
	assert_eq(int(afloat["region"]), FactionCatalog.NEW_WORLD)


func test_kind_labels_and_flagship_title() -> void:
	assert_eq(ForceLedger.kind_label(ForceLedger.KIND_ARMY), "army")
	assert_eq(ForceLedger.kind_label(ForceLedger.KIND_ARMY, true), "armies")
	assert_eq(ForceLedger.kind_label(ForceLedger.KIND_SQUADRON), "squadron")
	assert_eq(ForceLedger.kind_label(ForceLedger.KIND_SQUADRON, true), "squadrons")
	var fleets: MapRegionTable = _fleets()
	var fleet: FleetState = (fleets.value(FactionCatalog.OLD_WORLD, []) as Array)[0]
	fleet.hull_names = {"ship_1": "Trinidad"}
	var snapshot: Dictionary = ForceLedger.snapshot(_world(), _armies(), fleets, 0)
	assert_eq(
		String(_row(snapshot, ForceLedger.KIND_SQUADRON, 7)["title"]),
		"Squadron — Trinidad",
		"a squadron reads by the flagship it flies"
	)


func test_empty_or_missing_rosters_project_an_empty_ledger() -> void:
	var snapshot: Dictionary = ForceLedger.snapshot(null, null, null, 0)
	assert_eq(int(snapshot["total"]), 0)
	assert_true((snapshot["groups"] as Array).is_empty())
	assert_eq(ForceLedger.count(snapshot, ForceLedger.REGION_ALL), 0)
	var empty_world: WorldMap = WorldMap.new()
	assert_eq(int(ForceLedger.snapshot(empty_world, null, null, 0)["total"]), 0)


# --- the panel on the live map ----------------------------------------------


func test_muster_seal_key_and_keyboard_action_open_the_ledger() -> void:
	InputActions.ensure_actions()
	assert_true(InputMap.has_action(InputActions.MUSTER_ROLL))
	assert_ne(InputActions.MUSTER_ROLL, InputActions.CIVILIAN_ROSTER)
	assert_not_null(_seal_with_caption(screen.hud, "MUSTER"), "the cartouche carries the seal")
	var panel: ForceLedgerPanel = screen.hud.muster_roll
	assert_not_null(panel)
	screen.hud.muster_roll_pressed.emit()
	assert_true(panel.is_open())
	assert_true(int(panel._snapshot.get("total", 0)) > 0, "the crown holds forces on the chart")
	screen.hud.muster_roll_pressed.emit()
	assert_false(panel.is_open())


func test_ledger_kind_filter_and_visit_open_the_chosen_force() -> void:
	var panel: ForceLedgerPanel = screen.hud.muster_roll
	screen.hud.muster_roll_pressed.emit()
	panel._on_filter(ForceLedger.KIND_ARMY, false)
	assert_eq(panel._kind, ForceLedger.KIND_ARMY)
	var shown: int = ForceLedger.count(
		panel._snapshot, ForceLedger.REGION_ALL, ForceLedger.KIND_ARMY
	)
	assert_true(
		String(panel._subtitle.text).begins_with("Showing %d of" % shown),
		"the subtitle counts the narrowed view"
	)
	var rows: Array[Dictionary] = _rows_of_kind(panel._snapshot, ForceLedger.KIND_ARMY)
	assert_true(rows.size() > 0)
	assert_true(_row_widgets(panel) > 0, "the ledger printed rows")
	var first: Dictionary = rows[0]
	panel._visit(int(first["region"]), String(first["kind"]), int(first["id"]))
	assert_false(panel.is_open(), "Visit sets the ledger aside")
	assert_true(_selected_force(screen.play), "the force under the camera is the crown's own")


func test_region_filter_with_no_force_says_so() -> void:
	var panel: ForceLedgerPanel = screen.hud.muster_roll
	screen.hud.muster_roll_pressed.emit()
	panel._on_filter(ForceLedger.REGION_OLD, true)
	panel._on_filter(ForceLedger.KIND_SQUADRON, false)
	panel._apply_filter()
	var shown: int = ForceLedger.count(panel._snapshot, panel._region, panel._kind)
	assert_eq(panel._empty.visible, shown == 0)
	if shown == 0:
		assert_true(String(panel._empty.text).contains("No force"))


func test_visit_a_squadron_selects_her_and_missing_ids_do_not() -> void:
	var panel: ForceLedgerPanel = screen.hud.muster_roll
	screen.hud.muster_roll_pressed.emit()
	var rows: Array[Dictionary] = _rows_of_kind(panel._snapshot, ForceLedger.KIND_SQUADRON)
	assert_true(rows.size() > 0, "the crown keeps a squadron afloat")
	var fleet: Dictionary = rows[0]
	assert_true(
		MapPlayForceLedger.focus(
			screen.play, int(fleet["region"]), ForceLedger.KIND_SQUADRON, int(fleet["id"])
		),
		"a squadron can be visited"
	)
	assert_not_null(screen.play.ship_layer.selected())
	assert_false(MapPlayForceLedger.focus(screen.play, 0, ForceLedger.KIND_ARMY, -999))
	assert_false(MapPlayForceLedger.focus(screen.play, 0, ForceLedger.KIND_SQUADRON, -999))
	assert_false(MapPlayForceLedger.focus(null, 0, ForceLedger.KIND_ARMY, 0))


func test_an_embarked_army_visits_the_squadron_that_carries_it() -> void:
	var panel: ForceLedgerPanel = screen.hud.muster_roll
	screen.hud.muster_roll_pressed.emit()
	var marker: Ship = null
	for ship: Ship in screen.play.ship_layer.ships:
		if ship.faction == screen.play.player_faction:
			marker = ship
			break
	assert_not_null(marker, "the crown has a squadron in this region")
	var army: ArmyState = null
	for candidate: ArmyState in screen.play.army_layer.armies:
		if candidate.owner == screen.play.player_faction:
			army = candidate
			break
	assert_not_null(army, "the crown has an army in this region")
	army.embarked_fleet = marker.fleet_id
	assert_true(
		MapPlayForceLedger.focus(
			screen.play, screen.play.region_index, ForceLedger.KIND_ARMY, army.id
		),
		"an embarked standard is reached through its hulls"
	)
	assert_eq(screen.play.ship_layer.selected(), marker, "the carrying squadron is selected")
	army.embarked_fleet = MapModel.NO_ID


func test_back_closes_the_muster_roll_before_the_dossiers() -> void:
	var panel: ForceLedgerPanel = screen.hud.muster_roll
	screen.hud.muster_roll_pressed.emit()
	assert_true(panel.is_open())
	assert_true(BackRequest.handle(screen.play, screen.play.improvements))
	assert_false(panel.is_open(), "back sets the ledger aside first")
	var escaped := InputEventAction.new()
	escaped.action = InputActions.CANCEL
	escaped.pressed = true
	screen.hud.muster_roll_pressed.emit()
	panel._input(escaped)
	assert_false(panel.is_open(), "Escape closes the ledger")


func test_the_rows_own_tap_visits_its_force() -> void:
	var panel: ForceLedgerPanel = screen.hud.muster_roll
	screen.hud.muster_roll_pressed.emit()
	var row: ForceLedgerRow = null
	for child: Node in panel._rows.get_children():
		if child is ForceLedgerRow:
			row = child
			break
	assert_not_null(row)
	var tap := InputEventMouseButton.new()
	tap.pressed = true
	tap.button_index = MOUSE_BUTTON_LEFT
	row._gui_input(tap)
	assert_false(panel.is_open(), "a tap on the row visits the force")


func test_the_keyboard_action_toggles_from_the_map() -> void:
	InputActions.ensure_actions()
	var panel: ForceLedgerPanel = screen.hud.muster_roll
	var toggle := InputEventAction.new()
	toggle.action = InputActions.MUSTER_ROLL
	toggle.pressed = true
	panel._unhandled_input(toggle)
	assert_true(panel.is_open())
	panel._unhandled_input(toggle)
	assert_false(panel.is_open())


# --- fixtures ---------------------------------------------------------------


func _world() -> WorldMap:
	var old: MapModel = Naval.build()
	var new: MapModel = Naval.build()
	new.region_id = FactionCatalog.NEW_WORLD
	new.provinces[0].name = "Veracruz"
	var world := WorldMap.new()
	world.add_region(old)
	world.add_region(new)
	return world


func _armies() -> MapRegionTable:
	var table := MapRegionTable.new()
	var old: Array[ArmyState] = []
	old.append(ArmyState.muster(1, 0, 0, true, ["pikemen", "arquebusiers"]))
	var embarked: ArmyState = ArmyState.muster(2, 0, MapModel.NO_ID, false, ["pikemen"])
	embarked.embarked_fleet = 7
	old.append(embarked)
	old.append(ArmyState.muster(3, 1, 0, false, ["pikemen"]))
	table.set_region(FactionCatalog.OLD_WORLD, old)
	var new: Array[ArmyState] = []
	new.append(ArmyState.muster(4, 0, 0, false, ["arquebusiers", "pikemen"]))
	table.set_region(FactionCatalog.NEW_WORLD, new)
	return table


func _fleets() -> MapRegionTable:
	var table := MapRegionTable.new()
	var old: Array[FleetState] = []
	var moored: FleetState = FleetState.in_port(7, 0, 0)
	moored.set_hulls(["ship_1", "ship_2"])
	moored.embarked_army = 2
	old.append(moored)
	var rival: FleetState = FleetState.in_port(8, 1, 1)
	rival.set_hulls(["ship_3"])
	old.append(rival)
	table.set_region(FactionCatalog.OLD_WORLD, old)
	var new: Array[FleetState] = []
	var patrol: FleetState = FleetState.at_sea(9, 0, 0)
	patrol.set_hulls(["ship_4"])
	patrol.mission = FleetState.Mission.PATROL
	new.append(patrol)
	table.set_region(FactionCatalog.NEW_WORLD, new)
	return table


func _army_of(table: MapRegionTable, id: int) -> ArmyState:
	for raw: Variant in table.value(FactionCatalog.OLD_WORLD, []):
		var army := raw as ArmyState
		if army != null and army.id == id:
			return army
	return null


func _row(snapshot: Dictionary, kind: String, id: int) -> Dictionary:
	for raw: Variant in snapshot["rows"]:
		var row: Dictionary = raw
		if String(row["kind"]) == kind and int(row["id"]) == id:
			return row
	return {}


func _rows_of_kind(snapshot: Dictionary, kind: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for raw: Variant in snapshot["rows"]:
		var row: Dictionary = raw
		if String(row["kind"]) == kind:
			rows.append(row)
	return rows


func _row_widgets(panel: ForceLedgerPanel) -> int:
	var total: int = 0
	for child: Node in panel._rows.get_children():
		if child is ForceLedgerRow:
			total += 1
	return total


func _seal_with_caption(node: Node, caption: String) -> Button:
	var button := node as Button
	if button != null and _labels_carry(button, caption):
		return button
	for child: Node in node.get_children():
		var found: Button = _seal_with_caption(child, caption)
		if found != null:
			return found
	return null


func _labels_carry(node: Node, caption: String) -> bool:
	var label := node as Label
	if label != null:
		return label.text == caption
	for child: Node in node.get_children():
		if _labels_carry(child, caption):
			return true
	return false


func _selected_force(play: PlaySession) -> bool:
	if play.army_layer != null and play.army_layer.selected_army != null:
		return true
	return play.ship_layer != null and play.ship_layer.selected() != null
