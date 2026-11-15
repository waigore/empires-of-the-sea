class_name WorldMarket
extends RefCounted
## World market: one global price per tradeable commodity, buy/sell clears at the
## current integer price and the end-of-turn price discovery pass moves prices
## (wiki: world-market). Riches never trade here; they convert in their own phase.

const PRICE_FLOOR_RATIO: float = 0.30
const MAX_PRICE_STEP: float = 0.20

var prices: Dictionary = {}
## Faction -> {"buy": {commodity|"*": multiplier}, "sell": {...}}. Trade
## diplomacy publishes these; an empty book means the published price for all.
var trade_terms: Dictionary = {}
## `"buyer>seller" -> percent`: the subsidy step between one pair, published so
## the Minor's ask names the price the clearing charges (wiki: world-market
## § Subsidy price adjustment). The step lands on the deal, never on the crown's
## own rate, so it cannot touch a deal with another court.
var subsidy_terms: Dictionary = {}
## This turn's Minor Nation and Tribe offers, re-emitted each turn from their
## estates (wiki: world-market § Minor and tribe auto-sell; DR-20261110-08).
var minor_offers: Array[Dictionary] = []
## Staged bids/offers and carried residuals (wiki: world-market § Trade orders,
## § Order persistence). The ledger and the AI stage here; the matcher clears.
var book: MarketBook = MarketBook.new()
var _bids: Dictionary = {}
var _offers: Dictionary = {}
## Units bought this turn per buyer, so each crown spends its own cargo holds
## (DR-20261109-03); the price book stays one global order book.
var _bought_by_faction: Dictionary = {}
## Each buyer's own cargo afloat, commodity -> units, read by the next turn's
## raid pass. A raid takes the victim's goods only, never the whole book's
## (DR-20261110-13).
var cargo: MarketCargo = MarketCargo.new()


static func with_default_prices() -> WorldMarket:
	var market := WorldMarket.new()
	for id: String in CommodityCatalog.all_ids():
		if CommodityCatalog.is_tradeable(id):
			market.prices[id] = CommodityCatalog.base_price(id)
	return market


func price(id: String) -> int:
	if prices.has(id):
		return int(prices[id])
	return CommodityCatalog.base_price(id)


## Installs one crown's trade terms (trade diplomacy); empty clears them.
func set_terms(faction: int, terms: Dictionary) -> void:
	if terms.is_empty():
		trade_terms.erase(faction)
	else:
		trade_terms[faction] = terms


func clear_terms() -> void:
	trade_terms.clear()
	subsidy_terms.clear()


func terms_for(faction: int) -> Dictionary:
	var raw: Variant = trade_terms.get(faction, {})
	if typeof(raw) == TYPE_DICTIONARY:
		return raw
	return {}


## Multiplier for one side of the book; "*" is the crown-wide rate.
func term_multiplier(faction: int, id: String, is_buy: bool) -> float:
	var book: Dictionary = terms_for(faction)
	var side: Dictionary = book.get("buy" if is_buy else "sell", {})
	var raw: Variant = side.get(id, side.get("*", 1.0))
	return maxf(float(raw), 0.0)


## What this crown actually pays per unit after its trade terms.
func buy_price(id: String, faction: int = FactionCatalog.PLAYER_FACTION) -> int:
	return maxi(roundi(float(price(id)) * term_multiplier(faction, id, true)), 1)


## What this crown actually receives per unit after its trade terms.
func sell_price(id: String, faction: int = FactionCatalog.PLAYER_FACTION) -> int:
	return maxi(roundi(float(price(id)) * term_multiplier(faction, id, false)), 1)


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


## This turn's imports per commodity across every buyer, for price discovery.
## A raid must read one crown's own cargo instead: [method imports_for].
func imports_this_turn() -> Dictionary:
	return _bids.duplicate()


## One crown's own cargo afloat, commodity -> units: what a raid can take off
## its merchant hulls (wiki: ships-and-naval § Trade and Transport Interception;
## DR-20261110-13). Legacy books that predate per-buyer cargo attribute the whole
## book to the player, as [method bought_units_for] does — but only until a
## per-crown row exists: once one is written (or the book has been spent for the
## turn) the explicit rows are authoritative even when empty.
func imports_for(faction: int) -> Dictionary:
	if not cargo.tracked:
		return _bids.duplicate() if faction == FactionCatalog.PLAYER_FACTION else {}
	return cargo.of(faction)


## Every crown with cargo afloat, ascending: the courts a blockade can raid
## (DR-20261110-13).
func importing_factions() -> Array[int]:
	if not cargo.tracked:
		var legacy: Array[int] = []
		if not _bids.is_empty():
			legacy.append(FactionCatalog.PLAYER_FACTION)
		return legacy
	return cargo.factions()


## The cargo book closes when the raid pass has read it, not when prices move:
## the clearing fills the book at the turn's close and the next turn's raid
## pass is its only reader, so a price pass that also emptied it left hostile
## squadrons nothing to take (wiki: ships-and-naval § Trade and Transport
## Interception — "the victim's own purchases this turn").
func close_cargo_book() -> void:
	cargo.close()


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
	var unit_price: int = buy_price(id, faction)
	var cost: int = unit_price * quantity
	if not economy.spend_treasury(cost):
		return {"ok": false, "reason": "Insufficient treasury", "cost": cost}
	economy.add(id, quantity)
	record_import(id, quantity, faction)
	return {"ok": true, "reason": "", "unit_price": unit_price, "cost": cost}


## Books a purchase whose goods never sat in another crown's stockpile (a Minor
## or Tribe offer): the buyer's import and its price-discovery demand are the
## same as an ordinary bid (wiki: world-market § Minor and tribe auto-sell).
func record_import(id: String, quantity: int, faction: int) -> void:
	if quantity <= 0:
		return
	# A legacy book that only knows global bids attributes them to the player
	# before the first per-buyer entry is written.
	if _bought_by_faction.is_empty() and not _bids.is_empty():
		_bought_by_faction[FactionCatalog.PLAYER_FACTION] = bought_units()
	var prior: int = int(_bought_by_faction.get(faction, 0))
	_bids[id] = bid_volume(id) + quantity
	_bought_by_faction[faction] = prior + quantity
	cargo.record(faction, id, quantity)


## Sells from the stockpile at the current price and records the offer.
func sell(
	economy: PlayerEconomy,
	id: String,
	quantity: int,
	faction: int = FactionCatalog.PLAYER_FACTION
) -> Dictionary:
	if not can_trade(id):
		return {"ok": false, "reason": "Not traded on the world market"}
	if quantity <= 0:
		return {"ok": false, "reason": "Quantity must be positive"}
	if economy.quantity(id) < quantity:
		return {"ok": false, "reason": "Insufficient stockpile"}
	var unit_price: int = sell_price(id, faction)
	var revenue: int = unit_price * quantity
	economy.take(id, quantity)
	economy.add_treasury(revenue)
	_offers[id] = offer_volume(id) + quantity
	return {"ok": true, "reason": "", "unit_price": unit_price, "revenue": revenue}


## Published formula, floored to an integer and clamped to 30% of the base price
## (wiki: world-market § Price discovery): the step is half the imbalance between
## this turn's filled bids and submitted offers, capped at ±20%. No market depth
## term stands in the denominator — the rule is the courts' own order flow.
static func next_price(
	current: int,
	base: int,
	bids: int,
	offers: int
) -> int:
	var total: int = maxi(bids, 0) + maxi(offers, 0)
	if total <= 0:
		return maxi(current, 0)
	var spread: float = 0.5 * float(bids - offers) / float(total)
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
			current, CommodityCatalog.base_price(id), bid_volume(id), offer_volume(id)
		)
		prices[id] = updated
		if updated != current:
			changed[id] = updated
	_bids.clear()
	_offers.clear()
	_bought_by_faction.clear()
	# The cargo book outlives the price pass: the raid pass reads it next turn
	# and closes it (wiki: ships-and-naval § Trade and Transport Interception).
	# A court's offers are its harvest of the turn, re-emitted by the ledger
	# after this pass (DR-20261110-08).
	minor_offers.clear()
	return changed


func copy() -> WorldMarket:
	var clone := WorldMarket.new()
	clone.prices = prices.duplicate()
	clone.trade_terms = trade_terms.duplicate(true)
	clone.subsidy_terms = subsidy_terms.duplicate()
	clone.minor_offers = minor_offers.duplicate(true)
	clone.book = book.copy()
	clone._bids = _bids.duplicate()
	clone._offers = _offers.duplicate()
	clone._bought_by_faction = _bought_by_faction.duplicate()
	clone.cargo = cargo.copy()
	return clone


## Plain data for local saves (current prices and this turn's order book).
func to_dict() -> Dictionary:
	return {
		"prices": prices.duplicate(),
		"minor_offers": minor_offers.duplicate(true),
		"book": book.to_dict(),
		"bids": _bids.duplicate(),
		"offers": _offers.duplicate(),
		"bought_by_faction": _bought_by_faction.duplicate(),
		"imports_by_faction": cargo.to_dict(),
	}


static func from_dict(data: Dictionary) -> WorldMarket:
	var market := WorldMarket.with_default_prices()
	var saved: Dictionary = data.get("prices", {})
	for key: Variant in saved.keys():
		market.prices[String(key)] = int(saved[key])
	for entry: Variant in data.get("minor_offers", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		market.minor_offers.append((entry as Dictionary).duplicate())
	var book: Variant = data.get("book", {})
	if book is Dictionary and not (book as Dictionary).is_empty():
		market.book = MarketBook.from_dict(book)
	market._bids = data.get("bids", {}).duplicate()
	market._offers = data.get("offers", {}).duplicate()
	market._bought_by_faction = data.get("bought_by_faction", {}).duplicate()
	var cargo: Variant = data.get("imports_by_faction", null)
	# A save that carries the book is authoritative even when it is empty; one
	# written before per-crown cargo keeps the pooled-demand fallback.
	if cargo is Dictionary:
		market.cargo = MarketCargo.from_dict(cargo)
	return market
