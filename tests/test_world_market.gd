extends GdToolsTest
## World market: prices, trades and price discovery (wiki: world-market).


func test_market_seeds_tradeable_catalog_prices() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	assert_eq(market.prices.size(), 22)
	assert_eq(market.price("timber"), 30)
	assert_eq(market.price("lumber"), 60)
	assert_eq(market.price("iron"), 80)
	assert_false(market.prices.has("gold"))
	assert_false(market.prices.has("spices"))
	assert_false(market.can_trade("gold"))
	assert_true(market.can_trade("lumber"))


func test_buy_pays_the_current_price_and_records_a_bid() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var result: Dictionary = market.buy(economy, "timber", 2)
	assert_true(bool(result["ok"]))
	assert_eq(int(result["cost"]), 60)
	assert_eq(economy.treasury, PlayerEconomy.START_TREASURY - 60)
	assert_eq(economy.quantity("timber"), 2)
	assert_eq(market.bid_volume("timber"), 2)
	assert_eq(market.offer_volume("timber"), 0)


func test_buy_rejects_unaffordable_and_untradeable_rows() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.treasury = 10
	var poor: Dictionary = market.buy(economy, "timber", 1)
	assert_false(bool(poor["ok"]))
	assert_eq(String(poor["reason"]), "Insufficient treasury")
	assert_eq(economy.quantity("timber"), 0)
	var riches: Dictionary = market.buy(economy, "gold", 1)
	assert_false(bool(riches["ok"]))
	assert_eq(String(riches["reason"]), "Not traded on the world market")
	assert_false(bool(market.buy(economy, "timber", 0)["ok"]))


func test_sell_credits_treasury_and_records_an_offer() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.stockpile["timber"] = 3
	var result: Dictionary = market.sell(economy, "timber", 2)
	assert_true(bool(result["ok"]))
	assert_eq(int(result["revenue"]), 60)
	assert_eq(economy.treasury, PlayerEconomy.START_TREASURY + 60)
	assert_eq(economy.quantity("timber"), 1)
	assert_eq(market.offer_volume("timber"), 2)
	assert_false(bool(market.sell(economy, "timber", 5)["ok"]))
	assert_false(bool(market.sell(economy, "spices", 1)["ok"]))


func test_price_discovery_uses_the_published_formula() -> void:
	assert_eq(WorldMarket.next_price(30, 30, 0, 0), 30)
	assert_eq(WorldMarket.next_price(30, 30, 10, 10), 30)
	assert_eq(WorldMarket.next_price(30, 30, 10, 0), 36)
	assert_eq(WorldMarket.next_price(30, 30, 0, 10), 24)
	assert_eq(WorldMarket.next_price(30, 30, 100, 0), 36)
	assert_eq(WorldMarket.next_price(30, 30, 0, 100), 24)


func test_price_is_floored_at_thirty_percent_of_base() -> void:
	assert_eq(WorldMarket.next_price(10, 100, 0, 10), 30)
	assert_eq(WorldMarket.next_price(0, 100, 10, 0), 30)


func test_world_depth_damps_one_sided_trades() -> void:
	var shallow: int = WorldMarket.next_price(30, 30, 10, 0, 100)
	assert_eq(shallow, 30)
	var capped: int = WorldMarket.next_price(30, 30, 1000, 0, 0)
	assert_eq(capped, 36)


func test_advance_prices_publishes_and_resets_volumes() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices(0)
	var economy: PlayerEconomy = PlayerEconomy.starting()
	market.buy(economy, "grain", 10)
	var changed: Dictionary = market.advance_prices()
	assert_eq(int(market.price("grain")), 60)
	assert_eq(int(changed["grain"]), 60)
	assert_eq(market.bid_volume("grain"), 0)
	assert_eq(market.price("timber"), 30)
	assert_false(changed.has("timber"))


func test_copy_keeps_prices_and_volumes_separate() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	market.buy(economy, "timber", 10)
	var clone: WorldMarket = market.copy()
	clone.advance_prices()
	assert_eq(market.price("timber"), 30)
	assert_eq(clone.price("timber"), 35)
	assert_eq(market.bid_volume("timber"), 10)
	assert_eq(clone.bid_volume("timber"), 0)
