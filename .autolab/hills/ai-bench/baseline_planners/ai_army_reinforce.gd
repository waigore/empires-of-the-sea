class_name MainlineAiArmyReinforce
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
## `candidates` lists every legal line type the court could already pay for, so a
## turn trace can explain the pick (wiki: turn-trace-interpretation).
static func plan(
	config: MainlineAiConfig,
	economy: PlayerEconomy,
	own_regiments: int,
	at_war: bool
) -> Dictionary:
	var result: Dictionary = {
		"muster": "", "target": 0, "reasons": [], "candidates": [],
	}
	if config == null or economy == null:
		return result
	var target: int = _target(config, at_war)
	result["target"] = target
	if own_regiments >= target:
		result["reasons"].append("at target strength")
		return result
	if economy.available_peasants() - RegimentEconomy.WORKER_COST < config.parameter(
		"army.min_peasants"
	):
		result["reasons"].append("labour floor")
		return result
	var candidates: Array[Dictionary] = []
	for entry: Dictionary in _legal_candidates(config, economy):
		if not RegimentEconomy.missing_inputs(
			String(entry["type_id"]), economy.stockpile
		).is_empty():
			continue
		candidates.append(entry)
	result["candidates"] = candidates
	if candidates.is_empty():
		result["reasons"].append("nothing payable")
		return result
	result["muster"] = String(candidates[0]["type_id"])
	return result


## Regiments the court aims at: the peace target, raised by `army.war_extra` at
## war (wiki: ai-architecture § Land reinforcement).
static func _target(config: MainlineAiConfig, at_war: bool) -> int:
	var target: int = config.parameter("army.regiment_target")
	if at_war:
		target += config.parameter("army.war_extra")
	return target


## The line regiment this court would raise if its stores could pay for it:
## strongest `FPN + FPM`, then the newer era, then the lowest id. Materials are
## deliberately not read — this is the pattern the court is provisioning for, and
## the muster itself checks what it can already pay (wiki: growth-stage-planner
## § Recruitment modulation).
static func next_type(config: MainlineAiConfig, economy: PlayerEconomy) -> String:
	var legal: Array[Dictionary] = _legal_candidates(config, economy)
	if legal.is_empty():
		return ""
	return String(legal[0]["type_id"])


## Commodities this court keeps back so the regiment it means to raise can be
## mustered: the whole input row of the pattern it is saving for (wiki:
## growth-stage-planner § Recruitment modulation, "military fabric reservation
## holds inputs for upcoming recruits"; economy-planner § Reservations). The row
## is held even while the purse is still short of the muster — a court that only
## provisioned once it could pay would never stock the cloth it needs, and the
## muster would starve with a full war chest (issue #474). Empty when the court
## sits at its target or its fields cannot spare a hand, so a court that is not
## arming sells freely.
static func muster_reserve(
	config: MainlineAiConfig,
	economy: PlayerEconomy,
	own_regiments: int,
	at_war: bool
) -> Dictionary:
	if config == null or economy == null or own_regiments >= _target(config, at_war):
		return {}
	var type_id: String = saving_type(config, economy)
	if type_id.is_empty():
		return {}
	return RegimentEconomy.training_inputs(type_id)


## The line this court is saving for: the pattern it could raise today if its
## stores allowed, else the cheapest line its techs and fields open — the one a
## war chest it cannot yet spend will actually buy. Never empty unless its techs
## open no line at all or its fields cannot spare a hand (wiki:
## growth-stage-planner § Recruitment modulation; issue #474).
static func saving_type(config: MainlineAiConfig, economy: PlayerEconomy) -> String:
	if config == null or economy == null:
		return ""
	if economy.available_peasants() - RegimentEconomy.WORKER_COST < config.parameter(
		"army.min_peasants"
	):
		return ""
	var type_id: String = next_type(config, economy)
	if not type_id.is_empty():
		return type_id
	return _cheapest_line_type(economy)


## Treasury a court must hold before any muster is legal: `army.min_treasury`
## still in the purse after paying for the cheapest line pattern its techs open.
## 0 when it already stands at its target, can raise nothing, or has no peasant
## to spare. Other planners read it as the war chest they must not spend, so a
## court saving for its next regiment never funds itself into the deadlock where
## every muster is one ducat short (wiki: ai-architecture § Land reinforcement;
## growth-stage-planner § Recruitment modulation).
static func muster_floor(
	config: MainlineAiConfig,
	economy: PlayerEconomy,
	own_regiments: int,
	at_war: bool
) -> int:
	if config == null or economy == null:
		return 0
	if own_regiments >= _target(config, at_war):
		return 0
	if economy.available_peasants() - RegimentEconomy.WORKER_COST < config.parameter(
		"army.min_peasants"
	):
		return 0
	var floor_treasury: int = maxi(config.parameter("army.min_treasury"), 0)
	var cheapest: int = _cheapest_line(economy)
	if cheapest < 0:
		return floor_treasury
	return floor_treasury + cheapest


## Price of the cheapest line pattern this court's techs open today, ignoring the
## purse: what it has to save for, not what it can pay right now. -1 when its
## techs open no line at all.
static func _cheapest_line(economy: PlayerEconomy) -> int:
	var type_id: String = _cheapest_line_type(economy)
	if type_id.is_empty():
		return -1
	return RegimentCatalog.treasury_cost(type_id)


## The cheapest line pattern this court's techs open today, ignoring the purse.
## The lowest id breaks a tie, so the answer is stable across turns.
static func _cheapest_line_type(economy: PlayerEconomy) -> String:
	var cheapest: String = ""
	var cost: int = -1
	for type_id: String in RegimentCatalog.ids():
		if not LINE_CATEGORIES.has(RegimentCatalog.category(type_id)):
			continue
		if not RegimentEconomy.buildable(type_id, economy.tech_unlocked):
			continue
		var price: int = RegimentCatalog.treasury_cost(type_id)
		if cost < 0 or price < cost or (price == cost and type_id < cheapest):
			cheapest = type_id
			cost = price
	return cheapest


## Line patterns this court's treasury, labour pool and techs open today,
## strongest first. Materials are not read here; `plan` and `next_type` each
## decide what to do with a pattern the stores cannot yet pay for.
static func _legal_candidates(
	config: MainlineAiConfig, economy: PlayerEconomy
) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if config == null or economy == null:
		return candidates
	if economy.available_peasants() - RegimentEconomy.WORKER_COST < config.parameter(
		"army.min_peasants"
	):
		return candidates
	var floor_treasury: int = config.parameter("army.min_treasury")
	for type_id: String in RegimentCatalog.ids():
		if not LINE_CATEGORIES.has(RegimentCatalog.category(type_id)):
			continue
		if not RegimentEconomy.buildable(type_id, economy.tech_unlocked):
			continue
		if economy.treasury - RegimentCatalog.treasury_cost(type_id) < floor_treasury:
			continue
		candidates.append({
			"type_id": type_id,
			"strength": RegimentCatalog.strength(type_id),
			"era": RegimentCatalog.era(type_id),
		})
	candidates.sort_custom(_better)
	return candidates


## Strongest first, then the newer pattern, then the lowest id — one stable
## answer for a given ledger and tech set.
static func _better(a: Dictionary, b: Dictionary) -> bool:
	if int(a["strength"]) != int(b["strength"]):
		return int(a["strength"]) > int(b["strength"])
	if int(a["era"]) != int(b["era"]):
		return int(a["era"]) > int(b["era"])
	return String(a["type_id"]) < String(b["type_id"])