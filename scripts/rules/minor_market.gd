class_name MinorMarket
extends RefCounted
## Market supply from Minor Nations and Tribes (wiki: world-market § Minor and
## tribe auto-sell; § Trade orders). Each turn every court publishes one
## auto-offer per developed estate, naming the source tile so first right of
## refusal can attribute the sale. The ledger aggregates them for display; the
## matcher consumes the per-tile orders (REQ-P2-03, REQ-P3-03).

## One unit per held resource tile: the bootstrap non-Great-Power yield (minors
## never develop, so level 1 is the whole estate).
const PER_TILE_YIELD: int = 1


## Stable row key for the ledger: one row per seller and commodity.
static func offer_id(faction: int, commodity: String) -> String:
	return "%d:%s" % [faction, commodity]


## Display ask: deals clear at the published price (wiki: § Price discovery).
static func unit_price(
	market: WorldMarket,
	commodity: String,
	buyer: int = FactionCatalog.PLAYER_FACTION
) -> int:
	if market == null or not market.can_trade(commodity):
		return 0
	return maxi(
		roundi(float(market.price(commodity)) * market.term_multiplier(buyer, commodity, true)),
		1
	)


## One auto-offer per Minor/Tribe estate, purchased deeds included. A sold tile
## keeps its seller and origin, so the owning Great Power's bid can claim it
## first (world-market § First right of refusal).
static func emit_orders(world: WorldMap) -> Array[MarketOrder]:
	var orders: Array[MarketOrder] = []
	if world == null:
		return orders
	for model: MapModel in world.regions:
		if model == null:
			continue
		for province: ProvinceState in model.provinces:
			var seller: int = model.province_owner(province.id)
			var kind: int = FactionCatalog.type_of(seller)
			if (
				kind != FactionCatalog.Type.MINOR_NATION
				and kind != FactionCatalog.Type.TRIBE
			):
				continue
			for tile: Vector2i in province.tiles:
				var resource: int = model.resource_at(tile.x, tile.y)
				var commodity: String = Extraction.commodity_for_resource(resource)
				if commodity.is_empty() or not CommodityCatalog.is_tradeable(commodity):
					continue
				var index: int = model.index_of(tile.x, tile.y)
				if index < 0:
					continue
				orders.append(MarketOrder.create(
					seller,
					commodity,
					MarketOrder.SIDE_OFFER,
					PER_TILE_YIELD,
					1,
					model.region_id,
					index,
					true
				))
	orders.sort_custom(func(a: MarketOrder, b: MarketOrder) -> bool:
		if a.faction != b.faction:
			return a.faction < b.faction
		if a.origin_region != b.origin_region:
			return a.origin_region < b.origin_region
		if a.origin_index != b.origin_index:
			return a.origin_index < b.origin_index
		return a.commodity < b.commodity
	)
	return orders


## The ledger's aggregated book: one row per seller and commodity, richest
## first. `buyer` is kept for signature compatibility; the market is global.
static func emit(
	world: WorldMap, market: WorldMarket, _buyer: int = FactionCatalog.PLAYER_FACTION
) -> Array[Dictionary]:
	var rows: Dictionary = {}
	if world == null or market == null:
		return []
	for order: MarketOrder in emit_orders(world):
		var key: String = offer_id(order.faction, order.commodity)
		if not rows.has(key):
			rows[key] = {
				"id": key,
				"faction": order.faction,
				"commodity": order.commodity,
				"quantity": 0,
				"unit_price": unit_price(market, order.commodity),
			}
		var row: Dictionary = rows[key]
		row["quantity"] = int(row["quantity"]) + order.remaining()
	var offers: Array[Dictionary] = []
	for raw: Variant in rows.values():
		offers.append(raw)
	offers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["faction"]) != int(b["faction"]):
			return int(a["faction"]) < int(b["faction"])
		if int(a["quantity"]) != int(b["quantity"]):
			return int(a["quantity"]) > int(b["quantity"])
		return String(a["commodity"]) < String(b["commodity"])
	)
	return offers


## Publishes this turn's Minor Nation and Tribe rows for the ledger and save.
static func publish(market: WorldMarket, world: WorldMap, buyer: int) -> void:
	if market == null:
		return
	if world == null:
		market.minor_offers.clear()
		return
	market.minor_offers = emit(world, market, buyer)


## Index of an offer in the live ledger book, or -1 when it is gone.
static func index_of(offers: Array, offer_id_value: String) -> int:
	for index in offers.size():
		if String((offers[index] as Dictionary).get("id", "")) == offer_id_value:
			return index
	return -1


## Units still on the table for one ledger row (0 when sold out).
static func remaining(offers: Array, offer_id_value: String) -> int:
	var index: int = index_of(offers, offer_id_value)
	if index < 0:
		return 0
	return int((offers[index] as Dictionary).get("quantity", 0))


## Legacy direct purchase, retained for tools that trade outside a turn. Live
## play stages a bid instead, so first right of refusal and the tier ordering
## apply (world-market § Trade orders).
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
	var unit: int = int(offer.get("unit_price", 0))
	var cost: int = unit * quantity
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
		"unit_price": unit,
		"cost": cost,
		"commodity": commodity,
		"faction": seller,
		"quantity": quantity,
	}
