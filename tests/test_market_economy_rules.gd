extends GdToolsTest
## One boot for the purse: the market's offers and engine, the economy's rules and
## its overseas share, and trade cargo (wiki: world-market).

## Merged from test_market_offers, test_market_engine, test_economy_rules,
## test_economy_overseas, test_trade_cargo.
## One Godot boot (coverage instrumentation) per theme instead of one per file.
## Each test runs only its own suite's setup; teardown follows the setup.
const NavalFixture = preload("res://tests/naval_fixture.gd")

var _seq: int = 0

# --- test_market_offers ---

func _book() -> Array:
	return [
		{
			"id": "9:timber",
			"faction": 9,
			"commodity": "timber",
			"quantity": 3,
			"unit_price": 30,
		},
		{
			"id": "7:grain",
			"faction": 7,
			"commodity": "grain",
			"quantity": 5,
			"unit_price": 12,
		},
		{
			"id": "7:timber",
			"faction": 7,
			"commodity": "timber",
			"quantity": 1,
			"unit_price": 28,
		},
		{
			"id": "11:grain",
			"faction": 11,
			"commodity": "grain",
			"quantity": 2,
			"unit_price": 12,
		},
	]

func _ids(rows: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for row: Dictionary in rows:
		out.append(String(row["id"]))
	return out

func test_the_seller_filter_narrows_the_book_to_one_court() -> void:
	var rows: Array[Dictionary] = MarketOffersHead.apply(
		_book(), 7, MarketOffersHead.ALL_GOODS, MarketOffersHead.SORT_SELLER
	)
	assert_eq(_ids(rows), ["7:grain", "7:timber"])

func test_the_good_filter_narrows_the_book_to_one_commodity() -> void:
	var rows: Array[Dictionary] = MarketOffersHead.apply(
		_book(), MarketOffersHead.ALL_SELLERS, "grain", MarketOffersHead.SORT_SELLER
	)
	assert_eq(rows.size(), 2)
	for row: Dictionary in rows:
		assert_eq(String(row["commodity"]), "grain")

func test_both_filters_narrow_together_and_can_empty_the_book() -> void:
	var narrowed: Array[Dictionary] = MarketOffersHead.apply(
		_book(), 9, "timber", MarketOffersHead.SORT_SELLER
	)
	assert_eq(_ids(narrowed), ["9:timber"])
	assert_eq(
		MarketOffersHead.apply(_book(), 9, "grain", MarketOffersHead.SORT_SELLER).size(), 0
	)

## Court A–Z by name (not by id), and the richer book first inside a court.
func test_the_default_order_is_court_name_then_the_richest_book() -> void:
	var rows: Array[Dictionary] = MarketOffersHead.apply(
		_book(), MarketOffersHead.ALL_SELLERS, MarketOffersHead.ALL_GOODS,
		MarketOffersHead.SORT_SELLER
	)
	assert_eq(_ids(rows), ["9:timber", "11:grain", "7:grain", "7:timber"])

func test_sorting_by_good_groups_the_commodities() -> void:
	var rows: Array[Dictionary] = MarketOffersHead.apply(
		_book(), MarketOffersHead.ALL_SELLERS, MarketOffersHead.ALL_GOODS,
		MarketOffersHead.SORT_GOOD
	)
	assert_eq(_ids(rows), ["11:grain", "7:grain", "7:timber", "9:timber"])

func test_cheapest_first_pays_less_per_ton() -> void:
	var rows: Array[Dictionary] = MarketOffersHead.apply(
		_book(), MarketOffersHead.ALL_SELLERS, MarketOffersHead.ALL_GOODS,
		MarketOffersHead.SORT_PRICE
	)
	var prices: Array[int] = []
	for row: Dictionary in rows:
		prices.append(int(row["unit_price"]))
	assert_eq(prices, [12, 12, 28, 30], "the cheapest ask leads: %s" % [_ids(rows)])

func test_most_stock_first_fills_a_bid_sooner() -> void:
	var rows: Array[Dictionary] = MarketOffersHead.apply(
		_book(), MarketOffersHead.ALL_SELLERS, MarketOffersHead.ALL_GOODS,
		MarketOffersHead.SORT_STOCK
	)
	assert_eq(_ids(rows), ["7:grain", "9:timber", "11:grain", "7:timber"])

func test_junk_rows_are_skipped_and_the_published_book_is_never_reordered() -> void:
	var book: Array = _book()
	var published: Array = book.duplicate(true)
	book.append("not an offer")
	var rows: Array[Dictionary] = MarketOffersHead.apply(
		book, MarketOffersHead.ALL_SELLERS, MarketOffersHead.ALL_GOODS,
		MarketOffersHead.SORT_GOOD
	)
	assert_eq(rows.size(), 4)
	assert_eq(book.slice(0, 4), published, "a filter never edits the auction's own rows")

func test_the_head_offers_one_chip_per_court_and_good_on_the_table() -> void:
	var head := MarketOffersHead.new()
	head.render(
		_book(), MarketOffersHead.ALL_SELLERS, MarketOffersHead.ALL_GOODS,
		MarketOffersHead.SORT_SELLER
	)
	var chips: Dictionary = head.filter_buttons()
	assert_eq((chips["seller:-1"] as Button).text, "All courts 11", "all tons on the table")
	assert_eq((chips["seller:9"] as Button).text, "Aztec 3")
	assert_eq((chips["seller:7"] as Button).text, "Venice 6")
	assert_false(chips.has("seller:5"), "a court with nothing for sale has no chip")
	assert_eq((chips["good:grain"] as Button).text, "Grain 7")
	assert_eq((chips["good:timber"] as Button).text, "Timber 4")
	assert_false(chips.has("good:meat"), "a good nobody sells has no chip")
	for key: String in MarketOffersHead.SORT_KEYS:
		assert_true(chips.has("sort:%s" % key), "the order chip %s exists" % key)
	assert_true((chips["seller:-1"] as Button).button_pressed, "All is the opening filter")
	assert_true((chips["sort:seller"] as Button).button_pressed)
	head.free()

func test_a_chip_press_is_the_whole_filter_intent() -> void:
	var head := MarketOffersHead.new()
	head.render(
		_book(), MarketOffersHead.ALL_SELLERS, MarketOffersHead.ALL_GOODS,
		MarketOffersHead.SORT_SELLER
	)
	var seen: Array = []
	head.filters_changed.connect(
		func(seller: int, good: String, sort_key: String) -> void:
			seen.append([seller, good, sort_key])
	)
	(head.filter_buttons()["seller:11"] as Button).pressed.emit()
	assert_eq(head.seller, 11)
	assert_eq(seen, [[11, MarketOffersHead.ALL_GOODS, MarketOffersHead.SORT_SELLER]])
	var chips: Dictionary = head.filter_buttons()
	assert_true((chips["seller:11"] as Button).button_pressed, "the chosen chip lights")
	assert_false((chips["seller:-1"] as Button).button_pressed, "All steps aside")

	(head.filter_buttons()["good:timber"] as Button).pressed.emit()
	assert_eq(head.commodity, "timber")
	assert_eq(seen.size(), 2)
	assert_eq(seen[1], [11, "timber", MarketOffersHead.SORT_SELLER])

	(head.filter_buttons()["sort:quantity"] as Button).pressed.emit()
	assert_eq(head.sort_key, MarketOffersHead.SORT_STOCK)
	assert_eq(seen.size(), 3)
	assert_eq(seen[2], [11, "timber", MarketOffersHead.SORT_STOCK])
	head.free()

## A court that sold out this turn takes its chip with it; the filter falls back
## to All and tells the page, so the strip never hides the whole book silently.
func test_a_selection_the_new_book_lost_falls_back_to_all() -> void:
	var head := MarketOffersHead.new()
	head.render(_book(), 11, "grain", MarketOffersHead.SORT_PRICE)
	assert_eq(head.seller, 11)

	var seen: Array = []
	head.filters_changed.connect(
		func(seller: int, good: String, sort_key: String) -> void:
			seen.append([seller, good, sort_key])
	)
	var next_book: Array = [_book()[0]]
	head.render(next_book, 11, "grain", MarketOffersHead.SORT_PRICE)
	assert_eq(head.seller, MarketOffersHead.ALL_SELLERS)
	assert_eq(head.commodity, MarketOffersHead.ALL_GOODS)
	assert_eq(head.sort_key, MarketOffersHead.SORT_PRICE, "a live order survives the turn")
	assert_eq(seen, [[MarketOffersHead.ALL_SELLERS, MarketOffersHead.ALL_GOODS,
		MarketOffersHead.SORT_PRICE]])
	head.free()

func test_an_unknown_order_key_falls_back_to_the_court_order() -> void:
	var head := MarketOffersHead.new()
	head.render(_book(), MarketOffersHead.ALL_SELLERS, MarketOffersHead.ALL_GOODS, "sideways")
	assert_eq(head.sort_key, MarketOffersHead.SORT_SELLER)
	head.free()

## Chips are thumb targets on a phone viewport (REQ-P5-07).
func test_chips_grow_for_a_thumb_on_a_phone() -> void:
	var head := MarketOffersHead.new()
	head.render(
		_book(), MarketOffersHead.ALL_SELLERS, MarketOffersHead.ALL_GOODS,
		MarketOffersHead.SORT_SELLER
	)
	head.set_compact(true)
	for key: Variant in head.filter_buttons().keys():
		var chip: Button = head.filter_buttons()[key] as Button
		assert_eq(chip.custom_minimum_size.y, MarketOffersHead.CHIP_HEIGHT_TOUCH, String(key))
	head.set_compact(false)
	for key: Variant in head.filter_buttons().keys():
		var chip: Button = head.filter_buttons()[key] as Button
		assert_eq(chip.custom_minimum_size.y, MarketOffersHead.CHIP_HEIGHT, String(key))
	head.free()

# --- test_market_engine ---

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

func _market_engine_world(second_owner: int = 6) -> WorldMap:
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
	var world: WorldMap = _market_engine_world()
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
	var world: WorldMap = _market_engine_world()
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
	var world: WorldMap = _market_engine_world()
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
	var world: WorldMap = _market_engine_world(tribe)
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
	var world: WorldMap = _market_engine_world()
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

## Live play installs the crown's trade terms too, so the step must land once
## and not multiply the surcharge by itself (wiki: world-market § Subsidy price
## adjustment — the debt is `round(Q × P × (1 + p/100))`).
func test_the_subsidy_step_lands_once_with_the_terms_installed() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _market_engine_world()
	var economies: Dictionary = _economies()
	var diplomacy := DiplomacyState.new()
	diplomacy.set_subsidy(0, 6, 10)
	DiplomacyTrade.apply_terms(diplomacy, world, market)
	assert_eq(market.buy_price("timber", 0), 30, "the crown's own rate is the world price")
	MarketOrders.submit(
			market,
		0, "timber", MarketOrder.SIDE_BID, 1,
		{"cargo_free": 4, "treasury": 5000, "buy_price": market.buy_price("timber", 0)}
	)
	var before: int = (economies[0] as PlayerEconomy).treasury
	MarketClearing.clear(market, world, economies, {0: 4, 1: 4}, {"diplomacy": diplomacy})
	assert_eq(
		(economies[0] as PlayerEconomy).treasury, before - 33,
		"round(1 x 30 x 1.10) once, not the square of it"
	)

## The same goods bought from any other court carry no step: one unit from the
## subsidised Minor at 33, one the standing counterparty supplies at 30.
func test_a_subsidy_leaves_another_courts_deal_alone() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _market_engine_world()
	var economies: Dictionary = _economies()
	var diplomacy := DiplomacyState.new()
	diplomacy.set_subsidy(0, 6, 10)
	DiplomacyTrade.apply_terms(diplomacy, world, market)
	MarketOrders.submit(
			market,
		0, "timber", MarketOrder.SIDE_BID, 2,
		{"cargo_free": 4, "treasury": 5000, "buy_price": market.buy_price("timber", 0)}
	)
	var before: int = (economies[0] as PlayerEconomy).treasury
	MarketClearing.clear(market, world, economies, {0: 4, 1: 4}, {"diplomacy": diplomacy})
	assert_eq(
		(economies[0] as PlayerEconomy).treasury, before - 63,
		"33 to the subsidised court plus 30 to the counterparty"
	)

## The step stacks on the crown's own rate inside the rails the page publishes
## (wiki: world-market § Subsidy price adjustment — 70–150% buy, 50–130% sell).
func test_a_subsidy_steps_inside_the_published_rails() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	market.set_terms(0, {"buy": {"*": 1.5}, "sell": {"*": 0.5}})
	assert_almost_eq(
		MarketRules.deal_rate(market, "timber", 0, 1.2, true), 1.5, 0.001,
		"a 20% step on a 150% rate stops at the buy rail"
	)
	assert_almost_eq(
		MarketRules.deal_rate(market, "timber", 0, 0.8, false), 0.5, 0.001,
		"and the sell rail holds too"
	)
	var plain: WorldMarket = WorldMarket.with_default_prices()
	assert_almost_eq(MarketRules.deal_rate(plain, "timber", 0, 1.1, true), 1.1, 0.001)
	assert_almost_eq(MarketRules.deal_rate(plain, "timber", 0, 1.0, true), 1.0, 0.001)

## The step's arms and the guards around them: a crown buying a subsidised
## Minor's goods pays more, a Minor buying a crown's pays less, and every other
## pairing — two crowns, two minors, a minor's own sale — carries no step
## (wiki: world-market § Subsidy price adjustment, R3.4a/b).
func test_subsidy_step_arms_and_guards() -> void:
	assert_eq(MarketRules.subsidy_step(0, false, true, true), 1.0)
	assert_eq(MarketRules.subsidy_step(10, false, true, true), 1.1, "the payer buys dearer")
	assert_eq(MarketRules.subsidy_step(10, true, false, true), 0.9, "the minor buys cheaper")
	assert_eq(MarketRules.subsidy_step(10, true, true, true), 1.0, "two minors: no step")
	assert_eq(MarketRules.subsidy_step(10, false, false, true), 1.0, "two crowns: no step")
	assert_eq(
		MarketRules.subsidy_step(10, true, false, false), 0.9,
		"a crown's sale to the subsidised minor earns less"
	)
	assert_eq(MarketRules.subsidy_step(10, false, true, false), 1.0, "a minor's sale is cut")
	var market: WorldMarket = WorldMarket.with_default_prices()
	assert_eq(MarketRules.subsidy_percent(null, 0, 6), 0)
	assert_eq(MarketRules.subsidy_percent(market, -1, 6), 0)
	assert_eq(MarketRules.subsidy_percent(market, 0, -1), 0)
	assert_eq(MarketRules.deal_total(market, "timber", 0, 0, 1.1, true), 0, "no units, no debt")
	assert_false(MarketRules.is_minor(-1))
	assert_false(MarketRules.is_minor(0))
	assert_true(MarketRules.is_minor(6), "a Minor Nation")
	assert_true(MarketRules.is_minor(9), "a Tribe")
	# The sell arm of the pair helpers: a crown selling to the minor it subsidises.
	assert_eq(
		MarketRules.deal_unit_for(market, "timber", 6, 0, 10, false),
		roundi(float(market.price("timber")) * 0.9)
	)
	assert_eq(
		MarketRules.deal_total_for(market, "timber", 2, 6, 0, 10, false),
		roundi(float(2) * float(market.price("timber")) * 0.9)
	)


## The Minor's ask guards an empty market and an untradeable row, and reads a
## court with no step at the published price (wiki: world-market § Price
## discovery, § Subsidy price adjustment).
func test_the_minor_ask_guards_and_the_unstepped_row() -> void:
	assert_eq(MinorMarket.unit_price(null, "timber"), 0)
	var market: WorldMarket = WorldMarket.with_default_prices()
	assert_eq(MinorMarket.unit_price(market, "gold"), 0, "riches never trade")
	assert_eq(
		MinorMarket.unit_price(market, "timber", 0, 7),
		market.price("timber"),
		"a pair with no subsidy pays the world price"
	)
	assert_eq(MinorMarket.unit_price(market, "timber", 0), market.price("timber"))


func test_unfilled_bid_carries_or_drops_when_cargo_is_short() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _market_engine_world()
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
	var world: WorldMap = _market_engine_world()
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
	var world: WorldMap = _market_engine_world()
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
	var world: WorldMap = _market_engine_world()
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
	var world: WorldMap = _market_engine_world()
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
	var world: WorldMap = _market_engine_world()
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

## A sale's receipt names the ducats, not only the tons: the seller's fills row
## and the deal both carry what the auction paid (REQ-P5-05 — a sale is the one
## fill whose price the ledger could not otherwise show).
func test_a_sale_records_what_the_auction_paid() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _market_engine_world()
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
	var world: WorldMap = _market_engine_world()
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
	var world: WorldMap = _market_engine_world()
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

# --- test_economy_rules ---

func test_pool_counts_labour_and_food_by_tier() -> void:
	var pool: WorkerPool = WorkerPool.make(3, 2, 1, 1)
	assert_eq(pool.count(WorkerPool.Tier.PEASANT), 3)
	assert_eq(pool.count(WorkerPool.Tier.MASTER), 1)
	assert_eq(pool.total(), 7)
	assert_eq(pool.labour(), 3 * 1 + 2 * 4 + 1 * 6 + 1 * 8)
	assert_eq(pool.food_demand(), 3 * 1 + 2 * 2 + 1 * 2 + 1 * 2)

func test_pool_ignores_unknown_tiers_and_negative_counts() -> void:
	var pool: WorkerPool = WorkerPool.make(2)
	pool.set_count(-1, 5)
	pool.set_count(9, 5)
	pool.add(WorkerPool.Tier.PEASANT, -10)
	assert_eq(pool.total(), 0)
	assert_eq(pool.count(-1), 0)
	assert_false(pool.remove(WorkerPool.Tier.MASTER))
	assert_eq(pool.food_demand(), 0)

func test_luxury_and_tech_metadata_match_the_tiers() -> void:
	assert_eq(WorkerPool.luxury_for(WorkerPool.Tier.PEASANT), "")
	assert_eq(WorkerPool.luxury_for(WorkerPool.Tier.APPRENTICE), "refinedSugar")
	assert_eq(WorkerPool.luxury_for(WorkerPool.Tier.JOURNEYMAN), "cigars")
	assert_eq(WorkerPool.luxury_for(WorkerPool.Tier.MASTER), "furHats")
	assert_eq(WorkerPool.required_techs(WorkerPool.Tier.PEASANT), [])
	assert_true(WorkerPool.techs_unlocked(WorkerPool.Tier.PEASANT, {}))
	assert_false(WorkerPool.techs_unlocked(WorkerPool.Tier.APPRENTICE, {}))
	assert_false(
		WorkerPool.techs_unlocked(WorkerPool.Tier.APPRENTICE, {"apprentice_workers": true})
	)
	assert_true(
		WorkerPool.techs_unlocked(
			WorkerPool.Tier.APPRENTICE,
			{"apprentice_workers": true, "sugar_refining": true}
		)
	)
	assert_eq(WorkerPool.tier_name(WorkerPool.Tier.JOURNEYMAN), "Journeymen")

func test_recruit_costs_match_the_v1_table() -> void:
	var peasant: Dictionary = {"treasury": 0, "materials": {"fabric": 2}}
	var apprentice: Dictionary = {"treasury": 200, "materials": {"paper": 2}}
	var journeyman: Dictionary = {"treasury": 500, "materials": {"paper": 5}}
	var master: Dictionary = {"treasury": 1000, "materials": {"paper": 10}}
	assert_eq(WorkerPool.recruit_cost(WorkerPool.Tier.PEASANT), peasant)
	assert_eq(WorkerPool.recruit_cost(WorkerPool.Tier.APPRENTICE), apprentice)
	assert_eq(WorkerPool.recruit_cost(WorkerPool.Tier.JOURNEYMAN), journeyman)
	assert_eq(WorkerPool.recruit_cost(WorkerPool.Tier.MASTER), master)
	assert_false(WorkerPool.RECRUIT_CONSUMES_PEASANTS[WorkerPool.Tier.PEASANT])
	assert_true(WorkerPool.RECRUIT_CONSUMES_PEASANTS[WorkerPool.Tier.MASTER])

func test_copy_is_independent() -> void:
	var pool: WorkerPool = WorkerPool.make(2, 1)
	var clone: WorkerPool = pool.copy()
	clone.add(WorkerPool.Tier.PEASANT, 3)
	assert_eq(pool.count(WorkerPool.Tier.PEASANT), 2)
	assert_eq(clone.count(WorkerPool.Tier.PEASANT), 5)
	assert_eq(clone.count(WorkerPool.Tier.APPRENTICE), 1)

func test_economy_recruits_peasants_with_fabric() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.stockpile["fabric"] = 2
	var result: Dictionary = economy.recruit(WorkerPool.Tier.PEASANT)
	assert_true(bool(result["ok"]))
	assert_eq(economy.workers.count(WorkerPool.Tier.PEASANT), PlayerEconomy.START_PEASANTS + 1)
	assert_eq(economy.quantity("fabric"), 0)
	assert_eq(economy.treasury, PlayerEconomy.START_TREASURY)

func test_recruiting_a_peasant_needs_fabric() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	# The opening stock now carries cloth for the muster; drain it to test the gate.
	economy.stockpile["fabric"] = 0
	var result: Dictionary = economy.recruit(WorkerPool.Tier.PEASANT)
	assert_false(bool(result["ok"]))
	assert_eq(String(result["reason"]), "Insufficient materials")
	assert_eq(economy.workers.count(WorkerPool.Tier.PEASANT), PlayerEconomy.START_PEASANTS)

func test_trained_tiers_are_tech_gated_and_consume_a_peasant() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.stockpile["paper"] = 4
	var blocked: Dictionary = economy.recruit(WorkerPool.Tier.APPRENTICE)
	assert_false(bool(blocked["ok"]))
	assert_eq(String(blocked["reason"]), "Required technology not unlocked")
	assert_eq(economy.quantity("paper"), 4)

	economy.tech_unlocked = {"apprentice_workers": true, "sugar_refining": true}
	var result: Dictionary = economy.recruit(WorkerPool.Tier.APPRENTICE)
	assert_true(bool(result["ok"]))
	assert_eq(economy.workers.count(WorkerPool.Tier.APPRENTICE), 1)
	assert_eq(economy.workers.count(WorkerPool.Tier.PEASANT), PlayerEconomy.START_PEASANTS - 1)
	assert_eq(economy.treasury, PlayerEconomy.START_TREASURY - 200)
	assert_eq(economy.quantity("paper"), 2)

func test_training_needs_a_peasant_and_treasury() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.tech_unlocked = {
		"master_artisans": true,
		"hat_production": true,
	}
	economy.stockpile["paper"] = 10
	var poor: PlayerEconomy = economy.copy()
	poor.treasury = 999
	assert_eq(String(poor.recruit(WorkerPool.Tier.MASTER)["reason"]), "Insufficient treasury")

	economy.workers.set_count(WorkerPool.Tier.PEASANT, 0)
	assert_eq(String(economy.recruit(WorkerPool.Tier.MASTER)["reason"]), "Insufficient workers")
	economy.workers.set_count(WorkerPool.Tier.PEASANT, 1)
	assert_true(bool(economy.recruit(WorkerPool.Tier.MASTER)["ok"]))
	assert_eq(economy.workers.count(WorkerPool.Tier.MASTER), 1)
	assert_eq(economy.workers.count(WorkerPool.Tier.PEASANT), 0)

## A recruit is a queued order: the press files it, nothing is paid, and the
## peasant it will take is reserved so a second order cannot promise the same
## head (wiki: workers-and-population § Phase placement, § Peasant reservation).
func test_a_queued_recruit_reserves_the_peasant_it_will_take() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.tech_unlocked = {"apprentice_workers": true, "sugar_refining": true}
	economy.stockpile["paper"] = 4
	var peasants: int = economy.available_peasants()

	assert_true(bool(economy.queue_recruit(WorkerPool.Tier.APPRENTICE)["ok"]))
	assert_eq(economy.workers.count(WorkerPool.Tier.PEASANT), peasants, "no head moves yet")
	assert_eq(economy.available_peasants(), peasants - 1)
	assert_eq(economy.recruits.reserved_peasants(), 1)
	assert_eq(economy.treasury, PlayerEconomy.START_TREASURY, "nothing is paid yet")

	economy.workers.set_count(WorkerPool.Tier.PEASANT, 1)
	assert_eq(
		String(economy.queue_recruit(WorkerPool.Tier.APPRENTICE)["reason"]),
		"Insufficient workers",
		"the one peasant left is already promised"
	)
	assert_eq(economy.recruits.total(), 1, "a refused order is not filed")


## A peasant recruit consumes no headcount, so it reserves none.
func test_a_queued_peasant_recruit_takes_no_reservation() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.stockpile["fabric"] = 2
	var peasants: int = economy.available_peasants()
	assert_true(bool(economy.queue_recruit(WorkerPool.Tier.PEASANT)["ok"]))
	assert_eq(economy.available_peasants(), peasants)
	assert_eq(economy.recruits.reserved_peasants(), 0)


## Build/work takes the queue whole, so an order resolves exactly once.
func test_the_build_work_pass_drains_the_queue_once() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.stockpile["fabric"] = 2
	economy.queue_recruit(WorkerPool.Tier.PEASANT)
	var orders: Array[Dictionary] = economy.recruits.take_all()
	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["kind"]), RecruitQueue.KIND_WORKER)
	assert_true(economy.recruits.is_empty())
	assert_eq(economy.recruits.take_all().size(), 0, "a second pass finds nothing")


## A save carries the orders and the peasants they promise.
func test_orders_and_their_reservation_survive_a_snapshot() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.queue_build(RecruitQueue.KIND_SHIP, "carrack")
	economy.queue_build(RecruitQueue.KIND_CIVILIAN, "builder")
	var restored: PlayerEconomy = PlayerEconomy.starting()
	restored.apply_snapshot(economy.snapshot())
	assert_eq(restored.recruits.total(), 2)
	assert_eq(restored.recruits.pending(RecruitQueue.KIND_SHIP, "carrack"), 1)
	assert_eq(restored.recruits.reserved_peasants(), 1, "the hull's peasant stays reserved")
	assert_eq(restored.available_peasants(), economy.available_peasants())


## A damaged save drops what it cannot read instead of trusting it.
func test_a_damaged_save_drops_orders_it_cannot_read() -> void:
	var queue := RecruitQueue.new()
	queue.read(
		[{"kind": "worker", "key": "1"}, {"kind": "nonsense", "key": "x"}, 7]
	)
	assert_eq(queue.total(), 1)
	assert_eq(RecruitQueue.label(queue.orders[0]), "Apprentice")
	queue.read("not a queue")
	assert_true(queue.is_empty())


## A planning copy carries its own queue: simulating a turn never files an order
## on the live ledger.
func test_a_copy_carries_its_own_queue() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.queue_recruit(WorkerPool.Tier.PEASANT)
	var clone: PlayerEconomy = economy.copy()
	clone.recruits.take_all()
	assert_eq(economy.recruits.total(), 1, "the live ledger keeps its order")
	assert_eq(clone.recruits.total(), 0)


## The queue counts its orders by kind, names each on the ledger, and reserves
## one peasant per trained worker or build (wiki: workers-and-population
## § Peasant reservation).
func test_the_queue_counts_its_orders_by_kind_and_names_them() -> void:
	var queue := RecruitQueue.new()
	assert_true(queue.is_empty())
	assert_eq(queue.total(), 0)

	queue.add(RecruitQueue.KIND_WORKER, str(WorkerPool.Tier.APPRENTICE))
	queue.add(RecruitQueue.KIND_WORKER, str(WorkerPool.Tier.MASTER))
	queue.add(RecruitQueue.KIND_SHIP, "carrack")
	assert_eq(queue.total(), 3)
	assert_false(queue.is_empty())
	assert_eq(queue.pending_kind(RecruitQueue.KIND_WORKER), 2)
	assert_eq(queue.pending(RecruitQueue.KIND_WORKER, str(WorkerPool.Tier.APPRENTICE)), 1)
	assert_eq(queue.pending(RecruitQueue.KIND_REGIMENT, "peasant_levies"), 0)
	assert_eq(queue.reserved_peasants(), 3, "two trained workers and one hull")

	assert_eq(RecruitQueue.label(queue.orders[0]), "Apprentice")
	assert_eq(RecruitQueue.label(queue.orders[1]), "Master")
	assert_eq(RecruitQueue.label(queue.orders[2]), "Carrack")
	assert_eq(RecruitQueue.label({"kind": "civilian", "key": "builder"}), "Builder")
	assert_eq(RecruitQueue.label({"kind": "regiment", "key": "peasant_levies"}), "Peasant Levies")
	assert_eq(RecruitQueue.label({"kind": "mystery", "key": "x"}), "x", "an unknown kind names its key")
	assert_eq(queue.snapshot().size(), 3)


func test_disband_demotes_one_tier_to_peasant_without_refund() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.workers.set_count(WorkerPool.Tier.JOURNEYMAN, 2)
	assert_true(economy.disband(WorkerPool.Tier.JOURNEYMAN))
	assert_eq(economy.workers.count(WorkerPool.Tier.JOURNEYMAN), 1)
	assert_eq(economy.workers.count(WorkerPool.Tier.PEASANT), PlayerEconomy.START_PEASANTS + 1)
	assert_false(economy.disband(WorkerPool.Tier.PEASANT))
	assert_false(economy.disband(WorkerPool.Tier.MASTER))
	assert_eq(economy.treasury, PlayerEconomy.START_TREASURY)

## The ledger asks the rules why a disband is inert instead of guessing
## (wiki: workers-and-population § Disband; REQ-P2-03).
func test_disband_names_its_blocked_reasons() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	assert_eq(
		economy.disband_blocked_reason(WorkerPool.Tier.PEASANT),
		"Only a trained worker returns to the fields"
	)
	assert_eq(
		economy.disband_blocked_reason(WorkerPool.Tier.MASTER),
		"No master to send back"
	)
	economy.workers.set_count(WorkerPool.Tier.MASTER, 1)
	assert_eq(economy.disband_blocked_reason(WorkerPool.Tier.MASTER), "")
	assert_eq(
		economy.disband_blocked_reason(WorkerPool.TIER_COUNT), "Only a trained worker returns to the fields"
	)
	assert_eq(WorkerPool.tier_one(WorkerPool.Tier.APPRENTICE), "Apprentice")

func test_navy_eats_before_workers_and_two_units_per_ship() -> void:
	var pool: WorkerPool = WorkerPool.make(3)
	var stock: Dictionary = {"grain": 10, "meat": 0}
	var report: Dictionary = EconomyConsumption.resolve(pool, stock, 2)
	assert_eq(report["navy_demand"], 4)
	assert_eq(report["navy_fed"], 4)
	assert_eq(stock["grain"], 3)
	assert_eq(report["fed_workers"], 3)
	assert_eq(report["strikers"], 0)
	assert_eq(report["idle_labour"], 3)

## Fully fed hulls over hulls, not food units over food units: three food for
## two hulls feeds one hull in full, so the coverage is 0.5, not 0.75
## (wiki: workers-and-population § Consumption).
func test_navy_coverage_counts_fully_fed_hulls() -> void:
	assert_almost_eq(
		EconomyConsumption.navy_coverage({"navy_demand": 4, "navy_fed": 4}), 1.0, 0.0001
	)
	assert_almost_eq(
		EconomyConsumption.navy_coverage({"navy_demand": 4, "navy_fed": 3}), 0.5, 0.0001
	)
	assert_almost_eq(
		EconomyConsumption.navy_coverage({"navy_demand": 4, "navy_fed": 0}), 0.0, 0.0001
	)
	assert_almost_eq(EconomyConsumption.navy_coverage({}), 1.0, 0.0001)

func test_food_is_eaten_from_grain_before_meat() -> void:
	var pool: WorkerPool = WorkerPool.make(0)
	var stock: Dictionary = {"grain": 1, "meat": 5}
	var report: Dictionary = EconomyConsumption.resolve(pool, stock, 2)
	assert_eq(report["navy_fed"], 4)
	assert_eq(stock["grain"], 0)
	assert_eq(stock["meat"], 2)

func test_army_rations_come_first() -> void:
	var pool: WorkerPool = WorkerPool.make(1)
	var stock: Dictionary = {"grain": 2, "meat": 0}
	var report: Dictionary = EconomyConsumption.resolve(pool, stock, 0, 2)
	assert_eq(report["army_fed"], 2)
	assert_eq(report["fed_workers"], 0)
	assert_eq(report["strikers"], 1)
	assert_eq(stock["grain"], 0)

func test_trained_workers_need_grain_and_meat() -> void:
	var pool: WorkerPool = WorkerPool.make(0, 1)
	var stock: Dictionary = {"grain": 4, "meat": 0}
	var report: Dictionary = EconomyConsumption.resolve(pool, stock, 0)
	assert_eq(report["fed_workers"], 0)
	assert_eq(report["strikers"], 1)
	assert_eq(report["idle_labour"], 0)
	assert_eq(stock["grain"], 4)

	var fed_stock: Dictionary = {"grain": 1, "meat": 1, "refinedSugar": 1}
	var fed: Dictionary = EconomyConsumption.resolve(WorkerPool.make(0, 1), fed_stock, 0)
	assert_eq(fed["fed_workers"], 1)
	assert_eq(fed["luxury_spent"], {"refinedSugar": 1})
	assert_eq(fed["idle_labour"], 4)
	assert_eq(fed_stock["grain"], 0)
	assert_eq(fed_stock["meat"], 0)

func test_workers_are_fed_masters_before_peasants() -> void:
	var pool: WorkerPool = WorkerPool.make(1, 0, 0, 1)
	var stock: Dictionary = {"grain": 1, "meat": 1, "furHats": 1}
	var report: Dictionary = EconomyConsumption.resolve(pool, stock, 0)
	assert_eq(report["fed_counts"], [0, 0, 0, 1])
	assert_eq(report["strikers"], 1)
	assert_eq(report["idle_labour"], 8)
	assert_eq(report["luxury_spent"], {"furHats": 1})
	assert_eq(stock["grain"], 0)
	assert_eq(stock["meat"], 0)

func test_peasants_take_one_food_unit_of_either_kind() -> void:
	var stock: Dictionary = {"grain": 1, "meat": 3}
	var report: Dictionary = EconomyConsumption.resolve(WorkerPool.make(3), stock, 0)
	assert_eq(report["fed_workers"], 3)
	assert_eq(stock["grain"], 0)
	assert_eq(stock["meat"], 1)

func test_luxury_is_all_or_nothing_per_food_fed_worker() -> void:
	var pool: WorkerPool = WorkerPool.make(0, 2)
	var stock: Dictionary = {"grain": 2, "meat": 2, "refinedSugar": 1}
	var report: Dictionary = EconomyConsumption.resolve(pool, stock, 0)
	assert_eq(report["fed_workers"], 2)
	assert_eq(report["luxury_spent"], {"refinedSugar": 1})
	assert_eq(stock["refinedSugar"], 0)
	assert_eq(report["idle_counts"], [0, 1, 0, 0])
	assert_eq(report["idle_labour"], 4)
	assert_eq(report["strikers"], 1)

func test_starving_trained_workers_do_not_claim_luxury() -> void:
	var stock: Dictionary = {"grain": 0, "meat": 0, "cigars": 3}
	var report: Dictionary = EconomyConsumption.resolve(WorkerPool.make(0, 0, 1), stock, 0)
	assert_eq(report["fed_workers"], 0)
	assert_eq(report["luxury_spent"], {})
	assert_eq(stock["cigars"], 3)
	assert_eq(report["strikers"], 1)

func test_luxury_is_deducted_masters_first() -> void:
	var pool: WorkerPool = WorkerPool.make(0, 1, 1, 1)
	var stock: Dictionary = {"grain": 3, "meat": 3, "furHats": 1, "cigars": 1}
	var report: Dictionary = EconomyConsumption.resolve(pool, stock, 0)
	assert_eq(report["fed_workers"], 3)
	assert_eq(report["luxury_spent"], {"cigars": 1, "furHats": 1})
	assert_eq(report["idle_counts"], [0, 0, 1, 1])
	assert_eq(report["idle_labour"], 14)
	assert_eq(report["strikers"], 1)

func test_empty_pool_and_no_upkeep_is_a_clean_pass() -> void:
	var stock: Dictionary = {"grain": 0}
	var report: Dictionary = EconomyConsumption.resolve(WorkerPool.make(0), stock, 0)
	assert_eq(report["strikers"], 0)
	assert_eq(report["idle_labour"], 0)
	assert_eq(report["food_eaten"], 0)
	assert_eq(stock, {"grain": 0})

func test_turn_runs_all_four_phases_in_order() -> void:
	var economy: PlayerEconomy = _economy(2)
	economy.production.set_assignment("lumber", 1)
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
	economy.production.set_assignment("lumber", 3)
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
	economy.production.set_assignment("lumber", 1)
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
	economy.production.set_assignment("lumber", 2)
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

## The projection names the store Production will find, so the ledger can stop a
## row at what the phase can start (wiki: stockpiles-and-production § Production
## flow; issue #453).
func test_the_projection_names_the_post_consumption_store() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = _economy(2)
	economy.stockpile["grain"] = 3
	economy.stockpile["timber"] = 4
	var projection: Dictionary = EconomyTurn.project(economy, market, {"timber": 2}, 0)
	var store: Dictionary = projection["after_consumption"]
	# The harvest lands before Consumption, and two peasants eat a grain each.
	assert_eq(int(store.get("timber", 0)), 6)
	assert_eq(int(store.get("grain", 0)), 1)
	# The live store is untouched: the projection is a dry run.
	assert_eq(economy.quantity("timber"), 4)
	assert_eq(economy.quantity("grain"), 3)


func test_projection_has_no_side_effects() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = _economy(2)
	economy.production.set_assignment("lumber", 1)
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

func test_alloy_rows_take_two_turns() -> void:
	assert_eq(ProductionRecipes.turns("steel"), 2)
	assert_eq(ProductionRecipes.turns("bronze"), 2)
	assert_eq(ProductionRecipes.turns("lumber"), 1)
	assert_eq(ProductionRecipes.turns("unknown"), 1)


func test_a_two_turn_run_pays_now_and_lands_a_unit_a_phase() -> void:
	var stock: Dictionary = {"iron": 2, "coal": 2}
	var first: Dictionary = ProductionRecipes.plan(
		[{"recipe": "steel", "units": 2}], stock, 4, {}
	)
	assert_eq(first["runs"], {"steel": 2})
	assert_eq(first["produced"], {})
	assert_eq(first["completed"], {})
	assert_eq(first["consumed"], {"iron": 2, "coal": 2})
	assert_eq(first["labour_used"], 4)
	assert_eq(int(stock.get("steel", 0)), 0, "the steel is still on the anvil")
	assert_eq(ProductionRecipes.in_flight(first["wip"], "steel"), 2)
	var second: Dictionary = ProductionRecipes.plan([], stock, 0, {}, first["wip"])
	assert_eq(second["runs"], {})
	assert_eq(second["completed"], {"steel": 1}, "one unit leaves the workshop a phase")
	assert_eq(second["produced"], {"steel": 1})
	assert_eq(second["labour_used"], 0, "the batch paid its labour when it started")
	assert_eq(int(stock["steel"]), 1)
	assert_eq(ProductionRecipes.in_flight(second["wip"], "steel"), 1, "the rest still serves")
	var third: Dictionary = ProductionRecipes.plan([], stock, 0, {}, second["wip"])
	assert_eq(third["completed"], {"steel": 1})
	assert_eq(int(stock["steel"]), 2)
	assert_eq(third["wip"], {}, "the batch is spent")


## A batch of three started in one phase lands its last unit two phases after the
## first, and the drips cost the workshop nothing beyond what the start paid
## (wiki: production-recipes § Turns per unit; DR-20261113-02).
func test_a_batch_lands_one_unit_a_phase_until_it_is_spent() -> void:
	var stock: Dictionary = {"iron": 3, "coal": 3}
	var landed_at: Array[int] = []
	var wip: Dictionary = ProductionRecipes.plan(
		[{"recipe": "steel", "units": 3}], stock, 6, {}
	)["wip"]
	assert_eq(ProductionRecipes.in_flight(wip, "steel"), 3)
	for _phase in 4:
		var report: Dictionary = ProductionRecipes.plan([], stock, 0, {}, wip)
		wip = report["wip"]
		landed_at.append(int(report["completed"].get("steel", 0)))
		assert_eq(report["consumed"], {}, "a carried batch costs the phase nothing")
		assert_eq(int(stock["iron"]), 0, "no input is paid twice for a carried batch")
	assert_eq(landed_at, [1, 1, 1, 0], "one unit a phase, then nothing")
	assert_eq(int(stock["steel"]), 3)


## What leaves the workshop next phase: one unit per batch serving its last turn,
## so a row left set across phases lands as many as it has batches (wiki:
## production-recipes § Turns per unit; DR-20261113-02).
func test_the_workshop_reads_how_many_units_land_next_phase() -> void:
	var one: Dictionary = {"steel": [{"units": 3, "turns_left": 1}]}
	assert_eq(ProductionRecipes.next_landing(one, "steel"), 1, "one batch, one unit")
	var two: Dictionary = {
		"steel": [{"units": 2, "turns_left": 1}, {"units": 3, "turns_left": 1}],
	}
	assert_eq(
		ProductionRecipes.next_landing(two, "steel"), 2,
		"a court that leaves the row set starts a batch a phase, and each gives up a unit"
	)
	assert_eq(ProductionRecipes.in_flight(two, "steel"), 5, "the anvil still holds every unit")
	assert_eq(
		ProductionRecipes.next_landing({"steel": [{"units": 4, "turns_left": 2}]}, "steel"),
		0, "a batch still serving its first turn lands nothing yet"
	)
	assert_eq(ProductionRecipes.next_landing({}, "steel"), 0, "an idle workshop lands nothing")
	assert_eq(
		ProductionRecipes.next_landing({"lumber": [{"units": 3, "turns_left": 1}]}, "lumber"),
		3, "a carried one-turn batch lands whole, as before"
	)


## The wait is the soonest batch: a later batch cannot push the tag past a unit
## that is already one phase from the store (wiki: production-recipes § Turns per
## unit; DR-20261113-02).
func test_the_workshop_wait_reads_the_soonest_batch() -> void:
	assert_eq(
		ProductionRecipes.turns_left(
			{"steel": [{"units": 2, "turns_left": 1}, {"units": 3, "turns_left": 1}]}, "steel"
		),
		1
	)
	assert_eq(
		ProductionRecipes.turns_left(
			{"steel": [{"units": 1, "turns_left": 2}, {"units": 2, "turns_left": 1}]}, "steel"
		),
		1,
		"the soonest batch says when the next unit lands"
	)
	assert_eq(
		ProductionRecipes.turns_left({"steel": [{"units": 4, "turns_left": 2}]}, "steel"), 2
	)
	assert_eq(ProductionRecipes.turns_left({}, "steel"), 0)


## Drip-feeding three steel one unit a phase builds the same output from the same
## inputs as one batch of three, so a batch buys no front-loading.
func test_a_batch_matches_drip_feeding() -> void:
	var batch_stock: Dictionary = {"iron": 3, "coal": 3}
	var drip_stock: Dictionary = {"iron": 3, "coal": 3}
	var batch_wip: Dictionary = ProductionRecipes.plan(
		[{"recipe": "steel", "units": 3}], batch_stock, 6, {}
	)["wip"]
	var drip_wip: Dictionary = {}
	for phase in 4:
		batch_wip = ProductionRecipes.plan([], batch_stock, 0, {}, batch_wip)["wip"]
		var drip: Array[Dictionary] = []
		if phase < 3:
			drip.append({"recipe": "steel", "units": 1})
		drip_wip = ProductionRecipes.plan(drip, drip_stock, 2, {}, drip_wip)["wip"]
	assert_eq(int(batch_stock["steel"]), int(drip_stock["steel"]), "same steel by turn four")
	assert_eq(int(batch_stock.get("iron", 0)), int(drip_stock.get("iron", 0)))
	assert_eq(int(batch_stock.get("coal", 0)), int(drip_stock.get("coal", 0)))


func test_the_workshop_carries_across_turns() -> void:
	var economy: PlayerEconomy = _economy(4)
	economy.stockpile = {"grain": 20, "iron": 2, "coal": 2}
	economy.production.set_assignment("steel", 2)
	var market: WorldMarket = WorldMarket.with_default_prices()
	var first: Dictionary = EconomyTurn.resolve(economy, market, {}, 0)
	assert_eq(first["production"]["runs"], {"steel": 2})
	assert_eq(economy.quantity("steel"), 0)
	assert_eq(economy.production.wip_units("steel"), 2)
	assert_eq(economy.production.wip_turns("steel"), 1)
	var second: Dictionary = EconomyTurn.resolve(economy, market, {}, 0)
	assert_eq(second["production"]["completed"], {"steel": 1}, "one unit a phase")
	assert_eq(second["production"]["runs"], {})
	assert_eq(economy.quantity("steel"), 1)
	assert_eq(economy.production.wip_units("steel"), 1)
	var third: Dictionary = EconomyTurn.resolve(economy, market, {}, 0)
	assert_eq(third["production"]["completed"], {"steel": 1})
	assert_eq(economy.quantity("steel"), 2)
	assert_eq(economy.production.wip_units("steel"), 0)


func test_projection_counts_the_next_unit_landing() -> void:
	var economy: PlayerEconomy = _economy(4)
	economy.stockpile = {"grain": 20, "iron": 2, "coal": 2}
	economy.production.set_assignment("steel", 2)
	var market: WorldMarket = WorldMarket.with_default_prices()
	EconomyTurn.resolve(economy, market, {}, 0)
	var projection: Dictionary = EconomyTurn.project(economy, market, {}, 0)
	assert_eq(int(projection["stockpile_delta"].get("steel", 0)), 1, "one unit lands a phase")
	assert_eq(economy.quantity("steel"), 0, "a projection never lands the batch early")


func test_the_workshop_rides_the_snapshot() -> void:
	var economy: PlayerEconomy = _economy(4)
	economy.stockpile = {"grain": 20, "iron": 2, "coal": 2}
	economy.production.set_assignment("steel", 2)
	EconomyTurn.resolve(economy, WorldMarket.with_default_prices(), {}, 0)
	var restored: PlayerEconomy = PlayerEconomy.starting()
	restored.apply_snapshot(economy.snapshot())
	assert_eq(restored.production.wip_units("steel"), 2)
	assert_eq(restored.production.wip_turns("steel"), 1)
	restored.apply_snapshot({"production_wip": {"silk_gown": [{"units": 3, "turns_left": 1}]}})
	assert_eq(restored.production.wip_total(), 0, "a recipe the catalogue dropped is not trusted")


## A damaged workshop drops on load — a row that is not a list, an entry that is
## not a batch, a batch with no units or no turns left — and the phase reading
## one lands nothing instead of failing on the cast (wiki: production-recipes
## § Acceptance Criteria; DR-20261112-11).
func test_a_damaged_workshop_is_dropped_not_trusted() -> void:
	var economy: PlayerEconomy = _economy(4)
	economy.apply_snapshot({
		"production_wip": {
			"steel": {"units": 2, "turns_left": 1},
			"bronze": ["two", {"units": 0, "turns_left": 1}, {"units": 2, "turns_left": 0}],
			"lumber": [{"units": 2, "turns_left": 1}],
		},
	})
	assert_eq(economy.production.wip_total(), 2, "only a list of whole batches is trusted")
	assert_eq(economy.production.wip_units("lumber"), 2)
	assert_eq(economy.production.wip_units("steel"), 0, "a row that is not a list holds nothing")
	assert_eq(economy.production.wip_turns("steel"), 0)
	var planned: Dictionary = ProductionRecipes.plan(
		[], {}, 0, {}, {"steel": {"units": 2, "turns_left": 1}}
	)
	assert_eq(planned["produced"], {}, "the phase reads a damaged row as an empty workshop")
	assert_eq(planned["wip"], {})
	economy.stockpile = {"grain": 20}
	var report: Dictionary = EconomyTurn.resolve(
		economy, WorldMarket.with_default_prices(), {}, 0
	)
	assert_eq(report["production"]["produced"], {"lumber": 2}, "the whole batch still lands")
	assert_eq(economy.production.wip_total(), 0)


func _economy(peasants: int) -> PlayerEconomy:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.workers = WorkerPool.make(peasants)
	economy.stockpile = {"grain": 0, "wool": 2}
	economy.treasury = 1000
	return economy


func test_effective_yield_takes_the_minimum() -> void:
	assert_eq(Extraction.effective_yield(4, 4, 4, 4), 4)
	assert_eq(Extraction.effective_yield(4, 1, 4, 4), 1)
	assert_eq(Extraction.effective_yield(2, 4, 1, 4), 1)
	assert_eq(Extraction.effective_yield(3, 4, 4, 2), 2)
	assert_eq(Extraction.effective_yield(0, 4, 4, 4), 0)
	assert_eq(Extraction.effective_yield(9, 4, 4, 4), 4)
	assert_eq(Extraction.effective_yield(-3, 4, 4, 4), 0)

func test_tech_cap_defaults_to_one() -> void:
	assert_eq(Extraction.tech_cap_for("timber", {}), 1)
	assert_eq(Extraction.tech_cap_for("timber", {"timber": 3}), 3)
	assert_eq(Extraction.tech_cap_for("timber", {"timber": -1}), 0)

func test_map_resources_map_to_catalog_commodities() -> void:
	assert_eq(Extraction.commodity_for_resource(0), "timber")
	assert_eq(Extraction.commodity_for_resource(3), "gold")
	assert_eq(Extraction.commodity_for_resource(4), "grain")
	assert_eq(Extraction.commodity_for_resource(MapModel.NO_ID), "")

func test_seeded_map_resources_are_real_commodities() -> void:
	var table: Array[Dictionary] = MapGenerator.resource_table()
	for entry: Dictionary in table:
		assert_true(
			CommodityCatalog.known(String(entry["commodity"])), String(entry["commodity"])
		)

func test_yields_sum_owned_resource_tiles_and_the_capital_bonus() -> void:
	var model: MapModel = _fixture()
	var totals: Dictionary = Extraction.yields(model, 0, 0)
	assert_eq(totals, {"timber": 1, "grain": 1 + Extraction.CAPITAL_GRAIN_BONUS})

func test_yields_ignore_tiles_owned_by_others() -> void:
	var model: MapModel = _fixture()
	var totals: Dictionary = Extraction.yields(model, 1, 1)
	assert_eq(totals, {"grain": 1 + Extraction.CAPITAL_GRAIN_BONUS})
	var none: Dictionary = Extraction.yields(model, 2, -1)
	assert_eq(none, {})

func test_capital_bonus_needs_an_owned_capital() -> void:
	var model: MapModel = _fixture()
	var foreign: Dictionary = Extraction.yields(model, 0, 1)
	assert_eq(int(foreign.get("grain", 0)), 1)
	assert_eq(Extraction.yields(null, 0, 0), {})

func test_improved_tiles_use_the_works_level_and_connectivity() -> void:
	var model: MapModel = _fixture()
	var works := LandWorks.new()
	works.set_improvement(model, Vector2i(0, 0), 1)
	var totals: Dictionary = Extraction.yields(model, 0, 0, {}, works, Vector2i(0, 0))
	assert_eq(totals, {"timber": 1, "grain": Extraction.CAPITAL_GRAIN_BONUS})
	# The unimproved grain tile on (1, 0) no longer pays the placeholder level 1.
	var no_works: Dictionary = Extraction.yields(model, 0, 0)
	assert_eq(no_works, {"timber": 1, "grain": 1 + Extraction.CAPITAL_GRAIN_BONUS})

func test_disconnected_improvements_are_skipped() -> void:
	var model: MapModel = _fixture()
	var works := LandWorks.new()
	works.set_improvement(model, Vector2i(0, 0), 1)
	var totals: Dictionary = Extraction.yields(
		model, 0, -1, {}, works, Vector2i(-1, -1)
	)
	assert_eq(totals, {})

func test_works_respect_prospecting_and_extraction_caps() -> void:
	var model: MapModel = _fixture()
	var works := LandWorks.new()
	works.set_improvement(model, Vector2i(0, 0), 2)
	works.set_transport(model, Vector2i(0, 0), LandWorks.TRANSPORT_RAIL)
	var base: Dictionary = Extraction.yields(
		model, 0, -1, {}, works, Vector2i(0, 0)
	)
	assert_eq(base, {"timber": 1})
	var capped: Dictionary = Extraction.yields(
		model, 0, -1, {"timber": 4}, works, Vector2i(0, 0)
	)
	assert_eq(capped, {"timber": 2})

	model.resource[model.index_of(0, 0)] = 1
	works.set_improvement(model, Vector2i(0, 0), 1)
	var unprospected: Dictionary = Extraction.yields(
		model, 0, -1, {}, works, Vector2i(0, 0)
	)
	assert_eq(unprospected, {})
	works.set_prospected(0, model, Vector2i(0, 0))
	var prospected: Dictionary = Extraction.yields(
		model, 0, -1, {}, works, Vector2i(0, 0)
	)
	assert_eq(prospected, {"iron": 1})

## A coast held by a hostile squadron pays the crown nothing, and the controller
## prices the loss from its own fleet stations (wiki:
## capital-and-connectivity § Blockade; REQ-P2-03).
func test_the_ledger_prices_a_blockaded_coast() -> void:
	var model := MapModel.new()
	model.setup(4, 2)
	var home: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var coast: Array[Vector2i] = [Vector2i(2, 0), Vector2i(3, 0)]
	for tile: Vector2i in home + coast:
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.PLAINS
	model.province[model.index_of(0, 0)] = 0
	model.province[model.index_of(1, 0)] = 0
	model.province[model.index_of(2, 0)] = 1
	model.province[model.index_of(3, 0)] = 1
	var capital := ProvinceState.create(0, "Sevilla", home, Vector2(0.5, 0.0), 2, 0)
	capital.capital_tile = Vector2i(0, 0)
	capital.town_tile = Vector2i(0, 0)
	var harbour := ProvinceState.create(1, "Costa", coast, Vector2(2.5, 0.0), 2, 0)
	harbour.town_tile = Vector2i(3, 0)
	harbour.town_development = 0
	model.provinces = [capital, harbour]
	model.resource[model.index_of(2, 0)] = 4
	var works := LandWorks.new()
	works.add_port(model, Vector2i(3, 0))
	works.set_improvement(model, Vector2i(2, 0), 4)
	var controller := EconomyController.new()
	controller.model = model
	controller.player_faction = 0
	controller.capital_province = 0
	controller.capital_tile = Vector2i(0, 0)
	controller.works = works
	controller.economy = PlayerEconomy.starting()
	assert_false(Blockades.of(controller.blockade_source).any(), "no stations to read yet")
	assert_eq(
		int(controller.extraction().get("grain", 0)),
		1 + Extraction.CAPITAL_GRAIN_BONUS,
		"the harbour carries the estate's grain home"
	)
	var seals := Blockades.new()
	seals.sealed = {model.region_id: {1: true}}
	controller.blockade_source = func() -> Blockades: return seals
	assert_eq(
		int(controller.extraction().get("grain", 0)),
		Extraction.CAPITAL_GRAIN_BONUS,
		"the blockaded harbour carries nothing"
	)
	controller.free()


func test_tech_caps_lift_the_yield_per_tile() -> void:
	var model: MapModel = MapModel.new()
	model.setup(3, 1)
	model.province[model.index_of(0, 0)] = 0
	model.province[model.index_of(1, 0)] = 0
	var tiles_a: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var province_a := ProvinceState.create(0, "P0", tiles_a, Vector2.ZERO, 2, 0)
	province_a.town_development = 4
	model.provinces.append(province_a)
	model.resource[model.index_of(0, 0)] = 0
	model.resource[model.index_of(1, 0)] = 0
	var base: Dictionary = Extraction.yields(model, 0, -1)
	assert_eq(base, {"timber": 2})
	var capped: Dictionary = Extraction.yields(model, 0, -1, {"timber": 3})
	# Improvement level, not the tech cap, now limits the tiles in this slice.
	assert_eq(capped, {"timber": 2})

## Scrub forest timber is hard-capped at level 1; hardwood follows the tech cap.
func test_terrain_hard_cap_clamps_scrub_timber() -> void:
	var model: MapModel = _fixture()
	var works := LandWorks.new()
	var tile := Vector2i(0, 0)
	var index: int = model.index_of(tile.x, tile.y)
	model.terrain[index] = MapModel.Terrain.SCRUB_FOREST
	works.set_improvement(model, tile, LandWorks.MAX_IMPROVEMENT)
	works.set_transport(model, tile, LandWorks.TRANSPORT_RAIL)
	var scrub: Dictionary = Extraction.yields(
		model, 0, 0, {"timber": 4}, works, tile
	)
	assert_eq(int(scrub.get("timber", 0)), 1)
	model.terrain[index] = MapModel.Terrain.HARDWOOD_FOREST
	var hardwood: Dictionary = Extraction.yields(
		model, 0, 0, {"timber": 4}, works, tile
	)
	assert_eq(int(hardwood.get("timber", 0)), 4)

## The path transport cap is the bottleneck of the chosen route, and the best of
## several routes wins (wiki: capital-and-connectivity).
func test_path_transport_uses_the_best_bottleneck() -> void:
	var model := MapModel.new()
	model.setup(3, 3)
	for y in 3:
		for x in 3:
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			model.province[model.index_of(x, y)] = 0
	var tiles: Array[Vector2i] = []
	for y in 3:
		for x in 3:
			tiles.append(Vector2i(x, y))
	var province := ProvinceState.create(0, "P0", tiles, Vector2(1, 1), 9, 0, true)
	province.capital_tile = Vector2i(0, 0)
	province.town_development = 4
	model.provinces = [province]
	model.resource[model.index_of(0, 2)] = 0
	var works := LandWorks.new()
	works.set_improvement(model, Vector2i(0, 2), 2)
	works.set_transport(model, Vector2i(0, 1), LandWorks.TRANSPORT_ROAD)
	works.set_transport(model, Vector2i(0, 2), LandWorks.TRANSPORT_RAIL)
	var bottleneck: Dictionary = Extraction.yields(
		model, 0, 0, {"timber": 4}, works, Vector2i(0, 0)
	)
	assert_eq(int(bottleneck.get("timber", 0)), 1)
	# A second route along row 1 is rail all the way: max(min(paths)) = 4.
	for x in 3:
		works.set_transport(model, Vector2i(x, 1), LandWorks.TRANSPORT_RAIL)
	var best: Dictionary = Extraction.yields(
		model, 0, 0, {"timber": 4}, works, Vector2i(0, 0)
	)
	assert_eq(int(best.get("timber", 0)), 2)

## Town manufacturing bonus: level 2 -> x1, level 4 -> x2, level 3 -> none,
## never consuming the raw input (wiki: extraction-and-improvements).
func test_town_industry_multiplies_town_connected_raw() -> void:
	assert_eq(TownIndustry.bonus_for_province({"iron": 4}, 2, {}), {"castIron": 1})
	assert_eq(TownIndustry.bonus_for_province({"iron": 8}, 4, {}), {"castIron": 4})
	assert_eq(TownIndustry.bonus_for_province({"iron": 8}, 3, {}), {})
	assert_eq(TownIndustry.bonus_for_province({"iron": 3}, 4, {}), {})
	assert_eq(TownIndustry.bonus_for_province({"cotton": 4}, 2, {}), {})
	assert_eq(
		TownIndustry.bonus_for_province({"cotton": 4}, 2, {"cotton_weaving": true}),
		{"fabric": 1}
	)

## A court weighs a town upgrade by the manufactures the finished town would pay
## each turn, at base prices (wiki: extraction-and-improvements
## § Town manufacturing bonus; commodity-catalog § Manufactured base prices).
func test_town_industry_prices_the_finish_at_level_four() -> void:
	assert_eq(TownIndustry.value({"lumber": 2}), 120)
	assert_eq(TownIndustry.value({}), 0)
	assert_eq(TownIndustry.marginal_gain({"iron": 8}, 1), 4 * 160)
	assert_eq(TownIndustry.marginal_gain({"iron": 8}, 2), 2 * 160)
	assert_eq(TownIndustry.marginal_gain({"iron": 8}, 3), 4 * 160)
	assert_eq(TownIndustry.marginal_gain({"iron": 8}, 4), 0)
	assert_eq(TownIndustry.marginal_gain({}, 1), 0, "no raw, no bonus")

## Extraction credits the bonus from a town-adjacent raw tile without spending it.
func test_extraction_adds_the_town_manufacturing_bonus() -> void:
	var model: MapModel = _fixture()
	var works := LandWorks.new()
	var province: ProvinceState = model.provinces[0]
	province.town_tile = Vector2i(0, 0)
	province.town_development = 2
	model.resource[model.index_of(1, 0)] = 0
	works.set_improvement(model, Vector2i(0, 0), 0)
	works.set_improvement(model, Vector2i(1, 0), 2)
	var totals: Dictionary = Extraction.yields(
		model, 0, 0, {"timber": 4}, works, Vector2i(0, 0)
	)
	assert_eq(int(totals.get("timber", 0)), 2)
	assert_eq(int(totals.get("lumber", 0)), 0)
	works.set_improvement(model, Vector2i(1, 0), 4)
	var raised: Dictionary = Extraction.yields(
		model, 0, 0, {"timber": 4}, works, Vector2i(0, 0)
	)
	assert_eq(int(raised.get("timber", 0)), 4)
	assert_eq(int(raised.get("lumber", 0)), 1)

func test_treasury_ids_are_the_riches_set() -> void:
	assert_eq(
		CommodityCatalog.treasury_ids(),
		["gold", "silver", "gems", "diamonds", "spices"] as Array[String]
	)

func _fixture() -> MapModel:
	var model: MapModel = MapModel.new()
	model.setup(3, 2)
	for x in 2:
		model.province[model.index_of(x, 0)] = 0
	model.province[model.index_of(2, 0)] = 1
	model.province[model.index_of(0, 1)] = 1
	var tiles0: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var tiles1: Array[Vector2i] = [Vector2i(2, 0), Vector2i(0, 1)]
	var p0 := ProvinceState.create(0, "P0", tiles0, Vector2.ZERO, 2, 0)
	p0.town_development = 4
	var p1 := ProvinceState.create(1, "P1", tiles1, Vector2.ZERO, 2, 1)
	model.provinces.append(p0)
	model.provinces.append(p1)
	model.resource[model.index_of(0, 0)] = 0
	model.resource[model.index_of(1, 0)] = 4
	model.resource[model.index_of(2, 0)] = 4
	return model

func test_market_seeds_tradeable_catalog_prices() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	assert_eq(market.prices.size(), 22)
	assert_eq(market.price("timber"), 30)
	assert_eq(market.price("lumber"), 60)
	assert_eq(market.price("iron"), 80)
	assert_false(market.prices.has("gold"))
	# Spices is a rich: excluded from the book (Imperialism II; DR-20261113-13).
	assert_false(market.prices.has("spices"))
	assert_false(market.can_trade("gold"))
	assert_true(market.can_trade("lumber"))
	assert_false(market.can_trade("spices"))

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
	economy.stockpile["spices"] = 2
	var crop: Dictionary = market.sell(economy, "spices", 1)
	assert_false(bool(crop["ok"]), "spices never trade (Imperialism II)")
	assert_eq(String(crop["reason"]), "Not traded on the world market")
	assert_eq(economy.quantity("spices"), 2)

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

## A two-province region: Spain ashore, one Minor Nation (or Tribe) holding the
## other with a grain field and a timber estate.
func _offer_world(owner: int = 6) -> WorldMap:
	var model: MapModel = _fixture()
	model.provinces[1].owner = owner
	model.resource[model.index_of(0, 1)] = 0
	var world := WorldMap.new()
	world.add_region(model)
	return world

func test_minor_offers_publish_their_estates_at_the_world_price() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var offers: Array[Dictionary] = MinorMarket.emit(_offer_world(), market, 0)
	assert_eq(offers.size(), 2, "one row per commodity the estates yield")
	var timber: Dictionary = offers[MinorMarket.index_of(offers, "6:timber")]
	assert_eq(int(timber["faction"]), 6)
	assert_eq(String(timber["commodity"]), "timber")
	assert_eq(int(timber["quantity"]), 1)
	assert_eq(int(timber["unit_price"]), 30, "deals clear at the published price")
	assert_eq(MinorMarket.unit_price(market, "timber"), 30)
	assert_eq(MinorMarket.remaining(offers, "6:timber"), 1)
	assert_eq(MinorMarket.index_of(offers, "6:gold"), -1)

func test_tribes_offer_their_harvest_too() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var offers: Array[Dictionary] = MinorMarket.emit(_offer_world(9), market, 0)
	assert_eq(offers.size(), 2)
	assert_true(MinorMarket.index_of(offers, "9:timber") >= 0)

func test_offers_skip_riches() -> void:
	var world: WorldMap = _offer_world()
	var market: WorldMarket = WorldMarket.with_default_prices()
	var offers: Array[Dictionary] = MinorMarket.emit(world, market, 0)
	for offer: Dictionary in offers:
		assert_true(CommodityCatalog.is_tradeable(String(offer["commodity"])))
	# A gold seam is a rich, not a market good.
	world.region(0).resource[world.region(0).index_of(0, 1)] = 3
	var after: Array[Dictionary] = MinorMarket.emit(world, market, 0)
	assert_eq(after.size(), 1, "the grain estate still sells")
	assert_eq(String(after[0]["commodity"]), Extraction.GRAIN)
	assert_eq(MinorMarket.index_of(after, "6:gold"), -1)

func test_offers_belong_to_one_global_market() -> void:
	var world: WorldMap = _offer_world()
	var market: WorldMarket = WorldMarket.with_default_prices()
	assert_eq(world.owned_provinces(0, 5), 0)
	assert_eq(MinorMarket.emit(world, market, 5).size(), 2, "the book is global")
	assert_eq(MinorMarket.emit(null, market, 0), [])
	assert_eq(MinorMarket.emit(world, null, 0), [])

func test_buying_a_minor_offer_pays_the_court_and_fills_a_hold() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var offers: Array[Dictionary] = MinorMarket.emit(_offer_world(), market, 0)
	var result: Dictionary = MinorMarket.buy(
		market, economy, offers, "6:timber", 1, 5
	)
	assert_true(bool(result["ok"]), String(result.get("reason", "")))
	assert_eq(int(result["cost"]), 30)
	assert_eq(int(result["faction"]), 6)
	assert_eq(economy.treasury, PlayerEconomy.START_TREASURY - 30)
	assert_eq(economy.quantity("timber"), 1)
	assert_eq(market.bought_units_for(0), 1)
	assert_eq(market.bid_volume("timber"), 1)
	# The timber row is spent; the grain estate still has goods.
	assert_eq(offers.size(), 1)
	assert_false(bool(MinorMarket.buy(market, economy, offers, "6:timber", 1, 5)["ok"]))

func test_a_minor_offer_needs_a_free_cargo_hold() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var offers: Array[Dictionary] = MinorMarket.emit(_offer_world(), market, 0)
	var result: Dictionary = MinorMarket.buy(market, economy, offers, "6:timber", 1, 0)
	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("cargo holds"))
	assert_eq(economy.treasury, PlayerEconomy.START_TREASURY)
	assert_eq(economy.quantity("timber"), 0)
	assert_eq(MinorMarket.remaining(offers, "6:timber"), 1)

func test_a_minor_offer_cannot_be_overbought_or_bought_without_treasury() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var offers: Array[Dictionary] = MinorMarket.emit(_offer_world(), market, 0)
	var greedy: Dictionary = MinorMarket.buy(market, economy, offers, "6:timber", 2, 5)
	assert_false(bool(greedy["ok"]))
	assert_true(String(greedy["reason"]).contains("Only 1"))
	assert_eq(economy.treasury, PlayerEconomy.START_TREASURY)
	economy.treasury = 5
	var poor: Dictionary = MinorMarket.buy(market, economy, offers, "6:timber", 1, 5)
	assert_false(bool(poor["ok"]))
	assert_eq(String(poor["reason"]), "Insufficient treasury")
	assert_eq(MinorMarket.remaining(offers, "6:timber"), 1)
	assert_false(bool(MinorMarket.buy(market, economy, offers, "6:timber", 0, 5)["ok"]))

func test_offers_expire_with_the_turn_but_survive_a_save() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	market.minor_offers = MinorMarket.emit(_offer_world(), market, 0)
	var clone: WorldMarket = market.copy()
	assert_eq(clone.minor_offers, market.minor_offers)
	var restored: WorldMarket = WorldMarket.from_dict(market.to_dict())
	assert_eq(restored.minor_offers, market.minor_offers)
	assert_eq(int(restored.minor_offers[0]["unit_price"]), 50)
	market.advance_prices()
	assert_eq(market.minor_offers, [])

## A two-province map: a Great Power holds the west, Minor Nation 6 (or a Tribe)
## holds four estates in the east with one province town.
func _town_world(owner: int, resource: int, estates: int, town_level: int) -> WorldMap:
	var model := MapModel.new()
	model.setup(4, 2)
	for y in 2:
		for x in 4:
			model.province[model.index_of(x, y)] = 0 if x < 2 else 1
	var gp_tiles: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)
	]
	var minor_tiles: Array[Vector2i] = [
		Vector2i(2, 0), Vector2i(3, 0), Vector2i(2, 1), Vector2i(3, 1)
	]
	var gp := ProvinceState.create(0, "P0", gp_tiles, Vector2.ZERO, 4, 0)
	var minor := ProvinceState.create(1, "P1", minor_tiles, Vector2.ZERO, 4, owner)
	minor.town_tile = Vector2i(2, 0)
	minor.town_development = town_level
	model.provinces = [gp, minor]
	for tile: Vector2i in minor_tiles.slice(0, estates):
		model.resource[model.index_of(tile.x, tile.y)] = resource
	var world := WorldMap.new()
	world.add_region(model)
	return world

func _auto_offer(orders: Array[MarketOrder], commodity: String) -> MarketOrder:
	for order: MarketOrder in orders:
		if order.commodity == commodity:
			return order
	return null

## Units one commodity carries across every auto-offer in the book.
func _offered_units(orders: Array[MarketOrder], commodity: String) -> int:
	var total: int = 0
	for order: MarketOrder in orders:
		if order.commodity == commodity:
			total += order.remaining()
	return total

func test_a_level_two_minor_town_offers_one_manufacture() -> void:
	var world: WorldMap = _town_world(6, 0, 4, 2)
	var orders: Array[MarketOrder] = MinorMarket.emit_orders(world)
	var lumber: MarketOrder = _auto_offer(orders, "lumber")
	assert_not_null(lumber, "four timber estates feed a level-2 town")
	assert_eq(lumber.faction, 6)
	assert_eq(lumber.quantity, 1)
	assert_eq(lumber.priority, 1)
	assert_true(lumber.auto)
	assert_eq(
		lumber.origin_index, world.region(0).index_of(2, 0), "the province town is the source"
	)
	var market: WorldMarket = WorldMarket.with_default_prices()
	var offers: Array[Dictionary] = MinorMarket.emit(world, market, 0)
	assert_eq(int(offers[MinorMarket.index_of(offers, "6:lumber")]["quantity"]), 1)
	assert_eq(
		int(offers[MinorMarket.index_of(offers, "6:timber")]["quantity"]), 4,
		"the bonus spends none of the timber"
	)

func test_a_level_four_minor_town_doubles_the_bonus() -> void:
	var orders: Array[MarketOrder] = MinorMarket.emit_orders(_town_world(6, 0, 4, 4))
	assert_eq(_auto_offer(orders, "lumber").quantity, 2)

func test_odd_and_plain_town_levels_pay_nothing() -> void:
	for level: int in [1, 3]:
		var orders: Array[MarketOrder] = MinorMarket.emit_orders(_town_world(6, 0, 4, level))
		assert_null(_auto_offer(orders, "lumber"), "level %d pays no bonus" % level)
		assert_eq(_offered_units(orders, "timber"), 4, "the harvest still sells")

func test_a_town_needs_four_estates_to_manufacture() -> void:
	var orders: Array[MarketOrder] = MinorMarket.emit_orders(_town_world(6, 0, 3, 4))
	assert_null(_auto_offer(orders, "lumber"))
	assert_eq(_offered_units(orders, "timber"), 3)

func test_a_tribe_town_offers_its_manufactures_too() -> void:
	var world: WorldMap = _town_world(9, 5, 4, 2)
	var fabric: MarketOrder = _auto_offer(MinorMarket.emit_orders(world), "fabric")
	assert_not_null(fabric, "four wool estates feed a Tribe town")
	assert_eq(fabric.faction, 9)
	assert_eq(fabric.quantity, 1)

## Minors and Tribes never prospect, so a mineral estate is neither sold nor fed
## to the town (wiki: extraction-and-improvements § Non-Great-Power extraction).
func test_mineral_estates_never_feed_a_minor_town() -> void:
	var world: WorldMap = _town_world(6, 1, 4, 4)
	var orders: Array[MarketOrder] = MinorMarket.emit_orders(world)
	assert_eq(orders.size(), 0, "no iron in the ground, no cast iron on the market")
	var model: MapModel = world.region(0)
	assert_eq(MinorMarket.province_raw(model, model.provinces[1]), {})

## The offers are ordinary system-authored supply: a crown bids, the matcher
## fills it, and the Minor's receipt leaves the Great-Power pool as a sink.
func test_a_minor_town_offer_clears_in_the_auction() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _town_world(6, 0, 4, 2)
	var buyer: PlayerEconomy = PlayerEconomy.starting()
	var before: int = buyer.treasury
	var stock_before: int = buyer.quantity("lumber")
	MarketOrders.submit(
		market,
		0, "lumber", MarketOrder.SIDE_BID, 1,
		{"cargo_free": 4, "treasury": before}
	)
	var report: Dictionary = MarketClearing.clear(market, world, {0: buyer}, {0: 4})
	var mine: Array[Dictionary] = []
	for raw: Variant in report["deals"]:
		if int((raw as Dictionary).get("buyer", -2)) == 0:
			mine.append(raw as Dictionary)
	assert_eq(mine.size(), 1)
	assert_eq(int(mine[0]["seller"]), 6)
	assert_eq(String(mine[0]["commodity"]), "lumber")
	assert_eq(buyer.quantity("lumber"), stock_before + 1)
	assert_eq(buyer.treasury, before - 60, "one lumber at the published price")

# --- test_economy_overseas ---

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

## A colony of one town tile and two rail-linked timber estates, the estates
## already fully improved so the province's whole harvest is 8 timber.
func _plantation(level: int) -> MapModel:
	var model := MapModel.new()
	model.setup(3, 1)
	var tiles: Array[Vector2i] = []
	for x in 3:
		var tile := Vector2i(x, 0)
		model.terrain[model.index_of(x, 0)] = MapModel.Terrain.PLAINS
		model.province[model.index_of(x, 0)] = 0
		tiles.append(tile)
	var province := ProvinceState.create(0, "Plantation", tiles, Vector2.ZERO, 3, 0)
	province.town_tile = Vector2i(0, 0)
	province.town_development = level
	model.provinces.append(province)
	for x: int in [1, 2]:
		model.resource[model.index_of(x, 0)] = 0
	return model

func _plantation_works(model: MapModel) -> LandWorks:
	var works := LandWorks.new()
	works.add_port(model, Vector2i(0, 0))
	for x: int in [1, 2]:
		works.set_improvement(model, Vector2i(x, 0), LandWorks.MAX_IMPROVEMENT)
		works.set_transport(model, Vector2i(x, 0), LandWorks.TRANSPORT_RAIL)
	return works

## One home region empty of the crown's land plus one plantation region.
func _plantation_world(levels: Array) -> WorldMap:
	var world := WorldMap.new()
	world.add_region(_region(4))
	for level: int in levels:
		var model: MapModel = _plantation(level)
		world.add_region(model)
	return world

func _plantation_works_table(world: WorldMap) -> MapRegionTable:
	var table := MapRegionTable.new()
	for index in range(1, world.region_count()):
		table.set_region(index, _plantation_works(world.region(index)))
	return table

## Raw crosses and manufactures are earned on the far shore: no lumber leaves a
## colonial town before its input has landed (wiki: extraction-and-improvements
## § Town manufacturing bonus).
func test_overseas_totals_ship_raw_and_leave_the_bonus_to_delivery() -> void:
	var world: WorldMap = _plantation_world([4])
	var by_region: Dictionary = EconomyOverseas.region_totals(
		world, WorldMap.OLD_WORLD, 0, {"timber": 4}, _plantation_works_table(world)
	)

	assert_eq(by_region.get(1, {}), {"timber": 8}, "raw only — no lumber yet")

func test_landed_raw_pays_the_colonial_town_bonus() -> void:
	var world: WorldMap = _plantation_world([4])
	var plan: Dictionary = EconomyOverseas.delivered(
		{"grain": 3}, world, WorldMap.OLD_WORLD, 0, {"timber": 4},
		_plantation_works_table(world), 8
	)

	assert_eq(plan["shipped"], {"timber": 8})
	assert_eq(
		plan["manufactured"], {"lumber": 4, "paper": 4}, "level 4: floor(8 / 4) x 2"
	)
	assert_eq(plan["extraction"], {"grain": 3, "timber": 8, "lumber": 4, "paper": 4})
	assert_eq(int(plan["used"]), 8, "bonus output never spends a hold")
	assert_eq(plan["by_province"].get(1, {}).get(0, {}), {"timber": 8})

## Short holds leave tonnage on the far shore, and undelivered raw feeds no
## bonus recipe — four timber make one lumber, three make none.
func test_undelivered_tons_pay_no_colonial_bonus() -> void:
	var world: WorldMap = _plantation_world([4])
	var plan: Dictionary = EconomyOverseas.delivered(
		{}, world, WorldMap.OLD_WORLD, 0, {"timber": 4},
		_plantation_works_table(world), 3
	)

	assert_eq(plan["shipped"], {"timber": 3})
	assert_eq(plan["manufactured"], {})
	assert_eq(plan["extraction"], {"timber": 3})
	assert_eq(int(plan["left_total"]), 5, "the rest stays abroad")

## Within one commodity the fuller town draws the holds first, so a level-4 town
## earns its bonus before a level-2 one (DR-20261111-*).
func test_the_better_town_draws_the_landed_tons_first() -> void:
	var world: WorldMap = _plantation_world([2, 4])
	var works: MapRegionTable = _plantation_works_table(world)

	var tight: Dictionary = EconomyOverseas.delivered(
		{}, world, WorldMap.OLD_WORLD, 0, {"timber": 4}, works, 8
	)
	var roomy: Dictionary = EconomyOverseas.delivered(
		{}, world, WorldMap.OLD_WORLD, 0, {"timber": 4}, works, 16
	)

	assert_eq(
		tight["manufactured"], {"lumber": 4, "paper": 4}, "the level-4 town draws first"
	)
	assert_eq(
		roomy["manufactured"], {"lumber": 6, "paper": 6}, "then the level-2 town's x1"
	)

## A colonial town that manufactured says so in the turn summary, so the bonus is
## visible without opening a ledger (REQ-P5-05).
func test_the_turn_summary_names_colonial_manufactures() -> void:
	var report: Dictionary = {
		"overseas": {"used": 8, "left_total": 2, "manufactured": {"castIron": 2}},
	}
	var line: String = LedgerText.turn_summary(report)

	assert_true(line.contains("8 colonial tons landed"))
	assert_true(line.contains("2 cast iron made in colonial towns"))
	assert_true(line.contains("2 left on the far shore"))
	assert_false(LedgerText.turn_summary({}).contains("colonial towns"))


## A coast the sea has shut is a rule, not a lean harvest: the despatch names it
## (wiki: capital-and-connectivity § Blockade; REQ-P5-05).
func test_the_turn_summary_names_a_blockaded_coast() -> void:
	var report: Dictionary = {
		"extraction": {"grain": 5},
		"blockade": "Blockaded: Cádiz — nothing there reaches the crown by sea this turn",
	}
	var line: String = LedgerText.turn_summary(report)
	assert_true(line.contains("Blockaded: Cádiz"), line)
	assert_true(line.contains("gathered 5 grain"), line)
	assert_false(LedgerText.turn_summary({"extraction": {"grain": 5}}).contains("Blockaded"))


## A study the purse cannot pay is a rule with a floor, not a broken purse: the
## turn's own despatch names what stopped it, so a crown that never opens the
## college still learns why (wiki: tech-tree-labour-economy § money_lending,
## banking; REQ-P5-05).
func test_the_turn_summary_names_the_lending_floor_behind_an_unpaid_slot() -> void:
	var lending: Dictionary = {"research": {"unpaid": ["land_enclosure"], "floor": -500}}
	var line: String = LedgerText.turn_summary(lending)
	assert_true(line.contains("1 research slot unfunded"), line)
	assert_true(line.contains("the -500 lending floor is reached"), line)

	var borrowing: Dictionary = {"research": {"unpaid": ["a", "b"], "floor": 0}}
	var tied: String = LedgerText.turn_summary(borrowing)
	assert_true(tied.contains("2 research slots unfunded"), tied)
	assert_true(tied.contains("research may not borrow"), tied)


## The same rule spelled out for the college and the slot's own hover.
func test_the_floor_text_follows_money_lending_and_banking() -> void:
	assert_true(LedgerText.research_floor_line(0).contains("stops at 0 ducats"))
	assert_true(LedgerText.research_floor_line(0).contains("Money Lending"))
	assert_true(LedgerText.research_floor_line(ResearchFunding.DEBT_FLOOR).contains("-500"))
	assert_true(LedgerText.research_floor_line(ResearchFunding.DEBT_FLOOR).contains("Banking"))
	assert_true(
		LedgerText.research_floor_line(ResearchFunding.BANK_DEBT_FLOOR).contains("-1,000"),
		"both techs, both figures read as money"
	)
	assert_eq(LedgerText.research_floor_note(0), "research may not borrow")
	assert_eq(LedgerText.research_floor_note(ResearchFunding.DEBT_FLOOR), "the -500 lending floor is reached")

# --- test_trade_cargo ---

func _trade_cargo_world() -> WorldMap:
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
	var world: WorldMap = _trade_cargo_world()
	var home := FleetState.in_port(1, 0, 0, ["a", "b"], {"a": "fluyte", "b": "carrack"})
	var at_sea := FleetState.at_sea(2, 0, 0, ["c"], {"c": "indiaman"})
	# A harbour that is not the seat carries nothing.
	var other_port := FleetState.in_port(3, 0, 1, ["d"], {"d": "indiaman"})
	var foreign := FleetState.in_port(4, 1, 1, ["e"], {"e": "galleon"})
	var fleets: Dictionary = {0: [home, at_sea, other_port], 1: [foreign]}

	assert_eq(TradeCargo.capacity(world, fleets, 0), 7)
	assert_eq(TradeCargo.capacity(world, fleets, 1), 0)

func test_a_crown_without_a_seat_has_no_cargo() -> void:
	var world: WorldMap = _trade_cargo_world()
	var home := FleetState.in_port(1, 0, 0, ["a"], {"a": "fluyte"})
	assert_eq(TradeCargo.capacity(world, {0: [home]}, 6), 0)
	assert_eq(TradeCargo.capacity(null, {0: [home]}, 0), 0)

func test_status_reports_holds_used_and_free() -> void:
	var world: WorldMap = _trade_cargo_world()
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

# --- helpers for ported main economy tests ---

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

func _group(id: int, name: String, rows: Array) -> Dictionary:
	var producing: int = 0
	for row: Dictionary in rows:
		if int(row.get("output", 0)) > 0:
			producing += 1
	return {"id": id, "name": name, "rows": rows, "producing": producing}

func _rows() -> Array:
	return [
		{"output": 2, "working": false, "status": "producing"},
		{"output": 0, "working": true, "status": "building"},
		{"output": 0, "working": false, "status": "vacant"},
		{"output": 0, "working": false, "status": "disconnected"},
	]

# --- ported from main test_economy_rules ---



## The standing world counterparty is no court: it pays no clear price, so a
## harvest it absorbs owes the deed holder nothing (wiki:
## world-market-first-right-of-refusal § Eligibility — "another GP buys those
## units"; § Treasury transfer D4 — "the buyer GP pays").
func test_credits_ignore_a_sale_the_world_counterparty_took() -> void:
	var deals: Array[Dictionary] = [{
		"seller": 6, "buyer": MarketOrder.WORLD, "commodity": "timber",
		"quantity": 10, "price": 20.0, "seller_is_minor": true,
		"origin_region": 0, "origin_index": 1,
	}]
	var result: Dictionary = FirstRight.credits(
		deals,
		func(_region: int, _index: int) -> int: return 0,
		func(_gp: int, _minor: int) -> float: return 75.0,
		func(_gp: int, _minor: int) -> bool: return true
	)
	assert_eq((result["by_gp"] as Dictionary).size(), 0, "nobody paid a share")
	assert_eq((result["rows"] as Array).size(), 0, "no credit row for a world fill")
	assert_eq(float(result["sink"]), 0.0, "a world fill adds nothing to the sink")


## Playtest: a deed bought and never bid on must not mint treasury at the turn
## close, even though the standing world counterparty clears the harvest.



## Playtest: a deed bought and never bid on must not mint treasury at the turn
## close, even though the standing world counterparty clears the harvest.
func test_a_world_backstop_sale_pays_no_deed_share() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _world()
	var model: MapModel = world.region(0)
	assert_true(model.purchase_tile(Vector2i(2, 0), 0))
	var economies: Dictionary = _economies()
	var owner: PlayerEconomy = economies[0]
	var before: int = owner.treasury
	var diplomacy := DiplomacyState.new()
	diplomacy.ensure_relation(0, 6, 0).set_score(100.0)
	var report: Dictionary = MarketClearing.clear(
		market, world, economies, {0: 4, 1: 4}, {"diplomacy": diplomacy}
	)
	assert_eq(owner.treasury, before, "no court paid, so there is no share")
	assert_eq((report["credits"] as Dictionary)["by_gp"].size(), 0)
	assert_eq(float(report["sink"]), 0.0, "the world paid nothing into the sink")


## A kickback is funded from a court's payment, so a world fill funds none.



## A kickback is funded from a court's payment, so a world fill funds none.
func test_a_world_backstop_sale_pays_no_embassy_kickback() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _world()
	var economies: Dictionary = _economies()
	var embassy_court: PlayerEconomy = PlayerEconomy.starting()
	economies[2] = embassy_court
	var before: int = embassy_court.treasury
	var diplomacy := DiplomacyState.new()
	diplomacy.ensure_relation(2, 6, 0).set_score(50.0)
	diplomacy.set_overture(2, 6, DiplomacyCatalog.STAGE_EMBASSY)
	var report: Dictionary = MarketClearing.clear(
		market, world, economies, {0: 4, 1: 4, 2: 4}, {"diplomacy": diplomacy}
	)
	assert_eq(embassy_court.treasury, before, "no buyer, no kickback")
	assert_eq((report["credits"] as Dictionary)["by_gp"].size(), 0)


## The colony's harvest clears to its suzerain inside the tier even though the
## rival is the warmer, better-known court (wiki: diplomacy § R7.1;
## DR-20261111-11).



# --- from test_ledger_text.gd ---
## Ledger copy: the market clearing line and its quiet empty case.


func test_a_quiet_market_prints_nothing() -> void:
	assert_eq(LedgerText.market_summary({}, 0), "")


## The disband row promises no refund and names what the tier eats
## (wiki: workers-and-population § Disband, § Tiers).



## The disband row promises no refund and names what the tier eats
## (wiki: workers-and-population § Disband, § Tiers).
func test_the_disband_hint_names_the_promise_and_the_saving() -> void:
	var hint: String = LedgerText.disband_hint(WorkerPool.Tier.APPRENTICE)
	assert_true(hint.contains("no recruit cost is refunded"), hint)
	assert_true(hint.contains("An apprentice eats 2 food"), hint)
	assert_true(hint.contains("a unit of Refined Sugar"), hint)
	var master: String = LedgerText.disband_hint(WorkerPool.Tier.MASTER)
	assert_true(master.contains("A master eats 2 food and a unit of Fur Hats"), master)



func test_fills_carry_and_lapse_are_named() -> void:
	var report: Dictionary = {
		"fills": {0: {"bought": 2, "spent": 60, "sold": 1}},
		"carry": [{"commodity": "timber"}],
		"notes": [{
			"code": "carry_forward_dropped_cargo_insufficient",
			"faction": 0,
			"commodity": "grain",
		}],
	}
	var line: String = LedgerText.market_summary(report, 0)
	assert_true(line.contains("bought 2 for 60 ducats"))
	assert_true(line.contains("sold 1"))
	assert_true(line.contains("1 order carried"))
	assert_true(line.contains("1 order lapsed"))


## A sale names the ducats it paid, and the overseas share is named even when
## the court traded nothing itself: the auction is the purse movement the
## per-turn figure cannot project (wiki: world-market § Trade orders, § First
## right of refusal).



## A sale names the ducats it paid, and the overseas share is named even when
## the court traded nothing itself: the auction is the purse movement the
## per-turn figure cannot project (wiki: world-market § Trade orders, § First
## right of refusal).
func test_a_sale_and_an_overseas_share_are_named() -> void:
	var report: Dictionary = {
		"fills": {0: {"sold": 1, "earned": 50}},
		"credits": {"by_gp": {0: 89.4}},
		"carry": [],
		"notes": [],
	}
	var line: String = LedgerText.market_summary(report, 0)
	assert_true(line.contains("sold 1 for 50 ducats"), line)
	assert_true(line.contains("89 ducats in shares"), line)
	# A court with no fills of its own still reads its share.
	var quiet: Dictionary = {"fills": {}, "credits": {"by_gp": {0: 12.0}}}
	assert_true(
		LedgerText.market_summary(quiet, 0).contains("12 ducats in shares"),
		LedgerText.market_summary(quiet, 0),
	)
	assert_eq(LedgerText.share_credit({"credits": {0: 7.6}}, 0), 8, "a bare map is read too")


## The "Next turn" promise names the orders that settle after it, so a staged
## order is never read as already counted (wiki: stockpiles-and-production
## § Production flow — the auction clears after Production).



## The "Next turn" promise names the orders that settle after it, so a staged
## order is never read as already counted (wiki: stockpiles-and-production
## § Production flow — the auction clears after Production).
func test_the_preview_names_the_auction_it_excludes() -> void:
	var staged: Dictionary = {
		"stockpile_delta": {"grain": 3},
		"treasury_delta": 0,
		"staged_orders": 2,
	}
	var line: String = LedgerText.preview(staged)
	assert_true(line.contains("Grain +3"), line)
	assert_true(line.contains("2 orders settle at the auction"), line)
	var one: Dictionary = {"stockpile_delta": {}, "treasury_delta": 0, "staged_orders": 1}
	assert_true(
		LedgerText.preview(one).contains("1 order settles at the auction"),
		LedgerText.preview(one),
	)
	# Nothing staged: the calm line stays exactly as it was.
	assert_eq(
		LedgerText.preview({"stockpile_delta": {}, "treasury_delta": 0}),
		"Next turn: no stock changes.",
	)



func test_another_courts_lapse_is_not_ours() -> void:
	var report: Dictionary = {
		"fills": {},
		"carry": [],
		"notes": [{
			"code": "carry_forward_dropped_cargo_insufficient",
			"faction": 1,
			"commodity": "grain",
		}],
	}
	assert_eq(LedgerText.market_summary(report, 0), "")


# --- from test_ledger_helpers.gd ---
## Unit: the pure helpers extracted from the ledger and estates panels
## (REQ-P3-01, REQ-P3-04). No scene tree, so the rules stay testable.


# --- TextFormat --------------------------------------------------------------



# --- from test_ledger_helpers.gd ---
## Unit: the pure helpers extracted from the ledger and estates panels
## (REQ-P3-01, REQ-P3-04). No scene tree, so the rules stay testable.


# --- TextFormat --------------------------------------------------------------


func test_thousands_groups_and_keeps_the_sign() -> void:
	assert_eq(TextFormat.thousands(0), "0")
	assert_eq(TextFormat.thousands(999), "999")
	assert_eq(TextFormat.thousands(1000), "1,000")
	assert_eq(TextFormat.thousands(1234567), "1,234,567")
	assert_eq(TextFormat.thousands(-1234), "-1,234")


# --- LedgerText --------------------------------------------------------------



# --- LedgerText --------------------------------------------------------------


func test_recipe_title_names_the_single_input() -> void:
	var recipe_id: String = ProductionRecipes.available_ids({})[0]
	var title: String = LedgerText.recipe_title(recipe_id)
	assert_true(title.contains(CommodityCatalog.label(ProductionRecipes.output(recipe_id))))
	assert_true(LedgerText.recipe_tooltip(recipe_id).contains("→"))



func test_the_summary_reads_the_report() -> void:
	var economy: PlayerEconomy = PlayerEconomy.new()
	economy.treasury = 1234
	var report: Dictionary = {
		"consumption": {"idle_labour": 3, "strikers": 2, "navy_demand": 5},
	}
	var line: String = LedgerText.summary(economy, report)
	assert_true(line.contains("1,234 ducats"))
	assert_true(line.contains("labour 3 /"))
	assert_true(line.contains("strikes 2"))


## The ledger's food need is every mouth Consumption feeds — the workers, the
## army, the navy and the hospital staffs (wiki: workers-and-population
## § Consumption: "Total food demand = workers + navy + army + hospital staffs").
## A mid-game army is most of the larder, so a need that stopped at the workers
## and hulls read a crown at war as twice as fed as it was.



## The ledger's food need is every mouth Consumption feeds — the workers, the
## army, the navy and the hospital staffs (wiki: workers-and-population
## § Consumption: "Total food demand = workers + navy + army + hospital staffs").
## A mid-game army is most of the larder, so a need that stopped at the workers
## and hulls read a crown at war as twice as fed as it was.
func test_the_food_need_counts_every_mouth_the_larder_feeds() -> void:
	var economy: PlayerEconomy = PlayerEconomy.new()
	economy.workers = WorkerPool.make(4)
	var report: Dictionary = {
		"consumption": {
			"army_demand": 41, "navy_demand": 18, "hospital_demand": 4,
		},
	}
	var line: String = LedgerText.summary(economy, report)
	assert_true(line.contains("food need 67"), line)
	assert_eq(LedgerText.army_food(report), 41)
	assert_eq(LedgerText.army_food({}), 0, "a report with no consumption feeds nobody")



func test_the_preview_reports_deltas_or_calm() -> void:
	assert_eq(LedgerText.preview({}), "Next turn: no stock changes.")
	var line: String = LedgerText.preview(
		{"stockpile_delta": {"grain": 3}, "treasury_delta": -10}
	)
	assert_true(line.contains("+3"))
	assert_true(line.contains("ducats -10"))



func test_the_cargo_banner_covers_three_states() -> void:
	assert_true(LedgerText.cargo_line({}).contains("unknown"))
	var empty: Dictionary = {"holds": 0, "free": 0}
	assert_true(LedgerText.cargo_line(empty).contains("No cargo holds"))
	assert_eq(LedgerText.cargo_color(empty), Palette.GOLD_PALE)
	var laden: Dictionary = {"holds": 4, "free": 1}
	assert_true(LedgerText.cargo_line(laden).contains("4 holds"))
	assert_eq(LedgerText.cargo_color(laden), Palette.TEXT)



func test_report_counters_default_to_zero() -> void:
	assert_eq(LedgerText.idle_labour({}), 0)
	assert_eq(LedgerText.navy_food({"consumption": {"navy_demand": 7}}), 7)


# --- EstateLedger ------------------------------------------------------------



func test_groups_keep_province_order_and_merge_duplicates() -> void:
	var snapshot: Dictionary = {
		"groups": [
			_group(4, "OLD", _rows().slice(0, 2)),
			_group(4, "OLD", _rows().slice(2)),
			_group(9, "NEW", _rows().slice(0, 1)),
		],
	}
	var groups: Array[Dictionary] = EstateLedger.grouped(snapshot)
	assert_eq(groups.size(), 2)
	assert_eq(groups[0]["name"], "OLD")
	assert_eq((groups[0]["rows"] as Array).size(), 4)



func test_province_filter_keeps_one_group() -> void:
	var groups: Array[Dictionary] = EstateLedger.grouped(
		{"groups": [_group(1, "A", _rows()), _group(2, "B", _rows())]}
	)
	assert_eq(EstateLedger.in_province(groups, -1).size(), 2)
	assert_eq(EstateLedger.in_province(groups, 2).size(), 1)



func test_each_filter_selects_its_rows() -> void:
	var rows: Array = _rows()
	assert_eq(EstateLedger.matching(rows, "all").size(), 4)
	assert_eq(EstateLedger.matching(rows, "producing").size(), 1)
	assert_eq(EstateLedger.matching(rows, "building").size(), 1)
	assert_eq(EstateLedger.matching(rows, "vacant").size(), 1)
	assert_eq(EstateLedger.matching(rows, "issues").size(), 1)



func test_total_output_sums_every_yield() -> void:
	assert_eq(EstateLedger.total_output({"lumber": 2, "iron": 3}), 5)
	assert_eq(EstateLedger.total_output({}), 0)


# --- UiRowBuilder ------------------------------------------------------------



# --- UiRowBuilder ------------------------------------------------------------


func test_row_builder_builds_themed_widgets() -> void:
	var row: HBoxContainer = UiRowBuilder.row(38.0)
	assert_eq(row.custom_minimum_size.y, 38.0)
	var label: Label = UiRowBuilder.label("hi", 14, Palette.TEXT)
	assert_eq(label.text, "hi")
	var caption: Label = UiRowBuilder.caption("x", 10, Palette.TEXT_DIM, 44.0)
	assert_eq(caption.custom_minimum_size.x, 44.0)
	var button: Button = UiRowBuilder.button("Go", 38.0, 70.0)
	assert_eq(button.text, "Go")
	assert_eq(button.custom_minimum_size, Vector2(70, 38))
	row.free()
	label.free()
	caption.free()
	button.free()



func test_clear_empties_a_container() -> void:
	var box := VBoxContainer.new()
	add_child(box)
	UiRowBuilder.spacer(box)
	box.add_child(UiRowBuilder.label("gone", 12, Palette.TEXT))
	box.add_child(UiRowBuilder.label("gone too", 12, Palette.TEXT))
	assert_eq(box.get_child_count(), 3)
	UiRowBuilder.clear(box)
	assert_eq(box.get_child_count(), 0)
	box.queue_free()


# --- from test_commodity_icons.gd ---
## Every commodity carries its own medallion and every plate ships, so no two
## goods share one picture in the ledger (REQ-P1-02; tools/art/goods-medallions.md).



# --- from test_commodity_icons.gd ---
## Every commodity carries its own medallion and every plate ships, so no two
## goods share one picture in the ledger (REQ-P1-02; tools/art/goods-medallions.md).


func test_every_catalog_commodity_ships_a_medallion() -> void:
	var missing: Array[String] = []
	for id: String in CommodityCatalog.all_ids():
		if CommodityIcons.texture(id) == null:
			missing.append(id)
	assert_eq(missing.size(), 0, "goods with no plate: %s" % ", ".join(missing))



func test_two_goods_never_share_one_plate() -> void:
	var seen: Dictionary = {}
	var clashes: Array[String] = []
	for id: String in CommodityCatalog.all_ids():
		var art: Texture2D = CommodityIcons.texture(id)
		if art == null:
			continue
		if seen.has(art.resource_path):
			clashes.append("%s/%s" % [seen[art.resource_path], id])
		seen[art.resource_path] = id
	assert_eq(clashes.size(), 0, "goods sharing a plate: %s" % ", ".join(clashes))



func test_an_unknown_good_has_no_plate() -> void:
	assert_null(CommodityIcons.texture("no_such_good"))
	assert_null(CommodityIcons.texture(""))



func test_a_badge_draws_the_good_at_the_row_size() -> void:
	var badge: Control = CommodityIcons.badge("grain")
	var art: TextureRect = badge as TextureRect
	assert_not_null(art, "a known good draws a texture")
	assert_eq(art.texture, CommodityIcons.texture("grain"))
	assert_eq(art.custom_minimum_size, Vector2(CommodityIcons.ROW_SIZE, CommodityIcons.ROW_SIZE))
	badge.free()



func test_a_missing_plate_leaves_a_gap_of_the_same_width() -> void:
	var gap: Control = CommodityIcons.badge("no_such_good", 18)
	assert_null(gap as TextureRect, "a missing plate is not a texture")
	assert_eq(gap.custom_minimum_size, Vector2(18, 18), "the row keeps its columns")
	gap.free()



func test_a_name_cell_keeps_the_column_width() -> void:
	var cell: HBoxContainer = CommodityIcons.cell("timber", 132.0)
	assert_eq(cell.custom_minimum_size.x, 132.0, "the cell owns the column width")
	var labels: Array[Node] = cell.find_children("*", "Label", true, false)
	assert_eq(labels.size(), 1, "one label per cell")
	assert_eq((labels[0] as Label).text, CommodityCatalog.label("timber"))
	var art: Array[Node] = cell.find_children("*", "TextureRect", true, false)
	assert_eq(art.size(), 1, "the medallion rides inside the cell")
	assert_eq((art[0] as TextureRect).texture, CommodityIcons.texture("timber"))
	cell.free()


## The plate is 128 px so it survives the phone's 3× draw scale.



## The plate is 128 px so it survives the phone's 3× draw scale.
func test_a_plate_is_a_128_px_source() -> void:
	var art: Texture2D = CommodityIcons.texture("coal")
	assert_not_null(art)
	assert_eq(art.get_width(), 128)
	assert_eq(art.get_height(), 128)



# --- the Minor/Tribe sale order and its receipt ---

## One Minor estate and nothing else: whoever wins it takes the only timber.
func _sale_world() -> WorldMap:
	var model := MapModel.new()
	model.setup(4, 2)
	for y in 2:
		for x in 4:
			model.province[model.index_of(x, y)] = 0 if x < 2 else 1
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
	var gp_tiles: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)
	]
	var minor_tiles: Array[Vector2i] = [
		Vector2i(2, 0), Vector2i(3, 0), Vector2i(2, 1), Vector2i(3, 1)
	]
	var gp := ProvinceState.create(0, "P0", gp_tiles, Vector2.ZERO, 4, 0)
	var minor := ProvinceState.create(1, "P1", minor_tiles, Vector2.ZERO, 4, 6)
	model.provinces = [gp, minor]
	model.resource[model.index_of(2, 0)] = 0
	var world := WorldMap.new()
	world.add_region(model)
	return world


func _timber_buyer(report: Dictionary) -> int:
	for raw: Variant in report["deals"]:
		var deal: Dictionary = raw
		if String(deal.get("commodity", "")) == "timber" and int(deal.get("seller", -2)) == 6:
			return int(deal.get("buyer", -1))
	return -1


## A Trade Consulate is the first overture stage, and R7.3 serves its holder
## ahead of every consulate-less buyer whatever the rivals' relations (wiki:
## world-market § Sell-priority relation tiebreaker). The holder carries the
## higher faction id, so a gate read as "no Consulate anywhere" would hand the
## estate to the stranger by the default order.
func test_a_trade_consulate_clears_before_a_warmer_stranger() -> void:
	var world: WorldMap = _sale_world()
	var market: WorldMarket = WorldMarket.with_default_prices()
	var diplomacy := DiplomacyState.new()
	diplomacy.ensure_relation(0, 6, 0).set_score(90.0)
	diplomacy.ensure_relation(1, 6, 0).set_score(10.0)
	diplomacy.set_overture(1, 6, DiplomacyCatalog.STAGE_CONSULATE)
	# The stranger speaks first, so the deal proves the tiebreak, not the book order.
	for gp: int in [0, 1]:
		MarketOrders.submit(
			market,
			gp, "timber", MarketOrder.SIDE_BID, 1,
			{"cargo_free": 4, "treasury": 5000, "buy_price": 30}
		)
	var report: Dictionary = MarketClearing.clear(
		market, world, _economies(), {0: 4, 1: 4}, {"diplomacy": diplomacy}
	)
	assert_eq(_timber_buyer(report), 1, "the Consulate holder takes the estate")


## R7.3's relation arm needs a Consulate on both sides; two consulate-less courts
## keep the default order (ascending faction id) however warm one of them is.
func test_two_consulate_less_buyers_keep_the_default_order() -> void:
	var orders: Array[MarketOrder] = [
		_order(1, "timber", MarketOrder.SIDE_BID, 1, 1),
		_order(2, "timber", MarketOrder.SIDE_BID, 1, 1),
		_order(6, "timber", MarketOrder.SIDE_OFFER, 1, 1),
	]
	var context: Dictionary = _context()
	context["consulate_for"] = func(_gp: int, _minor: int) -> bool: return false
	context["relation_for"] = func(gp: int, _minor: int) -> float:
		return 90.0 if gp == 2 else 10.0
	var result: Dictionary = MarketMatcher.match(orders, context)
	assert_eq(
		int((result["deals"] as Array)[0]["buyer"]), 1,
		"a consulate-less court never jumps the default order"
	)


## The Deal Book line names the price the pair was charged — the crown's terms
## and the subsidy step included — not the untaxed published price (wiki:
## world-market § Subsidy price adjustment; REQ-P5-05).
func test_the_clearing_receipt_names_the_price_the_pair_charged() -> void:
	var world: WorldMap = _sale_world()
	var market: WorldMarket = WorldMarket.with_default_prices()
	var diplomacy := DiplomacyState.new()
	diplomacy.set_subsidy(0, 6, 10)
	var economies: Dictionary = _economies()
	var before: int = (economies[0] as PlayerEconomy).treasury
	MarketOrders.submit(
		market,
		0, "timber", MarketOrder.SIDE_BID, 1,
		{"cargo_free": 4, "treasury": before, "buy_price": 30}
	)
	var report: Dictionary = MarketClearing.clear(
		market, world, economies, {0: 4, 1: 4}, {"diplomacy": diplomacy}
	)
	var deal: Dictionary = {}
	for raw: Variant in report["deals"]:
		if int((raw as Dictionary).get("buyer", -2)) == 0:
			deal = raw
	assert_eq(before - (economies[0] as PlayerEconomy).treasury, 33, "one timber, 10% over")
	var line: String = LedgerText.deal_line(deal)
	assert_true(line.contains("at 33"), line)
	assert_true(line.contains("33 ducats"), "the receipt names the ducats paid: %s" % line)


## The other two Deal Book lines: a sale names its receipt, a favoured fill says
## so, and a legacied row with no `buy_unit` still reads at its published price
## (REQ-P5-05; wiki: world-market § Favored Trading Partner).
func test_the_deal_receipt_reads_a_sale_a_favour_and_an_old_row() -> void:
	assert_eq(
		LedgerText.deal_line({
			"buyer": 1, "seller": 0, "commodity": "timber",
			"quantity": 2, "price": 30, "earned": 60,
		}),
		"Sold 2 Timber to %s at 30 — 60 ducats" % FactionCatalog.name_of(1)
	)
	assert_true(
		LedgerText.deal_line({
			"buyer": 0, "seller": 6, "commodity": "timber",
			"quantity": 1, "price": 30, "is_favoured": true,
		}).ends_with("as its favoured partner")
	)
	assert_eq(
		LedgerText.deal_line({
			"buyer": 0, "seller": 6, "commodity": "timber", "quantity": 1, "price": 30,
		}),
		"Bought 1 Timber from %s at 30 — 30 ducats" % FactionCatalog.name_of(6),
		"a row saved before `buy_unit` reads at the published price"
	)


## The Deal Book is the crown's own: a court that sails as England reads her
## staged orders and her clearing, never Spain's (wiki: world-market § Trade
## orders; REQ-P2-03 — the sheet cannot answer for another crown).
func test_the_deal_book_reads_the_viewing_crowns_orders() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	assert_true(bool(MarketOrders.submit(
		market, 1, "timber", MarketOrder.SIDE_OFFER, 3,
		{"stock": 10, "reserved": {}}
	)["ok"]))
	var english := LedgerMarket.new()
	english.fill(PlayerEconomy.starting(), market, {}, [], {}, 1)
	assert_true(_has_cancel(english), "England reads her own staged offer")
	english.free()
	var spain := LedgerMarket.new()
	spain.fill(PlayerEconomy.starting(), market, {}, [], {}, 0)
	assert_false(_has_cancel(spain), "Spain does not read England's book")
	spain.free()


## A staged order is the only row that offers a Cancel, so its presence is the
## sheet's own answer to "is this my book?".
func _has_cancel(node: Node) -> bool:
	var button := node as Button
	if button != null and button.text == "Cancel":
		return true
	for child: Node in node.get_children():
		if _has_cancel(child):
			return true
	return false


## The Minor offer's Bid names the ask the clearing will charge — the published
## price with the crown's terms and the pair's subsidy step (wiki: world-market
## § Subsidy price adjustment; REQ-P5-05).
func test_the_minor_offer_bid_names_the_ask() -> void:
	var ledger := LedgerMarket.new()
	var row: Control = ledger._offer_row({
		"id": "6:timber", "faction": 6, "commodity": "timber",
		"quantity": 1, "unit_price": 33,
	})
	var buy: Button = row.get_child(row.get_child_count() - 1) as Button
	assert_eq(buy.text, "Bid")
	assert_true(buy.tooltip_text.contains("ask of 33"), buy.tooltip_text)
	row.free()
	ledger.free()


# --- rival lock-recovery (issue #489) ---------------------------------------

func _ai_config() -> AiConfig:
	return AiConfig.build(1, 1500)


## Units of one commodity a rival plan offers, or 0 when it offers none.
func _offer_of(plan: Dictionary, id: String) -> int:
	for raw: Variant in plan.get("offers", []):
		var offer: Dictionary = raw
		if String(offer["commodity"]) == id:
			return int(offer["quantity"])
	return 0


## Units of one commodity a rival plan bids for, or 0 when it bids for none.
func _bid_of(plan: Dictionary, id: String) -> int:
	for raw: Variant in plan.get("bids", []):
		var bid: Dictionary = raw
		if String(bid["commodity"]) == id:
			return int(bid["quantity"])
	return 0


## A court that cannot feed its own people stops holding a comfort reserve on
## the stock it is not about to spend: the hoard is worth more as the food it
## buys than as a shelf beside an empty larder (wiki: treasury-planner
## § Lock-recovery; issue #489).
func test_a_starving_court_liquidates_its_hoard() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.treasury = 100
	economy.stockpile = {"wool": 25}
	var market := WorldMarket.with_default_prices()
	var fed: Dictionary = AiMarketPlanner.plan(_ai_config(), economy, market, 0)
	assert_eq(_offer_of(fed, "wool"), 5, "a fed court keeps market.sell_reserve (20)")
	var starving: Dictionary = AiMarketPlanner.plan(
		_ai_config(), economy, market, 0, {}, {}, {}, 0, 6
	)
	assert_eq(
		_offer_of(starving, "wool"), 10,
		"a starving court sells down to market.max_offer_units"
	)


## The reserve still holds the court's own dinner: a starving court liquidates
## its manufactures and raw, never the grain its regiments and staffs eat
## (wiki: workers-and-population § Consumption).
func test_a_starving_court_never_sells_its_own_dinner() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.treasury = 100
	economy.stockpile = {"grain": 25}
	var market := WorldMarket.with_default_prices()
	var starving: Dictionary = AiMarketPlanner.plan(
		_ai_config(), economy, market, 0, {}, {}, {}, 0, 6
	)
	assert_eq(_offer_of(starving, "grain"), 5, "the ration reserve still applies")


## Food is not a discretionary spend: a court short of rations bids for it out of
## the whole purse, not the surplus above the war chest it is saving for — a
## strike costs it every hand it has (wiki: treasury-planner § Lock-recovery).
func test_a_starving_court_buys_food_out_of_the_whole_purse() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.treasury = 100
	economy.stockpile = {}
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(
		_ai_config(), economy, market, 2, {}, {}, {}, 2400, 6
	)
	assert_eq(
		_bid_of(plan, "grain"), 2,
		"two holds and 100 ducats buy two grain at 50, under a 2,400 war chest"
	)
	assert_eq(_bid_of(plan, "lumber"), 0, "the war chest still holds every build input")


## A court that can feed itself trades exactly as published: no food bid, and
## the comfort reserve stays on every commodity.
func test_a_fed_court_bids_no_food() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.treasury = 5000
	economy.stockpile = {"wool": 25}
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(_ai_config(), economy, market, 4)
	assert_eq(_bid_of(plan, "grain"), 0)
	assert_eq(_offer_of(plan, "wool"), 5)
