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
static func best_candidate(query: AiWorkQuery) -> Dictionary:
	if query.config == null or query.model == null or query.unit == null:
		return {}
	if query.unit.type_id != "merchant":
		return {}
	if not query.reserved.is_empty() and query.reserved.has(query.unit.tile):
		return {}
	# The Merchant a voyage will board takes no deed: it waits at the harbour
	# for the claim (#1127).
	if CivilianMuster.held_for_voyage(query.unit, query.context):
		return {}
	if not buyable_tiles(
		query.model, query.unit.owner, query.works, query.context
	).has(query.unit.tile):
		return {}
	return AiCivilianCandidate.make(
		query, LandPurchase.ACTION, query.unit.tile,
		_score(query, query.unit.tile)
	)


## One legal march toward the nearest buyable tile, or {} when the court has no
## offer it could sign (no embassy, a war with the seller, or an empty purse).
## The Merchant a voyage will board walks to its crown's harbour instead and
## waits there, so the claim sails without marching the crew off the map
## (wiki: civilian-units § Overseas deployment; #1127).
static func best_move(
	model: MapModel, unit: CivilianState, works: LandWorks, context: Dictionary = {}
) -> Dictionary:
	if model == null or unit == null or unit.type_id != "merchant":
		return {}
	if CivilianMuster.held_for_voyage(unit, context):
		return CivilianMuster.muster_move(
			model, unit, context, context.get("visibility", null)
		)
	var goals: Array[Vector2i] = buyable_tiles(model, unit.owner, works, context)
	if goals.is_empty():
		return {}
	var goal: Vector2i = AiLandRoute.nearest(goals, unit.tile)
	var view: VisibilityModel = context.get("visibility", null)
	return AiLandRoute.step_toward(model, unit, goal, view)


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
		# A boycotted court has no deed to sign here, so the planner must not
		# name one or march toward it (wiki: diplomacy § GP–Tribe — Boycott, R6).
		if DiplomacyTrade.blocked_by_boycott(diplomacy, faction, seller):
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


## Cheapest deed on offer from one seller, or 0 when nothing there can be signed
## **this turn**: the published price must fit the treasury the caller passes.
## A coarse reading for the diplomacy planner: the province's headline resource
## is enough to know a court would want its envoy chain opened. `view` is the
## buyer's chart of that region, so a province it has never reached offers
## nothing it can price — the same `fogged` bar `buyable_tiles` holds
## (wiki: fog-and-exploration § Visibility Levels; DR-20261113-03).
static func cheapest_offer(
	model: MapModel, faction: int, seller: int, treasury: int,
	view: VisibilityModel = null
) -> int:
	var price: int = priced_offer(model, faction, seller, view)
	return price if price <= treasury else 0


## The same coarse read without the treasury bar: the deed's published price
## whenever charted land offers one, so the envoy chain may open before the
## court can pay — the chain takes turns to walk and the purse refills while it
## does (issue #724; wiki: civilian-units § Merchant).
static func priced_offer(
	model: MapModel, faction: int, seller: int, view: VisibilityModel = null
) -> int:
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
		if view != null and not view.is_province_known(province.id):
			continue
		var tile: Vector2i = province.resource_tile
		if tile.x < 0 or model.is_purchased_tile(tile):
			continue
		if model.resource_at(tile.x, tile.y) == MapModel.NO_ID:
			continue
		var price: int = LandPurchase.cost(model, tile)
		if price <= 0:
			continue
		if best == 0 or price < best:
			best = price
	return best


## The Minor or Tribe whose deed this court would sign first, or -1 when no
## charted seller offers one: the cheapest priced offer across every region the
## court has charted, with neither war nor boycott in the way. One seller, not
## every seller — the warmth that prices a deed is the warmth that bars the war,
## so a court warms the one partner it means to buy from and keeps every
## conquest target cold (issue #841, the owner's warmth-targeting decision on
## #840; wiki: civilian-units § Merchant; diplomacy § GP AI policy for war vs.
## relations).
static func deed_seller(
	world: WorldMap, faction: int, charts: CourtCharts, diplomacy: DiplomacyState
) -> int:
	if world == null or diplomacy == null or faction < 0:
		return -1
	var best: int = -1
	var best_price: int = 0
	for index in world.region_count():
		var model: MapModel = world.region(index)
		if model == null:
			continue
		var view: VisibilityModel = charts.model_for(faction, index) if charts != null else null
		var deed: Dictionary = openable_deed(
			model, faction, {"diplomacy": diplomacy, "visibility": view}
		)
		if deed.is_empty():
			continue
		var price: int = int(deed["price"])
		if best < 0 or price < best_price:
			best = int(deed["seller"])
			best_price = price
	return best


## The study that opens the deed path, or "" when the court already holds it or
## has no priced deed to buy. The buyer-exists guard is the deed itself: a court
## with nothing on its chart to sign never spends a research slot on the tech
## (issue #841; wiki: civilian-units § Merchant).
static func deed_door(
	world: WorldMap, faction: int, charts: CourtCharts,
	diplomacy: DiplomacyState, tech: Dictionary
) -> String:
	if CivilianCatalog.is_unlocked("merchant", tech):
		return ""
	if deed_seller(world, faction, charts, diplomacy) < 0:
		return ""
	return CivilianCatalog.unlock_tech("merchant")


## True while an envoy chain toward a priced deed still has a rung to walk: a
## charted Minor or Tribe province offers a deed the court holds no embassy
## for, and neither war nor boycott stands in the way. The deed need not be
## affordable yet — this is the openable read the staff planner hires on, the
## court the chain will serve (issue #724; wiki: civilian-units § Merchant).
static func chain_openable(
	model: MapModel, faction: int, context: Dictionary
) -> bool:
	return not openable_deed(model, faction, context, true).is_empty()


## The cheapest deed the court can sign, or is walking its envoy chain toward:
## `{"seller": int, "price": int}` for a charted Minor or Tribe province that
## offers a resource tile at the published 15 x base price, with neither war nor
## boycott in the way. The treasury is deliberately not read: an embassy takes
## turns to open and the purse refills while it does, so this is the deed a
## court saves toward, not only the one it can pay for this turn — the reading
## the objective ledger prices (issue #724; wiki: civilian-units § Merchant).
## `without_embassy` narrows it to the rung a chain still has to walk. {} when
## no charted seller offers one.
static func openable_deed(
	model: MapModel, faction: int, context: Dictionary,
	without_embassy: bool = false
) -> Dictionary:
	var best: Dictionary = {}
	if model == null or faction < 0:
		return best
	var diplomacy: DiplomacyState = context.get("diplomacy", null)
	if diplomacy == null:
		return best
	var view: VisibilityModel = context.get("visibility", null)
	for province: ProvinceState in model.provinces:
		var seller: int = province.owner
		var kind: int = FactionCatalog.type_of(seller)
		if kind != FactionCatalog.Type.MINOR_NATION and kind != FactionCatalog.Type.TRIBE:
			continue
		if seller == faction:
			continue
		if without_embassy and DiplomacyRules.has_embassy(diplomacy, faction, seller):
			continue
		if DiplomacyRules.at_war_with(diplomacy, faction, seller):
			continue
		if DiplomacyTrade.blocked_by_boycott(diplomacy, faction, seller):
			continue
		if view != null and not view.is_province_known(province.id):
			continue
		# The price of this province's headline deed — the same row
		# `priced_offer` reads, one province at a time so the cheapest seller is
		# found in a single pass.
		var tile: Vector2i = province.resource_tile
		if tile.x < 0 or model.is_purchased_tile(tile):
			continue
		if model.resource_at(tile.x, tile.y) == MapModel.NO_ID:
			continue
		var price: int = LandPurchase.cost(model, tile)
		if price <= 0:
			continue
		if best.is_empty() or price < int(best["price"]):
			best = {"seller": seller, "price": price}
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
## civilian-units § Merchant; § Work Order Summary). A deed that clears straight
## to the treasury is worth the cash its ground pays — the same reading a mine's
## next level takes (`AiBuilderWork.RICHES_CASH`; issues #1382, #1383) — so a rich
## tile outranks a crop deed of the same published price, while a raw the workshop
## is short of still leads it, because a point of need is worth five.
static func _score(query: AiWorkQuery, tile: Vector2i) -> int:
	var commodity: String = Extraction.commodity_for_resource(
		query.model.resource_at(tile.x, tile.y)
	)
	var score: int = query.config.parameter("civilian.merchant_weight")
	score += AiBuilderWork.need(
		commodity, query.stockpile, query.config.parameter("civilian.need_target")
	) * 5
	if CommodityCatalog.is_riches(commodity):
		score += CommodityCatalog.base_price(commodity) * AiBuilderWork.RICHES_CASH / 100
	return score
