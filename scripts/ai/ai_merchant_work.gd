class_name AiMerchantWork
extends RefCounted
## Rival Merchant policy (wiki: civilian-units § Merchant, § Work Order Summary;
## civilian-work-planner § Merchant tasks). A Merchant buys a resource tile in a
## Minor Nation or Tribe province: the same embassy, peace and prospecting gates
## the player answers to, priced at 15 x the resource's base market price.
##
## The planner only ever names the merchant's own tile, so a rival may not sign a
## deed at a distance (wiki: § Work Types and Multi-Turn Builds — civilians move
## to and act on a tile). When the tile is out of reach it walks one legal step
## toward the nearest offer the court can close. Every candidate runs
## CivilianWork, so a planner cannot invent an outcome or spend twice
## (REQ-P2-03, REQ-P3-03). Pure rules: state in, order out.


## A purchase order for an idle Merchant standing on a buyable tile, or {}.
static func best_candidate(
	config: AiConfig,
	model: MapModel,
	unit: CivilianState,
	units: Array,
	works: LandWorks,
	stockpile: Dictionary,
	tech_caps: Dictionary,
	tech_unlocked: Dictionary,
	context: Dictionary,
	reserved: Dictionary
) -> Dictionary:
	if config == null or model == null or unit == null:
		return {}
	if unit.type_id != "merchant":
		return {}
	if not reserved.is_empty() and reserved.has(unit.tile):
		return {}
	if not buyable_tiles(model, unit.owner, works, context).has(unit.tile):
		return {}
	return AiCivilianCandidate.make(
		model, unit, LandPurchase.ACTION, unit.tile, works, units, stockpile,
		tech_caps, tech_unlocked, context, _score(config, model, unit.tile, stockpile)
	)


## One legal march toward the nearest buyable tile, or {} when the court has no
## offer it could sign (no embassy, a war with the seller, or an empty purse).
static func best_move(
	model: MapModel, unit: CivilianState, works: LandWorks, context: Dictionary = {}
) -> Dictionary:
	if model == null or unit == null or unit.type_id != "merchant":
		return {}
	var goals: Array[Vector2i] = buyable_tiles(model, unit.owner, works, context)
	if goals.is_empty():
		return {}
	var goal: Vector2i = _nearest(goals, unit.tile)
	var view: VisibilityModel = context.get("visibility", null)
	var best: Dictionary = {}
	for tile: Vector2i in CivilianMovement.valid_tiles(model, unit, view):
		var distance: int = absi(tile.x - goal.x) + absi(tile.y - goal.y)
		if best.is_empty() or distance < int(best["distance"]):
			best = {"kind": "move", "unit_id": unit.id, "tile": tile, "distance": distance}
		elif distance == int(best["distance"]) and tile < Vector2i(best["tile"]):
			best = {"kind": "move", "unit_id": unit.id, "tile": tile, "distance": distance}
	return best


## Every tile this court could buy this turn, in row-major order: a resource tile
## in a Minor or Tribe province that is not already deeded, sold to a court with
## an embassy and no war, at a price the treasury covers, and (for a mineral)
## prospected by the buyer (wiki: civilian-units § Merchant).
static func buyable_tiles(
	model: MapModel, faction: int, works: LandWorks, context: Dictionary
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if model == null or faction < 0:
		return result
	var diplomacy: DiplomacyState = context.get("diplomacy", null)
	if diplomacy == null:
		return result
	var view: VisibilityModel = context.get("visibility", null)
	var treasury: int = int(context.get("treasury", 0))
	for province: ProvinceState in model.provinces:
		var seller: int = province.owner
		var kind: int = FactionCatalog.type_of(seller)
		if kind != FactionCatalog.Type.MINOR_NATION and kind != FactionCatalog.Type.TRIBE:
			continue
		if seller == faction:
			continue
		if view != null and not view.is_province_known(province.id):
			continue
		if DiplomacyRules.at_war_with(diplomacy, faction, seller):
			continue
		if not DiplomacyRules.has_embassy(diplomacy, faction, seller):
			continue
		for tile: Vector2i in province.tiles:
			if not _buyable_tile(model, faction, works, tile, treasury):
				continue
			result.append(tile)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	return result


## Cheapest deed on offer from one seller, or 0 when nothing there can be signed.
## A coarse reading for the diplomacy planner: the province's headline resource
## is enough to know a court would want its envoy chain opened.
static func cheapest_offer(model: MapModel, faction: int, seller: int, treasury: int) -> int:
	if model == null:
		return 0
	if FactionCatalog.type_of(seller) != FactionCatalog.Type.MINOR_NATION and (
		FactionCatalog.type_of(seller) != FactionCatalog.Type.TRIBE
	):
		return 0
	var best: int = 0
	for province: ProvinceState in model.provinces:
		if province.owner != seller:
			continue
		var tile: Vector2i = province.resource_tile
		if tile.x < 0 or model.is_purchased_tile(tile):
			continue
		if model.resource_at(tile.x, tile.y) == MapModel.NO_ID:
			continue
		var price: int = LandPurchase.cost(model, tile)
		if price <= 0 or price > treasury:
			continue
		if best == 0 or price < best:
			best = price
	return best


static func _buyable_tile(
	model: MapModel, faction: int, works: LandWorks, tile: Vector2i, treasury: int
) -> bool:
	if model.is_purchased_tile(tile):
		return false
	var resource: int = model.resource_at(tile.x, tile.y)
	if resource == MapModel.NO_ID:
		return false
	if Extraction.commodity_for_resource(resource).is_empty():
		return false
	var price: int = LandPurchase.cost(model, tile)
	if price <= 0 or price > treasury:
		return false
	if not ImprovementCatalog.needs_prospecting(resource):
		return true
	return works != null and works.is_prospected(faction, model, tile)


## A deed is worth the base weight plus how short the court is of that commodity,
## so a grain estate is bought before a fourth timber one (wiki:
## civilian-units § Merchant; § Work Order Summary).
static func _score(
	config: AiConfig, model: MapModel, tile: Vector2i, stockpile: Dictionary
) -> int:
	var commodity: String = Extraction.commodity_for_resource(
		model.resource_at(tile.x, tile.y)
	)
	var score: int = config.parameter("civilian.merchant_weight")
	score += AiBuilderWork.need(
		commodity, stockpile, config.parameter("civilian.need_target")
	) * 5
	return score


static func _nearest(goals: Array[Vector2i], from: Vector2i) -> Vector2i:
	var best: Vector2i = goals[0]
	var best_distance: int = absi(best.x - from.x) + absi(best.y - from.y)
	for tile: Vector2i in goals:
		var distance: int = absi(tile.x - from.x) + absi(tile.y - from.y)
		if distance < best_distance or (distance == best_distance and tile < best):
			best = tile
			best_distance = distance
	return best
