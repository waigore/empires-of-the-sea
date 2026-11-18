class_name ImprovementCatalog
extends RefCounted
## Named terrain improvements and their output (wiki:
## extraction-and-improvements § Improvement Naming, § Improvement Build Costs).
## Pure catalog: rules, the estates ledger and tests share this one table
## (REQ-P3-03). Names derive from the tile resource, never from the level.

const MAX_LEVEL: int = LandWorks.MAX_IMPROVEMENT
## Cap until a researched tech lifts it (wiki: tech-and-extraction-cap);
## callers pass TechCatalog.extraction_caps(tech_unlocked).
const DEFAULT_TECH_CAP: int = 1

## Resource ids mirror MapGenerator.resource_table(). Every index the table
## carries has a published base name, so a copper, silver, gem or diamond estate
## reads `Mine` and a crop reads its own work (wiki: extraction-and-improvements
## § Improvement Naming).
##
## `icon` is the survey lens's own column key and stays the four published
## kinds (timber, ore, riches, farm: `ResourceTypes.ORDER`). `pictogram` is the
## estate's own pictogram — the thing the works is, not the group it belongs to
## — so a Farm, a Pasture, a Ranch, a Plantation and a Fur post never read as
## one sheaf (REQ-P1-08; DR-20261119-06).
const RESOURCES: Dictionary = {
	0: {"name": "Lumber camp", "category": "wood", "icon": "tree", "pictogram": "log"},
	1: {"name": "Mine", "category": "mine", "icon": "ore", "pictogram": "pick"},
	2: {"name": "Mine", "category": "mine", "icon": "ore", "pictogram": "pick"},
	3: {"name": "Mine", "category": "riches", "icon": "coin", "pictogram": "coin"},
	4: {"name": "Farm", "category": "farm", "icon": "wheat", "pictogram": "wheat"},
	5: {"name": "Pasture", "category": "farm", "icon": "wheat", "pictogram": "sheep"},
	6: {"name": "Ranch", "category": "farm", "icon": "wheat", "pictogram": "horse"},
	7: {"name": "Ranch", "category": "farm", "icon": "wheat", "pictogram": "cattle"},
	8: {"name": "Mine", "category": "mine", "icon": "ore", "pictogram": "pick"},
	9: {"name": "Mine", "category": "mine", "icon": "ore", "pictogram": "pick"},
	10: {"name": "Mine", "category": "riches", "icon": "coin", "pictogram": "coin"},
	11: {"name": "Mine", "category": "riches", "icon": "coin", "pictogram": "coin"},
	12: {"name": "Mine", "category": "riches", "icon": "coin", "pictogram": "coin"},
	13: {"name": "Plantation", "category": "farm", "icon": "wheat", "pictogram": "leaf"},
	14: {"name": "Plantation", "category": "farm", "icon": "wheat", "pictogram": "leaf"},
	15: {"name": "Plantation", "category": "farm", "icon": "wheat", "pictogram": "leaf"},
	16: {"name": "Fur post", "category": "farm", "icon": "wheat", "pictogram": "pelt"},
	17: {"name": "Plantation", "category": "farm", "icon": "wheat", "pictogram": "leaf"},
}

const DEFAULT_ENTRY: Dictionary = {
	"name": "Improvement",
	"category": "works",
	"icon": "ore",
	"pictogram": "pick",
}

const COMMODITY_LABELS: Dictionary = {
	"timber": "timber",
	"iron": "iron",
	"coal": "coal",
	"gold": "gold",
	"grain": "grain",
	"wool": "wool",
	"horses": "horses",
	"meat": "meat",
	"tin": "tin",
	"lumber": "lumber",
	"castIron": "cast iron",
	"steel": "steel",
	"bronze": "bronze",
	"paper": "paper",
}

## Prospect-required minerals (wiki: fog-and-exploration § Prospect-Required
## Resources): iron, copper, tin, coal, silver, gold, gems, diamonds. The map's
## own ids are listed; the commodity check keeps a chart that carries copper,
## silver, gems or diamonds on the same rule (DR-20261111-26).
const MINERAL_RESOURCES: Array[int] = [1, 2, 3, 8]
const MINERAL_COMMODITIES: Array[String] = [
	"iron", "copper", "tin", "coal", "silver", "gold", "gems", "diamonds",
]
static var _mineral_by_id: Dictionary = {}


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


## The raw commodity on the tile (wiki: commodity-catalog). The production
## phase refines it into lumber/cast iron/fabric/etc.
static func commodity(resource: int) -> String:
	return String(MapGenerator.resource_info(resource).get("commodity", ""))


static func commodity_label(commodity_id: String) -> String:
	return String(COMMODITY_LABELS.get(commodity_id, commodity_id))


static func category(resource: int) -> String:
	return String(entry(resource).get("category", "works"))


static func icon_kind(resource: int) -> String:
	return String(entry(resource).get("icon", "ore"))


## The estate's own pictogram: what the works is (a sheaf, a shepherd's sheep, a
## horse, a leaf, a pelt, a felled log, a pick) rather than the four survey
## groups the lens counts in. A resource the table has not published keeps the
## survey kind, so a row always draws something (REQ-P1-08; DR-20261119-06).
static func pictogram_kind(resource: int) -> String:
	var row: Dictionary = entry(resource)
	return String(row.get("pictogram", row.get("icon", "ore")))


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
	if resource < 0:
		return false
	if not _mineral_by_id.has(resource):
		_mineral_by_id[resource] = (
			MINERAL_RESOURCES.has(resource)
			or MINERAL_COMMODITIES.has(commodity(resource))
		)
	return bool(_mineral_by_id[resource])


static func tech_cap_for(commodity_id: String, tech_caps: Dictionary = {}) -> int:
	return maxi(int(tech_caps.get(commodity_id, DEFAULT_TECH_CAP)), 0)


## Wiki extraction formula: min(improvement, tech cap, transport, town cap).
static func effective_yield(
	resource: int,
	level: int,
	tech_caps: Dictionary = {},
	transport: int = 1,
	town_cap: int = MAX_LEVEL
) -> int:
	var commodity_id: String = commodity(resource)
	var cap: int = tech_cap_for(commodity_id, tech_caps)
	return clampi(mini(mini(level, cap), mini(transport, town_cap)), 0, MAX_LEVEL)


static func output_text(resource: int, amount: int) -> String:
	if amount <= 0:
		return "No yield"
	return "%d %s / turn" % [amount, commodity_label(commodity(resource))]


static func cost_text(level: int) -> String:
	return CivilianWork.cost_text(CivilianWork.cost_for("build_improvement", level))
