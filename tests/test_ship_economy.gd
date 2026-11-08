extends GdToolsTest
## Ship build economy and food upkeep (wiki: ships-and-naval).

const ROSTER: Array[String] = [
	"carrack",
	"fluyte",
	"sloop",
	"trader",
	"galleon",
	"indiaman",
	"frigate",
	"raider",
	"ship_of_the_line",
	"clipper",
	"merchant_steamship",
	"ironclad",
]


func test_catalog_covers_the_whole_roster() -> void:
	assert_eq(ShipEconomy.ENTRIES.size(), ROSTER.size())
	for ship_id: String in ROSTER:
		assert_true(ShipEconomy.known(ship_id), ship_id)
		assert_true(ShipStats.known(ship_id), ship_id)


func test_frozen_baseline_rows_match_the_wiki() -> void:
	assert_eq(ShipEconomy.treasury_cost("carrack"), 8000)
	assert_eq(ShipEconomy.build_inputs("carrack"), {"lumber": 2, "fabric": 1})
	assert_true(ShipEconomy.is_always_buildable("carrack"))
	assert_eq(ShipEconomy.unlock_era("carrack"), 0)
	assert_eq(ShipEconomy.treasury_cost("fluyte"), 6000)
	assert_eq(ShipEconomy.build_inputs("fluyte"), {"lumber": 1, "fabric": 1})
	assert_eq(ShipEconomy.unlock_era("fluyte"), 1)


func test_steam_and_line_rows_match_the_wiki() -> void:
	assert_eq(ShipEconomy.treasury_cost("ship_of_the_line"), 16500)
	assert_eq(ShipEconomy.build_inputs("ship_of_the_line"), {"lumber": 5, "fabric": 3})
	assert_eq(ShipEconomy.unlock_era("ship_of_the_line"), 3)
	assert_eq(ShipEconomy.treasury_cost("ironclad"), 21000)
	assert_eq(
		ShipEconomy.build_inputs("ironclad"), {"lumber": 2, "fabric": 2, "castIron": 5}
	)
	assert_eq(ShipEconomy.unlock_era("ironclad"), 4)
	assert_eq(ShipEconomy.treasury_cost("merchant_steamship"), 15500)
	assert_eq(
		ShipEconomy.build_inputs("merchant_steamship"),
		{"lumber": 2, "fabric": 2, "coal": 3}
	)
	assert_eq(ShipEconomy.treasury_cost("raider"), 11500)
	assert_eq(
		ShipEconomy.build_inputs("raider"), {"lumber": 2, "fabric": 1, "castIron": 2}
	)


func test_roles_align_with_ship_stats() -> void:
	for ship_id: String in ROSTER:
		var role: String = String(ShipEconomy.entry(ship_id)["role"])
		if ShipStats.is_warship(ship_id):
			assert_eq(role, "warship", ship_id)
		else:
			assert_eq(role, "merchant", ship_id)


func test_unknown_types_fall_back_to_the_carrack() -> void:
	assert_false(ShipEconomy.known("dromon"))
	assert_eq(ShipEconomy.entry("dromon"), ShipEconomy.entry("carrack"))
	assert_eq(ShipEconomy.treasury_cost("dromon"), 8000)


func test_food_upkeep_is_two_per_hull() -> void:
	assert_eq(ShipEconomy.FOOD_UPKEEP_PER_SHIP, 2)
	assert_eq(ShipEconomy.food_upkeep_per_ship("carrack"), 2)
	assert_eq(ShipEconomy.food_upkeep_per_ship("ironclad"), 2)
	var fleet: FleetState = FleetState.at_sea(
		1, 0, 3, ["ship_1", "ship_2", "ship_3"], {"ship_1": "sloop", "ship_2": "carrack"}
	)
	assert_eq(ShipEconomy.food_upkeep_for_fleet(fleet), 6)
	var minted: FleetState = FleetState.at_sea(2, 0, 3, [])
	# Factory still mints one default hull when none are given.
	assert_eq(ShipEconomy.food_upkeep_for_fleet(minted), 2)
	var sunk: FleetState = FleetState.at_sea(3, 0, 3, ["ship_9"])
	sunk.remove_hull("ship_9")
	assert_eq(ShipEconomy.food_upkeep_for_fleet(sunk), 0)
	assert_eq(ShipEconomy.food_upkeep_for_fleet(null), 0)


func test_food_upkeep_sums_owned_fleets_only() -> void:
	var fleets: Array[FleetState] = [
		FleetState.at_sea(1, 0, 1, ["ship_1", "ship_2"]),
		FleetState.at_sea(2, 1, 2, ["ship_3", "ship_4", "ship_5"]),
		FleetState.in_port(3, 0, 4, ["ship_6"]),
	]
	assert_eq(ShipEconomy.food_upkeep_for_owner(fleets, 0), 6)
	assert_eq(ShipEconomy.food_upkeep_for_owner(fleets, 1), 6)
	assert_eq(ShipEconomy.food_upkeep_for_owner(fleets, 2), 0)


func test_can_afford_checks_treasury_and_materials() -> void:
	var stock: Dictionary = {"lumber": 2, "fabric": 1}
	assert_true(ShipEconomy.can_afford("carrack", 8000, stock))
	assert_false(ShipEconomy.can_afford("carrack", 7999, stock))
	assert_false(ShipEconomy.can_afford("carrack", 8000, {"lumber": 1, "fabric": 1}))
	assert_true(ShipEconomy.can_afford("sloop", 5500, {"lumber": 1, "fabric": 1}))
	assert_false(
		ShipEconomy.can_afford("ironclad", 21000, {"lumber": 2, "fabric": 2, "castIron": 4})
	)
	assert_true(
		ShipEconomy.can_afford("ironclad", 21000, {"lumber": 2, "fabric": 2, "castIron": 5})
	)


func test_missing_inputs_lists_shortfalls() -> void:
	var short: Dictionary = ShipEconomy.missing_inputs(
		"raider", {"lumber": 1, "fabric": 1, "castIron": 0}
	)
	assert_eq(short, {"lumber": 1, "castIron": 2})
	assert_eq(ShipEconomy.missing_inputs("carrack", {"lumber": 2, "fabric": 1}), {})
