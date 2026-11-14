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
## `pressure_extra` is the extra target a court that can see the victory bar
## arms up for (DR-20261114-04); it raises the target, never the price.
## `fed_slack` is the grain the larder leaves after the army, the navy and the
## workers eat (see `fed_slack`); a court with no room for one more ration
## raises no more men, because the men it has would go hungry instead
## (wiki: workers-and-population § Strike workers; issue #489). A negative
## reading means the caller has no larder to read, and the food gates do not
## apply.
static func plan(
	config: MainlineAiConfig,
	economy: PlayerEconomy,
	own_regiments: int,
	at_war: bool,
	pressure_extra: int = 0,
	fed_slack: int = -1
) -> Dictionary:
	var result: Dictionary = {
		"muster": "", "target": 0, "reasons": [], "candidates": [],
	}
	if config == null or economy == null:
		return result
	var target: int = _target(config, at_war) + maxi(pressure_extra, 0)
	result["target"] = target
	if own_regiments >= target:
		result["reasons"].append("at target strength")
		return result
	if economy.available_peasants() - RegimentEconomy.WORKER_COST < config.parameter(
		"army.min_peasants"
	):
		result["reasons"].append("labour floor")
		return result
	if fed_slack >= 0 and fed_slack < 1:
		result["reasons"].append("striking for food")
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
		# Name the row that blocked it: a court holding its whole war chest
		# reads `nothing payable` for a missing pattern row otherwise, which is
		# what kept the material-row deadlock unrecorded (issue #474).
		result["reasons"].append_array(_missing_reasons(config, economy))
		return result
	result["muster"] = String(candidates[0]["type_id"])
	return result


## The material rows the pattern this court is saving for still lacks, named for
## the turn trace: a court holding a full war chest and no fabric musters
## nothing, and `nothing payable` alone never said why (issue #474).
static func _missing_reasons(config: MainlineAiConfig, economy: PlayerEconomy) -> Array[String]:
	var reasons: Array[String] = []
	var type_id: String = saving_type(config, economy)
	if type_id.is_empty():
		return reasons
	var missing: Dictionary = RegimentEconomy.missing_inputs(type_id, economy.stockpile)
	var ids: Array[String] = []
	for raw: Variant in missing.keys():
		ids.append(String(raw))
	ids.sort()
	for id: String in ids:
		reasons.append("missing %s %d" % [id, int(missing[id])])
	return reasons


## The province a stranded Home Army must march to, or -1 when it already stands
## at its seat. A court whose capital moves musters nowhere until the Home Army
## is recalled, so the recall is the first thing the muster pass does — the
## regiment joins the Home Army, and the Home Army is at the seat (issue #474).
static func recall_target(home_province: int, capital: int) -> int:
	if capital < 0 or home_province == capital:
		return -1
	return capital


## Grain and meat the larder holds: the two ration commodities, nothing else
## (wiki: workers-and-population § Consumption).
static func larder(economy: PlayerEconomy) -> int:
	if economy == null:
		return 0
	var held: int = 0
	for id: String in CommodityCatalog.FOOD:
		held += maxi(economy.quantity(id), 0)
	return held


## Grain the larder leaves once the consumption phase has fed the army, the navy
## and every worker (wiki: workers-and-population § Consumption: land military
## first, then navy, then workers). Negative means the workers strike for food
## and the court's labour is gone for the turn; 0 means they eat but nothing is
## left for one more man. The reading is the same one the strike rule makes, so
## a court never musters into a famine it cannot feed (issue #489).
static func fed_slack(economy: PlayerEconomy, army_food: int, ships: int) -> int:
	if economy == null:
		return 0
	var navy: int = maxi(ships, 0) * ShipEconomy.FOOD_UPKEEP_PER_SHIP
	var workers: int = 0
	for tier in WorkerPool.TIER_COUNT:
		workers += economy.workers.count(tier) * WorkerPool.FOOD_PER_WORKER[tier]
	return larder(economy) - maxi(army_food, 0) - navy - workers


## True when this court's own people are on strike for food: the ration the
## consumption phase owes its workers is more than the larder leaves after the
## army and the navy eat (wiki: workers-and-population § Strike workers).
static func starving(economy: PlayerEconomy, army_food: int, ships: int) -> bool:
	return fed_slack(economy, army_food, ships) < 0


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
	at_war: bool,
	pressure_extra: int = 0
) -> Dictionary:
	if config == null or economy == null:
		return {}
	if own_regiments >= _target(config, at_war) + maxi(pressure_extra, 0):
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