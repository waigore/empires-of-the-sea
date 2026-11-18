class_name MarketClearing
extends RefCounted
## End-of-turn world-market clearing (wiki: world-market § Trade orders, § Price
## discovery, § First right of refusal; world-market-first-right-of-refusal).
## Gathers the courts' staged orders and the Minor/Tribe harvest, matches them,
## then hands settle, first-right credits and carry to MarketSettlement. Pure
## rules: every input is data, so a headless test drives exactly the pass the
## game does (REQ-P2-03, REQ-P3-03).

const WORLD_DEPTH: int = 8


## Returns {deals, notes, credits, prices, sink, fills, carry}.
static func clear(
	market: WorldMarket,
	world: WorldMap,
	economies: Dictionary,
	free_holds: Dictionary,
	context: Dictionary = {}
) -> Dictionary:
	var notes: Array[Dictionary] = []
	if market == null:
		return {"deals": [], "notes": notes, "credits": {}, "prices": {}, "sink": 0.0}
	var orders: Array[MarketOrder] = _prepare_orders(market, world, notes)
	# The Minor/Tribe auto-offers stand on this turn's book, so they are the
	# spread's supply side as much as the courts' own offers are (wiki:
	# world-market § Price discovery; issue #730). Read before matching so each
	# row still carries the units it was published with.
	var auto_offers: Dictionary = _auto_supply(orders)
	var treasuries: Dictionary = {}
	var stock: Dictionary = {}
	for raw: Variant in economies.keys():
		var faction: int = int(raw)
		var economy: PlayerEconomy = economies[raw] as PlayerEconomy
		if economy == null:
			continue
		treasuries[faction] = economy.treasury
		stock[faction] = economy.stockpile.duplicate()
	var matcher_context: Dictionary = _matcher_context(
		market, world, context, treasuries, free_holds, stock
	)
	var orders_with_world: Array[MarketOrder] = orders.duplicate()
	orders_with_world.append_array(_world_orders(orders))
	var matched: Dictionary = MarketMatcher.match(orders_with_world, matcher_context)
	var deals: Array[Dictionary] = matched["deals"] as Array[Dictionary]
	# The matcher's MarketActivityNotes (a bid cut by cargo or purse, an offer the
	# seller no longer covers) belong to the Deal Book too (wiki: world-market
	# § Treasury budget for bids — note attribution; REQ-P5-05).
	for note: Variant in matched["notes"]:
		notes.append(note as Dictionary)
	var settled: Dictionary = MarketSettlement.settle(
		market, economies, deals, context, notes
	)
	# A deal the purse refused is no deal: never in the Deal Book or a share.
	deals = settled.get("deals", deals) as Array[Dictionary]
	var credits: Dictionary = MarketSettlement.first_right(
		world, economies, deals, context
	)
	var changed: Dictionary = market.advance_prices(auto_offers)
	var carry: Array[MarketOrder] = MarketSettlement.carry(
		orders, matched, economies, free_holds, notes
	)
	market.book.close_turn()
	market.book.set_carry(carry)
	market.book.last_deals = deals.duplicate(true)
	market.book.last_notes = notes.duplicate(true)
	# The Minor/Tribe book is priced for the crown that will read it: a court
	# sailing as England must not be quoted Spain's terms and subsidy step
	# (wiki: world-market § Subsidy price adjustment; REQ-P2-03, REQ-P5-05).
	MinorMarket.publish(
		market, world, int(context.get("viewer", FactionCatalog.PLAYER_FACTION))
	)
	return {
		"deals": deals,
		"notes": notes,
		"credits": credits,
		"prices": changed,
		"fills": settled.get("fills", {}),
		"sink": float(credits.get("sink", 0.0)),
		"carry": carry,
	}


## Staged orders plus the Minor/Tribe harvest. Orders that break the
## per-commodity mutual exclusion are dropped whole and noted.
static func _prepare_orders(
	market: WorldMarket, world: WorldMap, notes: Array[Dictionary]
) -> Array[MarketOrder]:
	var rows: Array[MarketOrder] = []
	rows.append_array(market.book.all_open())
	rows.append_array(MinorMarket.emit_orders(world))
	var dropped: Dictionary = MarketRules.staged_both_sides(rows)
	for key: String in dropped.keys():
		var parts: PackedStringArray = key.split(":")
		notes.append({
			"code": "trade_order_mutual_exclusion",
			"faction": int(parts[0]),
			"commodity": parts[1],
		})
	if dropped.is_empty():
		return rows
	var kept: Array[MarketOrder] = []
	for order: MarketOrder in rows:
		if not dropped.has(MarketRules.order_pair_key(order)):
			kept.append(order)
	return kept


## Units the Minor Nations and Tribes auto-offer per commodity this turn: their
## rows clear in matching at the published price, so the spread's supply side
## counts them (wiki: world-market § Price discovery; DR-20261115-18). Read
## before matching, while every row still holds the units it was published with.
static func _auto_supply(orders: Array[MarketOrder]) -> Dictionary:
	var supply: Dictionary = {}
	for order: MarketOrder in orders:
		if order == null or not order.auto or order.is_bid():
			continue
		supply[order.commodity] = int(supply.get(order.commodity, 0)) + order.remaining()
	return supply


## The standing world counterparty: enough units to clear every finite order on
## the other side, at the lowest priority, but never a court and never settled.
static func _world_orders(orders: Array[MarketOrder]) -> Array[MarketOrder]:
	var bid_total: Dictionary = {}
	var offer_total: Dictionary = {}
	for order: MarketOrder in orders:
		if order.is_world() or order.remaining() <= 0:
			continue
		if order.is_bid():
			bid_total[order.commodity] = int(bid_total.get(order.commodity, 0)) + order.remaining()
		else:
			offer_total[order.commodity] = int(offer_total.get(order.commodity, 0)) + order.remaining()
	var rows: Array[MarketOrder] = []
	for commodity: Variant in bid_total.keys():
		rows.append(MarketOrder.create(
			MarketOrder.WORLD, String(commodity), MarketOrder.SIDE_OFFER,
			int(bid_total[commodity]), 100
		))
	for commodity: Variant in offer_total.keys():
		rows.append(MarketOrder.create(
			MarketOrder.WORLD, String(commodity), MarketOrder.SIDE_BID,
			int(offer_total[commodity]), 100
		))
	return rows


static func _matcher_context(
	market: WorldMarket,
	world: WorldMap,
	context: Dictionary,
	treasuries: Dictionary,
	free_holds: Dictionary,
	stock: Dictionary
) -> Dictionary:
	var diplomacy: DiplomacyState = context.get("diplomacy", null)
	var out: Dictionary = {
		"prices": market.prices.duplicate(),
		"treasuries": treasuries,
		"free_holds": free_holds,
		"stock": stock,
		"buy_price_for": func(faction: int, commodity: String) -> int:
			return market.buy_price(commodity, faction),
		"purchased_for": func(region: int, index: int) -> int:
			return MarketSettlement.purchased_owner(world, region, index),
	}
	if diplomacy != null:
		out["ftp_for"] = func(a: int, b: int) -> bool:
			return DiplomacyTrade.is_ftp(diplomacy, a, b)
		# A colony's suzerain trades first inside the tier (wiki: diplomacy
		# § Favoured trading partner, R7.1; DR-20261111-11). Only the colony arm
		# reaches the auction: for an independent court the R7.1 partner is the
		# warmest buyer, and R7.3 already ranks that order behind every
		# Consulate holder.
		out["favoured_for"] = func(seller: int) -> int:
			if diplomacy.colony_of(seller) < 0:
				return MarketFavoured.UNDEFINED
			return MarketFavoured.of(diplomacy, seller)
		out["consulate_for"] = func(gp: int, minor: int) -> bool:
			return DiplomacyRules.has_consulate(diplomacy, gp, minor)
		out["relation_for"] = func(gp: int, minor: int) -> float:
			var record: DiplomacyRelation = diplomacy.relation(gp, minor)
			return record.score if record != null else 0.0
		# A boycott bars the deal, not the price: the boycotted court may not buy
		# from or sell to a Tribe that is the issuer's colony, so the pair never
		# fills and both orders carry (wiki: diplomacy § GP–Tribe — Boycott, R6).
		out["boycott_for"] = func(a: int, b: int) -> bool:
			return DiplomacyTrade.blocked_by_boycott(diplomacy, a, b)
	return out
