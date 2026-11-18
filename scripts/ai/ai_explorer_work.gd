class_name AiExplorerWork
extends RefCounted
## Rival Explorer policy (wiki: civilian-work-planner, fog-and-exploration;
## DR-20261110-21, DR-20261111-26). An Explorer surveys the province it stands in
## when its own court knows that province but has not charted all of it, reads
## the unsurveyed ground underfoot, and otherwise walks toward the nearest
## unsurveyed prospectable tile on its crown's land — or, with nothing left to
## read, toward the nearest charted province that still holds unknown ground.
##
## A mineral is hidden until the survey lands, so no plan may price it: the
## Explorer digs the ground its court can see, not a deposit it cannot.
##
## Every candidate runs CivilianWork, and the court's own chart gates what it
## may look at: an Explorer never marches into fog it has not broken and never
## surveys land it has not seen (REQ-P2-03, REQ-P3-03).


## A work order for an idle Explorer, or {} when none is legal.
static func best_candidate(query: AiWorkQuery) -> Dictionary:
	var view: VisibilityModel = query.view()
	if query.reserved.has(query.unit.tile):
		return {}
	if _held_for_voyage(query.unit, query.context):
		return {}
	var explore: Dictionary = _survey_candidate(query, view)
	if not explore.is_empty():
		return explore
	if query.model.owner_at(query.unit.tile.x, query.unit.tile.y) != query.unit.owner:
		return {}
	if not MineralSurvey.can_prospect(
		query.model, query.works, query.unit.owner, query.unit.tile, view
	):
		return {}
	# The deposit is unknown until the survey lands, so the order is priced on
	# the ground, never on a mineral the court has not seen (DR-20261111-26).
	var score: int = query.config.parameter("civilian.prospect_weight")
	return AiCivilianCandidate.make(query, "prospect", query.unit.tile, score)


## One legal march toward the next unexplored chart, or {} when the court has
## nothing left to explore and no mineral to reach. A colonist mustering for a
## voyage walks to its crown's harbour and waits there instead.
static func best_move(
	model: MapModel, unit: CivilianState, works: LandWorks, context: Dictionary = {}
) -> Dictionary:
	var view: VisibilityModel = context.get("visibility", null)
	var mustering: Vector2i = _port_tile(context)
	if _held_for_voyage(unit, context):
		if _at_port(model, unit, mustering):
			return {}
		return AiLandRoute.step_toward(model, unit, mustering, view)
	var goal: Vector2i = _goal(model, unit, works, view, context)
	if goal.x < 0:
		return {}
	return AiLandRoute.step_toward(model, unit, goal, view)


## The muster tile the civilian pass set while a voyage is pending, or (-1, -1).
static func _port_tile(context: Dictionary) -> Vector2i:
	return context.get("muster_port", Vector2i(-1, -1))


## True when this Explorer is the crew the pending voyage will board, so it
## takes no work and waits at the harbour. Only that one waits: a crown's other
## Explorers keep surveying and prospecting the home ground while a colony
## sails (issue #894; wiki: civilian-units § Overseas deployment). A caller that
## hands in no pick keeps the published reading — the harbour holds the crew.
static func _held_for_voyage(unit: CivilianState, context: Dictionary) -> bool:
	if _port_tile(context).x < 0:
		return false
	if not context.has("muster_unit"):
		return true
	return int(context["muster_unit"]) == unit.id


static func _at_port(model: MapModel, unit: CivilianState, port: Vector2i) -> bool:
	var here: int = model.province_at(unit.tile.x, unit.tile.y)
	return here != MapModel.NO_ID and here == model.province_at(port.x, port.y)


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
## known tile of a province that still holds unknown ground and may be surveyed
## (a Minor Nation or Tribe needs its Consulate, as for the player).
static func _goal(
	model: MapModel, unit: CivilianState, works: LandWorks, view: VisibilityModel,
	context: Dictionary
) -> Vector2i:
	var best: Vector2i = _nearest_unsurveyed(model, unit, works, view)
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


static func _nearest_unsurveyed(
	model: MapModel, unit: CivilianState, works: LandWorks, view: VisibilityModel
) -> Vector2i:
	var prospects: Array[Vector2i] = []
	for tile: Vector2i in model.ownership.owned_tiles(model, unit.owner):
		if MineralSurvey.can_prospect(model, works, unit.owner, tile, view):
			prospects.append(tile)
	return AiLandRoute.nearest(prospects, unit.tile)
