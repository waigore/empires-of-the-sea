extends GdToolsTest
## Overseas cargo: colony yield crosses on the home fleet's holds, richest
## commodity first, and undelivered tonnage stays abroad (wiki:
## extraction-and-improvements § Flow to Stockpile; DR-20261109-17).


func _region(owner_resource: int = 0) -> MapModel:
	var model := MapModel.new()
	model.setup(2, 1)
	model.province[model.index_of(0, 0)] = 0
	model.province[model.index_of(1, 0)] = 0
	var tiles: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var province := ProvinceState.create(0, "Colony", tiles, Vector2.ZERO, 2, 0)
	province.town_development = 4
	model.provinces.append(province)
	model.resource[model.index_of(0, 0)] = owner_resource
	model.resource[model.index_of(1, 0)] = 4
	return model


func _works(model: MapModel) -> LandWorks:
	var works := LandWorks.new()
	works.add_port(model, Vector2i(0, 0))
	works.set_improvement(model, Vector2i(0, 0), 1)
	return works


func test_shipping_order_is_richest_per_hold_first() -> void:
	assert_eq(
		EconomyOverseas.priority(["grain", "diamonds", "gold", "castIron"]),
		["diamonds", "gold", "castIron", "grain"]
	)


func test_the_holds_cap_the_crossing_and_the_rest_stays_abroad() -> void:
	var plan: Dictionary = EconomyOverseas.plan(
		{0: {"grain": 3}, 1: {"gold": 2, "timber": 4}}, 4
	)

	assert_eq(int(plan["holds"]), 4)
	assert_eq(int(plan["used"]), 4)
	assert_eq(plan["shipped"], {"gold": 2, "grain": 2})
	assert_eq(plan["left"], {"grain": 1, "timber": 4})
	assert_eq(int(plan["left_total"]), 5)


func test_no_holds_lands_nothing() -> void:
	var plan: Dictionary = EconomyOverseas.plan({0: {"timber": 2}}, 0)

	assert_eq(int(plan["used"]), 0)
	assert_eq(plan["shipped"], {})
	assert_eq(int(plan["left_total"]), 2)
	assert_eq(EconomyOverseas.shipped_total(plan), 0)


func test_more_holds_than_cargo_ships_everything() -> void:
	var plan: Dictionary = EconomyOverseas.plan({0: {"timber": 2}}, 9)

	assert_eq(int(plan["used"]), 2)
	assert_eq(plan["left"], {})
	assert_eq(EconomyOverseas.shipped_total(plan), 2)


func test_region_totals_skip_the_home_region_and_need_a_port() -> void:
	var world := WorldMap.new()
	world.add_region(_region(0))
	world.add_region(_region(4))
	var works := MapRegionTable.new()
	works.set_region(0, _works(world.region(0)))
	works.set_region(1, _works(world.region(1)))

	var by_region: Dictionary = EconomyOverseas.region_totals(
		world, WorldMap.OLD_WORLD, 0, {}, works
	)

	assert_false(by_region.has(0), "home yield never needs a hold")
	assert_eq(by_region.get(1, {}), {"grain": 1})


func test_an_unconnected_colony_yields_nothing_to_ship() -> void:
	var world := WorldMap.new()
	world.add_region(_region(0))
	world.add_region(_region(0))
	var works := MapRegionTable.new()
	works.set_region(1, LandWorks.new())

	var by_region: Dictionary = EconomyOverseas.region_totals(
		world, WorldMap.OLD_WORLD, 0, {}, works
	)

	assert_eq(by_region, {})
	assert_eq(
		EconomyOverseas.region_totals(world, WorldMap.OLD_WORLD, 0, {}, null), {}
	)


func test_the_ledger_reserves_the_colony_cargo_before_imports() -> void:
	var world := WorldMap.new()
	world.add_region(_region(0))
	var home: FleetState = FleetState.in_port(
		1, 0, 0, ["a"], {"a": "fluyte"}
	)
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()

	assert_eq(
		int(TradeCargo.status(world, {0: [home]}, 0, market, 3)["reserved"]), 3
	)
	assert_eq(int(TradeCargo.status(world, {0: [home]}, 0, market, 3)["free"]), 1)
	assert_eq(TradeCargo.free_holds(4, market, 3), 1)
	assert_true(bool(TradeCargo.buy(economy, market, 4, "grain", 1, 3)["ok"]))
	var refused: Dictionary = TradeCargo.buy(economy, market, 4, "grain", 1, 3)
	assert_false(bool(refused["ok"]))
	assert_true(String(refused["reason"]).contains("promised to the colonies"))


func test_the_banner_names_the_colonial_reservation() -> void:
	var cargo: Dictionary = {"holds": 6, "used": 0, "reserved": 4, "free": 2}

	var line: String = LedgerText.cargo_line(cargo)

	assert_true(line.contains("6 holds"))
	assert_true(line.contains("4 for the colonies"))
	assert_true(line.contains("2 free"))
	assert_true(LedgerText.cargo_line({"holds": 6, "free": 2}).contains("2 free"))


## One rule for the player's ledger and a rival's economy: home yield lands
## directly and the other region's tonnage needs a hold (DR-20261109-17).
func test_delivered_adds_only_what_the_holds_carry() -> void:
	var world := WorldMap.new()
	world.add_region(_region(0))
	world.add_region(_region(4))
	var works := MapRegionTable.new()
	works.set_region(0, _works(world.region(0)))
	works.set_region(1, _works(world.region(1)))
	var home := {"grain": 3}

	var none: Dictionary = EconomyOverseas.delivered(
		home, world, WorldMap.OLD_WORLD, 0, {}, works, 0
	)
	var one: Dictionary = EconomyOverseas.delivered(
		home, world, WorldMap.OLD_WORLD, 0, {}, works, 1
	)

	assert_eq(none["extraction"], {"grain": 3}, "no hold, no colonial ton")
	assert_eq(int(none["used"]), 0)
	assert_eq(int(one["used"]), 1)
	assert_eq(one["extraction"], {"grain": 4})
	assert_eq(home, {"grain": 3}, "the home totals are not mutated")
