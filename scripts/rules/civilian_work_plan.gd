class_name CivilianWorkPlan
extends RefCounted
## Cost, duration and target-level maths for civilian work orders (wiki:
## civilian-units § Work Order Summary, extraction-and-improvements § Improvement
## build costs and town development). Pure data/maths; CivilianWork validates
## and applies orders, so the arithmetic has one home.
##
## Order-row copy and transport preview live in [CivilianWorkRows]; refusal
## wording lives in [CivilianWorkRefusals] — each owns one seam so this plan
## stays under the soft size bar (REQ-P3-01).

const IMPROVEMENT_COSTS: Array[Dictionary] = [
	{},
	{"lumber": 1, "castIron": 1},
	{"lumber": 4, "castIron": 4},
	{"lumber": 8, "castIron": 8},
	{"lumber": 16, "castIron": 16},
]
## The improvement-input feedstock the H8 bootstrap covers: the raw whose
## extraction supplies the manufactures every raise spends (wool and cotton
## weave the muster's fabric and are not part of the gate — wiki:
## extraction-and-improvements § H8 feedstock bootstrap).
const FEEDSTOCK_RESOURCES: Array[String] = ["timber", "iron"]
const PROSPECT_TURNS: int = 1
const EXPLORE_MAX_TURNS: int = 3
## Town development tops out at 4; upgrade rows reuse the improvement table as
## the interim ruleset cost (wiki leaves it "per ruleset").
const MAX_TOWN: int = 4
## The Builder's town order needs National Bureaucracy (wiki:
## tech-tree-diplomacy-civilian). The province dossier's button and the work
## order's gate read this one id, so the button can never offer an order the
## rules refuse.
const TOWN_TECH: String = "national_bureaucracy"
const COMMODITY_NAMES: Dictionary = {
	"lumber": "lumber",
	"castIron": "cast iron",
	"steel": "steel",
	"bronze": "bronze",
	"paper": "paper",
}


static func cost_for(action: String, level: int = 1) -> Dictionary:
	if CivilianTransport.knows(action):
		return CivilianTransport.cost(action)
	if action == "build_fort":
		return FortRules.cost(clampi(level, 1, FortRules.MAX_LEVEL))
	if action == "build_hospital":
		return HospitalRules.cost(clampi(level, 1, HospitalRules.MAX_LEVEL))
	if action == "build_improvement" or action == "upgrade_town":
		return (
			IMPROVEMENT_COSTS[clampi(level, 1, LandWorks.MAX_IMPROVEMENT)] as Dictionary
		).duplicate()
	return {}


## The H8 feedstock bootstrap, level 1 only (wiki: extraction-and-improvements
## § H8 feedstock bootstrap): a level-0 raise on an unimproved timber or iron
## estate omits the manufacture inputs the court holds none of, breaking the
## circular dependency where sourcing lumber or cast iron itself requires the
## other. The `castIron` waiver runs while the stockpile holds at least one
## lumber but no cast iron; the `lumber` waiver adds the lumber when the
## stockpile holds neither, so the first feedstock estate is free. Once the
## court holds both inputs the full cost applies (issue #878).
static func bootstrap_cost(
	model: MapModel, tile: Vector2i, stockpile: Dictionary, level: int
) -> Dictionary:
	var cost: Dictionary = cost_for("build_improvement", level)
	if level != 1 or model == null or tile.x < 0:
		return cost
	var info: Dictionary = MapGenerator.resource_info(model.resource_at(tile.x, tile.y))
	if not FEEDSTOCK_RESOURCES.has(String(info.get("commodity", ""))):
		return cost
	if int(stockpile.get("castIron", 0)) >= 1:
		return cost
	# The castIron waiver: the raise pays no cast iron it does not hold.
	cost.erase("castIron")
	if int(stockpile.get("lumber", 0)) < 1:
		# The lumber waiver: the first feedstock estate is free.
		cost.erase("lumber")
	return cost


static func cost_text(cost: Dictionary) -> String:
	if cost.is_empty():
		return "Free"
	var parts: PackedStringArray = PackedStringArray()
	for commodity: Variant in cost.keys():
		var id: String = String(commodity)
		parts.append("%d %s" % [int(cost[commodity]), String(COMMODITY_NAMES.get(id, id))])
	return " + ".join(parts)


## Wiki exploration time: ceil(3 × tiles / largest province), capped at 3.
static func explore_turns(model: MapModel, province_id: int) -> int:
	var tiles: int = model.province_tiles(province_id).size()
	if tiles <= 0:
		return 1
	var largest: int = 1
	for province: ProvinceState in model.provinces:
		largest = maxi(largest, int((province.tiles as Array).size()))
	var turns: int = int(ceil(3.0 * float(tiles) / float(largest)))
	return clampi(turns, 1, EXPLORE_MAX_TURNS)


## Fort the engineer would raise in this province next: level + 1, capped.
static func fort_target(model: MapModel, tile: Vector2i) -> int:
	if model == null:
		return FortRules.next_level(0)
	return FortRules.next_level(
		FortRules.level_at(model, model.province_at(tile.x, tile.y))
	)


## Hospital the engineer would raise in this province next: level + 1, capped.
static func hospital_target(model: MapModel, tile: Vector2i) -> int:
	if model == null:
		return HospitalRules.next_level(0)
	return HospitalRules.next_level(
		HospitalRules.level_at(model, model.province_at(tile.x, tile.y))
	)


## Town the Builder would raise next: current level + 1, capped at 4.
static func town_upgrade_level(model: MapModel, tile: Vector2i) -> int:
	if model == null:
		return 2
	var province: ProvinceState = model.province_data(model.province_at(tile.x, tile.y))
	if province == null:
		return 2
	return clampi(province.town_level() + 1, 2, MAX_TOWN)


## Town level a finished upgrade lands. The order is priced and gated for the
## level the town held when it was assigned, but the town can rise while the
## crew works — a Great Power seat moved to this province is set to 4 — so the
## finish lands the higher of the two and never lowers a town it finds raised.
static func town_after_upgrade(current: int, priced: int) -> int:
	return maxi(current, clampi(priced, 1, MAX_TOWN))


static func cost_level(
	action: String, model: MapModel, tile: Vector2i, works: LandWorks
) -> int:
	if action == "upgrade_town":
		return town_upgrade_level(model, tile)
	if action == "build_fort":
		return fort_target(model, tile)
	if action == "build_hospital":
		return hospital_target(model, tile)
	return works.improvement_at(model, tile) + 1


static func duration_for(
	model: MapModel, action: String, tile: Vector2i, works: LandWorks
) -> int:
	match action:
		"explore":
			return explore_turns(model, model.province_at(tile.x, tile.y))
		"prospect":
			return PROSPECT_TURNS
		"build_improvement":
			return clampi(
				works.improvement_at(model, tile) + 1, 1, LandWorks.MAX_IMPROVEMENT
			)
		"upgrade_town":
			return town_upgrade_level(model, tile)
		"build_fort":
			return FortRules.turns(fort_target(model, tile))
		"build_hospital":
			return HospitalRules.turns(hospital_target(model, tile))
	if CivilianTransport.knows(action):
		return CivilianTransport.turns(action)
	return 1
