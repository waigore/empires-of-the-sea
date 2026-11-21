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

## The opening purse is the published seed capital (wiki: ruleset-config
## § Starting stockpiles; DR-20261115-16, #676). It buys the college, the
## surveys and the first roads before any estate yields.
func test_every_crown_opens_on_the_published_purse() -> void:
	assert_eq(PlayerEconomy.START_TREASURY, 20000)
	assert_eq(PlayerEconomy.starting().treasury, 20000)


func test_the_seller_filter_narrows_the_book_to_one_court() -> void:
	var rows: Array[Dictionary] = MarketBookFilter.apply(
		_book(), 7, MarketBookFilter.ALL_GOODS, MarketBookFilter.SORT_SELLER
	)
	assert_eq(_ids(rows), ["7:grain", "7:timber"])

func test_the_good_filter_narrows_the_book_to_one_commodity() -> void:
	var rows: Array[Dictionary] = MarketBookFilter.apply(
		_book(), MarketBookFilter.ALL_SELLERS, "grain", MarketBookFilter.SORT_SELLER
	)
	assert_eq(rows.size(), 2)
	for row: Dictionary in rows:
		assert_eq(String(row["commodity"]), "grain")

func test_both_filters_narrow_together_and_can_empty_the_book() -> void:
	var narrowed: Array[Dictionary] = MarketBookFilter.apply(
		_book(), 9, "timber", MarketBookFilter.SORT_SELLER
	)
	assert_eq(_ids(narrowed), ["9:timber"])
	assert_eq(
		MarketBookFilter.apply(_book(), 9, "grain", MarketBookFilter.SORT_SELLER).size(), 0
	)

## Court A–Z by name (not by id), and the richer book first inside a court.
func test_the_default_order_is_court_name_then_the_richest_book() -> void:
	var rows: Array[Dictionary] = MarketBookFilter.apply(
		_book(), MarketBookFilter.ALL_SELLERS, MarketBookFilter.ALL_GOODS,
		MarketBookFilter.SORT_SELLER
	)
	assert_eq(_ids(rows), ["9:timber", "11:grain", "7:grain", "7:timber"])

func test_sorting_by_good_groups_the_commodities() -> void:
	var rows: Array[Dictionary] = MarketBookFilter.apply(
		_book(), MarketBookFilter.ALL_SELLERS, MarketBookFilter.ALL_GOODS,
		MarketBookFilter.SORT_GOOD
	)
	assert_eq(_ids(rows), ["11:grain", "7:grain", "7:timber", "9:timber"])

func test_cheapest_first_pays_less_per_ton() -> void:
	var rows: Array[Dictionary] = MarketBookFilter.apply(
		_book(), MarketBookFilter.ALL_SELLERS, MarketBookFilter.ALL_GOODS,
		MarketBookFilter.SORT_PRICE
	)
	var prices: Array[int] = []
	for row: Dictionary in rows:
		prices.append(int(row["unit_price"]))
	assert_eq(prices, [12, 12, 28, 30], "the cheapest ask leads: %s" % [_ids(rows)])

func test_most_stock_first_fills_a_bid_sooner() -> void:
	var rows: Array[Dictionary] = MarketBookFilter.apply(
		_book(), MarketBookFilter.ALL_SELLERS, MarketBookFilter.ALL_GOODS,
		MarketBookFilter.SORT_STOCK
	)
	assert_eq(_ids(rows), ["7:grain", "9:timber", "11:grain", "7:timber"])

func test_junk_rows_are_skipped_and_the_published_book_is_never_reordered() -> void:
	var book: Array = _book()
	var published: Array = book.duplicate(true)
	book.append("not an offer")
	var rows: Array[Dictionary] = MarketBookFilter.apply(
		book, MarketBookFilter.ALL_SELLERS, MarketBookFilter.ALL_GOODS,
		MarketBookFilter.SORT_GOOD
	)
	assert_eq(rows.size(), 4)
	assert_eq(book.slice(0, 4), published, "a filter never edits the auction's own rows")

## The chip captions read the tallies: tons and offer count per court and good.
func test_the_tallies_count_tons_and_offers_per_court_and_good() -> void:
	var by_court: Dictionary = MarketBookFilter.tally(_book(), "faction")
	assert_eq(MarketBookFilter.tons(by_court), 11, "every ton on the table")
	assert_eq(MarketBookFilter.tons_of(by_court[7]), 6)
	assert_eq(int(by_court[7]["rows"]), 2)
	var by_good: Dictionary = MarketBookFilter.tally(_book(), "commodity")
	assert_eq(MarketBookFilter.tons_of(by_good["grain"]), 7)
	assert_eq(int(by_good["grain"]["rows"]), 2)
	assert_eq(MarketBookFilter.tons_of({}), 0, "an empty entry holds no tons")

func test_the_head_offers_one_chip_per_court_and_good_on_the_table() -> void:
	var head := MarketOffersHead.new()
	head.render(
		_book(), MarketBookFilter.ALL_SELLERS, MarketBookFilter.ALL_GOODS,
		MarketBookFilter.SORT_SELLER
	)
	var chips: Dictionary = head.filter_buttons()
	assert_eq((chips["seller:-1"] as Button).text, "All courts 11", "all tons on the table")
	assert_eq((chips["seller:9"] as Button).text, "Aztec 3")
	assert_eq((chips["seller:7"] as Button).text, "Venice 6")
	assert_false(chips.has("seller:5"), "a court with nothing for sale has no chip")
	assert_eq((chips["good:grain"] as Button).text, "Grain 7")
	assert_eq((chips["good:timber"] as Button).text, "Timber 4")
	assert_false(chips.has("good:meat"), "a good nobody sells has no chip")
	for key: String in MarketBookFilter.SORT_KEYS:
		assert_true(chips.has("sort:%s" % key), "the order chip %s exists" % key)
	assert_true((chips["seller:-1"] as Button).button_pressed, "All is the opening filter")
	assert_true((chips["sort:seller"] as Button).button_pressed)
	head.free()

func test_a_chip_press_is_the_whole_filter_intent() -> void:
	var head := MarketOffersHead.new()
	head.render(
		_book(), MarketBookFilter.ALL_SELLERS, MarketBookFilter.ALL_GOODS,
		MarketBookFilter.SORT_SELLER
	)
	var seen: Array = []
	head.filters_changed.connect(
		func(seller: int, good: String, sort_key: String) -> void:
			seen.append([seller, good, sort_key])
	)
	(head.filter_buttons()["seller:11"] as Button).pressed.emit()
	assert_eq(head.seller, 11)
	assert_eq(seen, [[11, MarketBookFilter.ALL_GOODS, MarketBookFilter.SORT_SELLER]])
	var chips: Dictionary = head.filter_buttons()
	assert_true((chips["seller:11"] as Button).button_pressed, "the chosen chip lights")
	assert_false((chips["seller:-1"] as Button).button_pressed, "All steps aside")

	(head.filter_buttons()["good:timber"] as Button).pressed.emit()
	assert_eq(head.commodity, "timber")
	assert_eq(seen.size(), 2)
	assert_eq(seen[1], [11, "timber", MarketBookFilter.SORT_SELLER])

	(head.filter_buttons()["sort:quantity"] as Button).pressed.emit()
	assert_eq(head.sort_key, MarketBookFilter.SORT_STOCK)
	assert_eq(seen.size(), 3)
	assert_eq(seen[2], [11, "timber", MarketBookFilter.SORT_STOCK])
	head.free()

## A court that sold out this turn takes its chip with it; the filter falls back
## to All and tells the page, so the strip never hides the whole book silently.
func test_a_selection_the_new_book_lost_falls_back_to_all() -> void:
	var head := MarketOffersHead.new()
	head.render(_book(), 11, "grain", MarketBookFilter.SORT_PRICE)
	assert_eq(head.seller, 11)

	var seen: Array = []
	head.filters_changed.connect(
		func(seller: int, good: String, sort_key: String) -> void:
			seen.append([seller, good, sort_key])
	)
	var next_book: Array = [_book()[0]]
	head.render(next_book, 11, "grain", MarketBookFilter.SORT_PRICE)
	assert_eq(head.seller, MarketBookFilter.ALL_SELLERS)
	assert_eq(head.commodity, MarketBookFilter.ALL_GOODS)
	assert_eq(head.sort_key, MarketBookFilter.SORT_PRICE, "a live order survives the turn")
	assert_eq(seen, [[MarketBookFilter.ALL_SELLERS, MarketBookFilter.ALL_GOODS,
		MarketBookFilter.SORT_PRICE]])
	head.free()

func test_an_unknown_order_key_falls_back_to_the_court_order() -> void:
	var head := MarketOffersHead.new()
	head.render(_book(), MarketBookFilter.ALL_SELLERS, MarketBookFilter.ALL_GOODS, "sideways")
	assert_eq(head.sort_key, MarketBookFilter.SORT_SELLER)
	head.free()

## Chips are thumb targets on a phone viewport (REQ-P5-07).
func test_chips_grow_for_a_thumb_on_a_phone() -> void:
	var head := MarketOffersHead.new()
	head.render(
		_book(), MarketBookFilter.ALL_SELLERS, MarketBookFilter.ALL_GOODS,
		MarketBookFilter.SORT_SELLER
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

## A settled court-to-court deal is recorded for the next Diplomacy phase's
## trade-deal lift (wiki: diplomacy § Relation Model — trade-deal boost, R10).
func test_a_settled_deal_records_the_pair_for_the_lift() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _market_engine_world()
	var economies: Dictionary = _economies()
	var diplomacy := DiplomacyState.new()
	diplomacy.ensure_relation(0, 6, 0).set_score(50.0)
	MarketOrders.submit(
			market,
		0, "timber", MarketOrder.SIDE_BID, 1,
		{"cargo_free": 4, "treasury": 5000, "buy_price": 30}
	)
	MarketClearing.clear(
		market, world, economies, {0: 4, 1: 4}, {"diplomacy": diplomacy}
	)
	assert_true(
		diplomacy.trade_pairs.has(diplomacy.pair_key(0, 6)),
		"the minor's harvest lifts the pair"
	)

## The standing world counterparty is no court, so a bid it fills records no
## pair (wiki: diplomacy § Relation Model — trade-deal boost, R10).
func test_the_world_counterparty_is_no_trade_pair() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _market_engine_world()
	var economies: Dictionary = _economies()
	var diplomacy := DiplomacyState.new()
	MarketOrders.submit(
			market,
		0, "iron", MarketOrder.SIDE_BID, 1,
		{"cargo_free": 4, "treasury": 5000, "buy_price": 80}
	)
	MarketClearing.clear(
		market, world, economies, {0: 4, 1: 4}, {"diplomacy": diplomacy}
	)
	assert_true(diplomacy.trade_pairs.is_empty())

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


## The share's total names the fills that paid it — the deed's own ground first,
## then the embassy kickbacks — so a crown that staged nothing still reads who
## bought what (wiki: world-market-first-right-of-refusal § Eligibility;
## REQ-P5-05). The ducats stay on the total: one deal's cut would publish the
## sealed relation score (DR-20261118-05).
func test_the_overseas_share_names_the_fills_that_paid_it() -> void:
	var report: Dictionary = {"credits": {
		"by_gp": {0: 73.0},
		"rows": [
			{
				"seller": 6, "buyer": 1, "commodity": "grain", "quantity": 1,
				"price": 50.0, "owner": 0, "owner_credit": 25.0,
				"kickbacks": [{"faction": 2, "credit": 4.0}],
			},
			{
				"seller": 12, "buyer": 1, "commodity": "timber", "quantity": 2,
				"price": 30.0, "owner": -1, "owner_credit": 0.0,
				"kickbacks": [{"faction": 0, "credit": 6.0}],
			},
		],
	}}
	var rows: Array[Dictionary] = LedgerMarketText.share_rows(report, 0)
	assert_eq(rows.size(), 2, "the crown's own ground, then its embassy's sale")
	assert_eq(String(rows[0]["kind"]), "deed")
	assert_eq(
		LedgerMarketText.share_row_line(rows[0]),
		"Our deed's share — %s bought 1 Grain from %s" % [
			FactionCatalog.name_of(1), FactionCatalog.name_of(6),
		]
	)
	assert_eq(String(rows[1]["kind"]), "embassy")
	assert_eq(
		LedgerMarketText.share_row_line(rows[1]),
		"Our embassy's kickback — %s bought 2 Timber from %s" % [
			FactionCatalog.name_of(1), FactionCatalog.name_of(12),
		]
	)
	assert_eq(LedgerMarketText.share_credit(report, 0), 73, "the total is unchanged")
	# A court that only earned the kickback reads only that row.
	var theirs: Array[Dictionary] = LedgerMarketText.share_rows(report, 2)
	assert_eq(theirs.size(), 1)
	assert_eq(String(theirs[0]["kind"]), "embassy")
	assert_eq(LedgerMarketText.share_rows(report, 3).size(), 0, "a court paid nothing reads nothing")


## A deed's own fill says so on the row it won; the same deal on another court's
## page carries no claim (wiki: world-market § First right of refusal).
func test_a_first_refusal_fill_says_so_on_its_row() -> void:
	var deal: Dictionary = {
		"buyer": 0, "seller": 6, "commodity": "timber", "quantity": 1,
		"price": 30, "buy_unit": 30, "cost": 30, "is_frr": true,
	}
	assert_true(
		LedgerMarketText.deal_line(deal, 0).ends_with("as its deed's first refusal"),
		"the buyer reads the right that won it the unit"
	)
	assert_false(
		LedgerMarketText.deal_line(deal, 1).contains("first refusal"),
		"a rival reads its own side of the same deal"
	)

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

# --- Boycott: the blocked-deal half (wiki: diplomacy § GP–Tribe — Boycott, R6) ---

## The bar is the pair's, not the offer's: the boycotted court is no bid at all
## for that seller, so the next court in the tier takes the goods.
func test_a_boycott_bars_the_pair_and_the_next_bid_takes_the_goods() -> void:
	var orders: Array[MarketOrder] = [
		_order(1, "timber", MarketOrder.SIDE_BID, 5, 1),
		_order(0, "timber", MarketOrder.SIDE_BID, 5, 1),
		_order(12, "timber", MarketOrder.SIDE_OFFER, 5, 1),
	]
	var context: Dictionary = _context()
	context["boycott_for"] = func(a: int, b: int) -> bool: return (
		(a == 1 and b == 12) or (a == 12 and b == 1)
	)
	var result: Dictionary = MarketMatcher.match(orders, context)
	var deals: Array = result["deals"]
	assert_eq(deals.size(), 1, "one deal, and it is not the barred pair's")
	assert_eq(int(deals[0]["buyer"]), 0)
	assert_eq(int(deals[0]["seller"]), 12)
	assert_eq(int(deals[0]["quantity"]), 5)

## Both sides of a barred pair carry at their unfilled quantity: a boycott
## leaves the order in the book (R6 — "both orders carry forward").
func test_a_boycott_leaves_both_orders_carrying() -> void:
	var orders: Array[MarketOrder] = [
		_order(1, "timber", MarketOrder.SIDE_BID, 4, 1),
		_order(12, "timber", MarketOrder.SIDE_OFFER, 3, 1),
	]
	var context: Dictionary = _context()
	context["boycott_for"] = func(a: int, b: int) -> bool: return (
		(a == 1 and b == 12) or (a == 12 and b == 1)
	)
	var result: Dictionary = MarketMatcher.match(orders, context)
	assert_eq((result["deals"] as Array).size(), 0, "no deal across the boycott")
	var left: Array = result["residuals"]
	assert_eq(left.size(), 2)
	for row: Variant in left:
		var quantity: int = int((row as Dictionary).get("quantity", 0))
		var faction: int = int((row as Dictionary).get("faction", -1))
		assert_eq(quantity, 4 if faction == 1 else 3, "the order keeps every unit")

## The bar runs both ways: a colony Tribe may not buy the goods the boycotted
## court offers either (R6 — all trade between the pair).
func test_a_boycott_bars_the_colonys_bid_too() -> void:
	var orders: Array[MarketOrder] = [
		_order(12, "timber", MarketOrder.SIDE_BID, 2, 1),
		_order(1, "timber", MarketOrder.SIDE_OFFER, 2, 1),
	]
	var context: Dictionary = _context()
	context["stock"] = {1: {"timber": 2}}
	context["treasuries"] = {12: 10000, 1: 10000}
	context["free_holds"] = {12: 4, 1: 4}
	context["boycott_for"] = func(a: int, b: int) -> bool: return (
		(a == 1 and b == 12) or (a == 12 and b == 1)
	)
	var result: Dictionary = MarketMatcher.match(orders, context)
	assert_eq((result["deals"] as Array).size(), 0)
	assert_eq((result["residuals"] as Array).size(), 2)

## Live clearing: the issuer's colony keeps its goods off the boycotted court's
## ledger, and the boycotted court buys them nowhere from that seller.
func test_boycott_blocks_the_deal_at_turn_end() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var tribe: int = int(FactionCatalog.TRIBES[3]["id"])
	var world: WorldMap = _market_engine_world(tribe)
	var economies: Dictionary = _economies()
	var diplomacy := DiplomacyState.new()
	diplomacy.set_colony(tribe, 0)
	diplomacy.ensure_relation(0, tribe, 0).set_score(30.0)
	diplomacy.set_overture(0, tribe, DiplomacyCatalog.STAGE_EMBASSY)
	diplomacy.ensure_relation(0, 1, 0).set_score(30.0)
	var ordered: Dictionary = DiplomacyTrade.boycott(diplomacy, 0, 1)
	assert_true(bool(ordered["ok"]), String(ordered.get("reason", "")))
	MarketOrders.submit(
			market,
		1, "timber", MarketOrder.SIDE_BID, 1,
		{"cargo_free": 4, "treasury": 5000, "buy_price": 30}
	)
	var report: Dictionary = MarketClearing.clear(
		market, world, economies, {0: 4, 1: 4}, {"diplomacy": diplomacy}
	)
	var crossed: int = 0
	var to_world: int = 0
	var from_world: int = 0
	for raw: Variant in report["deals"]:
		var deal: Dictionary = raw
		if String(deal.get("commodity", "")) != "timber":
			continue
		var seller: int = int(deal.get("seller", -2))
		var buyer: int = int(deal.get("buyer", -2))
		if seller == tribe and buyer == 1:
			crossed += 1
		if seller == tribe and buyer == MarketOrder.WORLD:
			to_world += 1
		if seller == MarketOrder.WORLD and buyer == 1:
			from_world += 1
	assert_eq(crossed, 0, "the colony's offer never reaches the boycotted court")
	assert_eq(to_world, 1, "it clears at the standing counterparty instead")
	assert_eq(from_world, 1, "and the boycotted court buys the goods elsewhere")

## A third court is untouched: the boycott blocks one Great Power, not the sale
## (R6 — "not trade between A's colony Tribes and other GPs").
func test_a_boycott_leaves_a_third_court_free_to_buy() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var tribe: int = int(FactionCatalog.TRIBES[3]["id"])
	var world: WorldMap = _market_engine_world(tribe)
	var economies: Dictionary = _economies()
	economies[2] = PlayerEconomy.starting()
	var diplomacy := DiplomacyState.new()
	diplomacy.set_colony(tribe, 0)
	diplomacy.ensure_relation(0, tribe, 0).set_score(30.0)
	diplomacy.set_overture(0, tribe, DiplomacyCatalog.STAGE_EMBASSY)
	diplomacy.ensure_relation(0, 1, 0).set_score(30.0)
	assert_true(bool(DiplomacyTrade.boycott(diplomacy, 0, 1)["ok"]))
	MarketOrders.submit(
			market,
		2, "timber", MarketOrder.SIDE_BID, 1,
		{"cargo_free": 4, "treasury": 5000, "buy_price": 30}
	)
	var report: Dictionary = MarketClearing.clear(
		market, world, economies, {0: 4, 1: 4, 2: 4}, {"diplomacy": diplomacy}
	)
	var from_colony: Array[Dictionary] = []
	for raw: Variant in report["deals"]:
		var deal: Dictionary = raw
		if (
			String(deal.get("commodity", "")) == "timber"
			and int(deal.get("seller", -2)) == tribe
		):
			from_colony.append(deal)
	assert_eq(from_colony.size(), 1, "the colony still sells to the world")
	assert_eq(int(from_colony[0]["buyer"]), 2)

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


## MarketSettlement owns settle, first-right credits and carry after the
## matcher (refactor home of the clearing's post-match pass). These drive the
## pure helpers without a full clear so the module's contract stays named.
func test_settlement_carry_keeps_a_covered_bid_and_drops_a_short_one() -> void:
	var covered := MarketOrder.create(0, "grain", MarketOrder.SIDE_BID, 3, 1)
	covered.id = "covered"
	var short := MarketOrder.create(0, "timber", MarketOrder.SIDE_BID, 4, 1)
	short.id = "short"
	var matched: Dictionary = {
		"residuals": [
			{"order_id": "covered", "quantity": 3},
			{"order_id": "short", "quantity": 4},
		],
	}
	var notes: Array[Dictionary] = []
	var carry: Array[MarketOrder] = MarketSettlement.carry(
		[covered, short], matched, _economies(), {0: 3}, notes
	)
	assert_eq(carry.size(), 1)
	assert_eq(carry[0].id, "covered")
	assert_eq(carry[0].quantity, 3)
	assert_eq(carry[0].filled, 0)
	assert_eq(notes.size(), 1)
	assert_eq(String(notes[0].get("code", "")), "carry_forward_dropped_cargo_insufficient")


## A bid is carried against the crown's trade cargo capacity — its holds less the
## tonnage the colonies ship — not against the holds a previous turn's imports
## used: those tons are spent, so the wiki's carry-forward gate still covers the
## bid (wiki: world-market § Order persistence, § Cargo).
func test_a_carried_bid_keeps_the_holds_the_last_imports_used() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _market_engine_world()
	var economies: Dictionary = _economies()
	MarketOrders.submit(
			market,
		0, "iron", MarketOrder.SIDE_BID, 3,
		{"cargo_free": 3, "treasury": 5000, "buy_price": 80}
	)
	# One hold is free at the close (two went on this turn's imports), and the
	# crown's trade cargo capacity is three: the residual two carry.
	var report: Dictionary = MarketClearing.clear(
		market, world, economies, {0: 1, 1: 4}, {"capacity": {0: 3, 1: 4}}
	)
	var carry: Array = report["carry"]
	assert_eq(carry.size(), 1, "the bid the capacity covers carries")
	var carried: int = 0 if carry.is_empty() else (carry[0] as MarketOrder).quantity
	assert_eq(carried, 2, "the unfilled two carry")
	var codes: Array[String] = []
	for note: Dictionary in report["notes"]:
		codes.append(String(note.get("code", "")))
	assert_false(codes.has("carry_forward_dropped_cargo_insufficient"))


## The same gate still drops a bid the trade cargo capacity cannot cover
## (wiki: world-market § Order persistence — the capacity is insufficient).
func test_a_carried_bid_drops_when_the_trade_capacity_is_short() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _market_engine_world()
	var economies: Dictionary = _economies()
	MarketOrders.submit(
			market,
		0, "iron", MarketOrder.SIDE_BID, 3,
		{"cargo_free": 3, "treasury": 5000, "buy_price": 80}
	)
	var report: Dictionary = MarketClearing.clear(
		market, world, economies, {0: 1, 1: 4}, {"capacity": {0: 1, 1: 4}}
	)
	assert_eq((report["carry"] as Array).size(), 0, "a bid past the capacity drops")
	var codes: Array[String] = []
	for note: Dictionary in report["notes"]:
		codes.append(String(note.get("code", "")))
	assert_true(codes.has("carry_forward_dropped_cargo_insufficient"))


func test_settlement_buy_unit_and_subsidy_read_the_pair() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	assert_eq(
		MarketSettlement.buy_unit(market, "timber", MarketOrder.WORLD, 6, 0),
		market.price("timber")
	)
	assert_eq(MarketSettlement.subsidy_percent({}, 0, 6), 0)
	var diplomacy := DiplomacyState.new()
	diplomacy.set_subsidy(0, 6, 15)
	assert_eq(
		MarketSettlement.subsidy_percent({"diplomacy": diplomacy}, 0, 6), 15
	)
	assert_eq(
		MarketSettlement.subsidy_percent({"diplomacy": diplomacy}, 1, 6), 0,
		"another court does not inherit the step"
	)


func test_settlement_economy_and_purchased_owner_guard() -> void:
	var economies: Dictionary = _economies()
	assert_eq(MarketSettlement.economy(economies, 0), economies[0])
	assert_eq(MarketSettlement.economy({"0": economies[0]}, 0), economies[0])
	assert_eq(MarketSettlement.economy(economies, 9), null)
	assert_eq(MarketSettlement.purchased_owner(null, 0, 0), -1)
	var world: WorldMap = _market_engine_world()
	assert_eq(MarketSettlement.purchased_owner(world, 0, 0), -1)
	var model: MapModel = world.region(0)
	assert_true(model.purchase_tile(Vector2i(0, 0), 0))
	assert_eq(
		MarketSettlement.purchased_owner(world, 0, model.index_of(0, 0)), 0
	)


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
	# 5 filled bids against 10 submitted offers AND the Minor/Tribe harvest that
	# stands on the same book (2 timber units here): the spread's supply side is
	# the whole book (wiki: world-market § Price discovery; issue #730).
	# 0.5 x (5 - 12) / 17 = -20.6%, capped at -20%, so 30 falls to 24.
	assert_eq(market.price("timber"), 24, "5 bids against 10 offers and the 2-unit harvest")

## One unit of demand is a whole side of the book: the clearing publishes the
## formula's ±20% cap, not a damped step (wiki: world-market § Price discovery;
## the denominator's depth stand-in contradicted the published rule).
func test_one_unit_of_clearing_moves_the_price_the_published_step() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _market_engine_world()
	var economies: Dictionary = _economies()
	MarketOrders.submit(
			market,
		0, "iron", MarketOrder.SIDE_BID, 1,
		{"cargo_free": 4, "treasury": 5000, "buy_price": 80}
	)
	MarketClearing.clear(market, world, economies, {0: 4, 1: 4})
	assert_eq(market.price("iron"), 96, "one filled bid at 80: +20% cap")

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

func test_the_trade_volumes_survive_a_save_round_trip() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	assert_eq(market.settle_purchase(economy, "grain", 2, 2, 100), true)
	assert_true(bool(MarketOrders.submit(
		market,
		3, "timber", MarketOrder.SIDE_OFFER, 1,
		{"stock": 4, "buy_price": 30}
	)["ok"]))

	var restored: WorldMarket = WorldMarket.from_dict(market.to_dict())

	assert_eq(restored.bid_volume("grain"), 2)
	assert_eq(restored.bought_units_for(2), 2)
	assert_eq(restored.imports_for(2), {"grain": 2})
	assert_eq(restored.importing_factions(), [2])
	assert_eq(restored.book.volumes.offer_volume("timber"), 1)
	assert_eq(restored.offer_volume("timber"), 1)
	assert_eq(restored.book.volumes.bought_units(), market.book.volumes.bought_units())
	assert_eq(restored.book.volumes.to_dict(), market.book.volumes.to_dict())

func test_a_save_from_before_the_book_held_its_volumes_still_loads() -> void:
	var saved: Dictionary = {
		"prices": {"grain": 44},
		"book": {
			"bids": {"grain": 3},
			"offers": {"timber": 2},
			"bought_by_faction": {"2": 3},
			"imports_by_faction": {"2": {"grain": 3}},
		},
	}

	var restored: WorldMarket = WorldMarket.from_dict(saved)

	assert_eq(restored.price("grain"), 44)
	assert_eq(restored.bid_volume("grain"), 3)
	assert_eq(restored.offer_volume("timber"), 2)
	assert_eq(restored.bought_units_for(2), 3)
	assert_eq(restored.imports_for(2), {"grain": 3})
	# The next turn still clears cleanly, and nothing leaks between markets.
	assert_eq(WorldMarket.with_default_prices().imports_for(2), {})

func test_a_market_saved_with_flat_volumes_still_loads() -> void:
	# The first shape folded the volumes beside the order book, on the market.
	var restored: WorldMarket = WorldMarket.from_dict({
		"book": {"submitted": []},
		"bids": {"grain": 2},
		"offers": {"timber": 1},
		"bought_by_faction": {"1": 2},
		"imports_by_faction": {"1": {"grain": 2}},
	})

	assert_eq(restored.price("grain"), CommodityCatalog.base_price("grain"))
	assert_eq(restored.bid_volume("grain"), 2)
	assert_eq(restored.offer_volume("timber"), 1)
	assert_eq(restored.bought_units_for(1), 2)
	assert_eq(restored.imports_for(1), {"grain": 2})

func test_a_settled_buy_books_the_purse_stock_and_cargo_together() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var purse: int = economy.treasury
	var grain_start: int = economy.quantity("grain")

	assert_true(market.settle_purchase(economy, "grain", 2, 2, 10))
	assert_eq(economy.treasury, purse - 10)
	assert_eq(economy.quantity("grain"), grain_start + 2)
	assert_eq(market.bid_volume("grain"), 2)
	assert_eq(market.imports_for(2), {"grain": 2})
	# A purse that cannot cover the deal moves nothing at all.
	economy.treasury = 3
	var grain: int = economy.quantity("grain")
	assert_false(market.settle_purchase(economy, "timber", 1, 2, 9))
	assert_eq(economy.treasury, 3)
	assert_eq(economy.quantity("timber"), 0)
	assert_eq(economy.quantity("grain"), grain)
	assert_eq(market.bid_volume("timber"), 0)

func test_a_cancelled_offer_gives_its_supply_back_and_never_below_zero() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	MarketOrders.submit(
		market,
		3, "timber", MarketOrder.SIDE_OFFER, 2,
		{"stock": 4, "buy_price": 30}
	)
	var order: MarketOrder = market.book.submitted[0]
	assert_eq(market.offer_volume("timber"), 2)

	assert_true(MarketOrders.cancel(market, 3, order.id))
	assert_eq(market.offer_volume("timber"), 0)
	market.book.volumes.withdraw_offer("timber", 5)
	assert_eq(market.offer_volume("timber"), 0)

func test_one_court_holding_both_sides_is_dropped_by_pair() -> void:
	var rows: Array[MarketOrder] = [
		_order(0, "timber", MarketOrder.SIDE_BID, 2, 1),
		_order(0, "timber", MarketOrder.SIDE_OFFER, 1, 1),
		_order(1, "timber", MarketOrder.SIDE_BID, 2, 1),
		_order(2, "grain", MarketOrder.SIDE_BID, 1, 1),
	]

	var dropped: Dictionary = MarketRules.staged_both_sides(rows)

	assert_eq(dropped.keys(), ["0:timber"])
	assert_eq(MarketRules.order_pair_key(rows[3]), "2:grain")

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
	var reserved: Dictionary = ProductionPhase.reserved_inputs(
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


## One press still files exactly one order, and the batch keys read the same
## verdict the single-head row does (REQ-P5-04).
func test_one_press_files_one_order() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.stockpile["fabric"] = 4
	var result: Dictionary = economy.queue_recruit(WorkerPool.Tier.PEASANT)
	assert_true(bool(result["ok"]))
	assert_eq(int(result["asked"]), 1)
	assert_eq(int(result["queued"]), 1)
	assert_eq(String(result["reason"]), "")
	assert_eq(economy.recruits.total(), 1)


## A batch files as many heads as the purse, the paper and the free peasants
## allow, and names the limit that stopped it (wiki: workers-and-population
## § Recruiting; REQ-P5-04, REQ-P5-05).
func test_a_batch_stops_at_the_purse() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.tech_unlocked = {"apprentice_workers": true, "sugar_refining": true}
	economy.workers.set_count(WorkerPool.Tier.PEASANT, 5)
	economy.treasury = 500
	economy.stockpile["paper"] = 10

	assert_eq(economy.recruit_affordable(WorkerPool.Tier.APPRENTICE), 2, "500 / 200")
	var result: Dictionary = economy.queue_recruit(WorkerPool.Tier.APPRENTICE, 5)
	assert_eq(int(result["queued"]), 2)
	assert_eq(int(result["asked"]), 5)
	assert_eq(String(result["reason"]), "Insufficient treasury")
	assert_eq(economy.recruits.total(), 2, "two orders are filed, not five")
	assert_eq(economy.recruits.reserved_peasants(), 2)
	assert_eq(economy.treasury, 500, "nothing is paid until Build/work")


## The materials row binds before the purse when the paper runs out first.
func test_a_batch_stops_at_the_paper() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.tech_unlocked = {"apprentice_workers": true, "sugar_refining": true}
	economy.workers.set_count(WorkerPool.Tier.PEASANT, 5)
	economy.treasury = 10000
	economy.stockpile["paper"] = 3

	assert_eq(economy.recruit_affordable(WorkerPool.Tier.APPRENTICE), 1, "3 paper / 2")
	var result: Dictionary = economy.queue_recruit(WorkerPool.Tier.APPRENTICE, 4)
	assert_eq(int(result["queued"]), 1)
	assert_eq(String(result["reason"]), "Insufficient materials")


## A trained head takes a peasant, so the free peasants cap the batch too.
func test_a_batch_stops_at_the_peasants() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.tech_unlocked = {"apprentice_workers": true, "sugar_refining": true}
	economy.workers.set_count(WorkerPool.Tier.PEASANT, 2)
	economy.treasury = 10000
	economy.stockpile["paper"] = 10

	assert_eq(economy.recruit_affordable(WorkerPool.Tier.APPRENTICE), 2)
	var result: Dictionary = economy.queue_recruit(WorkerPool.Tier.APPRENTICE, 3)
	assert_eq(int(result["queued"]), 2)
	assert_eq(String(result["reason"]), "Insufficient workers")
	assert_eq(economy.available_peasants(), 0, "both heads are promised")


## A peasant recruit takes no head, so only the fabric bounds the batch.
func test_a_peasant_batch_is_bounded_by_the_fabric() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.stockpile["fabric"] = 5
	assert_eq(economy.recruit_affordable(WorkerPool.Tier.PEASANT), 2, "5 fabric / 2")
	var result: Dictionary = economy.queue_recruit(WorkerPool.Tier.PEASANT, 4)
	assert_eq(int(result["queued"]), 2)
	assert_eq(String(result["reason"]), "Insufficient materials")
	assert_eq(economy.recruits.reserved_peasants(), 0, "a peasant takes no head")


## A locked tier affords nothing, and the batch reports the tech, not a purse.
func test_a_locked_tier_affords_nothing() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.workers.set_count(WorkerPool.Tier.PEASANT, 5)
	economy.treasury = 10000
	economy.stockpile["paper"] = 10
	assert_eq(economy.recruit_affordable(WorkerPool.Tier.APPRENTICE), 0)
	var result: Dictionary = economy.queue_recruit(WorkerPool.Tier.APPRENTICE, 3)
	assert_false(bool(result["ok"]))
	assert_eq(int(result["queued"]), 0)
	assert_eq(String(result["reason"]), "Required technology not unlocked")
	assert_eq(economy.recruits.total(), 0)


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

## The ledger forecasts a turn it has not taken: the phase's own answer, over a
## copy, so asking the question never spends a ration (REQ-P2-03).
func test_consumption_preview_spends_nothing() -> void:
	var pool: WorkerPool = WorkerPool.make(2, 1)
	var stock: Dictionary = {"grain": 3, "meat": 1, "refinedSugar": 1}
	var report: Dictionary = EconomyConsumption.preview(pool, stock, 1)
	assert_eq(stock["grain"], 3, "the preview leaves the larder alone")
	assert_eq(stock["meat"], 1)
	assert_eq(stock["refinedSugar"], 1)
	assert_eq(report["navy_demand"], 2)
	assert_eq(report["fed_workers"], 1, "the navy eats first, then the pool")
	assert_eq(report["strikers"], 2)
	# The same state resolved for real spends exactly what the preview promised.
	var spent: Dictionary = stock.duplicate()
	var real: Dictionary = EconomyConsumption.resolve(pool, spent, 1)
	assert_eq(real["fed_workers"], report["fed_workers"])
	assert_eq(real["strikers"], report["strikers"])
	assert_eq(spent["grain"], 0)

## The phase's larder read is one order, served or not: a pass the caller holds
## answers the forecast's questions (what every mouth wants, who strikes, which
## tier first) and its report is the phase's own, so the dry-run cannot drift
## from the turn that spends (REQ-P2-03, REQ-P3-01).
func test_a_larder_pass_answers_before_it_is_served() -> void:
	var pool: WorkerPool = WorkerPool.make(1, 0, 0, 1)
	var stock: Dictionary = {"grain": 1, "meat": 0, "furHats": 1}
	var larder: EconomyConsumption.Pass = EconomyConsumption.pass_over(pool, stock.duplicate(), 0)
	assert_eq(larder.food_wanted(), 3, "a master eats two, a peasant one")
	assert_eq(larder.food_fed(), 0, "nothing is served yet")
	assert_eq(larder.striking_tier(), WorkerPool.Tier.MASTER, "an empty larder bites from the top")
	larder.serve()
	assert_eq(larder.food_fed(), 1, "one ration feeds the master, not the peasant")
	assert_eq(larder.strikers(), 1)
	assert_eq(larder.striking_tier(), WorkerPool.Tier.MASTER)
	assert_eq(larder.report()["fed_counts"], [1, 0, 0, 0], "the master eats first")
	assert_eq(stock["grain"], 1, "the pass read a copy, the store is untouched")

## The forecast reads a pool the caller already made: arriving recruits stay a
## count of their own, so a caller who built the pool keeps `mouths` straight
## (REQ-P2-03).
func test_larder_reading_takes_a_built_pool() -> void:
	var pool: WorkerPool = WorkerPool.make(3)
	var read: Dictionary = LarderRead.reading(
		pool,
		{"grain": 2, "meat": 0},
		{"army": 1, "ships": 0, "hospital": 0},
		2,
	)
	assert_eq(int(read["mouths"]), 3)
	assert_eq(int(read["arriving"]), 2)
	assert_eq(int(read["strikers"]), 2, "the army eats one ration before the pool")
	assert_eq(int(read["striking_tier"]), WorkerPool.Tier.PEASANT)
	assert_eq(int(read["store_food"]), 2)

## A hand hired in Build/work eats with the court but labours the **next**
## Production phase: the phase that lets a new recruit turn the wheel the turn it
## is hired is a rule the wiki refuses (wiki: workers-and-population
## § Phase placement — same-turn labour is not supported).
func test_a_recruit_labours_the_phase_after_it_lands() -> void:
	var pool: WorkerPool = WorkerPool.make(2)
	var stock: Dictionary = {"grain": 8, "meat": 0}
	# One of the two peasants landed at this turn's Build/work.
	var report: Dictionary = EconomyConsumption.resolve(pool, stock, 0, 0, [], [1, 0, 0, 0])
	assert_eq(int(report["fed_workers"]), 2, "the arrival eats with the court")
	assert_eq(int(report["strikers"]), 0, "and is not a striker")
	assert_eq(int(report["idle_labour"]), 1, "one hand labours now, not two")
	assert_eq(int(report["labour_next_turn"]), 1, "the arrival turns the wheel next turn")
	# The next phase pays it in full: the same pool with nothing arriving.
	var later: Dictionary = EconomyConsumption.resolve(pool, stock, 0)
	assert_eq(int(later["idle_labour"]), 2, "both hands labour once the turn has closed")


## A hungry arrival withholds nothing: only a worker who kept their ration could
## have laboured at all, so a strike is never double-counted as withheld labour.
func test_a_starving_arrival_withholds_no_labour() -> void:
	var report: Dictionary = EconomyConsumption.resolve(
		WorkerPool.make(2), {"grain": 0, "meat": 0}, 0, 0, [], [1, 0, 0, 0]
	)
	assert_eq(int(report["idle_labour"]), 0)
	assert_eq(int(report["labour_next_turn"]), 0, "a striker has no labour to defer")
	assert_eq(int(report["strikers"]), 2)


## The phase budgets Production from the hands it already had: the pool holds the
## hire, but a run only the newcomer could pay for does not start until the next
## turn (wiki: workers-and-population § Phase placement).
func test_the_phase_never_spends_a_recruits_labour_early() -> void:
	# Two peasants in the pool, one of them landed at this turn's Build/work.
	# Lumber asks two labour a run, so only the old hand's labour can pay it.
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.workers = WorkerPool.make(2)
	economy.stockpile = {"grain": 40, "meat": 0, "timber": 4}
	economy.production.set_assignment("lumber", 2)
	var report: Dictionary = EconomyTurn.resolve(
		economy, WorldMarket.with_default_prices(), {}, 0, 0, false, {}, [], "", 0,
		[1, 0, 0, 0],
	)
	var runs: Dictionary = (report.get("production", {}) as Dictionary).get("runs", {})
	assert_eq(int(runs.get("lumber", 0)), 0, "one labour cannot start a two-labour run")
	assert_eq(
		int((report.get("consumption", {}) as Dictionary).get("labour_next_turn", 0)), 1,
		"the hire's labour is the next phase's",
	)
	# With nothing arriving, the same two hands start the run.
	var settled: PlayerEconomy = PlayerEconomy.starting()
	settled.workers = WorkerPool.make(2)
	settled.stockpile = {"grain": 40, "meat": 0, "timber": 4}
	settled.production.set_assignment("lumber", 2)
	var paid: Dictionary = EconomyTurn.resolve(
		settled, WorldMarket.with_default_prices(), {}, 0, 0, false
	)
	var paid_runs: Dictionary = (paid.get("production", {}) as Dictionary).get("runs", {})
	assert_eq(int(paid_runs.get("lumber", 0)), 1, "both hands labour once the turn closed")


## The queue reads the hands it will land, one count per tier, and pays no
## attention to the civilian, regiment and hull orders beside them: only a worker
## joins the pool (wiki: workers-and-population § Phase placement).
func test_the_queue_names_the_hands_it_lands_by_tier() -> void:
	var queue := RecruitQueue.new()
	queue.add(RecruitQueue.KIND_WORKER, str(WorkerPool.Tier.PEASANT))
	queue.add(RecruitQueue.KIND_WORKER, str(WorkerPool.Tier.PEASANT))
	queue.add(RecruitQueue.KIND_WORKER, str(WorkerPool.Tier.APPRENTICE))
	queue.add(RecruitQueue.KIND_REGIMENT, "peasant_levies")
	queue.add(RecruitQueue.KIND_SHIP, "carrack")
	queue.add(RecruitQueue.KIND_CIVILIAN, "builder")
	var arriving: Array[int] = queue.arriving_by_tier()
	assert_eq(arriving.size(), WorkerPool.TIER_COUNT)
	assert_eq(arriving, [2, 1, 0, 0])
	assert_eq(queue.reserved_peasants(), 3, "the train, the muster and the hull promise a peasant")


## Build/work's own records name the hands that actually landed, so a refused
## order — which leaves no record — withholds nothing from the phase it never
## joined (wiki: workers-and-population § Phase placement — an order the turn
## cannot keep is refused at resolution).
func test_only_a_landed_hand_is_counted_arriving() -> void:
	var done: Array[Dictionary] = [
		{"kind": "workerRecruited", "label": "Peasant", "tier": WorkerPool.Tier.PEASANT},
		{"kind": "workerRecruited", "label": "Apprentice", "tier": WorkerPool.Tier.APPRENTICE},
		{"kind": "civilianMustered", "label": "Builder"},
	]
	assert_eq(MapPlayRecruits.arriving_tiers(done), [1, 1, 0, 0])
	assert_eq(
		MapPlayRecruits.arriving_tiers([] as Array[Dictionary]), [0, 0, 0, 0],
		"a turn that landed nothing withholds nothing"
	)


## The crown's phase reads its arrivals from Build/work, not from the queue it
## proposed: an order the turn refused never lands, so it must not take an idle
## worker's labour with it (wiki: workers-and-population § Phase placement).
func test_a_refused_hand_withholds_no_labour() -> void:
	var controller := EconomyController.new()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.workers = WorkerPool.make(2, 2)
	economy.stockpile = {"grain": 40, "meat": 40, "refinedSugar": 4}
	economy.recruits.add(RecruitQueue.KIND_WORKER, str(WorkerPool.Tier.APPRENTICE))
	controller.economy = economy
	controller.market = WorldMarket.with_default_prices()
	# A session with no layers lands nothing: the queued apprentice is refused.
	controller.play = PlaySession.new()
	var report: Dictionary = controller.resolve_turn()
	controller.free()
	assert_eq(economy.workers.count(WorkerPool.Tier.APPRENTICE), 2, "the hire never landed")
	assert_eq(
		int((report["consumption"] as Dictionary).get("idle_labour", -1)),
		economy.workers.labour(),
		"both apprentices still turn the wheel"
	)


## The WORKERS tab's larder reading: the store, every appetite, and the tier a
## shortfall bites first — Masters before Peasants
## (wiki: workers-and-population § Consumption; REQ-P5-06).
func test_larder_forecast_names_the_tier_that_strikes_first() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.workers = WorkerPool.make(1, 0, 0, 1)
	economy.stockpile = {"grain": 1, "meat": 0, "furHats": 1}
	var read: Dictionary = LarderRead.forecast(economy)
	assert_eq(int(read["mouths"]), 2)
	assert_eq(int(read["food"]), 3, "a master eats two, a peasant one")
	assert_eq(int(read["store_food"]), 1)
	assert_eq(int(read["strikers"]), 1)
	assert_eq(int(read["striking_tier"]), WorkerPool.Tier.MASTER, "the master strikes first")
	assert_eq(int(read["food_short"]), 2)
	assert_eq(read["luxury"], {"furHats": 1})
	assert_eq(read["store_luxury"], {"furHats": 1})

## A larder that covers every mouth reads calm, and the luxury appetite is the
## one unit per trained worker the phase deducts
## (wiki: workers-and-population § Consumption).
func test_larder_forecast_covers_a_full_store() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.workers = WorkerPool.make(1, 1)
	economy.stockpile = {"grain": 4, "meat": 4, "refinedSugar": 1}
	var read: Dictionary = LarderRead.forecast(economy)
	assert_eq(int(read["strikers"]), 0)
	assert_eq(int(read["striking_tier"]), -1)
	assert_eq(int(read["food_short"]), 0)
	assert_eq(read["luxury_short"], {})
	assert_eq(read["luxury"], {"refinedSugar": 1})

## A trained worker fed but without their tier luxury strikes too, and the
## reading names the luxury rather than a food shortfall
## (wiki: workers-and-population § Consumption).
func test_larder_forecast_names_a_luxury_shortfall() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.workers = WorkerPool.make(0, 1)
	economy.stockpile = {"grain": 2, "meat": 2, "refinedSugar": 0}
	var read: Dictionary = LarderRead.forecast(economy)
	assert_eq(int(read["food_short"]), 0)
	assert_eq(int(read["strikers"]), 1)
	assert_eq(int(read["striking_tier"]), WorkerPool.Tier.APPRENTICE)
	assert_eq(read["luxury_short"], {"refinedSugar": 1})


## The turn's larder standing is the same dry run the WORKERS tab prints: the
## store's food, the whole larder's slack as a signed figure, and the strikers
## the phase would leave — the reading a crown acts on before it seals the turn
## (wiki: workers-and-population § Consumption; REQ-P5-05, REQ-P5-06).
func test_the_larder_standing_reads_the_store_and_its_slack() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.workers = WorkerPool.make(1, 0, 0, 1)
	economy.stockpile = {"grain": 1, "meat": 0, "furHats": 1}
	var read: Dictionary = LarderRead.standing(economy)
	assert_eq(int(read["food"]), 1, "the store's food, grain and meat together")
	assert_eq(int(read["wanted"]), 3, "a master eats two, a peasant one")
	assert_eq(int(read["slack"]), -2, "the shortfall reads signed")
	assert_eq(int(read["strikers"]), 1)
	assert_eq(int(read["striking_tier"]), WorkerPool.Tier.MASTER)
	economy.stockpile = {"grain": 5, "meat": 5, "furHats": 1}
	var calm: Dictionary = LarderRead.standing(economy)
	assert_eq(int(calm["food"]), 10)
	assert_eq(int(calm["slack"]), 7, "a covered larder reads a surplus")
	assert_eq(int(calm["strikers"]), 0)
	assert_eq(int(calm["striking_tier"]), -1)


## The warning a court hears a turn before the larder bites names what runs
## short and who strikes first, and stays silent on a covered larder. Both forms
## are the wiki's own lines — the food clause is separated from the strike by a
## semicolon, the luxury form keeps the dash (wiki: workers-and-population
## § Consumption; DR-20261119-11; REQ-P5-05, REQ-P5-06).
func test_the_larder_warning_names_what_runs_short() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.workers = WorkerPool.make(1, 0, 0, 1)
	economy.stockpile = {"grain": 1, "meat": 0, "furHats": 1}
	assert_eq(
		LarderRead.warning(LarderRead.standing(economy)),
		"The larder runs short — 2 food; 1 worker will strike at the next close, "
		+ "masters first."
	)
	# A luxury the tier wants with the food covered names the good, not a
	# shortfall in food the store does not have.
	economy.workers = WorkerPool.make(0, 1)
	economy.stockpile = {"grain": 2, "meat": 2, "refinedSugar": 0}
	assert_eq(
		LarderRead.warning(LarderRead.standing(economy)),
		"The larder runs short of Refined Sugar ×1 — 1 worker will strike at the "
		+ "next close, apprentices first."
	)
	economy.stockpile = {"grain": 4, "meat": 4, "refinedSugar": 2}
	assert_eq(LarderRead.warning(LarderRead.standing(economy)), "", "a calm larder is silent")


## A larder that runs short of food and of the luxury on top of it names the
## food first — the phase feeds it before any luxury — and still separates the
## shortfall from the strike with the published semicolon (wiki:
## workers-and-population § Consumption; DR-20261119-11).
func test_the_larder_warning_names_food_before_the_luxury() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.workers = WorkerPool.make(0, 2)
	economy.stockpile = {"grain": 1, "meat": 0, "refinedSugar": 0}
	var read: Dictionary = LarderRead.standing(economy)
	assert_true(int(read["slack"]) < 0, "the store cannot feed the pool")
	var line: String = LarderRead.warning(read)
	assert_true(line.begins_with("The larder runs short — "), line)
	assert_true(line.contains(" food; "), "the food clause takes the published semicolon")
	assert_false(line.contains("Refined Sugar"), "food is named before any luxury")


## The standing's `waiting` flag: the ledger's own projection already counts the
## musters and launches under orders, so the warning reads it with `waiting = false`
## or one mouth would be fed twice (wiki: workers-and-population § Consumption).
func test_the_larder_standing_does_not_feed_a_waiting_muster_twice() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.workers = WorkerPool.make(2)
	economy.stockpile = {"grain": 10, "meat": 0}
	economy.recruits.add(RecruitQueue.KIND_REGIMENT, "pikemen")
	var once: Dictionary = LarderRead.standing(economy, {"army": 2}, false)
	var twice: Dictionary = LarderRead.standing(economy, {"army": 0}, true)
	assert_eq(int(once["wanted"]), int(twice["wanted"]), "one muster, one ration")
	# The muster also takes a peasant: the phase feeds one hand and the regiment.
	assert_eq(int(once["wanted"]), 3, "one peasant, the muster's head and its ration")


## Recruits already under orders eat at the next Consumption, so the forecast
## counts them before the crown presses another row
## (wiki: workers-and-population § Phase placement).
func test_larder_forecast_counts_arriving_recruits() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.workers = WorkerPool.make(1)
	economy.stockpile = {"grain": 2, "meat": 0}
	economy.recruits.add(RecruitQueue.KIND_WORKER, str(WorkerPool.Tier.PEASANT))
	var read: Dictionary = LarderRead.forecast(economy)
	assert_eq(int(read["arriving"]), 1)
	assert_eq(int(read["mouths"]), 2, "the arriving peasant is a mouth too")
	assert_eq(int(read["food"]), 2)
	assert_eq(int(read["strikers"]), 0, "two food feeds both")
	economy.stockpile = {"grain": 1, "meat": 0}
	var thin: Dictionary = LarderRead.forecast(economy)
	assert_eq(int(thin["strikers"]), 1, "one ration, two mouths")

## A regiment and a hull under orders land at Build/work, before Consumption, so
## the larder the WORKERS tab forecasts pays their rations too — the muster roll
## does not show them yet (wiki: workers-and-population § Consumption;
## § Phase placement).
func test_larder_forecast_counts_a_waiting_muster_and_launch() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.workers = WorkerPool.make(4)
	economy.stockpile = {"grain": 40, "meat": 0}
	var read: Dictionary = LarderRead.forecast(economy, {"army": 6, "ships": 1})
	var appetites: Dictionary = read["appetites"]
	assert_eq(int(appetites["army"]), 6)
	assert_eq(int(appetites["navy"]), 2)
	assert_eq(int(appetites["pool"]), 4)
	economy.recruits.add(RecruitQueue.KIND_REGIMENT, "pikemen")
	economy.recruits.add(RecruitQueue.KIND_SHIP, "sloop")
	var waiting: Dictionary = LarderRead.forecast(economy, {"army": 6, "ships": 1})
	var fed: Dictionary = waiting["appetites"]
	assert_eq(
		int(fed["army"]), 6 + RegimentCatalog.food_upkeep("pikemen"),
		"the waiting muster eats its own ration"
	)
	assert_eq(int(fed["navy"]), 4, "one more hull eats two food")
	assert_eq(int(fed["pool"]), 2, "the muster and the launch each reserve a peasant")
	assert_eq(LarderRead.pending_rations(economy), {"army": 2, "ships": 1})

## The waiting muster's ration is enough to turn a calm larder into a striking
## one, so the sheet must name the strike the phase will pay for
## (wiki: workers-and-population § Consumption).
func test_larder_forecast_strikes_for_a_waiting_muster() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.workers = WorkerPool.make(3)
	economy.stockpile = {"grain": 12, "meat": 0}
	var calm: Dictionary = LarderRead.forecast(economy, {"army": 6, "ships": 1})
	assert_eq(int(calm["strikers"]), 0, "6 army + 2 navy + 3 pool = 11 of 12")
	economy.recruits.add(RecruitQueue.KIND_REGIMENT, "pikemen")
	economy.recruits.add(RecruitQueue.KIND_SHIP, "sloop")
	var thin: Dictionary = LarderRead.forecast(economy, {"army": 6, "ships": 1})
	assert_eq(int(thin["strikers"]), 1, "the waiting muster and hull eat four more")
	assert_eq(int(thin["striking_tier"]), WorkerPool.Tier.PEASANT)
	assert_eq(int(thin["store_short"]), 1)

## A waiting train trades a peasant for its tier in Build/work, so the next
## Consumption feeds one mouth, not two: the forecast must spend the peasant the
## order takes or it reads a shortfall the phase will never strike
## (wiki: workers-and-population § Recruiting; § Phase placement).
func test_larder_forecast_spends_the_peasant_a_train_takes() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.workers = WorkerPool.make(1)
	economy.stockpile = {"grain": 1, "meat": 1, "refinedSugar": 1}
	economy.recruits.add(RecruitQueue.KIND_WORKER, str(WorkerPool.Tier.APPRENTICE))
	var read: Dictionary = LarderRead.forecast(economy)
	assert_eq(int(read["mouths"]), 1, "the peasant becomes the apprentice")
	assert_eq(int(read["food"]), 2, "one apprentice ration, not a peasant's too")
	assert_eq(int(read["strikers"]), 0, "the larder covers the one mouth")
	assert_eq(int(read["food_short"]), 0)
	assert_eq(int(read["striking_tier"]), -1)
	assert_eq(read["luxury"], {"refinedSugar": 1})

## A mustered regiment or a launched hull takes a headcount too, so a waiting
## muster is one peasant fewer at the next Consumption
## (wiki: workers-and-population § Military and naval construction).
func test_larder_forecast_counts_a_waiting_muster_as_a_peasant_spent() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.workers = WorkerPool.make(2)
	economy.stockpile = {"grain": 4, "meat": 0}
	economy.recruits.add(RecruitQueue.KIND_REGIMENT, "peasant_levies")
	var read: Dictionary = LarderRead.forecast(economy)
	assert_eq(int(read["mouths"]), 1, "the muster takes one peasant")
	assert_eq(int(read["food"]), 1)
	assert_eq(int(read["strikers"]), 0)

## The other appetites the phase feeds first come from the last resolution, so
## the forecast never promises a ration the army or the navy will take
## (wiki: workers-and-population § Consumption).
func test_larder_forecast_reads_the_other_mouths() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.workers = WorkerPool.make(2)
	economy.stockpile = {"grain": 4, "meat": 0}
	var mouths: Dictionary = LarderRead.mouths(
		{"consumption": {"army_demand": 2, "navy_demand": 2, "hospital_demand": 0}}
	)
	assert_eq(
		mouths, {"army": 2, "ships": 1, "hospital": 0, "wards": [0]},
		"a report without the ward list reads as the one ward its sum says",
	)
	var read: Dictionary = LarderRead.forecast(economy, mouths)
	assert_eq(int(read["strikers"]), 2, "the army and the hull eat before the pool")
	assert_eq(int(read["striking_tier"]), WorkerPool.Tier.PEASANT)
	assert_eq(
		LarderRead.mouths({}), {"army": 0, "ships": 0, "hospital": 0, "wards": []}
	)

## Every appetite the phase pays, in its own deduction order, so the ledger can
## show why a store that covers the pool still strikes it
## (wiki: workers-and-population § Consumption; REQ-P2-03).
func test_larder_reading_names_every_appetite() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.workers = WorkerPool.make(6)
	economy.stockpile = {"grain": 12, "meat": 0}
	var read: Dictionary = LarderRead.forecast(
		economy, {"army": 8, "ships": 2, "hospital": 2}
	)
	assert_eq(int(read["store_food"]), 12)
	assert_eq(
		read["appetites"],
		{"army": 8, "navy": 4, "pool": 6, "wards": 2},
		"army, navy, pool then wards: the phase's own order",
	)
	assert_eq(int(read["strikers"]), 6, "the army and the navy eat the store first")
	assert_eq(int(read["food_short"]), 6)

## A court with no army, navy or ward reads the pool alone, and the appetites
## still add up to the pool's own rations.
func test_larder_reading_with_no_other_mouths() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.workers = WorkerPool.make(3)
	economy.stockpile = {"grain": 5, "meat": 0}
	var read: Dictionary = LarderRead.forecast(economy)
	assert_eq(read["appetites"], {"army": 0, "navy": 0, "pool": 3, "wards": 0})
	assert_eq(int(read["strikers"]), 0, "five grain feeds three peasants")
	assert_eq(int(read["store_short"]), 0)


## The wards eat last and only in whole staffs, so a larder that covers the small
## one behind a big one must feed it: a summed appetite would read a shortfall the
## phase never strikes, and the forecast has to be the phase's own answer
## (wiki: workers-and-population § Consumption; DR-20261112-04; REQ-P2-03).
func test_the_forecast_feeds_the_wards_the_phase_feeds() -> void:
	var pool: WorkerPool = WorkerPool.make(0)
	var store: Dictionary = {"grain": 3}
	var wards: Array[int] = [4, 2]
	var phase: Dictionary = EconomyConsumption.resolve(pool, store.duplicate(), 0, 0, wards)
	assert_eq(int(phase["hospital_fed"]), 2, "the field ward eats, the general one waits")
	var listed: Dictionary = LarderRead.reading(
		pool, store, {"army": 0, "ships": 0, "hospital": 6, "wards": wards}
	)
	var listed_report: Dictionary = listed["report"]
	assert_eq(
		int(listed_report["hospital_fed"]), int(phase["hospital_fed"]),
		"one ward at a time: the forecast spends what the phase spends",
	)
	# The summed appetite, which is all a report without the list carries, would
	# have fed nothing: the list is what keeps the two readers one rule.
	var summed: Dictionary = LarderRead.reading(
		pool, store, {"army": 0, "ships": 0, "hospital": 6}
	)
	assert_eq(int((summed["report"] as Dictionary)["hospital_fed"]), 0)
	assert_eq(int(listed["store_short"]), 3, "six food wanted, three held")


## The store's shortfall is every mouth's, not the pool's: a court that keeps its
## workers fed while the army or a ward goes without is still short
## (wiki: workers-and-population § Consumption — total food demand).
func test_the_store_shortfall_counts_every_mouth() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.workers = WorkerPool.make(2)
	economy.stockpile = {"grain": 3, "meat": 0}
	var read: Dictionary = LarderRead.forecast(
		economy, {"army": 0, "ships": 0, "hospital": 4, "wards": [4]}
	)
	assert_eq(int(read["strikers"]), 0, "the pool ate: no worker strikes")
	assert_eq(int(read["food_short"]), 0, "the pool's own rations were paid")
	assert_eq(int(read["store_short"]), 3, "the ward's rations were not")

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

## The phase keeps what it turned out, so the ledger and the save can read the
## work the court just paid for (wiki: production-recipes § Acceptance Criteria,
## `productionByRecipe`).
func test_the_phase_records_what_the_workshop_made() -> void:
	var economy: PlayerEconomy = _economy(2)
	economy.production.set_assignment("lumber", 1)
	EconomyTurn.resolve(
		economy, WorldMarket.with_default_prices(), {"grain": 10, "timber": 4}, 0
	)
	assert_eq(economy.production.made_units("lumber"), 1)
	assert_eq(economy.production.made_total(), 1)
	assert_eq(economy.production.made_units("steel"), 0, "a row that did not run made nothing")


## A two-turn row is recorded in the phase its unit lands, not the phase it
## started (wiki: production-recipes § Turns per unit; DR-20261113-02).
func test_a_two_turn_batch_is_recorded_when_its_unit_lands() -> void:
	var economy: PlayerEconomy = _economy(2)
	economy.production.set_assignment("steel", 1)
	EconomyTurn.resolve(
		economy, WorldMarket.with_default_prices(), {"grain": 10, "iron": 2, "coal": 2}, 0
	)
	assert_eq(economy.production.made_units("steel"), 0, "the steel is still on the anvil")
	EconomyTurn.resolve(economy, WorldMarket.with_default_prices(), {}, 0)
	assert_eq(economy.production.made_units("steel"), 1, "the landing is the record")


## The end-of-turn projection runs on a copy, so it never rewrites the phase the
## court already lived (REQ-P2-03).
func test_a_projection_does_not_record_the_phase() -> void:
	var economy: PlayerEconomy = _economy(2)
	economy.production.set_assignment("lumber", 1)
	EconomyTurn.project(
		economy, WorldMarket.with_default_prices(), {"grain": 10, "timber": 4}, 0
	)
	assert_eq(economy.production.made, {}, "a preview is not a phase")


## The record rides the save, and a damaged row drops instead of aborting the
## load (wiki: production-recipes § Acceptance Criteria).
func test_the_workshop_record_round_trips_and_drops_junk() -> void:
	var economy: PlayerEconomy = _economy(2)
	economy.production.set_made({"lumber": 3, "steel": 1, "ghost": 2, "bronze": 0})
	assert_eq(economy.production.made, {"lumber": 3, "steel": 1})
	var saved: Dictionary = economy.snapshot()
	assert_eq(saved["production_made"], {"lumber": 3, "steel": 1})
	var restored: PlayerEconomy = PlayerEconomy.starting()
	restored.apply_snapshot(saved)
	assert_eq(restored.production.made_units("lumber"), 3)
	assert_eq(restored.production.made_total(), 4)
	restored.apply_snapshot({"production_made": "junk"})
	assert_eq(restored.production.made, {}, "a damaged record reads as an idle workshop")
	restored.production.set_made({"lumber": {}, "steel": 2})
	assert_eq(restored.production.made, {"steel": 2}, "a count that is not a number drops")


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
	var market: WorldMarket = WorldMarket.with_default_prices()
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
	var first: Dictionary = ProductionPhase.plan(
		[{"recipe": "steel", "units": 2}], stock, 4, {}
	)
	assert_eq(first["runs"], {"steel": 2})
	assert_eq(first["produced"], {})
	assert_eq(first["completed"], {})
	assert_eq(first["consumed"], {"iron": 2, "coal": 2})
	assert_eq(first["labour_used"], 4)
	assert_eq(int(stock.get("steel", 0)), 0, "the steel is still on the anvil")
	assert_eq(ProductionWorkshop.units(first["wip"], "steel"), 2)
	var second: Dictionary = ProductionPhase.plan([], stock, 0, {}, first["wip"])
	assert_eq(second["runs"], {})
	assert_eq(second["completed"], {"steel": 1}, "one unit leaves the workshop a phase")
	assert_eq(second["produced"], {"steel": 1})
	assert_eq(second["labour_used"], 0, "the batch paid its labour when it started")
	assert_eq(int(stock["steel"]), 1)
	assert_eq(ProductionWorkshop.units(second["wip"], "steel"), 1, "the rest still serves")
	var third: Dictionary = ProductionPhase.plan([], stock, 0, {}, second["wip"])
	assert_eq(third["completed"], {"steel": 1})
	assert_eq(int(stock["steel"]), 2)
	assert_eq(third["wip"], {}, "the batch is spent")


## A batch of three started in one phase lands its last unit two phases after the
## first, and the drips cost the workshop nothing beyond what the start paid
## (wiki: production-recipes § Turns per unit; DR-20261113-02).
func test_a_batch_lands_one_unit_a_phase_until_it_is_spent() -> void:
	var stock: Dictionary = {"iron": 3, "coal": 3}
	var landed_at: Array[int] = []
	var wip: Dictionary = ProductionPhase.plan(
		[{"recipe": "steel", "units": 3}], stock, 6, {}
	)["wip"]
	assert_eq(ProductionWorkshop.units(wip, "steel"), 3)
	for _phase in 4:
		var report: Dictionary = ProductionPhase.plan([], stock, 0, {}, wip)
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
	assert_eq(ProductionWorkshop.ready_units(one, "steel", ProductionRecipes.turns("steel")), 1, "one batch, one unit")
	var two: Dictionary = {
		"steel": [{"units": 2, "turns_left": 1}, {"units": 3, "turns_left": 1}],
	}
	assert_eq(
		ProductionWorkshop.ready_units(two, "steel", ProductionRecipes.turns("steel")), 2,
		"a court that leaves the row set starts a batch a phase, and each gives up a unit"
	)
	assert_eq(ProductionWorkshop.units(two, "steel"), 5, "the anvil still holds every unit")
	assert_eq(
		ProductionWorkshop.ready_units({"steel": [{"units": 4, "turns_left": 2}]}, "steel", 2),
		0, "a batch still serving its first turn lands nothing yet"
	)
	assert_eq(ProductionWorkshop.ready_units({}, "steel", 2), 0, "an idle workshop lands nothing")
	assert_eq(
		ProductionWorkshop.ready_units({"lumber": [{"units": 3, "turns_left": 1}]}, "lumber", 1),
		3, "a carried one-turn batch lands whole, as before"
	)


## The wait is the soonest batch: a later batch cannot push the tag past a unit
## that is already one phase from the store (wiki: production-recipes § Turns per
## unit; DR-20261113-02).
func test_the_workshop_wait_reads_the_soonest_batch() -> void:
	assert_eq(
		ProductionWorkshop.soonest(
			{"steel": [{"units": 2, "turns_left": 1}, {"units": 3, "turns_left": 1}]}, "steel"
		),
		1
	)
	assert_eq(
		ProductionWorkshop.soonest(
			{"steel": [{"units": 1, "turns_left": 2}, {"units": 2, "turns_left": 1}]}, "steel"
		),
		1,
		"the soonest batch says when the next unit lands"
	)
	assert_eq(
		ProductionWorkshop.soonest({"steel": [{"units": 4, "turns_left": 2}]}, "steel"), 2
	)
	assert_eq(ProductionWorkshop.soonest({}, "steel"), 0)


## Drip-feeding three steel one unit a phase builds the same output from the same
## inputs as one batch of three, so a batch buys no front-loading.
func test_a_batch_matches_drip_feeding() -> void:
	var batch_stock: Dictionary = {"iron": 3, "coal": 3}
	var drip_stock: Dictionary = {"iron": 3, "coal": 3}
	var batch_wip: Dictionary = ProductionPhase.plan(
		[{"recipe": "steel", "units": 3}], batch_stock, 6, {}
	)["wip"]
	var drip_wip: Dictionary = {}
	for phase in 4:
		batch_wip = ProductionPhase.plan([], batch_stock, 0, {}, batch_wip)["wip"]
		var drip: Array[Dictionary] = []
		if phase < 3:
			drip.append({"recipe": "steel", "units": 1})
		drip_wip = ProductionPhase.plan(drip, drip_stock, 2, {}, drip_wip)["wip"]
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
	var planned: Dictionary = ProductionPhase.plan(
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
	assert_eq(
		totals, {"timber": 1, "grain": 2 + Extraction.CAPITAL_GRAIN_BONUS},
		"the ration estate pays its level doubled (issue #807)"
	)

func test_yields_ignore_tiles_owned_by_others() -> void:
	var model: MapModel = _fixture()
	var totals: Dictionary = Extraction.yields(model, 1, 1)
	assert_eq(totals, {"grain": 2 + Extraction.CAPITAL_GRAIN_BONUS})
	var none: Dictionary = Extraction.yields(model, 2, -1)
	assert_eq(none, {})

func test_capital_bonus_needs_an_owned_capital() -> void:
	var model: MapModel = _fixture()
	var foreign: Dictionary = Extraction.yields(model, 0, 1)
	assert_eq(int(foreign.get("grain", 0)), 2)
	assert_eq(Extraction.yields(null, 0, 0), {})

func test_improved_tiles_use_the_works_level_and_connectivity() -> void:
	var model: MapModel = _fixture()
	var works := LandWorks.new()
	works.set_improvement(model, Vector2i(0, 0), 1)
	var totals: Dictionary = Extraction.yields(model, 0, 0, {}, works, Vector2i(0, 0))
	assert_eq(totals, {"timber": 1, "grain": Extraction.CAPITAL_GRAIN_BONUS})
	# The unimproved grain tile on (1, 0) no longer pays the placeholder level 1.
	var no_works: Dictionary = Extraction.yields(model, 0, 0)
	assert_eq(no_works, {"timber": 1, "grain": 2 + Extraction.CAPITAL_GRAIN_BONUS})

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
		int(controller.readings.extraction().get("grain", 0)),
		2 + Extraction.CAPITAL_GRAIN_BONUS,
		"the harbour carries the estate's grain home"
	)
	var seals := Blockades.new()
	seals.sealed = {model.region_id: {1: true}}
	controller.blockade_source = func() -> Blockades: return seals
	assert_eq(
		int(controller.readings.extraction().get("grain", 0)),
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
	assert_eq(market.prices.size(), 24)
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

## The published ceiling: a deficit may ratchet a price to ten times its default
## and no further, while falling demand still walks it down (wiki: world-market
## § Price discovery; issue #730).
func test_price_is_capped_at_ten_times_base() -> void:
	assert_eq(WorldMarket.next_price(500, 50, 100, 0), 500, "at the ceiling it holds")
	assert_eq(WorldMarket.next_price(490, 50, 100, 0), 500, "a step past it clamps")
	assert_eq(WorldMarket.next_price(500, 50, 0, 100), 400, "demand below the cap still falls")
	assert_eq(WorldMarket.next_price(4, 50, 0, 100), 15, "the floor still holds")

## The Minor/Tribe auto-offer units clear in matching, so they are the spread's
## supply side too: a turn with only auto-offers on the book drives the price
## down (wiki: world-market § Price discovery; issue #730).
func test_auto_offer_units_move_the_spread_down() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	market.advance_prices({"timber": 40})
	assert_eq(int(market.price("timber")), 24, "supply alone: the -20% cap")
	var courts_only: WorldMarket = WorldMarket.with_default_prices()
	courts_only.advance_prices()
	assert_eq(int(courts_only.price("timber")), 30, "no auto-offer row, no move")

## The clearing hands this turn's harvest in: the same turn read through
## `MarketClearing` falls on the Minor's offer with no court bidding.
func test_the_clearing_reads_the_minor_harvest_as_supply() -> void:
	var world: WorldMap = _offer_world()
	var market: WorldMarket = WorldMarket.with_default_prices()
	MarketClearing.clear(market, world, _economies(), {0: 4, 1: 4})
	assert_true(
		int(market.price("timber")) < 30,
		"the Minor's timber offer is a supply row the spread reads",
	)

## One unit of flow is still a full side of the book: the formula caps at ±20%,
## so the smallest trade moves the price as far as a giant one (wiki:
## world-market § Price discovery). A market depth stand-in in the denominator
## used to damp this to 3% and contradicted the published rule.
func test_one_sided_trades_reach_the_published_cap() -> void:
	assert_eq(WorldMarket.next_price(30, 30, 1, 0), 36)
	assert_eq(WorldMarket.next_price(30, 30, 0, 1), 24)
	# A balanced book moves nothing, however small or large.
	assert_eq(WorldMarket.next_price(30, 30, 1, 1), 30)
	assert_eq(WorldMarket.next_price(30, 30, 400, 400), 30)
	# Inside the cap the step is the formula's own share.
	assert_eq(WorldMarket.next_price(30, 30, 2, 1), 35, "0.5 x 1 / 3 = +16.7%")
	assert_eq(WorldMarket.next_price(30, 30, 1, 2), 25, "0.5 x -1 / 3 = -16.7%")

func test_advance_prices_publishes_and_resets_volumes() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
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
	assert_eq(clone.price("timber"), 36, "10 filled bids alone: the +20% cap")
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

## The advanced start rewrites the world the book was published from — colonies
## claimed, estates raised, towns developed — so the rows must be republished:
## a crown opening on turn 100 read the turn-0 harvest (62 timber on the table
## where the auction held 9) and none of the developed towns' manufactures
## (wiki: world-market § Minor and tribe auto-sell; REQ-P2-03, REQ-P5-05).
func test_the_book_is_republished_when_the_world_moves_under_it() -> void:
	var world: WorldMap = _town_world(9, 0, 4, 1)
	var market: WorldMarket = WorldMarket.with_default_prices()
	MinorMarket.publish(market, world, 0)
	assert_eq(MinorMarket.remaining(market.minor_offers, "9:timber"), 4)
	assert_eq(MinorMarket.index_of(market.minor_offers, "9:lumber"), -1)
	# The preset's own move: the town is developed, so its manufactures appear.
	world.region(0).provinces[1].town_development = 2
	assert_eq(
		MinorMarket.index_of(market.minor_offers, "9:lumber"), -1,
		"the stale book hides the town's output"
	)
	var play := PlaySession.new()
	var controller := EconomyController.new()
	controller.market = market
	play.economy = controller
	play.world = world
	MapPlayMarket.republish(play)
	assert_eq(
		market.minor_offers, MinorMarket.emit(world, market, 0),
		"the book names the world it sells"
	)
	assert_eq(
		MinorMarket.remaining(market.minor_offers, "9:lumber"), 1,
		"the developed town is on the book"
	)
	# A session with no ledger, or a ledger with no market, has no book to write.
	MapPlayMarket.republish(null)
	var bare := PlaySession.new()
	MapPlayMarket.republish(bare)
	bare.economy = EconomyController.new()
	MapPlayMarket.republish(bare)

## The advanced start republishes the book once the preset has rewritten the
## world; a session that has no world yet writes no rows and does not crash
## (wiki: world-market § Minor and tribe auto-sell; REQ-P2-03).
func test_an_advanced_start_with_no_world_writes_no_book() -> void:
	var play := PlaySession.new()
	play.advanced_start = AdvancedStart.TURNS100
	var controller := EconomyController.new()
	controller.market = WorldMarket.with_default_prices()
	play.economy = controller
	MapPlayAdvanced.begin(play)
	assert_eq(controller.market.minor_offers, [], "no world, no rows")

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
	assert_eq(by_region.get(1, {}), {"grain": 2})

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

	var line: String = LedgerMarketText.cargo_line(cargo)

	assert_true(line.contains("6 holds"))
	assert_true(line.contains("4 for the colonies"))
	assert_true(line.contains("2 free"))
	assert_true(LedgerMarketText.cargo_line({"holds": 6, "free": 2}).contains("2 free"))

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
	var line: String = LedgerReportText.turn_summary(report)

	assert_true(line.contains("8 colonial tons landed"))
	assert_true(line.contains("2 cast iron made in colonial towns"))
	assert_true(line.contains("2 left on the far shore"))
	assert_false(LedgerReportText.turn_summary({}).contains("colonial towns"))


# --- test_cargo_read ---------------------------------------------------------


## The crossing the holds will make, read before the turn closes: the overseas
## plan's own figures, the stranded tonnage named by commodity and the rule that
## caps it (wiki: ships-and-naval § Cargo holds and capacity; DR-20261116-05;
## REQ-P5-05).
func test_the_crossing_reads_the_plan_before_the_turn_closes() -> void:
	var plan: Dictionary = {
		"holds": 4, "used": 4, "left": {"timber": 3, "grain": 2}, "left_total": 5,
	}
	var read: Dictionary = CargoRead.reading(plan)

	assert_true(bool(read["known"]))
	assert_eq(int(read["holds"]), 4)
	assert_eq(int(read["waiting"]), 9, "every ton the estates yield must cross")
	assert_eq(int(read["crossing"]), 4)
	assert_eq(int(read["stranded"]), 5)
	var goods: Array = read["goods"] as Array
	assert_eq(goods.size(), 2, "every stranded commodity is named")
	var total: int = 0
	for entry: Dictionary in goods:
		total += int(entry["amount"])
	assert_eq(total, 5)
	var richest: String = String(EconomyOverseas.priority(["timber", "grain"])[0])
	assert_eq(
		String((goods[0] as Dictionary)["id"]), richest,
		"richest first — the plan's own shipping order",
	)
	assert_eq(String((goods[1] as Dictionary)["id"]), "grain" if richest == "timber" else "timber")

	var line: String = CargoRead.line(read)
	assert_true(line.contains("9 tons abroad"), line)
	assert_true(line.contains("4 tons cross this turn"), line)
	assert_true(line.contains("5 tons left on the far shore"), line)
	var note: String = CargoRead.note(read)
	assert_true(note.contains("5 more would land the rest"), note)
	assert_true(note.contains("no per-province storage"), note)
	assert_true(note.contains("Left: "), note)


## The reading is the phase's own plan, not a figure of its own: the overseas
## plan's used/left split is what the line prints.
func test_the_crossing_reads_the_overseas_plans_own_split() -> void:
	var read: Dictionary = CargoRead.reading(EconomyOverseas.plan({1: {"timber": 9}}, 4))

	assert_eq(int(read["waiting"]), 9)
	assert_eq(int(read["crossing"]), 4)
	assert_eq(int(read["stranded"]), 5)
	assert_eq((read["goods"] as Array).size(), 1, "one commodity, one entry")
	assert_true(CargoRead.line(read).contains("5 tons left on the far shore"))


## A crown whose home squadron is away (or carries no merchantman) has no holds:
## the reading names that cause instead of only the tonnage it loses.
func test_a_crown_with_no_holds_names_the_merchantmen_it_needs() -> void:
	var read: Dictionary = CargoRead.reading(EconomyOverseas.plan({1: {"timber": 3}}, 0))

	assert_eq(int(read["crossing"]), 0)
	assert_eq(int(read["stranded"]), 3)
	assert_true(CargoRead.line(read).contains("0 tons cross this turn"), CargoRead.line(read))
	var note: String = CargoRead.note(read)
	assert_true(note.contains("merchant hulls are the only holds"), note)
	assert_true(note.contains("Launch a merchant hull"), note)


## The reading appears only when the rule bites: an estate that ships everything,
## a crown with no colonial tonnage and a caller with no world all print nothing.
func test_a_crossing_with_nothing_to_wait_for_prints_nothing() -> void:
	var quiet: Dictionary = CargoRead.reading(EconomyOverseas.plan({}, 4))
	assert_eq(CargoRead.line(quiet), "")
	assert_eq(CargoRead.note(quiet), "")

	var roomy: Dictionary = CargoRead.reading(EconomyOverseas.plan({1: {"timber": 3}}, 8))
	assert_true(CargoRead.line(roomy).contains("3 tons cross this turn"))
	assert_eq(CargoRead.note(roomy), "", "every ton crosses: no wait to name")

	var unknown: Dictionary = CargoRead.reading({})
	assert_false(bool(unknown["known"]))
	assert_eq(CargoRead.line(unknown), "", "no world, no promise")
	assert_eq(CargoRead.note(unknown), "")


## A coast the sea has shut is a rule, not a lean harvest: the despatch names it
## (wiki: capital-and-connectivity § Blockade; REQ-P5-05).
func test_the_turn_summary_names_a_blockaded_coast() -> void:
	var report: Dictionary = {
		"extraction": {"grain": 5},
		"blockade": "Blockaded: Cádiz — nothing there reaches the crown by sea this turn",
	}
	var line: String = LedgerReportText.turn_summary(report)
	assert_true(line.contains("Blockaded: Cádiz"), line)
	assert_true(line.contains("gathered 5 grain"), line)
	assert_false(LedgerReportText.turn_summary({"extraction": {"grain": 5}}).contains("Blockaded"))


## A study the purse cannot pay is a rule with a floor, not a broken purse: the
## turn's own despatch names what stopped it, so a crown that never opens the
## college still learns why (wiki: tech-tree-labour-economy § money_lending,
## banking; REQ-P5-05).
func test_the_turn_summary_names_the_lending_floor_behind_an_unpaid_slot() -> void:
	var lending: Dictionary = {"research": {"unpaid": ["land_enclosure"], "floor": -500}}
	var line: String = LedgerReportText.turn_summary(lending)
	assert_true(line.contains("1 research slot unfunded"), line)
	assert_true(line.contains("the -500 lending floor is reached"), line)

	var borrowing: Dictionary = {"research": {"unpaid": ["a", "b"], "floor": 0}}
	var tied: String = LedgerReportText.turn_summary(borrowing)
	assert_true(tied.contains("2 research slots unfunded"), tied)
	assert_true(tied.contains("research may not borrow"), tied)


## The lane raises the trouble cut only: the harvest, the deliveries and the
## finished study stay on the ledger sheet and the Gazette (wiki: hud-toasts).
func test_the_turn_summary_trouble_cut_keeps_only_what_asks_for_action() -> void:
	var quiet: Dictionary = {
		"extraction": {"grain": 5},
		"overseas": {"used": 2, "manufactured": {"castIron": 1}},
	}
	assert_eq(LedgerReportText.turn_summary(quiet, true), "", "nothing asks for action")

	var trouble: Dictionary = {
		"extraction": {"grain": 5},
		"consumption": {"strikers": 3},
		"hospital": {"hungry": ["Cádiz"]},
	}
	var line: String = LedgerReportText.turn_summary(trouble, true)
	assert_eq(line, "3 on strike  ·  1 hospital unstaffed", line)


## The same rule spelled out for the college and the slot's own hover.
func test_the_floor_text_follows_money_lending_and_banking() -> void:
	assert_true(LedgerReportText.research_floor_line(0).contains("stops at 0 ducats"))
	assert_true(LedgerReportText.research_floor_line(0).contains("Money Lending"))
	assert_true(LedgerReportText.research_floor_line(ResearchFunding.DEBT_FLOOR).contains("-500"))
	assert_true(LedgerReportText.research_floor_line(ResearchFunding.DEBT_FLOOR).contains("Banking"))
	assert_true(
		LedgerReportText.research_floor_line(ResearchFunding.BANK_DEBT_FLOOR).contains("-1,000"),
		"both techs, both figures read as money"
	)
	assert_eq(LedgerReportText.research_floor_note(0), "research may not borrow")
	assert_eq(LedgerReportText.research_floor_note(ResearchFunding.DEBT_FLOOR), "the -500 lending floor is reached")

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

func test_a_fleetless_seat_harbour_grants_one_hold() -> void:
	# A court with no merchant hull still imports one ton from its seat harbour
	# so it can buy the cloth for a first launch (issue #484, DR-20261114-11).
	var world: WorldMap = _trade_cargo_world()
	assert_eq(TradeCargo.capacity(world, {}, 0), TradeCargo.PORT_ALLOWANCE)
	var warships := FleetState.in_port(1, 0, 0, ["w"], {"w": "sloop"})
	assert_eq(TradeCargo.capacity(world, {0: [warships]}, 0), TradeCargo.PORT_ALLOWANCE)
	assert_eq(TradeCargo.fleet_holds(warships), 0)

## The harbour's one hold buys the yard its first cloth; it never carries a
## colony's harvest. A crown with no merchant hull in port at its seat has 0
## crossing holds (wiki: ships-and-naval § Cargo holds and capacity — "the home
## squadron's merchant hulls are the only holds"; "a crown with no seat or no
## squadron there has 0 holds").
func test_the_seat_allowance_is_a_trade_hold_and_never_a_crossing_hold() -> void:
	var world: WorldMap = _trade_cargo_world()
	assert_eq(TradeCargo.capacity(world, {}, 0), TradeCargo.PORT_ALLOWANCE)
	assert_eq(TradeCargo.home_holds(world, {}, 0), 0, "no merchant hull, no crossing")
	var warships := FleetState.in_port(1, 0, 0, ["w"], {"w": "sloop"})
	assert_eq(TradeCargo.capacity(world, {0: [warships]}, 0), TradeCargo.PORT_ALLOWANCE)
	assert_eq(TradeCargo.home_holds(world, {0: [warships]}, 0), 0, "warships carry nothing")
	var merchants := FleetState.in_port(2, 0, 0, ["a"], {"a": "fluyte"})
	assert_eq(TradeCargo.home_holds(world, {0: [merchants]}, 0), 4, "her holds are the crossing")

func test_merchants_away_from_the_seat_do_not_get_the_port_allowance() -> void:
	# Holds that exist but have sortied stay at 0 — the allowance is for a
	# fleetless court, not a home squadron that left the harbour.
	var world: WorldMap = _trade_cargo_world()
	var at_sea := FleetState.at_sea(2, 0, 0, ["c"], {"c": "fluyte"})
	assert_eq(TradeCargo.capacity(world, {0: [at_sea]}, 0), 0)

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
	assert_eq(LedgerMarketText.market_summary({}, 0), "")


## The disband row promises no refund and names what the tier eats
## (wiki: workers-and-population § Disband, § Tiers).



## The disband row promises no refund and names what the tier eats
## (wiki: workers-and-population § Disband, § Tiers).
func test_the_disband_hint_names_the_promise_and_the_saving() -> void:
	var hint: String = LedgerWorkersText.disband_hint(WorkerPool.Tier.APPRENTICE)
	assert_true(hint.contains("no recruit cost is refunded"), hint)
	assert_true(hint.contains("An apprentice eats 2 food"), hint)
	assert_true(hint.contains("a unit of Refined Sugar"), hint)
	var master: String = LedgerWorkersText.disband_hint(WorkerPool.Tier.MASTER)
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
	var line: String = LedgerMarketText.market_summary(report, 0)
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
	var line: String = LedgerMarketText.market_summary(report, 0)
	assert_true(line.contains("sold 1 for 50 ducats"), line)
	assert_true(line.contains("89 ducats in shares"), line)
	# A court with no fills of its own still reads its share.
	var quiet: Dictionary = {"fills": {}, "credits": {"by_gp": {0: 12.0}}}
	assert_true(
		LedgerMarketText.market_summary(quiet, 0).contains("12 ducats in shares"),
		LedgerMarketText.market_summary(quiet, 0),
	)
	assert_eq(LedgerMarketText.share_credit({"credits": {0: 7.6}}, 0), 8, "a bare map is read too")


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
	var line: String = LedgerMarketText.preview(staged)
	assert_true(line.contains("Grain +3"), line)
	assert_true(line.contains("2 orders settle at the auction"), line)
	var one: Dictionary = {"stockpile_delta": {}, "treasury_delta": 0, "staged_orders": 1}
	assert_true(
		LedgerMarketText.preview(one).contains("1 order settles at the auction"),
		LedgerMarketText.preview(one),
	)
	# Nothing staged: the calm line stays exactly as it was.
	assert_eq(
		LedgerMarketText.preview({"stockpile_delta": {}, "treasury_delta": 0}),
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
	assert_eq(LedgerMarketText.market_summary(report, 0), "")


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


# --- Ledger prose (production, workers, market, report) ----------------------


func test_recipe_title_names_the_single_input() -> void:
	var recipe_id: String = ProductionRecipes.available_ids({})[0]
	var title: String = LedgerProductionText.recipe_title(recipe_id)
	assert_true(title.contains(CommodityCatalog.label(ProductionRecipes.output(recipe_id))))
	assert_true(LedgerProductionText.recipe_tooltip(recipe_id).contains("→"))


func test_the_summary_reads_the_report() -> void:
	var economy: PlayerEconomy = PlayerEconomy.new()
	economy.treasury = 1234
	var report: Dictionary = {
		"consumption": {"idle_labour": 3, "strikers": 2, "navy_demand": 5},
	}
	var line: String = LedgerReportText.summary(economy, report)
	assert_true(line.contains("1,234 ducats"))
	assert_true(line.contains("labour 3 /"))
	assert_true(line.contains("strikes 2"))


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
	var line: String = LedgerReportText.summary(economy, report)
	assert_true(line.contains("food need 67"), line)
	assert_eq(LedgerReportText.army_food(report), 41)
	assert_eq(LedgerReportText.army_food({}), 0, "a report with no consumption feeds nobody")



func test_the_preview_reports_deltas_or_calm() -> void:
	assert_eq(LedgerMarketText.preview({}), "Next turn: no stock changes.")
	var line: String = LedgerMarketText.preview(
		{"stockpile_delta": {"grain": 3}, "treasury_delta": -10}
	)
	assert_true(line.contains("+3"))
	assert_true(line.contains("ducats -10"))



func test_the_cargo_banner_covers_three_states() -> void:
	assert_true(LedgerMarketText.cargo_line({}).contains("unknown"))
	var empty: Dictionary = {"holds": 0, "free": 0}
	assert_true(LedgerMarketText.cargo_line(empty).contains("No cargo holds"))
	assert_eq(LedgerMarketText.cargo_color(empty), Palette.GOLD_PALE)
	var laden: Dictionary = {"holds": 4, "free": 1}
	assert_true(LedgerMarketText.cargo_line(laden).contains("4 holds"))
	assert_eq(LedgerMarketText.cargo_color(laden), Palette.TEXT)



func test_report_counters_default_to_zero() -> void:
	assert_eq(LedgerReportText.idle_labour({}), 0)
	assert_eq(LedgerReportText.navy_food({"consumption": {"navy_demand": 7}}), 7)


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
	var line: String = LedgerMarketText.deal_line(deal)
	assert_true(line.contains("at 33"), line)
	assert_true(line.contains("33 ducats"), "the receipt names the ducats paid: %s" % line)


## The Deal Book names the ducats the clearing charged, not the per-unit ask
## multiplied out: the debt is rounded once from the whole deal, so a pact's
## 95% on five tons costs 333 while the ask reads 67 (wiki: world-market
## § Subsidy price adjustment — "never a sum of per-unit roundings"; REQ-P5-05).
func test_a_purchase_line_names_the_ducats_the_clearing_charged() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	market.set_terms(0, {"buy": {"*": 0.95}, "sell": {"*": 1.0}})
	var economies: Dictionary = _economies()
	var buyer: PlayerEconomy = economies[0]
	var before: int = buyer.treasury
	var staged: Dictionary = MarketOrders.submit(
		market,
		0, "copper", MarketOrder.SIDE_BID, 5,
		{"cargo_free": 10, "treasury": before, "buy_price": market.buy_price("copper", 0)}
	)
	assert_true(bool(staged["ok"]), String(staged.get("reason", "")))
	var report: Dictionary = MarketClearing.clear(
		market, _market_engine_world(), economies, {0: 10, 1: 10}
	)
	var deal: Dictionary = {}
	for raw: Variant in report["deals"]:
		if int((raw as Dictionary).get("buyer", -2)) == 0:
			deal = raw
			break
	assert_false(deal.is_empty(), "the world counterparty filled the bid")
	assert_eq(int(deal["quantity"]), 5)
	assert_eq(int(deal["buy_unit"]), 67, "the ask rounds the unit")
	assert_eq(int(deal["cost"]), 333, "the debt rounds the whole deal")
	assert_eq(before - buyer.treasury, 333, "and that is what the purse paid")
	assert_eq(
		LedgerMarketText.deal_line(deal),
		"Bought 5 Copper from the world market at 67 — 333 ducats (rounded from the deal)"
	)


## A purse-truncated deal buys fewer tons than the matcher proposed, so the row
## must carry the settled quantity: the Deal Book would otherwise name tons the
## crown never received (wiki: world-market § Treasury budget for bids — the
## resolver-side clamp; REQ-P5-05).
func test_a_truncated_deal_records_the_tons_it_settled() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var offer := MarketOrder.create(6, "timber", MarketOrder.SIDE_OFFER, 3, 1)
	offer.auto = true
	market.book.submit(offer)
	var economies: Dictionary = _economies()
	var buyer: PlayerEconomy = economies[0]
	buyer.treasury = 100
	var diplomacy := DiplomacyState.new()
	# The surcharge is invisible to the matcher's cap, so the settle truncates.
	diplomacy.set_subsidy(0, 6, 20)
	var staged: Dictionary = MarketOrders.submit(
		market,
		0, "timber", MarketOrder.SIDE_BID, 3,
		{"cargo_free": 10, "treasury": 100, "buy_price": 30}
	)
	assert_true(bool(staged["ok"]), String(staged.get("reason", "")))
	var report: Dictionary = MarketClearing.clear(
		market, null, economies, {0: 10}, {"diplomacy": diplomacy}
	)
	var deal: Dictionary = {}
	for raw: Variant in report["deals"]:
		if int((raw as Dictionary).get("buyer", -2)) == 0:
			deal = raw
			break
	assert_false(deal.is_empty(), "the minor's offer filled the bid")
	assert_eq(int(deal["quantity"]), 2, "two tons fit the purse at the surcharge")
	assert_eq(int(deal["cost"]), 72, "2 x 30 x 1.2, rounded once")
	assert_eq(buyer.quantity("timber"), 2)
	assert_eq(buyer.treasury, 28)
	assert_true(
		LedgerMarketText.deal_line(deal).begins_with("Bought 2 Timber"),
		LedgerMarketText.deal_line(deal)
	)


## The other two Deal Book lines: a sale names its receipt, a favoured fill says
## so, and a legacied row with no `buy_unit` still reads at its published price
## (REQ-P5-05; wiki: world-market § Favored Trading Partner).
func test_the_deal_receipt_reads_a_sale_a_favour_and_an_old_row() -> void:
	assert_eq(
		LedgerMarketText.deal_line({
			"buyer": 1, "seller": 0, "commodity": "timber",
			"quantity": 2, "price": 30, "earned": 60,
		}),
		"Sold 2 Timber to %s at 30 — 60 ducats" % FactionCatalog.name_of(1)
	)
	assert_true(
		LedgerMarketText.deal_line({
			"buyer": 0, "seller": 6, "commodity": "timber",
			"quantity": 1, "price": 30, "is_favoured": true,
		}).ends_with("as its favoured partner")
	)
	assert_eq(
		LedgerMarketText.deal_line({
			"buyer": 0, "seller": 6, "commodity": "timber", "quantity": 1, "price": 30,
		}),
		"Bought 1 Timber from %s at 30 — 30 ducats" % FactionCatalog.name_of(6),
		"a row saved before `buy_unit` reads at the published price"
	)


## A sale whose exports are taxed names the rate that moved the receipt: the
## published price it prints need not multiply to the ducats it earned, so a
## boycotted or pact-bearing crown would otherwise read a line that does not add
## up (wiki: diplomacy § GP–Tribe — Boycott; world-market § FTP; REQ-P5-05).
func test_a_taxed_sale_names_the_rate_that_moved_it() -> void:
	assert_eq(
		LedgerMarketText.deal_line({
			"buyer": 1, "seller": 0, "commodity": "timber",
			"quantity": 10, "price": 25, "earned": 225,
		}),
		"Sold 10 Timber to %s at 25 — 225 ducats (exports 90%%)" % FactionCatalog.name_of(1)
	)
	# An untaxed sale keeps the plain line: nothing moved the price.
	assert_eq(
		LedgerMarketText.deal_line({
			"buyer": 1, "seller": 0, "commodity": "timber",
			"quantity": 10, "price": 25, "earned": 250,
		}),
		"Sold 10 Timber to %s at 25 — 250 ducats" % FactionCatalog.name_of(1)
	)
	# A row with no stake (no tons, no price) names no rate: there is no rate to
	# name, and dividing by it would be the only wrong answer.
	assert_eq(
		LedgerMarketText.deal_line({
			"buyer": 1, "seller": 0, "commodity": "timber", "quantity": 0, "price": 25,
		}),
		"Sold 0 Timber to %s at 25 — 0 ducats" % FactionCatalog.name_of(1)
	)
	assert_eq(
		LedgerMarketText.deal_line({
			"buyer": 1, "seller": 0, "commodity": "timber", "quantity": 3, "price": 0,
		}),
		"Sold 3 Timber to %s at 0 — 0 ducats" % FactionCatalog.name_of(1)
	)


## The clearing's own receipt for a boycotted crown: the 10% the boycott costs
## is named on the line, and the ducats it earned are the taxed ones.
func test_a_boycotted_crowns_sale_receipt_names_the_boycott_rate() -> void:
	var world: WorldMap = _sale_world()
	var market: WorldMarket = WorldMarket.with_default_prices()
	var diplomacy := DiplomacyState.new()
	diplomacy.boycotts["1>0"] = 0
	DiplomacyTrade.apply_terms(diplomacy, world, market)
	var economies: Dictionary = _economies()
	var seller: PlayerEconomy = economies[0]
	seller.add("timber", 10)
	var before: int = seller.treasury
	MarketOrders.submit(
		market, 0, "timber", MarketOrder.SIDE_OFFER, 10, {"stock": 10, "reserved": {}}
	)
	var report: Dictionary = MarketClearing.clear(
		market, world, economies, {0: 4, 1: 4}, {"diplomacy": diplomacy}
	)
	var deal: Dictionary = {}
	for raw: Variant in report["deals"]:
		if int((raw as Dictionary).get("seller", -2)) == 0:
			deal = raw
	assert_false(deal.is_empty(), "the boycotted crown's timber sold")
	var line: String = LedgerMarketText.deal_line(deal, 0)
	assert_true(line.contains("(exports 90%)"), line)
	assert_eq(seller.treasury - before, int(deal.get("earned", 0)), "the receipt is the purse")
	assert_eq(
		int(deal.get("earned", 0)),
		roundi(float(deal.get("price", 0)) * 10.0 * 0.9),
		"the receipt is the published price less the boycott's 10%"
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


## The clearing's price pass is read where the clearing is narrated: a turn that
## moved prices says so, and a quiet market adds no line (wiki: world-market
## § Price discovery; REQ-P5-05).
func test_the_deal_book_names_the_prices_the_clearing_moved() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var ledger := LedgerMarket.new()
	ledger.fill(
		PlayerEconomy.starting(), market, {}, [], {"prices": {"grain": 24, "timber": 27}}, 0
	)
	assert_true(_has_text(ledger, "Prices moved"), "the clearing's prices are read")
	assert_true(
		_has_text(ledger, "%s 24" % CommodityCatalog.label("grain")),
		"the moved good is named with the price it now stands at"
	)
	ledger.free()
	var quiet := LedgerMarket.new()
	quiet.fill(PlayerEconomy.starting(), market, {}, [], {}, 0)
	assert_false(_has_text(quiet, "Prices moved"), "a quiet book adds no line")
	quiet.free()


## The line keeps one row: four goods, then a count of the rest.
func test_the_price_line_caps_its_goods() -> void:
	var moved: Dictionary = {}
	for id: String in ["grain", "timber", "iron", "wool", "coal"]:
		moved[id] = CommodityCatalog.base_price(id)
	var line: String = LedgerMarket.price_moves_line({"prices": moved})
	assert_true(line.begins_with("Prices moved:"), line)
	assert_true(line.ends_with("+1 more."), line)
	# The goods read in name order, so the fifth one is the one left out.
	assert_true(line.contains(CommodityCatalog.label("coal")), line)
	assert_false(
		line.contains(CommodityCatalog.label("wool")), "the fifth good waits"
	)
	assert_eq(LedgerMarket.price_moves_line({}), "", "no move, no line")


## The crossing the holds will make is read on the MARKET page, under the holds
## it spends, with the rule that caps it on the page and not in a hover
## (wiki: ships-and-naval § Cargo holds and capacity; DR-20261116-05;
## REQ-P5-05, REQ-P5-07).
func test_the_market_page_reads_the_crossing_the_holds_will_make() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var cargo: Dictionary = {
		"holds": 4, "used": 4, "reserved": 4, "free": 0, "clear_free": 0, "pending": 0,
		"crossing": CargoRead.reading(
			EconomyOverseas.plan({1: {"timber": 6, "grain": 3}}, 4)
		),
	}
	var ledger := LedgerMarket.new()
	ledger.fill(PlayerEconomy.starting(), market, cargo, [], {}, 0)
	assert_true(_has_text(ledger, "CROSSING"), "the crossing is on the page")
	assert_true(_has_text(ledger, "9 tons abroad"), "the tonnage that waits is named")
	assert_true(
		_has_text(ledger, "no per-province storage"), "the rule sits on the page"
	)
	ledger.free()

	var ashore := LedgerMarket.new()
	ashore.fill(PlayerEconomy.starting(), market, {"holds": 4}, [], {}, 0)
	assert_false(_has_text(ashore, "CROSSING"), "no overseas tonnage, no line")
	ashore.free()


## Any label under `root` whose text contains `needle`.
func _has_text(root: Node, needle: String) -> bool:
	var label := root as Label
	if label != null and label.text.contains(needle):
		return true
	for child: Node in root.get_children():
		if _has_text(child, needle):
			return true
	return false


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
	var plate := LedgerOffers.new()
	plate.fill([{
		"id": "6:timber", "faction": 6, "commodity": "timber",
		"quantity": 1, "unit_price": 33,
	}], {})
	var bids: Array[Button] = plate.offer_buttons()
	assert_eq(bids.size(), 1)
	var buy: Button = bids[0]
	assert_eq(buy.text, "Bid")
	assert_true(buy.tooltip_text.contains("ask of 33"), buy.tooltip_text)
	plate.free()


## The Deal Book prices every commodity row for the crown reading it: a court
## sailing as England must not read Spain's trade terms (wiki: world-market
## § Subsidy price adjustment — "trade terms still stack"; REQ-P2-03, REQ-P5-05).
func test_the_deal_book_prices_its_rows_for_the_viewing_crown() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	market.set_terms(1, {"buy": {"*": 0.9}, "sell": {"*": 1.1}})
	var english := LedgerMarket.new()
	english.fill(PlayerEconomy.starting(), market, {"free": 2}, [], {}, 1)
	var bid: Button = _bid_for(english, CommodityCatalog.label("grain"))
	assert_not_null(bid, "the grain row offers a bid")
	assert_true(
		bid.tooltip_text.contains("at %d ducats" % market.buy_price("grain", 1)),
		bid.tooltip_text
	)
	assert_false(
		bid.tooltip_text.contains("at %d ducats" % market.buy_price("grain", 0)),
		"the row must not read the default crown's terms: %s" % bid.tooltip_text
	)
	english.free()


## A staged order's notional is the crown's own price, not the default crown's
## (wiki: world-market § Trade orders; REQ-P2-03).
func test_a_staged_order_is_valued_at_the_viewing_crowns_terms() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	market.set_terms(1, {"buy": {"*": 0.9}, "sell": {"*": 1.1}})
	var order: MarketOrder = MarketOrder.create(1, "timber", MarketOrder.SIDE_OFFER, 2, 1)
	var ledger := LedgerMarket.new()
	ledger.fill(PlayerEconomy.starting(), market, {}, [], {}, 1)
	var row: Control = ledger._staged_row(order)
	var notional: Label = row.get_child(3) as Label
	assert_eq(notional.text, "%d" % (market.sell_price("timber", 1) * 2))
	assert_ne(notional.text, "%d" % (market.sell_price("timber", 0) * 2))
	row.free()
	ledger.free()


## The clearing republishes the Minor/Tribe book for the crown that will read
## it: a court sailing as England must not be quoted Spain's terms
## (wiki: world-market § Subsidy price adjustment; REQ-P2-03, REQ-P5-05).
func test_the_clearing_publishes_the_minor_book_for_the_reading_crown() -> void:
	var world: WorldMap = _offer_world()
	var market: WorldMarket = WorldMarket.with_default_prices()
	market.set_terms(1, {"buy": {"*": 0.9}, "sell": {"*": 1.0}})
	MarketClearing.clear(market, world, _economies(), {0: 4, 1: 4}, {"viewer": 1})
	# The harvest on the book moves the price before the book is republished, so
	# both readings are taken against the price the clearing left (issue #730).
	var published: int = market.price("timber")
	var english: Dictionary = market.minor_offers[
		MinorMarket.index_of(market.minor_offers, "6:timber")
	]
	assert_eq(int(english["unit_price"]), roundi(float(published) * 0.9), "England reads her own terms")
	MarketClearing.clear(market, world, _economies(), {0: 4, 1: 4})
	var spain: Dictionary = market.minor_offers[
		MinorMarket.index_of(market.minor_offers, "6:timber")
	]
	assert_eq(int(spain["unit_price"]), market.price("timber"), "no viewer keeps the published price")


## The Bid button of one commodity row, found by the good its tooltip names.
func _bid_for(node: Node, label: String) -> Button:
	var button := node as Button
	if button != null and button.text == "Bid" and button.tooltip_text.contains(label):
		return button
	for child: Node in node.get_children():
		var found: Button = _bid_for(child, label)
		if found != null:
			return found
	return null


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


## A court saving for a commitment its purse cannot reach does not sit on a hoard
## it is not about to spend: the comfort reserve stops holding back the stock the
## allocator did not claim, so the hoard becomes the purse it is saving for
## (wiki: treasury-planner § Lock-recovery; issue #489).
func test_a_saving_court_liquidates_the_hoard_it_cannot_use() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.treasury = 100
	# Under market.sell_reserve (20): a spending pass offers nothing; a saving
	# pass that sees the trapped hoard sells it (issue #489).
	economy.stockpile = {"wool": 15}
	var market := WorldMarket.with_default_prices()
	var spending: Dictionary = AiMarketPlanner.plan(_ai_config(), economy, market, 0)
	assert_eq(_offer_of(spending, "wool"), 0, "a spending court keeps market.sell_reserve")
	var saving: Dictionary = AiMarketPlanner.plan(
		_ai_config(), economy, market, 0, {}, {}, {}, 2400, 0, true
	)
	assert_eq(
		_offer_of(saving, "wool"), 10,
		"a saving court sells a trapped hoard down to market.max_offer_units"
	)
	# A saving court with a normal surplus still keeps the comfort reserve —
	# only the trapped shape liquidates.
	economy.stockpile = {"wool": 25}
	var loose: Dictionary = AiMarketPlanner.plan(
		_ai_config(), economy, market, 0, {}, {}, {}, 2400, 0, true
	)
	assert_eq(_offer_of(loose, "wool"), 5, "a loose surplus keeps market.sell_reserve")


## The row the next regiment is provisioned with is claimed before the market
## sees the stock, so a saving court never sells the cloth its muster needs
## (wiki: growth-stage-planner § Recruitment modulation).
func test_a_saving_court_keeps_the_row_its_muster_needs() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.treasury = 100
	economy.stockpile = {"wool": 25}
	var market := WorldMarket.with_default_prices()
	var saving: Dictionary = AiMarketPlanner.plan(
		_ai_config(), economy, market, 0, {}, {}, {"wool": 20}, 2400, 0, true
	)
	assert_eq(_offer_of(saving, "wool"), 5, "the muster's own row stays in the store")


## Saving for a muster never sells the court's dinner: food keeps its comfort
## reserve in lock-recovery, exactly as it does for a starving court
## (wiki: workers-and-population § Consumption).
func test_a_saving_court_never_sells_its_own_dinner() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.treasury = 100
	economy.stockpile = {"grain": 25}
	var market := WorldMarket.with_default_prices()
	var saving: Dictionary = AiMarketPlanner.plan(
		_ai_config(), economy, market, 0, {}, {}, {}, 2400, 0, true
	)
	assert_eq(_offer_of(saving, "grain"), 5, "the ration reserve still applies")


## The larder reading the lock-recovery gate is built on: both ration
## commodities, and nothing else in the stockpile — the Consumption phase's own
## count, never a second sum (issue #489; REQ-P2-03).
func test_the_larder_reading_counts_only_food() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.stockpile = {"grain": 7, "meat": 3, "wool": 40, "timber": 12}
	assert_eq(EconomyConsumption.food_available(economy.stockpile), 10)
	assert_eq(EconomyConsumption.food_available({}), 0)


## The debt is rounded once from the whole deal, so the per-unit charge cannot
## say whether one more ton fits: a subsidised deal whose total rounds past the
## purse must settle the tons that do fit. Before, the truncation re-derived the
## size from the rounded unit price, landed on the same quantity, and the payment
## was refused with the deal still booked — the crown paid nothing, received
## nothing, and the Deal Book named a purchase that never happened (wiki:
## world-market § Treasury budget for bids — the resolver-side clamp;
## § Subsidy price adjustment; REQ-P5-05).
func test_a_deal_whose_whole_total_rounds_past_the_purse_settles_what_fits() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	# 42 x 1.15 = 48.3: the whole-deal total rounds above the unit charge.
	market.prices["lumber"] = 42
	var offer := MarketOrder.create(6, "lumber", MarketOrder.SIDE_OFFER, 3, 1)
	offer.auto = true
	market.book.submit(offer)
	var economies: Dictionary = _economies()
	var buyer: PlayerEconomy = economies[0]
	buyer.treasury = 144
	var diplomacy := DiplomacyState.new()
	diplomacy.set_subsidy(0, 6, 15)
	var staged: Dictionary = MarketOrders.submit(
		market,
		0, "lumber", MarketOrder.SIDE_BID, 3,
		{"cargo_free": 10, "treasury": 144, "buy_price": 42}
	)
	assert_true(bool(staged["ok"]), String(staged.get("reason", "")))
	var report: Dictionary = MarketClearing.clear(
		market, null, economies, {0: 10}, {"diplomacy": diplomacy}
	)
	var deal: Dictionary = {}
	for raw: Variant in report["deals"]:
		if int((raw as Dictionary).get("buyer", -2)) == 0:
			deal = raw
			break
	assert_false(deal.is_empty(), "the minor's offer filled the bid")
	# 3 x 42 x 1.15 = 144.9 -> 145, one ducat past the purse; 2 tons are 97.
	assert_eq(int(deal["quantity"]), 2, "only the tons the whole total covers")
	assert_eq(int(deal["cost"]), 97, "2 x 42 x 1.15, rounded once")
	assert_eq(buyer.quantity("lumber"), 40 + 2, "the goods actually landed")
	assert_eq(buyer.treasury, 47, "and the purse paid exactly the deal total")
	var mine: Dictionary = (report["fills"] as Dictionary).get(0, {}) as Dictionary
	assert_eq(int(mine.get("bought", 0)), 2, "the fills row names the settled tons")
	assert_eq(int(mine.get("spent", 0)), 97, "and the ducats that left the purse")
	var truncation: Dictionary = {}
	for raw: Variant in report["notes"]:
		if String((raw as Dictionary).get("code", "")) == "bid_partial_fill_treasury_insufficient":
			truncation = raw
	assert_false(truncation.is_empty(), "the Deal Book can audit the truncation")
	assert_eq(int(truncation.get("quantity", 0)), 1, "the one ton the purse could not buy")


## A purse that cannot pay even the whole-deal rounding of one ton buys nothing:
## the seller keeps the goods and the row names no ducats (wiki: world-market
## § Treasury budget for bids; REQ-P5-05 never a silent outcome).
func test_a_deal_the_purse_cannot_pay_hands_nothing_over() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	market.prices["lumber"] = 42
	var offer := MarketOrder.create(6, "lumber", MarketOrder.SIDE_OFFER, 2, 1)
	offer.auto = true
	market.book.submit(offer)
	var economies: Dictionary = _economies()
	var buyer: PlayerEconomy = economies[0]
	buyer.treasury = 45
	var diplomacy := DiplomacyState.new()
	diplomacy.set_subsidy(0, 6, 15)
	# The validator knows the published 42, so the bid is admitted; the clearing
	# charges 48 a ton at the surcharge, which the purse cannot cover.
	MarketOrders.submit(
		market,
		0, "lumber", MarketOrder.SIDE_BID, 1,
		{"cargo_free": 10, "treasury": 45, "buy_price": 42}
	)
	var report: Dictionary = MarketClearing.clear(
		market, null, economies, {0: 10}, {"diplomacy": diplomacy}
	)
	assert_eq(buyer.treasury, 45, "nothing left the purse")
	assert_eq(buyer.quantity("lumber"), 40, "and nothing landed")
	assert_true(
		(report["fills"] as Dictionary).get(0, {}).is_empty(),
		"a deal that never paid is no fill"
	)
	for raw: Variant in report["deals"]:
		assert_ne(
			int((raw as Dictionary).get("buyer", -2)), 0,
			"nor a booked sale: %s" % str(raw)
		)


## Prices are a non-negative integer band: a legacy save that wrote a negative
## entry loads it as zero rather than publishing a price no deal ever charged
## (wiki: world-market § Price discovery).
func test_a_legacy_negative_price_loads_as_zero() -> void:
	var market: WorldMarket = WorldMarket.from_dict({
		"prices": {"timber": -5, "lumber": 60, "meat": 0},
	})
	assert_eq(market.price("timber"), 0, "the negative entry clamps to zero")
	assert_eq(market.price("lumber"), 60, "a published price survives")
	assert_eq(market.price("meat"), 0, "and a legal floor stays where it is")

# --- the crown's bid budget ---

## The crown's bid budget: the purse the turn's auction may spend once the waiting
## Build/work orders are paid (wiki: world-market § Treasury budget for bids;
## DR-20261115-13). One boot for the projection, the validator's refusal and the ledger
## line.

const TIMBER_PRICE: int = 30


func _bid_economy(treasury: int = PlayerEconomy.START_TREASURY) -> PlayerEconomy:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.treasury = treasury
	return economy


func _market() -> WorldMarket:
	return WorldMarket.with_default_prices()


func test_no_waiting_order_leaves_the_whole_purse() -> void:
	var economy: PlayerEconomy = _bid_economy(2500)
	var reading: Dictionary = MarketBudget.budget(economy)
	assert_eq(int(reading["treasury"]), 2500)
	assert_eq(int(reading["promised"]), 0)
	assert_eq(int(reading["budget"]), 2500)
	assert_eq(MarketBudget.projected_non_bid_delta(economy), 0)
	assert_true(LedgerMarketText.bid_budget_line(reading).contains("whole purse"))


func test_a_waiting_hull_is_promised_before_the_auction() -> void:
	var economy: PlayerEconomy = _bid_economy(10000)
	economy.queue_build(RecruitQueue.KIND_SHIP, "carrack")
	var reading: Dictionary = MarketBudget.budget(economy)
	assert_eq(int(reading["promised"]), ShipEconomy.treasury_cost("carrack"))
	assert_eq(int(reading["budget"]), 10000 - ShipEconomy.treasury_cost("carrack"))
	assert_eq(
		MarketBudget.projected_non_bid_delta(economy),
		-ShipEconomy.treasury_cost("carrack")
	)


func test_each_kind_is_priced_by_its_own_catalog() -> void:
	var economy: PlayerEconomy = _bid_economy(20000)
	economy.queue_build(RecruitQueue.KIND_WORKER, "1")
	economy.queue_build(RecruitQueue.KIND_CIVILIAN, "builder")
	economy.queue_build(RecruitQueue.KIND_REGIMENT, RegimentCatalog.DEFAULT_TYPE)
	economy.queue_build(RecruitQueue.KIND_SHIP, "carrack")
	var expected: int = (
		int(WorkerPool.recruit_cost(1)["treasury"])
		+ CivilianCatalog.treasury_cost("builder")
		+ RegimentCatalog.treasury_cost(RegimentCatalog.DEFAULT_TYPE)
		+ ShipEconomy.treasury_cost("carrack")
	)
	assert_eq(MarketBudget.promised(economy), expected)
	var rows: Array[Dictionary] = MarketBudget.pending(economy)
	assert_eq(rows.size(), 4)
	assert_eq(String(rows[0]["label"]), WorkerPool.tier_one(1))
	assert_eq(String(rows[3]["label"]), ShipStats.display_name("carrack"))


func test_an_unknown_order_costs_nothing() -> void:
	assert_eq(MarketBudget.order_cost("bogus", "nothing"), 0)
	assert_eq(MarketBudget.order_label("bogus", "nothing"), "")


func test_a_missing_ledger_asks_nothing_of_the_purse() -> void:
	assert_eq(MarketBudget.pending(null).size(), 0)
	assert_eq(MarketBudget.promised(null), 0)
	var reading: Dictionary = MarketBudget.budget(null)
	assert_eq(int(reading["treasury"]), 0)
	assert_eq(int(reading["budget"]), 0)


func test_a_promise_beyond_the_purse_leaves_nothing_to_bid() -> void:
	var economy: PlayerEconomy = _bid_economy(2500)
	economy.queue_build(RecruitQueue.KIND_SHIP, "carrack")
	var reading: Dictionary = MarketBudget.budget(economy)
	assert_eq(int(reading["budget"]), 0)
	assert_true(LedgerMarketText.bid_budget_line(reading).contains("nothing this turn"))


## A purse in debt is named as debt: the college's lending floor (Money Lending
## with Banking) can leave the crown owing more than it holds, and "the whole
## purse — 0 ducats" would print a sum it does not hold (wiki:
## tech-tree-labour-economy § banking; world-market § Treasury budget for bids;
## REQ-P5-05).
func test_a_purse_in_debt_is_named_as_debt_not_an_empty_purse() -> void:
	var economy: PlayerEconomy = _bid_economy(-925)
	var reading: Dictionary = MarketBudget.budget(economy)
	assert_eq(int(reading["purse"]), -925, "the crown's own balance keeps its debt")
	assert_eq(int(reading["treasury"]), 0, "the auction still spends max(0, treasury)")
	assert_eq(int(reading["budget"]), 0)
	var line: String = LedgerMarketText.bid_budget_line(reading)
	assert_true(line.contains("925 ducats in debt"), line)
	assert_false(line.contains("whole purse"), line)


## The same purse with orders already promised names both debts, so the crown
## reads where the money went (REQ-P5-05).
func test_a_purse_in_debt_names_the_orders_it_also_owes() -> void:
	var economy: PlayerEconomy = _bid_economy(-925)
	economy.queue_build(RecruitQueue.KIND_SHIP, "carrack")
	var line: String = LedgerMarketText.bid_budget_line(MarketBudget.budget(economy))
	assert_true(line.contains("925 ducats in debt"), line)
	assert_true(line.contains("promised to 1 waiting order"), line)


## The dead Bid press names the debt that shut it rather than the rules in the
## abstract (wiki: world-market § Treasury budget for bids; REQ-P5-05).
func test_the_bid_press_names_a_purse_in_debt() -> void:
	var built: Dictionary = MarketRow.build(
		"timber", 0, 0, {"free": 4}, _market(), 0,
		{
			"cargo_free": 4,
			"treasury": -925,
			"tech_unlocked": {},
			"projected_non_bid_delta": 0,
			"reserved": {},
		},
		false,
		func(_commodity: String, _quantity: int, _is_buy: bool) -> void: pass
	)
	var row: Node = built["row"] as Node
	var bid: Button = _bid_press(row)
	assert_not_null(bid, "the row draws a Bid press")
	assert_true(bid.disabled, "a purse in debt buys nothing")
	assert_true(bid.tooltip_text.contains("925 ducats in debt"), bid.tooltip_text)
	row.free()


## The first Bid press under `node`, so a row's own words can be read.
func _bid_press(node: Node) -> Button:
	for child: Node in node.get_children():
		if child is Button and (child as Button).text.strip_edges() == "Bid":
			return child as Button
		var found: Button = _bid_press(child)
		if found != null:
			return found
	return null


## True when the row prints `text` on a line of its own, so a test reads what a
## phone player sees instead of a hover (REQ-P1-05).
func _prints(node: Node, text: String) -> bool:
	var label := node as Label
	if label != null and label.text == text:
		return true
	for child: Node in node.get_children():
		if _prints(child, text):
			return true
	return false


## The reading every market row of one repaint shares, as the page hands it in.
func _row_ctx(overrides: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {
		"cargo_free": 4,
		"treasury": 1000,
		"tech_unlocked": {},
		"projected_non_bid_delta": 0,
		"reserved": {},
	}
	for key: Variant in overrides.keys():
		out[key] = overrides[key]
	return out


func _row(id: String, ctx: Dictionary) -> Dictionary:
	return MarketRow.build(
		id, 0, 0, {"free": int(ctx.get("cargo_free", 0))}, _market(), 0, ctx, false,
		func(_commodity: String, _quantity: int, _is_buy: bool) -> void: pass
	)


## A phone player has no hover: the reason the Bid is shut is printed under the
## row it shuts, in the rules' own words (wiki: world-market § Trade orders —
## validation rules; REQ-P1-05, REQ-P5-05).
func test_the_bid_press_prints_the_holds_that_shut_it() -> void:
	var built: Dictionary = _row("timber", _row_ctx({"cargo_free": 0}))
	var row: Node = built["row"] as Node
	assert_true(_bid_press(row).disabled, "no holds, no bid")
	assert_true(_prints(row, "No cargo holds free this turn"), "the row says why")
	row.free()


## The bid-type cap is a rule the row can name: a court already bidding on three
## commodities reads why the fourth is shut (wiki: world-market § Trade orders —
## bid type cap; REQ-P5-05).
func test_the_bid_press_prints_the_bid_type_cap() -> void:
	var market: WorldMarket = _market()
	for id: String in ["timber", "iron", "wool"]:
		var staged: Dictionary = MarketOrders.submit(
			market, 0, id, MarketOrder.SIDE_BID, 1, {"cargo_free": 8, "treasury": 9000}
		)
		assert_true(bool(staged["ok"]), String(staged.get("reason", "")))
	var built: Dictionary = MarketRow.build(
		"grain", 0, 0, {"free": 4}, market, 0, _row_ctx({"treasury": 9000}), false,
		func(_commodity: String, _quantity: int, _is_buy: bool) -> void: pass
	)
	var row: Node = built["row"] as Node
	assert_true(_bid_press(row).disabled, "the fourth commodity waits")
	assert_true(_prints(row, "A crown may bid on 3 commodities a turn."), "the cap is named")
	row.free()


## One side per commodity: a court that already offered the good reads why its
## Bid is shut rather than a rule in the abstract (wiki: world-market § Trade
## orders — mutual exclusion; REQ-P5-05).
func test_the_bid_press_prints_the_other_side_already_staged() -> void:
	var market: WorldMarket = _market()
	var offer: Dictionary = MarketOrders.submit(
		market, 0, "timber", MarketOrder.SIDE_OFFER, 1, {"stock": 4}
	)
	assert_true(bool(offer["ok"]), String(offer.get("reason", "")))
	var built: Dictionary = MarketRow.build(
		"timber", 4, 0, {"free": 4}, market, 0, _row_ctx(), false,
		func(_commodity: String, _quantity: int, _is_buy: bool) -> void: pass
	)
	var row: Node = built["row"] as Node
	assert_true(_bid_press(row).disabled, "one side per commodity")
	assert_true(
		_prints(row, "A court may bid or offer a commodity, never both in one turn."),
		"the exclusion is named"
	)
	row.free()


## A purse that cannot pay one whole ton says so, with the price it cannot meet
## (wiki: world-market § Treasury budget for bids; REQ-P5-05).
func test_the_bid_press_prints_a_purse_that_pays_no_whole_ton() -> void:
	var built: Dictionary = _row("timber", _row_ctx({"treasury": 10}))
	var row: Node = built["row"] as Node
	assert_true(_bid_press(row).disabled, "ten ducats buy no thirty-ducat ton")
	assert_true(_prints(row, "The purse leaves no whole ton at 30 ducats."), "the price is named")
	row.free()


## The debt the banner names is printed on the row too, not only in the hover
## (wiki: world-market § Treasury budget for bids; REQ-P5-05).
func test_the_bid_press_prints_a_purse_in_debt() -> void:
	var built: Dictionary = _row("timber", _row_ctx({"treasury": -925}))
	var row: Node = built["row"] as Node
	assert_true(_prints(row, "The purse is 925 ducats in debt."), "the debt is printed")
	row.free()


## One walk: the gates the row prints are the gates the order path enforces, so
## a dead press can never name a rule the validator does not (REQ-P2-03).
func test_the_bid_gates_are_the_validators_own() -> void:
	var market: WorldMarket = _market()
	var holds: Dictionary = MarketRules.bid_gates(
		market, 0, "timber", {"cargo_free": 0, "treasury": 500}
	)
	var refused: Dictionary = MarketOrders.submit(
		market, 0, "timber", MarketOrder.SIDE_BID, 1, {"cargo_free": 0, "treasury": 500}
	)
	assert_eq(String(holds["code"]), String(refused["code"]))
	assert_eq(String(holds["reason"]), String(refused["reason"]))
	var rich: Dictionary = MarketRules.bid_gates(market, 0, "gold", {"cargo_free": 4})
	assert_eq(String(rich["code"]), "trade_order_riches_excluded")
	assert_true(MarketRules.bid_gates(market, 0, "timber", {"cargo_free": 4})["ok"])


## A row the rules leave room for prints no refusal, so the sheet stays quiet
## where the Bid works (REQ-P1-07).
func test_a_bid_the_rules_allow_prints_no_refusal() -> void:
	var built: Dictionary = _row("timber", _row_ctx())
	var row: Node = built["row"] as Node
	assert_false(_bid_press(row).disabled, "four holds and a purse buy a ton")
	assert_false(_prints(row, "No cargo holds free this turn"))
	row.free()


func test_a_bid_the_promise_cannot_cover_is_refused() -> void:
	var economy: PlayerEconomy = _bid_economy(10000)
	economy.queue_build(RecruitQueue.KIND_SHIP, "carrack")
	var market: WorldMarket = _market()
	var context: Dictionary = {
		"cargo_free": 200,
		"treasury": economy.treasury,
		"buy_price": TIMBER_PRICE,
		"projected_non_bid_delta": MarketBudget.projected_non_bid_delta(economy),
	}
	var greedy: Dictionary = MarketOrders.submit(
		market, 0, "timber", MarketOrder.SIDE_BID, 100, context
	)
	assert_false(bool(greedy["ok"]))
	assert_eq(String(greedy["code"]), "trade_order_bid_exceeds_treasury_budget")
	assert_true(String(greedy["reason"]).contains("waiting orders"))
	var modest: Dictionary = MarketOrders.submit(
		market, 0, "timber", MarketOrder.SIDE_BID, 1, context
	)
	assert_true(bool(modest["ok"]), "one ton fits the purse the hull leaves")


func test_the_same_bid_clears_without_a_waiting_order() -> void:
	var economy: PlayerEconomy = _bid_economy(10000)
	var market: WorldMarket = _market()
	var result: Dictionary = MarketOrders.submit(
		market, 0, "timber", MarketOrder.SIDE_BID, 100,
		{
			"cargo_free": 200,
			"treasury": economy.treasury,
			"buy_price": TIMBER_PRICE,
			"projected_non_bid_delta": MarketBudget.projected_non_bid_delta(economy),
		}
	)
	assert_true(bool(result["ok"]), "an uncommitted purse covers the same bid")


func test_the_line_names_the_promised_purse() -> void:
	var economy: PlayerEconomy = _bid_economy(10000)
	economy.queue_build(RecruitQueue.KIND_SHIP, "carrack")
	var line: String = LedgerMarketText.bid_budget_line(MarketBudget.budget(economy))
	assert_true(line.contains("2,000 of 10,000 ducats"))
	assert_true(line.contains("8,000 promised to 1 waiting order"))


# --- MarketBatch: one press files the whole order (REQ-P5-04) ---

func _batch_ctx(overrides: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {
		"cargo_free": 4,
		"treasury": 1000,
		"tech_unlocked": {},
		"projected_non_bid_delta": 0,
		"reserved": {},
	}
	for key: Variant in overrides.keys():
		out[key] = overrides[key]
	return out


## The bid batch is the holds and the purse, whichever binds first.
func test_the_bid_batch_is_the_holds_and_the_purse() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var price: int = market.buy_price("timber", 0)
	assert_eq(MarketBatch.bid_units(market, 0, "timber", _batch_ctx()), 4, "four holds")
	assert_eq(
		MarketBatch.bid_units(market, 0, "timber", _batch_ctx({"treasury": price * 2})),
		2,
		"the purse binds before the holds",
	)
	assert_eq(
		MarketBatch.bid_units(market, 0, "timber", _batch_ctx({"cargo_free": 0})), 0,
		"no holds, no bid",
	)


## The staged bids and the waiting Build/work orders are paid first, so the
## batch is what is left of the holds and the purse.
func test_the_batch_leaves_the_staged_bids_and_the_waiting_orders_out() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var price: int = market.buy_price("timber", 0)
	var staged: Dictionary = MarketOrders.submit(
		market, 0, "timber", MarketOrder.SIDE_BID, 1, {"cargo_free": 4, "treasury": 1000}
	)
	assert_true(bool(staged["ok"]), String(staged.get("reason", "")))
	assert_eq(
		MarketBatch.bid_units(market, 0, "timber", _batch_ctx()), 3,
		"one hold and one unit's ducats are already promised",
	)
	var promised: Dictionary = _batch_ctx({
		"treasury": price * 3, "projected_non_bid_delta": -price,
	})
	assert_eq(
		MarketBatch.bid_units(market, 0, "timber", promised), 1,
		"the waiting order is paid before the auction",
	)


## One side per commodity, and the bid-type cap still holds: a commodity the
## court already bids on keeps batching, a fourth one does not open.
func test_the_batch_never_crosses_the_side_or_the_bid_type_cap() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var offer: Dictionary = MarketOrders.submit(
		market, 0, "timber", MarketOrder.SIDE_OFFER, 1, {"stock": 4}
	)
	assert_true(bool(offer["ok"]), String(offer.get("reason", "")))
	assert_eq(
		MarketBatch.bid_units(market, 0, "timber", _batch_ctx()), 0,
		"a court bids or offers a commodity, never both",
	)
	var capped: WorldMarket = WorldMarket.with_default_prices()
	for id: String in ["timber", "iron", "wool"]:
		MarketOrders.submit(
			capped, 0, id, MarketOrder.SIDE_BID, 1, {"cargo_free": 8, "treasury": 9000}
		)
	var rich: Dictionary = _batch_ctx({"cargo_free": 8, "treasury": 9000})
	assert_eq(
		MarketBatch.bid_units(capped, 0, "grain", rich), 0,
		"a fourth commodity is refused by the cap",
	)
	assert_gt(
		MarketBatch.bid_units(capped, 0, "timber", rich), 1,
		"a commodity already bid on still batches",
	)


## A court with no plan (or no economy) reserves nothing, so the sheet's offer
## cap is the whole holding.
func test_no_plan_reserves_nothing() -> void:
	assert_eq(MarketBatch.reservations(null), {})
	var economy := PlayerEconomy.new()
	assert_eq(MarketBatch.reservations(economy), {})


## The offer batch is the stock the assigned runs leave, less the tons already
## offered this turn.
func test_the_offer_batch_leaves_production_and_the_staged_offers_out() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var ctx: Dictionary = _batch_ctx({"reserved": {"timber": 2}})
	assert_eq(
		MarketBatch.offer_units(market, 0, "timber", 5, ctx), 3,
		"the assigned runs eat two tons",
	)
	var staged: Dictionary = MarketOrders.submit(
		market, 0, "timber", MarketOrder.SIDE_OFFER, 1, {"stock": 5}
	)
	assert_true(bool(staged["ok"]), String(staged.get("reason", "")))
	assert_eq(
		MarketBatch.offer_units(market, 0, "timber", 5, ctx), 2,
		"the ton already offered is not offered twice",
	)
	assert_eq(MarketBatch.offer_units(market, 0, "timber", 0, ctx), 0)


## A Minor/Tribe row batches the seller's whole row, never more than it has left.
func test_the_minor_row_batch_stops_at_the_seller_s_left() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var offer: Dictionary = {
		"id": "6:timber", "faction": 6, "commodity": "timber",
		"quantity": 2, "unit_price": 30,
	}
	assert_eq(MarketBatch.offer_row_units(market, 0, offer, _batch_ctx()), 2)
	assert_eq(
		MarketBatch.offer_row_units(market, 0, offer, _batch_ctx({"cargo_free": 1})), 1,
		"one hold, one ton",
	)
	assert_eq(
		MarketBatch.offer_row_units(market, 0, offer, _batch_ctx({"cargo_free": 0})), 0
	)


## The Minor/Tribe row's batch pays the ask it prints: a surcharge rides on the
## deal, so a purse that covers three tons at the world price covers two at the
## ask, and the press never names more ducats than the crown holds (wiki:
## world-market § Subsidy price adjustment, § Treasury budget for bids).
func test_the_minor_row_batch_pays_the_ask_the_press_prints() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	market.subsidy_terms["0>6"] = 20
	var offer: Dictionary = {
		"id": "6:timber", "faction": 6, "commodity": "timber",
		"quantity": 9, "unit_price": 30,
	}
	var ctx: Dictionary = _batch_ctx({"cargo_free": 9, "treasury": 100})
	assert_eq(
		MarketBatch.bid_units(market, 0, "timber", ctx), 3,
		"the world price alone would buy three tons",
	)
	var units: int = MarketBatch.offer_row_units(market, 0, offer, ctx)
	assert_eq(units, 2, "the ask of 36 pays two tons from 100 ducats")
	var total: int = MarketRules.deal_total_for(market, "timber", units, 0, 6, 20, true)
	assert_lte(total, 100, "the whole deal fits the purse")
	assert_gt(
		MarketRules.deal_total_for(market, "timber", units + 1, 0, 6, 20, true), 100,
		"one more ton is a deal the purse cannot pay",
	)


## The figure is the validator's own cap: the batch is accepted and one more
## unit is refused, so a press can never stage an order the rules would not
## (REQ-P2-03).
func test_the_batch_is_exactly_what_the_validator_accepts() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var price: int = market.buy_price("timber", 0)
	var by_holds: Dictionary = _batch_ctx({"cargo_free": 3, "treasury": 1000})
	var units: int = MarketBatch.bid_units(market, 0, "timber", by_holds)
	assert_eq(units, 3)
	var accepted: Dictionary = MarketOrders.submit(
		market, 0, "timber", MarketOrder.SIDE_BID, units, by_holds
	)
	assert_true(bool(accepted["ok"]), String(accepted.get("reason", "")))
	var refused: Dictionary = MarketOrders.submit(
		market, 0, "timber", MarketOrder.SIDE_BID, units + 1, by_holds
	)
	assert_false(bool(refused["ok"]))
	assert_eq(String(refused["code"]), "trade_order_cargo_insufficient")

	var purse_market: WorldMarket = WorldMarket.with_default_prices()
	var by_purse: Dictionary = _batch_ctx({
		"cargo_free": 5, "treasury": price * 2, "buy_price": price,
	})
	var purse_units: int = MarketBatch.bid_units(purse_market, 0, "timber", by_purse)
	assert_eq(purse_units, 2)
	var fits: Dictionary = MarketOrders.submit(
		purse_market, 0, "timber", MarketOrder.SIDE_BID, purse_units, by_purse
	)
	assert_true(bool(fits["ok"]), String(fits.get("reason", "")))
	var over: Dictionary = MarketOrders.submit(
		purse_market, 0, "timber", MarketOrder.SIDE_BID, 1, by_purse
	)
	assert_false(bool(over["ok"]))
	assert_eq(String(over["code"]), "trade_order_bid_exceeds_treasury_budget")


# --- the PRODUCTION tab's one press (DR-20261116-08) -------------------------


## One press files one run on every ready row, in the page's order, and each row
## is capped by the allowance the rows before it leave: the walk reads the same
## arithmetic the row's "+" is capped by (REQ-P2-03, REQ-P5-04).
func test_the_production_batch_sets_one_run_on_every_ready_row() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var stock: Dictionary = {"timber": 10, "wool": 10, "iron": 10, "coal": 10}
	var result: Dictionary = ProductionBatch.plan(
		["lumber", "fabric_from_wool", "steel"], economy, 0, stock, 20, []
	)
	var plan: Dictionary = result["plan"]
	assert_eq(int(result["runs"]), 3, "every ready row took a step")
	assert_eq(int(plan["lumber"]), 1)
	assert_eq(int(plan["fabric_from_wool"]), 1)
	assert_eq(int(plan["steel"]), 1, "the slow row takes one run, not its whole bench")


## A row already at its ceiling has no step to file, and the press never fills a
## row to the ceiling: one press is one step per row (REQ-P5-04).
func test_the_production_batch_skips_a_row_at_its_ceiling() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var stock: Dictionary = {"timber": 10, "wool": 10}
	var assignments: Array = [{"recipe": "lumber", "units": 5}]
	var result: Dictionary = ProductionBatch.plan(
		["lumber", "fabric_from_wool"], economy, 0, stock, 20, assignments
	)
	assert_eq(int(result["runs"]), 1, "only the row with room takes a step")
	assert_false((result["plan"] as Dictionary).has("lumber"), "the full row is left alone")
	assert_eq(int(result["skipped"]), 1)


## The labour the earlier rows claim is gone for the rows after them, so the walk
## can never set a run the phase would refuse (REQ-P2-03).
func test_the_production_batch_spends_the_labour_it_claims() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var stock: Dictionary = {"timber": 10, "wool": 10}
	var result: Dictionary = ProductionBatch.plan(
		["lumber", "fabric_from_wool"], economy, 0, stock, 2, []
	)
	assert_eq(int(result["runs"]), 1, "two labour points buy one run")
	assert_eq(int((result["plan"] as Dictionary)["lumber"]), 1)
	assert_eq(int(result["skipped"]), 1, "the second row waits on the labour")


## A row whose hand or town's works is missing is no step at all: the press names
## only what the phase would start (wiki: production-recipes § Worker-tier gates).
func test_the_production_batch_skips_a_gated_row() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var stock: Dictionary = {"tobacco": 10, "fabric": 10}
	var result: Dictionary = ProductionBatch.plan(
		["cigars", "garments"], economy, 0, stock, 20, []
	)
	assert_eq(int(result["runs"]), 0, "no gated row is offered")
	assert_eq(int(result["skipped"]), 2)


## The receipt names what the press set, and says why a page with nothing ready
## offered no step (REQ-P5-05).
func test_the_production_batch_receipt_names_the_runs() -> void:
	assert_eq(
		ProductionBatch.receipt(3), "Set 3 runs — every ready row in this view is ordered."
	)
	assert_eq(
		ProductionBatch.receipt(1), "Set 1 run — every ready row in this view is ordered."
	)
	assert_true(ProductionBatch.receipt(0).begins_with("No ready row to set"))


## The walk prices itself before the crown signs: the labour and the materials
## the runs would claim, what the phase keeps of its idle labour, and the rows it
## leaves out (REQ-P5-06; DR-20261118-24).
func test_the_production_batch_prices_the_line_it_would_file() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var stock: Dictionary = {"timber": 10, "wool": 10, "iron": 10, "coal": 10}
	var result: Dictionary = ProductionBatch.plan(
		["lumber", "fabric_from_wool", "steel"], economy, 0, stock, 20, []
	)
	assert_eq(int(result["runs"]), 3)
	assert_eq(int(result["labour"]), 6, "three runs at two labour each")
	assert_eq(int(result["labour_budget"]), 20)
	var inputs: Dictionary = result["inputs"]
	assert_eq(int(inputs.get("timber", 0)), 2)
	assert_eq(int(inputs.get("wool", 0)), 2)
	assert_eq(int(inputs.get("iron", 0)), 1)
	assert_eq(int(inputs.get("coal", 0)), 1)
	assert_eq(
		ProductionBatch.sheet_line(result),
		"3 runs · 6 labour · 2 Wool · 2 Timber · 1 Iron · 1 Coal"
		+ " — the phase keeps 14 of its 20 idle labour."
	)


## A row the walk leaves out is counted on the line, and a page with nothing to
## file prints no line at all (REQ-P5-05, REQ-P5-06).
func test_the_production_batch_line_names_the_rows_it_leaves_out() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var tight: Dictionary = ProductionBatch.plan(
		["lumber", "fabric_from_wool"], economy, 0, {"timber": 10, "wool": 10}, 2, []
	)
	assert_eq(int(tight["runs"]), 1, "two labour points buy one run")
	assert_eq(
		ProductionBatch.sheet_line(tight),
		"1 run · 2 labour · 2 Timber — the phase keeps 0 of its 2 idle labour."
		+ " 1 row waits on a ceiling, a hand, a town's works or the labour and store left."
	)
	var gated: Dictionary = ProductionBatch.plan(
		["cigars", "garments"], economy, 0, {"tobacco": 10, "fabric": 10}, 20, []
	)
	assert_eq(int(gated["runs"]), 0)
	assert_eq(ProductionBatch.sheet_line(gated), "", "nothing to file prints no line")


# --- MarketPressure: the row book a court reads (REQ-P3-03) -----------------

## Every claim consumes the store, so the regiment's material adds to what the
## works already reserved instead of replacing it (wiki: economy-planner
## § Reservations; growth-stage-planner § Recruitment modulation).
func test_promised_adds_the_regiments_claim_to_the_reserved_store() -> void:
	var reserved: Dictionary = {"lumber": 2}
	var claims: Dictionary = MarketPressure.promised(reserved, {"lumber": 1, "fabric": 3})
	assert_eq(int(claims["lumber"]), 3)
	assert_eq(int(claims["fabric"]), 3)
	assert_eq(int(reserved["lumber"]), 2, "the caller's own book is not written")
	assert_eq(MarketPressure.promised(reserved, {}), reserved, "no need, no copy")


## The France shape: a saving court holds tradeable stock, yet every row sits
## under the comfort reserve, so it offers nothing and is trapped (issue #489).
func test_a_trapped_hoard_is_the_france_shape() -> void:
	var market: WorldMarket = _market()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.stockpile = {"wool": 20, "grain": 25}
	assert_true(MarketPressure.hoard_trapped(economy, market, 20))
	economy.stockpile = {"wool": 30, "grain": 25}
	assert_false(MarketPressure.hoard_trapped(economy, market, 20), "a surplus is not trapped")
	economy.stockpile = {"grain": 25}
	assert_false(MarketPressure.hoard_trapped(economy, market, 20), "dinner is not a hoard")
	assert_false(MarketPressure.hoard_trapped(null, market, 20))


## Rows rank the richest surplus first, and liquidation lifts the reserve on
## everything but the dinner (wiki: treasury-planner § Lock-recovery).
func test_surpluses_rank_the_richest_first_and_keep_the_dinner() -> void:
	var market: WorldMarket = _market()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.stockpile = {"wool": 25, "grain": 25, "timber": 40}
	var rows: Array[Dictionary] = MarketPressure.surpluses(economy, market, 20)
	assert_eq(int(rows[0]["surplus"]), 20, "the richest row leads")
	assert_eq(String(rows[0]["commodity"]), "timber")
	var liquid: Array[Dictionary] = MarketPressure.surpluses(economy, market, 20, {}, true)
	assert_eq(int(liquid[0]["surplus"]), 40)
	var grain: Dictionary = {}
	for row: Dictionary in liquid:
		if String(row["commodity"]) == "grain":
			grain = row
	assert_eq(int(grain["surplus"]), 5, "the ration keeps its reserve")


## The next regiment's material leads the deficit rows even when a works input is
## shorter; the estate feedstock leads the rest (issue #878).
func test_deficits_lead_with_the_regiments_claim_then_the_feedstock() -> void:
	var market: WorldMarket = _market()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.stockpile = {}
	var inputs: Array[String] = ["lumber", "castIron", "fabric", "paper"]
	var rows: Array[Dictionary] = MarketPressure.deficits(
		economy, market, inputs, 3, {"paper": 1}, {}, ["lumber", "castIron"]
	)
	assert_eq(String(rows[0]["commodity"]), "paper", "the muster's row leads")
	assert_eq(String(rows[1]["commodity"]), "castIron", "feedstock before the rest")
	assert_eq(int(rows[0]["deficit"]), 3)
	assert_eq(MarketPressure.deficits(null, market, inputs, 3).size(), 0)


## The ration is one row bought in full — a court that can only import half its
## dinner still strikes (wiki: treasury-planner § Lock-recovery).
func test_food_deficits_buy_the_ration_in_one_row() -> void:
	var rows: Array[Dictionary] = MarketPressure.food_deficits(_market(), 6)
	assert_eq(rows.size(), 1)
	assert_eq(String(rows[0]["commodity"]), "grain")
	assert_eq(int(rows[0]["deficit"]), 6)
	assert_eq(MarketPressure.food_deficits(_market(), 0).size(), 0)
	assert_eq(MarketPressure.food_deficits(null, 6).size(), 0)


## Every pass reads the book's tradeable goods in one order (REQ-P2-03).
func test_tradeable_ids_are_sorted() -> void:
	var ids: Array[String] = MarketPressure.tradeable_ids(_market())
	var sorted_ids: Array[String] = ids.duplicate()
	sorted_ids.sort()
	assert_eq(ids, sorted_ids)
	assert_true(ids.has("grain"))
	assert_eq(MarketPressure.tradeable_ids(null).size(), 0)


# --- the deal matcher's ordering arms ----------------------------------------
## Who takes the goods: the matcher's ordering arms own their home
## (wiki: world-market § Trade orders, § Priority override; REQ-P3-01). The
## caller keeps the deals, the state and the price; these read one rank arm
## each, in the order the matcher walks them.
##
## Folded from test_market_matcher_rank_rules: eight pure cases paid a whole
## Godot boot (coverage instrumentation) of their own for arms the market boot
## already opens (docs/testing.md § Speed rules — one boot per theme).


func test_the_lower_tier_bid_is_the_best_bid() -> void:
	var late: MarketOrder = _order(1, "timber", MarketOrder.SIDE_BID, 10, 2)
	var early: MarketOrder = _order(2, "timber", MarketOrder.SIDE_BID, 10, 1)
	var offer: MarketOrder = _order(0, "timber", MarketOrder.SIDE_OFFER, 10)
	var best: MarketOrder = MarketMatcherRank.best_bid([late, early], offer, {}, {})
	assert_eq(best.priority, 1)


func test_a_spent_bid_and_a_blocked_bid_are_no_bid_at_all() -> void:
	var spent: MarketOrder = _order(1, "timber", MarketOrder.SIDE_BID, 10)
	spent.filled = spent.quantity
	var blocked: MarketOrder = _order(2, "timber", MarketOrder.SIDE_BID, 10)
	var standing: MarketOrder = _order(3, "timber", MarketOrder.SIDE_BID, 10)
	var best: MarketOrder = MarketMatcherRank.best_bid(
		[spent, blocked, standing], _order(0, "timber", MarketOrder.SIDE_OFFER, 10),
		{blocked.id: true}, {}
	)
	assert_eq(best, standing)


func test_no_bid_left_answers_null() -> void:
	var spent: MarketOrder = _order(1, "timber", MarketOrder.SIDE_BID, 10)
	spent.filled = spent.quantity
	var best: MarketOrder = MarketMatcherRank.best_bid(
		[spent], _order(0, "timber", MarketOrder.SIDE_OFFER, 10), {}, {}
	)
	assert_eq(best, null)


func test_a_boycott_bars_the_pair_for_the_matcher() -> void:
	var context: Dictionary = {"boycott_for": func(a: int, b: int) -> bool:
		return a == 1 and b == 0
	}
	assert_true(MarketMatcherRank.boycott_for(context, 1, 0))
	assert_false(MarketMatcherRank.boycott_for(context, 2, 0))


func test_no_boycott_reading_bars_nothing() -> void:
	assert_false(MarketMatcherRank.boycott_for({}, 1, 0))


func test_within_a_tier_the_smaller_court_id_is_next() -> void:
	var offer: MarketOrder = _order(3, "timber", MarketOrder.SIDE_OFFER, 10)
	var first: MarketOrder = _order(1, "timber", MarketOrder.SIDE_BID, 10)
	var second: MarketOrder = _order(2, "timber", MarketOrder.SIDE_BID, 10)
	assert_true(MarketMatcherRank.bid_less(first, second, offer, {}))
	assert_false(MarketMatcherRank.bid_less(second, first, offer, {}))


func test_one_courts_two_orders_walk_by_order_id() -> void:
	var offer: MarketOrder = _order(3, "timber", MarketOrder.SIDE_OFFER, 10)
	var first: MarketOrder = _order(1, "timber", MarketOrder.SIDE_BID, 10)
	var second: MarketOrder = _order(1, "timber", MarketOrder.SIDE_BID, 10)
	assert_true(MarketMatcherRank.bid_less(first, second, offer, {}))
	assert_false(MarketMatcherRank.bid_less(second, first, offer, {}))


func test_offers_walk_tier_then_auto_then_court_then_tile() -> void:
	var late: MarketOrder = _order(1, "timber", MarketOrder.SIDE_OFFER, 10, 2)
	var court: MarketOrder = _order(4, "timber", MarketOrder.SIDE_OFFER, 10)
	var far_tile: MarketOrder = _order(1, "timber", MarketOrder.SIDE_OFFER, 10, 1, 1, 7)
	var near_tile: MarketOrder = _order(1, "timber", MarketOrder.SIDE_OFFER, 10, 1, 1, 2)
	var auto_offer: MarketOrder = _order(9, "timber", MarketOrder.SIDE_OFFER, 10, 1, 0, 0, true)
	var offers: Array = [late, court, far_tile, near_tile, auto_offer]
	MarketMatcherRank.sort_offers(offers)
	assert_eq(offers, [auto_offer, near_tile, far_tile, court, late])


# --- the production tab's own pick (DR-20261121-07) ---------------------------


## The tab names the runs the published economy pass books: the same
## `production_orders` call, in the catalogue's own order, with the plan's own
## counts — and it books nothing itself.
func test_the_production_pick_names_the_runs_the_plan_books() -> void:
	var economy := PlayerEconomy.starting()
	economy.stockpile = {"timber": 10, "wool": 4}
	economy.workers = WorkerPool.make(6)
	var plan: Dictionary = AiEconomyPlanner.production_orders(
		AiConfig.build(1, 1500), economy
	)

	var pick: Dictionary = MapPlayProductionPick.of(economy, plan)

	assert_eq(String(pick.get("kind", "")), MapPlayProductionPick.KIND_RUN)
	assert_eq(
		pick["runs"],
		{"fabric_from_wool": 1, "lumber": 1, "paper": 1},
		"the plan's own assignments, recipe by recipe"
	)
	assert_eq(
		String(pick["line"]),
		"the court would run Lumber ×1, Fabric ×1 and Paper ×1 this phase",
		"the catalogue's own order"
	)
	assert_eq(
		MapPlayProductionPick.sentence(String(pick["line"])),
		"The court would run Lumber ×1, Fabric ×1 and Paper ×1 this phase."
	)
	assert_eq(economy.production.assignment_units("lumber"), 0, "a reading: nothing is set")


## A court whose stores already stand at its reserve target is told so, rather
## than left to guess why no row is worth a run.
func test_the_production_pick_names_the_reserve_it_already_holds() -> void:
	var economy := PlayerEconomy.starting()
	var stock: Dictionary = {}
	for id: String in CommodityCatalog.MANUFACTURED:
		stock[id] = 25
	economy.stockpile = stock
	economy.workers = WorkerPool.make(6)
	var plan: Dictionary = AiEconomyPlanner.production_orders(
		AiConfig.build(1, 1500), economy
	)

	var pick: Dictionary = MapPlayProductionPick.of(economy, plan)

	assert_eq(String(pick.get("kind", "")), MapPlayProductionPick.KIND_DONE)
	assert_eq(pick["runs"], {}, "no row is named")
	assert_eq(String(pick["line"]), MapPlayProductionPick.DONE_LINE)


## Empty stores and no idle hand: the labour gate is named, not a silent page.
func test_the_production_pick_names_the_hands_it_has_not() -> void:
	var economy := PlayerEconomy.starting()
	economy.stockpile = {}
	economy.workers.counts = [0, 0, 0, 0]
	var plan: Dictionary = AiEconomyPlanner.production_orders(
		AiConfig.build(1, 1500), economy
	)

	var pick: Dictionary = MapPlayProductionPick.of(economy, plan)

	assert_eq(String(pick.get("kind", "")), MapPlayProductionPick.KIND_HANDS)
	assert_eq(String(pick["line"]), MapPlayProductionPick.HANDS_LINE)


## Idle hands and empty stores: the store — or the bench — is the gate, and the
## line says so instead of naming a hand that stands idle.
func test_the_production_pick_names_the_stores_it_lacks() -> void:
	var economy := PlayerEconomy.starting()
	economy.stockpile = {}
	economy.workers = WorkerPool.make(6)
	var plan: Dictionary = AiEconomyPlanner.production_orders(
		AiConfig.build(1, 1500), economy
	)

	var pick: Dictionary = MapPlayProductionPick.of(economy, plan)

	assert_eq(String(pick.get("kind", "")), MapPlayProductionPick.KIND_STORES)
	assert_eq(String(pick["line"]), MapPlayProductionPick.STORES_LINE)


## Beyond four outputs the clause counts what it does not name, so a rich plan
## stays one line of chrome on a handset (REQ-P5-07).
func test_the_production_pick_counts_the_rows_it_cannot_name() -> void:
	var line: String = MapPlayProductionPick.run_line({
		"lumber": 2,
		"castIron": 1,
		"fabric": 1,
		"paper": 1,
		"steel": 3,
	})

	assert_eq(
		line,
		"the court would run Lumber ×2, Cast Iron ×1, Fabric ×1, Steel ×3 and 1 more this phase"
	)
	# The tail counts rows, not the units they hold: "and N more" is read as N
	# more manufactures, the way the market page's own cap reads its goods
	# (LedgerMarket.price_moves_line's `+N more deals`, cargo's `and N more`).
	# A hidden run of three steel is one row left out, not three.
	assert_eq(
		MapPlayProductionPick.run_line({
			"lumber": 1, "castIron": 1, "fabric": 1, "refinedSugar": 1, "steel": 3,
		}),
		"the court would run Lumber ×1, Cast Iron ×1, Fabric ×1, Refined Sugar ×1"
		+ " and 1 more this phase",
		"the tail names the rows left out, not the units they hold"
	)
	assert_eq(
		MapPlayProductionPick.run_line({"lumber": 2}),
		"the court would run Lumber ×2 this phase",
		"one row reads alone"
	)
	assert_eq(MapPlayProductionPick.run_line({}), "", "no run, no clause")


## No ledger, no plan, no session: the pick answers nothing rather than a line
## the sheet would have to invent (REQ-P5-06).
func test_the_production_pick_reads_nothing_without_its_parts() -> void:
	var economy := PlayerEconomy.starting()
	var plan: Dictionary = AiEconomyPlanner.production_orders(
		AiConfig.build(1, 1500), economy
	)
	assert_true(MapPlayProductionPick.of(null, plan).is_empty(), "no ledger, no pick")
	assert_true(MapPlayProductionPick.of(economy, {}).is_empty(), "no plan, no pick")
	assert_true(MapPlayProductionPick.pick(null).is_empty(), "no session, no pick")
	assert_eq(MapPlayProductionPick.sentence(""), "", "no clause, no sentence")
