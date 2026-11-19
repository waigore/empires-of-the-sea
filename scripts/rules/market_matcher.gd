class_name MarketMatcher
extends RefCounted
## Pure world-market deal matcher (wiki: world-market § Trade orders, § Price
## discovery; world-market-first-right-of-refusal § Priority override). Orders
## clear at the published integer price. Supply is scarce Minor/Tribe and Great
## Power offers; the caller may add a WORLD counterparty so an unmatched order
## still fills at the published price.
##
## Ordering: (1) first right of refusal — a purchased tile's auto-offer fills
## the owning Great Power's bid before any tier; (2) integer priority tiers,
## lowest first; (3) within a tier a favoured pact (GP–GP), then a colony
## Tribe's suzerain, then (for Minor/Tribe sellers) Consulate holders and the
## higher relation score; (4) ascending faction id, then order id.
##
## A colonial boycott bars a pair outright — no fill between the boycotted court
## and the issuer's colony Tribes; both orders carry (wiki: diplomacy § Boycott).
## No RNG, no logging, no Game/Node access (REQ-P3-03).
##
## This file keeps the deals, the running state and the price. Who takes the
## goods is `MarketMatcherRank`'s own job: the offer order and the tier arms
## (REQ-P3-01).


## Returns {deals, residuals, notes}. Orders are cloned; the caller carries.
static func match(orders: Array[MarketOrder], context: Dictionary = {}) -> Dictionary:
	var deals: Array[Dictionary] = []
	var notes: Array[Dictionary] = []
	var prices: Dictionary = context.get("prices", {})
	var by_commodity: Dictionary = {}
	for order: MarketOrder in orders:
		if order == null or order.remaining() <= 0:
			continue
		if not by_commodity.has(order.commodity):
			by_commodity[order.commodity] = {"bids": [], "offers": []}
		var bucket: Dictionary = by_commodity[order.commodity]
		var key: String = "bids" if order.is_bid() else "offers"
		(bucket[key] as Array).append(order.clone())
	var ids: Array = by_commodity.keys()
	ids.sort()
	var state := {
		"prices": prices,
		"holds": _int_copy(context.get("free_holds", {})),
		"treasury": _int_copy(context.get("treasuries", {})),
		"spent": {},
		"stock": _stock_copy(context.get("stock", {})),
		"context": context,
		"notes": notes,
	}
	var left_by_id: Dictionary = {}
	for raw: Variant in ids:
		var commodity: String = String(raw)
		var bucket: Dictionary = by_commodity[commodity]
		var bids: Array = bucket["bids"]
		var offers: Array = bucket["offers"]
		_first_right(commodity, bids, offers, state, deals)
		_match_tiers(commodity, bids, offers, state, deals)
		for order: MarketOrder in bids + offers:
			left_by_id[order.id] = order.remaining()
	return {"deals": deals, "residuals": _residuals(orders, left_by_id), "notes": notes}


## FRR pre-pass: purchased-tile offers fill the owning court's bid first.
static func _first_right(
	commodity: String, bids: Array, offers: Array, state: Dictionary, deals: Array
) -> void:
	var purchased_for: Variant = state["context"].get("purchased_for", null)
	for raw: Variant in offers:
		var offer: MarketOrder = raw
		if offer.remaining() <= 0 or not offer.auto:
			continue
		if offer.origin_region < 0 or offer.origin_index < 0:
			continue
		if not purchased_for is Callable:
			continue
		var owner: int = int((purchased_for as Callable).call(
			offer.origin_region, offer.origin_index
		))
		if owner < 0:
			continue
		for bid_raw: Variant in bids:
			var bid: MarketOrder = bid_raw
			if bid.faction != owner or bid.remaining() <= 0:
				continue
			if MarketMatcherRank.boycott_for(state["context"], bid.faction, offer.faction):
				continue
			var filled: int = _fill(bid, offer, commodity, state, deals, true)
			if filled <= 0:
				continue


static func _match_tiers(
	commodity: String, bids: Array, offers: Array, state: Dictionary, deals: Array
) -> void:
	MarketMatcherRank.sort_offers(offers)
	var blocked: Dictionary = {}
	for raw: Variant in offers:
		var offer: MarketOrder = raw
		while offer.remaining() > 0:
			var bid: MarketOrder = MarketMatcherRank.best_bid(
				bids, offer, blocked, state["context"]
			)
			if bid == null:
				break
			var filled: int = _fill(bid, offer, commodity, state, deals, false)
			if filled <= 0:
				blocked[bid.id] = true
	# Anything left carries. Name the constraint that stopped it (wiki: world-market
	# § Treasury budget for bids — `bidPartialFill*Insufficient`; REQ-P5-05).
	var had_offer: bool = false
	for raw: Variant in offers:
		if (raw as MarketOrder).quantity > 0:
			had_offer = true
			break
	for raw: Variant in bids:
		var bid: MarketOrder = raw
		if bid.remaining() <= 0 or not had_offer:
			continue
		var code: String = ""
		if _holds_left(state, bid.faction) <= 0:
			code = "bid_partial_fill_cargo_insufficient"
		elif _treasury_left(state, bid.faction) < _buy_price(
			state, bid.faction, commodity
		):
			code = "bid_partial_fill_treasury_insufficient"
		if code.is_empty():
			continue
		(state["notes"] as Array).append({
			"code": code,
			"faction": bid.faction,
			"commodity": commodity,
			"quantity": bid.remaining(),
		})


## Fills one bid/offer pair, capped by the buyer's holds, purse and the seller's
## stock. Returns the units cleared.
static func _fill(
	bid: MarketOrder,
	offer: MarketOrder,
	commodity: String,
	state: Dictionary,
	deals: Array,
	is_frr: bool
) -> int:
	if bid.is_world() and offer.is_world():
		return 0
	var quantity: int = mini(bid.remaining(), offer.remaining())
	var gated_seller: bool = (
		not offer.is_world() and not MarketRules.is_minor(offer.faction) and not offer.auto
	)
	if gated_seller:
		var stock_left: int = _stock_left(state, offer.faction, commodity)
		if stock_left < quantity:
			# The tons the seller no longer holds are named (REQ-P5-05).
			(state["notes"] as Array).append({
				"code": "offer_partial_fill_stock_insufficient",
				"faction": offer.faction,
				"commodity": commodity,
				"quantity": quantity - maxi(stock_left, 0),
			})
			quantity = stock_left
	quantity = mini(quantity, _cap_for_buyer(state, bid, commodity))
	if quantity <= 0:
		return 0
	var price: float = _price(state, commodity)
	if price <= 0.0:
		return 0
	bid.filled += quantity
	offer.filled += quantity
	if gated_seller:
		_take_stock(state, offer.faction, commodity, quantity)
	if not bid.is_world():
		_debit_caps(state, bid.faction, quantity, commodity)
	var is_ftp: bool = false
	var ftp_for: Variant = state["context"].get("ftp_for", null)
	if ftp_for is Callable:
		is_ftp = bool((ftp_for as Callable).call(bid.faction, offer.faction))
	# Flags the sale a colony's suzerain took (DR-20261111-11).
	var is_favoured: bool = false
	var favoured_for: Variant = state["context"].get("favoured_for", null)
	if favoured_for is Callable and not bid.is_world() and MarketRules.is_minor(offer.faction):
		is_favoured = int((favoured_for as Callable).call(offer.faction)) == bid.faction
	deals.append({
		"commodity": commodity,
		"buyer": bid.faction,
		"seller": offer.faction,
		"quantity": quantity,
		"price": price,
		"priority": mini(bid.priority, offer.priority),
		"is_frr": is_frr,
		"is_ftp": is_ftp and not is_frr,
		"is_favoured": is_favoured and not is_frr,
		"seller_is_minor": MarketRules.is_minor(offer.faction),
		"origin_region": offer.origin_region,
		"origin_index": offer.origin_index,
		"offer_id": offer.id,
		"bid_id": bid.id,
	})
	return quantity


static func _cap_for_buyer(state: Dictionary, bid: MarketOrder, commodity: String) -> int:
	if bid.is_world():
		return bid.remaining()
	var unit: float = _buy_price(state, bid.faction, commodity)
	if unit <= 0.0:
		return 0
	var by_holds: int = maxi(_holds_left(state, bid.faction), 0)
	var by_purse: int = int(floor(maxf(_treasury_left(state, bid.faction), 0.0) / unit))
	return maxi(mini(bid.remaining(), mini(by_holds, by_purse)), 0)


static func _residuals(
	orders: Array[MarketOrder], left_by_id: Dictionary
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for order: MarketOrder in orders:
		if order == null:
			continue
		var left: int = int(left_by_id.get(order.id, order.remaining()))
		if left <= 0:
			continue
		rows.append({
			"order_id": order.id,
			"faction": order.faction,
			"commodity": order.commodity,
			"side": order.side,
			"quantity": left,
			"auto": order.auto,
			"priority": order.priority,
			"origin_region": order.origin_region,
			"origin_index": order.origin_index,
		})
	return rows


static func _price(state: Dictionary, commodity: String) -> float:
	var prices: Dictionary = state["prices"]
	if prices.has(commodity):
		return float(prices[commodity])
	return float(CommodityCatalog.base_price(commodity))


static func _buy_price(state: Dictionary, faction: int, commodity: String) -> float:
	var callable: Variant = state["context"].get("buy_price_for", null)
	if callable is Callable:
		return float((callable as Callable).call(faction, commodity))
	return _price(state, commodity)


static func _holds_left(state: Dictionary, faction: int) -> int:
	var holds: Dictionary = state["holds"]
	return int(holds.get(faction, holds.get(str(faction), 0)))


static func _treasury_left(state: Dictionary, faction: int) -> float:
	var treasury: Dictionary = state["treasury"]
	var spent: Dictionary = state["spent"]
	var have: float = float(treasury.get(faction, treasury.get(str(faction), 0)))
	return have - float(spent.get(faction, spent.get(str(faction), 0)))


static func _debit_caps(
	state: Dictionary, faction: int, quantity: int, commodity: String
) -> void:
	var holds: Dictionary = state["holds"]
	holds[faction] = maxi(_holds_left(state, faction) - quantity, 0)
	var spent: Dictionary = state["spent"]
	spent[faction] = float(spent.get(faction, 0.0)) + float(quantity) * _buy_price(
		state, faction, commodity
	)


static func _stock_left(state: Dictionary, faction: int, commodity: String) -> int:
	if faction == MarketOrder.WORLD:
		return 1 << 30
	var stock: Dictionary = state["stock"]
	var row: Variant = stock.get(faction, stock.get(str(faction), {}))
	if row is Dictionary:
		return int((row as Dictionary).get(commodity, 0))
	return 0


static func _take_stock(
	state: Dictionary, faction: int, commodity: String, quantity: int
) -> void:
	var stock: Dictionary = state["stock"]
	var key: Variant = faction if stock.has(faction) else str(faction)
	if not stock.has(key):
		stock[faction] = {}
		key = faction
	var row: Dictionary = stock[key] as Dictionary
	row[commodity] = maxi(int(row.get(commodity, 0)) - quantity, 0)


static func _int_copy(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if raw is Dictionary:
		for key: Variant in (raw as Dictionary).keys():
			out[int(key)] = int((raw as Dictionary)[key])
	return out


static func _stock_copy(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if raw is Dictionary:
		for key: Variant in (raw as Dictionary).keys():
			var row: Variant = (raw as Dictionary)[key]
			if row is Dictionary:
				out[int(key)] = (row as Dictionary).duplicate()
	return out
