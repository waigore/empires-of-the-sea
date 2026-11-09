extends GdToolsTest
## Merchant cargo: the home fleet's holds cap world-market imports (wiki:
## ships-and-naval § Cargo holds and capacity; world-market § Cargo;
## DR-20261109-03). Pure rules, so no scene is needed.

const NavalFixture = preload("res://tests/naval_fixture.gd")


func _world() -> WorldMap:
	var world := WorldMap.new()
	world.add_region(NavalFixture.build())
	return world


func test_a_merchant_hull_carries_cargo_and_a_warship_does_not() -> void:
	var fluyte := FleetState.in_port(1, 0, 0, ["a", "b"], {"a": "fluyte", "b": "sloop"})
	assert_eq(TradeCargo.fleet_holds(fluyte), 4)
	var galleon := FleetState.in_port(2, 0, 0, ["c"], {"c": "galleon"})
	assert_eq(TradeCargo.fleet_holds(galleon), 6)
	var line := FleetState.in_port(3, 0, 0, ["d"], {"d": "ship_of_the_line"})
	assert_eq(TradeCargo.fleet_holds(line), 0)
	assert_eq(TradeCargo.fleet_holds(null), 0)


func test_capacity_counts_only_the_crowns_squadrons_in_port_at_its_seat() -> void:
	var world: WorldMap = _world()
	var home := FleetState.in_port(1, 0, 0, ["a", "b"], {"a": "fluyte", "b": "carrack"})
	var at_sea := FleetState.at_sea(2, 0, 0, ["c"], {"c": "indiaman"})
	# A harbour that is not the seat carries nothing.
	var other_port := FleetState.in_port(3, 0, 1, ["d"], {"d": "indiaman"})
	var foreign := FleetState.in_port(4, 1, 1, ["e"], {"e": "galleon"})
	var fleets: Dictionary = {0: [home, at_sea, other_port], 1: [foreign]}

	assert_eq(TradeCargo.capacity(world, fleets, 0), 7)
	assert_eq(TradeCargo.capacity(world, fleets, 1), 0)


func test_a_crown_without_a_seat_has_no_cargo() -> void:
	var world: WorldMap = _world()
	var home := FleetState.in_port(1, 0, 0, ["a"], {"a": "fluyte"})
	assert_eq(TradeCargo.capacity(world, {0: [home]}, 6), 0)
	assert_eq(TradeCargo.capacity(null, {0: [home]}, 0), 0)


func test_status_reports_holds_used_and_free() -> void:
	var world: WorldMap = _world()
	var home := FleetState.in_port(1, 0, 0, ["a"], {"a": "fluyte"})
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	assert_true(bool(TradeCargo.buy(economy, market, 4, "grain", 2)["ok"]))

	var status: Dictionary = TradeCargo.status(world, {0: [home]}, 0, market)

	assert_eq(int(status["holds"]), 4)
	assert_eq(int(status["used"]), 2)
	assert_eq(int(status["free"]), 2)


func test_imports_share_the_holds_across_commodities() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var fabric_before: int = economy.quantity("fabric")

	assert_true(bool(TradeCargo.buy(economy, market, 4, "grain", 3)["ok"]))
	assert_true(bool(TradeCargo.buy(economy, market, 4, "timber", 1)["ok"]))
	var refused: Dictionary = TradeCargo.buy(economy, market, 4, "fabric", 1)

	assert_false(bool(refused["ok"]))
	assert_true(String(refused["reason"]).contains("4 cargo holds"))
	assert_eq(market.bought_units(), 4)
	assert_eq(economy.quantity("fabric"), fabric_before)


func test_no_home_fleet_refuses_with_its_own_reason() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var refused: Dictionary = TradeCargo.buy(economy, market, 0, "grain", 1)
	assert_false(bool(refused["ok"]))
	assert_true(String(refused["reason"]).contains("No cargo holds"))
	assert_eq(market.bought_units(), 0)


func test_other_market_refusals_pass_through() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	assert_eq(
		String(TradeCargo.buy(economy, market, 4, "gold", 1)["reason"]),
		"Not traded on the world market"
	)
	assert_eq(
		String(TradeCargo.buy(economy, market, 4, "grain", 0)["reason"]),
		"Quantity must be positive"
	)
	economy.treasury = 10
	assert_eq(
		String(TradeCargo.buy(economy, market, 4, "grain", 1)["reason"]),
		"Insufficient treasury"
	)


func test_sales_do_not_spend_a_hold() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.stockpile["timber"] = 2

	assert_true(bool(market.sell(economy, "timber", 2)["ok"]))

	assert_eq(market.bought_units(), 0)
	assert_eq(TradeCargo.free_holds(4, market), 4)


func test_next_turn_releases_the_holds() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	assert_true(bool(TradeCargo.buy(economy, market, 2, "grain", 2)["ok"]))
	assert_eq(TradeCargo.free_holds(2, market), 0)

	market.advance_prices()

	assert_eq(TradeCargo.free_holds(2, market), 2)
	assert_eq(market.bought_units(), 0)


func test_a_saved_market_remembers_the_laden_holds() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	assert_true(bool(TradeCargo.buy(economy, market, 3, "grain", 2)["ok"]))

	var restored: WorldMarket = WorldMarket.from_dict(market.to_dict())

	assert_eq(restored.bought_units(), 2)
	assert_eq(TradeCargo.free_holds(3, restored), 1)
