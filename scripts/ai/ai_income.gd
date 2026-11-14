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
## lay as readily as the next regiment (issue #484). Pure and deterministic:
## the purse and the target are the only inputs (REQ-P2-03, REQ-P3-03).

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
## at war, the muster it is saving for (its own cash floor plus the cheapest
## line) and the hull it means to lay (`AiNavy`, issue #484), whichever is
## larger, while it stands under the target that asks for either; at peace, its
## own cash floor, so a court that is not fighting still grows. 0 when the caller
## has no ledger to read.
static func reserve(
	config: AiConfig, economy: PlayerEconomy, at_war: bool, regiments: int,
	hull_chest: int = 0
) -> int:
	if config == null or economy == null:
		return 0
	var floor: int = maxi(config.parameter("economy.min_treasury"), 0)
	if not at_war:
		return floor
	var muster: int = maxi(floor, AiArmyReinforce.muster_floor(config, economy, regiments, true))
	return maxi(muster, maxi(hull_chest, 0))


## One turn's goal plus the readings behind it, for the turn trace and the
## observer row. `hull_chest` is the yard price the court is saving for, 0 when
## it is not rebuilding its fleet.
static func plan(
	config: AiConfig, economy: PlayerEconomy, at_war: bool, regiments: int,
	hull_chest: int = 0
) -> Dictionary:
	var need: int = reserve(config, economy, at_war, regiments, hull_chest)
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
	hull_chest: int = 0
) -> String:
	return String(plan(config, economy, at_war, regiments, hull_chest)["goal"])


## True while the court's money comes before anything it can defer.
static func wants_income(
	config: AiConfig, economy: PlayerEconomy, at_war: bool, regiments: int,
	hull_chest: int = 0
) -> bool:
	return goal_for(config, economy, at_war, regiments, hull_chest) == GOAL_EARN


## Reader-facing goal for the observer panel and the turn trace.
static func label(goal: String) -> String:
	return String(LABELS.get(goal, LABELS[GOAL_SPEND]))
