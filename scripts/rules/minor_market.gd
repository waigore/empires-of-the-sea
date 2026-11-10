class_name MinorMarket
extends RefCounted
## Market offers from Minor Nations and Tribes (wiki: world-market § Minor and
## tribe auto-sell). Each turn a court with land ashore publishes what its
## connected estates produce; a Great Power buys those goods direct, below the
## middleman world price, while the seller's whole purse leaves the economy as a
## treasury sink. Pure rules: the ledger emits intents and this module decides
## (REQ-P2-03, REQ-P3-03; DR-20261110-08).

## Direct purchase: the seller keeps the whole receipt, so no merchant house
## takes its cut (DR-20261110-08).
const DISCOUNT: float = 0.75
## Grain is the Great Power capital ration, never a Minor or Tribe cash crop.
const EXCLUDED: Array[String] = [Extraction.GRAIN]


## Stable row key: one offer per seller and commodity.
static func offer_id(faction: int, commodity: String) -> String:
	return "%d:%s" % [faction, commodity]


## What one unit costs direct: the world price under the courts' discount and
## the buyer's trade terms (a pact or subsidy moves a direct purchase too),
## never below one ducat.
static func unit_price(
	market: WorldMarket,
	commodity: String,
	buyer: int = FactionCatalog.PLAYER_FACTION
) -> int:
	if market == null or not market.can_trade(commodity):
		return 0
	var ask: int = maxi(int(floor(float(market.price(commodity)) * DISCOUNT)), 1)
	return maxi(roundi(float(ask) * market.term_multiplier(buyer, commodity, true)), 1)


## This turn's offers for one buyer: every Minor Nation and Tribe in a region
## where the buyer holds land, one row per commodity, richest first.
static func emit(
	world: WorldMap, market: WorldMarket, buyer: int
) -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	if world == null or market == null:
		return offers
	for region_index in world.region_count():
		if world.owned_provinces(region_index, buyer) <= 0:
			continue
		_region_offers(world.region(region_index), world, region_index, market, offers, buyer)
	offers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["faction"]) != int(b["faction"]):
			return int(a["faction"]) < int(b["faction"])
		if int(a["quantity"]) != int(b["quantity"]):
			return int(a["quantity"]) > int(b["quantity"])
		return String(a["commodity"]) < String(b["commodity"])
	)
	return offers


static func _region_offers(
	model: MapModel,
	world: WorldMap,
	region_index: int,
	market: WorldMarket,
	offers: Array[Dictionary],
	buyer: int
) -> void:
	if model == null:
		return
	var sellers: Array[int] = []
	sellers.append_array(FactionCatalog.minor_ids())
	sellers.append_array(FactionCatalog.tribe_ids())
	for faction: int in sellers:
		var seat: int = world.seat_province(region_index, faction)
		if seat == MapModel.NO_ID:
			continue
		var yields: Dictionary = Extraction.yields(model, faction, seat)
		var commodities: Array = yields.keys()
		commodities.sort()
		for raw: Variant in commodities:
			var commodity: String = String(raw)
			var quantity: int = int(yields[raw])
			if quantity <= 0 or EXCLUDED.has(commodity):
				continue
			if not market.can_trade(commodity):
				continue
			offers.append({
				"id": offer_id(faction, commodity),
				"faction": faction,
				"commodity": commodity,
				"quantity": quantity,
				"unit_price": unit_price(market, commodity, buyer),
			})


## Publishes this turn's Minor Nation and Tribe offers: every court in a region
## the crown holds land in sells what its estates yield (wiki: world-market
## § Minor and tribe auto-sell; DR-20261110-08).
static func publish(market: WorldMarket, world: WorldMap, buyer: int) -> void:
	if market == null:
		return
	if world == null:
		market.minor_offers.clear()
		return
	market.minor_offers = emit(world, market, buyer)


## Index of an offer in the live book, or -1 when it is spent or gone.
static func index_of(offers: Array, offer_id_value: String) -> int:
	for index in offers.size():
		if String((offers[index] as Dictionary).get("id", "")) == offer_id_value:
			return index
	return -1


## Units still on the table for one offer (0 when it has sold out).
static func remaining(offers: Array, offer_id_value: String) -> int:
	var index: int = index_of(offers, offer_id_value)
	if index < 0:
		return 0
	return int((offers[index] as Dictionary).get("quantity", 0))


## Buys from one offer: cargo first, then treasury, then the seller's receipt.
## The whole cost leaves the Great Power pool (treasury sink) and the purchase
## counts as this turn's import for price discovery and naval interception.
static func buy(
	market: WorldMarket,
	economy: PlayerEconomy,
	offers: Array,
	offer_id_value: String,
	quantity: int,
	holds: int,
	reserved: int = 0,
	buyer: int = FactionCatalog.PLAYER_FACTION
) -> Dictionary:
	if quantity <= 0:
		return {"ok": false, "reason": "Quantity must be positive"}
	var index: int = index_of(offers, offer_id_value)
	if index < 0:
		return {"ok": false, "reason": "That court has nothing left to sell this turn."}
	var offer: Dictionary = offers[index]
	var commodity: String = String(offer.get("commodity", ""))
	var seller: int = int(offer.get("faction", -1))
	var left: int = int(offer.get("quantity", 0))
	if quantity > left:
		return {
			"ok": false,
			"reason": "Only %d %s left from %s." % [
				left, CommodityCatalog.label(commodity), FactionCatalog.name_of(seller)
			],
		}
	var gate: Dictionary = TradeCargo.check(market, holds, quantity, reserved, buyer)
	if not bool(gate.get("ok", false)):
		return gate
	var unit_price: int = int(offer.get("unit_price", 0))
	var cost: int = unit_price * quantity
	if not economy.spend_treasury(cost):
		return {"ok": false, "reason": "Insufficient treasury", "cost": cost}
	economy.add(commodity, quantity)
	market.record_import(commodity, quantity, buyer)
	offer["quantity"] = left - quantity
	if int(offer["quantity"]) <= 0:
		offers.remove_at(index)
	return {
		"ok": true,
		"reason": "",
		"unit_price": unit_price,
		"cost": cost,
		"commodity": commodity,
		"faction": seller,
		"quantity": quantity,
	}
