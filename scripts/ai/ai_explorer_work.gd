class_name AiExplorerWork
extends RefCounted
## Rival Explorer policy (wiki: civilian-work-planner, fog-and-exploration;
## DR-20261110-21, DR-20261111-26). An Explorer surveys the province it stands in
## when its own court knows that province but has not charted all of it, reads the
## unsurveyed ground underfoot, and otherwise walks toward the nearest unsurveyed
## prospectable tile on its crown's land or on the ground of a Minor Nation or
## Tribe whose deed it could sign (issue #1383) — or, with nothing left to read,
## toward the nearest charted province that still holds unknown ground.
##
## A mineral is hidden until the survey lands, so no plan may price it: the
## Explorer digs the ground its court can see, not a deposit it cannot.
##
## Every candidate runs CivilianWork, and the court's own chart gates what it
## may look at: an Explorer never marches into fog it has not broken and never
## surveys land it has not seen (REQ-P2-03, REQ-P3-03).


## **The Merchant's deed ground is the Explorer's to read** (issue #1383): the
## deed book reaches the rich tiles only for a court that has surveyed them, and
## no rival Explorer ever dug foreign ground — `_nearest_unsurveyed` walked the
## crown's own tiles only — so the gold, silver, gem and diamond deeds were a
## player's alone. A court reads a Minor Nation's or Tribe's charted ground where
## it could sign the deed that ground is sold by: the seller is a Minor or Tribe,
## the court holds an embassy with it, and neither war nor boycott stands in the
## way — the exact gates [LandPurchase] answers, restated as a survey gate. The
## deposit is never read: only the seller, the footing and the bond decide, so a
## plan can never price a mineral the court has not surveyed (REQ-P2-03).


## A work order for an idle Explorer, or {} when none is legal.
static func best_candidate(query: AiWorkQuery) -> Dictionary:
	var view: VisibilityModel = query.view()
	if query.reserved.has(query.unit.tile):
		return {}
	if CivilianMuster.held_for_voyage(query.unit, query.context):
		return {}
	var explore: Dictionary = _survey_candidate(query, view)
	if not explore.is_empty():
		return explore
	var own: bool = (
		query.model.owner_at(query.unit.tile.x, query.unit.tile.y) == query.unit.owner
	)
	if not own and not deed_ground(
		query.model, query.unit.owner, query.unit.tile, query.context
	):
		return {}
	if not MineralSurvey.can_prospect(
		query.model, query.works, query.unit.owner, query.unit.tile, view
	):
		return {}
	# The deposit is unknown until the survey lands, so the order is priced on
	# the ground, never on a mineral the court has not seen (DR-20261111-26).
	var score: int = query.config.parameter("civilian.prospect_weight")
	return AiCivilianCandidate.make(query, "prospect", query.unit.tile, score)


## True when this court may survey foreign ground here (issue #1383): the tile
## sits in a Minor Nation's or Tribe's province whose court it holds an embassy
## with, at peace and unbought out of no boycott — the gates [LandPurchase.check]
## answers before a deed is signed. Province ownership and faction type are public
## readings (fog-and-exploration § Province ownership intel) and no deposit is
## named, so the gate never leaks a hidden mineral. Without a court in `context`
## the gate is closed: the published own-land read stands.
static func deed_ground(
	model: MapModel, owner: int, tile: Vector2i, context: Dictionary
) -> bool:
	if model == null or owner < 0 or tile.x < 0:
		return false
	var province: int = model.province_at(tile.x, tile.y)
	if province == MapModel.NO_ID:
		return false
	return _seller_allows(model, owner, model.province_owner(province), context)


## One seller's deed gate, shared by the tile read and the province walk.
static func _seller_allows(
	model: MapModel, owner: int, seller: int, context: Dictionary
) -> bool:
	if model == null or seller == MapModel.NO_ID or seller == owner:
		return false
	var kind: int = FactionCatalog.type_of(seller)
	if kind != FactionCatalog.Type.MINOR_NATION and kind != FactionCatalog.Type.TRIBE:
		return false
	var diplomacy: DiplomacyState = context.get("diplomacy", null)
	if diplomacy == null:
		return false
	if DiplomacyRules.at_war_with(diplomacy, owner, seller):
		return false
	if DiplomacyTrade.blocked_by_boycott(diplomacy, owner, seller):
		return false
	return DiplomacyRules.has_embassy(diplomacy, owner, seller)


## One legal march toward the next unexplored chart, or {} when the court has
## nothing left to explore and no mineral to reach. A colonist mustering for a
## voyage walks to its crown's harbour and waits there instead.
static func best_move(
	model: MapModel, unit: CivilianState, works: LandWorks, context: Dictionary = {}
) -> Dictionary:
	var view: VisibilityModel = context.get("visibility", null)
	if CivilianMuster.held_for_voyage(unit, context):
		return CivilianMuster.muster_move(model, unit, context, view)
	var goal: Vector2i = _goal(model, unit, works, view, context)
	if goal.x < 0:
		return {}
	return AiLandRoute.step_toward(model, unit, goal, view)


## Exploring a partly charted province is the Explorer's first duty: the tiles
## its crown has not seen cannot be bought, worked or planned on.
static func _survey_candidate(
	query: AiWorkQuery, view: VisibilityModel
) -> Dictionary:
	if view == null:
		return {}
	var province: int = query.model.province_at(
		query.unit.tile.x, query.unit.tile.y
	)
	if province == MapModel.NO_ID:
		return {}
	if not view.is_province_known(province):
		return {}
	if view.is_province_fully_visible(province):
		return {}
	var score: int = query.config.parameter("civilian.prospect_weight")
	if query.model.region_id == WorldMap.NEW_WORLD:
		score += 20
	return AiCivilianCandidate.make(query, "explore", query.unit.tile, score)


## Nearest unsurveyed prospectable tile on the crown's own land, else the nearest
## charted tile of a Minor Nation or Tribe the court could sign a deed with
## (issue #1383), else the nearest known tile of a province that still holds
## unknown ground and may be surveyed (a Minor Nation or Tribe needs its
## Consulate, as for the player).
static func _goal(
	model: MapModel, unit: CivilianState, works: LandWorks, view: VisibilityModel,
	context: Dictionary
) -> Vector2i:
	var best: Vector2i = _nearest_unsurveyed(model, unit, works, view, context)
	if best.x >= 0 or view == null:
		return best
	var reachable: Array[Vector2i] = []
	for province: ProvinceState in model.provinces:
		if not view.is_province_known(province.id):
			continue
		if view.is_province_fully_visible(province.id):
			continue
		for tile: Vector2i in province.tiles:
			if view.level_at(tile.x, tile.y) < VisibilityModel.Level.FOGGED:
				continue
			if not CivilianExplorerGates.explore_refusal(
				model, unit.owner, province.id, context
			).is_empty():
				continue
			reachable.append(tile)
	return AiLandRoute.nearest(reachable, unit.tile)


## Every tile this court may still survey, its own ground first and then the
## deed ground it could buy (issue #1383). The foreign reading is silent when the
## caller publishes no court, so the published own-land walk is unchanged.
static func _nearest_unsurveyed(
	model: MapModel, unit: CivilianState, works: LandWorks, view: VisibilityModel,
	context: Dictionary
) -> Vector2i:
	var prospects: Array[Vector2i] = []
	for tile: Vector2i in model.ownership.owned_tiles(model, unit.owner):
		if MineralSurvey.can_prospect(model, works, unit.owner, tile, view):
			prospects.append(tile)
	prospects.append_array(_deed_prospects(model, unit.owner, works, view, context))
	return AiLandRoute.nearest(prospects, unit.tile)


## The surveyable ground of every Minor Nation and Tribe whose deed this court
## could sign, in row-major order (issue #1383). A seller's ground is walked only
## once the seller passes the deed gate, and each tile still answers the survey
## rule's own terrain, chart and prospecting bars — no deposit is read.
static func _deed_prospects(
	model: MapModel, owner: int, works: LandWorks, view: VisibilityModel,
	context: Dictionary
) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if context.get("diplomacy", null) == null:
		return tiles
	for province: ProvinceState in model.provinces:
		if not _seller_allows(model, owner, province.owner, context):
			continue
		if view != null and not view.is_province_known(province.id):
			continue
		for tile: Vector2i in province.tiles:
			if MineralSurvey.can_prospect(model, works, owner, tile, view):
				tiles.append(tile)
	return tiles
