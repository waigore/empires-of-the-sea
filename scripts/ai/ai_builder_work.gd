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
##
## The estate side reads the same [ImprovementLedger] rows the player's ESTATES
## ledger renders, so a rival prices a tile by the yield its own crown can gather
## rather than by the tile alone: a level the town, road or technology cap will
## not pay earns no premium, and a town that is capping its estates is worth the
## estate levels it unlocks. A court therefore raises the town before pouring
## lumber and cast iron into estates it cannot gather.

## Base-price units per point of score, so a rich town outranks an estate without
## drowning every other order on the court's board.
const VALUE_DIVISOR: int = 8
## Score per unit of yield the next level would actually pay each turn.
const GAIN_WEIGHT: int = 10
## Score per estate level a town upgrade would let its province gather.
const UNLOCK_VALUE: int = 20


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
	town_raw: Dictionary,
	estates: Array = []
) -> Dictionary:
	var rows: Array[Dictionary] = _rows(estates)
	if rows.is_empty():
		rows = estate_rows(
			model, works, units, stockpile, unit.owner, tech_caps, context
		)
	var best: Dictionary = _best_estate(
		config, model, unit, works, units, stockpile, tech_caps, tech_unlocked,
		context, reserved, rows
	)
	return _better(
		best,
		_town_candidate(
			config, model, unit, works, units, stockpile, tech_caps, tech_unlocked,
			context, reserved, town_raw, rows
		)
	)


## The estate ledger's rows for one court: the same projection the ESTATES
## ledger renders, so the planner and the player read one source (REQ-P2-03).
static func estate_rows(
	model: MapModel,
	works: LandWorks,
	units: Array,
	stockpile: Dictionary,
	owner: int,
	tech_caps: Dictionary,
	context: Dictionary
) -> Array[Dictionary]:
	if model == null or works == null or owner < 0:
		return [] as Array[Dictionary]
	var roster: Array[CivilianState] = []
	roster.assign(units)
	var snapshot: Dictionary = ImprovementLedger.snapshot(
		model, works, roster, stockpile, owner,
		context.get("capital_tile", CivilianState.NO_TILE), tech_caps
	)
	return _rows(snapshot.get("estates", []))


## Yield the next improvement level would actually add each turn: the current
## output minus what the town, road and technology caps already allow. Zero when
## the crown cannot gather another unit from this tile yet.
static func paid_gain(row: Dictionary) -> int:
	var level: int = int(row.get("level", 0))
	if level >= LandWorks.MAX_IMPROVEMENT:
		return 0
	var cap: int = mini(int(row.get("tech_cap", 0)), int(row.get("terrain_cap", 0)))
	var now: int = int(row.get("output", 0))
	var raised: int = Extraction.effective_yield(
		level + 1, cap, int(row.get("transport", 0)), int(row.get("town_cap", 0))
	)
	return maxi(raised - now, 0)


## Estate levels this province's town is holding back: the yield the estates
## would gather one level further on with the town fully developed, less what
## that same level gathers under today's town cap. Town development caps a
## capital province's estates, so this is the yield the Builder buys by raising
## the town first (wiki: capital-and-connectivity § Town rule). Zero for an
## estate the road or technology already caps.
static func town_unlocks(estates: Array, province_id: int) -> int:
	var total: int = 0
	for row: Dictionary in estates:
		if int(row.get("province", -1)) != province_id:
			continue
		if not bool(row.get("connected", false)):
			continue
		var level: int = mini(int(row.get("level", 0)) + 1, LandWorks.MAX_IMPROVEMENT)
		if level <= 0:
			continue
		var cap: int = mini(int(row.get("tech_cap", 0)), int(row.get("terrain_cap", 0)))
		var transport: int = int(row.get("transport", 0))
		var town_cap: int = int(row.get("town_cap", 0))
		var capped: int = Extraction.effective_yield(level, cap, transport, town_cap)
		var lifted: int = Extraction.effective_yield(
			level, cap, transport, LandWorks.MAX_IMPROVEMENT
		)
		total += maxi(lifted - capped, 0)
	return total


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
## upgrade of the same crop, and a level the crown can gather pays a premium.
static func _best_estate(
	config: AiConfig, model: MapModel, unit: CivilianState, works: LandWorks,
	units: Array, stockpile: Dictionary, tech_caps: Dictionary,
	tech_unlocked: Dictionary, context: Dictionary, reserved: Dictionary,
	estates: Array
) -> Dictionary:
	var best: Dictionary = {}
	var target: int = config.parameter("civilian.need_target")
	for row: Dictionary in estates:
		var tile: Vector2i = row.get("tile", CivilianState.NO_TILE)
		if tile.x < 0 or reserved.has(tile):
			continue
		if String(row.get("status", "")) == "maxed":
			continue
		var level: int = int(row.get("level", 0))
		var crop: String = String(row.get("commodity", ""))
		var gain: int = paid_gain(row)
		var connected: bool = bool(row.get("connected", false))
		var score: int = config.parameter("civilian.improvement_weight")
		# A shortage only pulls an order that can pay it: an estate the town or
		# transport cap holds back is an investment, not a source, and the town
		# or the engineer's road is the order that makes it pay. A tile still
		# off the crown network keeps its shortage weight, because the road that
		# links it is already the Engineer's business.
		if gain > 0 or not connected:
			score += need(crop, stockpile, target) * 10
		if level <= 0:
			score += 10
		score += gain * GAIN_WEIGHT
		var candidate: Dictionary = AiCivilianCandidate.make(
			model, unit, "build_improvement", tile, works, units, stockpile,
			tech_caps, tech_unlocked, context, score
		)
		best = _better(best, candidate)
	return best


## The town whose finished development is worth the most per turn. Levels 2 and 4
## pay a bonus and level 3 pays none, so the gain is measured at level 4 less what
## the town already pays; the Builder still walks the levels one at a time
## (wiki: extraction-and-improvements § Town manufacturing bonus). A town that is
## capping its province's estates is also worth the yield those estates would
## gather once it rises, so it is raised before estates that cannot pay.
static func _town_candidate(
	config: AiConfig, model: MapModel, unit: CivilianState, works: LandWorks,
	units: Array, stockpile: Dictionary, tech_caps: Dictionary,
	tech_unlocked: Dictionary, context: Dictionary, reserved: Dictionary,
	raw_by_province: Dictionary, estates: Array
) -> Dictionary:
	var best: Dictionary = {}
	var weight: int = config.parameter("civilian.town_upgrade_weight")
	for province: ProvinceState in model.provinces:
		if province.owner != unit.owner:
			continue
		if province.town_level() >= CivilianWorkPlan.MAX_TOWN:
			continue
		var raw: Dictionary = raw_by_province.get(province.id, {}) as Dictionary
		if raw.is_empty():
			continue
		var town: Vector2i = ImprovementSystem.town_tile(
			model, works, province.id, province.capital_tile
		)
		if town.x < 0 or reserved.has(town):
			continue
		var gain: int = TownIndustry.marginal_gain(
			raw, province.town_development, tech_unlocked
		)
		var unlocks: int = town_unlocks(estates, province.id)
		if gain <= 0 and unlocks <= 0:
			continue
		var candidate: Dictionary = AiCivilianCandidate.make(
			model, unit, "upgrade_town", town, works, units, stockpile, tech_caps,
			tech_unlocked, context,
			weight + int(gain / VALUE_DIVISOR) + unlocks * UNLOCK_VALUE
		)
		best = _better(best, candidate)
	return best


static func _rows(raw: Variant) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	rows.assign(raw)
	return rows


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
