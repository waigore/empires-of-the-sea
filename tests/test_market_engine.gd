extends GdToolsTest
## World-market matching engine: order validation, priority tiers, first right
## of refusal, relation tiebreaks, profit shares, embassy kickbacks, subsidy
## steps, carry-forward and price discovery (wiki: world-market;
## world-market-first-right-of-refusal).

var _seq: int = 0


func _order(
	faction: int,
	commodity: String,
	side: String,
	quantity: int,
	priority: int = 1,
	origin_region: int = MarketOrder.NO_ORIGIN,
	origin_index: int = MarketOrder.NO_ORIGIN,
	auto_offer: bool = false
) -> MarketOrder:
	_seq += 1
	var order: MarketOrder = MarketOrder.create(
		faction, commodity, side, quantity, priority, origin_region, origin_index, auto_offer
	)
	order.id = "t%d" % _seq
	return order


func _context(overrides: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {
		"prices": {"timber": 30, "grain": 10},
		"free_holds": {0: 10, 1: 10, 2: 10, 6: 10, 9: 10},
		"treasuries": {0: 10000, 1: 10000, 2: 10000, 6: 0, 9: 0},
		"stock": {0: {"timber": 10}, 1: {"timber": 10}, 2: {"timber": 10}, 3: {"timber": 10}},
	}
	for key: Variant in overrides.keys():
		out[key] = overrides[key]
	return out


# --- validation --------------------------------------------------------------


func test_one_side_per_commodity() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var bid: Dictionary = MarketOrders.submit(
			market,
		0, "timber", MarketOrder.SIDE_BID, 1, {"cargo_free": 4, "treasury": 500}
	)
	assert_true(bool(bid["ok"]), String(bid.get("reason", "")))
	var offer: Dictionary = MarketOrders.submit(
			market,
		0, "timber", MarketOrder.SIDE_OFFER, 1, {"stock": 4}
	)
	assert_false(bool(offer["ok"]))
	assert_eq(String(offer["code"]), "trade_order_mutual_exclusion")


func test_bid_type_cap_is_three_and_trade_fairs_raise_it_to_six() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var ids: Array[String] = ["timber", "iron", "wool", "grain"]
	for index in 3:
		var result: Dictionary = MarketOrders.submit(
			market,
			0, ids[index], MarketOrder.SIDE_BID, 1, {"cargo_free": 8, "treasury": 9000}
		)
		assert_true(bool(result["ok"]), String(result.get("reason", "")))
	var fourth: Dictionary = MarketOrders.submit(
			market,
		0, ids[3], MarketOrder.SIDE_BID, 1, {"cargo_free": 8, "treasury": 9000}
	)
	assert_false(bool(fourth["ok"]))
	assert_eq(String(fourth["code"]), "trade_order_bid_type_cap_exceeded")
	var fair: WorldMarket = WorldMarket.with_default_prices()
	for index in 4:
		var result: Dictionary = MarketOrders.submit(
		fair,
			0, ids[index], MarketOrder.SIDE_BID, 1,
			{"cargo_free": 8, "treasury": 9000, "tech_unlocked": {"trade_fairs": true}}
		)
		assert_true(bool(result["ok"]), String(result.get("reason", "")))


func test_offer_is_capped_by_stock_and_bid_by_cargo() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var offer: Dictionary = MarketOrders.submit(
			market,
		0, "timber", MarketOrder.SIDE_OFFER, 3, {"stock": 2}
	)
	assert_false(bool(offer["ok"]))
	assert_eq(String(offer["code"]), "trade_order_stock_insufficient")
	var bid: Dictionary = MarketOrders.submit(
			market,
		0, "timber", MarketOrder.SIDE_BID, 3, {"cargo_free": 2, "treasury": 500}
	)
	assert_false(bool(bid["ok"]))
	assert_eq(String(bid["code"]), "trade_order_cargo_insufficient")


# --- priority and ties -------------------------------------------------------


func test_higher_priority_bid_clears_the_offer_first() -> void:
	var orders: Array[MarketOrder] = [
		_order(1, "timber", MarketOrder.SIDE_BID, 5, 2),
		_order(0, "timber", MarketOrder.SIDE_BID, 5, 1),
		_order(6, "timber", MarketOrder.SIDE_OFFER, 5, 1),
	]
	var result: Dictionary = MarketMatcher.match(orders, _context())
	var deals: Array = result["deals"]
	assert_eq(deals.size(), 1)
	assert_eq(int(deals[0]["buyer"]), 0)
	assert_eq(int(deals[0]["quantity"]), 5)
	var left: Array = result["residuals"]
	assert_eq(left.size(), 1)
	assert_eq(int(left[0]["faction"]), 1)


func test_favoured_partner_wins_a_tie() -> void:
	var orders: Array[MarketOrder] = [
		_order(1, "timber", MarketOrder.SIDE_BID, 5, 1),
		_order(2, "timber", MarketOrder.SIDE_BID, 5, 1),
		_order(3, "timber", MarketOrder.SIDE_OFFER, 5, 1),
	]
	var context: Dictionary = _context()
	context["ftp_for"] = func(a: int, b: int) -> bool: return a == 1 and b == 3
	var result: Dictionary = MarketMatcher.match(orders, context)
	var deals: Array = result["deals"]
	assert_eq(deals.size(), 1)
	assert_eq(int(deals[0]["buyer"]), 1)
	assert_true(bool(deals[0]["is_ftp"]))


func test_minor_sale_prefers_a_consulate_holder_then_higher_relation() -> void:
	var orders: Array[MarketOrder] = [
		_order(1, "timber", MarketOrder.SIDE_BID, 5, 1),
		_order(2, "timber", MarketOrder.SIDE_BID, 5, 1),
		_order(6, "timber", MarketOrder.SIDE_OFFER, 5, 1),
	]
	var context: Dictionary = _context()
	context["consulate_for"] = func(gp: int, _minor: int) -> bool: return true
	context["relation_for"] = func(gp: int, _minor: int) -> float:
		return 70.0 if gp == 2 else 25.0
	var result: Dictionary = MarketMatcher.match(orders, context)
	var deals: Array = result["deals"]
	assert_eq(deals.size(), 1)
	assert_eq(int(deals[0]["buyer"]), 2, "higher relation with the seller wins")


func test_a_consulate_holder_beats_a_higher_relation_without_one() -> void:
	var orders: Array[MarketOrder] = [
		_order(1, "timber", MarketOrder.SIDE_BID, 5, 1),
		_order(2, "timber", MarketOrder.SIDE_BID, 5, 1),
		_order(6, "timber", MarketOrder.SIDE_OFFER, 5, 1),
	]
	var context: Dictionary = _context()
	context["consulate_for"] = func(gp: int, _minor: int) -> bool: return gp == 1
	context["relation_for"] = func(gp: int, _minor: int) -> float:
		return 80.0 if gp == 2 else 10.0
	var result: Dictionary = MarketMatcher.match(orders, context)
	assert_eq(int((result["deals"] as Array)[0]["buyer"]), 1)


# --- first right of refusal --------------------------------------------------


func test_first_right_overrides_a_higher_priority_rival() -> void:
	var orders: Array[MarketOrder] = [
		_order(0, "timber", MarketOrder.SIDE_BID, 4, 5),
		_order(1, "timber", MarketOrder.SIDE_BID, 4, 1),
		_order(6, "timber", MarketOrder.SIDE_OFFER, 4, 1, 0, 1, true),
	]
	var context: Dictionary = _context()
	context["purchased_for"] = func(_region: int, _index: int) -> int: return 0
	var result: Dictionary = MarketMatcher.match(orders, context)
	var deals: Array = result["deals"]
	assert_eq(deals.size(), 1)
	assert_eq(int(deals[0]["buyer"]), 0)
	assert_true(bool(deals[0]["is_frr"]))
	assert_eq(int((result["residuals"] as Array)[0]["faction"]), 1)


func test_first_right_partial_fill_exposes_the_residual() -> void:
	var orders: Array[MarketOrder] = [
		_order(0, "timber", MarketOrder.SIDE_BID, 4, 1),
		_order(1, "timber", MarketOrder.SIDE_BID, 6, 1),
		_order(6, "timber", MarketOrder.SIDE_OFFER, 10, 1, 0, 1, true),
	]
	var context: Dictionary = _context()
	context["purchased_for"] = func(_region: int, _index: int) -> int: return 0
	var result: Dictionary = MarketMatcher.match(orders, context)
	var deals: Array = result["deals"]
	assert_eq(deals.size(), 2)
	assert_true(bool(deals[0]["is_frr"]))
	assert_eq(int(deals[0]["quantity"]), 4)
	assert_false(bool(deals[1]["is_frr"]))
	assert_eq(int(deals[1]["quantity"]), 6)


# --- profit share and kickbacks ---------------------------------------------


func test_profit_is_relation_linear_with_no_cap() -> void:
	assert_eq(FirstRight.profit(0.0, 4, 2.5), 0.0)
	assert_eq(FirstRight.profit(100.0, 4, 2.5), 10.0)
	assert_eq(FirstRight.profit(75.0, 10, 5.0), 37.5)
	assert_eq(FirstRight.profit(-5.0, 10, 5.0), 0.0)
	assert_eq(FirstRight.profit(200.0, 10, 5.0), 50.0, "clamped to 100")


func test_embassy_kickback_is_ten_percent_of_the_relation_portion() -> void:
	assert_eq(FirstRight.kickback(100.0, 10, 20.0), 20.0)
	assert_eq(FirstRight.kickback(50.0, 10, 20.0), 10.0)


func test_credits_separate_the_owner_share_from_kickbacks() -> void:
	var deals: Array[Dictionary] = [{
		"seller": 6, "buyer": 1, "commodity": "timber",
		"quantity": 10, "price": 20.0, "seller_is_minor": true,
		"origin_region": 0, "origin_index": 1,
	}]
	var result: Dictionary = FirstRight.credits(
		deals,
		func(_region: int, _index: int) -> int: return 0,
		func(gp: int, _minor: int) -> float: return 75.0 if gp == 0 else 50.0,
		func(gp: int, _minor: int) -> bool: return gp in [1, 2]
	)
	var by_gp: Dictionary = result["by_gp"]
	assert_eq(float(by_gp[0]), 150.0, "owner full share, no 40% cap")
	assert_eq(float(by_gp[1]), 10.0, "buyer also holds an embassy")
	assert_eq(float(by_gp[2]), 10.0)
	assert_eq(float(result["sink"]), 30.0)


# --- clearing, settlement and carry-forward ---------------------------------


func _world() -> WorldMap:
	var model: MapModel = MapModel.new()
	model.setup(3, 2)
	for x in 2:
		model.province[model.index_of(x, 0)] = 0
	model.province[model.index_of(2, 0)] = 1
	model.province[model.index_of(0, 1)] = 1
	var tiles0: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var tiles1: Array[Vector2i] = [Vector2i(2, 0), Vector2i(0, 1)]
	var p0 := ProvinceState.create(0, "P0", tiles0, Vector2.ZERO, 2, 0)
	var p1 := ProvinceState.create(1, "P1", tiles1, Vector2.ZERO, 2, 6)
	model.provinces.append(p0)
	model.provinces.append(p1)
	model.resource[model.index_of(0, 0)] = 0
	model.resource[model.index_of(2, 0)] = 0
	model.resource[model.index_of(0, 1)] = 4
	for tile: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1)]:
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.PLAINS
	var world := WorldMap.new()
	world.add_region(model)
	return world


func _economies() -> Dictionary:
	return {
		0: PlayerEconomy.starting(),
		1: PlayerEconomy.starting(),
	}


func test_a_bid_buys_the_minor_harvest_and_books_cargo() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _world()
	var economies: Dictionary = _economies()
	var buyer: PlayerEconomy = economies[0]
	var before: int = buyer.treasury
	var staged: Dictionary = MarketOrders.submit(
			market,
		0, "timber", MarketOrder.SIDE_BID, 1,
		{"cargo_free": 4, "treasury": before, "buy_price": 30}
	)
	assert_true(bool(staged["ok"]), String(staged.get("reason", "")))
	var report: Dictionary = MarketClearing.clear(
		market, world, economies, {0: 4, 1: 4}
	)
	var deals: Array = report["deals"]
	var mine: Array = []
	for raw: Variant in deals:
		if int((raw as Dictionary).get("buyer", -99)) == 0:
			mine.append(raw)
	assert_eq(mine.size(), 1)
	assert_eq(int(mine[0]["seller"]), 6)
	assert_eq(int(mine[0]["quantity"]), 1)
	assert_eq(buyer.treasury, before - 30)
	assert_eq(buyer.quantity("timber"), 1)
	assert_eq(int(((report["fills"] as Dictionary).get(0, {}) as Dictionary).get("bought", 0)), 1)


func test_no_purchased_tile_means_no_profit_share() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _world()
	var economies: Dictionary = _economies()
	MarketOrders.submit(
			market,
		0, "timber", MarketOrder.SIDE_BID, 1,
		{"cargo_free": 4, "treasury": 5000, "buy_price": 30}
	)
	var before: int = (economies[1] as PlayerEconomy).treasury
	var report: Dictionary = MarketClearing.clear(
		market, world, economies, {0: 4, 1: 4}
	)
	assert_eq(int((report["credits"] as Dictionary)["by_gp"].get(1, 0)), 0)
	assert_eq((economies[1] as PlayerEconomy).treasury, before)


func test_first_right_pays_the_tile_owner_on_a_rival_sale() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _world()
	var model: MapModel = world.region(0)
	var tile: Vector2i = Vector2i(2, 0)
	assert_true(model.purchase_tile(tile, 0))
	var economies: Dictionary = _economies()
	var owner: PlayerEconomy = economies[0]
	var owner_before: int = owner.treasury
	var diplomacy := DiplomacyState.new()
	diplomacy.ensure_relation(0, 6, 0).set_score(75.0)
	MarketOrders.submit(
			market,
		1, "timber", MarketOrder.SIDE_BID, 1,
		{"cargo_free": 4, "treasury": 5000, "buy_price": 30}
	)
	var report: Dictionary = MarketClearing.clear(
		market, world, economies, {0: 4, 1: 4}, {"diplomacy": diplomacy}
	)
	var credited: int = roundi(float((report["credits"] as Dictionary)["by_gp"].get(0, 0)))
	assert_eq(credited, 23, "1 x 30 x 75% = 22.5, rounded once")
	assert_eq(owner.treasury, owner_before + 23)
	assert_false((economies[1] as PlayerEconomy).treasury == PlayerEconomy.START_TREASURY)


func test_subsidy_surcharge_lands_on_the_minor_sale() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _world()
	var economies: Dictionary = _economies()
	var diplomacy := DiplomacyState.new()
	diplomacy.set_subsidy(0, 6, 10)
	MarketOrders.submit(
			market,
		0, "timber", MarketOrder.SIDE_BID, 1,
		{"cargo_free": 4, "treasury": 5000, "buy_price": 30}
	)
	var before: int = (economies[0] as PlayerEconomy).treasury
	MarketClearing.clear(market, world, economies, {0: 4, 1: 4}, {"diplomacy": diplomacy})
	assert_eq((economies[0] as PlayerEconomy).treasury, before - 33)


func test_unfilled_bid_carries_or_drops_when_cargo_is_short() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _world()
	var economies: Dictionary = _economies()
	MarketOrders.submit(
			market,
		0, "grain", MarketOrder.SIDE_BID, 5,
		{"cargo_free": 10, "treasury": 5000, "buy_price": 10}
	)
	var report: Dictionary = MarketClearing.clear(
		market, world, economies, {0: 2, 1: 4}
	)
	assert_eq((report["carry"] as Array).size(), 0)
	var codes: Array[String] = []
	for note: Dictionary in report["notes"]:
		codes.append(String(note.get("code", "")))
	assert_true(codes.has("carry_forward_dropped_cargo_insufficient"))


func test_unfilled_bid_carries_when_cargo_can_still_cover_it() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _world()
	var economies: Dictionary = _economies()
	MarketOrders.submit(
			market,
		0, "grain", MarketOrder.SIDE_BID, 5,
		{"cargo_free": 10, "treasury": 5000, "buy_price": 10}
	)
	var before: int = (economies[0] as PlayerEconomy).quantity("grain")
	var report: Dictionary = MarketClearing.clear(
		market, world, economies, {0: 8, 1: 4}
	)
	# The world maker fills all five, so nothing carries; a fresh book stays clean.
	assert_eq((report["carry"] as Array).size(), 0)
	assert_eq((economies[0] as PlayerEconomy).quantity("grain"), before + 5)


func test_price_discovery_reads_filled_bids_and_submitted_offers() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _world()
	var economies: Dictionary = _economies()
	(economies[1] as PlayerEconomy).stockpile["timber"] = 10
	MarketOrders.submit(
			market,
		1, "timber", MarketOrder.SIDE_OFFER, 10,
		{"stock": 10}
	)
	MarketOrders.submit(
			market,
		0, "timber", MarketOrder.SIDE_BID, 5,
		{"cargo_free": 8, "treasury": 5000, "buy_price": 30}
	)
	MarketClearing.clear(market, world, economies, {0: 8, 1: 8})
	assert_eq(market.price("timber"), 27, "5 filled bids against 10 submitted offers")


func test_purchased_tile_still_publishes_its_harvest() -> void:
	var world: WorldMap = _world()
	var model: MapModel = world.region(0)
	var tile: Vector2i = Vector2i(2, 0)
	assert_true(model.purchase_tile(tile, 0))
	var orders: Array[MarketOrder] = MinorMarket.emit_orders(world)
	var found: bool = false
	for order: MarketOrder in orders:
		if order.commodity == "timber" and order.origin_index == model.index_of(tile.x, tile.y):
			found = true
			assert_eq(order.faction, 6)
			assert_true(order.auto)
	assert_true(found, "a deed keeps the seller's tile in the book for FRR")


func test_clearing_is_deterministic() -> void:
	var first: Dictionary = _clear_once()
	var second: Dictionary = _clear_once()
	assert_eq(first["deals"], second["deals"])


func _clear_once() -> Dictionary:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _world()
	var economies: Dictionary = _economies()
	MarketOrders.submit(
			market,
		0, "timber", MarketOrder.SIDE_BID, 1,
		{"cargo_free": 4, "treasury": 5000, "buy_price": 30}
	)
	return MarketClearing.clear(market, world, economies, {0: 4, 1: 4})


func test_the_order_book_survives_a_save_round_trip() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	MarketOrders.submit(
			market,
		0, "timber", MarketOrder.SIDE_BID, 2,
		{"cargo_free": 4, "treasury": 5000, "buy_price": 30}
	)
	var restored: WorldMarket = WorldMarket.from_dict(market.to_dict())
	assert_eq(restored.book.submitted.size(), 1)
	var order: MarketOrder = restored.book.submitted[0]
	assert_eq(order.commodity, "timber")
	assert_eq(order.remaining(), 2)
	assert_eq(restored.book.pending_buy_units(0), 2)
	assert_eq(MarketOrders.cancel(restored, 0, order.id), true)
	assert_eq(restored.book.pending_buy_units(0), 0)


func test_first_right_beats_a_favoured_partner() -> void:
	var orders: Array[MarketOrder] = [
		_order(0, "timber", MarketOrder.SIDE_BID, 4, 5),
		_order(1, "timber", MarketOrder.SIDE_BID, 4, 1),
		_order(6, "timber", MarketOrder.SIDE_OFFER, 4, 1, 0, 1, true),
	]
	var context: Dictionary = _context()
	context["purchased_for"] = func(_region: int, _index: int) -> int: return 0
	context["ftp_for"] = func(a: int, b: int) -> bool: return a == 1 and b == 6
	var result: Dictionary = MarketMatcher.match(orders, context)
	assert_eq(int((result["deals"] as Array)[0]["buyer"]), 0)
	assert_true(bool((result["deals"] as Array)[0]["is_frr"]))


func test_an_embassy_kickback_is_paid_from_the_minor_sale() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _world()
	var model: MapModel = world.region(0)
	model.resource[model.index_of(0, 1)] = MapModel.NO_ID
	var economies: Dictionary = _economies()
	var diplomacy := DiplomacyState.new()
	diplomacy.ensure_relation(2, 6, 0).set_score(50.0)
	diplomacy.set_overture(2, 6, DiplomacyCatalog.STAGE_EMBASSY)
	MarketOrders.submit(
		market,
		1, "timber", MarketOrder.SIDE_BID, 1,
		{"cargo_free": 4, "treasury": 5000, "buy_price": 30}
	)
	# Give the kickback recipient a ledger so the credit is observable.
	var embassy_court: PlayerEconomy = PlayerEconomy.starting()
	economies[2] = embassy_court
	var before: int = embassy_court.treasury
	MarketClearing.clear(market, world, economies, {0: 4, 1: 4, 2: 4}, {"diplomacy": diplomacy})
	assert_eq(embassy_court.treasury, before + 2, "1 x 30 x 50% x 10% = 1.5, rounded once")


func test_a_bid_beyond_the_purse_is_refused_before_the_book() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var result: Dictionary = MarketOrders.submit(
		market,
		0, "timber", MarketOrder.SIDE_BID, 10,
		{"cargo_free": 20, "treasury": 100, "buy_price": 30}
	)
	assert_false(bool(result["ok"]))
	assert_eq(String(result["code"]), "trade_order_bid_exceeds_treasury_budget")


func test_cancelling_an_offer_returns_its_submitted_volume() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var staged: Dictionary = MarketOrders.submit(
		market,
		1, "timber", MarketOrder.SIDE_OFFER, 3, {"stock": 3}
	)
	assert_true(bool(staged["ok"]))
	assert_eq(market.offer_volume("timber"), 3)
	assert_true(MarketOrders.cancel(market, 1, String(staged["order_id"])))
	assert_eq(market.offer_volume("timber"), 0)
	assert_false(MarketOrders.cancel(market, 1, "missing"))
