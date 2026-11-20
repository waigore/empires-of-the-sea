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
## buy a regiment the human rules would refuse. Line-pattern answers live on
## [AiArmyReinforceLine]; this owner keeps the turn plan and the food/purse
## gates that decide whether a muster fires.

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
## apply. `harvest_slack` is the reading the growth gate plans with: the ration
## food the court's own harvest carries less every mouth it already feeds
## (`AiState.food_slack`, noted by the economy pass). The army the court
## desires is provisioned before it is raised — a court whose harvest cannot
## carry one more ration arms no further, and its food income is grown first,
## so the store's runway no longer lets the court arm past its land (issue
## #807; the fallback trim's measured lesson). The sentinel -2 keeps the
## store gate alone.
## `reserve` is the purse a claim above this muster holds back — the hull the
## court is saving for (`AiNavy`). A muster spends only what stands above it, so
## the fleet's chest survives the army's turn (issue #484) — but only when the
## court can already fill that chest: a yard price it is still short of is not
## held back at all while a regiment is due, so unlocking a warship can never
## starve the line (issue #591, `AiIncome.hull_held`). `own_warships` is that
## same gate: a fleetless court keeps the chest even while short (issue #484)
## — and never while it banks for the army its conquest still needs (issue
## #995): `conquest_gap` drops the rebuild chest behind the line, because the
## army holds the land the yard stands on.
static func plan(
	config: AiConfig,
	economy: PlayerEconomy,
	own_regiments: int,
	at_war: bool,
	pressure_extra: int = 0,
	fed_slack: int = -1,
	reserve: int = 0,
	held_row: Dictionary = {},
	own_warships: int = -1,
	harvest_slack: int = -2,
	conquest_gap: bool = false
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
	if not AiArmyReinforceLine.labour_floor_ok(config, economy):
		result["reasons"].append("labour floor")
		return result
	if fed_slack >= 0 and fed_slack < 1:
		result["reasons"].append("striking for food")
		return result
	if harvest_slack >= -1 and harvest_slack < 1:
		result["reasons"].append("the harvest cannot carry one more ration")
		return result
	var chest: int = AiIncome.hull_held(
		config, economy, at_war, own_regiments, reserve, own_warships, conquest_gap
	)
	# The hull's row is the fleet's once the chest is full: the muster spends
	# only what stands above it, exactly as it spends only the purse above the
	# chest. A court that wove one cloth a turn and mustered it away could never
	# lay the hull it had already paid for (issue #484). The same `hull_held`
	# gate drops the row while the chest is still out of reach (issue #591).
	var stores: Dictionary = _stores_above(
		economy.stockpile, held_row if chest > 0 else {}
	)

	var candidates: Array[Dictionary] = []
	for entry: Dictionary in AiArmyReinforceLine.candidates(config, economy, chest):
		if not RegimentEconomy.missing_inputs(String(entry["type_id"]), stores).is_empty():
			continue
		candidates.append(entry)
	result["candidates"] = candidates
	if candidates.is_empty():
		if chest > 0 and economy.treasury <= chest:
			result["reasons"].append("saving for a hull")
		else:
			result["reasons"].append("nothing payable")
			# Name the row that blocked it: a court holding its whole war chest
			# reads `nothing payable` for a missing pattern row otherwise, which
			# is what kept the material-row deadlock unrecorded (issue #474).
			result["reasons"].append_array(_missing_reasons(config, economy, stores))
		return result
	result["muster"] = String(candidates[0]["type_id"])
	return result


## The stockpile a muster may spend: everything the court holds, less the row a
## higher-ranked claim keeps back (the hull's cloth). Empty `held` returns the
## store untouched, so a court with no hull due musters exactly as before.
static func _stores_above(stockpile: Dictionary, held: Dictionary) -> Dictionary:
	if held.is_empty():
		return stockpile
	var stores: Dictionary = stockpile.duplicate()
	for commodity: Variant in held.keys():
		var id: String = String(commodity)
		stores[id] = maxi(int(stores.get(id, 0)) - int(held[commodity]), 0)
	return stores


## The material rows the pattern this court is saving for still lacks, named for
## the turn trace: a court holding a full war chest and no fabric musters
## nothing, and `nothing payable` alone never said why (issue #474).
static func _missing_reasons(
	config: AiConfig, economy: PlayerEconomy, stores: Dictionary = {}
) -> Array[String]:
	var reasons: Array[String] = []
	var type_id: String = saving_type(config, economy)
	if type_id.is_empty():
		return reasons
	var missing: Dictionary = RegimentEconomy.missing_inputs(
		type_id, stores if not stores.is_empty() else economy.stockpile
	)
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


## Grain the larder leaves once the army, the navy and every worker have eaten
## (wiki: workers-and-population § Consumption, in that order). Negative means
## the workers strike and the court's labour is gone for the turn; 0 means they
## eat but nothing is left for one more man. The arithmetic is the phase's own:
## `LarderRead` serves the published larder in its deduction order, so the muster
## gate, the strike rule and the ledger's larder line name one number and never
## drift apart (issue #489; REQ-P2-03).
static func fed_slack(economy: PlayerEconomy, army_food: int, ships: int) -> int:
	if economy == null:
		return 0
	var read: Dictionary = LarderRead.reading(
		economy.workers, economy.stockpile, {"army": army_food, "ships": ships}
	)
	var mouths: Dictionary = read["appetites"]
	var wanted: int = int(mouths["army"]) + int(mouths["navy"]) + int(mouths["pool"])
	return int(read["store_food"]) - wanted


## True when this court's own people are on strike for food: the ration the
## consumption phase owes its workers is more than the larder leaves after the
## army and the navy eat (wiki: workers-and-population § Strike workers).
static func starving(economy: PlayerEconomy, army_food: int, ships: int) -> bool:
	return fed_slack(economy, army_food, ships) < 0


## Peasants a court keeps in the fields so its muster stays legal: the
## `army.min_peasants` floor the muster itself reads plus the levy's own hand
## (`RegimentEconomy.WORKER_COST`). The reservation is answered only while the
## court stands under its target, is at war, holds the material row of the
## pattern it is saving for, and its purse already holds the muster's war chest
## — behind the slot un-latch and the chest escalation, never ahead of them
## (issue #807, evidence/issue-474 Round 9: measured −3.65 % on the destitute
## tree where it never fired). 0 otherwise, so a court that is not arming
## trains freely.
static func muster_hands(
	config: AiConfig,
	economy: PlayerEconomy,
	own_regiments: int,
	at_war: bool
) -> int:
	if config == null or economy == null or not at_war:
		return 0
	if own_regiments >= _target(config, at_war):
		return 0
	var type_id: String = saving_type(config, economy)
	if type_id.is_empty():
		return 0
	if not RegimentEconomy.missing_inputs(type_id, economy.stockpile).is_empty():
		return 0
	if economy.treasury < muster_floor(config, economy, own_regiments, at_war):
		return 0
	return config.parameter("army.min_peasants") + RegimentEconomy.WORKER_COST


## Regiments the court aims at: the peace target, raised by `army.war_extra` at
## war (wiki: ai-architecture § Land reinforcement).
static func _target(config: AiConfig, at_war: bool) -> int:
	var target: int = config.parameter("army.regiment_target")
	if at_war:
		target += config.parameter("army.war_extra")
	return target


## The army the court desires at its published target — the size it plans food
## income for while it stands under it (issue #807). The same table
## `_target` prices the muster with.
static func desired_regiments(config: AiConfig, at_war: bool) -> int:
	if config == null:
		return 0
	return _target(config, at_war)


## The line regiment this court would raise if its stores could pay for it.
## Owned by [AiArmyReinforceLine]; kept here so planners keep one call site.
static func next_type(config: AiConfig, economy: PlayerEconomy) -> String:
	return AiArmyReinforceLine.next_type(config, economy)


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
	config: AiConfig,
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


## The line this court is saving for. Owned by [AiArmyReinforceLine].
static func saving_type(config: AiConfig, economy: PlayerEconomy) -> String:
	return AiArmyReinforceLine.saving_type(config, economy)


## Treasury a court must hold before any muster is legal: `army.min_treasury`
## still in the purse after paying for the cheapest line pattern its techs open.
## 0 when it already stands at its target, can raise nothing, or has no peasant
## to spare. Other planners read it as the war chest they must not spend, so a
## court saving for its next regiment never funds itself into the deadlock where
## every muster is one ducat short (wiki: ai-architecture § Land reinforcement;
## growth-stage-planner § Recruitment modulation).
static func muster_floor(
	config: AiConfig,
	economy: PlayerEconomy,
	own_regiments: int,
	at_war: bool
) -> int:
	if config == null or economy == null:
		return 0
	if own_regiments >= _target(config, at_war):
		return 0
	if not AiArmyReinforceLine.labour_floor_ok(config, economy):
		return 0
	var floor_treasury: int = maxi(config.parameter("army.min_treasury"), 0)
	var cheapest: int = AiArmyReinforceLine.cheapest_line(economy)
	if cheapest < 0:
		return floor_treasury
	return floor_treasury + cheapest


## Why a court standing under its target prices no muster row ("" when the row
## stands): the muster's own gates, in the trace's words, so a silent absence
## cannot hide the starvation again (issue #1143). The muster's own money and
## food gates live on `plan`; this names only the gates that price the row
## itself — the labour floor and a court whose techs open no line pattern.
static func absent_reason(
	config: AiConfig, economy: PlayerEconomy, own_regiments: int, at_war: bool
) -> String:
	if config == null or economy == null:
		return ""
	if own_regiments >= _target(config, at_war):
		return ""
	if not AiArmyReinforceLine.labour_floor_ok(config, economy):
		return "the labour floor holds: no spare hand for the levy"
	if AiArmyReinforceLine.saving_type(config, economy).is_empty():
		return "no line pattern its techs open"
	return ""


## Price of the cheapest line pattern this court's techs open today. Owned by
## [AiArmyReinforceLine].
static func cheapest_line_price(economy: PlayerEconomy) -> int:
	return AiArmyReinforceLine.cheapest_line_price(economy)
