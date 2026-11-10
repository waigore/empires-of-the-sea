extends GdToolsTest
## Rival world-market participation (wiki: world-market; docs/ai.md). Sells
## above the reserve and production inputs, bids with free holds, and keeps each
## crown's cargo separate.

const CONFIG_FACTION: int = 1


func _config() -> AiConfig:
	return AiConfig.build(CONFIG_FACTION, 1500)


func _economy(stock: Dictionary, treasury: int = 5000) -> PlayerEconomy:
	var economy := PlayerEconomy.starting()
	economy.treasury = treasury
	economy.stockpile = stock.duplicate()
	return economy


func test_a_court_sells_surplus_above_the_reserve() -> void:
	var economy: PlayerEconomy = _economy({"grain": 100})
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(_config(), economy, market, 0)
	var offers: Array = plan["offers"]
	assert_eq(offers.size(), 1)
	assert_eq(String(offers[0]["commodity"]), "grain")
	assert_eq(int(offers[0]["quantity"]), 10, "market.max_offer_units caps the lot")
	var result: Dictionary = AiMarketPlanner.apply(economy, market, plan, CONFIG_FACTION)
	assert_eq((result["sold"] as Array).size(), 1)
	assert_eq((result["bought"] as Array).size(), 0, "no holds means no imports")
	assert_eq(economy.quantity("grain"), 90)
	assert_true(economy.treasury > 5000)


func test_production_inputs_are_never_sold_under_the_court() -> void:
	var economy: PlayerEconomy = _economy({"lumber": 30, "grain": 100})
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(
		_config(), economy, market, 0, {}, {"lumber": 20}
	)
	for raw: Variant in plan["offers"]:
		var offer: Dictionary = raw
		assert_ne(String(offer["commodity"]), "lumber")


func test_bids_short_build_inputs_with_free_holds_and_the_purse() -> void:
	var economy: PlayerEconomy = _economy(
		{"lumber": 0, "castIron": 0, "fabric": 0, "paper": 0}, 5000
	)
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(_config(), economy, market, 20)
	var bids: Array = plan["bids"]
	assert_eq(bids.size(), 3, "baseline bid-type cap")
	for raw: Variant in bids:
		var bid: Dictionary = raw
		assert_true(int(bid["quantity"]) <= 5)
	var result: Dictionary = AiMarketPlanner.apply(economy, market, plan, CONFIG_FACTION)
	assert_eq((result["bought"] as Array).size(), 3)
	assert_true(economy.quantity("bronze") > 0)


func test_no_bid_can_break_the_minimum_treasury() -> void:
	var economy: PlayerEconomy = _economy({"lumber": 0, "castIron": 0}, 520)
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(_config(), economy, market, 20)
	var spend: int = 0
	for raw: Variant in plan["bids"]:
		var bid: Dictionary = raw
		spend += int(bid["quantity"]) * int(market.price(String(bid["commodity"])))
	assert_true(spend <= 20, "only the £20 above the floor may be bid")
	assert_true(economy.treasury - spend >= 500 - 1)


func test_trade_fairs_raise_the_bid_type_cap_to_six() -> void:
	var economy: PlayerEconomy = _economy(
		{"lumber": 0, "castIron": 0, "fabric": 0, "paper": 0, "steel": 0, "bronze": 0},
		100000
	)
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(
		_config(), economy, market, 100, {"trade_fairs": true}
	)
	assert_eq((plan["bids"] as Array).size(), 6)


func test_a_buyer_spends_only_its_own_holds() -> void:
	var economy: PlayerEconomy = _economy({}, 5000)
	var market := WorldMarket.with_default_prices()
	assert_true(bool(market.buy(economy, "grain", 2, 1)["ok"]))
	assert_eq(market.bought_units_for(1), 2)
	assert_eq(market.bought_units_for(0), 0)
	assert_eq(market.bought_units(), 2, "the price book still sees the tonnage")
	assert_true(bool(market.buy(economy, "grain", 1)["ok"]))
	assert_eq(market.bought_units_for(0), 1)
	assert_eq(TradeCargo.used(market, 1), 2)
	assert_eq(TradeCargo.used(market, 0), 1)
	var restored: WorldMarket = WorldMarket.from_dict(market.to_dict())
	assert_eq(restored.bought_units_for(1), 2)
	assert_eq(restored.bought_units_for(0), 1)


func test_missing_inputs_make_the_plan_empty() -> void:
	var economy: PlayerEconomy = _economy({"grain": 100})
	var market := WorldMarket.with_default_prices()
	assert_true((AiMarketPlanner.plan(null, economy, market, 0)["offers"] as Array).is_empty())
	assert_true((AiMarketPlanner.plan(_config(), null, market, 0)["offers"] as Array).is_empty())
	assert_true((AiMarketPlanner.plan(_config(), economy, null, 0)["offers"] as Array).is_empty())
	assert_true((AiMarketPlanner.apply(null, null, {})["sold"] as Array).is_empty())


func test_offers_stop_at_the_type_cap() -> void:
	var economy: PlayerEconomy = _economy({
		"grain": 100, "timber": 100, "iron": 100, "wool": 100,
	})
	var plan: Dictionary = AiMarketPlanner.plan(
		_config(), economy, WorldMarket.with_default_prices(), 0
	)
	assert_eq((plan["offers"] as Array).size(), 3)


func test_a_refused_trade_is_reported_not_swallowed() -> void:
	var economy: PlayerEconomy = _economy({"grain": 0}, 0)
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = {
		"offers": [{"commodity": "grain", "quantity": 5}],
		"bids": [{"commodity": "lumber", "quantity": 5, "unit_price": 60}],
	}
	var result: Dictionary = AiMarketPlanner.apply(economy, market, plan, CONFIG_FACTION)
	assert_eq((result["sold"] as Array).size(), 0)
	assert_eq((result["bought"] as Array).size(), 0)
	assert_eq((result["refused"] as Array).size(), 2)


func test_price_falls_back_to_the_catalog_and_zero_sales_are_refused() -> void:
	var market := WorldMarket.with_default_prices()
	market.prices.erase("grain")
	assert_eq(market.price("grain"), CommodityCatalog.base_price("grain"))
	var economy: PlayerEconomy = _economy({"grain": 4})
	assert_false(bool(market.sell(economy, "grain", 0)["ok"]))


func test_a_legacy_book_attributes_bids_to_the_player() -> void:
	var market: WorldMarket = WorldMarket.from_dict({"bids": {"grain": 3}})
	assert_eq(market.bought_units_for(FactionCatalog.PLAYER_FACTION), 3)
	assert_eq(market.bought_units_for(1), 0)
	var economy: PlayerEconomy = _economy({}, 5000)
	assert_true(bool(market.buy(economy, "grain", 1, 1)["ok"]))
	assert_eq(market.bought_units_for(FactionCatalog.PLAYER_FACTION), 3)
	assert_eq(market.bought_units_for(1), 1)
