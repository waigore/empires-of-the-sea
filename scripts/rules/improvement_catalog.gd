class_name ImprovementCatalog
extends RefCounted
## Named terrain improvements and their output (wiki:
## extraction-and-improvements § Improvement Naming, § Improvement Build Costs).
## Pure catalog: rules, the estates ledger and tests share this one table
## (REQ-P3-03). Names derive from the tile resource, never from the level.
##
## Milestone bridge: until the Production phase and raw-stock pipeline land,
## a lumber camp credits lumber and a mine credits cast iron directly. The
## raw -> manufactured recipe pass is a release-blocking follow-up.

const MAX_LEVEL: int = LandWorks.MAX_IMPROVEMENT

## Resource ids mirror MapGenerator.resource_table().
const RESOURCES: Dictionary = {
	0: {"name": "Lumber camp", "commodity": "lumber", "category": "wood", "icon": "tree"},
	1: {"name": "Mine", "commodity": "castIron", "category": "mine", "icon": "ore"},
	2: {"name": "Mine", "commodity": "coal", "category": "mine", "icon": "ore"},
	3: {"name": "Mine", "commodity": "gold", "category": "riches", "icon": "coin"},
	4: {"name": "Farm", "commodity": "grain", "category": "farm", "icon": "wheat"},
	5: {"name": "Pasture", "commodity": "wool", "category": "farm", "icon": "wheat"},
	6: {"name": "Ranch", "commodity": "horses", "category": "farm", "icon": "wheat"},
	7: {"name": "Salt works", "commodity": "salt", "category": "mine", "icon": "ore"},
	8: {"name": "Fishery", "commodity": "fish", "category": "farm", "icon": "fish"},
}

const DEFAULT_ENTRY: Dictionary = {
	"name": "Improvement",
	"commodity": "",
	"category": "works",
	"icon": "ore",
}

const COMMODITY_LABELS: Dictionary = {
	"lumber": "lumber",
	"castIron": "cast iron",
	"coal": "coal",
	"gold": "gold",
	"grain": "grain",
	"wool": "wool",
	"horses": "horses",
	"salt": "salt",
	"fish": "fish",
}

## Iron, coal and gold are the map's prospect-required minerals
## (wiki: fog-and-exploration § Prospect-Required Resources).
const MINERAL_RESOURCES: Array[int] = [1, 2, 3]


static func known(resource: int) -> bool:
	return RESOURCES.has(resource)


static func entry(resource: int) -> Dictionary:
	return RESOURCES.get(resource, DEFAULT_ENTRY)


static func base_name(resource: int) -> String:
	return String(entry(resource).get("name", "Improvement"))


## "Farm" at level 0, "Farm (L2)" once improved. Levels never rename the work.
static func display_name(resource: int, level: int = 0) -> String:
	var name: String = base_name(resource)
	if level <= 0:
		return name
	return "%s (L%d)" % [name, clampi(level, 1, MAX_LEVEL)]


static func commodity(resource: int) -> String:
	return String(entry(resource).get("commodity", ""))


static func commodity_label(commodity_id: String) -> String:
	return String(COMMODITY_LABELS.get(commodity_id, commodity_id))


static func category(resource: int) -> String:
	return String(entry(resource).get("category", "works"))


static func icon_kind(resource: int) -> String:
	return String(entry(resource).get("icon", "ore"))


static func production(level: int) -> int:
	return clampi(level, 0, MAX_LEVEL)


## Resource yield at a level: one unit of the tile commodity per level.
static func yield_for(resource: int, level: int) -> Dictionary:
	var amount: int = production(level)
	var commodity_id: String = commodity(resource)
	if amount <= 0 or commodity_id.is_empty():
		return {}
	return {commodity_id: amount}


static func needs_prospecting(resource: int) -> bool:
	return MINERAL_RESOURCES.has(resource)


static func output_text(resource: int, level: int) -> String:
	var amount: int = production(level)
	if amount <= 0:
		return "No yield"
	return "%d %s / turn" % [amount, commodity_label(commodity(resource))]


static func cost_text(level: int) -> String:
	return CivilianWork.cost_text(CivilianWork.cost_for("build_improvement", level))
