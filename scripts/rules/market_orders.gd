class_name MarketOrders
extends RefCounted
## Submission and withdrawal of world-market orders (wiki: world-market
## § Trade orders). Kept out of WorldMarket so the price book stays one small
## domain; the book holds the orders and this module applies the shared
## validation and ke'+"'"+"eps submitted offer volume for price discovery
## (REQ-P3-03).


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
		market.book.volumes.record_offer(id, order.quantity)
	return {"ok": true, "reason": "", "order_id": order.id, "order": order}


## Cancels a staged order and returns its offer volume to the book. A
## carry-forward order is not this turn's submission, so it cannot be withdrawn
## and its tons were never counted in this turn's supply: the withdrawal must
## leave the price-discovery book untouched (wiki: world-market § Price
## discovery — only this turn's submitted offers price the spread; § Order
## persistence — carry-forward orders are not cancelable).
static func cancel(market: WorldMarket, faction: int, order_id: String) -> bool:
	if market == null:
		return false
	var order: MarketOrder = market.book.find_order(faction, order_id)
	if order == null or not market.book.submitted.has(order):
		return false
	if order.side == MarketOrder.SIDE_OFFER:
		market.book.volumes.withdraw_offer(order.commodity, order.remaining())
	return market.book.cancel(faction, order_id)
