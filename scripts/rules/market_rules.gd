class_name MarketRules
extends RefCounted
## Validation for world-market orders (wiki: world-market § Trade orders —
## validation rules). Pure rules: a refusal carries the wiki reason code so the
## ledger, the AI and tests speak the same contract (REQ-P2-03, REQ-P3-03).

const BASELINE_BID_TYPES: int = 3
const TRADE_FAIRS_BID_TYPES: int = 6
const TRADE_FAIRS: String = "trade_fairs"


## Bids on distinct commodities: three by default, six with Trade Fairs.
static func bid_type_cap(tech_unlocked: Dictionary = {}) -> int:
	if bool(tech_unlocked.get(TRADE_FAIRS, false)):
		return TRADE_FAIRS_BID_TYPES
	return BASELINE_BID_TYPES


## Treasury available for bids after this turn's non-bid deficit.
static func treasury_budget(treasury: int, projected_non_bid_delta: int = 0) -> int:
	var deficit: int = maxi(-projected_non_bid_delta, 0)
	return maxi(treasury - deficit, 0)


## Validates one order against the live book. `context` carries the caller's
## stock, free holds, treasury, tech and the effective buy price, so this module
## never reaches into a controller (REQ-P3-03).
static func validate(
	market: WorldMarket, order: MarketOrder, context: Dictionary = {}
) -> Dictionary:
	if market == null or order == null:
		return _no("No market is open.", "market_closed")
	if order.commodity.is_empty() or not market.can_trade(order.commodity):
		return _no("Not traded on the world market", "trade_order_riches_excluded")
	if order.quantity <= 0:
		return _no("Quantity must be positive", "trade_order_quantity")
	if order.side != MarketOrder.SIDE_BID and order.side != MarketOrder.SIDE_OFFER:
		return _no("Unknown order side", "trade_order_side")
	if order.priority < 1:
		return _no("Priority must be one or higher", "trade_order_priority")
	var book: MarketBook = market.book
	if book.has_opposite(order.faction, order.commodity, order.side):
		return _no(
			"A court may bid or offer a commodity, never both in one turn.",
			"trade_order_mutual_exclusion"
		)
	if order.side == MarketOrder.SIDE_BID:
		return _validate_bid(market, order, context)
	return _validate_offer(market, order, context)


static func _validate_bid(
	market: WorldMarket, order: MarketOrder, context: Dictionary
) -> Dictionary:
	var book: MarketBook = market.book
	var tech: Dictionary = context.get("tech_unlocked", {})
	var cap: int = bid_type_cap(tech)
	var ids: Array[String] = book.bid_commodities(order.faction)
	if not ids.has(order.commodity) and ids.size() >= cap:
		return _no(
			"A crown may bid on %d commodities a turn." % cap,
			"trade_order_bid_type_cap_exceeded"
		)
	var free: int = maxi(int(context.get("cargo_free", 0)), 0)
	var promised: int = book.pending_buy_units(order.faction)
	var hold_cap: int = maxi(free - promised, 0)
	if order.quantity > hold_cap:
		return _no("No cargo holds free this turn", "trade_order_cargo_insufficient")
	var price: int = maxi(int(context.get("buy_price", 0)), 0)
	var budget: int = treasury_budget(
		int(context.get("treasury", 0)),
		int(context.get("projected_non_bid_delta", 0))
	)
	var committed: int = 0
	for staged: MarketOrder in book.orders_for(order.faction, MarketOrder.SIDE_BID):
		committed += staged.remaining() * maxi(
			market.buy_price(staged.commodity, order.faction), 0
		)
	if price > 0 and committed + order.quantity * price > budget:
		return _no(
			"The treasury cannot cover that bid.", "trade_order_bid_exceeds_treasury_budget"
		)
	return _yes()


static func _validate_offer(
	market: WorldMarket, order: MarketOrder, context: Dictionary
) -> Dictionary:
	var book: MarketBook = market.book
	var stock: int = maxi(int(context.get("stock", 0)), 0)
	# The assigned production runs eat their inputs before the auction clears, so
	# those tons are never sellable (wiki: world-market § Trade orders — the offer
	# cap is the post-production stockpile minus industry reservations).
	var reserved: Dictionary = context.get("reserved", {}) as Dictionary
	var claimed: int = maxi(int(reserved.get(order.commodity, 0)), 0)
	var promised: int = book.pending_sell_units(order.faction, order.commodity)
	if order.quantity > maxi(stock - claimed - promised, 0):
		return _no("Not enough stock to offer that many.", "trade_order_stock_insufficient")
	return _yes()


## Notional of one order at a per-unit price, for the ledger and tests.
static func notional(order: MarketOrder, unit_price: int) -> int:
	return order.remaining() * maxi(unit_price, 0)


static func _yes() -> Dictionary:
	return {"ok": true, "reason": "", "code": ""}


static func _no(reason: String, code: String) -> Dictionary:
	return {"ok": false, "reason": reason, "code": code}
