class_name MainlineAiExplorerWork
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
static func best_candidate(
	config: MainlineAiConfig,
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
	var view: VisibilityModel = context.get("visibility", null)
	if reserved.has(unit.tile):
		return {}
	if _marching_to_port(model, unit, context):
		return {}
	var explore: Dictionary = _survey_candidate(
		config, model, unit, units, works, stockpile, tech_caps, tech_unlocked,
		context, view
	)
	if not explore.is_empty():
		return explore
	if model.owner_at(unit.tile.x, unit.tile.y) != unit.owner:
		return {}
	if not MineralSurvey.can_prospect(model, works, unit.owner, unit.tile, view):
		return {}
	# The deposit is unknown until the survey lands, so the order is priced on
	# the ground, never on a mineral the court has not seen (DR-20261111-26).
	var score: int = config.parameter("civilian.prospect_weight")
	return MainlineAiCivilianCandidate.make(
		model, unit, "prospect", unit.tile, works, units, stockpile, tech_caps,
		tech_unlocked, context, score
	)


## One legal march toward the next unexplored chart, or {} when the court has
## nothing left to explore and no mineral to reach. A colonist mustering for a
## voyage walks to its crown's harbour and waits there instead.
static func best_move(
	model: MapModel, unit: CivilianState, works: LandWorks, context: Dictionary = {}
) -> Dictionary:
	var view: VisibilityModel = context.get("visibility", null)
	var mustering: Vector2i = _port_tile(context)
	if mustering.x >= 0:
		if _at_port(model, unit, mustering):
			return {}
		return _step_toward(model, unit, mustering, view)
	var goal: Vector2i = _goal(model, unit, works, view, context)
	if goal.x < 0:
		return {}
	return _step_toward(model, unit, goal, view)


## The muster tile the civilian pass set while a voyage is pending, or (-1, -1).
static func _port_tile(context: Dictionary) -> Vector2i:
	return context.get("muster_port", Vector2i(-1, -1))


## True when the Explorer is mustering and still away from its harbour: it takes
## no work and marches home rather than surveying the ground it stands on.
static func _marching_to_port(
	model: MapModel, unit: CivilianState, context: Dictionary
) -> bool:
	var port: Vector2i = _port_tile(context)
	if port.x < 0 or _at_port(model, unit, port):
		return false
	return true


static func _at_port(model: MapModel, unit: CivilianState, port: Vector2i) -> bool:
	var here: int = model.province_at(unit.tile.x, unit.tile.y)
	return here != MapModel.NO_ID and here == model.province_at(port.x, port.y)


## One legal step that brings the unit closer to `goal`; row-major on a tie so
## the same state always walks the same way.
static func _step_toward(
	model: MapModel, unit: CivilianState, goal: Vector2i, view: VisibilityModel
) -> Dictionary:
	var best: Dictionary = {}
	for tile: Vector2i in CivilianMovement.valid_tiles(model, unit, view):
		var distance: int = absi(tile.x - goal.x) + absi(tile.y - goal.y)
		if best.is_empty() or distance < int(best["distance"]):
			best = {"kind": "move", "unit_id": unit.id, "tile": tile, "distance": distance}
		elif distance == int(best["distance"]) and tile < Vector2i(best["tile"]):
			best = {"kind": "move", "unit_id": unit.id, "tile": tile, "distance": distance}
	return best


## Exploring a partly charted province is the Explorer's first duty: the tiles
## its crown has not seen cannot be bought, worked or planned on.
static func _survey_candidate(
	config: MainlineAiConfig,
	model: MapModel,
	unit: CivilianState,
	units: Array,
	works: LandWorks,
	stockpile: Dictionary,
	tech_caps: Dictionary,
	tech_unlocked: Dictionary,
	context: Dictionary,
	view: VisibilityModel
) -> Dictionary:
	if view == null:
		return {}
	var province: int = model.province_at(unit.tile.x, unit.tile.y)
	if province == MapModel.NO_ID:
		return {}
	if not view.is_province_known(province):
		return {}
	if view.is_province_fully_visible(province):
		return {}
	var score: int = config.parameter("civilian.prospect_weight")
	if model.region_id == WorldMap.NEW_WORLD:
		score += 20
	return MainlineAiCivilianCandidate.make(
		model, unit, "explore", unit.tile, works, units, stockpile, tech_caps,
		tech_unlocked, context, score
	)


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
	var best_distance: int = 1 << 30
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
			var distance: int = absi(tile.x - unit.tile.x) + absi(tile.y - unit.tile.y)
			if distance < best_distance or (distance == best_distance and tile < best):
				best = tile
				best_distance = distance
	return best


static func _nearest_unsurveyed(
	model: MapModel, unit: CivilianState, works: LandWorks, view: VisibilityModel
) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var best_distance: int = 1 << 30
	for tile: Vector2i in model.ownership.owned_tiles(model, unit.owner):
		if not MineralSurvey.can_prospect(model, works, unit.owner, tile, view):
			continue
		var distance: int = absi(tile.x - unit.tile.x) + absi(tile.y - unit.tile.y)
		if distance < best_distance or (distance == best_distance and tile < best):
			best = tile
			best_distance = distance
	return best