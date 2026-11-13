class_name MinorMarket
extends RefCounted
## Market supply from Minor Nations and Tribes (wiki: world-market § Minor and
## tribe auto-sell; § Trade orders). Each turn every court publishes one
## auto-offer per developed estate, naming the source tile so first right of
## refusal can attribute the sale, plus one per developed province town for the
## manufactures it pays. The ledger aggregates them for display; the matcher
## consumes the per-tile orders (REQ-P2-03, REQ-P3-03).

## One unit per held resource tile: the bootstrap non-Great-Power yield (minors
## never develop, so level 1 is the whole estate).
const PER_TILE_YIELD: int = 1


## Stable row key for the ledger: one row per seller and commodity.
static func offer_id(faction: int, commodity: String) -> String:
	return "%d:%s" % [faction, commodity]


## The commodity a Minor or Tribe estate actually yields, or "" when the court
## cannot work it. Minors and Tribes never prospect, so a mineral tile stays in
## the ground, and riches never trade on the market (wiki:
## extraction-and-improvements § Non-Great-Power extraction; world-market
## § Tradeable commodities).
static func estate_commodity(model: MapModel, tile: Vector2i) -> String:
	var resource: int = model.resource_at(tile.x, tile.y)
	if ImprovementCatalog.needs_prospecting(resource):
		return ""
	var commodity: String = Extraction.commodity_for_resource(resource)
	if commodity.is_empty() or not CommodityCatalog.is_tradeable(commodity):
		return ""
	return commodity


## One province's raw this turn, commodity -> units: its estates at the
## bootstrap level-1 yield. The world map carries no per-tile works, so every
## estate in the province counts as town-connected — the same assumption the
## estate book makes (wiki: extraction-and-improvements
## § Non-Great-Power extraction).
static func province_raw(model: MapModel, province: ProvinceState) -> Dictionary:
	var raw: Dictionary = {}
	for tile: Vector2i in province.tiles:
		var commodity: String = estate_commodity(model, tile)
		if commodity.is_empty():
			continue
		raw[commodity] = int(raw.get(commodity, 0)) + PER_TILE_YIELD
	return raw


## Manufactures a Minor or Tribe province's developed town pays this turn: the
## town bonus on the raw its own estates grow (wiki: extraction-and-improvements
## § Town manufacturing bonus). Minors never research, so only ungated recipes
## run. The output spends no raw, no labour and no cargo — it is published as a
## system-authored offer instead of landing in a stockpile.
static func province_manufactures(model: MapModel, province: ProvinceState) -> Dictionary:
	if TownIndustry.multiplier(province.town_development) <= 0:
		return {}
	return TownIndustry.bonus_for_province(
		province_raw(model, province), province.town_development, {}
	)


## Display ask: deals clear at the published price, adjusted by the reader's own
## terms and by the subsidy step this pair carries, so the row names the ducats
## the clearing will charge (wiki: world-market § Price discovery, § Subsidy
## price adjustment; REQ-P5-05).
static func unit_price(
	market: WorldMarket,
	commodity: String,
	buyer: int = FactionCatalog.PLAYER_FACTION,
	seller: int = -1
) -> int:
	if market == null or not market.can_trade(commodity):
		return 0
	var percent: int = MarketRules.subsidy_percent(market, buyer, seller)
	var step: float = MarketRules.subsidy_step(
		percent, _is_minor(buyer), seller >= 0 and _is_minor(seller), true
	)
	return MarketRules.deal_unit(market, commodity, buyer, step, true)


static func _is_minor(faction: int) -> bool:
	if faction < 0:
		return false
	var kind: int = FactionCatalog.type_of(faction)
	return kind == FactionCatalog.Type.MINOR_NATION or kind == FactionCatalog.Type.TRIBE


## One auto-offer per Minor/Tribe estate, purchased deeds included, plus one per
## developed province town for the manufactures it pays. A sold tile keeps its
## seller and origin, so the owning Great Power's bid can claim it first
## (world-market § First right of refusal).
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
				var commodity: String = estate_commodity(model, tile)
				if commodity.is_empty():
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
			# A developed town turns part of that harvest into manufactures
			# without spending it (wiki: extraction-and-improvements § Town
			# manufacturing bonus). The town tile is the origin: no deed can buy
			# it, so first right of refusal never claims town output.
			var made: Dictionary = province_manufactures(model, province)
			var town_index: int = model.index_of(
				province.town_tile.x, province.town_tile.y
			)
			if made.is_empty() or town_index < 0:
				continue
			for output: Variant in made.keys():
				orders.append(MarketOrder.create(
					seller,
					String(output),
					MarketOrder.SIDE_OFFER,
					int(made[output]),
					1,
					model.region_id,
					town_index,
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
## first. Every row is priced for the reader against that seller, so a subsidy
## the pair carries shows in the ask the clearing will charge.
static func emit(
	world: WorldMap, market: WorldMarket, buyer: int = FactionCatalog.PLAYER_FACTION
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
				"unit_price": unit_price(market, order.commodity, buyer, order.faction),
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
