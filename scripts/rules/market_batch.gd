class_name MarketBatch
extends RefCounted
## The most units one press may file on the world market: the validator's own
## cap read forward, so a batch is never an order the single press would have
## refused (wiki: world-market § Trade orders — quantity, cargo and treasury
## caps; REQ-P2-03, REQ-P5-04).
##
## A court that needs a turn's ration buys it in one order instead of ten
## presses, and the figure is the rules' own: the holds left after the staged
## bids, the purse left after the waiting Build/work orders and the bids already
## on the book, the stock left after the assigned runs eat their inputs. Pure
## reads — nothing here stages, spends or mutates (REQ-P3-03).


## The reading every row of one repaint shares: the same keys
## `MarketRules.validate` takes, so the sheet and the order path price one
## context. `reserved` is `ProductionRecipes.reserved_inputs` for the court.
static func context(
	economy: PlayerEconomy, cargo: Dictionary, reserved: Dictionary = {}
) -> Dictionary:
	if economy == null:
		return {}
	return {
		"cargo_free": int(cargo.get("clear_free", cargo.get("free", 0))),
		"treasury": economy.treasury,
		"tech_unlocked": economy.tech_unlocked,
		"projected_non_bid_delta": MarketBudget.projected_non_bid_delta(economy),
		"reserved": reserved,
	}


## The tons the court's assigned runs eat before the auction clears:
## `ProductionRecipes.reserved_inputs` for its current plan, empty for a court
## with no plan (or none at all). One owner for the read the sheet, the row's
## caption and the validator all price (wiki: world-market § Trade orders — the
## offer cap is the post-production stockpile minus industry reservations).
static func reservations(economy: PlayerEconomy) -> Dictionary:
	if economy == null:
		return {}
	return ProductionRecipes.reserved_inputs(economy.production.assignments())


## Units a bid on `commodity` may carry in one order: the free holds after the
## staged bids, and the purse after the waiting orders and the bids already
## committed. Zero when the rules would refuse the order outright — a closed
## market, a riches id, the other side already staged, or the bid-type cap
## reached on a commodity this court does not yet bid on.
static func bid_units(
	market: WorldMarket, faction: int, commodity: String, context: Dictionary
) -> int:
	if market == null or not market.can_trade(commodity):
		return 0
	var book: MarketBook = market.book
	if book.has_opposite(faction, commodity, MarketOrder.SIDE_BID):
		return 0
	var cap: int = MarketRules.bid_type_cap(context.get("tech_unlocked", {}))
	var ids: Array[String] = book.bid_commodities(faction)
	if not ids.has(commodity) and ids.size() >= cap:
		return 0
	var hold_cap: int = maxi(
		maxi(int(context.get("cargo_free", 0)), 0) - book.pending_buy_units(faction), 0
	)
	if hold_cap <= 0:
		return 0
	var price: int = market.buy_price(commodity, faction)
	# The caller's own reading wins when it passes one, so the batch and the
	# validator price one figure (REQ-P2-03).
	if context.has("buy_price"):
		price = maxi(int(context.get("buy_price", 0)), 0)
	if price <= 0:
		return hold_cap
	var budget: int = MarketRules.treasury_budget(
		int(context.get("treasury", 0)),
		int(context.get("projected_non_bid_delta", 0))
	)
	var committed: int = 0
	for staged: MarketOrder in book.orders_for(faction, MarketOrder.SIDE_BID):
		committed += staged.remaining() * maxi(
			market.buy_price(staged.commodity, faction), 0
		)
	var by_purse: int = maxi(int(floor(float(budget - committed) / float(price))), 0)
	return mini(hold_cap, by_purse)


## Units an offer on `commodity` may carry in one order: the stock the assigned
## production runs leave, less the tons already offered this turn. `stock` is the
## court's own holding of that commodity.
static func offer_units(
	market: WorldMarket, faction: int, commodity: String, stock: int, context: Dictionary
) -> int:
	if market == null or not market.can_trade(commodity):
		return 0
	var book: MarketBook = market.book
	if book.has_opposite(faction, commodity, MarketOrder.SIDE_OFFER):
		return 0
	var reserved: Dictionary = context.get("reserved", {}) as Dictionary
	var claimed: int = maxi(int(reserved.get(commodity, 0)), 0)
	var promised: int = book.pending_sell_units(faction, commodity)
	return maxi(maxi(stock, 0) - claimed - promised, 0)


## Units one press on a Minor/Tribe book row may carry: the bid cap above, and
## never more than the seller has left on that row.
static func offer_row_units(
	market: WorldMarket, faction: int, offer: Dictionary, context: Dictionary
) -> int:
	var left: int = maxi(int(offer.get("quantity", 0)), 0)
	if left <= 0:
		return 0
	var commodity: String = String(offer.get("commodity", ""))
	return mini(bid_units(market, faction, commodity, context), left)
