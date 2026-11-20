class_name WorldMarket
extends RefCounted
## World market: one global price per tradeable commodity, buy/sell clears at the
## current integer price and the end-of-turn price discovery pass moves prices
## (wiki: world-market). Riches never trade here; they convert in their own phase.

const PRICE_FLOOR_RATIO: float = 0.30
## The ceiling the published spread may ratchet to: ten times the default price.
## A deficit may lift a price no further, while falling demand lets it fall
## naturally to the floor (wiki: world-market § Price discovery; issue #730).
const PRICE_CEILING_RATIO: float = 10.0
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
## `viewer -> {seller: issuer}`: the Minor/Tribe sellers a crown may not deal
## with because a boycott shuts them (wiki: diplomacy § GP–Tribe — Boycott, R6;
## DR-20261115-03). Published beside the rates so the offers plate can print the
## bar the deal matcher enforces but a price never shows.
var sealed: Dictionary = {}
## This turn's Minor Nation and Tribe offers, re-emitted each turn from their
## estates (wiki: world-market § Minor and tribe auto-sell; DR-20261110-08).
var minor_offers: Array[Dictionary] = []
## Staged bids/offers, carried residuals and the turn's trade volumes (wiki:
## world-market § Trade orders, § Order persistence). The ledger and the AI stage
## here; the matcher clears. The queries below read through, so callers keep one
## book to ask about what moved this turn. Cargo afloat lives on the volumes and
## outlives the price pass until the raid pass closes it (DR-20261111-17).
var book: MarketBook = MarketBook.new()


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
	sealed.clear()


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


## Units bid this turn on one commodity: the price-discovery demand side.
func bid_volume(id: String) -> int:
	return book.volumes.bid_volume(id)


## Units offered this turn on one commodity: the price-discovery supply side.
func offer_volume(id: String) -> int:
	return book.volumes.offer_volume(id)


## Units bought this turn across every commodity: the tonnage merchant cargo
## must carry (wiki: world-market § Cargo).
func bought_units() -> int:
	return book.volumes.bought_units()


## Units one crown bought this turn. Legacy books that predate per-buyer
## accounting attribute every laden hold to the player.
func bought_units_for(faction: int) -> int:
	return book.volumes.bought_units_for(faction)


## This turn's imports per commodity across every buyer, for price discovery.
## A raid must read one crown's own cargo instead: [method imports_for].
func imports_this_turn() -> Dictionary:
	return book.volumes.imports_this_turn()


## One crown's own cargo afloat, commodity -> units: what a raid can take off
## its merchant hulls (wiki: ships-and-naval § Trade and Transport Interception;
## DR-20261110-13). Legacy books that predate per-buyer cargo attribute the whole
## book to the player, as [method bought_units_for] does — but only until a
## per-crown row exists: once one is written (or the book has been spent for the
## turn) the explicit rows are authoritative even when empty.
func imports_for(faction: int) -> Dictionary:
	return book.volumes.imports_for(faction)


## Every crown with cargo afloat, ascending: the courts a blockade can raid
## (DR-20261110-13). The cargo book closes via [method MarketBook.close_cargo]
## when the raid pass has read it, not when prices move (DR-20261111-17).
func importing_factions() -> Array[int]:
	return book.volumes.importing_factions()


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
	if not settle_purchase(economy, id, quantity, faction, cost):
		return {"ok": false, "reason": "Insufficient treasury", "cost": cost}
	return {"ok": true, "reason": "", "unit_price": unit_price, "cost": cost}


## Pays a purchase and lands the goods: the purse edge, the stockpile and the
## book's cargo and price-discovery demand move as one. The ledger's own buy and
## the end-of-turn clearing settle through here, so a filled deal is booked
## exactly like a click (wiki: world-market § Trade orders). False when the
## purse cannot cover `cost`; nothing moves.
func settle_purchase(
	economy: PlayerEconomy, id: String, quantity: int, faction: int, cost: int
) -> bool:
	if economy == null or not economy.spend_treasury(cost):
		return false
	economy.add(id, quantity)
	record_import(id, quantity, faction)
	return true


## Books a purchase whose goods never sat in another crown's stockpile (a Minor
## or Tribe offer): the buyer's import and its price-discovery demand are the
## same as an ordinary bid (wiki: world-market § Minor and tribe auto-sell).
func record_import(id: String, quantity: int, faction: int) -> void:
	book.volumes.record_import(id, quantity, faction)


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
	book.volumes.record_offer(id, quantity)
	return {"ok": true, "reason": "", "unit_price": unit_price, "revenue": revenue}


## Published formula, floored to an integer and clamped between 30% and ten
## times the base price (wiki: world-market § Price discovery; issue #730): the
## step is half the imbalance between this turn's filled bids and submitted
## offers, capped at ±20%. No market depth term stands in the denominator — the
## rule is the courts' own order flow. The ceiling is the safety rail a
## pathological spike (war, blockade, a failed harvest) cannot climb past, not a
## target: a price under it moves by the spread exactly as before.
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
	var ceiling: int = int(floor(float(base) * PRICE_CEILING_RATIO))
	return clampi(stepped, floor_price, maxi(ceiling, floor_price))


## Applies this turn's price discovery and starts the next turn with clean books.
## `auto_offers` is the commodity → units of Minor/Tribe auto-offer quantity on
## the book this turn: it clears in matching, so it is the spread's supply side
## too (wiki: world-market § Price discovery; issue #730). Carry-forward
## unfilled quantities stay out, as published.
func advance_prices(auto_offers: Dictionary = {}) -> Dictionary:
	var changed: Dictionary = {}
	for id: String in CommodityCatalog.all_ids():
		if not can_trade(id):
			continue
		var current: int = price(id)
		var supply: int = offer_volume(id) + maxi(int(auto_offers.get(id, 0)), 0)
		var updated: int = next_price(
			current, CommodityCatalog.base_price(id), bid_volume(id), supply
		)
		prices[id] = updated
		if updated != current:
			changed[id] = updated
	book.reset_turn_volumes()
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
	clone.sealed = sealed.duplicate(true)
	clone.minor_offers = minor_offers.duplicate(true)
	clone.book = book.copy()
	return clone


## Plain data for local saves (current prices and this turn's order book).
func to_dict() -> Dictionary:
	return {
		"prices": prices.duplicate(),
		"minor_offers": minor_offers.duplicate(true),
		"book": book.to_dict(),
	}


static func from_dict(data: Dictionary) -> WorldMarket:
	var market := WorldMarket.with_default_prices()
	var saved: Dictionary = data.get("prices", {})
	for key: Variant in saved.keys():
		# Prices are a non-negative integer band: a legacy save that wrote a
		# negative entry loads it as zero rather than publishing a price no
		# deal ever charged (wiki: world-market § Price discovery).
		market.prices[String(key)] = maxi(int(saved[key]), 0)
	for entry: Variant in data.get("minor_offers", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		market.minor_offers.append((entry as Dictionary).duplicate())
	var book_data: Variant = data.get("book", {})
	if book_data is Dictionary and not (book_data as Dictionary).is_empty():
		market.book = MarketBook.from_dict(book_data)
	# Saves written while the volumes sat beside the book keep loading: they
	# are folded into the book's volumes on the way in. Top-level cargo from
	# the MarketCargo extract lands the same way.
	market.book.volumes.adopt_legacy(data)
	return market
