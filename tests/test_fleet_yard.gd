extends GdToolsTest
## The naval yard: a hull costs its published build row plus one peasant, tech
## gates each type, and the breaker's yard returns the head
## (wiki: ships-and-naval § Ship build economy, § Ship muster and the breaker's
## yard; DR-20261109-01). Pure rules, so no scene is needed.

var _econ: PlayerEconomy


func before_each() -> void:
	_econ = PlayerEconomy.starting()
	_econ.treasury = 60000


func test_launch_pays_the_row_and_one_peasant() -> void:
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
	var fleet := FleetState.empty_in_port(7, 0, 1)
	_econ.tech_unlocked["advanced_hull_design"] = true

	var result: Dictionary = FleetYard.launch(_econ, fleet, "frigate", "ship_9")

	assert_true(bool(result["ok"]), String(result["reason"]))
	assert_eq(fleet.type_of("ship_9"), "frigate")


func test_no_peasant_refuses_the_launch_and_spends_nothing() -> void:
	var fleet := FleetState.empty_in_port(7, 0, 1)
	_econ.workers.set_count(WorkerPool.Tier.PEASANT, 0)
	var treasury: int = _econ.treasury

	var result: Dictionary = FleetYard.launch(_econ, fleet, "carrack", "ship_9")

	assert_false(bool(result["ok"]))
	assert_eq(String(result["reason"]), "Insufficient workers")
	assert_eq(fleet.ship_count(), 0)
	assert_eq(_econ.treasury, treasury)


func test_insufficient_materials_refuse_the_launch() -> void:
	var fleet := FleetState.empty_in_port(7, 0, 1)
	_econ.stockpile["lumber"] = 1

	var result: Dictionary = FleetYard.launch(_econ, fleet, "carrack", "ship_9")

	assert_false(bool(result["ok"]))
	assert_eq(String(result["reason"]), "Insufficient materials")
	assert_eq(fleet.ship_count(), 0)


func test_the_breaker_yard_returns_one_peasant() -> void:
	var fleet := FleetState.at_sea(3, 0, 2, ["ship_1", "ship_2"], {"ship_2": "sloop"})
	var peasants: int = _econ.available_peasants()

	var result: Dictionary = FleetYard.scrap(_econ, fleet, "ship_2")

	assert_true(bool(result["ok"]), String(result["reason"]))
	assert_eq(fleet.hulls, ["ship_1"])
	assert_eq(_econ.available_peasants(), peasants + 1)
	assert_false(bool(result["retired"]))
	assert_eq(_econ.treasury, 60000, "no treasury is refunded")


func test_breaking_up_the_last_hull_retires_the_squadron() -> void:
	var fleet := FleetState.at_sea(3, 0, 2, ["ship_1"])

	var result: Dictionary = FleetYard.scrap(_econ, fleet, "ship_1")

	assert_true(bool(result["ok"]))
	assert_true(bool(result["retired"]))
	assert_false(fleet.is_afloat())


func test_a_hull_must_belong_to_the_fleet() -> void:
	var fleet := FleetState.at_sea(3, 0, 2, ["ship_1"])

	var result: Dictionary = FleetYard.scrap(_econ, fleet, "ship_99")

	assert_false(bool(result["ok"]))
	assert_eq(fleet.hulls, ["ship_1"])


func test_rows_lead_with_payable_hulls_and_reason_the_locked_ones() -> void:
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
	var rows: Array[Dictionary] = FleetYard.rows(_econ, false)

	for row: Dictionary in rows:
		assert_false(bool(row["ok"]))
		assert_eq(String(row["reason"]), "Launch hulls at your capital port.")


func test_every_hull_names_a_real_tech_or_none() -> void:
	for type_id: String in ShipEconomy.ENTRIES.keys():
		var tech: String = ShipEconomy.tech_for(type_id)
		if type_id == "carrack":
			assert_eq(tech, "", "the carrack never needs research")
			continue
		assert_false(tech.is_empty(), type_id)
		assert_true(TechCatalog.known(tech), tech)


func test_cost_text_reads_as_a_yard_ledger() -> void:
	var text: String = ShipEconomy.cost_text("carrack")

	assert_true(text.contains("8,000 ducats"))
	assert_true(text.contains("2 Lumber"))
	assert_true(text.contains("1 Fabric"))
	assert_true(text.contains("1 worker"))


func test_hull_firepower_sums_into_ship_strength() -> void:
	var fleet := FleetState.at_sea(3, 0, 2, ["ship_1", "ship_2"], {"ship_2": "sloop"})

	assert_eq(ShipStats.firepower("carrack"), 2)
	assert_eq(ShipStats.firepower("sloop"), 2)
	assert_eq(FleetPanel.strength_of(fleet), 4)
	assert_eq(FleetPanel.strength_of(null), 0)
