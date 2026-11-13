class_name CivilianWorkPlan
extends RefCounted
## Cost, duration and target-level maths for civilian work orders (wiki:
## civilian-units § Work Order Summary, extraction-and-improvements § Improvement
## build costs and town development). Pure data/maths; CivilianWork validates
## and applies orders, so the arithmetic has one home.

const IMPROVEMENT_COSTS: Array[Dictionary] = [
	{},
	{"lumber": 1, "castIron": 1},
	{"lumber": 4, "castIron": 4},
	{"lumber": 8, "castIron": 8},
	{"lumber": 16, "castIron": 16},
]
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


## Why this crown cannot raise the province's town now, or "" when the order is
## open. Ownership and the Builder are the work order's own business; this
## answers the two gates the province dossier also has to show (wiki:
## civilian-units § Builder; tech-tree-diplomacy-civilian).
static func town_upgrade_refusal(
	province: ProvinceState, tech_unlocked: Dictionary = {}
) -> String:
	if province == null or not province.has_town():
		return "This province has no town to upgrade."
	if province.town_level() >= MAX_TOWN:
		return "This town is already fully developed."
	if not bool(tech_unlocked.get(TOWN_TECH, false)):
		return "Requires %s to upgrade a town." % TechCatalog.display_name(TOWN_TECH)
	return ""


## The order as the court reads it. A fort is the one order that lands at one of
## three levels, each with its own price, wait and tech gate, so the order names
## the level it would raise — "Build fort" alone cannot be told from "Build
## fort" for a higher wall (wiki: siege-mechanics § Fort Levels).
static func order_label(
	action: String, model: MapModel, tile: Vector2i, plain: String
) -> String:
	if action != "build_fort":
		return plain
	return "Build %s fort" % FortRules.level_name(fort_target(model, tile)).to_lower()


## One row of the work-order list: the label the court reads, the price beside
## it and the materials the rules charge. A fort's price also names the turns it
## takes, because its wall is the one order that arrives over several of them.
static func option_row(
	action: String, model: MapModel, tile: Vector2i, works: LandWorks,
	check: Dictionary, plain: String
) -> Dictionary:
	var cost: Dictionary = cost_for(action, cost_level(action, model, tile, works))
	var price: String = cost_text(cost)
	if action == LandPurchase.ACTION:
		price = String(check.get("cost_text", LandPurchase.cost_text(model, tile)))
	var row: Dictionary = {
		"label": order_label(action, model, tile, plain),
		"cost": cost,
		"cost_text": price,
	}
	if action != "build_fort":
		return row
	var turns: int = duration_for(model, action, tile, works)
	row["cost_text"] = "%s · %d turn%s" % [price, turns, "" if turns == 1 else "s"]
	return row


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
