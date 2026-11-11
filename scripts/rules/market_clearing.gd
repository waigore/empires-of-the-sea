class_name MarketClearing
extends RefCounted
## End-of-turn world-market clearing (wiki: world-market § Trade orders, § Price
## discovery, § First right of refusal; world-market-first-right-of-refusal).
## Gathers the courts' staged orders and the Minor/Tribe harvest, matches them,
## settles purses and cargo, pays first-right profit and embassy kickbacks,
## advances prices and carries unfilled orders forward. Pure rules: every input
## is data, so a headless test drives exactly the pass the game does
## (REQ-P2-03, REQ-P3-03).

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
	var settled: Dictionary = _settle(market, economies, deals, context, notes)
	var credits: Dictionary = _first_right(world, economies, deals, context)
	var changed: Dictionary = market.advance_prices()
	var carry: Array[MarketOrder] = _carry(orders, matched, economies, free_holds, notes)
	market.book.close_turn()
	market.book.set_carry(carry)
	market.book.last_deals = deals.duplicate(true)
	market.book.last_notes = notes.duplicate(true)
	MinorMarket.publish(market, world, FactionCatalog.PLAYER_FACTION)
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
	var pairs: Dictionary = {}
	for order: MarketOrder in rows:
		if order.remaining() <= 0 or order.is_world():
			continue
		var key: String = "%d:%s" % [order.faction, order.commodity]
		var sides: Dictionary = pairs.get(key, {}) as Dictionary
		sides[order.side] = true
		pairs[key] = sides
	var dropped: Dictionary = {}
	for key: String in pairs.keys():
		var sides: Dictionary = pairs[key]
		if sides.has(MarketOrder.SIDE_BID) and sides.has(MarketOrder.SIDE_OFFER):
			dropped[key] = true
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
		var key: String = "%d:%s" % [order.faction, order.commodity]
		if not dropped.has(key):
			kept.append(order)
	return kept


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
			return _purchased_owner(world, region, index),
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
			return DiplomacyRules.has_embassy(diplomacy, gp, minor)
		out["relation_for"] = func(gp: int, minor: int) -> float:
			var record: DiplomacyRelation = diplomacy.relation(gp, minor)
			return record.score if record != null else 0.0
	return out


## Settles every filled deal: buyer purse, cargo and stock, then seller stock
## and purse. Minor/Tribe sellers have no wallet, so their receipt is the sink.
static func _settle(
	market: WorldMarket,
	economies: Dictionary,
	deals: Array[Dictionary],
	context: Dictionary,
	notes: Array[Dictionary]
) -> Dictionary:
	var fills: Dictionary = {}
	for deal: Dictionary in deals:
		var buyer: int = int(deal.get("buyer", MarketOrder.WORLD))
		var seller: int = int(deal.get("seller", MarketOrder.WORLD))
		var commodity: String = String(deal.get("commodity", ""))
		var quantity: int = int(deal.get("quantity", 0))
		if quantity <= 0 or commodity.is_empty():
			continue
		var price: int = int(deal.get("price", 0))
		var subsidy: int = _subsidy_percent(context, buyer, seller)
		var buy_unit: int = _buy_unit(market, commodity, buyer, seller, subsidy)
		var cost: int = buy_unit * quantity
		var buyer_economy: PlayerEconomy = _economy(economies, buyer)
		if buyer_economy != null:
			if buyer_economy.treasury < cost:
				quantity = int(floor(float(buyer_economy.treasury) / float(maxi(buy_unit, 1))))
				cost = buy_unit * quantity
				notes.append({
					"code": "bid_partial_fill_treasury_insufficient",
					"faction": buyer,
					"commodity": commodity,
					"quantity": int(deal.get("quantity", 0)) - quantity,
				})
			if quantity <= 0:
				continue
			buyer_economy.spend_treasury(cost)
			buyer_economy.add(commodity, quantity)
			market.record_import(commodity, quantity, buyer)
		var seller_economy: PlayerEconomy = _economy(economies, seller)
		if seller_economy != null:
			seller_economy.take(commodity, quantity)
			var sell_unit: int = _sell_unit(market, commodity, seller, buyer, subsidy)
			seller_economy.add_treasury(sell_unit * quantity)
		deal["quantity"] = quantity
		deal["buy_unit"] = buy_unit
		deal["subsidy_percent"] = subsidy
		var row: Dictionary = fills.get(buyer, {}) as Dictionary
		row["bought"] = int(row.get("bought", 0)) + quantity
		row["spent"] = int(row.get("spent", 0)) + cost
		fills[buyer] = row
		if seller_economy != null:
			var sold: Dictionary = fills.get(seller, {}) as Dictionary
			sold["sold"] = int(sold.get("sold", 0)) + quantity
			fills[seller] = sold
	return {"fills": fills}


## Tax the subsidised pair at settlement (wiki: world-market § Subsidy price
## adjustment). Only a minor/tribe sale to its subsidising court occurs here
## today; the discount arm is kept for pure tests and future minor bids.
static func _subsidy_percent(context: Dictionary, buyer: int, seller: int) -> int:
	var diplomacy: DiplomacyState = context.get("diplomacy", null)
	if diplomacy == null:
		return 0
	var payer: int = -1
	var target: int = -1
	if _is_minor(seller) and buyer >= 0:
		payer = buyer
		target = seller
	elif _is_minor(buyer) and seller >= 0:
		payer = seller
		target = buyer
	if payer < 0:
		return 0
	return maxi(diplomacy.subsidy(payer, target), 0)


static func _buy_unit(
	market: WorldMarket, commodity: String, buyer: int, seller: int, subsidy_percent: int
) -> int:
	if buyer == MarketOrder.WORLD:
		return maxi(market.price(commodity), 1)
	var unit: float = float(market.buy_price(commodity, buyer))
	if subsidy_percent > 0 and _is_minor(buyer) and not _is_minor(seller):
		unit *= 1.0 - float(subsidy_percent) / 100.0
	elif subsidy_percent > 0 and not _is_minor(buyer) and _is_minor(seller):
		unit *= 1.0 + float(subsidy_percent) / 100.0
	return maxi(roundi(unit), 1)


static func _sell_unit(
	market: WorldMarket, commodity: String, seller: int, buyer: int, subsidy_percent: int
) -> int:
	if seller == MarketOrder.WORLD:
		return maxi(market.price(commodity), 1)
	var unit: float = float(market.sell_price(commodity, seller))
	if subsidy_percent > 0 and _is_minor(buyer) and not _is_minor(seller):
		unit *= 1.0 - float(subsidy_percent) / 100.0
	return maxi(roundi(unit), 1)


## Credits the tile-owning court its relation share and every other
## embassy-holding court its 10% kickback.
static func _first_right(
	world: WorldMap,
	economies: Dictionary,
	deals: Array[Dictionary],
	context: Dictionary
) -> Dictionary:
	var diplomacy: DiplomacyState = context.get("diplomacy", null)
	var relation_for: Callable = func(gp: int, minor: int) -> float:
		var record: DiplomacyRelation = diplomacy.relation(gp, minor) if diplomacy != null else null
		return record.score if record != null else 0.0
	var embassy_for: Callable = func(gp: int, minor: int) -> bool:
		return diplomacy != null and DiplomacyRules.has_embassy(diplomacy, gp, minor)
	var purchased_for: Callable = func(region: int, index: int) -> int:
		return _purchased_owner(world, region, index)
	var result: Dictionary = FirstRight.credits(
		deals, purchased_for, relation_for, embassy_for
	)
	var by_gp: Dictionary = result["by_gp"] as Dictionary
	for raw: Variant in by_gp.keys():
		var economy: PlayerEconomy = _economy(economies, int(raw))
		if economy != null:
			economy.add_treasury(roundi(float(by_gp[raw])))
	return result


## Unfilled Great-Power orders carry forward unless their stock or holds no
## longer cover them (wiki: world-market § Order persistence).
static func _carry(
	orders: Array[MarketOrder],
	matched: Dictionary,
	economies: Dictionary,
	free_holds: Dictionary,
	notes: Array[Dictionary]
) -> Array[MarketOrder]:
	var carry: Array[MarketOrder] = []
	for order: MarketOrder in orders:
		if order.auto or order.is_world() or order.faction < 0:
			continue
		var left: int = _residual_for(order, matched)
		if left <= 0:
			continue
		if order.is_bid():
			if int(free_holds.get(order.faction, 0)) < left:
				notes.append({
					"code": "carry_forward_dropped_cargo_insufficient",
					"faction": order.faction,
					"commodity": order.commodity,
					"quantity": left,
				})
				continue
		else:
			var economy: PlayerEconomy = _economy(economies, order.faction)
			var stock: int = economy.quantity(order.commodity) if economy != null else 0
			if stock < left:
				notes.append({
					"code": "carry_forward_dropped_stockpile_insufficient",
					"faction": order.faction,
					"commodity": order.commodity,
					"quantity": left,
				})
				continue
		var carried: MarketOrder = order.clone()
		carried.quantity = left
		carried.filled = 0
		carry.append(carried)
	return carry


static func _residual_for(order: MarketOrder, matched: Dictionary) -> int:
	for row: Dictionary in matched["residuals"]:
		if String(row.get("order_id", "")) != order.id:
			continue
		return int(row.get("quantity", 0))
	# A filled order has no residual row.
	return 0


static func _purchased_owner(world: WorldMap, region: int, index: int) -> int:
	if world == null or region < 0 or index < 0:
		return -1
	var model: MapModel = world.region(region)
	if model == null:
		return -1
	if not model.ownership.is_purchased(index):
		return -1
	return model.ownership.purchaser(index)


static func _economy(economies: Dictionary, faction: int) -> PlayerEconomy:
	var found: Variant = economies.get(faction, null)
	if found == null:
		found = economies.get(str(faction), null)
	return found as PlayerEconomy


static func _is_minor(faction: int) -> bool:
	if faction < 0:
		return false
	var kind: int = FactionCatalog.type_of(faction)
	return kind == FactionCatalog.Type.MINOR_NATION or kind == FactionCatalog.Type.TRIBE
