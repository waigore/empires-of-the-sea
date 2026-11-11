class_name AiArmyReinforce
extends RefCounted
## Full-AI land reinforcement (wiki: ai-architecture § Land reinforcement,
## growth-stage-planner § Recruitment modulation; DR-20261111-04).
##
## A rival court raises new land regiments from its **own** ledger, under the
## same muster the human drill yard uses, but only once its economy can carry
## them — the growth-stage throttle. One line regiment a turn, the strongest
## legal cram it can pay for, while it stays under its target strength; a court
## at war arms up to a higher target.
##
## Pure rules: config, ledger and counts in, a type id out (REQ-P2-03,
## REQ-P3-03). The map adapter spends through ArmyTraining, so the AI can never
## buy a regiment the human rules would refuse.

## Categories that field a line: a mustered regiment is infantry, never the
## army's whole battery or horse (the opening roster keeps its own mix).
const LINE_CATEGORIES: Array[int] = [
	RegimentCatalog.Category.LIGHT_INFANTRY,
	RegimentCatalog.Category.REGULAR_INFANTRY,
	RegimentCatalog.Category.HEAVY_INFANTRY,
]


## One turn's muster decision.
## Returns {muster: type id or "", target, reasons: [], candidates: []}.
## `candidates` lists every legal line type with its score, so a turn trace can
## explain the pick (wiki: turn-trace-interpretation).
static func plan(
	config: AiConfig,
	economy: PlayerEconomy,
	own_regiments: int,
	at_war: bool
) -> Dictionary:
	var result: Dictionary = {
		"muster": "", "target": 0, "reasons": [], "candidates": [],
	}
	if config == null or economy == null:
		return result
	var target: int = config.parameter("army.regiment_target")
	if at_war:
		target += config.parameter("army.war_extra")
	result["target"] = target
	if own_regiments >= target:
		result["reasons"].append("at target strength")
		return result
	var peasants: int = economy.available_peasants()
	var floor_treasury: int = config.parameter("army.min_treasury")
	var floor_peasants: int = config.parameter("army.min_peasants")
	if peasants - RegimentEconomy.WORKER_COST < floor_peasants:
		result["reasons"].append("labour floor")
		return result
	var candidates: Array[Dictionary] = []
	for type_id: String in RegimentCatalog.ids():
		if not LINE_CATEGORIES.has(RegimentCatalog.category(type_id)):
			continue
		var reason: String = RegimentEconomy.blocked_reason(
			type_id,
			economy.treasury,
			economy.stockpile,
			peasants,
			economy.tech_unlocked
		)
		if reason.is_empty() and economy.treasury - RegimentCatalog.treasury_cost(
			type_id
		) < floor_treasury:
			reason = "would break the war chest"
		if not reason.is_empty():
			continue
		candidates.append({
			"type_id": type_id,
			"strength": RegimentCatalog.strength(type_id),
			"era": RegimentCatalog.era(type_id),
		})
	candidates.sort_custom(_better)
	result["candidates"] = candidates
	if candidates.is_empty():
		result["reasons"].append("nothing payable")
		return result
	result["muster"] = String(candidates[0]["type_id"])
	return result


## Strongest first, then the newer pattern, then the lowest id — one stable
## answer for a given ledger and tech set.
static func _better(a: Dictionary, b: Dictionary) -> bool:
	if int(a["strength"]) != int(b["strength"]):
		return int(a["strength"]) > int(b["strength"])
	if int(a["era"]) != int(b["era"]):
		return int(a["era"]) > int(b["era"])
	return String(a["type_id"]) < String(b["type_id"])
