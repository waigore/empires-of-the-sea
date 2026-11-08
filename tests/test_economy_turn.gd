extends GdToolsTest
## Turn resolution: Extraction -> Riches -> Consumption -> Production, then prices
## (wiki: stockpiles-and-production § Production flow).


func test_turn_runs_all_four_phases_in_order() -> void:
	var economy: PlayerEconomy = _economy(2)
	economy.set_assignment("lumber", 1)
	var market: WorldMarket = WorldMarket.with_default_prices()
	var report: Dictionary = EconomyTurn.resolve(
		economy, market, {"grain": 10, "timber": 4}, 0
	)
	assert_eq(report["extraction"], {"grain": 10, "timber": 4})
	assert_eq(int(report["consumption"]["food_eaten"]), 2)
	assert_eq(report["production"]["runs"], {"lumber": 1})
	assert_eq(economy.quantity("grain"), 8)
	assert_eq(economy.quantity("timber"), 2)
	assert_eq(economy.quantity("lumber"), 1)
	assert_eq(economy.quantity("wool"), 2)


func test_gold_clears_into_treasury() -> void:
	var economy: PlayerEconomy = _economy(1)
	economy.stockpile["gold"] = 2
	economy.stockpile["spices"] = 1
	var before: int = economy.treasury
	var report: Dictionary = EconomyTurn.resolve(
		economy, WorldMarket.with_default_prices(), {}, 0
	)
	assert_eq(int(report["riches_treasury"]), 2 * 166 + 50)
	assert_eq(economy.treasury, before + 2 * 166 + 50)
	assert_eq(economy.quantity("gold"), 0)
	assert_eq(economy.quantity("spices"), 0)


func test_starving_workers_produce_nothing() -> void:
	var economy: PlayerEconomy = _economy(2)
	economy.stockpile["grain"] = 0
	economy.stockpile["timber"] = 6
	economy.set_assignment("lumber", 3)
	var report: Dictionary = EconomyTurn.resolve(
		economy, WorldMarket.with_default_prices(), {}, 0
	)
	assert_eq(int(report["consumption"]["strikers"]), 2)
	assert_eq(report["production"]["runs"], {})
	assert_eq(economy.quantity("timber"), 6)
	assert_eq(economy.quantity("lumber"), 0)


func test_navy_eats_before_production_labour() -> void:
	var economy: PlayerEconomy = _economy(3)
	economy.stockpile["grain"] = 2
	economy.stockpile["timber"] = 4
	economy.set_assignment("lumber", 1)
	var report: Dictionary = EconomyTurn.resolve(
		economy, WorldMarket.with_default_prices(), {}, 1
	)
	assert_eq(int(report["consumption"]["navy_fed"]), 2)
	assert_eq(int(report["consumption"]["navy_demand"]), 2)
	assert_eq(int(report["consumption"]["fed_workers"]), 0)
	assert_eq(report["production"]["runs"], {})


func test_projection_matches_the_live_resolution() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = _economy(2)
	economy.stockpile["gold"] = 1
	economy.set_assignment("lumber", 2)
	var projection: Dictionary = EconomyTurn.project(
		economy, market, {"grain": 6, "timber": 6}, 1
	)
	var before: Dictionary = economy.stockpile.duplicate()
	var treasury_before: int = economy.treasury
	EconomyTurn.resolve(economy, market, {"grain": 6, "timber": 6}, 1)
	assert_eq(int(projection["treasury_delta"]), economy.treasury - treasury_before)
	for id: String in CommodityCatalog.all_ids():
		var live: int = economy.quantity(id) - int(before.get(id, 0))
		assert_eq(int(projection["stockpile_delta"].get(id, 0)), live, id)


func test_projection_has_no_side_effects() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = _economy(2)
	economy.set_assignment("lumber", 1)
	var stock_before: Dictionary = economy.stockpile.duplicate()
	var treasury_before: int = economy.treasury
	EconomyTurn.project(economy, market, {"timber": 4}, 0)
	assert_eq(economy.stockpile, stock_before)
	assert_eq(economy.treasury, treasury_before)
	assert_eq(economy.workers.count(WorkerPool.Tier.PEASANT), 2)


func test_turn_advances_market_prices_but_projection_does_not() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices(0)
	var economy: PlayerEconomy = _economy(1)
	market.buy(economy, "grain", 10)
	var projection: Dictionary = EconomyTurn.project(economy, market, {"grain": 10}, 0)
	assert_eq(market.price("grain"), 50)
	assert_eq(projection["prices"], {})
	EconomyTurn.resolve(economy, market, {"grain": 10}, 0)
	assert_eq(market.price("grain"), 60)
	assert_eq(market.bid_volume("grain"), 0)


func test_empty_turn_is_a_no_op() -> void:
	var economy: PlayerEconomy = _economy(0)
	var before: Dictionary = economy.stockpile.duplicate()
	var report: Dictionary = EconomyTurn.resolve(
		economy, WorldMarket.with_default_prices(), {}, 0
	)
	assert_eq(report["extraction"], {})
	assert_eq(report["production"]["runs"], {})
	assert_eq(economy.stockpile, before)


func _economy(peasants: int) -> PlayerEconomy:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.workers = WorkerPool.make(peasants)
	economy.stockpile = {"grain": 0, "wool": 2}
	economy.treasury = 1000
	return economy
