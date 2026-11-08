class_name RegimentEconomy
extends RefCounted
## Land regiment training economy (wiki: military-units § Training Costs,
## military-generals § Regiment Economy, tech-tree-military § Unlocks).
## Pure catalog and validation: treasury + material inputs + one worker per
## regiment, and the unlocking tech that gates each type. No nodes (REQ-P3-03).
##
## The wiki fixes the cavalry input table and the treasury scale; it leaves the
## non-cavalry material rows to program config, so those are interim constants
## here (one row per category) and documented in docs/armies.md.

## type -> unlocking tech id; empty means buildable from game start.
const TECH: Dictionary = {
	"peasant_levies": "",
	"pikemen": "",
	"arquebusiers": "",
	"bowmen": "",
	"squires": "",
	"knights": "",
	"culverin": "",
	"calivermen": "improved_infantry_tactics",
	"halberdiers": "improved_iron_weapons",
	"musketeers": "weapon_craftsmanship",
	"cossacks": "recruit_steppe_horsemen",
	"lancers": "organised_regiments",
	"harquebusiers": "improved_cavalry_tactics",
	"horse_artillery": "horse_artillery",
	"royal_artillery": "siege_engineering",
	"skirmishers": "early_rifles",
	"regulars": "bayonet",
	"grenadiers": "explosives",
	"hussars": "hussars",
	"cuirassiers": "improved_cavalry_weapons",
	"light_artillery": "light_artillery_tactics",
	"heavy_artillery": "heavy_artillery",
	"sharpshooters": "long_range_rifles",
	"rifle_infantry": "needle_guns",
	"guards": "elite_military_training",
	"scouts": "scouting",
	"carbine_cavalry": "repeating_cavalry_carbine",
	"field_artillery": "field_artillery_tactics",
	"siege_guns": "high_grade_steel",
}

## Cavalry rows exactly as published (wiki: military-units § Cavalry Input
## Requirements); horses are only required where the table names them.
const CAVALRY_INPUTS: Dictionary = {
	"squires": {"fabric": 1, "castIron": 1, "horses": 2},
	"knights": {"fabric": 1, "castIron": 2, "horses": 2},
	"cossacks": {"fabric": 1, "castIron": 2, "horses": 2},
	"lancers": {"fabric": 1, "castIron": 2},
	"harquebusiers": {"fabric": 1, "castIron": 2},
	"hussars": {"fabric": 1, "castIron": 2},
	"cuirassiers": {"fabric": 1, "castIron": 2},
	"scouts": {"fabric": 1, "castIron": 2},
	"carbine_cavalry": {"fabric": 1, "castIron": 2},
}

## Interim non-cavalry rows by category: the wiki names the commodities but
## publishes no per-regiment quantities, so these are the code-side config
## until a ruleset loader exists.
const CATEGORY_INPUTS: Dictionary = {
	RegimentCatalog.Category.LIGHT_INFANTRY: {"fabric": 1},
	RegimentCatalog.Category.REGULAR_INFANTRY: {"fabric": 1, "castIron": 1},
	RegimentCatalog.Category.HEAVY_INFANTRY: {"fabric": 1, "castIron": 2},
	RegimentCatalog.Category.BOWMEN: {"fabric": 1, "lumber": 1},
	RegimentCatalog.Category.LIGHT_ARTILLERY: {"castIron": 2, "bronze": 1},
	RegimentCatalog.Category.HEAVY_ARTILLERY: {"castIron": 2, "bronze": 2},
}

## Every land regiment consumes one worker from the pool at construction.
const WORKER_COST: int = 1


static func tech_for(type_id: String) -> String:
	return String(TECH.get(type_id, ""))


static func buildable(type_id: String, tech_unlocked: Dictionary) -> bool:
	if not RegimentCatalog.has_type(type_id):
		return false
	var tech: String = tech_for(type_id)
	return tech.is_empty() or bool(tech_unlocked.get(tech, false))


## Commodity inputs for one regiment; cavalry overrides the category row.
static func training_inputs(type_id: String) -> Dictionary:
	if CAVALRY_INPUTS.has(type_id):
		return (CAVALRY_INPUTS[type_id] as Dictionary).duplicate()
	var row: Dictionary = CATEGORY_INPUTS.get(RegimentCatalog.category(type_id), {})
	return row.duplicate()


static func missing_inputs(type_id: String, stockpile: Dictionary) -> Dictionary:
	var short: Dictionary = {}
	var inputs: Dictionary = training_inputs(type_id)
	for commodity: Variant in inputs.keys():
		var id: String = String(commodity)
		var have: int = int(stockpile.get(id, 0))
		if have < int(inputs[commodity]):
			short[id] = int(inputs[commodity]) - have
	return short


## Empty string when the row is payable; otherwise the first blocking reason.
static func blocked_reason(
	type_id: String,
	treasury: int,
	stockpile: Dictionary,
	peasants: int,
	tech_unlocked: Dictionary
) -> String:
	if not RegimentCatalog.has_type(type_id):
		return "Unknown regiment"
	if not buildable(type_id, tech_unlocked):
		return "Requires %s" % TechCatalog.display_name(tech_for(type_id))
	if treasury < RegimentCatalog.treasury_cost(type_id):
		return "Insufficient treasury"
	if not missing_inputs(type_id, stockpile).is_empty():
		return "Insufficient materials"
	if peasants < WORKER_COST:
		return "Insufficient workers"
	return ""


## "2,000 ducats · 1 Fabric · 1 Cast Iron · 1 worker" for the muster ledger.
static func cost_text(type_id: String) -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append("%s ducats" % _thousands(RegimentCatalog.treasury_cost(type_id)))
	var inputs: Dictionary = training_inputs(type_id)
	for commodity: Variant in inputs.keys():
		parts.append("%d %s" % [int(inputs[commodity]), CommodityCatalog.label(String(commodity))])
	parts.append("%d worker" % WORKER_COST)
	return " · ".join(parts)


static func _thousands(value: int) -> String:
	var text: String = str(value)
	var out: String = ""
	while text.length() > 3:
		out = "," + text.substr(text.length() - 3) + out
		text = text.substr(0, text.length() - 3)
	return text + out
