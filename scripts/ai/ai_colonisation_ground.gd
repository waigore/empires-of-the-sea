class_name AiColonisationGround
extends RefCounted
## Landing ground weights for rival colonisation voyages
## (wiki: civilian-units § Overseas deployment; DR-20261119-05; issue #1382).
##
## The court's workshop appetite and earn-posture riches bet pick which coast
## an expedition sails for and which tile it lands on. Pure rules: chart and
## appetite in, ranked zones or tile weights out (REQ-P2-03, REQ-P3-01,
## REQ-P3-03). [AiColonisationPlanner] keeps the public door; voyage steps live
## on [AiColonisationVoyage].

## The one crew that may read ground: only an Explorer digs a deposit out of the
## chart, so only an Explorer's landing is worth aiming at hills (issue #1382).
const EXPLORER: String = "explorer"

## Appetite key for mineral-bearing terrain while the court sails for income.
const RICHES_KEY: String = "riches"

## Weight one prospectable tile carries while the court sails for income: enough
## to outrank bare ground and a crop nobody is short of, never a raw the
## workshop wants (a wanted raw counts its own shortfall, one point a unit).
const RICHES_GROUND: int = 1

## The shift that puts a wanted raw's shortfall above every riches weight: the
## richest configured bet (1000) still loses to one unit of workshop need, so the
## treasury read never starves a recipe the court feeds (issue #1382).
const WANTED_SHIFT: int = 1001


## Sea zones with at least one land tile this type may land on, and whose water
## the court has charted. A zone that fronts a ground the court's workshop turns
## comes first, so the expedition sails for the coast that grows what it needs
## (DR-20261119-05); a zone fronting ground worth surveying follows `riches`
## while the court sails for income (issue #1382); the zone id breaks every tie,
## so a caller with no appetite keeps the published order.
static func landing_zones(
	model: MapModel, type_id: String, owner: int, charts: CourtCharts = null,
	appetite: Dictionary = {}, riches: int = 0
) -> Array[int]:
	var weights: Dictionary = {}
	for zone: SeaZoneState in model.sea_zones:
		if charts != null and not charts.knows_zone(owner, model.region_id, zone.id):
			continue
		for water: Vector2i in zone.tiles:
			for tile: Vector2i in CivilianMovement.NEIGHBORS:
				var land: Vector2i = water + tile
				if not model.in_bounds(land.x, land.y) or not model.is_land(land.x, land.y):
					continue
				if not CivilianMovement.may_enter(model, type_id, owner, land):
					continue
				if charts != null:
					var view: VisibilityModel = charts.model_for(owner, model.region_id)
					if view != null and view.level_at(land.x, land.y) < VisibilityModel.Level.FOGGED:
						continue
				var weight: int = ground_weight(model, land, appetite, riches)
				if not weights.has(zone.id) or weight > int(weights[zone.id]):
					weights[zone.id] = weight
	var zones: Array[int] = []
	for id: Variant in weights.keys():
		zones.append(int(id))
	zones.sort_custom(func(a: int, b: int) -> bool:
		if int(weights[a]) != int(weights[b]):
			return int(weights[a]) > int(weights[b])
		return a < b
	)
	return zones


## How much this ground is worth to the court on its water: the appetite weight of
## the commodity the tile carries, else the bet on ground an Explorer can survey,
## else zero (DR-20261119-05).
##
## The treasury is read beside the workshop (issue #1382): on prospectable ground
## (swamp, hills, mountain, desert) a tile nobody's workshop wants carries the
## appetite's `riches` weight — `economy.riches_route_weight`, set once the court
## charts the New World — and the earn-posture Explorer bet (`riches` arg), the
## bigger read winning. A raw the workshop is short of always leads: its shortfall
## is shifted above every bet, so the riches read outranks bare ground and a crop
## nobody is short of and never starves a recipe the workshop feeds. No mineral is
## named, priced or planned on: the weight rides the terrain, not a deposit, so the
## fog rule holds (DR-20261111-26) and the appetite's own mineral exclusion stands.
## A caller with no appetite and no bet keeps the compass order.
static func ground_weight(
	model: MapModel, tile: Vector2i, appetite: Dictionary, riches: int = 0
) -> int:
	var resource: int = model.resource_at(tile.x, tile.y)
	if resource >= 0 and not appetite.is_empty():
		var commodity: String = ImprovementCatalog.commodity(resource)
		if not commodity.is_empty():
			var wanted: int = maxi(int(appetite.get(commodity, 0)), 0)
			if wanted > 0:
				return wanted * WANTED_SHIFT
	if MineralSurvey.prospectable(model, tile):
		return mini(
			maxi(int(appetite.get(RICHES_KEY, 0)), maxi(riches, 0)),
			WANTED_SHIFT - 1
		)
	return 0
