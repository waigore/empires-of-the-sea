extends GdToolsTest
## Who takes the goods: the deal matcher's ordering arms own their home
## (wiki: world-market § Trade orders, § Priority override; REQ-P3-01). The
## caller keeps the deals, the state and the price; these read one rank arm
## each, in the order the matcher walks them.

var _seq: int = 0


func _order(
	faction: int, side: String, quantity: int = 10, priority: int = 1,
	origin_region: int = MarketOrder.NO_ORIGIN,
	origin_index: int = MarketOrder.NO_ORIGIN, auto_offer: bool = false
) -> MarketOrder:
	_seq += 1
	var order: MarketOrder = MarketOrder.create(
		faction, "timber", side, quantity, priority, origin_region, origin_index, auto_offer
	)
	order.id = "r%d" % _seq
	return order


func test_the_lower_tier_bid_is_the_best_bid() -> void:
	var late: MarketOrder = _order(1, MarketOrder.SIDE_BID, 10, 2)
	var early: MarketOrder = _order(2, MarketOrder.SIDE_BID, 10, 1)
	var offer: MarketOrder = _order(0, MarketOrder.SIDE_OFFER)
	var best: MarketOrder = MarketMatcherRank.best_bid([late, early], offer, {}, {})
	assert_eq(best.priority, 1)


func test_a_spent_bid_and_a_blocked_bid_are_no_bid_at_all() -> void:
	var spent: MarketOrder = _order(1, MarketOrder.SIDE_BID)
	spent.filled = spent.quantity
	var blocked: MarketOrder = _order(2, MarketOrder.SIDE_BID)
	var standing: MarketOrder = _order(3, MarketOrder.SIDE_BID)
	var best: MarketOrder = MarketMatcherRank.best_bid(
		[spent, blocked, standing], _order(0, MarketOrder.SIDE_OFFER), {blocked.id: true}, {}
	)
	assert_eq(best, standing)


func test_no_bid_left_answers_null() -> void:
	var spent: MarketOrder = _order(1, MarketOrder.SIDE_BID)
	spent.filled = spent.quantity
	var best: MarketOrder = MarketMatcherRank.best_bid(
		[spent], _order(0, MarketOrder.SIDE_OFFER), {}, {}
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
	var offer: MarketOrder = _order(3, MarketOrder.SIDE_OFFER)
	var first: MarketOrder = _order(1, MarketOrder.SIDE_BID)
	var second: MarketOrder = _order(2, MarketOrder.SIDE_BID)
	assert_true(MarketMatcherRank.bid_less(first, second, offer, {}))
	assert_false(MarketMatcherRank.bid_less(second, first, offer, {}))


func test_one_courts_two_orders_walk_by_order_id() -> void:
	var offer: MarketOrder = _order(3, MarketOrder.SIDE_OFFER)
	var first: MarketOrder = _order(1, MarketOrder.SIDE_BID)
	var second: MarketOrder = _order(1, MarketOrder.SIDE_BID)
	assert_true(MarketMatcherRank.bid_less(first, second, offer, {}))
	assert_false(MarketMatcherRank.bid_less(second, first, offer, {}))


func test_offers_walk_tier_then_auto_then_court_then_tile() -> void:
	var late: MarketOrder = _order(1, MarketOrder.SIDE_OFFER, 10, 2)
	var court: MarketOrder = _order(4, MarketOrder.SIDE_OFFER)
	var far_tile: MarketOrder = _order(1, MarketOrder.SIDE_OFFER, 10, 1, 1, 7)
	var near_tile: MarketOrder = _order(1, MarketOrder.SIDE_OFFER, 10, 1, 1, 2)
	var auto_offer: MarketOrder = _order(9, MarketOrder.SIDE_OFFER, 10, 1, 0, 0, true)
	var offers: Array = [late, court, far_tile, near_tile, auto_offer]
	MarketMatcherRank.sort_offers(offers)
	assert_eq(offers, [auto_offer, near_tile, far_tile, court, late])