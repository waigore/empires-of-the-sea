class_name WorldMarket
extends RefCounted
## World market: one global price per tradeable commodity, buy/sell clears at the
## current integer price and the end-of-turn price discovery pass moves prices
## (wiki: world-market). Riches never trade here; they convert in their own phase.

const PRICE_FLOOR_RATIO: float = 0.30
const MAX_PRICE_STEP: float = 0.20
## The slice has no AI order flow yet; depth stands in for the rest of the world so
## one nation's trades nudge prices instead of pinning them to the cap every turn.
const DEFAULT_WORLD_DEPTH: int = 8

var prices: Dictionary = {}
var world_depth: int = DEFAULT_WORLD_DEPTH
var _bids: Dictionary = {}
var _offers: Dictionary = {}
## Units bought this turn per buyer, so each crown spends its own cargo holds
## (DR-20261109-03); the price book stays one global order book.
var _bought_by_faction: Dictionary = {}


static func with_default_prices(depth: int = DEFAULT_WORLD_DEPTH) -> WorldMarket:
	var market := WorldMarket.new()
	market.world_depth = maxi(depth, 0)
	for id: String in CommodityCatalog.all_ids():
		if CommodityCatalog.is_tradeable(id):
			market.prices[id] = CommodityCatalog.base_price(id)
	return market


func price(id: String) -> int:
	if prices.has(id):
		return int(prices[id])
	return CommodityCatalog.base_price(id)


func can_trade(id: String) -> bool:
	return CommodityCatalog.is_tradeable(id)


func bid_volume(id: String) -> int:
	return int(_bids.get(id, 0))


func offer_volume(id: String) -> int:
	return int(_offers.get(id, 0))


## Units bought this turn across every commodity: the tonnage merchant cargo
## must carry (wiki: world-market § Cargo).
func bought_units() -> int:
	var total: int = 0
	for id: Variant in _bids.keys():
		total += int(_bids[id])
	return total


## Units one crown bought this turn. Legacy books that predate per-buyer
## accounting attribute every laden hold to the player.
func bought_units_for(faction: int) -> int:
	if _bought_by_faction.is_empty() and not _bids.is_empty():
		return bought_units() if faction == FactionCatalog.PLAYER_FACTION else 0
	return int(_bought_by_faction.get(faction, 0))


## This turn's imports per commodity, for the naval raid pass (wiki:
## ships-and-naval § Trade and Transport Interception).
func imports_this_turn() -> Dictionary:
	return _bids.duplicate()


## Buys at the current price and records the bid for price discovery.
func buy(
	economy: PlayerEconomy,
	id: String,
	quantity: int,
	faction: int = FactionCatalog.PLAYER_FACTION
) -> Dictionary:
	if not can_trade(id):
		return {"ok": false, "reason": "Not traded on the world market"}
	if quantity <= 0:
		return {"ok": false, "reason": "Quantity must be positive"}
	var unit_price: int = price(id)
	var cost: int = unit_price * quantity
	if not economy.spend_treasury(cost):
		return {"ok": false, "reason": "Insufficient treasury", "cost": cost}
	# A legacy book that only knows global bids attributes them to the player
	# before the first per-buyer entry is written.
	if _bought_by_faction.is_empty() and not _bids.is_empty():
		_bought_by_faction[FactionCatalog.PLAYER_FACTION] = bought_units()
	var prior: int = int(_bought_by_faction.get(faction, 0))
	economy.add(id, quantity)
	_bids[id] = bid_volume(id) + quantity
	_bought_by_faction[faction] = prior + quantity
	return {"ok": true, "reason": "", "unit_price": unit_price, "cost": cost}


## Sells from the stockpile at the current price and records the offer.
func sell(economy: PlayerEconomy, id: String, quantity: int) -> Dictionary:
	if not can_trade(id):
		return {"ok": false, "reason": "Not traded on the world market"}
	if quantity <= 0:
		return {"ok": false, "reason": "Quantity must be positive"}
	if economy.quantity(id) < quantity:
		return {"ok": false, "reason": "Insufficient stockpile"}
	var unit_price: int = price(id)
	var revenue: int = unit_price * quantity
	economy.take(id, quantity)
	economy.add_treasury(revenue)
	_offers[id] = offer_volume(id) + quantity
	return {"ok": true, "reason": "", "unit_price": unit_price, "revenue": revenue}


## Published formula, floored to an integer and clamped to 30% of the base price.
static func next_price(
	current: int,
	base: int,
	bids: int,
	offers: int,
	depth: int = 0
) -> int:
	var total: int = maxi(bids, 0) + maxi(offers, 0)
	if total <= 0:
		return maxi(current, 0)
	var spread: float = 0.5 * float(bids - offers) / float(total + 2 * maxi(depth, 0))
	spread = clampf(spread, -MAX_PRICE_STEP, MAX_PRICE_STEP)
	var stepped: int = int(floor(float(current) * (1.0 + spread)))
	var floor_price: int = int(floor(float(base) * PRICE_FLOOR_RATIO))
	return maxi(stepped, floor_price)


## Applies this turn's price discovery and starts the next turn with clean books.
func advance_prices() -> Dictionary:
	var changed: Dictionary = {}
	for id: String in CommodityCatalog.all_ids():
		if not can_trade(id):
			continue
		var current: int = price(id)
		var updated: int = next_price(
			current, CommodityCatalog.base_price(id), bid_volume(id), offer_volume(id), world_depth
		)
		prices[id] = updated
		if updated != current:
			changed[id] = updated
	_bids.clear()
	_offers.clear()
	_bought_by_faction.clear()
	return changed


func copy() -> WorldMarket:
	var clone := WorldMarket.new()
	clone.prices = prices.duplicate()
	clone.world_depth = world_depth
	clone._bids = _bids.duplicate()
	clone._offers = _offers.duplicate()
	clone._bought_by_faction = _bought_by_faction.duplicate()
	return clone


## Plain data for local saves (current prices and this turn's order book).
func to_dict() -> Dictionary:
	return {
		"prices": prices.duplicate(),
		"world_depth": world_depth,
		"bids": _bids.duplicate(),
		"offers": _offers.duplicate(),
		"bought_by_faction": _bought_by_faction.duplicate(),
	}


static func from_dict(data: Dictionary) -> WorldMarket:
	var market := WorldMarket.with_default_prices(int(data.get("world_depth", DEFAULT_WORLD_DEPTH)))
	var saved: Dictionary = data.get("prices", {})
	for key: Variant in saved.keys():
		market.prices[String(key)] = int(saved[key])
	market._bids = data.get("bids", {}).duplicate()
	market._offers = data.get("offers", {}).duplicate()
	market._bought_by_faction = data.get("bought_by_faction", {}).duplicate()
	return market
