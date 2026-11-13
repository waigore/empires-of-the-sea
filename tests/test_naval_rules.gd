# gdlint: disable=max-public-methods
extends GdToolsTest
## The sea in one suite: the yard, hull names and rosters, station orders, sortie,
## strength aggregation, retreat, a lost port, interception, movement and raids
## (wiki: ships-and-naval).

## Merged from test_fleet_yard, test_fleet_yard_block, test_fleet_names,
## test_fleet_rosters, test_fleet_sortie, test_fleet_missions, test_naval_strength,
## test_naval_retreat, test_naval_port_loss, test_naval_interception,
## test_naval_movement, test_naval_raid.
## One Godot boot (coverage instrumentation) per theme instead of one per file.
## Each test runs only its own suite's setup; teardown follows the setup.
const fleet_names_Fixture = preload("res://tests/map_fixture.gd")
const fleet_rosters_Fixture = preload("res://tests/map_fixture.gd")
const fleet_sortie_NavalFixture = preload("res://tests/naval_fixture.gd")
const fleet_missions_NavalFixture = preload("res://tests/naval_fixture.gd")
const naval_retreat_NavalFixture = preload("res://tests/naval_fixture.gd")
const naval_port_loss_Fixture = preload("res://tests/naval_fixture.gd")
const naval_interception_NavalFixture = preload("res://tests/naval_fixture.gd")

const FACTIONS: Array[String] = ["España", "England", "France", "Portugal"]
const SEAT: int = 0
const HARBOUR: int = 1

var _econ: PlayerEconomy
var _fleet_names_econ: PlayerEconomy
var _markers: ShipMarkers = null
var _fleet_sortie_model: MapModel = null
var _fleet_missions_model: MapModel = null
var _naval_retreat_model: MapModel = null
var _naval_interception_model: MapModel = null

var _suite_setup: String = ""

func after_each() -> void:
	match _suite_setup:
		"fleet_rosters":
			_teardown_fleet_rosters()
	_suite_setup = ""

func _setup_fleet_yard() -> void:
	_suite_setup = "fleet_yard"
	_econ = PlayerEconomy.starting()
	_econ.treasury = 60000

func _setup_fleet_names() -> void:
	_suite_setup = "fleet_names"
	_fleet_names_econ = PlayerEconomy.starting()
	_fleet_names_econ.treasury = 60000

func _setup_fleet_rosters() -> void:
	_suite_setup = "fleet_rosters"
	_markers = ShipMarkers.new()
	_markers.model = fleet_rosters_Fixture.region()

func _setup_fleet_sortie() -> void:
	_suite_setup = "fleet_sortie"
	_fleet_sortie_model = fleet_sortie_NavalFixture.build()

func _setup_fleet_missions() -> void:
	_suite_setup = "fleet_missions"
	_fleet_missions_model = fleet_missions_NavalFixture.build()

func _setup_naval_retreat() -> void:
	_suite_setup = "naval_retreat"
	_naval_retreat_model = naval_retreat_NavalFixture.build()

func _setup_naval_interception() -> void:
	_suite_setup = "naval_interception"
	_naval_interception_model = naval_interception_NavalFixture.build()

func _teardown_fleet_rosters() -> void:
	_markers.clear()
	_markers = null

# --- test_fleet_yard ---

func test_launch_pays_the_row_and_one_peasant() -> void:
	_setup_fleet_yard()
	var fleet := FleetState.empty_in_port(7, 0, 1)
	var treasury: int = _econ.treasury
	var peasants: int = _econ.available_peasants()
	var lumber: int = _econ.quantity("lumber")
	var fabric: int = _econ.quantity("fabric")

	var result: Dictionary = FleetYard.launch(_econ, fleet, "carrack", "ship_9")

	assert_true(bool(result["ok"]), String(result["reason"]))
	assert_eq(fleet.hulls, ["ship_9"])
	assert_eq(fleet.type_of("ship_9"), "carrack")
	assert_eq(_econ.treasury, treasury - ShipEconomy.treasury_cost("carrack"))
	assert_eq(_econ.available_peasants(), peasants - 1)
	assert_eq(_econ.quantity("lumber"), lumber - 2)
	assert_eq(_econ.quantity("fabric"), fabric - 1)

func test_a_locked_hull_names_its_tech_and_spends_nothing() -> void:
	_setup_fleet_yard()
	var fleet := FleetState.empty_in_port(7, 0, 1)
	var treasury: int = _econ.treasury
	var peasants: int = _econ.available_peasants()

	var result: Dictionary = FleetYard.launch(_econ, fleet, "frigate", "ship_9")

	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("Requires"))
	assert_true(String(result["reason"]).contains("Advanced Hull Design"))
	assert_eq(fleet.ship_count(), 0)
	assert_eq(_econ.treasury, treasury)
	assert_eq(_econ.available_peasants(), peasants)

func test_research_unlocks_the_hull() -> void:
	_setup_fleet_yard()
	var fleet := FleetState.empty_in_port(7, 0, 1)
	_econ.tech_unlocked["advanced_hull_design"] = true

	var result: Dictionary = FleetYard.launch(_econ, fleet, "frigate", "ship_9")

	assert_true(bool(result["ok"]), String(result["reason"]))
	assert_eq(fleet.type_of("ship_9"), "frigate")

func test_no_peasant_refuses_the_launch_and_spends_nothing() -> void:
	_setup_fleet_yard()
	var fleet := FleetState.empty_in_port(7, 0, 1)
	_econ.workers.set_count(WorkerPool.Tier.PEASANT, 0)
	var treasury: int = _econ.treasury

	var result: Dictionary = FleetYard.launch(_econ, fleet, "carrack", "ship_9")

	assert_false(bool(result["ok"]))
	assert_eq(String(result["reason"]), "Insufficient workers")
	assert_eq(fleet.ship_count(), 0)
	assert_eq(_econ.treasury, treasury)

func test_insufficient_materials_refuse_the_launch() -> void:
	_setup_fleet_yard()
	var fleet := FleetState.empty_in_port(7, 0, 1)
	_econ.stockpile["lumber"] = 1

	var result: Dictionary = FleetYard.launch(_econ, fleet, "carrack", "ship_9")

	assert_false(bool(result["ok"]))
	assert_eq(String(result["reason"]), "Insufficient materials")
	assert_eq(fleet.ship_count(), 0)

func test_the_breaker_yard_returns_one_peasant() -> void:
	_setup_fleet_yard()
	var fleet := FleetState.at_sea(3, 0, 2, ["ship_1", "ship_2"], {"ship_2": "sloop"})
	var peasants: int = _econ.available_peasants()

	var result: Dictionary = FleetYard.scrap(_econ, fleet, "ship_2")

	assert_true(bool(result["ok"]), String(result["reason"]))
	assert_eq(fleet.hulls, ["ship_1"])
	assert_eq(_econ.available_peasants(), peasants + 1)
	assert_false(bool(result["retired"]))
	assert_eq(_econ.treasury, 60000, "no treasury is refunded")

func test_breaking_up_the_last_hull_retires_the_squadron() -> void:
	_setup_fleet_yard()
	var fleet := FleetState.at_sea(3, 0, 2, ["ship_1"])

	var result: Dictionary = FleetYard.scrap(_econ, fleet, "ship_1")

	assert_true(bool(result["ok"]))
	assert_true(bool(result["retired"]))
	assert_false(fleet.is_afloat())

func test_a_hull_must_belong_to_the_fleet() -> void:
	_setup_fleet_yard()
	var fleet := FleetState.at_sea(3, 0, 2, ["ship_1"])

	var result: Dictionary = FleetYard.scrap(_econ, fleet, "ship_99")

	assert_false(bool(result["ok"]))
	assert_eq(fleet.hulls, ["ship_1"])

func test_rows_lead_with_payable_hulls_and_reason_the_locked_ones() -> void:
	_setup_fleet_yard()
	var rows: Array[Dictionary] = FleetYard.rows(_econ, true)

	assert_eq(rows.size(), ShipEconomy.ENTRIES.size())
	assert_true(bool(rows[0]["ok"]), "a payable row leads the yard")
	var locked: int = 0
	for row: Dictionary in rows:
		if not bool(row["ok"]):
			locked += 1
			assert_false(String(row["reason"]).is_empty())
	assert_gt(locked, 0, "era hulls stay locked without research")

func test_an_absent_home_port_blocks_every_row() -> void:
	_setup_fleet_yard()
	var rows: Array[Dictionary] = FleetYard.rows(_econ, false)

	for row: Dictionary in rows:
		assert_false(bool(row["ok"]))
		assert_eq(String(row["reason"]), "Launch hulls at your capital port.")

func test_every_hull_names_a_real_tech_or_none() -> void:
	_setup_fleet_yard()
	for type_id: String in ShipEconomy.ENTRIES.keys():
		var tech: String = ShipEconomy.tech_for(type_id)
		if type_id == "carrack":
			assert_eq(tech, "", "the carrack never needs research")
			continue
		assert_false(tech.is_empty(), type_id)
		assert_true(TechCatalog.known(tech), tech)

func test_cost_text_reads_as_a_yard_ledger() -> void:
	_setup_fleet_yard()
	var text: String = ShipEconomy.cost_text("carrack")

	assert_true(text.contains("8,000 ducats"))
	assert_true(text.contains("2 Lumber"))
	assert_true(text.contains("1 Fabric"))
	assert_true(text.contains("1 worker"))

func test_hull_firepower_sums_into_ship_strength() -> void:
	_setup_fleet_yard()
	var fleet := FleetState.at_sea(3, 0, 2, ["ship_1", "ship_2"], {"ship_2": "sloop"})

	assert_eq(ShipStats.firepower("carrack"), 2)
	assert_eq(ShipStats.firepower("sloop"), 2)
	# The dossier's strength is the resolver's weighted figure, never Σ FRP: a
	# carrack is 2.75 and a sloop 3.25 (wiki: § Naval Strength Aggregation).
	assert_almost_eq(NavalStrength.strength(fleet), 6.0, 0.0001)
	assert_almost_eq(NavalStrength.strength(null), 0.0, 0.0001)
	assert_almost_eq(NavalCombat.side_strength([fleet]), 6.0, 0.0001)

# --- test_fleet_yard_block ---

func _rows() -> Array[Dictionary]:
	return [
		{
			"type_id": "carrack",
			"name": "Carrack",
			"cost_text": "8000",
			"ok": true,
			"reason": "",
		},
		{
			"type_id": "frigate",
			"name": "Frigate",
			"cost_text": "",
			"ok": false,
			"reason": "no peasants",
		},
	]

func _buttons(block: FleetYardBlock, prefix: String) -> Array[String]:
	var out: Array[String] = []
	for node: Node in block.find_children("*", "Button", true, false):
		var text: String = (node as Button).text
		if text.begins_with(prefix):
			out.append(text)
	return out

func test_the_slip_lists_launches_and_opens_at_once() -> void:
	var block := FleetYardBlock.new()
	add_child(block)

	block.show_slip(_rows(), true)

	assert_true(block._button.visible, "a player with rows gets the yard")
	assert_true(block._open, "the capital slip opens the drawer")
	assert_eq(block._button.text, "Close shipyard")
	assert_eq(_buttons(block, "Launch"), ["Launch", "Launch"])
	block.free()

func test_a_foreign_yard_shows_nothing() -> void:
	var block := FleetYardBlock.new()
	add_child(block)

	block.show_slip(_rows(), false)

	assert_false(block._button.visible, "no orders for another crown")
	assert_false(block._scroll.visible)
	block.free()

func test_a_join_hides_the_yard_and_keeps_the_rows() -> void:
	var block := FleetYardBlock.new()
	add_child(block)
	var fleet := FleetState.in_port(3, 1, 4, ["ship_1"], {})
	block.show_rows(fleet, _rows(), true, true)
	assert_true(block._open, "the fleet opens on the yard")
	block.set_offer_join(true)

	assert_false(block._button.visible, "the join takes the yard's place")
	assert_false(block._scroll.visible, "a hidden drawer takes no height")
	assert_eq(block._rows.size(), 2, "the rows stay for when the join is passed")
	block.free()

func test_a_scrap_asks_once_then_emits() -> void:
	var block := FleetYardBlock.new()
	add_child(block)
	var fleet := FleetState.in_port(3, 1, 4, ["ship_1"], {})
	var emitted: Array[String] = []
	block.action_pressed.connect(func(action: String) -> void: emitted.append(action))
	block.show_rows(fleet, _rows(), true, true)

	block.on_scrap_pressed("ship_1")

	assert_eq(block._armed_hull, "ship_1", "the first tap arms")
	assert_eq(emitted, [] as Array[String], "arming sends nothing")

	block.on_scrap_pressed("ship_1")

	assert_eq(emitted, ["yard:scrap:ship_1"])
	assert_eq(block._armed_hull, "", "a confirmed scrap clears the arm")
	block.free()

# --- test_fleet_names ---

func test_a_launch_christens_the_hull_from_its_crown() -> void:
	_setup_fleet_names()
	var fleet := FleetState.empty_in_port(3, 0, 1)

	var result: Dictionary = FleetYard.launch(_fleet_names_econ, fleet, "carrack", "ship_1")

	assert_true(bool(result["ok"]), String(result["reason"]))
	var name: String = String(result["name"])
	assert_true(
		ShipNames.pool_for(0).has(name),
		"Spain christens from its own pool, got '%s'" % name
	)
	assert_eq(ShipNames.of(fleet, "ship_1"), name, "the name is kept on the hull")

func test_the_same_crown_squadron_and_hull_always_name_alike() -> void:
	_setup_fleet_names()
	var first := FleetState.empty_in_port(3, 0, 1)
	var second := FleetState.empty_in_port(3, 0, 1)

	first.add_hull("ship_7", "carrack")
	second.add_hull("ship_7", "carrack")

	assert_eq(ShipNames.of(first, "ship_7"), ShipNames.of(second, "ship_7"))
	assert_true(
		ShipNames.pool_for(0).has(ShipNames.of(first, "ship_7")),
		"a reloaded fleet speaks the same name"
	)

func test_a_squadron_never_flies_the_same_name_twice() -> void:
	_setup_fleet_names()
	var fleet := FleetState.empty_in_port(3, 0, 1)
	for index in range(14):
		fleet.add_hull("ship_%d" % index, "carrack")

	var names: Array[String] = []
	var numbered: bool = false
	for hull_id: String in fleet.hulls:
		var name: String = ShipNames.of(fleet, hull_id)
		assert_false(name.is_empty())
		assert_false(names.has(name), "'%s' flies twice" % name)
		if name.ends_with(" II"):
			numbered = true
		names.append(name)
	assert_eq(names.size(), fleet.ship_count())
	# Past the ten-name pool the repeats are numbered, never duplicated.
	assert_true(numbered, "a repeat is numbered, not duplicated")

func test_a_crown_with_no_pool_still_names_its_hulls() -> void:
	_setup_fleet_names()
	var fleet := FleetState.empty_in_port(2, 9, 5)
	fleet.add_hull("ship_1", "sloop")

	assert_true(ShipNames.GENERIC.has(ShipNames.of(fleet, "ship_1")))

func test_a_saved_hull_keeps_the_name_it_was_given() -> void:
	_setup_fleet_names()
	var fleet := FleetState.in_port(3, 1, 4, ["ship_2", "ship_5"], {})
	var before: Dictionary = {}
	for hull_id: String in fleet.hulls:
		before[hull_id] = ShipNames.of(fleet, hull_id)

	var restored: FleetState = FleetState.from_dict(fleet.to_dict())

	for hull_id: String in restored.hulls:
		assert_eq(ShipNames.of(restored, hull_id), String(before[hull_id]))
	assert_eq(restored.to_dict()["hull_names"], fleet.to_dict()["hull_names"])

func test_a_hull_saved_before_names_existed_is_christened_on_load() -> void:
	_setup_fleet_names()
	var fleet := FleetState.in_port(3, 1, 4, ["ship_2", "ship_5"], {})
	var legacy: Dictionary = fleet.to_dict()
	legacy.erase("hull_names")

	var restored: FleetState = FleetState.from_dict(legacy)

	assert_eq(restored.ship_count(), 2)
	for hull_id: String in restored.hulls:
		assert_eq(
			ShipNames.of(restored, hull_id),
			ShipNames.of(fleet, hull_id),
			"the load speaks the name the hull would have flown"
		)

func test_a_merge_keeps_every_hull_name() -> void:
	_setup_fleet_names()
	var home := FleetState.in_port(3, 1, 4, ["ship_1"], {})
	var returning := FleetState.at_sea(5, 1, 2, ["ship_4"], {})
	var expected: String = ShipNames.of(returning, "ship_4")
	var home_name: String = ShipNames.of(home, "ship_1")

	home.merge_from(returning)

	assert_eq(ShipNames.of(home, "ship_4"), expected)
	assert_eq(ShipNames.of(home, "ship_1"), home_name)

func test_scrapping_names_the_hull_it_breaks() -> void:
	_setup_fleet_names()
	var fleet := FleetState.in_port(3, 0, 1, ["ship_1", "ship_2"], {})
	var doomed: String = ShipNames.of(fleet, "ship_2")

	var result: Dictionary = FleetYard.scrap(_fleet_names_econ, fleet, "ship_2")

	assert_true(bool(result["ok"]), String(result["reason"]))
	assert_eq(String(result["name"]), doomed)
	assert_false(fleet.hull_names.has("ship_2"), "a broken hull keeps no name")

func test_an_unnamed_hull_reads_a_name_without_a_write() -> void:
	_setup_fleet_names()
	var fleet := FleetState.in_port(3, 0, 1, [], {})
	fleet.hulls.append("ship_9")
	fleet.hull_types["ship_9"] = "carrack"

	var name: String = ShipNames.of(fleet, "ship_9")

	assert_false(name.is_empty())
	assert_false(fleet.hull_names.has("ship_9"), "a read never stores work of its own")

## The dossier's own line counts hulls in the singular when it carries one: "1
## ship", never "1 ships" (REQ-P1-07, read at a phone's size).
func test_the_dossier_counts_one_hull_in_the_singular() -> void:
	_setup_fleet_names()
	var panel := FleetPanel.new()
	add_child(panel)
	var fleet := FleetState.in_port(3, 1, 4, ["ship_1"], {})

	panel.refresh(fleet_names_Fixture.region(), fleet, true)

	var line: String = ""
	for node: Node in panel.find_children("*", "Label", true, false):
		var text: String = (node as Label).text
		if text.contains("Carrack") and text.contains("upkeep"):
			line = text
	assert_true(line.begins_with("1 ship · "), "the dossier reads '%s'" % line)

	panel.refresh(fleet_names_Fixture.region(), fleet, true, "", [], [], 1, [], "", {"count": 1})
	for node: Node in panel.find_children("*", "Label", true, false):
		var text: String = (node as Label).text
		if text.contains("carrying"):
			line = text
	assert_true(line.contains("carrying 1 regiment · 1 colonist"), "the dossier reads '%s'" % line)
	panel.free()

## The dossier names the hull, and the break-up confirmation names what it breaks
## (REQ-P1-03, REQ-P5-04).
func test_the_dossier_and_the_break_up_name_the_hull() -> void:
	_setup_fleet_names()
	var panel := FleetPanel.new()
	add_child(panel)
	var fleet := FleetState.in_port(3, 1, 4, ["ship_1"], {})
	var hull_name: String = ShipNames.of(fleet, "ship_1")
	var rows: Array[Dictionary] = [
		{
			"type_id": "carrack",
			"name": "Carrack",
			"cost_text": "8000",
			"ok": true,
			"reason": "",
		},
	]

	panel.refresh(fleet_names_Fixture.region(), fleet, true, "", rows)
	panel.set_yard_open(true)

	var printed: bool = false
	for node: Node in panel.find_children("*", "Label", true, false):
		var text: String = (node as Label).text
		if text.contains(hull_name) and text.contains("Carrack"):
			printed = true
	assert_true(printed, "the hull row prints '%s — Carrack'" % hull_name)

	var confirm: Button = null
	for node: Node in panel.find_children("*", "Button", true, false):
		if (node as Button).text == "Break up":
			confirm = node as Button
	assert_not_null(confirm, "the hull offers a break-up")
	panel._on_scrap_pressed("ship_1")
	for node: Node in panel.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text == "Confirm scrap":
			confirm = button
	assert_eq(confirm.text, "Confirm scrap", "the first tap only arms")
	assert_true(
		confirm.tooltip_text.contains(hull_name),
		"the confirmation names the hull: '%s'" % confirm.tooltip_text
	)
	panel.free()

# --- test_fleet_rosters ---

func _regions() -> MapRegionTable:
	var regions := MapRegionTable.new()
	regions.set_region(0, [
		FleetState.at_sea(0, 1, 0, ["a", "b"]), FleetState.in_port(1, 1, 2, ["c"])
	])
	regions.set_region(1, [FleetState.at_sea(4, 2, 5, ["d"])])
	return regions

func test_every_region_contributes_to_the_hull_count() -> void:
	_setup_fleet_rosters()
	var regions := _regions()
	assert_eq(FleetRosters.hulls_afloat(regions, 1), 3)
	assert_eq(FleetRosters.hulls_afloat(regions, 2), 1)
	assert_eq(FleetRosters.hulls_afloat(MapRegionTable.new(), 1), 0)

func test_next_id_avoids_ids_used_in_any_region() -> void:
	_setup_fleet_rosters()
	var regions := _regions()
	assert_eq(FleetRosters.next_id_all(regions), 5)
	assert_eq(FleetRosters.next_id_all(MapRegionTable.new()), 0)

func test_all_returns_one_typed_roster_per_region() -> void:
	_setup_fleet_rosters()
	var regions := _regions()
	var rosters: Array[Array] = FleetRosters.all(regions)
	assert_eq(rosters.size(), 2)
	assert_eq(rosters[1].size(), 1)

## A passenger's seat is read from the squadron that lists it — a sunken or
## missing squadron keeps none (wiki: ships-and-naval § Naval transport).
func test_carried_seats_come_from_the_squadron_rosters() -> void:
	_setup_fleet_rosters()
	var regions := MapRegionTable.new()
	var crowded := FleetState.at_sea(0, 1, 0, ["a", "b"])
	crowded.add_civilian(7)
	crowded.embarked_army = 11
	var sunk := FleetState.empty_in_port(3, 1, 2)
	sunk.add_civilian(8)
	sunk.embarked_army = 12
	regions.set_region(0, [crowded, null, sunk])
	var other := FleetState.in_port(4, 2, 2, ["d"])
	other.add_civilian(9)
	regions.set_region(1, [other])

	assert_eq(
		FleetRosters.carried_civilians(regions), {7: 0, 9: 4},
		"a sunk hull's passenger has no seat"
	)
	assert_eq(FleetRosters.carried_armies(regions), {11: 0})
	assert_eq(FleetRosters.carried_civilians(MapRegionTable.new()), {})

func test_removing_the_selected_marker_clears_the_selection() -> void:
	_setup_fleet_rosters()
	var fleet := FleetState.at_sea(3, 1, 0)
	var ship: Ship = _markers.make(fleet)
	_markers.selected_ship = ship
	_markers.remove(ship)
	assert_eq(_markers.ships.size(), 0)
	assert_null(_markers.selected_ship)
	assert_eq(_markers.find(3), null)

func test_clear_frees_every_marker() -> void:
	_setup_fleet_rosters()
	_markers.make(FleetState.at_sea(0, 1, 0))
	_markers.make(FleetState.in_port(1, 2, 2))
	_markers.selected_ship = _markers.ships[0]
	_markers.clear()
	assert_eq(_markers.ships.size(), 0)
	assert_null(_markers.selected_ship)

# --- test_fleet_sortie ---

func _home() -> FleetState:
	return FleetState.in_port(
		1, 0, 0, ["a", "b"], {"a": "fluyte", "b": "carrack"}
	)

func test_the_home_squadron_may_only_sail_from_its_capital() -> void:
	_setup_fleet_sortie()
	var home: FleetState = _home()
	var at_sea: FleetState = FleetState.at_sea(2, 0, 0, ["c"], {"c": "fluyte"})
	var outside: FleetState = FleetState.in_port(3, 0, 1, ["d"], {"d": "fluyte"})

	assert_true(NavalMovement.is_home_fleet(_fleet_sortie_model, home))
	assert_eq(FleetSortie.zones(_fleet_sortie_model, home), [0])
	assert_true(bool(FleetSortie.can_sortie(_fleet_sortie_model, home, 0)["ok"]))
	assert_false(bool(FleetSortie.can_sortie(_fleet_sortie_model, at_sea, 0)["ok"]))
	assert_false(bool(FleetSortie.can_sortie(_fleet_sortie_model, outside, 0)["ok"]))
	assert_eq(FleetSortie.zones(_fleet_sortie_model, at_sea), [] as Array[int])

func test_a_sortie_needs_a_move_a_hull_and_a_bordering_zone() -> void:
	_setup_fleet_sortie()
	var home: FleetState = _home()
	home.moved = true
	assert_true(String(FleetSortie.can_sortie(_fleet_sortie_model, home, 0)["reason"]).contains("already sailed"))

	var empty: FleetState = FleetState.empty_in_port(4, 0, 0)
	assert_true(String(FleetSortie.can_sortie(_fleet_sortie_model, empty, 0)["reason"]).contains("no hulls"))

	var fresh: FleetState = _home()
	assert_true(String(FleetSortie.can_sortie(_fleet_sortie_model, fresh, 1)["reason"]).contains("does not border"))
	assert_false(bool(FleetSortie.can_sortie(null, fresh, 0)["ok"]))

func test_the_sortie_spends_the_move_and_turns_home_into_a_normal_squadron() -> void:
	_setup_fleet_sortie()
	var home: FleetState = _home()
	var result: Dictionary = FleetSortie.apply(_fleet_sortie_model, home, 0)

	assert_true(bool(result["ok"]))
	assert_true(home.is_at_sea())
	assert_eq(home.sea_zone, 0)
	assert_eq(home.province, MapModel.NO_ID)
	assert_true(home.moved)
	assert_false(NavalMovement.is_home_fleet(_fleet_sortie_model, home))

func test_the_home_holds_leave_with_the_squadron_and_return_when_it_moors() -> void:
	_setup_fleet_sortie()
	var world := WorldMap.new()
	world.add_region(_fleet_sortie_model)
	var home: FleetState = _home()
	var fleets: Dictionary = {0: [home]}

	assert_eq(TradeCargo.capacity(world, fleets, 0), 7)

	FleetSortie.apply(_fleet_sortie_model, home, 0)
	assert_eq(TradeCargo.capacity(world, fleets, 0), 0, "at sea the holds are away")

	NavalMovement.begin_turn([home])
	assert_true(bool(NavalMovement.apply_move(
		_fleet_sortie_model, home, FleetState.Location.IN_PORT, 0
	)["ok"]))
	assert_true(NavalMovement.is_home_fleet(_fleet_sortie_model, home))
	assert_eq(TradeCargo.capacity(world, fleets, 0), 7)

func test_colonists_keep_their_seats_through_a_sortie() -> void:
	_setup_fleet_sortie()
	var home: FleetState = _home()
	home.add_civilian(11)
	home.add_civilian(12)

	FleetSortie.apply(_fleet_sortie_model, home, 0)

	assert_eq(home.embarked_civilians, [11, 12])
	assert_eq(home.civilian_count(), 2)

func test_a_squadron_never_breaks_a_hull_out_from_under_its_colonists() -> void:
	_setup_fleet_sortie()
	var home: FleetState = FleetState.in_port(1, 0, 0, ["a"], {"a": "fluyte"})
	home.add_civilian(11)
	assert_false(bool(NavalTransport.can_scrap(home, null)["ok"]))
	home.add_hull("b", "carrack")
	assert_true(bool(NavalTransport.can_scrap(home, null)["ok"]))

func test_troops_cannot_board_a_squadron_carrying_colonists() -> void:
	_setup_fleet_sortie()
	var home: FleetState = _home()
	home.add_civilian(11)
	var army: ArmyState = ArmyState.muster(7, 0, 0, false, ["pikemen"], 700)
	var result: Dictionary = NavalTransport.can_embark(_fleet_sortie_model, army, home)

	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("colonists"))

# --- test_fleet_missions ---

func _war(a: int, b: int) -> bool:
	return a != b

func _peace(_a: int, _b: int) -> bool:
	return false

func test_a_patrol_station_spends_the_move_and_persists() -> void:
	_setup_fleet_missions()
	var fleet := FleetState.at_sea(1, 0, 0)
	var result: Dictionary = FleetMissions.assign(_fleet_missions_model, fleet, FleetState.Mission.PATROL)
	assert_true(bool(result["ok"]), String(result.get("reason", "")))
	assert_eq(fleet.mission, FleetState.Mission.PATROL)
	assert_true(fleet.moved, "taking a station spends the turn's move")
	assert_true(FleetMissions.status_note(_fleet_missions_model, fleet).contains("patrol"))
	var fleets: Array[FleetState] = [fleet]
	NavalMovement.begin_turn(fleets)
	assert_false(fleet.moved, "the next turn restores the move")
	assert_eq(fleet.mission, FleetState.Mission.PATROL, "the station persists")

func test_the_home_fleet_and_docked_squadrons_cannot_take_a_station() -> void:
	_setup_fleet_missions()
	var home := FleetState.in_port(2, 0, 0)
	assert_true(FleetMissions.can_assign(
		_fleet_missions_model, home, FleetState.Mission.PATROL
	)["reason"].contains("home fleet"))
	var docked := FleetState.in_port(3, 0, 1)
	assert_true(FleetMissions.can_assign(
		_fleet_missions_model, docked, FleetState.Mission.PATROL
	)["reason"].contains("at sea"))
	var moved := FleetState.at_sea(4, 0, 0)
	moved.moved = true
	assert_true(FleetMissions.can_assign(
		_fleet_missions_model, moved, FleetState.Mission.PATROL
	)["reason"].contains("already moved"))
	var same := FleetState.at_sea(5, 0, 0)
	same.mission = FleetState.Mission.PATROL
	assert_true(FleetMissions.can_assign(
		_fleet_missions_model, same, FleetState.Mission.PATROL
	)["reason"].contains("already holds"))
	var empty := FleetState.at_sea(6, 0, 0)
	empty.hulls = []
	empty.hull_types = {}
	assert_true(FleetMissions.can_assign(
		_fleet_missions_model, empty, FleetState.Mission.PATROL
	)["reason"].contains("no hulls"))
	assert_false(bool(FleetMissions.can_assign(null, home, FleetState.Mission.PATROL)["ok"]))
	assert_false(bool(FleetMissions.can_assign(
		_fleet_missions_model, home, FleetState.Mission.MOVE
	)["ok"]))

func test_a_blockade_needs_a_hostile_coast_in_the_zone() -> void:
	_setup_fleet_missions()
	var fleet := FleetState.at_sea(1, 0, 1)
	assert_eq(FleetMissions.blockade_targets(_fleet_missions_model, fleet, _war), [1])
	var result: Dictionary = FleetMissions.assign(
		_fleet_missions_model, fleet, FleetState.Mission.BLOCKADE, 1, _war
	)
	assert_true(bool(result["ok"]), String(result.get("reason", "")))
	assert_eq(fleet.blockade_province, 1)
	assert_true(FleetMissions.is_blockading(_fleet_missions_model, fleet, _war))
	assert_false(FleetMissions.is_blockading(_fleet_missions_model, fleet, _peace))
	assert_true(FleetMissions.status_note(_fleet_missions_model, fleet).contains("Blockading Coro"))
	var far := FleetState.at_sea(2, 0, 0)
	assert_true(FleetMissions.can_assign(
		_fleet_missions_model, far, FleetState.Mission.BLOCKADE, 1, _war
	)["reason"].contains("border"))
	var own := FleetState.at_sea(3, 0, 0)
	assert_true(FleetMissions.can_assign(
		_fleet_missions_model, own, FleetState.Mission.BLOCKADE, 0, _war
	)["reason"].contains("enemy coast"))
	var missing := FleetState.at_sea(4, 0, 1)
	assert_true(FleetMissions.can_assign(
		_fleet_missions_model, missing, FleetState.Mission.BLOCKADE, 99, _war
	)["reason"].contains("enemy province"))
	assert_true(FleetMissions.can_assign(
		_fleet_missions_model, FleetState.at_sea(5, 0, 1), FleetState.Mission.BLOCKADE, 1, _peace
	)["reason"].contains("declared war"))
	var same := FleetState.at_sea(6, 0, 1)
	same.mission = FleetState.Mission.BLOCKADE
	same.blockade_province = 1
	assert_true(FleetMissions.can_assign(
		_fleet_missions_model, same, FleetState.Mission.BLOCKADE, 1, _war
	)["reason"].contains("already blockades"))
	_fleet_missions_model.province_data(1).owner = MapModel.NO_ID
	assert_true(FleetMissions.can_assign(
		_fleet_missions_model, FleetState.at_sea(7, 0, 1), FleetState.Mission.BLOCKADE, 1, _war
	)["reason"].contains("no crown"))

func test_blockade_targets_are_the_hostile_coasts_beside_the_zone() -> void:
	_setup_fleet_missions()
	var fleet := FleetState.at_sea(1, 0, 0)
	assert_eq(FleetMissions.blockade_targets(_fleet_missions_model, fleet, _war), [])
	assert_eq(FleetMissions.blockade_targets(null, fleet, _war), [])
	var docked := FleetState.in_port(2, 0, 1)
	assert_eq(FleetMissions.blockade_targets(_fleet_missions_model, docked, _war), [])

func test_a_normal_move_clears_the_station() -> void:
	_setup_fleet_missions()
	var fleet := FleetState.at_sea(1, 0, 0)
	FleetMissions.assign(_fleet_missions_model, fleet, FleetState.Mission.PATROL)
	var fleets: Array[FleetState] = [fleet]
	NavalMovement.begin_turn(fleets)
	var result: Dictionary = NavalMovement.apply_move(
		_fleet_missions_model, fleet, FleetState.Location.AT_SEA, 1
	)
	assert_true(bool(result["ok"]))
	assert_eq(fleet.mission, FleetState.Mission.NONE)
	assert_eq(fleet.blockade_province, MapModel.NO_ID)

func test_the_strongest_station_identifies_a_group() -> void:
	_setup_fleet_missions()
	var patrol := FleetState.at_sea(1, 0, 0)
	patrol.mission = FleetState.Mission.PATROL
	var blockade := FleetState.at_sea(2, 0, 1)
	blockade.mission = FleetState.Mission.BLOCKADE
	blockade.blockade_province = 1
	assert_eq(
		FleetMissions.station_mission(_fleet_missions_model, [patrol], _war),
		FleetState.Mission.PATROL
	)
	assert_eq(
		FleetMissions.station_mission(_fleet_missions_model, [patrol, blockade], _war),
		FleetState.Mission.BLOCKADE
	)
	assert_eq(
		FleetMissions.station_mission(_fleet_missions_model, [blockade], _peace),
		FleetState.Mission.NONE
	)

## The station line follows the same gate the interception does: a blockade
## whose coast is ours, or at peace, attempts nothing, so the dossier must not
## claim it does (REQ-P2-03).
func test_a_blockade_note_follows_the_station_gate() -> void:
	_setup_fleet_missions()
	var fleet := FleetState.at_sea(1, 0, 1)
	FleetMissions.assign(_fleet_missions_model, fleet, FleetState.Mission.BLOCKADE, 1, _war)
	assert_true(FleetMissions.status_note(_fleet_missions_model, fleet, _war).contains("Blockading Coro"))
	# The crown takes the coast it was blockading.
	_fleet_missions_model.province_data(1).owner = 0
	assert_false(FleetMissions.is_blockading(_fleet_missions_model, fleet, _war))
	assert_false(FleetMissions.status_note(_fleet_missions_model, fleet, _war).contains("Blockading"))
	assert_true(FleetMissions.status_note(_fleet_missions_model, fleet, _war).contains("lapsed"))
	# Peace ends a blockade just as surely as capture.
	_fleet_missions_model.province_data(1).owner = 1
	assert_true(FleetMissions.status_note(_fleet_missions_model, fleet, _peace).contains("lapsed"))
	assert_true(FleetMissions.status_note(_fleet_missions_model, fleet, _war).contains("Blockading"))
	# A station with no coast or map still names the station plainly.
	var legacy := FleetState.at_sea(2, 0, 1)
	legacy.mission = FleetState.Mission.BLOCKADE
	assert_true(FleetMissions.status_note(null, legacy).contains("the enemy coast"))

func test_station_ids_round_trip_and_labels_read_plainly() -> void:
	_setup_fleet_missions()
	assert_eq(FleetMissions.id_of(FleetState.Mission.PATROL), "patrol")
	assert_eq(FleetMissions.from_id("patrol"), FleetState.Mission.PATROL)
	assert_eq(FleetMissions.id_of(FleetState.Mission.BLOCKADE), "blockade")
	assert_eq(FleetMissions.from_id("blockade"), FleetState.Mission.BLOCKADE)
	assert_eq(FleetMissions.id_of(FleetState.Mission.DEFEND), "defend")
	assert_eq(FleetMissions.from_id("defend"), FleetState.Mission.DEFEND)
	assert_eq(FleetMissions.label(FleetState.Mission.BLOCKADE), "Blockade")
	assert_eq(FleetMissions.from_id("nonsense"), FleetState.Mission.NONE)
	assert_eq(FleetMissions.label(FleetState.Mission.NONE), "No station")
	assert_true(FleetMissions.is_stationary(FleetState.Mission.PATROL))
	assert_false(FleetMissions.is_stationary(FleetState.Mission.MOVE))

func test_a_defend_station_holds_and_names_its_orders() -> void:
	_setup_fleet_missions()
	var fleet := FleetState.at_sea(1, 0, 0)
	var result: Dictionary = FleetMissions.assign(
		_fleet_missions_model, fleet, FleetState.Mission.DEFEND
	)
	assert_true(bool(result["ok"]), String(result.get("reason", "")))
	assert_eq(fleet.mission, FleetState.Mission.DEFEND)
	assert_true(fleet.moved)
	assert_true(FleetMissions.status_note(_fleet_missions_model, fleet).contains("Holding station"))
	assert_true(String(result["message"]).contains("holds station"))

func test_a_lapsed_blockade_stops_claiming_the_station() -> void:
	_setup_fleet_missions()
	var fleet := FleetState.at_sea(1, 0, 1)
	FleetMissions.assign(_fleet_missions_model, fleet, FleetState.Mission.BLOCKADE, 1, _war)
	assert_true(FleetMissions.status_note(_fleet_missions_model, fleet, _war).contains("Blockading Coro"))
	var peace: String = FleetMissions.status_note(_fleet_missions_model, fleet, _peace)
	assert_true(peace.contains("lapsed"), peace)
	_fleet_missions_model.province_data(1).owner = 0
	var taken: String = FleetMissions.status_note(_fleet_missions_model, fleet, _war)
	assert_true(taken.contains("lapsed"), taken)
	assert_false(FleetMissions.is_blockading(_fleet_missions_model, fleet, _war))

func test_mission_and_blockade_survive_a_save_round_trip() -> void:
	_setup_fleet_missions()
	var fleet := FleetState.at_sea(1, 0, 1)
	FleetMissions.assign(_fleet_missions_model, fleet, FleetState.Mission.BLOCKADE, 1, _war)
	var saved: FleetState = FleetState.from_dict(fleet.to_dict())
	assert_eq(saved.mission, FleetState.Mission.BLOCKADE)
	assert_eq(saved.blockade_province, 1)
	var legacy: FleetState = FleetState.from_dict({"id": 9, "owner": 0})
	assert_eq(legacy.mission, FleetState.Mission.NONE)
	assert_eq(legacy.blockade_province, MapModel.NO_ID)

## Marking a landing site spends the move, so the squadron never sailed into
## the zone and cannot seize the initiative from the fleet that did (wiki:
## ships-and-naval § Missions and Movement — Beachhead is stationary).
func test_a_beachhead_squadron_is_stationary() -> void:
	_setup_fleet_missions()
	var marker := FleetState.at_sea(1, 0, 0, ["ship_1"], {"ship_1": "carrack"})
	marker.mission = FleetState.Mission.BEACHHEAD
	marker.beachhead_province = 1
	marker.beachhead_turn = 1
	marker.moved = true
	var mover := FleetState.at_sea(2, 1, 0, ["ship_2"], {"ship_2": "carrack"})
	mover.moved = true

	assert_true(FleetMissions.is_stationary(FleetState.Mission.BEACHHEAD))
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		[marker, mover], Callable(), {"interception_roll": 0.99}
	)

	assert_eq(battles.size(), 1)
	assert_eq(int(battles[0]["attacker"]), 1, "the squadron that sailed in attacks")

# --- test_naval_strength ---

func _naval_strength_squadron() -> FleetState:
	return FleetState.at_sea(
		4, 0, 1, ["ship_1", "ship_2", "ship_3"],
		{"ship_1": "carrack", "ship_2": "carrack", "ship_3": "frigate"}
	)

func test_the_squadron_totals_every_hull() -> void:
	var row: Dictionary = NavalStrength.squadron(_naval_strength_squadron())
	var totals: Dictionary = row["totals"]

	assert_eq(int(row["count"]), 3)
	assert_eq(int(totals["frp"]), 2 + 2 + 4)
	assert_eq(int(totals["rng"]), 1 + 1 + 3)
	assert_eq(int(totals["arm"]), 1 + 1 + 2)
	assert_eq(int(totals["hull"]), 2 + 2 + 4)
	assert_eq(int(totals["mv"]), 2 + 2 + 3)

func test_rows_aggregate_distinct_hulls_of_one_type() -> void:
	var rows: Array = NavalStrength.squadron(_naval_strength_squadron())["types"]

	assert_eq(rows.size(), 2, "two types, three hulls")
	assert_eq(String(rows[0]["type_id"]), "carrack")
	assert_eq(int(rows[0]["count"]), 2)
	assert_eq(String(rows[1]["type_id"]), "frigate")
	assert_eq(int(rows[1]["count"]), 1)
	assert_false(bool(rows[0]["warship"]))
	assert_true(bool(rows[1]["warship"]))

func test_strength_and_pool_match_the_resolver() -> void:
	var fleet: FleetState = _naval_strength_squadron()
	var row: Dictionary = NavalStrength.squadron(fleet)

	assert_almost_eq(float(row["strength"]), 2.75 + 2.75 + 5.8, 0.0001)
	assert_almost_eq(float(row["strength"]), NavalCombat.side_strength([fleet]), 0.0001)
	assert_almost_eq(
		float(row["durability"]), NavalCombat.side_durability([fleet]), 0.0001
	)
	assert_almost_eq(NavalStrength.strength(null), 0.0, 0.0001)
	assert_almost_eq(NavalStrength.durability(null), 0.0, 0.0001)

func test_an_empty_squadron_reads_as_nothing() -> void:
	var row: Dictionary = NavalStrength.squadron(FleetState.empty_in_port(9, 0, 1))

	assert_eq(int(row["count"]), 0)
	assert_almost_eq(float(row["strength"]), 0.0, 0.0001)
	assert_eq((row["types"] as Array).size(), 0)
	assert_eq(int((row["totals"] as Dictionary)["frp"]), 0)

func test_the_formula_names_every_weight() -> void:
	var row: Dictionary = NavalStrength.squadron(_naval_strength_squadron())
	var formula: String = String(row["formula"])

	assert_true(formula.contains("FRP 8"), formula)
	assert_true(formula.contains("RNG 5×0.4"), formula)
	assert_true(formula.contains("ARM 4×0.15"), formula)
	assert_true(formula.contains("MV 7×0.1"), formula)
	# 2.2 + 2.2 + 4.8: the pool is summed per hull, never 8 × (1 + 4/10).
	assert_almost_eq(float(row["durability"]), 9.2, 0.0001)
	assert_true(String(row["pool"]).contains("9.2"), String(row["pool"]))

func test_a_hull_line_names_its_own_numbers() -> void:
	assert_eq(
		NavalStrength.hull_line("frigate"),
		"FRP 4 · RNG 3 · ARM 2 · HULL 4 · MV 3 · 5.8 strength"
	)

func test_an_edge_wins_and_an_even_split_is_a_draw() -> void:
	var win: Dictionary = NavalStrength.odds(60.0, 40.0)
	assert_eq(NavalStrength.outcome_of(win), NavalStrength.OUTCOME_WIN)
	assert_eq(NavalStrength.share_text(win), "60%")

	var loss: Dictionary = NavalStrength.odds(40.0, 60.0)
	assert_eq(NavalStrength.outcome_of(loss), NavalStrength.OUTCOME_LOSS)

	# The resolver calls anything inside ±3% of an even split a stalemate, so the
	# boundary itself is a draw (wiki: § Naval Combat Resolution).
	assert_eq(
		NavalStrength.outcome_of(NavalStrength.odds(53.0, 47.0)),
		NavalStrength.OUTCOME_DRAW
	)
	assert_eq(
		NavalStrength.outcome_of(NavalStrength.odds(53.1, 46.9)),
		NavalStrength.OUTCOME_WIN
	)
	assert_almost_eq(NavalStrength.need(), 0.53, 0.0001)

func test_no_strength_anywhere_is_a_draw() -> void:
	var even: Dictionary = NavalStrength.odds(0.0, 0.0)

	assert_eq(NavalStrength.outcome_of(even), NavalStrength.OUTCOME_DRAW)
	assert_almost_eq(float(even["share"]), 0.5, 0.0001)

func test_the_zone_sums_friend_and_hostile_sides() -> void:
	var mine: FleetState = FleetState.at_sea(1, 0, 0, ["ship_1"], {"ship_1": "carrack"})
	var second: FleetState = FleetState.at_sea(2, 0, 0, ["ship_2"], {"ship_2": "carrack"})
	var theirs: FleetState = FleetState.at_sea(3, 1, 0, ["ship_3"], {"ship_3": "frigate"})
	var far: FleetState = FleetState.at_sea(4, 1, 1, ["ship_4"], {"ship_4": "frigate"})
	var moored: FleetState = FleetState.in_port(5, 1, 1, ["ship_5"], {"ship_5": "frigate"})

	var row: Dictionary = NavalStrength.zone([mine, second, theirs, far, moored], mine)

	assert_almost_eq(float(row["own"]), 5.5, 0.0001, "two of ours fight as one side")
	assert_almost_eq(float(row["foe"]), 5.8, 0.0001, "the other zone and the port stay out")
	assert_eq(int(row["own_hulls"]), 2)
	assert_eq(int(row["foe_hulls"]), 1)
	assert_true((row["foes"] as Array).has(1))
	assert_eq(NavalStrength.outcome_of(row), NavalStrength.OUTCOME_DRAW)

func test_a_peaceful_flag_is_no_threat() -> void:
	var mine: FleetState = FleetState.at_sea(1, 0, 0, ["ship_1"], {"ship_1": "carrack"})
	var theirs: FleetState = FleetState.at_sea(3, 1, 0, ["ship_3"], {"ship_3": "frigate"})
	var peace := func(_a: int, _b: int) -> bool: return false

	var row: Dictionary = NavalStrength.zone([mine, theirs], mine, peace)

	assert_almost_eq(float(row["foe"]), 0.0, 0.0001)
	assert_eq((row["foes"] as Array).size(), 0)

func test_a_moored_squadron_gets_no_odds() -> void:
	var moored: FleetState = FleetState.in_port(5, 0, 1, ["ship_5"], {"ship_5": "frigate"})

	assert_eq(NavalStrength.zone([moored], moored).size(), 0)
	assert_eq(NavalStrength.zone([], null).size(), 0)

func test_the_zone_falls_back_to_the_squadron_it_was_asked_about() -> void:
	var lone: FleetState = FleetState.at_sea(7, 0, 1, ["ship_7"], {"ship_7": "sloop"})

	var row: Dictionary = NavalStrength.zone([], lone)

	assert_almost_eq(float(row["own"]), 3.25, 0.0001)
	assert_eq(int(row["own_hulls"]), 1)

# --- test_naval_retreat ---

func _naval_retreat_fleet(id: int, owner: int, zone: int, types: Array) -> FleetState:
	var fleet := FleetState.at_sea(id, owner, zone)
	var hull_ids: Array[String] = []
	var hull_types: Dictionary = {}
	for index in types.size():
		var hull_id: String = "ship_%d_%d" % [id, index]
		hull_ids.append(hull_id)
		hull_types[hull_id] = types[index]
	fleet.set_hulls(hull_ids, hull_types)
	return fleet

func _naval_retreat_squadron(id: int, owner: int, zone: int, type_id: String, count: int) -> FleetState:
	var types: Array = []
	for _index in count:
		types.append(type_id)
	return _naval_retreat_fleet(id, owner, zone, types)

func test_retreat_chance_follows_the_wiki_formula() -> void:
	_setup_naval_retreat()
	var beaten := _naval_retreat_squadron(1, 1, 0, "fluyte", 1)
	var victor := _naval_retreat_squadron(2, 0, 0, "carrack", 1)
	assert_almost_eq(
		NavalRetreat.chance([beaten], [victor], FleetState.Mission.NONE), 0.6, 0.0001
	)
	assert_almost_eq(
		NavalRetreat.chance([beaten], [victor], FleetState.Mission.PATROL), 0.5, 0.0001
	)
	assert_almost_eq(
		NavalRetreat.chance([beaten], [victor], FleetState.Mission.BLOCKADE), 0.4, 0.0001
	)
	var fast := _naval_retreat_squadron(3, 1, 0, "sloop", 1)
	assert_almost_eq(
		NavalRetreat.chance([fast], [victor], FleetState.Mission.NONE), 0.7, 0.0001
	)
	assert_almost_eq(
		NavalRetreat.chance([victor], [fast], FleetState.Mission.NONE), 0.5, 0.0001
	)

func test_a_retreat_needs_an_adjacent_friendly_or_neutral_zone() -> void:
	_setup_naval_retreat()
	var beaten := _naval_retreat_squadron(1, 1, 0, "carrack", 1)
	var victor := _naval_retreat_squadron(2, 0, 0, "carrack", 3)
	var hostile := _naval_retreat_squadron(3, 2, 1, "carrack", 1)
	var fleets: Array = [victor, beaten, hostile]
	var owners: Array[int] = [1]
	assert_eq(
		NavalRetreat.safe_zones(_naval_retreat_model, 0, owners, fleets),
		[] as Array[int],
		"the only neighbouring zone is hostile"
	)
	fleets.erase(hostile)
	assert_eq(
		NavalRetreat.safe_zones(_naval_retreat_model, 0, owners, fleets),
		[1] as Array[int]
	)

func test_a_successful_retreat_moves_the_beaten_squadron() -> void:
	_setup_naval_retreat()
	var strong := _naval_retreat_squadron(1, 0, 0, "carrack", 3)
	strong.moved = true
	var weak := _naval_retreat_squadron(2, 1, 0, "carrack", 1)
	var fleets: Array = [strong, weak]
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		fleets,
		Callable(),
		{"model": _naval_retreat_model, "fleets": fleets, "retreat_roll": 0.0}
	)
	var retreat: Dictionary = battles[0]["retreat"]
	assert_true(bool(retreat["success"]))
	assert_eq(int(retreat["zone"]), 1)
	assert_eq(weak.sea_zone, 1)
	assert_eq(weak.ship_count(), 1, "the squadron slips away intact")
	assert_true(weak.moved)
	assert_eq((battles[0]["defender_lost"] as Array).size(), 0)

func test_a_failed_retreat_is_a_rout() -> void:
	_setup_naval_retreat()
	var strong := _naval_retreat_squadron(1, 0, 0, "carrack", 3)
	strong.moved = true
	var weak := _naval_retreat_squadron(2, 1, 0, "carrack", 1)
	var fleets: Array = [strong, weak]
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		fleets,
		Callable(),
		{"model": _naval_retreat_model, "fleets": fleets, "retreat_roll": 0.99}
	)
	var retreat: Dictionary = battles[0]["retreat"]
	assert_false(bool(retreat["success"]))
	assert_eq(weak.ship_count(), 0)
	assert_eq(int((battles[0]["defender_lost"] as Array).size()), 1)

func test_a_retreating_side_abandons_its_station() -> void:
	_setup_naval_retreat()
	var strong := _naval_retreat_squadron(1, 0, 0, "carrack", 3)
	strong.moved = true
	var weak := _naval_retreat_squadron(2, 1, 0, "carrack", 1)
	weak.mission = FleetState.Mission.DEFEND
	weak.beachhead_province = 1
	weak.beachhead_turn = 3
	var fleets: Array = [strong, weak]
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		fleets,
		Callable(),
		{"model": _naval_retreat_model, "fleets": fleets, "retreat_roll": 0.0}
	)
	assert_true(bool((battles[0]["retreat"] as Dictionary)["success"]))
	assert_eq(weak.mission, FleetState.Mission.NONE)
	assert_false(weak.has_beachhead())

func test_without_a_model_the_loser_is_still_routed() -> void:
	_setup_naval_retreat()
	var strong := _naval_retreat_squadron(1, 0, 0, "carrack", 3)
	strong.moved = true
	var weak := _naval_retreat_squadron(2, 1, 0, "carrack", 1)
	var battles: Array[Dictionary] = NavalCombat.resolve_turn([strong, weak])
	assert_eq((battles[0]["retreat"] as Dictionary).size(), 0)
	assert_eq(weak.ship_count(), 0)

func test_the_despatch_names_the_withdrawal() -> void:
	_setup_naval_retreat()
	var battle: Dictionary = {
		"attacker": 0,
		"defender": 1,
		"outcome": NavalCombat.Outcome.SIDE1_VICTORY,
		"attacker_lost": [],
		"defender_lost": [],
		"retreat": {"success": true, "beaten": 1, "zone": 4},
	}
	assert_eq(
		BattleReport.describe(battle, "Windward Passage", FACTIONS),
		"England withdraws from the Windward Passage — España holds the zone"
	)

# --- test_naval_port_loss ---

func test_a_squadron_in_a_captured_port_sorts_out_to_the_lowest_zone() -> void:
	var model: MapModel = naval_port_loss_Fixture.build()
	var fleet: FleetState = FleetState.in_port(1, 0, SEAT, ["ship_1"])
	model.province_data(SEAT).owner = 1

	var reports: Array[Dictionary] = NavalPortLoss.evict_stranded(model, [fleet])

	assert_eq(reports.size(), 1)
	assert_false(bool(reports[0]["scuttled"]))
	assert_eq(int(reports[0]["zone"]), 0)
	assert_true(fleet.is_at_sea())
	assert_eq(fleet.sea_zone, 0)
	assert_eq(fleet.province, MapModel.NO_ID)
	assert_true(fleet.moved, "the sortie spends the squadron's move")

func test_a_squadron_with_no_coast_is_scuttled() -> void:
	var model: MapModel = _inland_chart()
	var fleet: FleetState = FleetState.in_port(1, 1, HARBOUR, ["ship_1"])

	var reports: Array[Dictionary] = NavalPortLoss.evict_stranded(model, [fleet])

	assert_eq(reports.size(), 1)
	assert_true(bool(reports[0]["scuttled"]))
	assert_eq(int(reports[0]["zone"]), MapModel.NO_ID)
	assert_true(fleet.is_afloat(), "the report keeps the hull list for the toast")

func test_an_empty_slip_is_dropped_without_a_report() -> void:
	var model: MapModel = naval_port_loss_Fixture.build()
	var slip: FleetState = FleetState.empty_in_port(1, 0, SEAT)
	model.province_data(SEAT).owner = 1
	var roster: Array[FleetState] = [slip]

	var reports: Array[Dictionary] = NavalPortLoss.evict_stranded(model, roster)

	assert_true(reports.is_empty())
	assert_true(roster.is_empty())

func test_an_owned_port_keeps_its_squadron_moored() -> void:
	var model: MapModel = naval_port_loss_Fixture.build()
	var fleet: FleetState = FleetState.in_port(1, 0, SEAT, ["ship_1"])

	var reports: Array[Dictionary] = NavalPortLoss.evict_stranded(model, [fleet])

	assert_true(reports.is_empty())
	assert_true(fleet.is_in_port())
	assert_eq(fleet.province, SEAT)

func test_a_seaboard_seat_re_moors_the_home_squadron() -> void:
	var model: MapModel = naval_port_loss_Fixture.build()
	var fleet: FleetState = FleetState.in_port(1, 0, SEAT, ["ship_1"])
	model.province_data(HARBOUR).owner = 0

	var result: Dictionary = NavalPortLoss.relocate_home(model, [fleet], 0, SEAT, HARBOUR)

	assert_eq(int(result["merged"]), 0)
	assert_eq((result["moved"] as Array).size(), 1)
	assert_eq(fleet.province, HARBOUR)
	assert_true(fleet.is_in_port())
	assert_eq(fleet.hulls, ["ship_1"])

func test_an_inland_seat_leaves_the_home_squadron_to_sort_out() -> void:
	var model: MapModel = _inland_chart()
	var fleet: FleetState = FleetState.in_port(1, 0, SEAT, ["ship_1"])

	var result: Dictionary = NavalPortLoss.relocate_home(model, [fleet], 0, SEAT, HARBOUR)

	assert_true((result["moved"] as Array).is_empty())
	assert_eq(fleet.province, SEAT, "the eviction pass owns the inland fallback")
	model.province_data(SEAT).owner = 1
	NavalPortLoss.evict_stranded(model, [fleet])
	assert_true(fleet.is_at_sea())
	assert_eq(fleet.sea_zone, 0)

func test_a_squadron_at_the_new_seat_absorbs_the_home_squadron() -> void:
	var model: MapModel = naval_port_loss_Fixture.build()
	var home: FleetState = FleetState.in_port(1, 0, SEAT, ["ship_1"])
	var moored: FleetState = FleetState.in_port(2, 0, HARBOUR, ["ship_2"])
	model.province_data(HARBOUR).owner = 0
	var roster: Array[FleetState] = [home, moored]

	var result: Dictionary = NavalPortLoss.relocate_home(model, roster, 0, SEAT, HARBOUR)

	assert_eq(int(result["merged"]), 1)
	assert_eq(roster.size(), 1)
	assert_eq(roster[0], moored)
	assert_eq(moored.hulls, ["ship_2", "ship_1"])

## The re-mooring is administrative: the absorbed squadron keeps its colonists
## and troops, and a second army goes ashore at the new seat instead of being
## lost (wiki: ships-and-naval § Ports that change hands; DR-20261109-11).
func test_the_absorbed_squadron_keeps_its_passengers() -> void:
	var model: MapModel = naval_port_loss_Fixture.build()
	var home: FleetState = FleetState.in_port(1, 0, SEAT, ["ship_1", "ship_2"])
	var moored: FleetState = FleetState.in_port(2, 0, HARBOUR, ["ship_3", "ship_4"])
	model.province_data(HARBOUR).owner = 0
	home.add_civilian(11)
	home.embarked_army = 21
	var roster: Array[FleetState] = [home, moored]

	var result: Dictionary = NavalPortLoss.relocate_home(model, roster, 0, SEAT, HARBOUR)

	assert_eq(int(result["merged"]), 1)
	assert_true(moored.has_civilian(11), "the colonist rides the absorbed hulls")
	assert_eq(moored.embarked_army, 21, "the troops stay aboard")
	assert_true((result["ashore"] as Array).is_empty())

	# A second army cannot share the squadron: the surplus is reported for the
	# landing at the new seat, never dropped with the merged-away hulls.
	moored.embarked_army = 31
	var second: FleetState = FleetState.in_port(3, 0, SEAT, ["ship_5"])
	second.embarked_army = 32
	var other: Dictionary = NavalPortLoss.relocate_home(
		model, [second, moored], 0, SEAT, HARBOUR
	)

	assert_eq(moored.embarked_army, 31, "the moored squadron keeps its own army")
	assert_eq((other["ashore"] as Array), [32] as Array[int])

func test_an_empty_home_slip_is_dropped_on_the_move() -> void:
	var model: MapModel = naval_port_loss_Fixture.build()
	var slip: FleetState = FleetState.empty_in_port(1, 0, SEAT)
	var roster: Array[FleetState] = [slip]

	var result: Dictionary = NavalPortLoss.relocate_home(model, roster, 0, SEAT, HARBOUR)

	assert_true((result["moved"] as Array).is_empty())
	assert_true(roster.is_empty())

func test_settlement_sorts_out_and_reports_every_region() -> void:
	var model: MapModel = naval_port_loss_Fixture.build()
	var world := WorldMap.new()
	world.add_region(model)
	var regions := MapRegionTable.new()
	var fleet: FleetState = FleetState.in_port(1, 0, SEAT, ["ship_1"])
	regions.set_region(0, [fleet])
	model.province_data(SEAT).owner = 1

	var result: Dictionary = FleetPortSettlement.settle(world, regions, [])

	assert_eq((result["regions"] as Array), [0])
	assert_eq((result["reports"] as Array).size(), 1)
	assert_eq((result["sorties"] as Array).size(), 1)
	assert_true(fleet.is_at_sea())

func test_settlement_re_moors_a_reassigned_home_squadron() -> void:
	var model: MapModel = naval_port_loss_Fixture.build()
	var world := WorldMap.new()
	world.add_region(model)
	var regions := MapRegionTable.new()
	var fleet: FleetState = FleetState.in_port(1, 0, SEAT, ["ship_1"])
	regions.set_region(0, [fleet])
	model.province_data(HARBOUR).owner = 0

	var result: Dictionary = FleetPortSettlement.settle(
		world,
		regions,
		[{"faction": 0, "lost": SEAT, "province": HARBOUR, "region": 0}]
	)

	assert_eq(fleet.province, HARBOUR)
	assert_eq((result["reports"] as Array).size(), 1)
	assert_true((result["sorties"] as Array).is_empty())

## A 7x3 chart: province 0 is coastal, province 1 is ringed by neutral land so
## it has no sea zone, and the only water is the bay beside province 0.
func _inland_chart() -> MapModel:
	var model := MapModel.new()
	model.setup(7, 3)
	_land(model, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)], 0)
	_land(model, [Vector2i(3, 0), Vector2i(4, 0), Vector2i(3, 1), Vector2i(4, 1)], 1)
	for tile: Vector2i in [
		Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2),
		Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 0),
		Vector2i(5, 1), Vector2i(5, 2),
	]:
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.PLAINS
	var water: Array[Vector2i] = [
		Vector2i(0, 2), Vector2i(1, 2),
		Vector2i(6, 0), Vector2i(6, 1), Vector2i(6, 2),
	]
	for tile: Vector2i in water:
		model.sea_zone[model.index_of(tile.x, tile.y)] = 0
	var seat := ProvinceState.create(
		0, "Seat", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
		Vector2(0.5, 0.5), 4, 0, true
	)
	var inland := ProvinceState.create(
		1, "Inland", [Vector2i(3, 0), Vector2i(4, 0), Vector2i(3, 1), Vector2i(4, 1)],
		Vector2(3.5, 0.5), 4, 0, false
	)
	model.provinces = [seat, inland]
	model.sea_zones = [SeaZoneState.create(0, "Bay", water, Vector2(0.5, 2.0), 5)]
	return model

func _land(model: MapModel, tiles: Array, province_id: int) -> void:
	for tile: Vector2i in tiles:
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.PLAINS
		model.province[model.index_of(tile.x, tile.y)] = province_id

# --- test_naval_interception ---

func _naval_interception_fleet(id: int, owner: int, zone: int, types: Array) -> FleetState:
	var fleet := FleetState.at_sea(id, owner, zone)
	var hull_ids: Array[String] = []
	var hull_types: Dictionary = {}
	for index in types.size():
		var hull_id: String = "ship_%d_%d" % [id, index]
		hull_ids.append(hull_id)
		hull_types[hull_id] = types[index]
	fleet.set_hulls(hull_ids, hull_types)
	return fleet

func _naval_interception_squadron(id: int, owner: int, zone: int, type_id: String, count: int) -> FleetState:
	var types: Array = []
	for _index in count:
		types.append(type_id)
	return _naval_interception_fleet(id, owner, zone, types)

func test_interception_chance_follows_the_wiki_formula() -> void:
	_setup_naval_interception()
	var sloop := _naval_interception_squadron(1, 0, 0, "sloop", 1)
	var fluyte := _naval_interception_squadron(2, 1, 0, "fluyte", 1)
	assert_almost_eq(
		NavalInterception.chance([sloop], [fluyte], FleetState.Mission.PATROL),
		0.5 * 4.0 / 7.0,
		0.0001
	)
	assert_almost_eq(
		NavalInterception.chance([sloop], [fluyte], FleetState.Mission.BLOCKADE),
		0.9 * 4.0 / 7.0,
		0.0001
	)
	assert_eq(
		NavalInterception.chance([], [fluyte], FleetState.Mission.PATROL), 0.0
	)
	assert_eq(
		NavalInterception.chance([sloop], [], FleetState.Mission.PATROL), 0.0
	)

func test_interception_chance_is_clamped() -> void:
	_setup_naval_interception()
	var sloop := _naval_interception_squadron(1, 0, 0, "sloop", 1)
	var many_fluytes := _naval_interception_squadron(2, 1, 0, "fluyte", 30)
	assert_almost_eq(
		NavalInterception.chance([sloop], [many_fluytes], FleetState.Mission.PATROL),
		NavalInterception.MIN_CHANCE,
		0.0001
	)
	var raiders := _naval_interception_squadron(3, 0, 0, "raider", 20)
	var one_fluyte := _naval_interception_squadron(4, 1, 0, "fluyte", 1)
	assert_almost_eq(
		NavalInterception.chance([raiders], [one_fluyte], FleetState.Mission.BLOCKADE),
		NavalInterception.MAX_CHANCE,
		0.0001
	)

func test_the_roll_is_deterministic_and_in_range() -> void:
	_setup_naval_interception()
	var first: float = NavalInterception.roll(1500, 4, 2, 0, 1)
	assert_almost_eq(first, NavalInterception.roll(1500, 4, 2, 0, 1), 0.0001)
	assert_gte(first, 0.0)
	assert_lt(first, 1.0)
	assert_ne(first, NavalInterception.roll(1501, 4, 2, 0, 1))

func test_attempts_follow_the_roll() -> void:
	_setup_naval_interception()
	var sloop := _naval_interception_squadron(1, 0, 0, "sloop", 1)
	var fluyte := _naval_interception_squadron(2, 1, 0, "fluyte", 1)
	var hit: Dictionary = NavalInterception.attempt(
		0, [sloop], [fluyte], FleetState.Mission.PATROL, 0, 0, 0.0
	)
	var miss: Dictionary = NavalInterception.attempt(
		0, [sloop], [fluyte], FleetState.Mission.PATROL, 0, 0, 0.99
	)
	assert_true(bool(hit["ok"]))
	assert_false(bool(miss["ok"]))
	assert_true(bool(NavalInterception.attempt(
		0, [], [fluyte], FleetState.Mission.PATROL, 0, 0, 0.0
	)["ok"]) == false)

func test_a_successful_patrol_interception_makes_the_patroller_attacker() -> void:
	_setup_naval_interception()
	var patrol := _naval_interception_squadron(1, 0, 0, "sloop", 1)
	patrol.mission = FleetState.Mission.PATROL
	var mover := _naval_interception_squadron(2, 1, 0, "fluyte", 1)
	mover.moved = true
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		[patrol, mover], Callable(), {"interception_roll": 0.0}
	)
	assert_eq(battles.size(), 1)
	assert_eq(int(battles[0]["attacker"]), 0)
	assert_true(bool(battles[0]["intercepted"]))
	assert_almost_eq(
		float(battles[0]["interception_chance"]), 0.5 * 4.0 / 7.0, 0.0001
	)

func test_a_failed_interception_leaves_the_mover_as_attacker() -> void:
	_setup_naval_interception()
	var patrol := _naval_interception_squadron(1, 0, 0, "sloop", 1)
	patrol.mission = FleetState.Mission.PATROL
	var mover := _naval_interception_squadron(2, 1, 0, "fluyte", 1)
	mover.moved = true
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		[patrol, mover], Callable(), {"interception_roll": 0.99}
	)
	assert_eq(int(battles[0]["attacker"]), 1)
	assert_false(bool(battles[0]["intercepted"]))

func test_a_blockade_intercepts_on_the_higher_factor() -> void:
	_setup_naval_interception()
	var blockader := _naval_interception_squadron(1, 0, 1, "sloop", 1)
	blockader.mission = FleetState.Mission.BLOCKADE
	blockader.blockade_province = 1
	var mover := _naval_interception_squadron(2, 1, 1, "fluyte", 1)
	mover.moved = true
	var context: Dictionary = {"model": _naval_interception_model, "interception_roll": 0.45}
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		[blockader, mover], Callable(), context
	)
	assert_true(bool(battles[0]["intercepted"]))
	assert_eq(int(battles[0]["attacker"]), 0)
	# The same roll misses a patrol's lower chance in the same waters.
	var patrol := _naval_interception_squadron(3, 0, 1, "sloop", 1)
	patrol.mission = FleetState.Mission.PATROL
	var other := _naval_interception_squadron(4, 1, 1, "fluyte", 1)
	other.moved = true
	var misses: Array[Dictionary] = NavalCombat.resolve_turn(
		[patrol, other], Callable(), context
	)
	assert_false(bool(misses[0]["intercepted"]))
	assert_eq(int(misses[0]["attacker"]), 1)

func test_a_defending_squadron_does_not_intercept() -> void:
	_setup_naval_interception()
	var defender := _naval_interception_squadron(1, 0, 0, "sloop", 1)
	defender.mission = FleetState.Mission.DEFEND
	var mover := _naval_interception_squadron(2, 1, 0, "fluyte", 1)
	mover.moved = true
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		[defender, mover], Callable(), {"interception_roll": 0.0}
	)
	assert_false(bool(battles[0]["intercepted"]))
	assert_eq(int(battles[0]["attacker"]), 1)

func test_only_the_station_holders_join_the_roll() -> void:
	_setup_naval_interception()
	var patrol := _naval_interception_squadron(1, 0, 0, "sloop", 1)
	patrol.mission = FleetState.Mission.PATROL
	var holding := _naval_interception_squadron(2, 0, 0, "ship_of_the_line", 2)
	holding.mission = FleetState.Mission.DEFEND
	var mover := _naval_interception_squadron(3, 1, 0, "carrack", 1)
	mover.moved = true
	# A Defend squadron's intercept ratings must not turn the patrol's 0.33 roll
	# into a 0.40 hit; the mover keeps the initiative in this battle.
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		[patrol, holding, mover], Callable(), {"interception_roll": 0.35}
	)
	assert_false(bool(battles[0]["intercepted"]))
	assert_eq(int(battles[0]["attacker"]), 1)
	assert_almost_eq(
		float(battles[0]["interception_chance"]), 0.5 * 4.0 / 6.0, 0.0001
	)

## Crown-tech query: `owner` holds Privateering Companies, nobody else does.
func _charter(owner: int) -> Callable:
	return func(crown: int, tech_id: String) -> bool:
		return crown == owner and tech_id == NavalInterception.PRIVATEERING_TECH

func test_privateers_multiply_the_intercept_score() -> void:
	_setup_naval_interception()
	var sloop := _naval_interception_squadron(1, 0, 0, "sloop", 1)
	var fluyte := _naval_interception_squadron(2, 1, 0, "fluyte", 1)
	var plain: float = NavalInterception.chance(
		[sloop], [fluyte], FleetState.Mission.PATROL
	)
	var chartered: float = NavalInterception.chance(
		[sloop], [fluyte], FleetState.Mission.PATROL, _charter(0)
	)
	assert_almost_eq(plain, 0.5 * 4.0 / 7.0, 0.0001)
	# Σintercept 4 × 1.25 = 5 against the same flee score of 3.
	assert_almost_eq(chartered, 0.5 * 5.0 / 8.0, 0.0001)
	assert_gt(chartered, plain)

func test_only_the_interceptors_charter_counts() -> void:
	_setup_naval_interception()
	var sloop := _naval_interception_squadron(1, 0, 0, "sloop", 1)
	var fluyte := _naval_interception_squadron(2, 1, 0, "fluyte", 1)
	# The target's own privateers never help the interceptor.
	assert_almost_eq(
		NavalInterception.chance(
			[sloop], [fluyte], FleetState.Mission.PATROL, _charter(1)
		),
		0.5 * 4.0 / 7.0,
		0.0001
	)
	# A crown without the tech gets the plain table.
	assert_almost_eq(
		NavalInterception.chance(
			[sloop], [fluyte], FleetState.Mission.PATROL, _charter(4)
		),
		0.5 * 4.0 / 7.0,
		0.0001
	)

func test_a_privateer_patrol_wins_a_roll_a_plain_one_misses() -> void:
	_setup_naval_interception()
	# 0.30 lies between the plain 4/14 and the chartered 5/16.
	var plain_patrol := _naval_interception_squadron(1, 0, 0, "sloop", 1)
	plain_patrol.mission = FleetState.Mission.PATROL
	var plain_mover := _naval_interception_squadron(2, 1, 0, "fluyte", 1)
	plain_mover.moved = true
	var plain: Array[Dictionary] = NavalCombat.resolve_turn(
		[plain_patrol, plain_mover], Callable(), {"interception_roll": 0.30}
	)
	assert_false(bool(plain[0]["intercepted"]))
	var chartered_patrol := _naval_interception_squadron(3, 0, 0, "sloop", 1)
	chartered_patrol.mission = FleetState.Mission.PATROL
	var chartered_mover := _naval_interception_squadron(4, 1, 0, "fluyte", 1)
	chartered_mover.moved = true
	var chartered: Array[Dictionary] = NavalCombat.resolve_turn(
		[chartered_patrol, chartered_mover],
		Callable(),
		{"interception_roll": 0.30, "has_tech": _charter(0)}
	)
	assert_true(bool(chartered[0]["intercepted"]))
	assert_eq(int(chartered[0]["attacker"]), 0)

## A crown in the full-AI observer answers from its own AI ledger: no human
## ledger resolves there, so the charter must still count (REQ-P2-03).
func test_the_observer_crown_earns_its_privateer_charter() -> void:
	_setup_naval_interception()
	var play := PlaySession.new()
	play.player_faction = 0
	play.observer_mode = true
	play.ai = AiState.new()
	play.ai.economy_for(0).tech_unlocked[NavalInterception.PRIVATEERING_TECH] = true
	var sloop := _naval_interception_squadron(1, 0, 0, "sloop", 1)
	var fluyte := _naval_interception_squadron(2, 1, 0, "fluyte", 1)
	assert_almost_eq(
		NavalInterception.chance(
			[sloop], [fluyte], FleetState.Mission.PATROL, play.has_tech
		),
		0.5 * 5.0 / 8.0,
		0.0001
	)

func test_the_dossier_reads_the_privateer_charter() -> void:
	_setup_naval_interception()
	var play := PlaySession.new()
	play.player_faction = 0
	play.model = _naval_interception_model
	var economy := EconomyController.new()
	economy.economy = PlayerEconomy.starting()
	play.economy = economy
	var fleet := _naval_interception_squadron(1, 0, 0, "sloop", 1)
	fleet.mission = FleetState.Mission.PATROL
	assert_false(MapPlayFleetMissions.note(play, fleet).contains("Privateers"))
	economy.economy.tech_unlocked[NavalInterception.PRIVATEERING_TECH] = true
	var note: String = MapPlayFleetMissions.note(play, fleet)
	assert_true(note.contains("On patrol"))
	assert_true(note.contains("Privateers"))
	assert_true(note.contains("+25%"))
	# A squadron in port can take no station, so the charter is not dangled.
	var docked := FleetState.in_port(2, 0, 0, ["home_1"], {"home_1": "fluyte"})
	assert_false(MapPlayFleetMissions.note(play, docked).contains("Privateers"))
	economy.free()

# --- test_naval_movement ---
## Sea-going fleet movement and docking (wiki: ships-and-naval, map-topology).

const naval_movement_NavalFixture = preload("res://tests/naval_fixture.gd")
var _naval_movement_model: MapModel = null

func _setup_naval_movement() -> void:
	_suite_setup = "naval_movement"
	_naval_movement_model = naval_movement_NavalFixture.build()


func test_province_sea_zones_lists_adjacent_water() -> void:
	_setup_naval_movement()
	assert_eq(NavalMovement.province_sea_zones(_naval_movement_model, 0), [0])
	assert_eq(NavalMovement.province_sea_zones(_naval_movement_model, 1), [1])
	assert_eq(NavalMovement.province_sea_zones(_naval_movement_model, 99), [])


func test_owned_provinces_by_zone() -> void:
	_setup_naval_movement()
	assert_eq(NavalMovement.owned_provinces_by_zone(_naval_movement_model, 0, 0), [0])
	assert_eq(NavalMovement.owned_provinces_by_zone(_naval_movement_model, 1, 0), [])
	assert_eq(NavalMovement.owned_provinces_by_zone(_naval_movement_model, 0, 1), [])


func test_sea_fleet_moves_one_adjacent_zone() -> void:
	_setup_naval_movement()
	var fleet := FleetState.at_sea(1, 0, 0)
	assert_eq(NavalMovement.destination_zones(_naval_movement_model, fleet), [1])

	var result: Dictionary = NavalMovement.apply_move(
		_naval_movement_model, fleet, FleetState.Location.AT_SEA, 1
	)

	assert_true(bool(result["ok"]))
	assert_eq(int(result["entered_zone"]), 1)
	assert_eq(fleet.sea_zone, 1)
	assert_eq(fleet.province, MapModel.NO_ID)
	assert_true(fleet.moved)


func test_same_zone_is_not_a_move() -> void:
	_setup_naval_movement()
	var fleet := FleetState.at_sea(1, 0, 0)
	var result: Dictionary = NavalMovement.apply_move(
		_naval_movement_model, fleet, FleetState.Location.AT_SEA, 0
	)
	assert_false(bool(result["ok"]))
	assert_eq(fleet.sea_zone, 0)
	assert_false(fleet.moved)


func test_fleet_may_move_only_once_per_turn() -> void:
	_setup_naval_movement()
	var fleet := FleetState.at_sea(1, 0, 0)
	NavalMovement.apply_move(_naval_movement_model, fleet, FleetState.Location.AT_SEA, 1)
	var second: Dictionary = NavalMovement.apply_move(
		_naval_movement_model, fleet, FleetState.Location.AT_SEA, 0
	)
	assert_false(bool(second["ok"]))
	assert_eq(fleet.sea_zone, 1)
	assert_true(String(second["reason"]).contains("already moved"))


func test_begin_turn_restores_the_move() -> void:
	_setup_naval_movement()
	var fleet := FleetState.at_sea(1, 0, 0)
	NavalMovement.apply_move(_naval_movement_model, fleet, FleetState.Location.AT_SEA, 1)
	var fleets: Array[FleetState] = [fleet]
	NavalMovement.begin_turn(fleets)
	assert_false(fleet.moved)
	var check: Dictionary = NavalMovement.can_move(
		_naval_movement_model, fleet, FleetState.Location.AT_SEA, 0
	)
	assert_true(bool(check["ok"]))


func test_docking_requires_ownership() -> void:
	_setup_naval_movement()
	var fleet := FleetState.at_sea(1, 0, 1)
	var result: Dictionary = NavalMovement.apply_move(
		_naval_movement_model, fleet, FleetState.Location.IN_PORT, 1
	)
	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("owns"))
	assert_eq(fleet.location, FleetState.Location.AT_SEA)


func test_docking_requires_adjacent_coast() -> void:
	_setup_naval_movement()
	var fleet := FleetState.at_sea(1, 0, 1)
	var result: Dictionary = NavalMovement.apply_move(
		_naval_movement_model, fleet, FleetState.Location.IN_PORT, 0
	)
	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("border"))


func test_fleet_docks_at_a_harbour() -> void:
	_setup_naval_movement()
	var fleet := FleetState.at_sea(1, 0, 0)
	assert_eq(NavalMovement.dockable_provinces(_naval_movement_model, fleet), [0])

	var result: Dictionary = NavalMovement.apply_move(
		_naval_movement_model, fleet, FleetState.Location.IN_PORT, 0
	)

	assert_true(bool(result["ok"]))
	assert_eq(int(result["entered_zone"]), -1)
	assert_eq(fleet.location, FleetState.Location.IN_PORT)
	assert_eq(fleet.province, 0)
	assert_eq(fleet.sea_zone, MapModel.NO_ID)


func test_port_fleet_undocks_into_adjacent_zone() -> void:
	_setup_naval_movement()
	# Province 1 is a non-capital port, so this is a sea-going squadron.
	var fleet := FleetState.in_port(2, 0, 1)
	assert_eq(NavalMovement.destination_zones(_naval_movement_model, fleet), [1])

	var result: Dictionary = NavalMovement.apply_move(
		_naval_movement_model, fleet, FleetState.Location.AT_SEA, 1
	)

	assert_true(bool(result["ok"]))
	assert_eq(fleet.location, FleetState.Location.AT_SEA)
	assert_eq(fleet.sea_zone, 1)
	assert_eq(fleet.province, MapModel.NO_ID)


func test_port_fleet_cannot_move_to_another_port() -> void:
	_setup_naval_movement()
	var fleet := FleetState.in_port(2, 0, 1)
	var result: Dictionary = NavalMovement.apply_move(
		_naval_movement_model, fleet, FleetState.Location.IN_PORT, 1
	)
	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("already in port"))


func test_province_without_a_harbour_cannot_be_entered() -> void:
	_setup_naval_movement()
	_naval_movement_model.provinces[0].port_tile = Vector2i(-1, -1)
	var fleet := FleetState.at_sea(1, 0, 0)
	assert_false(NavalMovement.has_harbour(_naval_movement_model, 0))
	assert_eq(NavalMovement.dockable_provinces(_naval_movement_model, fleet), [])

	var result: Dictionary = NavalMovement.apply_move(
		_naval_movement_model, fleet, FleetState.Location.IN_PORT, 0
	)
	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("harbour"))


func test_unknown_zone_is_rejected() -> void:
	_setup_naval_movement()
	var fleet := FleetState.at_sea(1, 0, 0)
	var result: Dictionary = NavalMovement.apply_move(
		_naval_movement_model, fleet, FleetState.Location.AT_SEA, 99
	)
	assert_false(bool(result["ok"]))
	assert_eq(fleet.sea_zone, 0)


func test_valid_destinations_match_the_location() -> void:
	_setup_naval_movement()
	var sea: Dictionary = NavalMovement.valid_destinations(
		_naval_movement_model, FleetState.at_sea(1, 0, 0)
	)
	assert_eq(sea["sea_zones"], [1])
	assert_eq(sea["provinces"], [0])

	var port: Dictionary = NavalMovement.valid_destinations(
		_naval_movement_model, FleetState.in_port(2, 0, 1)
	)
	assert_eq(port["sea_zones"], [1])
	assert_eq(port["provinces"], [])


func test_the_home_fleet_never_sails() -> void:
	_setup_naval_movement()
	var home := FleetState.in_port(2, 0, 0)
	assert_true(NavalMovement.is_home_fleet(_naval_movement_model, home))
	assert_eq(NavalMovement.destination_zones(_naval_movement_model, home), [])

	var result: Dictionary = NavalMovement.apply_move(
		_naval_movement_model, home, FleetState.Location.AT_SEA, 0
	)

	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("home fleet"))
	assert_eq(home.location, FleetState.Location.IN_PORT)
	assert_eq(home.province, 0)


func test_docking_at_the_capital_merges_into_the_home_fleet() -> void:
	_setup_naval_movement()
	var home := FleetState.in_port(2, 0, 0, ["ship_a"], {"ship_a": "carrack"})
	var incoming := FleetState.at_sea(3, 0, 0, ["ship_b"], {"ship_b": "sloop"})
	var roster: Array[FleetState] = [home, incoming]

	var dock: Dictionary = NavalMovement.apply_move(
		_naval_movement_model, incoming, FleetState.Location.IN_PORT, 0
	)
	var merge: Dictionary = NavalMovement.merge_into_home(_naval_movement_model, roster, incoming)
	var merged: FleetState = merge.get("fleet") as FleetState

	assert_true(bool(dock["ok"]))
	assert_eq(merged, home)
	assert_eq(roster.size(), 1)
	assert_eq(home.hulls, ["ship_a", "ship_b"], "instance ids survive in order")
	assert_eq(home.type_of("ship_b"), "sloop")


func test_merging_never_duplicates_a_hull_instance() -> void:
	_setup_naval_movement()
	var home := FleetState.in_port(2, 0, 0, ["ship_a"], {"ship_a": "carrack"})
	var incoming := FleetState.at_sea(3, 0, 0, ["ship_a", "ship_b"], {"ship_b": "fluyte"})
	var roster: Array[FleetState] = [home, incoming]

	NavalMovement.apply_move(_naval_movement_model, incoming, FleetState.Location.IN_PORT, 0)
	NavalMovement.merge_into_home(_naval_movement_model, roster, incoming)

	assert_eq(home.hulls, ["ship_a", "ship_b"])
	assert_eq(home.count_of_type("carrack"), 1)


func test_docking_at_a_non_capital_port_does_not_merge() -> void:
	_setup_naval_movement()
	_naval_movement_model.provinces[1].owner = 0
	var home := FleetState.in_port(2, 0, 0)
	var incoming := FleetState.at_sea(3, 0, 1)
	var roster: Array[FleetState] = [home, incoming]

	NavalMovement.apply_move(_naval_movement_model, incoming, FleetState.Location.IN_PORT, 1)

	assert_false(NavalMovement.is_home_fleet(_naval_movement_model, incoming))
	var merge: Dictionary = NavalMovement.merge_into_home(_naval_movement_model, roster, incoming)
	assert_null(merge.get("fleet"))
	assert_eq(roster.size(), 2)


func test_fleet_state_defaults_to_one_hull() -> void:
	_setup_naval_movement()
	var sea := FleetState.at_sea(4, 2, 0)
	assert_eq(sea.ship_count(), 1)
	assert_eq(sea.hulls, ["ship_4"])
	assert_true(sea.is_at_sea())

	var port := FleetState.in_port(5, 1, 0, ["ship_a", "ship_b"])
	assert_eq(port.ship_count(), 2)
	assert_true(port.is_in_port())
	assert_false(port.moved)


func test_fleet_hulls_keep_their_catalog_types() -> void:
	_setup_naval_movement()
	var fleet := FleetState.at_sea(6, 0, 0, ["ship_6"], {"ship_6": "sloop"})
	assert_eq(fleet.type_of("ship_6"), "sloop")
	# Unmapped and unknown hulls count as the default carrack.
	assert_eq(fleet.type_of("ship_unknown"), "carrack")
	var legacy := FleetState.in_port(7, 0, 0, ["ship_7"])
	assert_eq(legacy.type_of("ship_7"), "carrack")
	assert_eq(legacy.count_of_type("carrack"), 1)


func test_fleet_hulls_can_be_added_removed_and_summarised() -> void:
	_setup_naval_movement()
	var fleet := FleetState.at_sea(8, 0, 0, ["ship_8"], {"ship_8": "carrack"})
	fleet.add_hull("ship_9", "galleon")
	fleet.add_hull("ship_9", "sloop")
	assert_eq(fleet.ship_count(), 2)
	assert_eq(fleet.count_of_type("galleon"), 1)
	assert_eq(fleet.hull_summary(), "1 Carrack · 1 Galleon")
	assert_true(fleet.remove_hull("ship_8"))
	assert_false(fleet.remove_hull("ship_8"))
	assert_eq(fleet.hull_summary(), "1 Galleon")
	assert_true(fleet.is_afloat())
	fleet.remove_hull("ship_9")
	assert_false(fleet.is_afloat())


# --- naval transport (wiki: ships-and-naval § Naval transport) ----------------


func _naval_movement_transport_pair() -> Array:
	var fleet := FleetState.in_port(3, 0, 0, ["ship_3"])
	var army := ArmyState.muster(7, 0, 0, false, ["pikemen"], 700)
	return [army, fleet]


func test_one_hull_carries_one_regiment() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	assert_eq(NavalTransport.capacity(fleet), 1)
	assert_true(bool(NavalTransport.can_embark(_naval_movement_model, army, fleet)["ok"]))
	assert_true(bool(NavalTransport.embark(_naval_movement_model, army, fleet)["ok"]))
	assert_eq(army.province, MapModel.NO_ID)
	assert_true(army.moved)
	assert_eq(army.embarked_fleet, fleet.id)
	assert_eq(fleet.embarked_army, army.id)


func test_transport_capacity_refuses_an_army_larger_than_the_squadron() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var fleet: FleetState = pair[1]
	var army := ArmyState.muster(8, 0, 0, false, ["pikemen", "pikemen"], 800)
	var check: Dictionary = NavalTransport.can_embark(_naval_movement_model, army, fleet)
	assert_false(bool(check["ok"]))
	assert_eq(
		String(check["reason"]),
		"The squadron has 1 hull and cannot carry 2 regiments.",
		"one hull reads singular"
	)


func test_the_home_army_never_boards() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var fleet: FleetState = pair[1]
	var home := ArmyState.muster(8, 0, 0, true, ["pikemen"], 800)
	var check: Dictionary = NavalTransport.can_embark(_naval_movement_model, home, fleet)
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("Home Army"))


func test_boarding_needs_a_fleet_in_this_port() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var elsewhere := FleetState.in_port(4, 0, 1, ["ship_4"])
	var check: Dictionary = NavalTransport.can_embark(_naval_movement_model, army, elsewhere)
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("not in this port"))


func test_an_embarked_army_lands_on_an_owned_coast() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_naval_movement_model, army, fleet)
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 0
	fleet.province = MapModel.NO_ID
	assert_true(bool(NavalTransport.disembark(_naval_movement_model, army, fleet, 0)["ok"]))
	assert_eq(army.province, 0)
	assert_eq(army.embarked_fleet, -1)
	assert_eq(fleet.embarked_army, -1)
	assert_true(army.moved)


func test_a_hostile_landing_needs_a_beachhead() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_naval_movement_model, army, fleet)
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 1
	fleet.province = MapModel.NO_ID
	var check: Dictionary = NavalTransport.disembark(_naval_movement_model, army, fleet, 1)
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("beachhead"))


## A marked beachhead opens the hostile coast on the following turn only, and
## the landing consumes it (wiki: ships-and-naval § Missions and Movement).
func test_beachhead_opens_a_hostile_coast_on_the_following_turn() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_naval_movement_model, army, fleet)
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 1
	fleet.province = MapModel.NO_ID
	assert_eq(NavalTransport.hostile_coasts(_naval_movement_model, fleet), [1])
	var marked: Dictionary = NavalTransport.establish_beachhead(_naval_movement_model, fleet, 1, 5)
	assert_true(bool(marked["ok"]))
	assert_true(fleet.moved)
	assert_eq(fleet.beachhead_province, 1)
	assert_eq(fleet.beachhead_turn, 5)
	assert_false(bool(NavalTransport.beachhead_ready(fleet, 5)))
	assert_true(bool(NavalTransport.beachhead_ready(fleet, 6)))
	assert_eq(NavalTransport.landing_provinces(_naval_movement_model, fleet, 5), [])
	assert_eq(NavalTransport.landing_provinces(_naval_movement_model, fleet, 6), [1])
	# A site already held names its own wait rather than asking for a beachhead.
	var early: Dictionary = NavalTransport.disembark(_naval_movement_model, army, fleet, 1, 5)
	assert_false(bool(early["ok"]))
	assert_true(String(early["reason"]).contains("opens next turn"))
	assert_false(bool(NavalTransport.disembark(_naval_movement_model, army, fleet, 1, 5)["ok"]))
	assert_true(bool(NavalTransport.disembark(_naval_movement_model, army, fleet, 1, 6)["ok"]))
	assert_eq(army.province, 1)
	assert_eq(army.embarked_fleet, -1)
	assert_true(army.moved)
	assert_false(fleet.has_beachhead())
	# The landing is an invasion: the army is a contestant in the province.
	var armies: Array[ArmyState] = [army]
	assert_eq(ArmyCombat.contested_provinces(_naval_movement_model, armies), [1])


func test_beachhead_lasts_one_full_turn_then_expires() -> void:
	_setup_naval_movement()
	var fleet := FleetState.at_sea(3, 0, 1, ["ship_3"])
	fleet.moved = false
	assert_true(bool(NavalTransport.establish_beachhead(_naval_movement_model, fleet, 1, 5)["ok"]))
	var fleets: Array[FleetState] = [fleet]
	NavalTransport.expire_beachheads(fleets, 5)
	assert_true(fleet.has_beachhead())
	NavalMovement.begin_turn(fleets)
	assert_false(fleet.moved)
	assert_true(bool(NavalTransport.beachhead_ready(fleet, 6)))
	NavalTransport.expire_beachheads(fleets, 6)
	assert_false(fleet.has_beachhead())


## A marker whose coast changes hands or whose war ends has no hostile landing
## left; the rules gate the landing, so the marker must not promise one.
func test_a_beachhead_target_must_stay_a_hostile_shore() -> void:
	_setup_naval_movement()
	var fleet := FleetState.at_sea(3, 0, 1, ["ship_3"])
	fleet.moved = false
	assert_true(bool(NavalTransport.establish_beachhead(_naval_movement_model, fleet, 1, 5)["ok"]))
	assert_true(NavalTransport.beachhead_target_valid(_naval_movement_model, fleet))
	_naval_movement_model.province_data(1).owner = 0
	assert_false(NavalTransport.beachhead_target_valid(_naval_movement_model, fleet))
	_naval_movement_model.province_data(1).owner = 1
	var peaceful := func(_a: int, _b: int) -> bool: return false
	assert_false(NavalTransport.beachhead_target_valid(_naval_movement_model, fleet, peaceful))
	assert_true(NavalTransport.beachhead_target_valid(_naval_movement_model, fleet))
	fleet.sea_zone = 0
	assert_false(NavalTransport.beachhead_target_valid(_naval_movement_model, fleet))
	assert_false(NavalTransport.beachhead_target_valid(null, fleet))
	assert_false(NavalTransport.beachhead_target_valid(_naval_movement_model, null))


func test_beachhead_refusals_cover_each_gate() -> void:
	_setup_naval_movement()
	var own_coast := FleetState.at_sea(3, 0, 0, ["ship_3"])
	assert_false(bool(NavalTransport.can_establish_beachhead(_naval_movement_model, own_coast, 0)["ok"]))
	var moved := FleetState.at_sea(4, 0, 1, ["ship_4"])
	moved.moved = true
	assert_true(String(
		NavalTransport.can_establish_beachhead(_naval_movement_model, moved, 1)["reason"]
	).contains("already moved"))
	var docked := FleetState.in_port(5, 0, 0, ["ship_5"])
	assert_true(String(
		NavalTransport.can_establish_beachhead(_naval_movement_model, docked, 1)["reason"]
	).contains("at sea"))
	var empty := FleetState.at_sea(6, 0, 1, [] as Array[String])
	empty.hulls = []
	empty.hull_types = {}
	assert_true(String(
		NavalTransport.can_establish_beachhead(_naval_movement_model, empty, 1)["reason"]
	).contains("no hulls"))
	var far := FleetState.at_sea(7, 0, 0, ["ship_7"])
	assert_true(String(
		NavalTransport.can_establish_beachhead(_naval_movement_model, far, 1)["reason"]
	).contains("border"))
	var peaceful := func(_a: int, _b: int) -> bool: return false
	assert_true(String(
		NavalTransport.can_establish_beachhead(_naval_movement_model, own_coast, 1, 0, peaceful)["reason"]
	).contains("declared war"))
	assert_false(bool(NavalTransport.can_establish_beachhead(null, own_coast, 1)["ok"]))
	assert_true(String(
		NavalTransport.can_establish_beachhead(_naval_movement_model, own_coast, 99)["reason"]
	).contains("not a province"))
	assert_false(bool(NavalTransport.establish_beachhead(_naval_movement_model, moved, 1, 0)["ok"]))
	assert_false(bool(NavalTransport.beachhead_ready(null, 0)))
	assert_false(NavalTransport.beachhead_allows(null, null, 1))
	assert_false(NavalTransport.beachhead_allows(_naval_movement_model, null, 1))
	assert_eq(NavalTransport.hostile_coasts(null, own_coast).size(), 0)
	assert_eq(NavalTransport.hostile_coasts(_naval_movement_model, own_coast).size(), 0)
	var own_mark := FleetState.at_sea(8, 0, 0, ["ship_8"])
	own_mark.beachhead_province = 0
	own_mark.beachhead_turn = 4
	assert_false(NavalTransport.beachhead_allows(_naval_movement_model, own_mark, 0, 5))
	var mixed: Array[FleetState] = [null]
	NavalTransport.expire_beachheads(mixed, 5)


func test_landing_requires_the_fleet_to_border_the_coast() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_naval_movement_model, army, fleet)
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 1
	fleet.province = MapModel.NO_ID
	var check: Dictionary = NavalTransport.disembark(_naval_movement_model, army, fleet, 0)
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("border"))


func test_landing_provinces_follow_the_sea_zone() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_naval_movement_model, army, fleet)
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 0
	fleet.province = MapModel.NO_ID
	assert_eq(NavalTransport.landing_provinces(_naval_movement_model, fleet), [0])
	fleet.sea_zone = 1
	assert_eq(NavalTransport.landing_provinces(_naval_movement_model, fleet), [])


func test_breaking_up_a_hull_cannot_strand_the_troops() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_naval_movement_model, army, fleet)
	assert_false(bool(NavalTransport.can_scrap(fleet, army)["ok"]))
	fleet.add_hull("ship_5")
	assert_true(bool(NavalTransport.can_scrap(fleet, army)["ok"]))


func test_transport_state_survives_a_save_round_trip() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_naval_movement_model, army, fleet)
	fleet.beachhead_province = 1
	fleet.beachhead_turn = 5
	var saved_army: ArmyState = ArmyState.from_dict(army.to_dict())
	var saved_fleet: FleetState = FleetState.from_dict(fleet.to_dict())
	assert_eq(saved_army.embarked_fleet, fleet.id)
	assert_eq(saved_army.province, MapModel.NO_ID)
	assert_eq(saved_fleet.embarked_army, army.id)
	assert_eq(saved_fleet.beachhead_province, 1)
	assert_eq(saved_fleet.beachhead_turn, 5)


func _transport_layer(army: ArmyState) -> ArmyLayer:
	var layer := ArmyLayer.new()
	layer.model = _naval_movement_model
	var armies: Array[ArmyState] = [army]
	layer.armies = armies
	layer.regions.set_region(_naval_movement_model.region_id, layer.armies)
	return layer


func test_an_embarked_army_follows_its_fleet_between_regions() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_naval_movement_model, army, fleet)
	var layer: ArmyLayer = _transport_layer(army)
	ArmyTransport.move_to_region(layer, army.id, 1)
	assert_eq(layer.armies.size(), 0)
	var destination: Array[ArmyState] = []
	destination.assign(layer.regions.value(1, []))
	assert_eq(destination.size(), 1)
	assert_true(destination[0] == army)
	layer.free()


func test_a_sunk_squadrons_army_leaves_the_roster() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_naval_movement_model, army, fleet)
	var layer: ArmyLayer = _transport_layer(army)
	var lost: Array[ArmyState] = ArmyTransport.drop_lost(layer, {})
	assert_eq(lost.size(), 1)
	assert_true(lost[0] == army)
	assert_eq(layer.armies.size(), 0)
	layer.free()


func test_a_live_squadron_keeps_its_army() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_naval_movement_model, army, fleet)
	var layer: ArmyLayer = _transport_layer(army)
	var live: Dictionary = {}
	live[army.id] = fleet.id
	var lost: Array[ArmyState] = ArmyTransport.drop_lost(layer, live)
	assert_eq(lost.size(), 0)
	assert_eq(layer.armies.size(), 1)
	layer.free()


func test_embarkation_refusals_cover_each_gate() -> void:
	_setup_naval_movement()
	var fleet := FleetState.in_port(3, 0, 0, ["ship_3"])
	var army := ArmyState.muster(7, 0, 0, false, ["pikemen"], 700)
	assert_false(bool(NavalTransport.can_embark(_naval_movement_model, null, fleet)["ok"]))
	assert_false(bool(NavalTransport.can_embark(_naval_movement_model, army, null)["ok"]))
	var foreign := ArmyState.muster(8, 1, 0, false, ["pikemen"], 800)
	assert_false(bool(NavalTransport.can_embark(_naval_movement_model, foreign, fleet)["ok"]))
	var empty := ArmyState.muster(9, 0, 0, false, [], 900)
	assert_false(bool(NavalTransport.can_embark(_naval_movement_model, empty, fleet)["ok"]))
	army.embarked_fleet = 5
	assert_false(bool(NavalTransport.can_embark(_naval_movement_model, army, fleet)["ok"]))
	army.embarked_fleet = -1
	army.moved = true
	assert_false(bool(NavalTransport.can_embark(_naval_movement_model, army, fleet)["ok"]))
	army.moved = false
	fleet.location = FleetState.Location.AT_SEA
	assert_false(bool(NavalTransport.can_embark(_naval_movement_model, army, fleet)["ok"]))
	fleet.location = FleetState.Location.IN_PORT
	fleet.moved = true
	assert_false(bool(NavalTransport.can_embark(_naval_movement_model, army, fleet)["ok"]))
	fleet.moved = false
	fleet.embarked_army = 9
	assert_false(bool(NavalTransport.can_embark(_naval_movement_model, army, fleet)["ok"]))
	fleet.embarked_army = -1
	assert_false(bool(NavalTransport.can_embark(null, army, fleet)["ok"]))


func test_landing_refusals_cover_each_gate() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_naval_movement_model, army, fleet)
	assert_false(bool(NavalTransport.can_disembark(_naval_movement_model, null, fleet, 0)["ok"]))
	assert_false(bool(NavalTransport.can_disembark(_naval_movement_model, army, null, 0)["ok"]))
	var outsider := ArmyState.muster(8, 0, 0, false, ["pikemen"], 800)
	assert_false(bool(NavalTransport.can_disembark(_naval_movement_model, outsider, fleet, 0)["ok"]))
	assert_false(bool(NavalTransport.can_disembark(_naval_movement_model, army, fleet, 99)["ok"]))
	assert_false(bool(NavalTransport.can_disembark(_naval_movement_model, army, fleet, 1)["ok"]))
	_naval_movement_model.province_data(1).owner = 0
	assert_false(bool(NavalTransport.can_disembark(_naval_movement_model, army, fleet, 1)["ok"]))
	_naval_movement_model.province_data(1).owner = 1
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 1
	fleet.province = MapModel.NO_ID
	assert_false(bool(NavalTransport.can_disembark(_naval_movement_model, army, fleet, 0)["ok"]))
	fleet.sea_zone = 0
	assert_true(bool(NavalTransport.can_disembark(_naval_movement_model, army, fleet, 0)["ok"]))


func test_port_landing_and_scrap_gates() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_naval_movement_model, army, fleet)
	assert_eq(NavalTransport.landing_provinces(_naval_movement_model, fleet), [0])
	assert_eq(NavalTransport.landing_provinces(_naval_movement_model, null), [])
	assert_eq(NavalTransport.landing_provinces(_naval_movement_model, FleetState.at_sea(4, 0, 0)), [0])
	assert_true(bool(NavalTransport.can_scrap(null, army)["ok"]))
	assert_false(bool(NavalTransport.can_scrap(fleet, null)["ok"]))


func test_transport_layer_lookups_and_refusals() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	var layer: ArmyLayer = _transport_layer(army)
	assert_null(ArmyTransport.army_by_id(layer, -1))
	assert_null(ArmyTransport.army_by_id(layer, 999))
	assert_true(ArmyTransport.army_by_id(layer, army.id) == army)
	assert_eq(ArmyTransport.region_of(layer, army), _naval_movement_model.region_id)
	assert_false(bool(ArmyTransport.embark(layer, army, FleetState.at_sea(3, 0, 0))["ok"]))
	assert_false(bool(ArmyTransport.disembark(layer, null, 0)["ok"]))
	assert_false(bool(ArmyTransport.disembark(layer, fleet, 0)["ok"]))
	ArmyTransport.move_to_region(layer, 999, 1)
	ArmyTransport.remove_from(layer, army, _naval_movement_model.region_id)
	assert_eq(layer.armies.size(), 0)
	layer.free()


func test_transport_layer_same_region_move_is_a_no_op() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_naval_movement_model, army, fleet)
	var layer: ArmyLayer = _transport_layer(army)
	ArmyTransport.move_to_region(layer, army.id, _naval_movement_model.region_id)
	assert_eq(layer.armies.size(), 1)
	ArmyTransport.move_to_region(layer, army.id, 1)
	assert_eq(ArmyTransport.region_of(layer, army), 1)
	layer.free()


func test_drop_lost_leaves_unembarked_armies_alone() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_naval_movement_model, army, fleet)
	var grounded := ArmyState.muster(11, 0, 0, false, ["pikemen"], 1100)
	var layer: ArmyLayer = _transport_layer(army)
	layer.armies.append(grounded)
	var lost: Array[ArmyState] = ArmyTransport.drop_lost(layer, {})
	assert_eq(lost.size(), 1)
	assert_eq(layer.armies.size(), 1)
	assert_true(layer.armies[0] == grounded)
	layer.free()


## The squadron's own roster names the troops it carries; the army's
## back-pointer may lag a merge, and that must not block the landing
## (wiki: ships-and-naval § Naval transport; DR-20261109-17).
func test_an_army_lands_after_its_squadron_was_merged() -> void:
	_setup_naval_movement()
	var home := FleetState.in_port(2, 0, 0, ["ship_a"], {"ship_a": "fluyte"})
	var incoming := FleetState.at_sea(3, 0, 0, ["ship_b"], {"ship_b": "fluyte"})
	var army := ArmyState.create(7, 0, 0, false, ["unit_7"], {"unit_7": "pikemen"})
	army.embarked_fleet = incoming.id
	incoming.embarked_army = army.id
	var roster: Array[FleetState] = [home, incoming]

	NavalMovement.apply_move(_naval_movement_model, incoming, FleetState.Location.IN_PORT, 0)
	var merge: Dictionary = NavalMovement.merge_into_home(_naval_movement_model, roster, incoming)
	var merged: FleetState = merge.get("fleet") as FleetState

	assert_eq(merged.embarked_army, army.id, "the home fleet keeps the troops")
	assert_eq(army.embarked_fleet, incoming.id, "the army's own pointer lags")
	var check: Dictionary = NavalTransport.can_disembark(_naval_movement_model, army, merged, 0)
	assert_true(bool(check.get("ok", false)), String(check.get("reason", "")))


## One squadron carries one army: a merge keeps the target's troops and reports
## the surplus army so the layer can land it at the port (wiki: ships-and-naval
## § Naval transport).
func test_a_merge_keeps_one_army_and_reports_the_other() -> void:
	_setup_naval_movement()
	var home := FleetState.in_port(2, 0, 0, ["ship_a"], {"ship_a": "fluyte"})
	var incoming := FleetState.at_sea(3, 0, 0, ["ship_b"], {"ship_b": "fluyte"})
	home.embarked_army = 10
	incoming.embarked_army = 11
	var roster: Array[FleetState] = [home, incoming]

	NavalMovement.apply_move(_naval_movement_model, incoming, FleetState.Location.IN_PORT, 0)
	var merge: Dictionary = NavalMovement.merge_into_home(_naval_movement_model, roster, incoming)

	assert_eq(home.embarked_army, 10, "the moored army stays aboard")
	assert_eq(int(merge["displaced"]), 11, "the surplus army is reported")
	assert_eq(incoming.embarked_army, -1, "the merged-away squadron is emptied")

# --- test_naval_raid ---
## Cargo raids by patrol/blockade squadrons (wiki: ships-and-naval § Trade and
## Transport Interception; DR-20261109-16).

const naval_raid_NavalFixture = preload("res://tests/naval_fixture.gd")
var _naval_raid_model: MapModel = null

func _setup_naval_raid() -> void:
	_suite_setup = "naval_raid"
	_naval_raid_model = naval_raid_NavalFixture.build()


func _naval_raid_fleet(id: int, owner: int, zone: int, types: Array) -> FleetState:
	var fleet := FleetState.at_sea(id, owner, zone)
	var hull_ids: Array[String] = []
	var hull_types: Dictionary = {}
	for index in types.size():
		var hull_id: String = "ship_%d_%d" % [id, index]
		hull_ids.append(hull_id)
		hull_types[hull_id] = types[index]
	fleet.set_hulls(hull_ids, hull_types)
	return fleet


func _naval_raid_raider(mission: int = FleetState.Mission.PATROL) -> FleetState:
	var fleet := FleetState.at_sea(1, 1, 0, ["raider_1"], {"raider_1": "frigate"})
	fleet.mission = mission
	return fleet


func test_a_patrol_raider_skims_a_share_of_the_imports() -> void:
	_setup_naval_raid()
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _naval_raid_raider()
	var result: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, raider], 0, home, {"grain": 10}, Callable(), 1, 1, 0.0
	)
	assert_true(bool(result["ok"]))
	assert_gt(int(result["lost_total"]), 0)
	assert_gt(int((result["losses"] as Dictionary)["grain"]), 0)
	assert_between(float(result["efficiency"]), NavalRaid.MIN_EFFICIENCY, NavalRaid.MAX_EFFICIENCY)
	assert_almost_eq(float(result["chance"]), 0.5 * 5.0 / 8.0, 0.0001)


func test_escorts_cut_the_raid_chance() -> void:
	_setup_naval_raid()
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _naval_raid_raider()
	var alone: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, raider], 0, home, {"grain": 10}, Callable(), 1, 1, 0.99
	)
	home.add_hull("home_2", "sloop")
	var escorted: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, raider], 0, home, {"grain": 10}, Callable(), 1, 1, 0.99
	)
	assert_lt(float(escorted["chance"]), float(alone["chance"]))
	assert_false(bool(escorted["ok"]))


func test_peace_and_distant_raiders_do_not_raid() -> void:
	_setup_naval_raid()
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _naval_raid_raider()
	var peace := func(_a: int, _b: int) -> bool: return false
	assert_false(bool(NavalRaid.resolve(
		_naval_raid_model, [home, raider], 0, home, {"grain": 5}, peace, 1, 1, 0.0
	)["ok"]))
	raider.sea_zone = 1
	assert_false(bool(NavalRaid.resolve(
		_naval_raid_model, [home, raider], 0, home, {"grain": 5}, Callable(), 1, 1, 0.0
	)["ok"]))
	assert_false(bool(NavalRaid.resolve(
		_naval_raid_model, [home, raider], 0, null, {"grain": 5}, Callable(), 1, 1, 0.0
	)["ok"]))
	assert_false(bool(NavalRaid.resolve(
		_naval_raid_model, [home, raider], 0, home, {}, Callable(), 1, 1, 0.0
	)["ok"]))


func test_a_blockade_raider_earns_the_bonus() -> void:
	_setup_naval_raid()
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var patrol := _naval_raid_raider()
	var blockade := _naval_raid_raider(FleetState.Mission.BLOCKADE)
	blockade.blockade_province = 0
	var patrolled: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, patrol], 0, home, {"grain": 10}, Callable(), 1, 1, 0.99
	)
	var stopped: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, blockade], 0, home, {"grain": 10}, Callable(), 1, 1, 0.99
	)
	assert_gt(float(stopped["chance"]), float(patrolled["chance"]))
	assert_almost_eq(
		float(stopped["chance"]), float(patrolled["chance"]) * NavalRaid.BLOCKADE_BONUS,
		0.0001
	)


func test_privateers_improve_the_raid_chance() -> void:
	_setup_naval_raid()
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _naval_raid_raider()
	var plain: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, raider], 0, home, {"grain": 10}, Callable(), 1, 1, 0.99
	)
	var charter := func(owner: int, tech_id: String) -> bool:
		return owner == 1 and tech_id == NavalInterception.PRIVATEERING_TECH
	var chartered: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, raider], 0, home, {"grain": 10}, Callable(), 1, 1, 0.99, charter
	)
	assert_almost_eq(float(plain["chance"]), 0.5 * 5.0 / 8.0, 0.0001)
	# Σintercept 5 × 1.25 = 6.25 against the same flee score of 3.
	assert_almost_eq(float(chartered["chance"]), 0.5 * 6.25 / 9.25, 0.0001)
	assert_gt(float(chartered["chance"]), float(plain["chance"]))


## In the full-AI observer every crown answers from its AI ledger; the human
## ledger is frozen and must not answer for the observed crown (REQ-P2-03).
func test_the_observer_answers_tech_from_each_crowns_ledger() -> void:
	_setup_naval_raid()
	var play := PlaySession.new()
	play.player_faction = 0
	play.observer_mode = true
	play.ai = AiState.new()
	var economy := EconomyController.new()
	economy.economy = PlayerEconomy.starting()
	play.economy = economy
	economy.economy.tech_unlocked[NavalInterception.PRIVATEERING_TECH] = true
	assert_false(
		play.has_tech(0, NavalInterception.PRIVATEERING_TECH),
		"the human ledger does not resolve in the observer"
	)
	play.ai.economy_for(0).tech_unlocked[NavalInterception.PRIVATEERING_TECH] = true
	assert_true(play.has_tech(0, NavalInterception.PRIVATEERING_TECH))
	assert_false(play.has_tech(1, NavalInterception.PRIVATEERING_TECH))
	play.ai.economy_for(1).tech_unlocked[NavalInterception.PRIVATEERING_TECH] = true
	assert_true(play.has_tech(1, NavalInterception.PRIVATEERING_TECH))
	assert_false(play.has_tech(2, NavalInterception.PRIVATEERING_TECH))
	economy.free()


func test_the_session_answers_tech_for_the_human_and_rivals() -> void:
	_setup_naval_raid()
	var play := PlaySession.new()
	play.player_faction = 0
	play.ai = AiState.new()
	assert_false(play.has_tech(0, NavalInterception.PRIVATEERING_TECH))
	var economy := EconomyController.new()
	economy.economy = PlayerEconomy.starting()
	play.economy = economy
	economy.economy.tech_unlocked[NavalInterception.PRIVATEERING_TECH] = true
	assert_true(play.has_tech(0, NavalInterception.PRIVATEERING_TECH))
	assert_false(play.has_tech(1, NavalInterception.PRIVATEERING_TECH))
	play.ai.economy_for(1).tech_unlocked[NavalInterception.PRIVATEERING_TECH] = true
	assert_true(play.has_tech(1, NavalInterception.PRIVATEERING_TECH))
	assert_false(play.has_tech(0, ""))
	economy.free()


func test_losses_never_exceed_the_imports() -> void:
	_setup_naval_raid()
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _naval_raid_raider()
	var result: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, raider], 0, home, {"grain": 1}, Callable(), 1, 1, 0.0
	)
	assert_eq(int(result["lost_total"]), 1)
	assert_eq(int((result["losses"] as Dictionary)["grain"]), 1)


func test_a_blockade_bonus_does_not_cross_zones() -> void:
	_setup_naval_raid()
	# Both coasts answer to the victim, so both zones border its shore.
	_naval_raid_model.province_data(1).owner = 0
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var patrol := _naval_raid_fleet(1, 1, 1, ["sloop"])
	patrol.mission = FleetState.Mission.PATROL
	var blockader := _naval_raid_fleet(2, 1, 0, ["sloop"])
	blockader.mission = FleetState.Mission.BLOCKADE
	blockader.blockade_province = 0
	var lone: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, patrol], 0, home, {"grain": 10}, Callable(), 1, 1, 0.3,
		Callable(), 0.99
	)
	assert_false(bool(lone["ok"]), "a lone patrol in the far zone misses at 0.30")
	var both: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, patrol, blockader], 0, home, {"grain": 10}, Callable(), 1, 1, 0.3,
		Callable(), 0.99
	)
	assert_true(bool(both["ok"]))
	assert_eq(int(both["zone"]), 0, "the blockading squadron raids in its own zone")
	assert_almost_eq(
		float(both["chance"]),
		NavalInterception.chance([blockader], [home], FleetState.Mission.PATROL)
		* NavalRaid.BLOCKADE_BONUS,
		0.0001
	)


func test_the_market_reports_this_turns_imports() -> void:
	_setup_naval_raid()
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.treasury = 5000
	assert_true(bool(market.buy(economy, "grain", 3)["ok"]))
	assert_eq(int(market.imports_this_turn().get("grain", 0)), 3)
	assert_eq(market.bought_units(), 3)


func test_the_map_raid_pass_takes_the_losses_from_the_ledger() -> void:
	_setup_naval_raid()
	var play := PlaySession.new()
	play.model = _naval_raid_model
	play.player_faction = 0
	play.capital_province = 0
	play.turn = 1
	play.map_seed = 1
	while NavalInterception.roll(play.map_seed, play.turn, 0, 1, 77) >= 0.3:
		play.map_seed += 1
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _naval_raid_raider()
	var fleets: Array[FleetState] = [home, raider]
	var ships := ShipLayer.new()
	ships.model = _naval_raid_model
	ships.player_faction = 0
	ships.fleets = fleets
	ships.regions.set_region(_naval_raid_model.region_id, fleets)
	var world := WorldMap.new()
	world.add_region(_naval_raid_model)
	play.world = world
	var economy := EconomyController.new()
	economy.economy = PlayerEconomy.starting()
	economy.market = WorldMarket.with_default_prices()
	economy.economy.treasury = 5000
	assert_true(bool(economy.market.buy(economy.economy, "grain", 4)["ok"]))
	play.ship_layer = ships
	play.economy = economy
	var before: int = economy.economy.quantity("grain")

	var result: Dictionary = MapPlayRaids.resolve(play)

	assert_true(bool(result.get("ok", false)))
	assert_gt(int(result.get("taken", 0)), 0)
	assert_lt(economy.economy.quantity("grain"), before)
	ships.free()
	economy.free()


# --- a raid takes cargo and may sink a merchant hull (DR-20261111-17) --------


func test_a_raid_sinks_a_merchant_hull() -> void:
	_setup_naval_raid()
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _naval_raid_raider()
	var result: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, raider], 0, home, {"grain": 10}, Callable(), 1, 1, 0.0,
		Callable(), 0.0
	)
	assert_true(bool(result["ok"]))
	assert_eq((result["hulls_lost"] as Array).size(), 1)
	assert_eq(home.hulls.size(), 0, "the merchant went down")
	var sunk: Dictionary = (result["hulls_lost"] as Array)[0]
	assert_eq(String(sunk["type_id"]), "fluyte")
	assert_false(String(sunk["name"]).is_empty(), "the despatch can name her")
	assert_almost_eq(float(result["hull_chance"]), 0.4, 0.0001, "base 0.2 × civilian 2")
	assert_almost_eq(float(result["hull_roll"]), 0.0, 0.0001)
	assert_eq(raider.hulls.size(), 1, "the raider risks no hull of its own")


func test_a_raid_can_miss_the_hull_and_keep_every_sail() -> void:
	_setup_naval_raid()
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _naval_raid_raider()
	var result: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, raider], 0, home, {"grain": 10}, Callable(), 1, 1, 0.0,
		Callable(), 0.99
	)
	assert_true(bool(result["ok"]), "the cargo still goes")
	assert_true((result["hulls_lost"] as Array).is_empty())
	assert_eq(home.hulls.size(), 1, "the merchant came home")


func test_escorts_cut_the_hull_loss() -> void:
	_setup_naval_raid()
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _naval_raid_raider()
	var alone: Dictionary = NavalRaid.preview(
		[raider], home, {"grain": 10}, FleetState.Mission.PATROL
	)
	assert_almost_eq(float(alone["hull_chance"]), 0.4, 0.0001)
	assert_eq(String(alone["hull_at_risk"]), "fluyte")
	home.add_hull("home_2", "sloop")
	var escorted: Dictionary = NavalRaid.preview(
		[raider], home, {"grain": 10}, FleetState.Mission.PATROL
	)
	assert_almost_eq(float(escorted["hull_chance"]), 0.2, 0.0001, "a sloop halves it")
	var result: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, raider], 0, home, {"grain": 10}, Callable(), 1, 1, 0.0,
		Callable(), 0.3
	)
	assert_true(bool(result["ok"]))
	assert_true(
		(result["hulls_lost"] as Array).is_empty(),
		"the roll that would sink her alone misses under escort"
	)
	assert_eq(home.hulls.size(), 2)


func test_the_richest_merchant_hull_is_the_one_taken() -> void:
	_setup_naval_raid()
	var home := FleetState.in_port(
		10, 0, 0, ["home_1", "home_2"], {"home_1": "carrack", "home_2": "fluyte"}
	)
	var raider := _naval_raid_raider()
	var result: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, raider], 0, home, {"grain": 10}, Callable(), 1, 1, 0.0,
		Callable(), 0.0
	)
	assert_eq((result["hulls_lost"] as Array).size(), 1)
	assert_eq(home.hulls, ["home_1"] as Array[String], "the 4-hold fluyte is the prize")
	assert_eq(String(((result["hulls_lost"] as Array)[0] as Dictionary)["type_id"]), "fluyte")


func test_a_warship_is_never_the_prize() -> void:
	_setup_naval_raid()
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "sloop"})
	var raider := _naval_raid_raider()
	var result: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [home, raider], 0, home, {"grain": 10}, Callable(), 1, 1, 0.0,
		Callable(), 0.0
	)
	assert_true(bool(result["ok"]))
	assert_eq(float(result["hull_chance"]), 0.0, "no civilian hull to take")
	assert_true((result["hulls_lost"] as Array).is_empty())
	assert_eq(home.hulls.size(), 1, "the escort is not a prize")


## A court with no home fleet in port offers no civilian hull to price.
func test_a_missing_home_fleet_prices_no_hull() -> void:
	_setup_naval_raid()
	assert_eq(NavalHullLoss.chance(null), 0.0)
	assert_eq(NavalHullLoss.escort_factor(null), 0.0)
	assert_true(NavalHullLoss.at_risk(null).is_empty())
	assert_eq(NavalRaid.hull_loss_chance(null), 0.0)


func test_a_prize_sinks_the_rivals_merchant_hull() -> void:
	_setup_naval_raid()
	var crown := _naval_raid_fleet(1, 0, 1, ["sloop"])
	crown.mission = FleetState.Mission.BLOCKADE
	crown.blockade_province = 1
	var laden := FleetState.in_port(20, 1, 1, ["rival_1"], {"rival_1": "fluyte"})
	var raids: Array[Dictionary] = NavalRaid.resolve_prizes(
		_naval_raid_model, [crown, laden], 0,
		{1: {"imports": {"grain": 10}, "home": laden}}, Callable(), 1, 1, Callable(), 0.0, 0.0
	)
	assert_eq(raids.size(), 1)
	assert_eq((raids[0]["hulls_lost"] as Array).size(), 1)
	assert_eq(laden.hulls.size(), 0, "the rival's merchant went down as prize")
	assert_gt(int(raids[0]["lost_total"]), 0, "and her cargo went with her")


func test_a_prize_takes_the_rivals_cargo_off_its_home_naval_raid_fleet() -> void:
	_setup_naval_raid()
	var crown := _naval_raid_fleet(1, 0, 1, ["sloop"])
	crown.mission = FleetState.Mission.BLOCKADE
	crown.blockade_province = 1
	var laden := FleetState.in_port(20, 1, 1, ["rival_1"], {"rival_1": "fluyte"})
	var raids: Array[Dictionary] = NavalRaid.resolve_prizes(
		_naval_raid_model, [crown, laden], 0,
		{1: {"imports": {"grain": 10}, "home": laden}}, Callable(), 1, 1, Callable(), 0.0, 0.99
	)
	assert_eq(raids.size(), 1)
	assert_eq(int(raids[0]["victim"]), 1)
	assert_eq(int(raids[0]["raider"]), 0)
	assert_gt(int(raids[0]["lost_total"]), 0)
	assert_true((raids[0]["hulls_lost"] as Array).is_empty())
	assert_eq(laden.hulls.size(), 1, "a prize need not cost the merchant a hull")


func test_a_prize_needs_a_declared_war() -> void:
	_setup_naval_raid()
	var crown := _naval_raid_fleet(1, 0, 1, ["sloop"])
	crown.mission = FleetState.Mission.BLOCKADE
	crown.blockade_province = 1
	var laden := FleetState.in_port(20, 1, 1, ["rival_1"], {"rival_1": "fluyte"})
	var peace := func(_a: int, _b: int) -> bool: return false
	var raids: Array[Dictionary] = NavalRaid.resolve_prizes(
		_naval_raid_model, [crown, laden], 0,
		{1: {"imports": {"grain": 10}, "home": laden}}, peace, 1, 1, Callable(), 0.0
	)
	assert_true(raids.is_empty(), "peace takes no prize")


func test_a_prize_comes_only_from_the_crowns_own_squadrons() -> void:
	_setup_naval_raid()
	var rival_ship := _naval_raid_fleet(1, 2, 1, ["sloop"])
	rival_ship.mission = FleetState.Mission.BLOCKADE
	rival_ship.blockade_province = 1
	var laden := FleetState.in_port(20, 1, 1, ["rival_1"], {"rival_1": "fluyte"})
	var raids: Array[Dictionary] = NavalRaid.resolve_prizes(
		_naval_raid_model, [rival_ship, laden], 0,
		{1: {"imports": {"grain": 10}, "home": laden}}, Callable(), 1, 1, Callable(), 0.0
	)
	assert_true(raids.is_empty(), "another crown's blockade is not the crown's prize")


func test_a_prize_rolls_on_its_own_salt() -> void:
	_setup_naval_raid()
	var crown := _naval_raid_fleet(1, 0, 1, ["sloop"])
	crown.mission = FleetState.Mission.BLOCKADE
	crown.blockade_province = 1
	var laden := FleetState.in_port(20, 1, 1, ["rival_1"], {"rival_1": "fluyte"})
	var seed_value: int = 1
	var expected: float = NavalInterception.roll(
		seed_value, 3, 1, 0, NavalRaid.PRIZE_TAG_BASE + 1
	)
	while expected >= 0.2:
		seed_value += 1
		expected = NavalInterception.roll(
			seed_value, 3, 1, 0, NavalRaid.PRIZE_TAG_BASE + 1
		)
	var raids: Array[Dictionary] = NavalRaid.resolve_prizes(
		_naval_raid_model, [crown, laden], 0,
		{1: {"imports": {"grain": 10}, "home": laden}}, Callable(), seed_value, 3
	)
	assert_eq(raids.size(), 1)
	assert_almost_eq(float(raids[0]["roll"]), expected, 0.0001)


func test_the_market_keeps_each_crowns_cargo_apart() -> void:
	_setup_naval_raid()
	var market: WorldMarket = WorldMarket.with_default_prices()
	var mine: PlayerEconomy = PlayerEconomy.starting()
	var rival: PlayerEconomy = PlayerEconomy.starting()
	mine.treasury = 5000
	rival.treasury = 5000
	assert_true(bool(market.buy(mine, "grain", 2, 0)["ok"]))
	assert_true(bool(market.buy(rival, "timber", 3, 1)["ok"]))
	assert_eq(int(market.imports_for(0).get("grain", 0)), 2)
	assert_eq(int(market.imports_for(0).get("timber", 0)), 0)
	assert_eq(int(market.imports_for(1).get("timber", 0)), 3)
	assert_eq(
		int(market.imports_this_turn().get("grain", 0)), 2,
		"price discovery still pools every buyer's demand"
	)
	var expected: Array[int] = [0, 1]
	assert_eq(market.importing_factions(), expected)


func test_the_book_closes_with_the_turn() -> void:
	_setup_naval_raid()
	var market: WorldMarket = WorldMarket.with_default_prices()
	var mine: PlayerEconomy = PlayerEconomy.starting()
	mine.treasury = 5000
	assert_true(bool(market.buy(mine, "grain", 2, 0)["ok"]))
	market.advance_prices()
	assert_true(
		market.imports_for(0).is_empty(),
		"price discovery closes the cargo book the raid pass reads"
	)
	assert_true(market.importing_factions().is_empty())


func test_a_saved_book_keeps_each_crowns_cargo() -> void:
	_setup_naval_raid()
	var market: WorldMarket = WorldMarket.with_default_prices()
	var rival: PlayerEconomy = PlayerEconomy.starting()
	rival.treasury = 5000
	assert_true(bool(market.buy(rival, "timber", 3, 1)["ok"]))
	var restored: WorldMarket = WorldMarket.from_dict(market.to_dict())
	restored = WorldMarket.from_dict(
		JSON.parse_string(JSON.stringify(restored.to_dict())) as Dictionary
	)
	assert_eq(int(restored.imports_for(1).get("timber", 0)), 3)
	assert_true(bool(restored.buy(rival, "timber", 1, 1)["ok"]))
	assert_eq(int(restored.imports_for(1).get("timber", 0)), 4, "a reload keeps filling the row")


func test_the_map_pass_pays_the_crown_for_its_blockade() -> void:
	_setup_naval_raid()
	var play := PlaySession.new()
	play.model = _naval_raid_model
	play.player_faction = 0
	play.capital_province = 0
	play.turn = 1
	play.ai = AiState.new()
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.ensure_relation(0, 1, 1)
	DiplomacyRules.declare_war(play.diplomacy, 0, 1, false)
	var blockader := _naval_raid_fleet(1, 0, 1, ["sloop"])
	blockader.mission = FleetState.Mission.BLOCKADE
	blockader.blockade_province = 1
	var laden := FleetState.in_port(20, 1, 1, ["rival_1"], {"rival_1": "fluyte"})
	var fleets: Array[FleetState] = [blockader, laden]
	var ships := ShipLayer.new()
	ships.model = _naval_raid_model
	ships.player_faction = 0
	ships.fleets = fleets
	ships.regions.set_region(_naval_raid_model.region_id, fleets)
	play.ship_layer = ships
	var world := WorldMap.new()
	world.add_region(_naval_raid_model)
	play.world = world
	var economy := EconomyController.new()
	economy.economy = PlayerEconomy.starting()
	economy.market = WorldMarket.with_default_prices()
	play.economy = economy
	economy.market.record_import("grain", 6, 1)
	var rival: PlayerEconomy = play.ledger_for(1)
	rival.add("grain", 6)
	var rival_before: int = rival.quantity("grain")
	var crown_before: int = economy.economy.quantity("grain")
	play.map_seed = 1
	var salt: int = NavalRaid.PRIZE_TAG_BASE + 1
	var cargo_chance: float = NavalRaid.trade_chance(
		[blockader], laden, FleetState.Mission.BLOCKADE
	)
	var hull_chance: float = NavalRaid.hull_loss_chance(laden)
	while NavalInterception.roll(play.map_seed, 1, 1, 0, salt) >= cargo_chance \
			or NavalInterception.roll(
				play.map_seed, 1, 1, 0, 0, NavalRaid.HULL_PRIZE_TAG_BASE + 1
			) < hull_chance:
		play.map_seed += 1

	var result: Dictionary = MapPlayRaids.resolve(play)

	assert_gt(int(result.get("prize", 0)), 0)
	assert_gt(
		economy.economy.quantity("grain"), crown_before,
		"the prize lands in the crown's stockpile"
	)
	assert_lt(rival.quantity("grain"), rival_before, "the rival's cargo is what paid for it")
	assert_eq(laden.hulls.size(), 1, "the merchant hull came home this time")
	assert_eq(int(result.get("sunk", 0)), 0)
	ships.free()
	economy.free()


## A prize takes the rival's merchant hull too: the home fleet loses her and her
## holds with the cargo (DR-20261111-17).
func test_the_map_pass_sinks_the_rivals_merchant_hull() -> void:
	_setup_naval_raid()
	var play := PlaySession.new()
	play.model = _naval_raid_model
	play.player_faction = 0
	play.capital_province = 0
	play.turn = 1
	play.ai = AiState.new()
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.ensure_relation(0, 1, 1)
	DiplomacyRules.declare_war(play.diplomacy, 0, 1, false)
	var blockader := _naval_raid_fleet(1, 0, 1, ["sloop"])
	blockader.mission = FleetState.Mission.BLOCKADE
	blockader.blockade_province = 1
	var laden := FleetState.in_port(20, 1, 1, ["rival_1"], {"rival_1": "fluyte"})
	var fleets: Array[FleetState] = [blockader, laden]
	var ships := ShipLayer.new()
	ships.model = _naval_raid_model
	ships.player_faction = 0
	ships.fleets = fleets
	ships.regions.set_region(_naval_raid_model.region_id, fleets)
	play.ship_layer = ships
	var world := WorldMap.new()
	world.add_region(_naval_raid_model)
	play.world = world
	var economy := EconomyController.new()
	economy.economy = PlayerEconomy.starting()
	economy.market = WorldMarket.with_default_prices()
	play.economy = economy
	economy.market.record_import("grain", 6, 1)
	play.ledger_for(1).add("grain", 6)
	play.map_seed = 1
	var salt: int = NavalRaid.PRIZE_TAG_BASE + 1
	var cargo_chance: float = NavalRaid.trade_chance(
		[blockader], laden, FleetState.Mission.BLOCKADE
	)
	var hull_chance: float = NavalRaid.hull_loss_chance(laden)
	while NavalInterception.roll(play.map_seed, 1, 1, 0, salt) >= cargo_chance \
			or NavalInterception.roll(
				play.map_seed, 1, 1, 0, 0, NavalRaid.HULL_PRIZE_TAG_BASE + 1
			) >= hull_chance:
		play.map_seed += 1

	var result: Dictionary = MapPlayRaids.resolve(play)

	assert_eq(int(result.get("sunk", 0)), 1, "the raid sent one merchant down")
	assert_eq(laden.hulls.size(), 0, "her holds are gone with her")
	var report: Dictionary = (result["reports"] as Array)[0]
	assert_eq((report["hulls_lost"] as Array).size(), 1)
	assert_true(
		String(((report["hulls_lost"] as Array)[0] as Dictionary)["name"]).length() > 0,
		"the despatch names the ship"
	)
	ships.free()
	economy.free()


func test_the_crown_loses_only_its_own_cargo_to_raiders() -> void:
	_setup_naval_raid()
	var play := PlaySession.new()
	play.model = _naval_raid_model
	play.player_faction = 0
	play.capital_province = 0
	play.turn = 1
	play.ai = AiState.new()
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.ensure_relation(0, 1, 1)
	DiplomacyRules.declare_war(play.diplomacy, 0, 1, false)
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _naval_raid_fleet(2, 1, 0, ["frigate"])
	raider.mission = FleetState.Mission.PATROL
	home.mission = FleetState.Mission.NONE
	home.moved = false
	var fleets: Array[FleetState] = [home, raider]
	var ships := ShipLayer.new()
	ships.model = _naval_raid_model
	ships.player_faction = 0
	ships.fleets = fleets
	ships.regions.set_region(_naval_raid_model.region_id, fleets)
	play.ship_layer = ships
	var world := WorldMap.new()
	world.add_region(_naval_raid_model)
	play.world = world
	var economy := EconomyController.new()
	economy.economy = PlayerEconomy.starting()
	economy.market = WorldMarket.with_default_prices()
	economy.economy.add("grain", 20)
	play.economy = economy
	economy.market.record_import("grain", 4, 0)
	economy.market.record_import("grain", 40, 1)
	var before: int = economy.economy.quantity("grain")
	play.map_seed = 1
	var cargo_chance: float = NavalRaid.trade_chance(
		[raider], home, FleetState.Mission.PATROL
	)
	var hull_chance: float = NavalRaid.hull_loss_chance(home)
	while NavalInterception.roll(play.map_seed, 1, 0, 1, NavalRaid.ROLL_TAG) >= cargo_chance \
			or NavalInterception.roll(
				play.map_seed, 1, 0, 1, 0, NavalRaid.HULL_TAG
			) < hull_chance:
		play.map_seed += 1

	var result: Dictionary = MapPlayRaids.resolve(play)

	var taken: int = int(result.get("taken", 0))
	assert_gt(taken, 0)
	assert_lte(taken, 4, "the rival's forty units were never the crown's cargo")
	assert_eq(economy.economy.quantity("grain"), before - taken)
	assert_eq(home.hulls.size(), 1, "this raid pinched cargo and missed the hull")
	assert_eq(int(result.get("sunk", 0)), 0)
	ships.free()
	economy.free()


## The other side of the same draw: the crown's merchant is sent down, with the
## holds she carried (DR-20261111-17).
func test_the_map_pass_sinks_the_crowns_merchant_hull() -> void:
	_setup_naval_raid()
	var play := PlaySession.new()
	play.model = _naval_raid_model
	play.player_faction = 0
	play.capital_province = 0
	play.turn = 1
	play.ai = AiState.new()
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.ensure_relation(0, 1, 1)
	DiplomacyRules.declare_war(play.diplomacy, 0, 1, false)
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _naval_raid_fleet(2, 1, 0, ["frigate"])
	raider.mission = FleetState.Mission.PATROL
	var fleets: Array[FleetState] = [home, raider]
	var ships := ShipLayer.new()
	ships.model = _naval_raid_model
	ships.player_faction = 0
	ships.fleets = fleets
	ships.regions.set_region(_naval_raid_model.region_id, fleets)
	play.ship_layer = ships
	var world := WorldMap.new()
	world.add_region(_naval_raid_model)
	play.world = world
	var economy := EconomyController.new()
	economy.economy = PlayerEconomy.starting()
	economy.market = WorldMarket.with_default_prices()
	economy.economy.add("grain", 20)
	play.economy = economy
	economy.market.record_import("grain", 4, 0)
	play.map_seed = 1
	var cargo_chance: float = NavalRaid.trade_chance(
		[raider], home, FleetState.Mission.PATROL
	)
	var hull_chance: float = NavalRaid.hull_loss_chance(home)
	while NavalInterception.roll(play.map_seed, 1, 0, 1, NavalRaid.ROLL_TAG) >= cargo_chance \
			or NavalInterception.roll(
				play.map_seed, 1, 0, 1, 0, NavalRaid.HULL_TAG
			) >= hull_chance:
		play.map_seed += 1

	var result: Dictionary = MapPlayRaids.resolve(play)

	assert_eq(int(result.get("sunk", 0)), 1, "the raiders sank a merchant")
	assert_eq(home.hulls.size(), 0, "her holds leave the home fleet with her")
	var report: Dictionary = (result["reports"] as Array)[0]
	assert_eq(String(report["kind"]), "incoming")
	assert_eq((report["hulls_lost"] as Array).size(), 1)
	ships.free()
	economy.free()


func test_the_dossier_prices_the_prize_before_the_move() -> void:
	_setup_naval_raid()
	var play := PlaySession.new()
	play.model = _naval_raid_model
	play.player_faction = 0
	play.turn = 1
	play.ai = AiState.new()
	var blockader := _naval_raid_fleet(1, 0, 1, ["sloop"])
	blockader.mission = FleetState.Mission.BLOCKADE
	blockader.blockade_province = 1
	var laden := FleetState.in_port(20, 1, 1, ["rival_1"], {"rival_1": "fluyte"})
	var fleets: Array[FleetState] = [blockader, laden]
	var ships := ShipLayer.new()
	ships.model = _naval_raid_model
	ships.player_faction = 0
	ships.fleets = fleets
	ships.regions.set_region(_naval_raid_model.region_id, fleets)
	play.ship_layer = ships
	var world := WorldMap.new()
	world.add_region(_naval_raid_model)
	play.world = world
	play.map_seed = 1
	var economy := EconomyController.new()
	economy.economy = PlayerEconomy.starting()
	economy.market = WorldMarket.with_default_prices()
	play.economy = economy
	economy.market.record_import("grain", 6, 1)
	var note: String = MapPlayFleetMissions.prize_note(play, blockader)
	var odds: Dictionary = NavalRaid.preview(
		[blockader], laden, {"grain": 6}, FleetState.Mission.BLOCKADE
	)
	assert_true(note.contains("Prize:"))
	assert_true(
		note.contains("sinks a Fluyte"),
		"the dossier prices the merchant hull as well as the cargo"
	)
	assert_true(note.contains("40%"), "base 0.2 × civilian 2 with no escort")
	assert_true(
		note.contains("%d%%" % int(round(float(odds["chance"]) * 100.0))),
		"the dossier reads the chance the rules roll"
	)
	assert_true(note.contains("~%d" % int(odds["expected"])))
	# With nothing bought this turn there is no cargo afloat to take.
	economy.market.advance_prices()
	assert_true(
		MapPlayFleetMissions.prize_note(play, blockader).contains("no cargo afloat")
	)
	# A crown that has taken the coast blockades its own shore: no prize.
	economy.market.record_import("grain", 4, 1)
	_naval_raid_model.province_data(1).owner = 0
	assert_eq(MapPlayFleetMissions.prize_note(play, blockader), "")
	_naval_raid_model.province_data(1).owner = 1
	# A rival whose merchant hulls are at sea has no laden home fleet to raid.
	laden.location = FleetState.Location.AT_SEA
	laden.sea_zone = 1
	laden.province = MapModel.NO_ID
	assert_true(
		MapPlayFleetMissions.prize_note(play, blockader).contains("at sea")
	)
	economy.free()


# --- rival-on-rival raids + prize cargo (DR-20261111-20) ----------------------


## A wired one-region play session: the crown's ledger plus the rival ledgers a
## prize raid writes to. `fleets` is the region roster every pass reads.
func _naval_raid_session(fleets: Array[FleetState]) -> PlaySession:
	var play := PlaySession.new()
	play.model = _naval_raid_model
	play.player_faction = 0
	play.capital_province = 0
	play.turn = 1
	play.map_seed = 1
	play.ai = AiState.new()
	play.diplomacy = DiplomacyState.new()
	var ships := ShipLayer.new()
	ships.model = _naval_raid_model
	ships.player_faction = 0
	ships.fleets = fleets
	ships.regions.set_region(_naval_raid_model.region_id, fleets)
	play.ship_layer = ships
	var world := WorldMap.new()
	world.add_region(_naval_raid_model)
	play.world = world
	var economy := EconomyController.new()
	economy.economy = PlayerEconomy.starting()
	economy.market = WorldMarket.with_default_prices()
	play.economy = economy
	return play


## First seed where `raider`'s prize roll on `victim` lands: cargo comes aboard
## and the hull draw misses (or hits), as the test asks.
func _naval_raid_seed_for_prize(
	play: PlaySession, raider: FleetState, home: FleetState, victim: int, sink_hull: bool
) -> void:
	var salt: int = NavalRaid.PRIZE_TAG_BASE + victim
	var hull_salt: int = NavalRaid.HULL_PRIZE_TAG_BASE + victim
	var chance: float = NavalRaid.trade_chance([raider], home, raider.mission)
	var hull_chance: float = NavalRaid.hull_loss_chance(home)
	while true:
		var cargo: float = NavalInterception.roll(
			play.map_seed, play.turn, raider.sea_zone, raider.owner, salt
		)
		var hull: float = NavalInterception.roll(
			play.map_seed, play.turn, raider.sea_zone, raider.owner, 0, hull_salt
		)
		if cargo < chance and (hull < hull_chance) == sink_hull:
			return
		play.map_seed += 1


## The other coast belongs to a rival, and the rival's blockade pays the rival:
## the crown is not a party to the war and takes neither cargo nor a despatch.
func test_a_rival_blockade_lands_its_prize_in_the_rival_ledger() -> void:
	_setup_naval_raid()
	_naval_raid_model.province_data(0).owner = 2
	var blockader := _naval_raid_fleet(1, 1, 0, ["sloop"])
	blockader.mission = FleetState.Mission.BLOCKADE
	blockader.blockade_province = 0
	var laden := FleetState.in_port(20, 2, 0, ["rival_1"], {"rival_1": "fluyte"})
	var play := _naval_raid_session([blockader, laden])
	play.diplomacy.ensure_relation(1, 2, 1)
	DiplomacyRules.declare_war(play.diplomacy, 1, 2, false)
	play.economy.market.record_import("grain", 6, 2)
	var victim: PlayerEconomy = play.ledger_for(2)
	victim.add("grain", 6)
	var victim_before: int = victim.quantity("grain")
	var raider: PlayerEconomy = play.ledger_for(1)
	var raider_before: int = raider.quantity("grain")
	var crown_before: int = play.economy.economy.quantity("grain")
	_naval_raid_seed_for_prize(play, blockader, laden, 2, false)

	var result: Dictionary = MapPlayRaids.resolve(play)

	var prize: int = int(result.get("rival_prize", 0))
	assert_gt(prize, 0, "a rival's blockade takes a rival's cargo")
	assert_eq(raider.quantity("grain"), raider_before + prize, "the prize is the raider's")
	assert_eq(victim.quantity("grain"), victim_before - prize, "and it leaves the victim's stockpile")
	assert_eq(
		play.economy.economy.quantity("grain"), crown_before,
		"the crown was never a party to that war"
	)
	assert_true((result["reports"] as Array).is_empty(), "no despatch to a stranger")
	var rival_raids: Array = result["rival_raids"] as Array
	assert_eq(rival_raids.size(), 1)
	var raid: Dictionary = rival_raids[0] as Dictionary
	assert_eq(String(raid["kind"]), "rival")
	assert_eq(int(raid["raider"]), 1)
	assert_eq(int(raid["victim"]), 2)
	assert_eq(laden.hulls.size(), 1, "the hull draw missed this turn")
	play.ship_layer.free()
	play.economy.free()


func test_two_rivals_at_peace_take_no_prize() -> void:
	_setup_naval_raid()
	_naval_raid_model.province_data(0).owner = 2
	var blockader := _naval_raid_fleet(1, 1, 0, ["sloop"])
	blockader.mission = FleetState.Mission.BLOCKADE
	blockader.blockade_province = 0
	var laden := FleetState.in_port(20, 2, 0, ["rival_1"], {"rival_1": "fluyte"})
	var play := _naval_raid_session([blockader, laden])
	play.diplomacy.ensure_relation(1, 2, 1)
	play.economy.market.record_import("grain", 6, 2)
	play.ledger_for(2).add("grain", 6)
	var raider: PlayerEconomy = play.ledger_for(1)
	var raider_before: int = raider.quantity("grain")
	var victim_before: int = play.ledger_for(2).quantity("grain")

	var result: Dictionary = MapPlayRaids.resolve(play)

	assert_eq(int(result.get("rival_prize", 0)), 0)
	assert_eq(raider.quantity("grain"), raider_before, "peace takes no prize")
	assert_eq(play.ledger_for(2).quantity("grain"), victim_before, "the rival keeps its cargo")
	assert_eq(laden.hulls.size(), 1)
	assert_true((result["rival_raids"] as Array).is_empty())
	play.ship_layer.free()
	play.economy.free()


## The same raid that skims cargo can send the victim's merchant down, and the
## hull leaves the rival's home fleet without a peasant or a coin returned.
func test_a_rival_prize_sinks_the_victims_merchant_hull() -> void:
	_setup_naval_raid()
	_naval_raid_model.province_data(0).owner = 2
	var blockader := _naval_raid_fleet(1, 1, 0, ["sloop"])
	blockader.mission = FleetState.Mission.BLOCKADE
	blockader.blockade_province = 0
	var laden := FleetState.in_port(20, 2, 0, ["rival_1"], {"rival_1": "fluyte"})
	var play := _naval_raid_session([blockader, laden])
	play.diplomacy.ensure_relation(1, 2, 1)
	DiplomacyRules.declare_war(play.diplomacy, 1, 2, false)
	play.economy.market.record_import("grain", 6, 2)
	play.ledger_for(2).add("grain", 6)
	_naval_raid_seed_for_prize(play, blockader, laden, 2, true)

	var result: Dictionary = MapPlayRaids.resolve(play)

	assert_gt(int(result.get("rival_prize", 0)), 0, "her cargo went with her")
	assert_eq(laden.hulls.size(), 0, "the rival's merchant is gone")
	var raid: Dictionary = (result["rival_raids"] as Array)[0] as Dictionary
	assert_eq((raid["hulls_lost"] as Array).size(), 1)
	assert_true(
		String(((raid["hulls_lost"] as Array)[0] as Dictionary)["name"]).length() > 0,
		"a rival's loss still carries the ship's name"
	)
	play.ship_layer.free()
	play.economy.free()


## The crown suffers one raid a turn through `_incoming`; a rival's blockade off
## its coast is never also a prize raid writing into the rival's ledger.
func test_the_crown_is_never_a_rivals_prize() -> void:
	_setup_naval_raid()
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _naval_raid_fleet(2, 1, 0, ["frigate"])
	raider.mission = FleetState.Mission.PATROL
	var play := _naval_raid_session([home, raider])
	play.diplomacy.ensure_relation(0, 1, 1)
	DiplomacyRules.declare_war(play.diplomacy, 0, 1, false)
	play.economy.economy.add("grain", 20)
	play.economy.market.record_import("grain", 4, 0)
	var rival: PlayerEconomy = play.ledger_for(1)
	var rival_before: int = rival.quantity("grain")
	var crown_before: int = play.economy.economy.quantity("grain")
	var cargo_chance: float = NavalRaid.trade_chance(
		[raider], home, FleetState.Mission.PATROL
	)
	var hull_chance: float = NavalRaid.hull_loss_chance(home)
	while NavalInterception.roll(play.map_seed, 1, 0, 1, NavalRaid.ROLL_TAG) >= cargo_chance \
			or NavalInterception.roll(
				play.map_seed, 1, 0, 1, 0, NavalRaid.HULL_TAG
			) < hull_chance:
		play.map_seed += 1

	var result: Dictionary = MapPlayRaids.resolve(play)

	var taken: int = int(result.get("taken", 0))
	assert_gt(taken, 0, "the crown loses the one raid its coast suffers")
	assert_eq(play.economy.economy.quantity("grain"), crown_before - taken)
	assert_eq(rival.quantity("grain"), rival_before, "the raider took no prize off the crown")
	assert_true((result["rival_raids"] as Array).is_empty())
	play.ship_layer.free()
	play.economy.free()


## Two crowns blockading one coast each take their own prize: the rolls are
## salted per raider and the tonnage lands in each raider's own ledger.
func test_two_blockades_share_the_victims_cargo_apart() -> void:
	_setup_naval_raid()
	var crown := _naval_raid_fleet(1, 0, 1, ["sloop"])
	crown.mission = FleetState.Mission.BLOCKADE
	crown.blockade_province = 1
	var rival := _naval_raid_fleet(2, 2, 1, ["sloop"])
	rival.mission = FleetState.Mission.BLOCKADE
	rival.blockade_province = 1
	var laden := FleetState.in_port(20, 1, 1, ["rival_1"], {"rival_1": "fluyte"})
	var play := _naval_raid_session([crown, rival, laden])
	play.diplomacy.ensure_relation(0, 1, 1)
	DiplomacyRules.declare_war(play.diplomacy, 0, 1, false)
	play.diplomacy.ensure_relation(2, 1, 1)
	DiplomacyRules.declare_war(play.diplomacy, 2, 1, false)
	play.economy.market.record_import("grain", 6, 1)
	var victim: PlayerEconomy = play.ledger_for(1)
	victim.add("grain", 6)
	var victim_before: int = victim.quantity("grain")
	var partner: PlayerEconomy = play.ledger_for(2)
	var partner_before: int = partner.quantity("grain")
	var crown_before: int = play.economy.economy.quantity("grain")
	var salt: int = NavalRaid.PRIZE_TAG_BASE + 1
	var hull_salt: int = NavalRaid.HULL_PRIZE_TAG_BASE + 1
	var chance: float = NavalRaid.trade_chance([crown], laden, FleetState.Mission.BLOCKADE)
	var hull_chance: float = NavalRaid.hull_loss_chance(laden)
	while NavalInterception.roll(play.map_seed, 1, 1, 0, salt) >= chance \
			or NavalInterception.roll(play.map_seed, 1, 1, 2, salt) >= chance \
			or NavalInterception.roll(play.map_seed, 1, 1, 0, 0, hull_salt) < hull_chance \
			or NavalInterception.roll(play.map_seed, 1, 1, 2, 0, hull_salt) < hull_chance:
		play.map_seed += 1

	var result: Dictionary = MapPlayRaids.resolve(play)

	var prize: int = int(result.get("prize", 0))
	var rival_prize: int = int(result.get("rival_prize", 0))
	assert_gt(prize, 0, "the crown's blockade pays the crown")
	assert_gt(rival_prize, 0, "the rival's blockade pays the rival")
	assert_eq(play.economy.economy.quantity("grain"), crown_before + prize)
	assert_eq(partner.quantity("grain"), partner_before + rival_prize)
	assert_eq(victim.quantity("grain"), victim_before - prize - rival_prize)
	assert_eq(laden.hulls.size(), 1, "both hull draws missed")
	play.ship_layer.free()
	play.economy.free()
