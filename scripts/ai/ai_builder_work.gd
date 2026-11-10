class_name AiBuilderWork
extends RefCounted
## Builder work policy (wiki: civilian-work-planner, extraction-and-improvements
## § Town manufacturing bonus).
##
## An idle Builder either raises the estate the stores are shortest of or
## finishes a province town. A town at development 2 or 4 turns town-connected
## raw into manufactures for free, so the town's score is the base-price worth of
## the extra output it would pay each turn, divided by [constant VALUE_DIVISOR] so
## it sits on the same scale as the other `civilian.*` weights. Raw that never
## reaches the crown is worth nothing: an overseas province is priced on the tons
## the holds actually landed, and a province with no town-connected raw is never
## upgraded. Every order runs through [AiCivilianCandidate], the same gate the
## player's dossier uses (REQ-P2-03, REQ-P3-03).

## Base-price units per point of score, so a rich town outranks an estate without
## drowning every other order on the court's board.
const VALUE_DIVISOR: int = 8


## Highest-scoring legal Builder order for this court, or {} when the land and
## its towns hold nothing worth doing.
static func best_candidate(
	config: AiConfig,
	model: MapModel,
	unit: CivilianState,
	works: LandWorks,
	units: Array,
	stockpile: Dictionary,
	tech_caps: Dictionary,
	tech_unlocked: Dictionary,
	context: Dictionary,
	reserved: Dictionary,
	town_raw: Dictionary
) -> Dictionary:
	var best: Dictionary = _best_estate(
		config, model, unit, works, units, stockpile, tech_caps, tech_unlocked,
		context, reserved
	)
	return _better(
		best,
		_town_candidate(
			config, model, unit, works, units, stockpile, tech_caps, tech_unlocked,
			context, reserved, town_raw
		)
	)


## How short the stores are of a commodity against the court's target, 0..target.
## The scarcity read every civilian planner scores by.
static func need(commodity: String, stockpile: Dictionary, target: int) -> int:
	if commodity.is_empty():
		return 0
	return clampi(target - int(stockpile.get(commodity, 0)), 0, target)


## Town-connected raw this court can spend on a town bonus: what the holds landed
## for an overseas region, the home region's own harvest otherwise.
static func town_raw(
	model: MapModel,
	owner: int,
	works: LandWorks,
	tech_caps: Dictionary,
	tech_unlocked: Dictionary,
	context: Dictionary
) -> Dictionary:
	if context.has("delivered_raw"):
		return context["delivered_raw"] as Dictionary
	if model == null or works == null:
		return {}
	return Extraction.province_raw(
		model, owner, tech_caps, works,
		context.get("capital_tile", CivilianState.NO_TILE), tech_unlocked
	)


## The estate the stores are shortest of; a fresh estate scores higher than an
## upgrade of the same crop.
static func _best_estate(
	config: AiConfig, model: MapModel, unit: CivilianState, works: LandWorks,
	units: Array, stockpile: Dictionary, tech_caps: Dictionary,
	tech_unlocked: Dictionary, context: Dictionary, reserved: Dictionary
) -> Dictionary:
	var best: Dictionary = {}
	var target: int = config.parameter("civilian.need_target")
	for tile: Vector2i in model.ownership.owned_tiles(model, unit.owner):
		if reserved.has(tile):
			continue
		var resource: int = model.resource_at(tile.x, tile.y)
		if resource == MapModel.NO_ID:
			continue
		var level: int = works.improvement_at(model, tile)
		if level >= LandWorks.MAX_IMPROVEMENT:
			continue
		var crop: String = ImprovementCatalog.commodity(resource)
		var score: int = config.parameter("civilian.improvement_weight")
		score += need(crop, stockpile, target) * 10
		if level <= 0:
			score += 10
		var candidate: Dictionary = AiCivilianCandidate.make(
			model, unit, "build_improvement", tile, works, units, stockpile,
			tech_caps, tech_unlocked, context, score
		)
		best = _better(best, candidate)
	return best


## The town whose finished development is worth the most per turn. Levels 2 and 4
## pay a bonus and level 3 pays none, so the gain is measured at level 4 less what
## the town already pays; the Builder still walks the levels one at a time
## (wiki: extraction-and-improvements § Town manufacturing bonus).
static func _town_candidate(
	config: AiConfig, model: MapModel, unit: CivilianState, works: LandWorks,
	units: Array, stockpile: Dictionary, tech_caps: Dictionary,
	tech_unlocked: Dictionary, context: Dictionary, reserved: Dictionary,
	raw_by_province: Dictionary
) -> Dictionary:
	var best: Dictionary = {}
	if raw_by_province.is_empty():
		return best
	var weight: int = config.parameter("civilian.town_upgrade_weight")
	for province: ProvinceState in model.provinces:
		if province.owner != unit.owner:
			continue
		if province.town_level() >= CivilianWorkPlan.MAX_TOWN:
			continue
		var town: Vector2i = ImprovementSystem.town_tile(
			model, works, province.id, province.capital_tile
		)
		if town.x < 0 or reserved.has(town):
			continue
		var raw: Dictionary = raw_by_province.get(province.id, {}) as Dictionary
		var gain: int = TownIndustry.marginal_gain(
			raw, province.town_development, tech_unlocked
		)
		if gain <= 0:
			continue
		var candidate: Dictionary = AiCivilianCandidate.make(
			model, unit, "upgrade_town", town, works, units, stockpile, tech_caps,
			tech_unlocked, context, weight + int(gain / VALUE_DIVISOR)
		)
		best = _better(best, candidate)
	return best


## Higher score wins; a tie goes to the earlier tile on the map, so the same save
## makes the same order.
static func _better(best: Dictionary, candidate: Dictionary) -> Dictionary:
	if candidate.is_empty():
		return best
	if best.is_empty():
		return candidate
	if int(candidate["score"]) != int(best["score"]):
		return candidate if int(candidate["score"]) > int(best["score"]) else best
	var first: Vector2i = candidate["tile"]
	var held: Vector2i = best["tile"]
	if first.y != held.y:
		return candidate if first.y < held.y else best
	if first.x != held.x:
		return candidate if first.x < held.x else best
	return candidate if String(candidate["action"]) < String(best["action"]) else best
