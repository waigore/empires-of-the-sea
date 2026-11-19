# gdlint: disable=max-public-methods
extends GdToolsTest
## The sea in one suite: the yard, hull names and rosters, station orders, sortie,
## strength aggregation, retreat, a lost port, interception, movement and raids
## (wiki: ships-and-naval).

## Merged from test_fleet_yard, test_fleet_yard_block, test_fleet_names,
## test_fleet_rosters, test_fleet_sortie, test_fleet_missions, test_naval_strength,
## test_naval_retreat, test_naval_port_loss, test_naval_interception,
## test_naval_movement, test_naval_raid, test_naval_intel, test_hostility_rules.
## test_fleet_rules was a re-pointed copy of these 36 cases and is folded in.
## One Godot boot (coverage instrumentation) per theme instead of one per file.
## Each test runs only its own suite's setup; teardown follows the setup.
const fleet_names_NavalFixture = preload("res://tests/naval_fixture.gd")
const naval_transport_AiFixture = preload("res://tests/ai_fixture.gd")
const fleet_rosters_NavalFixture = preload("res://tests/naval_fixture.gd")
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
	_markers.model = fleet_rosters_NavalFixture.build()

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

## A court flies a hull her studies never opened — the opening muster's Fluyte —
## so the yard offers her without the tech, the same gate the rival courts read
## (issue #484; REQ-P2-03).
func test_a_flown_hull_stays_on_the_slip_without_her_tech() -> void:
	_setup_fleet_yard()
	var by_type: Dictionary = {}
	for row: Dictionary in FleetYard.rows(_econ, true, ["fluyte"]):
		by_type[String(row["type_id"])] = row

	assert_true(bool((by_type["fluyte"] as Dictionary)["ok"]), "her own craft is on the slip")
	assert_false(bool((by_type["frigate"] as Dictionary)["ok"]), "a hull never flown waits")

func test_an_absent_home_port_blocks_every_row() -> void:
	_setup_fleet_yard()
	var rows: Array[Dictionary] = FleetYard.rows(_econ, false)

	for row: Dictionary in rows:
		assert_false(bool(row["ok"]))
		assert_eq(String(row["reason"]), "Launch hulls at your capital port.")

## The yard's one press walks the slip's order and reserves what each hull order
## spends, so a press never files a launch the Build/work pass would refuse
## (REQ-P2-03, REQ-P5-04; DR-20261118-08).
func test_the_yard_batch_reserves_the_ledger_each_hull_spends() -> void:
	_setup_fleet_yard()
	_econ.tech_unlocked["superior_hull_design"] = true
	var types: Array[String] = ["carrack", "fluyte"]

	var result: Dictionary = FleetYard.queue_all(_econ, true, types)

	assert_eq(int(result["filed"]), 2, "every payable hull files")
	assert_eq(String(result["refusal"]), "", "nothing is refused")
	assert_eq(
		_econ.recruits.pending_kind(RecruitQueue.KIND_SHIP), 2, "one order per hull"
	)
	assert_eq(
		_econ.available_peasants(),
		PlayerEconomy.START_PEASANTS - 2,
		"each hull reserves her peasant"
	)

	# Cash: the carrack's price leaves the fluyte short.
	_econ = PlayerEconomy.starting()
	_econ.tech_unlocked["superior_hull_design"] = true
	_econ.treasury = ShipEconomy.treasury_cost("carrack")
	result = FleetYard.queue_all(_econ, true, types)
	assert_eq(int(result["filed"]), 1, "only what the purse covers")
	assert_eq(String(result["refusal"]), "Insufficient treasury")

	# Materials: the carrack takes the last bolt of cloth.
	_econ = PlayerEconomy.starting()
	_econ.tech_unlocked["superior_hull_design"] = true
	_econ.treasury = 60000
	_econ.stockpile["fabric"] = 1
	result = FleetYard.queue_all(_econ, true, types)
	assert_eq(int(result["filed"]), 1, "only what the stores cover")
	assert_eq(String(result["refusal"]), "Insufficient materials")

	# Hands: the queue reserves the peasant, so the second hull finds none.
	_econ = PlayerEconomy.starting()
	_econ.tech_unlocked["superior_hull_design"] = true
	_econ.treasury = 60000
	_econ.workers = WorkerPool.make(1)
	result = FleetYard.queue_all(_econ, true, types)
	assert_eq(int(result["filed"]), 1, "only what the pool covers")
	assert_eq(String(result["refusal"]), "Insufficient workers")

## The slip's one press reads only rows no waiting order claims, and only at the
## crown's own capital port, so a second press never doubles a hull already under
## orders (DR-20261118-08).
func test_the_yard_batch_skips_a_hull_already_under_orders() -> void:
	_setup_fleet_yard()
	_econ.tech_unlocked["superior_hull_design"] = true
	_econ.queue_build(RecruitQueue.KIND_SHIP, "carrack")

	var ready: Array[String] = FleetYard.batch_types(_econ, true)

	assert_false(ready.has("carrack"), "a hull under orders is not re-filed")
	assert_true(ready.has("fluyte"), "a row nothing claims still stands ready")
	assert_true(FleetYard.batch_types(_econ, false).is_empty(), "no slip away from home")
	var away: Dictionary = FleetYard.queue_all(_econ, false, ["fluyte"])
	assert_eq(int(away["filed"]), 0, "nothing is laid down away from home")
	assert_eq(String(away["refusal"]), FleetYard.NOT_AT_HOME, "the gate speaks its row's words")

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

## Every button whose face starts with `prefix`; `exact` keeps only a button
## whose face is the prefix itself, so the slip's own row presses can be read
## apart from the one batch press under them (DR-20261118-08).
func _buttons(block: FleetYardBlock, prefix: String, exact: bool = false) -> Array[String]:
	var out: Array[String] = []
	for node: Node in block.find_children("*", "Button", true, false):
		var text: String = (node as Button).text
		if text.begins_with(prefix) and (not exact or text == prefix):
			out.append(text)
	return out

func test_the_slip_lists_launches_and_opens_at_once() -> void:
	var block := FleetYardBlock.new()
	add_child(block)

	block.show_slip(_rows(), true)

	assert_true(block._button.visible, "a player with rows gets the yard")
	assert_true(block._open, "the capital slip opens the drawer")
	assert_eq(block._button.text, "Close shipyard")
	assert_eq(_buttons(block, "Launch", true), ["Launch", "Launch"], "one press per hull")
	# The slip's own one press stands hidden while nothing on it is ready.
	assert_eq(_buttons(block, "Launch all ready"), ["Launch all ready (0)"])
	assert_false((block._batch as Control).visible, "nothing ready, no batch press")
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
	var fleet := FleetState.in_port(3, 1, 0, ["ship_1"], {})

	panel.refresh(fleet_names_NavalFixture.build(), fleet, true)

	var line: String = ""
	for node: Node in panel.find_children("*", "Label", true, false):
		var text: String = (node as Label).text
		if text.contains("Carrack") and text.contains("upkeep"):
			line = text
	assert_true(line.begins_with("1 ship · "), "the dossier reads '%s'" % line)

	panel.refresh(fleet_names_NavalFixture.build(), fleet, true, "", [], [], 1, [], "", {"count": 1})
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
	var fleet := FleetState.in_port(3, 1, 0, ["ship_1"], {})
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

	panel.refresh(fleet_names_NavalFixture.build(), fleet, true, "", rows)
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


## A crown whose leader publishes a naval row fights at that multiplier, and a
## land or court leader never touches the sea (wiki: leader-bonuses § When
## Bonuses Apply — the naval exception is de Ruyter's row only).
func test_de_ruyter_lifts_only_his_own_side_at_sea() -> void:
	var mine: FleetState = FleetState.at_sea(1, 0, 0, ["ship_1"], {"ship_1": "carrack"})
	var theirs: FleetState = FleetState.at_sea(2, 1, 0, ["ship_2"], {"ship_2": "carrack"})
	var mine_base: float = NavalCombat.side_strength([mine])
	var theirs_base: float = NavalCombat.side_strength([theirs])
	var led: Array[Dictionary] = NavalCombat.resolve_turn(
		[mine, theirs], Callable(), {"leaders": {0: "de_ruyter", 1: "napoleon"}}
	)
	assert_eq(led.size(), 1, "two hostile sides in one zone fight")
	var record: Dictionary = led[0]
	assert_eq(int(record["attacker"]), 0, "the lower owner id opens the fight")
	assert_almost_eq(float(record["attacker_strength"]), mine_base * 1.15, 0.0001,
		"de Ruyter's squadron fights 15% stronger")
	assert_almost_eq(float(record["defender_strength"]), theirs_base, 0.0001,
		"a court without a naval row fights as published")


func test_a_sea_fight_without_leaders_fights_as_published() -> void:
	var mine: FleetState = FleetState.at_sea(1, 0, 0, ["ship_1"], {"ship_1": "carrack"})
	var theirs: FleetState = FleetState.at_sea(2, 1, 0, ["ship_2"], {"ship_2": "frigate"})
	var published: float = NavalCombat.side_strength([mine])
	var plain: Array[Dictionary] = NavalCombat.resolve_turn([mine, theirs])
	assert_eq(plain.size(), 1)
	assert_almost_eq(
		float(plain[0]["attacker_strength"]), published, 0.0001,
		"no leader context leaves the published strength alone"
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


## The dossier's share reads the crown's leader exactly as the resolver does, so
## a de Ruyter squadron's printed odds are the odds it strikes (REQ-P2-03).
func test_the_zone_share_reads_the_published_naval_row() -> void:
	var mine: FleetState = FleetState.at_sea(1, 0, 0, ["ship_1"], {"ship_1": "carrack"})
	var theirs: FleetState = FleetState.at_sea(3, 1, 0, ["ship_3"], {"ship_3": "carrack"})
	var published: float = NavalCombat.side_strength([mine])
	var plain: Dictionary = NavalStrength.zone([mine, theirs], mine)
	assert_almost_eq(float(plain["own"]), published, 0.0001)
	var led: Dictionary = NavalStrength.zone(
		[mine, theirs], mine, Callable(), {}, {0: "de_ruyter", 1: "napoleon"}
	)
	assert_almost_eq(float(led["own"]), published * 1.15, 0.0001)
	assert_almost_eq(
		float(led["foe"]), published, 0.0001, "a land leader never touches the sea"
	)


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

## A squadron that sorts out of a captured port in the other chart enters that
## water exactly as a sail order does, so the crown charts the zone even though
## the court is looking at the other chart (wiki: ships-and-naval § Ports that
## change hands — "The entry reveals the zone for its owner like any move").
func test_a_sort_out_in_the_other_chart_charts_the_zone() -> void:
	var play: PlaySession = _two_chart_session()
	var fleet: FleetState = FleetState.in_port(1, 0, SEAT, ["ship_1"])
	play.ship_layer.regions.set_region(1, [fleet])
	play.world.region(1).province_data(SEAT).owner = 1

	MapPlayPortLoss.settle(play, [])

	assert_true(fleet.is_at_sea(), "the port fell, so the squadron sorts out")
	assert_eq(fleet.sea_zone, 0)
	var chart: VisibilityModel = play.visibility_by_region.get(1, null)
	assert_not_null(chart, "the other chart is minted for the entry")
	if chart == null:
		return
	for tile: Vector2i in play.world.region(1).sea_zone_data(0).tiles:
		assert_eq(
			chart.level_at(tile.x, tile.y), VisibilityModel.Level.FULLY_VISIBLE,
			"the entered zone's water is charted"
		)
	# The strict coastal ring comes with the water, as any sail order charts it.
	assert_eq(chart.level_at(1, 0), VisibilityModel.Level.FULLY_VISIBLE)
	# The shown chart is the ship layer's own signal, so nothing is minted here.
	assert_false(play.visibility_by_region.has(0))

## A re-mooring is administrative and charts nothing, a rival's sortie is not
## the crown's reading, and a scuttled squadron enters no water at all.
func test_only_the_crowns_own_sort_out_charts_the_other_chart() -> void:
	var play: PlaySession = _two_chart_session()
	var reports: Array[Dictionary] = [
		{"fleet": 1, "owner": 1, "province": SEAT, "zone": 0, "scuttled": false, "region": 1},
		{"fleet": 2, "owner": 0, "from": SEAT, "to": HARBOUR, "region": 1},
		{"fleet": 3, "owner": 0, "province": SEAT, "zone": MapModel.NO_ID, "scuttled": true, "region": 1},
	]

	MapPlayPortLoss.chart_sorties(play, reports)

	assert_false(play.visibility_by_region.has(1), "no chart is minted for nothing")

## Two charts, the crown looking at the old one: the fixture's chart twice, the
## second standing in for the New World. The layer knows both rosters.
func _two_chart_session() -> PlaySession:
	var old_world: MapModel = naval_port_loss_Fixture.build()
	var new_world: MapModel = naval_port_loss_Fixture.build()
	new_world.region_id = 1
	var world := WorldMap.new()
	world.add_region(old_world)
	world.add_region(new_world)
	var play := PlaySession.new()
	play.world = world
	play.model = old_world
	play.player_faction = 0
	play.region_index = 0
	play.ship_layer = ShipLayer.new()
	play.ship_layer.model = old_world
	play.ship_layer.world = world
	play.ship_layer.player_faction = 0
	return play

## The chart helper's own guards: the shown region hands back the session's
## model, a region the world does not have mints nothing, and a session with no
## world or no reports is a no-op.
func test_the_chart_helper_guards_what_it_cannot_chart() -> void:
	var play: PlaySession = _two_chart_session()
	var shown := VisibilityModel.new()
	shown.setup(play.model, 0)
	play.visibility = shown

	assert_eq(MapPlayFogTurn.chart(play, 0), shown, "the shown chart is the session's")
	assert_eq(MapPlayFogTurn.chart(play, 9), null, "no such region")
	assert_eq(MapPlayFogTurn.chart(null, 0), null, "no session")
	var bare := PlaySession.new()
	bare.player_faction = 0
	assert_eq(MapPlayFogTurn.chart(bare, 1), null, "no world to cut a chart from")
	MapPlayPortLoss.chart_sorties(null, [])
	MapPlayPortLoss.chart_sorties(bare, [{"owner": 0, "zone": 0, "region": 1}])
	assert_true(bare.visibility_by_region.is_empty(), "nothing is charted without a world")

## A sort-out the crown is already looking at is the ship layer's own signal,
## and a report with no zone enters no water.
func test_a_shown_chart_sort_out_and_a_zoneless_report_chart_nothing() -> void:
	var play: PlaySession = _two_chart_session()
	var reports: Array[Dictionary] = [
		{"fleet": 1, "owner": 0, "province": SEAT, "zone": 0, "scuttled": false, "region": 0},
		{"fleet": 2, "owner": 0, "province": SEAT, "zone": MapModel.NO_ID, "scuttled": false, "region": 1},
	]

	MapPlayPortLoss.chart_sorties(play, reports)

	assert_true(play.visibility_by_region.is_empty(), "neither report charts a chart")

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


## One reading says where a court's seat harbour and home harbour are: the seat
## when it has a port, else the lowest-id own harbour, else NO_ID (wiki:
## ships-and-naval § Home Fleet, § Cargo holds and capacity).
func test_seat_and_home_harbour_read_the_same_seat() -> void:
	_setup_naval_movement()
	var model: MapModel = _naval_movement_model
	assert_eq(NavalMovement.seat_harbour(model, 0), 0)
	assert_eq(NavalMovement.home_harbour(model, 0), 0)
	# A court with a harbour but no capital seat still musters somewhere.
	assert_eq(NavalMovement.seat_harbour(model, 1), MapModel.NO_ID)
	assert_eq(NavalMovement.home_harbour(model, 1), 1)
	assert_eq(NavalMovement.seat_harbour(model, 9), MapModel.NO_ID)
	assert_eq(NavalMovement.home_harbour(model, 9), MapModel.NO_ID)
	assert_eq(NavalMovement.home_harbour(null, 0), MapModel.NO_ID)


## The seat outranks a lower-id harbour, and an inland seat falls back to the
## lowest-id own harbour rather than reading NO_ID.
func test_home_harbour_prefers_the_seat_then_the_lowest_id() -> void:
	_setup_naval_movement()
	var model: MapModel = _naval_movement_model
	model.provinces[1].owner = 0
	assert_eq(NavalMovement.home_harbour(model, 0), 0, "the seat outranks province 1")
	model.provinces[0].port_tile = Vector2i(-1, -1)
	assert_eq(NavalMovement.seat_harbour(model, 0), MapModel.NO_ID)
	assert_eq(NavalMovement.home_harbour(model, 0), 1, "an inland seat falls back to a port")


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


## A squadron that keeps afloat on fewer hulls keeps only the men her deck still
## holds: one hull carries one regiment, so a sunk hull drowns hers (wiki:
## ships-and-naval § Naval transport; § Naval Combat Resolution — a victor still
## loses hulls to the beaten side's strength).
func test_a_sunk_hull_takes_her_regiment_with_her() -> void:
	var fleet := FleetState.at_sea(5, 0, 0, ["ship_5", "ship_6", "ship_7"])
	var army := ArmyState.muster(11, 0, 0, false, ["pikemen", "knights", "musketeers"], 1100)
	fleet.embarked_army = army.id
	army.embarked_fleet = fleet.id
	army.province = MapModel.NO_ID
	fleet.remove_hull("ship_7")
	var drowned: Dictionary = NavalTransport.trim_aboard(fleet, army)
	var men: Array = drowned["regiments"]
	assert_eq(men.size(), 1, "one hull lost, one regiment drowned")
	assert_eq(army.count(), 2)
	assert_eq(String(men[0]), "unit_1100", "the weakest colours drowns first")
	assert_false(army.regiments.has("unit_1100"))
	assert_eq(fleet.embarked_army, army.id, "the men left aboard still ride her")
	assert_eq(NavalTransport.aboard(fleet, army), 2, "one hull, one man")
	assert_eq(
		NavalTransport.drown_news(drowned),
		["1 regiment went down with the sunk hulls — the deck could not hold them"],
		"the bar names the one regiment it lost"
	)


## A deck the sea empties carries no army any more, and the standard leaves with
## the men (wiki: military-armies § Dismissing regiments — an embarked army that
## retires leaves the deck with the field).
func test_a_deck_that_empties_puts_the_standard_aside() -> void:
	var fleet := FleetState.at_sea(6, 0, 0, ["ship_8"])
	var army := ArmyState.muster(12, 0, 0, false, ["pikemen"], 1200)
	fleet.embarked_army = army.id
	army.embarked_fleet = fleet.id
	army.province = MapModel.NO_ID
	fleet.remove_hull("ship_8")
	NavalTransport.trim_aboard(fleet, army)
	assert_true(army.is_empty())
	assert_eq(fleet.embarked_army, -1, "an empty deck carries no army")
	assert_eq(army.embarked_fleet, -1, "and no man is still aboard")


## A raid sinks a merchant hull under the colonists she carries (wiki:
## ships-and-naval § Civilian passengers — one hull carries one civilian).
func test_a_sunk_hull_takes_her_colonist_with_her() -> void:
	var fleet := FleetState.in_port(7, 0, 0, ["ship_9", "ship_10", "ship_11"])
	fleet.add_civilian(21)
	fleet.add_civilian(22)
	fleet.add_civilian(23)
	fleet.remove_hull("ship_11")
	var drowned: Dictionary = NavalTransport.trim_aboard(fleet, null)
	var colonists: Array = drowned["civilians"]
	assert_eq(colonists.size(), 1, "one hull lost, one colonist drowned")
	assert_eq(int(colonists[0]), 23, "the last hand aboard drowns first")
	assert_eq(fleet.civilian_count(), 2)
	assert_eq(NavalTransport.aboard(fleet, null), 2)
	assert_eq(NavalTransport.drown_news(drowned), ["A colonist went down with a sunk hull"])


## The turn's close reads every deck: whichever loss took the hull — a battle's
## sinking or a raid's prize — the men it leaves without a deck go down, and a
## standard the sea emptied retires off the roster.
func test_the_deck_is_reconciled_after_the_hulls_are_lost() -> void:
	var layer := ArmyLayer.new()
	var army := ArmyState.muster(13, 0, 0, false, ["pikemen", "knights"], 1300)
	var fleet := FleetState.at_sea(8, 0, 0, ["ship_12"])
	fleet.embarked_army = army.id
	army.embarked_fleet = fleet.id
	army.province = MapModel.NO_ID
	var roster: Array[ArmyState] = [army]
	layer.regions.set_region(0, roster)
	var rows: Array[Dictionary] = ArmyTransport.reconcile_aboard(layer, [fleet])
	assert_eq(rows.size(), 1, "the squadron that drowned a man is named")
	assert_eq(int(rows[0]["owner"]), 0)
	assert_eq(army.count(), 1)
	assert_eq(fleet.embarked_army, army.id, "one man still rides her")
	fleet.remove_hull("ship_12")
	ArmyTransport.reconcile_aboard(layer, [fleet])
	assert_eq(fleet.embarked_army, -1)
	var left: Array = layer.regions.value(0, [])
	assert_true(left.is_empty(), "the emptied standard retires")
	layer.free()


## The turn's close reads every deck on both charts: a squadron afloat on fewer
## hulls than men drowns the surplus, whichever loss took the hull (wiki:
## ships-and-naval § Naval transport — "each hull carries one regiment").
func test_the_turn_close_reads_every_deck() -> void:
	var world: WorldMap = naval_transport_AiFixture.land_world([0])
	var layer := ArmyLayer.new()
	var army := ArmyState.muster(14, 0, 0, false, ["pikemen", "knights", "musketeers"], 1400)
	var fleet := FleetState.at_sea(9, 0, 0, ["ship_13", "ship_14"])
	fleet.embarked_army = army.id
	army.embarked_fleet = fleet.id
	army.province = MapModel.NO_ID
	var roster: Array[ArmyState] = [army]
	layer.regions.set_region(0, roster)
	var ships := ShipLayer.new()
	ships.regions.set_region(0, [fleet] as Array[FleetState])
	var play := PlaySession.new()
	play.world = world
	play.player_faction = 0
	play.army_layer = layer
	play.ship_layer = ships
	var rows: Array[Dictionary] = MapPlayNavalTurn.reconcile_decks(play)
	assert_eq(rows.size(), 1, "two hulls could not hold three regiments")
	assert_eq(army.count(), 2)
	assert_eq(fleet.embarked_army, army.id)
	assert_true(MapPlayNavalTurn.reconcile_decks(play).is_empty(), "a full deck is silent")
	layer.free()
	ships.free()


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


## A site open by the clock but no longer a hostile shore names the loss, not a
## wait: the coast changed hands or the war ended, so no turn will open it.
func test_a_lapsed_beachhead_names_the_loss_not_a_wait() -> void:
	_setup_naval_movement()
	var pair: Array = _naval_movement_transport_pair()
	var army: ArmyState = pair[0]
	var fleet: FleetState = pair[1]
	NavalTransport.embark(_naval_movement_model, army, fleet)
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 1
	fleet.province = MapModel.NO_ID
	assert_true(bool(NavalTransport.establish_beachhead(
		_naval_movement_model, fleet, 1, 5
	)["ok"]))
	# The war ends before the site opens.
	var peace: Callable = func(_a: int, _b: int) -> bool: return false
	var lapsed: Dictionary = NavalTransport.disembark(
		_naval_movement_model, army, fleet, 1, 6, peace
	)
	assert_false(bool(lapsed["ok"]))
	assert_true(String(lapsed["reason"]).contains("lapsed"), String(lapsed["reason"]))
	assert_false(String(lapsed["reason"]).contains("opens next turn"))


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


## A merge may leave an army pointing at a squadron the chart no longer holds;
## seat_carried rewrites that seat onto the squadron that keeps the troops
## (wiki: military-armies § The muster roll). Guards stay quiet when the layer,
## the squadron or the embarked id is missing.
func test_seat_carried_rewrites_a_lagging_army_pointer() -> void:
	_setup_naval_movement()
	var army := ArmyState.create(7, 0, 0, false, ["unit_7"], {"unit_7": "pikemen"})
	army.embarked_fleet = 99
	var layer: ArmyLayer = _transport_layer(army)
	var fleet := FleetState.in_port(2, 0, 0, ["ship_a"], {"ship_a": "fluyte"})
	fleet.embarked_army = army.id

	ArmyTransport.seat_carried(null, fleet)
	ArmyTransport.seat_carried(layer, null)
	var empty := FleetState.in_port(3, 0, 0, ["ship_b"], {"ship_b": "fluyte"})
	ArmyTransport.seat_carried(layer, empty)
	assert_eq(army.embarked_fleet, 99, "an empty deck does not rewrite a seat")

	empty.embarked_army = 999
	ArmyTransport.seat_carried(layer, empty)
	assert_eq(army.embarked_fleet, 99, "a missing army id is a no-op")

	ArmyTransport.seat_carried(layer, fleet)
	assert_eq(army.embarked_fleet, fleet.id, "the army answers the squadron that carries her")
	ArmyTransport.seat_carried(layer, fleet)
	assert_eq(army.embarked_fleet, fleet.id, "an already-correct seat stays put")
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


## The live order: the crown's bid is filled by the turn's clearing, and the
## cargo it bought is what the next raid pass takes. A price pass that emptied
## the book left the raid with nothing (wiki: ships-and-naval § Trade and
## Transport Interception; DR-20261111-17).
func test_the_map_raid_pass_takes_the_cargo_the_clearing_bought() -> void:
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
	play.ship_layer = ships
	play.economy = economy
	var submit: Dictionary = MarketOrders.submit(
		economy.market, 0, "grain", MarketOrder.SIDE_BID, 4,
		{
			"cargo_free": 4,
			"treasury": economy.economy.treasury,
			"buy_price": economy.market.buy_price("grain", 0),
		}
	)
	assert_true(bool(submit["ok"]), String(submit.get("reason", "")))
	MarketClearing.clear(economy.market, null, {0: economy.economy}, {0: 4})
	var before: int = economy.economy.quantity("grain")
	assert_eq(
		int(economy.market.imports_for(0).get("grain", 0)), 4,
		"the clearing's purchase is cargo afloat"
	)

	var result: Dictionary = MapPlayRaids.resolve(play)

	assert_true(bool(result.get("ok", false)))
	assert_gt(int(result.get("taken", 0)), 0)
	assert_lt(economy.economy.quantity("grain"), before)
	assert_true(
		economy.market.importing_factions().is_empty(),
		"the raid pass is the cargo book's one reader and closes it"
	)
	ships.free()
	economy.free()


## The lane carries the raid the crown suffers, the one that takes the crown's
## own cargo; a prize the crown's stations took reads on the Gazette's sheet
## (wiki: hud-toasts). Rings are drawn for every report either way.
func test_only_the_raid_on_the_crown_reaches_the_lane() -> void:
	var hud := DespatchHud.new()
	add_child(hud)
	var play := PlaySession.new()
	play.player_faction = 0
	play.hud = hud
	var incoming: Dictionary = {
		"kind": "incoming", "raider": 1, "zone_name": "Mar Caribe",
		"taken": 3, "losses": {"grain": 3}, "hulls_lost": [],
	}
	var prize: Dictionary = {
		"kind": "prize", "raider": 0, "victim": 2, "zone_name": "Mar Caribe",
		"taken": 2, "losses": {"timber": 2}, "hulls_lost": [],
	}

	MapPlayRaids._report(play, [incoming, prize])

	assert_eq(hud.toasts.size(), 1, "one raid is the crown's news")
	assert_true(hud.toasts[0].contains("seize"), hud.toasts[0])
	hud.free()


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


## A tie on cargo goes to the lower instance id, not to whichever hull the
## roster happens to list first — a squadron that absorbed another is not in id
## order (wiki: ships-and-naval § Trade and Transport Interception — "the
## richest hold is taken (largest cargoHold, lower instance id on a tie)").
func test_a_cargo_tie_takes_the_lower_instance_id() -> void:
	_setup_naval_raid()
	var merged := FleetState.in_port(
		10, 0, 0, ["ship_9", "ship_2"], {"ship_9": "fluyte", "ship_2": "fluyte"}
	)
	assert_eq(String(NavalHullLoss.at_risk(merged)["id"]), "ship_2")
	var ten := FleetState.in_port(
		11, 0, 0, ["ship_10", "ship_9"], {"ship_10": "fluyte", "ship_9": "fluyte"}
	)
	assert_eq(
		String(NavalHullLoss.at_risk(ten)["id"]), "ship_9",
		"the hull number decides, not the string order"
	)
	var plain := FleetState.in_port(
		12, 0, 0, ["home_9", "home_2"], {"home_9": "fluyte", "home_2": "fluyte"}
	)
	assert_eq(
		String(NavalHullLoss.at_risk(plain)["id"]), "home_2",
		"ids off the ship_<n> pattern still break the tie the same way"
	)
	var raider := _naval_raid_raider()
	var result: Dictionary = NavalRaid.resolve(
		_naval_raid_model, [merged, raider], 0, merged, {"grain": 10}, Callable(), 1, 1, 0.0,
		Callable(), 0.0
	)
	assert_eq((result["hulls_lost"] as Array).size(), 1)
	assert_eq(merged.hulls, ["ship_9"] as Array[String], "the lower-id hull left the fleet")


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


## The cargo the auction filled is afloat until the raid pass has read it: a
## price pass that emptied the book left hostile squadrons nothing to take
## (wiki: ships-and-naval § Trade and Transport Interception — "the victim's own
## purchases this turn"; DR-20261111-17).
func test_the_cargo_book_outlives_the_price_pass_and_closes_at_the_raid() -> void:
	_setup_naval_raid()
	var market: WorldMarket = WorldMarket.with_default_prices()
	var mine: PlayerEconomy = PlayerEconomy.starting()
	mine.treasury = 5000
	assert_true(bool(market.buy(mine, "grain", 2, 0)["ok"]))
	market.advance_prices()
	assert_eq(
		int(market.imports_for(0).get("grain", 0)), 2,
		"price discovery does not empty the cargo the raid pass reads"
	)
	assert_eq(market.importing_factions(), [0] as Array[int])
	market.book.close_cargo()
	assert_true(market.imports_for(0).is_empty())
	assert_true(market.importing_factions().is_empty())


## A bid staged on the book is only cargo once the clearing fills it, and it is
## afloat for the next raid pass (the live path: no direct buy record).
func test_a_filled_bid_leaves_its_cargo_afloat_for_the_raid_pass() -> void:
	_setup_naval_raid()
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.treasury = 5000
	var submit: Dictionary = MarketOrders.submit(
		market, 0, "grain", MarketOrder.SIDE_BID, 3,
		{"cargo_free": 4, "treasury": economy.treasury, "buy_price": market.buy_price("grain", 0)}
	)
	assert_true(bool(submit["ok"]), String(submit.get("reason", "")))
	MarketClearing.clear(market, null, {0: economy}, {0: 4})
	assert_eq(economy.quantity("grain"), PlayerEconomy.starting().quantity("grain") + 3)
	assert_eq(
		int(market.imports_for(0).get("grain", 0)), 3,
		"the clearing's purchase is the tonnage the next raid pass reads"
	)
	assert_eq(market.importing_factions(), [0] as Array[int])


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



## A hull a raid sends down leaves the chart with her: the marker stops flying
## her the moment the rules take her, not on the next rebuild (wiki:
## ships-and-naval § Trade and Transport Interception — "a sunk hull leaves the
## fleet with her name and holds at once").
func test_the_marker_stops_flying_a_hull_a_raid_sank() -> void:
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
	var home := FleetState.in_port(
		10, 0, 0, ["ship_2", "ship_9"], {"ship_2": "fluyte", "ship_9": "fluyte"}
	)
	var raider := _naval_raid_fleet(2, 1, 0, ["frigate"])
	raider.mission = FleetState.Mission.PATROL
	var fleets: Array[FleetState] = [home, raider]
	var ships := ShipLayer.new()
	ships.model = _naval_raid_model
	ships.player_faction = 0
	ships.fleets = fleets
	ships.regions.set_region(_naval_raid_model.region_id, fleets)
	ships.rebuild_markers()
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
	var marker: Ship = ships.ship_for(home)
	assert_eq(marker.hull_count, 2, "both hulls fly before the raid")

	MapPlayRaids.resolve(play)

	assert_eq(home.hulls.size(), 1, "one merchant went down")
	assert_eq(
		ships.ship_for(home).hull_count, 1, "the marker drops the hull the raid sank"
	)
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
	# Cargo afloat lasts until the raid pass has read it: a price pass alone does
	# not empty the book (wiki: ships-and-naval § Trade and Transport
	# Interception).
	economy.market.advance_prices()
	assert_true(
		MapPlayFleetMissions.prize_note(play, blockader).contains("Prize:"),
		"the dossier still prices cargo the clearing left afloat"
	)
	economy.market.book.close_cargo()
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


# --- the sea's despatch (wiki: ships-and-naval § Naval Combat Resolution) -----

const DESPATCH_NAMES: Array[String] = ["España", "England"]


func _dispatch_battle() -> Dictionary:
	return {
		"attacker": 0,
		"defender": 1,
		"attacker_strength": 182.0,
		"defender_strength": 121.0,
		"attacker_before": 6,
		"defender_before": 4,
		"attacker_hulls": [
			"galleon", "galleon", "galleon", "galleon", "sloop", "sloop",
		],
		"defender_hulls": ["carrack", "carrack", "carrack", "carrack"],
		"attacker_lost": ["ship_9"],
		"attacker_lost_names": ["San Juan"],
		"defender_lost": ["a", "b", "c", "d"],
		"defender_lost_names": ["Trinidad", "Concepcion"],
		"outcome": NavalCombat.Outcome.SIDE1_VICTORY,
		"retreat": {},
	}


func test_the_record_carries_the_hulls_each_side_flew() -> void:
	var strong := FleetState.at_sea(
		1, 0, 0, ["ship_1", "ship_2", "ship_3"],
		{"ship_1": "galleon", "ship_2": "galleon", "ship_3": "sloop"}
	)
	strong.moved = true
	var weak := FleetState.at_sea(2, 1, 0, ["ship_4"], {"ship_4": "carrack"})
	var battles: Array[Dictionary] = NavalCombat.resolve_turn([strong, weak])
	var battle: Dictionary = battles[0]
	assert_eq(
		battle["attacker_hulls"], ["galleon", "galleon", "sloop"] as Array[String],
		"the attacker's hulls, by type, in roster order"
	)
	assert_eq(battle["defender_hulls"], ["carrack"] as Array[String])
	assert_eq((battle["attacker_hulls"] as Array).size(), int(battle["attacker_before"]))


func test_the_despatch_groups_the_hulls_by_type() -> void:
	var battle: Dictionary = _dispatch_battle()
	var groups: Array[Dictionary] = NavalDispatch.groups(battle, NavalDispatch.ATTACKER)
	assert_eq(groups.size(), 2, "one medallion per type")
	assert_eq(String(groups[0]["type"]), "galleon", "the biggest group leads")
	assert_eq(int(groups[0]["count"]), 4)
	assert_eq(int(groups[1]["count"]), 2)
	assert_eq(
		NavalDispatch.groups_text(battle, NavalDispatch.ATTACKER),
		"4 Galleon and 2 Sloop"
	)
	assert_eq(NavalDispatch.hull_count(battle, NavalDispatch.DEFENDER), 4)


func test_the_despatch_strikes_the_share_the_resolver_struck() -> void:
	var battle: Dictionary = _dispatch_battle()
	assert_eq(NavalDispatch.strength(battle, NavalDispatch.ATTACKER), 182)
	assert_eq(NavalDispatch.share_percent(battle), 60)
	var maths: String = NavalDispatch.maths_line(battle, DESPATCH_NAMES)
	assert_true(maths.contains("Strength 182 against 121"))
	assert_true(maths.contains("share 60 of 100"), "the share is printed, not guessed")
	assert_true(maths.contains("better than 53"), "the bar the rules use is named")


func test_the_despatch_names_the_meeting_and_the_dead() -> void:
	var battle: Dictionary = _dispatch_battle()
	var opening: String = NavalDispatch.opening(battle, "Mar Caribe", DESPATCH_NAMES)
	assert_true(opening.contains("España's 6 hulls (4 Galleon and 2 Sloop)"))
	assert_true(opening.contains("England's 4 (4 Carrack)"))
	assert_true(opening.contains("in the Mar Caribe"))
	var beats: Array[String] = NavalDispatch.beats(battle, "Mar Caribe", DESPATCH_NAMES)
	assert_eq(beats.size(), 5, "the meeting, the maths, two losses, the verdict")
	assert_eq(beats[2], "España loses 1 ship (San Juan).")
	assert_eq(beats[3], "England loses 4 ships (Trinidad, Concepcion).")
	assert_eq(
		NavalDispatch.outcome_text(battle, "Mar Caribe", DESPATCH_NAMES),
		"España holds the Mar Caribe"
	)


func test_a_withdrawal_and_a_standoff_are_told_differently() -> void:
	var battle: Dictionary = _dispatch_battle()
	battle["retreat"] = {"success": true, "beaten": 1}
	assert_eq(
		NavalDispatch.outcome_text(battle, "Mar Caribe", DESPATCH_NAMES),
		"England withdraws — España holds the Mar Caribe"
	)
	battle["retreat"] = {}
	battle["outcome"] = NavalCombat.Outcome.STALEMATE
	assert_eq(
		NavalDispatch.outcome_text(battle, "Mar Caribe", DESPATCH_NAMES),
		"Neither colour holds the Mar Caribe"
	)
	assert_true(
		NavalDispatch.closing(battle, DESPATCH_NAMES).contains("neither holds the zone")
	)


func test_a_record_without_hull_types_still_tells_the_meeting() -> void:
	var battle: Dictionary = _dispatch_battle()
	battle.erase("attacker_hulls")
	battle.erase("defender_hulls")
	battle["attacker_before"] = 6
	battle["defender_before"] = 4
	var opening: String = NavalDispatch.opening(battle, "", DESPATCH_NAMES)
	assert_eq(opening, "España's 6 hulls meet England's 4 at sea.")
	assert_eq(
		NavalDispatch.headline(battle, "", DESPATCH_NAMES), "España against England"
	)


# --- the turn pass raises the plate for the crown's own fight -----------------

const despatch_NavalFixture = preload("res://tests/naval_fixture.gd")


class DespatchHud extends GameHud:
	var dispatched: Array[String] = []
	var toasts: Array[String] = []

	func toast(text: String, _icon_name: String = "") -> void:
		toasts.append(text)

	func toast_plate_line(text: String, _icon_name: String = "") -> void:
		toasts.append(text)

	func show_naval_dispatch(_battle: Dictionary, zone: String) -> void:
		dispatched.append(zone)


## One session with two hostile squadrons in the Caribbean, and a stub court that
## records what the pass told it.
func _despatch_play(hud: GameHud, fleets: Array[FleetState]) -> PlaySession:
	var model: MapModel = despatch_NavalFixture.build()
	var play := PlaySession.new()
	play.model = model
	play.player_faction = 0
	play.turn = 1
	play.map_seed = 7
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.ensure_relation(0, 1, 1)
	play.diplomacy.ensure_relation(0, 2, 1)
	play.diplomacy.ensure_relation(1, 2, 1)
	var ships := ShipLayer.new()
	ships.model = model
	ships.player_faction = 0
	ships.fleets = fleets
	ships.regions.set_region(model.region_id, fleets)
	play.ship_layer = ships
	var world := WorldMap.new()
	world.add_region(model)
	play.world = world
	var armies := ArmyLayer.new()
	armies.model = model
	armies.regions.set_region(model.region_id, [] as Array[ArmyState])
	play.army_layer = armies
	var civilians := CivilianLayer.new()
	civilians.model = model
	civilians.regions.set_region(model.region_id, [] as Array[CivilianState])
	play.civilian_layer = civilians
	play.hud = hud
	return play


func test_the_crowns_sea_fight_opens_the_despatch_plate() -> void:
	var strong := FleetState.at_sea(1, 0, 0, ["ship_1"], {"ship_1": "galleon"})
	strong.moved = true
	var weak := FleetState.at_sea(2, 1, 0, ["ship_2"], {"ship_2": "carrack"})
	var hud := DespatchHud.new()
	add_child(hud)
	var play: PlaySession = _despatch_play(hud, [strong, weak] as Array[FleetState])
	DiplomacyRules.declare_war(play.diplomacy, 0, 1, false)

	var battles: Array[Dictionary] = MapPlayNavalTurn.resolve(play)

	assert_eq(battles.size(), 1, "two hostile squadrons in one zone fight")
	assert_eq(hud.dispatched.size(), 1, "the crown's fight opens the plate")
	assert_eq(hud.dispatched[0], "Mar Caribe", "the plate names the water")
	assert_eq(hud.toasts.size(), 1, "the despatch line still reaches the court")
	hud.free()
	play.ship_layer.free()


func test_a_rivals_sea_fight_stays_the_courts_news_alone() -> void:
	var strong := FleetState.at_sea(1, 1, 0, ["ship_1"], {"ship_1": "galleon"})
	strong.moved = true
	var weak := FleetState.at_sea(2, 2, 0, ["ship_2"], {"ship_2": "carrack"})
	var hud := DespatchHud.new()
	add_child(hud)
	var play: PlaySession = _despatch_play(hud, [strong, weak] as Array[FleetState])
	# Only the rivals strike each other: the crown keeping its peace hears news.
	DiplomacyRules.declare_war(play.diplomacy, 1, 2, false)

	var battles: Array[Dictionary] = MapPlayNavalTurn.resolve(play)

	assert_eq(battles.size(), 1, "the rivals fight")
	assert_true(hud.dispatched.is_empty(), "the crown's plate is not raised for them")
	assert_true(hud.toasts.is_empty(), "a rival's fight is the Gazette's news")
	hud.free()
	play.ship_layer.free()


## A drowned regiment reaches the lane only when it was the crown's own: a
## rival's loss at sea is its own court's news (wiki: hud-toasts).
func test_a_drowned_rival_regiment_stays_off_the_lane() -> void:
	var hud := DespatchHud.new()
	add_child(hud)
	var play: PlaySession = _despatch_play(hud, [] as Array[FleetState])
	var rival: Array[ArmyState] = [
		ArmyState.muster(1, 1, 0, false, ["peasant_levies"] as Array[String], 9),
	]
	rival[0].embarked_fleet = 99
	play.army_layer.regions.set_region(play.model.region_id, rival)

	MapPlayNavalTurn.resolve(play)

	assert_true(hud.toasts.is_empty(), "a rival's drowned men are its own news")
	var mine: Array[ArmyState] = [
		ArmyState.muster(2, 0, 0, false, ["peasant_levies"] as Array[String], 8),
	]
	mine[0].embarked_fleet = 99
	play.army_layer.regions.set_region(play.model.region_id, mine)

	MapPlayNavalTurn.resolve(play)

	assert_eq(hud.toasts.size(), 1, "the crown's own loss is told")
	assert_true(hud.toasts[0].contains("went down"), hud.toasts[0])
	hud.free()
	play.ship_layer.free()



# --- from test_naval_intel.gd ---
## The crown's watch over rival squadrons.
## The crown's watch over rival squadrons (wiki: ships-and-naval
## § Sighted strength; DR-20261113-20, `NavalIntel`).
## The rule is plain state: a rival sighted this turn is unread until she is
## still in view at a later turn's opening, and leaving the crown's chart starts
## the watch over. The watch is kept per chart, because fleet ids are minted per
## roster and id 5 stands for a different squadron on each map.

const FLEET: int = 41
const OTHER: int = 42
const OLD_WORLD: int = FactionCatalog.OLD_WORLD
const NEW_WORLD: int = FactionCatalog.NEW_WORLD


func test_a_first_sighting_is_unread() -> void:
	var intel := NavalIntel.new()

	assert_eq(intel.observe([FLEET], 5, OLD_WORLD), [])
	assert_false(intel.is_revealed(FLEET, OLD_WORLD), "a first sighting gives up no weight")


func test_the_same_turn_refreshes_do_not_read_her() -> void:
	var intel := NavalIntel.new()

	intel.observe([FLEET], 5, OLD_WORLD)
	intel.observe([FLEET, OTHER], 5, OLD_WORLD)
	intel.observe([FLEET], 5, OLD_WORLD)

	assert_false(intel.is_revealed(FLEET, OLD_WORLD), "the watch needs a turn boundary")
	assert_false(intel.is_revealed(OTHER, OLD_WORLD))


func test_a_rival_still_in_view_next_turn_is_read_once() -> void:
	var intel := NavalIntel.new()
	intel.observe([FLEET], 5, OLD_WORLD)

	assert_eq(intel.observe([FLEET], 6, OLD_WORLD), [FLEET])
	assert_true(intel.is_revealed(FLEET, OLD_WORLD), "a squadron watched across a turn is read")
	assert_eq(intel.observe([FLEET], 7, OLD_WORLD), [], "the news is told once")
	assert_true(intel.is_revealed(FLEET, OLD_WORLD))


func test_a_rival_not_seen_at_the_boundary_is_read_at_the_next_one() -> void:
	var intel := NavalIntel.new()
	intel.observe([FLEET], 5, OLD_WORLD)
	intel.observe([], 6, OLD_WORLD)

	assert_false(intel.is_revealed(FLEET, OLD_WORLD),
		"slipping out of view starts the watch over")
	intel.observe([FLEET], 7, OLD_WORLD)

	assert_false(intel.is_revealed(FLEET, OLD_WORLD), "a fresh sighting is unread again")
	assert_eq(intel.observe([FLEET], 8, OLD_WORLD), [FLEET])


func test_leaving_view_forgets_the_read() -> void:
	var intel := NavalIntel.new()
	intel.observe([FLEET], 5, OLD_WORLD)
	intel.observe([FLEET], 6, OLD_WORLD)
	assert_true(intel.is_revealed(FLEET, OLD_WORLD))

	intel.observe([], 7, OLD_WORLD)

	assert_false(intel.is_revealed(FLEET, OLD_WORLD), "out of sight is out of knowledge")
	assert_eq(intel.watched(OLD_WORLD), [], "no squadrons under the eye")


func test_a_gap_in_the_watch_does_not_read_her() -> void:
	var intel := NavalIntel.new()
	intel.observe([FLEET], 5, OLD_WORLD)
	intel.observe([], 6, OLD_WORLD)
	intel.observe([FLEET], 6, OLD_WORLD)

	assert_false(intel.is_revealed(FLEET, OLD_WORLD), "the second sighting is still this turn")


func test_the_watch_survives_a_save() -> void:
	var intel := NavalIntel.new()
	intel.observe([FLEET], 5, OLD_WORLD)
	intel.observe([FLEET, OTHER], 6, OLD_WORLD)
	var restored: NavalIntel = NavalIntel.from_dict(intel.to_dict())

	assert_true(restored.is_revealed(FLEET, OLD_WORLD), "a read squadron stays read")
	assert_false(restored.is_revealed(OTHER, OLD_WORLD), "an unread squadron stays unread")
	assert_eq(restored.watched(OLD_WORLD), [FLEET, OTHER], "both stay under the eye")
	assert_eq(restored.observe([OTHER], 7, OLD_WORLD), [OTHER], "the clock resumes")


## Fleet ids are minted per roster, so the same id stands for another squadron on
## the other chart: a read earned on one map must never hand over the other's
## weight, and looking away must not clear the watch behind it.
func test_each_chart_keeps_its_own_watch() -> void:
	var intel := NavalIntel.new()
	intel.observe([FLEET], 5, OLD_WORLD)
	intel.observe([FLEET], 6, OLD_WORLD)
	assert_true(intel.is_revealed(FLEET, OLD_WORLD))

	assert_false(intel.is_revealed(FLEET, NEW_WORLD),
		"a New World squadron of the same id is not the Old World one")

	intel.observe([FLEET], 7, NEW_WORLD)

	assert_true(intel.is_revealed(FLEET, OLD_WORLD),
		"another chart is not another water")
	assert_false(intel.is_revealed(FLEET, NEW_WORLD),
		"the New World watch starts from her own sighting")
	assert_eq(intel.watched(NEW_WORLD), [FLEET])

	var restored: NavalIntel = NavalIntel.from_dict(intel.to_dict())
	assert_true(restored.is_revealed(FLEET, OLD_WORLD), "both watches ride the save")
	assert_false(restored.is_revealed(FLEET, NEW_WORLD))


## A save written before the watch was kept per chart carries one flat watch; it
## belonged to the chart the court stood on.
func test_a_flat_watch_from_an_older_save_lands_on_its_own_chart() -> void:
	var legacy: Dictionary = {"seen": {FLEET: 5}, "revealed": [FLEET]}
	var restored: NavalIntel = NavalIntel.from_dict(legacy, NEW_WORLD)

	assert_true(restored.is_revealed(FLEET, NEW_WORLD))
	assert_false(restored.is_revealed(FLEET, OLD_WORLD))
	assert_eq(NavalIntel.from_dict(legacy).watched(NEW_WORLD), [],
		"a flat watch with no chart to sit on is dropped, not guessed")


func test_a_save_without_a_watch_resumes_empty() -> void:
	assert_eq(NavalIntel.from_dict({}).watched(OLD_WORLD), [])
	assert_eq(NavalIntel.from_dict(null).watched(OLD_WORLD), [])
	assert_false(NavalIntel.from_dict({"seen": "stale"}, OLD_WORLD).is_revealed(FLEET, OLD_WORLD))
	assert_false(
		NavalIntel.from_dict({"regions": "stale"}, OLD_WORLD).is_revealed(FLEET, OLD_WORLD)
	)


func test_a_dossier_reads_a_rival_only_once_her_watch_closes() -> void:
	var intel := NavalIntel.new()
	intel.observe([FLEET], 5, OLD_WORLD)
	var my_fleet := FleetState.at_sea(1, 0, 7, ["hull_1"], {"hull_1": "carrack"})
	var rival := FleetState.at_sea(FLEET, 1, 7, ["hull_2"], {"hull_2": "carrack"})
	var known := func(other: FleetState) -> bool: return intel.is_revealed(other.id, OLD_WORLD)

	var unread: Dictionary = NavalStrength.dossier(
		[my_fleet, rival], my_fleet, Callable(), {}, {}, known
	)
	assert_true(bool((unread["zone"] as Dictionary).get("unread", false)),
		"an unread rival weighs nothing in the odds")

	intel.observe([FLEET], 6, OLD_WORLD)
	var read: Dictionary = NavalStrength.dossier(
		[my_fleet, rival], my_fleet, Callable(), {}, {}, known
	)
	assert_false(bool((read["zone"] as Dictionary).get("unread", false)))
	assert_gt(float(read["zone"]["foe"]), 0.0, "a read rival counts in the zone")


func test_a_sighted_rival_dossier_is_fogged() -> void:
	var fogged: Dictionary = NavalStrength.fogged()

	assert_eq(int(fogged["count"]), 1, "the block still shows")
	assert_false(bool(fogged["known"]))
	assert_almost_eq(float(fogged["strength"]), 0.0, 0.0001, "no weight leaks")


# --- the shared war query (from test_hostility_rules) ---
## The naval rules and the rival planners read one hostility predicate
## and one at-war membership set (REQ-P3-03, REQ-P3-04).

func test_a_faction_is_never_hostile_to_itself() -> void:
	assert_false(Hostility.between(Callable(), 3, 3))
	assert_false(Hostility.between(func(_a: int, _b: int) -> bool: return true, 3, 3))


func test_an_unset_query_keeps_every_other_faction_hostile() -> void:
	assert_true(Hostility.between(Callable(), 1, 2))


func test_a_set_query_decides_the_pair() -> void:
	var at_war: Callable = func(a: int, b: int) -> bool: return a == 1 and b == 2
	assert_true(Hostility.between(at_war, 1, 2))
	assert_false(Hostility.between(at_war, 2, 1))


func test_no_court_reads_no_known_wars() -> void:
	assert_true(Hostility.owners(null, 1).is_empty())


func test_owners_lists_every_court_at_war() -> void:
	var state: DiplomacyState = DiplomacyState.new()
	state.initialize(1)
	state.ensure_relation(1, 2).at_war = true
	state.ensure_relation(1, 3).at_war = false
	var hostile: Dictionary = Hostility.owners(state, 1)
	assert_true(hostile.has(2))
	assert_false(hostile.has(3))
	assert_false(hostile.has(1))


# --- test_fleet_passes ---

## The sea's node-free passes: a turn's battles resolve in every region and the
## drowned leave their roster, while the roster surgery a hand-over, a passage
## and a battle need lives in FleetRosters, where the layer, the save and the AI
## read the same list (wiki: map-topology § two regions; ships-and-naval § Naval
## Combat, § Ports that change hands).

const passes_NavalFixture = preload("res://tests/naval_fixture.gd")
const OWNER: int = 0
const RIVAL: int = 1
const CARIBBEAN: int = 0


func test_every_region_fights_and_names_its_battle() -> void:
	var world: WorldMap = _passes_world()
	var regions: MapRegionTable = _passes_regions()

	var battles: Array[Dictionary] = NavalBattles.resolve_region_turn(
		world, regions, _passes_war, {"seed": 7, "turn": 3}
	)

	assert_true(battles.size() >= 1, "two crowns at war in one zone fight")
	for battle: Dictionary in battles:
		assert_eq(int(battle["region"]), 0, "only the Old World's zone is contested")
	assert_eq(
		(regions.value(1, []) as Array).size(), 2,
		"a region with no battle keeps the roster it had"
	)


func test_a_beaten_squadron_leaves_its_region() -> void:
	var world: WorldMap = _passes_world()
	var regions: MapRegionTable = _passes_regions()

	NavalBattles.resolve_region_turn(world, regions, _passes_war, {"seed": 7, "turn": 3})

	var old_world: Array[FleetState] = []
	old_world.assign(regions.value(0, []))
	assert_eq(old_world.size(), 1, "the lone hull goes down and its squadron leaves the roster")
	assert_eq(old_world[0].owner, OWNER, "the victor keeps the sea")
	assert_true(old_world[0].is_afloat())


func test_no_hostility_leaves_the_sea_alone() -> void:
	var world: WorldMap = _passes_world()
	var regions: MapRegionTable = _passes_regions()

	var battles: Array[Dictionary] = NavalBattles.resolve_region_turn(
		world, regions, _passes_peace, {"seed": 7, "turn": 3}
	)

	assert_true(battles.is_empty(), "peace spills no blood")
	assert_eq((regions.value(0, []) as Array).size(), 2, "both squadrons keep the sea")


## --- roster surgery ---------------------------------------------------------


func test_prune_drops_a_squadron_with_no_hulls() -> void:
	var live: FleetState = FleetState.at_sea(1, OWNER, CARIBBEAN, ["ship_1"])
	var sunk: FleetState = FleetState.at_sea(2, RIVAL, CARIBBEAN, ["ship_2"])
	sunk.hulls.clear()
	var roster: Array[FleetState] = [live, sunk, null]

	FleetRosters.prune(roster)

	assert_eq(roster.size(), 2, "a hauled-out squadron leaves")
	assert_eq(roster[0], live, "the live command keeps its berth")
	assert_null(roster[1], "a null slot is not the same as a sunk one: only hulls decide")


func test_hand_over_recolours_or_retires_a_crowns_squadrons() -> void:
	var roster: Array[FleetState] = [
		FleetState.at_sea(1, RIVAL, CARIBBEAN, ["ship_1"]),
		FleetState.at_sea(2, OWNER, CARIBBEAN, ["ship_2"]),
	]

	FleetRosters.hand_over(roster, RIVAL, OWNER)

	assert_eq(roster.size(), 2, "an absorption keeps every hull")
	assert_eq(roster[0].owner, OWNER, "the loser's colours change")

	FleetRosters.hand_over(roster, OWNER, MapModel.NO_ID)

	assert_true(roster.is_empty(), "a terminal fall retires every squadron it owned")


func test_a_passage_renumbers_the_crossing_squadron() -> void:
	var regions: MapRegionTable = _passes_regions()
	var from: Array[FleetState] = []
	from.assign(regions.value(0, []))
	var crossing: FleetState = from[0]

	var destination: Array[FleetState] = FleetRosters.hand_to_region(
		regions, 0, crossing, 1, from
	)

	assert_eq(destination.size(), 3, "the squadron lands in the other roster")
	assert_eq(int((regions.value(0, []) as Array).size()), 1, "and leaves the one it sailed from")
	assert_eq(crossing.id, 5, "it takes the next free id across every region")
	var ids: Array[int] = []
	for region: Array in FleetRosters.all(regions):
		for fleet: FleetState in region:
			ids.append(fleet.id)
	ids.sort()
	assert_eq(ids, [2, 3, 4, 5] as Array[int], "both rosters list every hull and no id twice")


func test_zones_at_sea_lists_each_zone_once() -> void:
	var roster: Array[FleetState] = [
		FleetState.at_sea(1, OWNER, CARIBBEAN, ["ship_1"]),
		FleetState.at_sea(2, OWNER, CARIBBEAN, ["ship_2"]),
		FleetState.at_sea(3, OWNER, 1, ["ship_3"]),
		FleetState.at_sea(4, RIVAL, 1, ["ship_4"]),
		FleetState.in_port(5, OWNER, 0, ["ship_5"]),
	]

	assert_eq(
		FleetRosters.zones_at_sea(roster, OWNER), [CARIBBEAN, 1] as Array[int],
		"one entry per zone the crown holds, and no port"
	)
	assert_true(FleetRosters.zones_at_sea(roster, 9).is_empty(), "a crown at no sea holds no zone")


func test_each_visits_every_region_roster() -> void:
	var regions: MapRegionTable = _passes_regions()
	var seen: Array[int] = []

	FleetRosters.each(
		regions, func(roster: Array[FleetState]) -> void: seen.append(roster.size())
	)

	seen.sort()
	assert_eq(seen, [2, 2] as Array[int], "every stored roster is visited once")


## --- berths -----------------------------------------------------------------


func test_prune_drops_the_marker_of_a_sunk_squadron() -> void:
	var markers := ShipMarkers.new()
	markers.model = passes_NavalFixture.build()
	var kept: FleetState = FleetState.at_sea(1, OWNER, CARIBBEAN, ["ship_1"])
	var sunk: FleetState = FleetState.at_sea(2, RIVAL, CARIBBEAN, ["ship_2"])
	var kept_marker: Ship = markers.make(kept)
	var sunk_marker: Ship = markers.make(sunk)
	markers.selected_ship = sunk_marker

	markers.prune([kept] as Array[FleetState])

	assert_eq(markers.ships.size(), 1, "only the squadron still on the roster keeps a marker")
	assert_eq(markers.ships[0], kept_marker)
	assert_null(markers.selected_ship, "a selection cannot outlive the hull that wore it")
	markers.remove(kept_marker)


func test_a_port_berth_prefers_the_registered_tile() -> void:
	var model: MapModel = passes_NavalFixture.build()

	assert_eq(
		ShipMarkers.port_position(model, 0),
		MapGeo.tile_center(1, 0, ShipMarkers.TILE_SIZE),
		"the harbour tile is the berth"
	)
	model.provinces[0].port_tile = Vector2i(-1, -1)
	assert_eq(
		ShipMarkers.port_position(model, 0),
		model.province_center(0) * ShipMarkers.TILE_SIZE,
		"a province with no harbour tile berths at its centre"
	)


## --- fleets in one station (wiki: ships-and-naval § Fleets in one station;
## DR-20261119-08) ------------------------------------------------------------


## Four of the crown's squadrons and one rival, all in the Mar Caribe, in id
## order: 1-3 stand in the row, 4 leads the stack, 5 rides behind her.
func _station_fleets() -> Array[FleetState]:
	var fleets: Array[FleetState] = []
	for index in 5:
		var owner: int = RIVAL if index == 4 else OWNER
		fleets.append(FleetState.at_sea(index + 1, owner, CARIBBEAN, ["ship_%d" % (index + 1)]))
	return fleets


## The crown's squadrons in one water fan out in a short row; the rest of hers
## and every rival's ride one stack whose head draws the hull, so a rival is
## never a nation row of her own.
func test_a_shared_station_fans_the_crown_out_and_stacks_the_rest() -> void:
	var fleets: Array[FleetState] = _station_fleets()
	var plan: Dictionary = FleetLanes.plan(fleets, OWNER)
	var lanes: Dictionary = plan["lanes"]
	var stacks: Dictionary = plan["stacks"]

	# Four slots: the crown's three in a row, then the stack the rest ride.
	assert_eq(lanes.size(), 4, "three fan steps and one stack head")
	assert_eq(lanes[1], Vector2(-1.5, 0.0) * FleetLanes.LANE_SPAN)
	assert_eq(lanes[2], Vector2(-0.5, 0.0) * FleetLanes.LANE_SPAN)
	assert_eq(lanes[3], Vector2(0.5, 0.0) * FleetLanes.LANE_SPAN)
	assert_eq(lanes[4], Vector2(1.5, 0.0) * FleetLanes.LANE_SPAN)
	assert_false(lanes.has(5), "the rival behind the head draws no hull of her own")
	assert_eq(int(plan["fronts"]["sea:0"]), 4, "the crown's fourth draws the stack")
	assert_eq(stacks[4].size(), 2, "her fourth and the rival walk one cycle")
	assert_eq(int(stacks[4][1]), 5, "the cycle keeps the station's own order")


## A station of rivals only is one stack, never a row: the crown reads their
## courts through the cycle, one command at a time.
func test_a_station_of_rivals_is_one_stack() -> void:
	var fleets: Array[FleetState] = [
		FleetState.at_sea(7, RIVAL, CARIBBEAN, ["a"]),
		FleetState.at_sea(8, 2, CARIBBEAN, ["b"]),
	]
	var plan: Dictionary = FleetLanes.plan(fleets, OWNER)

	assert_eq((plan["lanes"] as Dictionary).size(), 1, "one hull for the whole water")
	assert_eq((plan["stacks"] as Dictionary)[7].size(), 2)
	assert_false((plan["lanes"] as Dictionary).has(8), "the second rival is covered")


## The markers take the plan: each fanned squadron draws at her own step, a
## covered squadron draws no hull, and the head wears the pennants of the courts
## stacked behind her.
func test_the_markers_lay_the_row_out_and_cover_the_stack() -> void:
	var markers := ShipMarkers.new()
	markers.model = passes_NavalFixture.build()
	var fleets: Array[FleetState] = _station_fleets()
	for fleet: FleetState in fleets:
		markers.make(fleet)
	markers.layout(fleets, OWNER)
	var first: Ship = markers.find(1)
	var second: Ship = markers.find(2)
	var head: Ship = markers.find(4)
	var behind: Ship = markers.find(5)

	assert_lt(first.drawn_position().x, second.drawn_position().x, "the row runs left to right")
	assert_false(first.covered)
	assert_false(head.covered, "the head of the stack draws the hull")
	assert_true(behind.covered, "the squadron behind her draws none")
	assert_true(head.shows_hull())
	assert_false(behind.shows_hull())
	assert_eq(head.pips.size(), 1, "one pennant for the court behind her")
	assert_eq(int(head.pips[0]), RIVAL, "and it flies that court's colour")
	assert_true(behind.pips.is_empty() or behind.pips.size() == 1)

	# The plate prints on the squadron in the crown's hand, and always on a rival
	# the fog has not read (wiki: ships-and-naval § Fleets in one station,
	# § Sighted strength).
	assert_false(first.shows_plate(), "a read squadron out of hand keeps her figure back")
	first.set_selected(true)
	assert_true(first.shows_plate(), "the squadron in hand prints it")
	behind.set_intel(false)
	assert_true(behind.shows_plate(), "an unread rival's plate still says the fog withholds it")


## The crown's selection comes to the head of her stack, so the squadron she is
## reading keeps drawing the hull; a rival the fog withholds never takes it.
func test_the_selection_leads_the_stack_and_the_fog_keeps_her_hidden() -> void:
	var markers := ShipMarkers.new()
	markers.model = passes_NavalFixture.build()
	var fleets: Array[FleetState] = []
	for index in 3:
		fleets.append(FleetState.at_sea(index + 1, RIVAL, CARIBBEAN, ["ship_%d" % index]))
	for fleet: FleetState in fleets:
		markers.make(fleet)
	markers.layout(fleets, OWNER)
	assert_eq(int(markers.find(1).stack[0]), 1, "the first rival draws the stack")

	markers.selected_ship = markers.find(3)
	markers.layout(fleets, OWNER)
	assert_false(markers.find(3).covered, "the squadron in hand draws the hull")
	assert_true(markers.find(1).covered)
	assert_eq(int(markers.find(3).stack.find(3)), 2, "her place in the cycle never moves")

	# The fog takes the first rival: the head passes to the next one drawn.
	markers.find(1).visible = false
	markers.selected_ship = null
	markers.layout(fleets, OWNER)
	assert_true(markers.find(1).covered, "a rival under the fog is never handed the hull")
	assert_false(markers.find(2).covered)
	assert_eq(markers.next_in_stack(markers.find(2)).fleet_id, 3, "the cycle skips her")


## A shared station's reading order names every squadron the chart draws there —
## the crown's row first, then the stack behind it — and never one the fog
## withholds, so a tap on the row still says which command of the water is in
## hand (wiki: ships-and-naval § Fleets in one station).
func test_a_shared_station_names_every_hull_the_chart_draws() -> void:
	var fleets: Array[FleetState] = _station_fleets()
	var plan: Dictionary = FleetLanes.plan(fleets, OWNER)
	var stations: Dictionary = plan["stations"]

	assert_eq((stations[1] as Array).size(), 5, "four of the crown's and the rival")
	assert_eq(int((stations[1] as Array)[0]), 1, "the row leads the reading")
	assert_eq(int((stations[1] as Array)[3]), 4, "the stack stands after the row")

	# The fog's rival is not counted, and her colour rides no pennant.
	var fogged: Array[int] = [5]
	var hidden_plan: Dictionary = FleetLanes.plan(fleets, OWNER, -1, fogged)
	var hidden_stations: Dictionary = hidden_plan["stations"] as Dictionary
	assert_eq((hidden_stations[1] as Array).size(), 4, "the unseen rival is not counted")
	assert_false((hidden_stations[1] as Array).has(5), "and holds no place in the order")

	var markers := ShipMarkers.new()
	markers.model = passes_NavalFixture.build()
	for fleet: FleetState in fleets:
		markers.make(fleet)
	markers.find(5).visible = false
	markers.layout(fleets, OWNER)
	assert_eq(markers.find(4).station.size(), 4, "the head reads what the chart draws")
	assert_true(markers.find(4).pips.is_empty(), "an unseen court wears no pennant")


## The crown's row keeps its own reading when the stack is empty: a fanned
## squadron is told her place among the water's commands, not her place in a
## cycle she never joined (wiki: ships-and-naval § Fleets in one station).
func test_a_fanned_squadron_still_reads_her_station() -> void:
	var fleets: Array[FleetState] = []
	for index in 2:
		fleets.append(FleetState.at_sea(index + 1, OWNER, CARIBBEAN, ["ship_%d" % index]))
	var markers := ShipMarkers.new()
	markers.model = passes_NavalFixture.build()
	for fleet: FleetState in fleets:
		markers.make(fleet)
	markers.layout(fleets, OWNER)
	var first: Ship = markers.find(1)
	assert_true(first.stack.is_empty(), "a row of two rides no stack")
	assert_eq(first.station.size(), 2, "the station's reading still holds both hulls")
	assert_eq(int(first.station[0]), 1)


## --- fixtures ---------------------------------------------------------------


## Two Old-World charts: region 0 is at war over the Caribbean with four carracks
## against one sloop, region 1 keeps two squadrons of one crown in company.
func _passes_world() -> WorldMap:
	var world := WorldMap.new()
	for index in 2:
		var model: MapModel = passes_NavalFixture.build()
		model.region_id = index
		world.add_region(model)
	return world


func _passes_regions() -> MapRegionTable:
	var regions := MapRegionTable.new()
	var strong: Array[FleetState] = [
		FleetState.at_sea(
			1, OWNER, CARIBBEAN, ["ship_1", "ship_2", "ship_3", "ship_4"],
			{"ship_1": "carrack", "ship_2": "carrack", "ship_3": "carrack", "ship_4": "carrack"}
		),
	]
	var weak: Array[FleetState] = [
		FleetState.at_sea(2, RIVAL, CARIBBEAN, ["ship_5"], {"ship_5": "sloop"}),
	]
	var company: Array[FleetState] = [
		FleetState.at_sea(3, RIVAL, CARIBBEAN, ["ship_6"], {"ship_6": "carrack"}),
		FleetState.at_sea(4, RIVAL, CARIBBEAN, ["ship_7"], {"ship_7": "carrack"}),
	]
	var old_world: Array[FleetState] = []
	old_world.append_array(strong)
	old_world.append_array(weak)
	regions.set_region(0, old_world)
	regions.set_region(1, company)
	return regions


## The court's war query: the two crowns of the Old World are at war.
func _passes_war(a: int, b: int) -> bool:
	return (a == OWNER and b == RIVAL) or (a == RIVAL and b == OWNER)


## The same query in peacetime: no pair is hostile.
func _passes_peace(_a: int, _b: int) -> bool:
	return false

# --- fleet_split ---

## A sea-going squadron of three hulls, mixed types, moored nowhere.
func _split_fleet() -> FleetState:
	return FleetState.at_sea(
		2, 0, 0, ["ship_1", "ship_2", "ship_3"],
		{"ship_1": "carrack", "ship_2": "sloop", "ship_3": "fluyte"}
	)

func test_a_hull_detaches_into_a_squadron_of_her_own() -> void:
	_setup_fleet_sortie()
	var fleet: FleetState = _split_fleet()
	var fleets: Array[FleetState] = [fleet]
	var flown: String = ShipNames.of(fleet, "ship_2")

	var result: Dictionary = FleetSplit.detach(
		_fleet_sortie_model, fleets, fleet, "ship_2", 9
	)

	assert_true(bool(result["ok"]), String(result["reason"]))
	assert_eq(fleet.hulls, ["ship_1", "ship_3"], "the squadron keeps her other hulls")
	var split: FleetState = result["fleet"] as FleetState
	assert_not_null(split)
	assert_eq(split.id, 9, "she takes the id the roster offered")
	assert_eq(split.hulls, ["ship_2"], "the detached hull flies alone")
	assert_eq(split.type_of("ship_2"), "sloop", "she keeps her catalog type")
	assert_eq(ShipNames.of(split, "ship_2"), flown, "she keeps the name she flew")
	assert_true(split.is_at_sea())
	assert_eq(split.sea_zone, fleet.sea_zone, "she stands in the same water")
	assert_eq(fleets.size(), 2, "the roster keeps both commands")
	assert_eq(String(result["name"]), flown)

func test_the_new_squadron_takes_no_station_and_keeps_the_readiness() -> void:
	_setup_fleet_sortie()
	var fleet: FleetState = _split_fleet()
	fleet.moved = true
	fleet.mission = FleetState.Mission.PATROL
	fleet.beachhead_province = 1
	fleet.beachhead_turn = 4
	fleet.add_civilian(11)
	var fleets: Array[FleetState] = [fleet]

	var result: Dictionary = FleetSplit.detach(
		_fleet_sortie_model, fleets, fleet, "ship_3", 9
	)

	assert_true(bool(result["ok"]), String(result["reason"]))
	var split: FleetState = result["fleet"] as FleetState
	assert_true(split.moved, "a hull that has sailed does not sail again")
	assert_eq(split.mission, FleetState.Mission.NONE, "the station stays with the squadron")
	assert_eq(split.blockade_province, MapModel.NO_ID)
	assert_false(split.has_beachhead(), "a landing site is one squadron's")
	assert_eq(split.civilian_count(), 0, "the colonists stay aboard the squadron")
	assert_eq(fleet.civilian_count(), 1)

func test_a_squadron_of_one_hull_has_nothing_to_detach() -> void:
	_setup_fleet_sortie()
	var fleet := FleetState.at_sea(2, 0, 0, ["ship_1"])
	var fleets: Array[FleetState] = [fleet]

	var check: Dictionary = FleetSplit.can_detach(_fleet_sortie_model, fleet, "ship_1")

	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("one hull"))
	assert_eq(fleets.size(), 1)

func test_a_hull_that_is_not_aboard_is_refused() -> void:
	_setup_fleet_sortie()
	var fleet: FleetState = _split_fleet()
	var fleets: Array[FleetState] = [fleet]

	var result: Dictionary = FleetSplit.detach(
		_fleet_sortie_model, fleets, fleet, "ship_99", 9
	)

	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("not aboard"))
	assert_eq(fleet.hulls.size(), 3, "nothing leaves the squadron")
	assert_eq(fleets.size(), 1, "no command is founded")

func test_the_home_squadron_keeps_the_seat() -> void:
	_setup_fleet_sortie()
	var home := FleetState.in_port(1, 0, 0, ["a", "b"], {"a": "fluyte", "b": "carrack"})
	var moored := FleetState.in_port(4, 1, 0, ["c", "d"], {"c": "fluyte", "d": "carrack"})

	var check: Dictionary = FleetSplit.can_detach(_fleet_sortie_model, home, "a")

	assert_true(NavalMovement.is_home_fleet(_fleet_sortie_model, home))
	assert_false(bool(check["ok"]), "only the home fleet lies in port at the seat")
	assert_true(String(check["reason"]).contains("home squadron"))
	assert_true(
		bool(FleetSplit.can_detach(_fleet_sortie_model, moored, "c")["ok"]),
		"a squadron in a foreign port may still split"
	)

func test_a_hull_leaves_only_when_the_passengers_fit() -> void:
	_setup_fleet_sortie()
	var crowded := FleetState.at_sea(
		2, 0, 0, ["ship_1", "ship_2"], {"ship_1": "carrack", "ship_2": "sloop"}
	)
	crowded.add_civilian(11)
	crowded.add_civilian(12)

	var check: Dictionary = FleetSplit.can_detach(_fleet_sortie_model, crowded, "ship_1")

	assert_false(bool(check["ok"]), "two colonists need two hulls")
	assert_true(String(check["reason"]).contains("2 passengers"))
	crowded.add_hull("ship_3", "carrack")
	assert_true(bool(FleetSplit.can_detach(_fleet_sortie_model, crowded, "ship_1")["ok"]))

func test_troops_aboard_hold_the_squadron_whole() -> void:
	_setup_fleet_sortie()
	var fleet: FleetState = _split_fleet()
	fleet.embarked_army = 7

	var check: Dictionary = FleetSplit.can_detach(_fleet_sortie_model, fleet, "ship_1")

	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("Land the troops"))

func test_the_rows_read_every_hull_and_name_her() -> void:
	_setup_fleet_sortie()
	var fleet: FleetState = _split_fleet()

	var rows: Array[Dictionary] = FleetSplit.rows(_fleet_sortie_model, fleet)

	assert_eq(rows.size(), 3, "every hull of the squadron is on the list")
	for row: Dictionary in rows:
		assert_true(bool(row["ok"]), String(row["reason"]))
		assert_eq(String(row["name"]), ShipNames.of(fleet, String(row["hull"])))
		assert_false(String(row["type_name"]).is_empty())
	assert_eq(FleetSplit.rows(_fleet_sortie_model, null), [] as Array[Dictionary])

func test_the_split_drawer_lists_every_hull_and_files_one_tap() -> void:
	_setup_fleet_sortie()
	var block := FleetSplitBlock.new()
	add_child(block)
	var fleet: FleetState = _split_fleet()
	var emitted: Array[String] = []
	block.action_pressed.connect(func(action: String) -> void: emitted.append(action))

	block.show_rows(_fleet_sortie_model, fleet, true, false)

	assert_true(block._button.visible, "a squadron of three hulls may split")
	assert_false(block._scroll.visible, "the drawer waits for a tap")
	assert_eq(block._note.text, FleetSplit.NOTE, "the rule sits on the sheet")
	block.set_open(true)
	assert_true(block._scroll.visible)
	var detaches: Array[Button] = []
	for node: Node in block.find_children("*", "Button", true, false):
		if (node as Button).text == "Detach":
			detaches.append(node as Button)
	assert_eq(detaches.size(), 3, "every hull offers her own detach")
	var hull_name: String = ShipNames.of(fleet, "ship_1")
	var printed: bool = false
	for node: Node in block.find_children("*", "Label", true, false):
		var text: String = (node as Label).text
		if text.contains(hull_name) and text.contains("Carrack"):
			printed = true
	assert_true(printed, "the row prints '%s — Carrack'" % hull_name)
	detaches[0].pressed.emit()
	assert_eq(emitted, ["split:ship_1"], "the tap hands the hull to the dossier")
	block.free()

func test_the_split_drawer_names_the_gate_instead_of_a_press() -> void:
	_setup_fleet_sortie()
	var block := FleetSplitBlock.new()
	add_child(block)
	var home := FleetState.in_port(1, 0, 0, ["a", "b"], {"a": "fluyte", "b": "carrack"})

	block.show_rows(_fleet_sortie_model, home, true, false)

	assert_false(block._button.visible, "the home squadron keeps the seat")
	assert_true(block._note.visible, "the reason is on the sheet, not in a hover")
	assert_true(block._note.text.contains("home squadron"), block._note.text)
	block.show_rows(_fleet_sortie_model, home, false, false)
	assert_false(block._note.visible, "a rival's squadron reads nothing")
	block.free()

func test_a_squadron_of_one_hull_shows_no_drawer() -> void:
	_setup_fleet_sortie()
	var block := FleetSplitBlock.new()
	add_child(block)
	var fleet := FleetState.at_sea(2, 0, 0, ["ship_1"])

	block.show_rows(_fleet_sortie_model, fleet, true, false)

	assert_false(block._button.visible)
	assert_false(block._note.visible, "nothing to explain on a single hull")
	block.free()
