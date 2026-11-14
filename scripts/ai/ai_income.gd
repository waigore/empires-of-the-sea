class_name AiIncome
extends RefCounted
## The court's money goal (wiki: ai-architecture § Money first;
## treasury-planner § Priority; DR-20261113-19).
##
## Income outranks every want a court has except the victory itself, and the
## victory cannot be bought without it: a court that cannot pay for its next
## regiment cannot take a province, and a court that cannot take a province
## never reaches the bar. So before the planners run, each court reads whether
## its purse can already carry its next commitment — the muster it means to
## raise, or its own cash floor once it stands at target.
##
## A court short of that reads `earn`. Its income planners lead (voyages, sales,
## extraction works, prizes) and every spender that can wait stands down: no
## studies, no hires, no imports, no new war. A court that can pay reads
## `spend` and plays as published. The commitment can be the hull it means to
## lay as readily as the next regiment (issue #484) — but only once the court can
## already fill that chest: a yard price it is still short of waits behind the
## army, because a reserve no planner can pay out starves the regiment the court
## could have raised (issue #591). Pure and deterministic: the purse and the
## target are the only inputs (REQ-P2-03, REQ-P3-03).

const GOAL_EARN: String = "earn"
const GOAL_SPEND: String = "spend"

const LABELS: Dictionary = {
	GOAL_EARN: "earning",
	GOAL_SPEND: "spending",
}


## True when any court holds a declared war on this one: the reserve a court
## must hold is read against it, and a war lifts the muster target by
## `army.war_extra` (wiki: ai-architecture § Land reinforcement).
static func at_war(state: DiplomacyState, faction: int) -> bool:
	if state == null:
		return false
	for record: DiplomacyRelation in state.relations_of(faction):
		if record.at_war:
			return true
	return false


## The purse this court must hold before it may spend on anything it can defer:
## At war: the muster it is saving for and the hull it means to lay (`AiNavy`,
## issue #484) once that chest is in reach — whichever is larger. At peace: its
## cash floor, or the hull chest when rebuilding with no fighting hull left so
## the yard is not gifted away before the next war (#484). 0 when the caller
## has no ledger to read.
static func reserve(
	config: AiConfig, economy: PlayerEconomy, at_war: bool, regiments: int,
	hull_chest: int = 0, own_warships: int = -1
) -> int:
	if config == null or economy == null:
		return 0
	var floor: int = maxi(config.parameter("economy.min_treasury"), 0)
	if not at_war:
		return maxi(
			floor, hull_held(config, economy, false, regiments, hull_chest, own_warships)
		)
	var muster: int = maxi(floor, AiArmyReinforce.muster_floor(config, economy, regiments, true))
	return maxi(
		muster, hull_held(config, economy, true, regiments, hull_chest, own_warships)
	)


## The yard's chest as this court holds it this turn. A chest the court can
## already fill is the fleet's — the purse waits for the hull and the yard leads.
## A chest it cannot afford yet stands behind the army, unless the court has no
## fighting hull left — then the rebuild chest is held even while the muster is
## due (#484, #591). 0 when there is no hull to save for.
static func hull_held(
	config: AiConfig, economy: PlayerEconomy, at_war: bool, regiments: int,
	hull_chest: int, own_warships: int = -1
) -> int:
	var chest: int = maxi(hull_chest, 0)
	if config == null or economy == null or chest <= 0:
		return chest
	if economy.treasury >= chest:
		return chest
	if own_warships == 0:
		return chest
	if AiArmyReinforce.muster_floor(config, economy, regiments, at_war) > 0:
		return 0
	return chest


## One turn's goal plus the readings behind it, for the turn trace and the
## observer row. `hull_chest` is the yard price the court is saving for, 0 when
## it is not rebuilding its fleet.
static func plan(
	config: AiConfig, economy: PlayerEconomy, at_war: bool, regiments: int,
	hull_chest: int = 0, own_warships: int = -1
) -> Dictionary:
	var need: int = reserve(config, economy, at_war, regiments, hull_chest, own_warships)
	var held: int = economy.treasury if economy != null else 0
	return {
		"goal": GOAL_EARN if held < need else GOAL_SPEND,
		"reserve": need,
		"treasury": held,
		"regiments": regiments,
		"hull_chest": maxi(hull_chest, 0),
	}


## Goal name only, for callers that do not keep the readings.
static func goal_for(
	config: AiConfig, economy: PlayerEconomy, at_war: bool, regiments: int,
	hull_chest: int = 0, own_warships: int = -1
) -> String:
	return String(plan(config, economy, at_war, regiments, hull_chest, own_warships)["goal"])


## True while the court's money comes before anything it can defer.
static func wants_income(
	config: AiConfig, economy: PlayerEconomy, at_war: bool, regiments: int,
	hull_chest: int = 0, own_warships: int = -1
) -> bool:
	return goal_for(config, economy, at_war, regiments, hull_chest, own_warships) == GOAL_EARN


## The refusal a deferrable spender records while the court is still filling its
## purse, naming the reserve it keeps (wiki: treasury-planner § Priority; issue
## #580). `amount` is what the order would take out of the purse today (0 for an
## order that only promises future money, like a subsidy). Empty when the court
## may spend without dipping under the reserve it is saving for.
static func saving_reason(income: Dictionary, amount: int = 0) -> String:
	# No money goal read (a caller with no ledger) keeps the published behaviour.
	if income.is_empty():
		return ""
	var reserve: int = int(income.get("reserve", 0))
	var held: int = int(income.get("treasury", 0))
	if String(income.get("goal", GOAL_SPEND)) != GOAL_EARN and held - amount >= reserve:
		return ""
	return "the court is saving for its reserve (%d)" % reserve


## Reader-facing goal for the observer panel and the turn trace.
static func label(goal: String) -> String:
	return String(LABELS.get(goal, LABELS[GOAL_SPEND]))
