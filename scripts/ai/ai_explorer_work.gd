class_name AiExplorerWork
extends RefCounted
## Rival Explorer policy (wiki: civilian-work-planner, fog-and-exploration;
## DR-20261110-21). An Explorer surveys the province it stands in when its own
## court knows that province but has not charted all of it, prospects an
## unprospected mineral on its crown's land, and otherwise walks toward the
## nearest charted province that still holds unknown ground.
##
## Every candidate runs CivilianWork, and the court's own chart gates what it
## may look at: an Explorer never marches into fog it has not broken and never
## surveys land it has not seen (REQ-P2-03, REQ-P3-03).


## A work order for an idle Explorer, or {} when none is legal.
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
	var view: VisibilityModel = context.get("visibility", null)
	if reserved.has(unit.tile):
		return {}
	var explore: Dictionary = _survey_candidate(
		config, model, unit, units, works, stockpile, tech_caps, tech_unlocked,
		context, view
	)
	if not explore.is_empty():
		return explore
	if model.owner_at(unit.tile.x, unit.tile.y) != unit.owner:
		return {}
	var resource: int = model.resource_at(unit.tile.x, unit.tile.y)
	if not ImprovementCatalog.needs_prospecting(resource):
		return {}
	var score: int = config.parameter("civilian.prospect_weight")
	score += AiBuilderWork.need(
		ImprovementCatalog.commodity(resource), stockpile,
		config.parameter("civilian.need_target")
	) * 10
	return AiCivilianCandidate.make(
		model, unit, "prospect", unit.tile, works, units, stockpile, tech_caps,
		tech_unlocked, context, score
	)


## One legal march toward the next unexplored chart, or {} when the court has
## nothing left to explore and no mineral to reach.
static func best_move(
	model: MapModel, unit: CivilianState, works: LandWorks, context: Dictionary = {}
) -> Dictionary:
	var view: VisibilityModel = context.get("visibility", null)
	var goal: Vector2i = _goal(model, unit, works, view, context)
	if goal.x < 0:
		return {}
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
	config: AiConfig,
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
	return AiCivilianCandidate.make(
		model, unit, "explore", unit.tile, works, units, stockpile, tech_caps,
		tech_unlocked, context, score
	)


## Nearest unprospected mineral on the crown's own land, else the nearest known
## tile of a province that still holds unknown ground and may be surveyed (a
## Minor Nation or Tribe needs its Consulate, as for the player).
static func _goal(
	model: MapModel, unit: CivilianState, works: LandWorks, view: VisibilityModel,
	context: Dictionary
) -> Vector2i:
	var best: Vector2i = _nearest_mineral(model, unit, works)
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
			if not CivilianExplorerGates.refusal(
				"explore", model, unit.owner, tile, province.id, view, context
			).is_empty():
				continue
			var distance: int = absi(tile.x - unit.tile.x) + absi(tile.y - unit.tile.y)
			if distance < best_distance or (distance == best_distance and tile < best):
				best = tile
				best_distance = distance
	return best


static func _nearest_mineral(
	model: MapModel, unit: CivilianState, works: LandWorks
) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var best_distance: int = 1 << 30
	for tile: Vector2i in model.ownership.owned_tiles(model, unit.owner):
		if not ImprovementCatalog.needs_prospecting(model.resource_at(tile.x, tile.y)):
			continue
		if works.is_prospected(unit.owner, model, tile):
			continue
		var distance: int = absi(tile.x - unit.tile.x) + absi(tile.y - unit.tile.y)
		if distance < best_distance or (distance == best_distance and tile < best):
			best = tile
			best_distance = distance
	return best
