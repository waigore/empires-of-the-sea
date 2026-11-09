class_name CivilianCatalog
extends RefCounted
## Canonical civilian unit roster and training costs (wiki: civilian-units
## § Civilian Types and Roles). Pure catalog: training validation, the civilian
## panel and tests read this one table (REQ-P3-03).
##
## All six wiki types are listed so the roster stays faithful; the starting three,
## the tech-gated Merchant and the Rail Builder are playable. Spy carries a
## `deferred` reason instead of silently pretending to work (REQ-P2-02).

const ORDER: Array[String] = [
	"explorer",
	"engineer",
	"builder",
	"spy",
	"merchant",
	"rail_builder",
]

const TYPES: Dictionary = {
	"explorer":
	{
		"role": "Explorer",
		"treasury": 1000,
		"paper": 2,
		"unlock": "starting",
		"works": ["explore", "prospect"],
		"implemented": true,
		"deferred": "",
	},
	"engineer":
	{
		"role": "Engineer",
		"treasury": 1000,
		"paper": 2,
		"unlock": "starting",
		"works": ["build_road", "build_port", "build_fort"],
		"implemented": true,
		"deferred": "",
	},
	"builder":
	{
		"role": "Builder",
		"treasury": 1000,
		"paper": 2,
		"unlock": "starting",
		"works": ["build_improvement"],
		"implemented": true,
		"deferred": "",
	},
	"spy":
	{
		"role": "Spy",
		"treasury": 2000,
		"paper": 4,
		"unlock": "starting",
		"works": ["counter_spy"],
		"implemented": false,
		"deferred": "Counter-spy and court reports need rival spies, rival research and AI activity to observe.",
	},
	"merchant":
	{
		"role": "Merchant",
		"treasury": 2000,
		"paper": 4,
		"unlock": "tech:merchant_companies",
		"works": ["purchase_land"],
		"implemented": true,
		"deferred": "",
	},
	"rail_builder":
	{
		"role": "Rail Builder",
		"treasury": 2000,
		"paper": 4,
		"unlock": "tech:early_steam_engine",
		"works": ["build_rail"],
		"implemented": true,
		"deferred": "",
	},
}

const DEFAULT_TYPE: String = "builder"


static func known(type_id: String) -> bool:
	return TYPES.has(type_id)


static func entry(type_id: String) -> Dictionary:
	return TYPES.get(type_id, TYPES[DEFAULT_TYPE])


static func normalize(type_id: String) -> String:
	if TYPES.has(type_id):
		return type_id
	return DEFAULT_TYPE


static func display_name(type_id: String) -> String:
	return String(entry(type_id)["role"])


static func treasury_cost(type_id: String) -> int:
	return int(entry(type_id).get("treasury", 0))


static func paper_cost(type_id: String) -> int:
	return int(entry(type_id).get("paper", 0))


static func is_starting(type_id: String) -> bool:
	return String(entry(type_id).get("unlock", "")) == "starting"


## Tech a type requires, or "" for the starting roster (wiki: civilian-units
## § Civilian Types and Roles).
static func unlock_tech(type_id: String) -> String:
	var unlock: String = String(entry(type_id).get("unlock", ""))
	if not unlock.begins_with("tech:"):
		return ""
	return unlock.trim_prefix("tech:")


static func is_unlocked(type_id: String, tech_unlocked: Dictionary = {}) -> bool:
	var tech: String = unlock_tech(type_id)
	return tech.is_empty() or bool(tech_unlocked.get(tech, false))


static func is_implemented(type_id: String) -> bool:
	return bool(entry(type_id).get("implemented", false))


static func deferred_reason(type_id: String) -> String:
	return String(entry(type_id).get("deferred", ""))


## Every type whose work orders ship, in roster order. Tech-gated types stay
## listed so the training panel can explain the gate; training re-checks it.
static func playable_types() -> Array[String]:
	var result: Array[String] = []
	for type_id: String in ORDER:
		if is_implemented(type_id):
			result.append(type_id)
	return result


static func works(type_id: String) -> Array[String]:
	var result: Array[String] = []
	for raw: Variant in entry(type_id).get("works", []):
		result.append(String(raw))
	return result


static func can_afford(type_id: String, treasury: int, paper: int) -> bool:
	return treasury >= treasury_cost(type_id) and paper >= paper_cost(type_id)


## "1,000 cash + 2 paper" for the training buttons and dossiers.
static func training_cost_text(type_id: String) -> String:
	return "%s cash + %d paper" % [
		thousands(treasury_cost(type_id)),
		paper_cost(type_id),
	]


static func thousands(value: int) -> String:
	var text: String = str(absi(value))
	var out: String = ""
	var count: int = 0
	for i in range(text.length() - 1, -1, -1):
		out = text[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out
