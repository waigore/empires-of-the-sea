class_name MarketOrders
extends RefCounted
## Submission and withdrawal of world-market orders (wiki: world-market
## § Trade orders). Kept out of WorldMarket so the price book stays one small
## domain; the book holds the orders, this module applies the shared validation
## and keeps submitted offer volume for price discovery (REQ-P3-03).


## Stages one order after the shared validation rules pass. An offer's submitted
## quantity counts for this turn's price discovery immediately (wiki:
## world-market § Price discovery); the filled bid quantity is booked at clear.
static func submit(
	market: WorldMarket,
	faction: int,
	id: String,
	side: String,
	quantity: int,
	context: Dictionary = {},
	priority: int = 1
) -> Dictionary:
	if market == null:
		return {"ok": false, "reason": "No market is open.", "code": "market_closed"}
	var order: MarketOrder = MarketOrder.create(
		faction, id, side, quantity, priority
	)
	var check: Dictionary = MarketRules.validate(market, order, context)
	if not bool(check.get("ok", false)):
		return {
			"ok": false,
			"reason": String(check.get("reason", "")),
			"code": String(check.get("code", "")),
		}
	market.book.submit(order)
	if side == MarketOrder.SIDE_OFFER:
		market._offers[id] = market.offer_volume(id) + order.quantity
	return {"ok": true, "reason": "", "order_id": order.id, "order": order}


## Cancels a staged order and returns its offer volume to the book.
static func cancel(market: WorldMarket, faction: int, order_id: String) -> bool:
	if market == null:
		return false
	var order: MarketOrder = market.book.find_order(faction, order_id)
	if order == null:
		return false
	if order.side == MarketOrder.SIDE_OFFER:
		market._offers[order.commodity] = maxi(
			market.offer_volume(order.commodity) - order.remaining(), 0
		)
	return market.book.cancel(faction, order_id)
