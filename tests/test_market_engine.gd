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


# --- favoured trading partner (wiki: diplomacy § R7.1) ------------------------


func test_the_suzerain_is_a_colonys_favoured_partner() -> void:
	var state := DiplomacyState.new()
	state.ensure_relation(1, 12, 0).set_score(90.0)
	state.set_colony(12, 0)
	assert_eq(MarketFavoured.of(state, 12), 0, "a colony ignores the warmer rival")
	assert_true(MarketFavoured.is_suzerain(state, 12, 0))
	assert_false(MarketFavoured.is_suzerain(state, 12, 1))


func test_the_warmest_court_is_an_independent_courts_favoured_partner() -> void:
	var state := DiplomacyState.new()
	state.ensure_relation(2, 7, 0).set_score(72.0)
	state.ensure_relation(1, 7, 0).set_score(68.0)
	assert_eq(MarketFavoured.of(state, 7), 2)


func test_an_equal_relation_breaks_to_the_smaller_court_id() -> void:
	var state := DiplomacyState.new()
	state.ensure_relation(2, 7, 0).set_score(60.0)
	state.ensure_relation(1, 7, 0).set_score(60.0)
	assert_eq(MarketFavoured.of(state, 7), 1)


func test_a_court_no_one_knows_has_no_favoured_partner() -> void:
	assert_eq(MarketFavoured.of(DiplomacyState.new(), 7), MarketFavoured.UNDEFINED)
	assert_eq(MarketFavoured.of(null, 7), MarketFavoured.UNDEFINED)


func test_a_colonys_suzerain_clears_the_tier_before_a_warmer_rival() -> void:
	var orders: Array[MarketOrder] = [
		_order(1, "timber", MarketOrder.SIDE_BID, 5, 1),
		_order(0, "timber", MarketOrder.SIDE_BID, 5, 1),
		_order(12, "timber", MarketOrder.SIDE_OFFER, 5, 1),
	]
	var context: Dictionary = _context()
	context["favoured_for"] = func(_seller: int) -> int: return 0
	context["consulate_for"] = func(_gp: int, _minor: int) -> bool: return true
	context["relation_for"] = func(gp: int, _minor: int) -> float:
		return 90.0 if gp == 1 else 10.0
	var result: Dictionary = MarketMatcher.match(orders, context)
	var deals: Array = result["deals"]
	assert_eq(deals.size(), 1)
	assert_eq(int(deals[0]["buyer"]), 0, "the suzerain trades first whatever its relation")
	assert_true(bool(deals[0]["is_favoured"]))
	assert_false(bool(deals[0]["is_ftp"]))


func test_a_favoured_colony_never_crosses_a_priority_tier() -> void:
	var orders: Array[MarketOrder] = [
		_order(0, "timber", MarketOrder.SIDE_BID, 5, 5),
		_order(1, "timber", MarketOrder.SIDE_BID, 5, 1),
		_order(12, "timber", MarketOrder.SIDE_OFFER, 5, 1),
	]
	var context: Dictionary = _context()
	context["favoured_for"] = func(_seller: int) -> int: return 0
	var result: Dictionary = MarketMatcher.match(orders, context)
	assert_eq(int((result["deals"] as Array)[0]["buyer"]), 1, "favour stays inside its tier")


func test_an_independent_seller_keeps_the_consulate_order() -> void:
	var orders: Array[MarketOrder] = [
		_order(1, "timber", MarketOrder.SIDE_BID, 5, 1),
		_order(2, "timber", MarketOrder.SIDE_BID, 5, 1),
		_order(7, "timber", MarketOrder.SIDE_OFFER, 5, 1),
	]
	var context: Dictionary = _context()
	# The independent court's R7.1 partner is its warmest buyer, and the auction
	# leaves that arm to R7.3: the Consulate holder is served first.
	context["favoured_for"] = func(_seller: int) -> int: return MarketFavoured.UNDEFINED
	context["consulate_for"] = func(gp: int, _minor: int) -> bool: return gp == 1
	context["relation_for"] = func(gp: int, _minor: int) -> float:
		return 90.0 if gp == 2 else 10.0
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


func _world(second_owner: int = 6) -> WorldMap:
	var model: MapModel = MapModel.new()
	model.setup(3, 2)
	for x in 2:
		model.province[model.index_of(x, 0)] = 0
	model.province[model.index_of(2, 0)] = 1
	model.province[model.index_of(0, 1)] = 1
	var tiles0: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var tiles1: Array[Vector2i] = [Vector2i(2, 0), Vector2i(0, 1)]
	var p0 := ProvinceState.create(0, "P0", tiles0, Vector2.ZERO, 2, 0)
	var p1 := ProvinceState.create(1, "P1", tiles1, Vector2.ZERO, 2, second_owner)
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


## The colony's harvest clears to its suzerain inside the tier even though the
## rival is the warmer, better-known court (wiki: diplomacy § R7.1;
## DR-20261111-11).
func test_the_suzerain_clears_a_colonys_harvest_at_turn_end() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var tribe: int = int(FactionCatalog.TRIBES[3]["id"])
	var world: WorldMap = _world(tribe)
	var economies: Dictionary = _economies()
	var diplomacy := DiplomacyState.new()
	diplomacy.set_colony(tribe, 0)
	for gp: int in [0, 1]:
		diplomacy.ensure_relation(gp, tribe, 0).set_score(10.0 if gp == 0 else 90.0)
		diplomacy.set_overture(gp, tribe, DiplomacyCatalog.STAGE_EMBASSY)
	# The rival speaks first, so the deal proves the tiebreak, not the book order.
	for gp: int in [1, 0]:
		MarketOrders.submit(
			market,
			gp, "timber", MarketOrder.SIDE_BID, 1,
			{"cargo_free": 4, "treasury": 5000, "buy_price": 30}
		)
	var report: Dictionary = MarketClearing.clear(
		market, world, economies, {0: 4, 1: 4}, {"diplomacy": diplomacy}
	)
	var from_colony: Array[Dictionary] = []
	var from_world: Array[Dictionary] = []
	for raw: Variant in report["deals"]:
		var deal: Dictionary = raw
		if String(deal.get("commodity", "")) != "timber":
			continue
		if int(deal.get("seller", -2)) == tribe:
			from_colony.append(deal)
		elif int(deal.get("seller", -2)) == MarketOrder.WORLD:
			from_world.append(deal)
	assert_eq(from_colony.size(), 1, "the colony's one timber auto-offer")
	assert_eq(int(from_colony[0]["buyer"]), 0, "the suzerain takes its colony's goods")
	assert_true(bool(from_colony[0]["is_favoured"]))
	assert_eq(from_world.size(), 1, "the rival buys at the published price instead")
	assert_eq(int(from_world[0]["buyer"]), 1)
	assert_false(bool(from_world[0]["is_favoured"]))


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


# --- what the auction promises and what it settles ---------------------------


## A sale's receipt names the ducats, not only the tons: the seller's fills row
## and the deal both carry what the auction paid (REQ-P5-05 — a sale is the one
## fill whose price the ledger could not otherwise show).
func test_a_sale_records_what_the_auction_paid() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _world()
	world.region(0).resource[world.region(0).index_of(2, 0)] = MapModel.NO_ID
	var economies: Dictionary = _economies()
	(economies[1] as PlayerEconomy).stockpile["timber"] = 2
	assert_true(bool(MarketOrders.submit(
		market, 1, "timber", MarketOrder.SIDE_OFFER, 2, {"stock": 2}
	)["ok"]))
	assert_true(bool(MarketOrders.submit(
		market, 0, "timber", MarketOrder.SIDE_BID, 2,
		{"cargo_free": 20, "treasury": 5000, "buy_price": 30}
	)["ok"]))
	var report: Dictionary = MarketClearing.clear(market, world, economies, {0: 20, 1: 20})
	var sold: Dictionary = (report["fills"] as Dictionary).get(1, {}) as Dictionary
	assert_eq(int(sold.get("sold", 0)), 2)
	assert_eq(int(sold.get("earned", 0)), 60, "two tons at the timber price")
	var deals: Array = report["deals"]
	var mine: Array = []
	for raw: Variant in deals:
		if int((raw as Dictionary).get("seller", -99)) == 1:
			mine.append(raw)
	assert_eq(mine.size(), 1)
	assert_eq(int(mine[0]["earned"]), 60, "the deal carries the receipt too")
	assert_eq(int((report["fills"] as Dictionary).get(0, {}).get("spent", 0)), 60)


## A bid cut short by cargo holds keeps its MarketActivityNote in the clearing
## report, so the Deal Book can audit the truncation (wiki: world-market
## § Treasury budget for bids — MarketActivityNote attribution).
func test_a_truncated_bid_keeps_its_audit_note() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _world()
	# No Minor harvest: the only supply is the Great Power offer below.
	world.region(0).resource[world.region(0).index_of(2, 0)] = MapModel.NO_ID
	var economies: Dictionary = _economies()
	(economies[1] as PlayerEconomy).stockpile["timber"] = 10
	assert_true(bool(MarketOrders.submit(
		market, 1, "timber", MarketOrder.SIDE_OFFER, 10, {"stock": 10}
	)["ok"]))
	assert_true(bool(MarketOrders.submit(
		market, 0, "timber", MarketOrder.SIDE_BID, 10,
		{"cargo_free": 20, "treasury": 5000, "buy_price": 30}
	)["ok"]))
	# The turn's overseas extraction reserves most of the holds before the
	# auction clears, so the bid can only take two tons.
	var report: Dictionary = MarketClearing.clear(market, world, economies, {0: 2, 1: 10})
	assert_eq(int((report["fills"] as Dictionary).get(0, {}).get("bought", 0)), 2)
	var codes: Array[String] = []
	for note: Dictionary in report["notes"]:
		codes.append(String(note.get("code", "")))
	assert_true(
		codes.has("bid_partial_fill_cargo_insufficient"),
		"the cargo truncation reaches the Deal Book: %s" % str(codes)
	)
	var booked: Array = market.book.last_notes
	assert_eq(booked.size(), report["notes"].size(), "the book keeps the same notes")


## The Deal Book names the constraint that actually stopped the bid: a purse
## that cannot buy one more ton is a treasury truncation, not a cargo shortfall
## (wiki: world-market § Treasury budget for bids; REQ-P5-05 never a wrong reason).
func test_a_bid_cut_by_the_purse_names_the_purse() -> void:
	var orders: Array[MarketOrder] = [
		_order(1, "timber", MarketOrder.SIDE_BID, 4, 1),
		_order(6, "timber", MarketOrder.SIDE_OFFER, 4, 1, 0, 1, true),
	]
	var context: Dictionary = _context({"treasuries": {1: 40}, "free_holds": {1: 10}})
	var result: Dictionary = MarketMatcher.match(orders, context)
	assert_eq(int(((result["deals"] as Array)[0] as Dictionary)["quantity"]), 1)
	var codes: Array[String] = []
	for note: Variant in result["notes"]:
		codes.append(String((note as Dictionary).get("code", "")))
	assert_true(codes.has("bid_partial_fill_treasury_insufficient"), str(codes))
	assert_false(codes.has("bid_partial_fill_cargo_insufficient"), str(codes))


## A bid with holds and purse to spare that no offer could fill is not a
## truncation; the Deal Book stays silent rather than blaming cargo.
func test_a_bid_with_no_offer_carries_without_a_note() -> void:
	var orders: Array[MarketOrder] = [
		_order(1, "timber", MarketOrder.SIDE_BID, 2, 1),
	]
	var context: Dictionary = _context({"treasuries": {1: 5000}, "free_holds": {1: 10}})
	var result: Dictionary = MarketMatcher.match(orders, context)
	assert_eq((result["notes"] as Array).size(), 0, str(result["notes"]))


## A Great Power offer the seller can no longer cover is not a deal, and the
## dropped units are named (wiki: world-market § Trade orders — an offer sells
## only what the ledger still holds; REQ-P5-05 never a silent outcome).
func test_an_offer_the_seller_spent_does_not_mint_goods() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _world()
	world.region(0).resource[world.region(0).index_of(2, 0)] = MapModel.NO_ID
	var economies: Dictionary = _economies()
	var seller: PlayerEconomy = economies[1]
	var buyer: PlayerEconomy = economies[0]
	seller.stockpile["timber"] = 10
	assert_true(bool(MarketOrders.submit(
		market, 1, "timber", MarketOrder.SIDE_OFFER, 10, {"stock": 10}
	)["ok"]))
	# Production runs before the auction and eats every ton offered.
	assert_true(seller.take("timber", 10))
	assert_true(bool(MarketOrders.submit(
		market, 0, "timber", MarketOrder.SIDE_BID, 10,
		{"cargo_free": 20, "treasury": 5000, "buy_price": 30}
	)["ok"]))
	var seller_purse: int = seller.treasury
	var buyer_purse: int = buyer.treasury
	var report: Dictionary = MarketClearing.clear(market, world, economies, {0: 20, 1: 20})
	assert_eq(seller.treasury, seller_purse, "no pay for timber the seller no longer holds")
	assert_eq(buyer.treasury, buyer_purse, "no charge for a deal that cannot ship")
	assert_eq(buyer.quantity("timber"), 0, "the auction never mints goods")
	var noted: bool = false
	for note: Dictionary in report["notes"]:
		if String(note.get("code", "")) == "offer_partial_fill_stock_insufficient":
			noted = true
	assert_true(noted, "the dropped fill is on the deal book")


## The offer cap is the post-production stockpile minus the inputs the assigned
## runs will eat (wiki: world-market § Trade orders — validation rule 7).
func test_an_offer_is_capped_by_the_production_that_will_eat_it() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var reserved: Dictionary = ProductionRecipes.reserved_inputs(
		[{"recipe": "lumber", "units": 3}]
	)
	assert_eq(int(reserved.get("timber", 0)), 6, "3 runs x 2 timber")
	var refused: Dictionary = MarketOrders.submit(
		market, 1, "timber", MarketOrder.SIDE_OFFER, 5,
		{"stock": 10, "reserved": reserved}
	)
	assert_false(bool(refused["ok"]))
	assert_eq(String(refused["code"]), "trade_order_stock_insufficient")
	var admitted: Dictionary = MarketOrders.submit(
		market, 1, "timber", MarketOrder.SIDE_OFFER, 4,
		{"stock": 10, "reserved": reserved}
	)
	assert_true(bool(admitted["ok"]), String(admitted.get("reason", "")))
