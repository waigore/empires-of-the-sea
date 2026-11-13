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


## The subsidy step one deal carries, 1.0 for a pair with none: a subsidised
## Minor/Tribe's goods cost its payer `1 + p%` and the other arms move `1 − p%`
## (wiki: world-market § Subsidy price adjustment, R3.4a/b). The step is scoped
## to the pair, so a deal with any other court carries 1.0.
static func subsidy_step(
	percent: int, buyer_is_minor: bool, seller_is_minor: bool, is_buy: bool
) -> float:
	if percent <= 0:
		return 1.0
	var step: float = float(percent) / 100.0
	if is_buy:
		if seller_is_minor and not buyer_is_minor:
			return 1.0 + step
		if buyer_is_minor and not seller_is_minor:
			return 1.0 - step
		return 1.0
	if buyer_is_minor and not seller_is_minor:
		return 1.0 - step
	return 1.0


## The subsidy percent a published pair carries, 0 when it carries none.
static func subsidy_percent(market: WorldMarket, buyer: int, seller: int) -> int:
	if market == null or buyer < 0 or seller < 0:
		return 0
	return int(market.subsidy_terms.get("%d>%d" % [buyer, seller], 0))


## The multiplier one deal actually lands at: the court's own terms times the
## pair's subsidy step, kept inside the rails the page publishes — "trade terms
## still stack with it inside the 70–150% (buy) and 50–130% (sell) rails"
## (wiki: world-market § Subsidy price adjustment). One read for the settlement,
## the ask and the UI, so none of them can drift.
static func deal_rate(
	market: WorldMarket, commodity: String, court: int, step: float, is_buy: bool
) -> float:
	var rate: float = market.term_multiplier(court, commodity, is_buy) * step
	if is_buy:
		return clampf(rate, DiplomacyCatalog.TERMS_BUY_MIN, DiplomacyCatalog.TERMS_BUY_MAX)
	return clampf(rate, DiplomacyCatalog.TERMS_SELL_MIN, DiplomacyCatalog.TERMS_SELL_MAX)


## One unit at the published price and the deal's rate; what the ask prints.
static func deal_unit(
	market: WorldMarket, commodity: String, court: int, step: float, is_buy: bool
) -> int:
	var rate: float = deal_rate(market, commodity, court, step, is_buy)
	return maxi(roundi(float(market.price(commodity)) * rate), 1)


## One deal's total, rounded once from the published price and the whole rate
## (wiki: world-market § Subsidy price adjustment — the debt is
## `round(Q × P × (1 ± p/100))`, never a sum of per-unit roundings).
static func deal_total(
	market: WorldMarket,
	commodity: String,
	quantity: int,
	court: int,
	step: float,
	is_buy: bool
) -> int:
	if quantity <= 0:
		return 0
	var rate: float = deal_rate(market, commodity, court, step, is_buy)
	return maxi(roundi(float(quantity) * float(market.price(commodity)) * rate), quantity)


## Whether a court is a Minor Nation or a Tribe; the subsidy arms read it.
static func is_minor(faction: int) -> bool:
	if faction < 0:
		return false
	var kind: int = FactionCatalog.type_of(faction)
	return kind == FactionCatalog.Type.MINOR_NATION or kind == FactionCatalog.Type.TRIBE


## One unit of a deal between two named courts, the step read from the pair.
static func deal_unit_for(
	market: WorldMarket, commodity: String, buyer: int, seller: int,
	subsidy_percent: int, is_buy: bool
) -> int:
	if is_buy:
		var buy_step: float = subsidy_step(
			subsidy_percent, is_minor(buyer), is_minor(seller), true
		)
		return deal_unit(market, commodity, buyer, buy_step, true)
	var sell_step: float = subsidy_step(
		subsidy_percent, is_minor(buyer), is_minor(seller), false
	)
	return deal_unit(market, commodity, seller, sell_step, false)


## One deal's whole cost or receipt between two named courts.
static func deal_total_for(
	market: WorldMarket, commodity: String, quantity: int, buyer: int, seller: int,
	subsidy_percent: int, is_buy: bool
) -> int:
	var step: float = subsidy_step(
		subsidy_percent, is_minor(buyer), is_minor(seller), is_buy
	)
	return deal_total(market, commodity, quantity, buyer if is_buy else seller, step, is_buy)


static func _yes() -> Dictionary:
	return {"ok": true, "reason": "", "code": ""}


static func _no(reason: String, code: String) -> Dictionary:
	return {"ok": false, "reason": reason, "code": code}
