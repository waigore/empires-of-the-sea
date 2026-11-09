class_name ShipEconomy
extends RefCounted
## Canonical ship build costs and food upkeep (wiki: ships-and-naval § Ship
## build economy, § Ship food upkeep). Pure catalog: BuildUnitOrder validation
## and consumption phases read this; no nodes (REQ-P3-03).

## Per hull, per turn (grain/meat stockpile abstraction).
const FOOD_UPKEEP_PER_SHIP: int = 2

## One peasant leaves the pool when a hull is launched (wiki: ships-and-naval
## § Ship muster; DR-20261109-01 § Paying the muster).
const WORKER_COST: int = 1

## type -> unlocking tech id (wiki: tech-tree-naval § Unlocks); empty means the
## hull is buildable from game start.
const TECH: Dictionary = {
	"carrack": "",
	"fluyte": "superior_hull_design",
	"sloop": "navigation",
	"trader": "improved_sail_design",
	"galleon": "convoying",
	"indiaman": "large_hulls",
	"frigate": "advanced_hull_design",
	"raider": "paddlewheels",
	"ship_of_the_line": "ship_of_the_line",
	"clipper": "clipper_ships",
	"merchant_steamship": "merchant_steamships",
	"ironclad": "advanced_iron_working",
}

## Unlock era 0 = always buildable (no tech). Eras 1–4 match tech-tree-naval.
const ENTRIES: Dictionary = {
	"carrack":
	{
		"role": "merchant",
		"unlock_era": 0,
		"treasury": 8000,
		"inputs": {"lumber": 2, "fabric": 1},
	},
	"fluyte":
	{
		"role": "merchant",
		"unlock_era": 1,
		"treasury": 6000,
		"inputs": {"lumber": 1, "fabric": 1},
	},
	"sloop":
	{
		"role": "warship",
		"unlock_era": 1,
		"treasury": 5500,
		"inputs": {"lumber": 1, "fabric": 1},
	},
	"trader":
	{
		"role": "merchant",
		"unlock_era": 2,
		"treasury": 7500,
		"inputs": {"lumber": 2, "fabric": 2},
	},
	"galleon":
	{
		"role": "merchant",
		"unlock_era": 2,
		"treasury": 9500,
		"inputs": {"lumber": 3, "fabric": 2},
	},
	"indiaman":
	{
		"role": "merchant",
		"unlock_era": 2,
		"treasury": 11000,
		"inputs": {"lumber": 3, "fabric": 3},
	},
	"frigate":
	{
		"role": "warship",
		"unlock_era": 3,
		"treasury": 10500,
		"inputs": {"lumber": 2, "fabric": 2},
	},
	"raider":
	{
		"role": "warship",
		"unlock_era": 3,
		"treasury": 11500,
		"inputs": {"lumber": 2, "fabric": 1, "castIron": 2},
	},
	"ship_of_the_line":
	{
		"role": "warship",
		"unlock_era": 3,
		"treasury": 16500,
		"inputs": {"lumber": 5, "fabric": 3},
	},
	"clipper":
	{
		"role": "merchant",
		"unlock_era": 4,
		"treasury": 13500,
		"inputs": {"lumber": 3, "fabric": 3},
	},
	"merchant_steamship":
	{
		"role": "merchant",
		"unlock_era": 4,
		"treasury": 15500,
		"inputs": {"lumber": 2, "fabric": 2, "coal": 3},
	},
	"ironclad":
	{
		"role": "warship",
		"unlock_era": 4,
		"treasury": 21000,
		"inputs": {"lumber": 2, "fabric": 2, "castIron": 5},
	},
}


static func known(type_id: String) -> bool:
	return ENTRIES.has(type_id)


## Economy row for a catalog type; unknown ids fall back to the always-buildable carrack.
static func entry(type_id: String) -> Dictionary:
	return ENTRIES.get(type_id, ENTRIES[ShipStats.DEFAULT_TYPE])


static func unlock_era(type_id: String) -> int:
	return int(entry(type_id).get("unlock_era", 0))


static func is_always_buildable(type_id: String) -> bool:
	return unlock_era(type_id) == 0


static func treasury_cost(type_id: String) -> int:
	return int(entry(type_id).get("treasury", 0))


static func build_inputs(type_id: String) -> Dictionary:
	return (entry(type_id).get("inputs", {}) as Dictionary).duplicate()


## Wiki freezes food upkeep at 2 for every published hull type.
static func food_upkeep_per_ship(_type_id: String = ShipStats.DEFAULT_TYPE) -> int:
	return FOOD_UPKEEP_PER_SHIP


static func food_upkeep_for_fleet(fleet: FleetState) -> int:
	if fleet == null:
		return 0
	return fleet.ship_count() * FOOD_UPKEEP_PER_SHIP


static func food_upkeep_for_owner(fleets: Array[FleetState], owner: int) -> int:
	var total: int = 0
	for fleet: FleetState in fleets:
		if fleet == null or fleet.owner != owner:
			continue
		total += food_upkeep_for_fleet(fleet)
	return total


## True when treasury and stockpile cover the published build row.
static func can_afford(type_id: String, treasury: int, stockpile: Dictionary) -> bool:
	if treasury < treasury_cost(type_id):
		return false
	var inputs: Dictionary = build_inputs(type_id)
	for commodity: Variant in inputs.keys():
		var need: int = int(inputs[commodity])
		var have: int = int(stockpile.get(String(commodity), 0))
		if have < need:
			return false
	return true


## Commodity ids still short of the build row (empty when affordable on materials).
static func missing_inputs(type_id: String, stockpile: Dictionary) -> Dictionary:
	var short: Dictionary = {}
	var inputs: Dictionary = build_inputs(type_id)
	for commodity: Variant in inputs.keys():
		var id: String = String(commodity)
		var need: int = int(inputs[commodity])
		var have: int = int(stockpile.get(id, 0))
		if have < need:
			short[id] = need - have
	return short


static func tech_for(type_id: String) -> String:
	return String(TECH.get(ShipStats.normalize(type_id), ""))


## A hull is buildable iff it has no unlocking tech or that tech is researched
## (wiki: tech-tree § Regiment and ship buildability).
static func buildable(type_id: String, tech_unlocked: Dictionary) -> bool:
	if not known(type_id):
		return false
	var tech: String = tech_for(type_id)
	return tech.is_empty() or bool(tech_unlocked.get(tech, false))


## Empty string when the build row is payable; otherwise the first blocker, so
## the yard and the order path share one gate (REQ-P2-03).
static func blocked_reason(
	type_id: String,
	treasury: int,
	stockpile: Dictionary,
	peasants: int,
	tech_unlocked: Dictionary
) -> String:
	if not known(type_id):
		return "Unknown ship"
	if not buildable(type_id, tech_unlocked):
		return "Requires %s" % TechCatalog.display_name(tech_for(type_id))
	if treasury < treasury_cost(type_id):
		return "Insufficient treasury"
	if not missing_inputs(type_id, stockpile).is_empty():
		return "Insufficient materials"
	if peasants < WORKER_COST:
		return "Insufficient workers"
	return ""


## "8,000 ducats · 2 Lumber · 1 Fabric · 1 worker" for the yard ledger.
static func cost_text(type_id: String) -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append("%s ducats" % _thousands(treasury_cost(type_id)))
	var inputs: Dictionary = build_inputs(type_id)
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
