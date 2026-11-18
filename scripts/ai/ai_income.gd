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
## the yard is not gifted away before the next war (#484) — plus the muster
## chest once the purse holds the cheapest line's own price, so the regiment a
## peaceful court is one payment short of is banked, not auctioned away
## (#603). 0 when the caller has no ledger to read.
##
## `conquest_gap` is the win-bar reading (issue #995): a court that is short of
## the Old World bar with an army still under target banks for the regiment
## that takes the provinces it needs — at peace as at war. The conquest
## shortfall is the trigger, not the war: the buy-out (#975) and the prompt end
## of pointless wars (#999) often leave a court at peace precisely because it
## has no army, and a peace that never banks never arms. The bank also holds
## through the escalation stall: the gap is the standing reason to bank, so a
## wobble in the fill is not a stall.
##
## `muster_stall` is the deferred-aim escalation reading (#603): the turns the
## muster aim has been deferred without its shortfall shrinking. A war chest
## the court has stalled on re-routes — the reserve falls back to the cash
## floor and the reachable hull chest, so every planner that reads it leads
## again — and the shortfall shrinking resumes the chest as published.
static func reserve(
	config: AiConfig, economy: PlayerEconomy, at_war: bool, regiments: int,
	hull_chest: int = 0, own_warships: int = -1, muster_stall: int = 0,
	conquest_gap: bool = false
) -> int:
	if config == null or economy == null:
		return 0
	var floor: int = maxi(config.parameter("economy.min_treasury"), 0)
	var muster: int = AiArmyReinforce.muster_floor(config, economy, regiments, true)
	if muster_stall >= maxi(config.parameter("ledger.escalate_turns"), 1):
		# The re-route: the reserve the court cannot reach stands down so the
		# court's own income planners lead again (issue #603). The bar reads
		# two turns, not one (issue #995): a bank that is progressing
		# restarts the stall at one on every new-low turn, and the bar at one
		# answered the fill's own progress — no chest ever closed, at war or
		# at peace. Two turns means a genuine standing-still re-routes and a
		# filling bank never does; the valve itself is untouched.
		muster = 0
	elif not at_war and not conquest_gap:
		# At peace the war chest is kept only once the purse already holds the
		# cheapest line's own price (wiki: ai-architecture § Land
		# reinforcement): a poorer court keeps its cash floor and grows — no
		# peace-time save phase (DR-20261113-22) — and a court in reach banks
		# the last of the chest instead of auctioning it away the turn peace
		# opens (issue #603). A court short of the bar keeps the whole chest
		# (issue #995): the gap is the trigger, not the war.
		if economy.treasury < AiArmyReinforce.cheapest_line_price(economy):
			muster = 0
	var held: int = hull_held(
		config, economy, at_war, regiments, hull_chest, own_warships, conquest_gap
	)
	return maxi(floor, maxi(muster, held))


## The yard's chest as this court holds it this turn. A chest the court can
## already fill is the fleet's — the purse waits for the hull and the yard leads.
## A chest it cannot afford yet stands behind the army, unless the court has no
## fighting hull left — then the rebuild chest is held even while the muster is
## due (#484, #591) — and never while the court banks for the army its conquest
## still needs (issue #995): a fleetless court at war that is short of the bar
## with a host under strength buys its line before its hull, because the army
## holds the land the yard stands on. 0 when there is no hull to save for.
static func hull_held(
	config: AiConfig, economy: PlayerEconomy, at_war: bool, regiments: int,
	hull_chest: int, own_warships: int = -1, conquest_gap: bool = false
) -> int:
	var chest: int = maxi(hull_chest, 0)
	if config == null or economy == null or chest <= 0:
		return chest
	if economy.treasury >= chest:
		return chest
	if own_warships == 0 and not conquest_gap:
		return chest
	if AiArmyReinforce.muster_floor(config, economy, regiments, at_war) > 0:
		return 0
	return chest


## One turn's goal plus the readings behind it, for the turn trace and the
## observer row. `hull_chest` is the yard price the court is saving for, 0 when
## it is not rebuilding its fleet. `muster_stall` is the deferred-aim
## escalation reading (issue #603; see `reserve`). `conquest_gap` is the
## win-bar reading (issue #995; see `reserve`).
static func plan(
	config: AiConfig, economy: PlayerEconomy, at_war: bool, regiments: int,
	hull_chest: int = 0, own_warships: int = -1, muster_stall: int = 0,
	conquest_gap: bool = false
) -> Dictionary:
	var need: int = reserve(
		config, economy, at_war, regiments, hull_chest, own_warships, muster_stall,
		conquest_gap
	)
	var held: int = economy.treasury if economy != null else 0
	return {
		"goal": GOAL_EARN if held < need else GOAL_SPEND,
		"reserve": need,
		"treasury": held,
		"regiments": regiments,
		"hull_chest": maxi(hull_chest, 0),
		# The win-bar reading the bank rides on (issue #995): the trace and
		# the treaty rungs read it beside the goal it moved.
		"conquest_gap": conquest_gap,
	}


## Goal name only, for callers that do not keep the readings.
static func goal_for(
	config: AiConfig, economy: PlayerEconomy, at_war: bool, regiments: int,
	hull_chest: int = 0, own_warships: int = -1, conquest_gap: bool = false
) -> String:
	return String(
		plan(config, economy, at_war, regiments, hull_chest, own_warships, 0, conquest_gap)["goal"]
	)


## True while the court's money comes before anything it can defer.
static func wants_income(
	config: AiConfig, economy: PlayerEconomy, at_war: bool, regiments: int,
	hull_chest: int = 0, own_warships: int = -1, conquest_gap: bool = false
) -> bool:
	return (
		goal_for(config, economy, at_war, regiments, hull_chest, own_warships, conquest_gap)
		== GOAL_EARN
	)


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


## True while this court is banking for the army its conquest still needs
## (issue #995): the win-bar gap holds, the host stands under the war-time
## target, and the purse is one line-cycle short of the chest — so every
## deferrable purchase (a war, a pact break, an envoy rung) waits, and a purse
## that peaks inside a turn still belongs to the army that marches before
## anything else spends it. The read is the purse, the host and the bar, never
## the money goal: the goal wobbles on the re-route cycle, and a wobble must
## not open a front. A caller with no ledger or no income row keeps the
## published behaviour.
static func banking(
	config: AiConfig, ai_state: AiState, income: Dictionary
) -> bool:
	if config == null or not bool(income.get("conquest_gap", false)):
		return false
	if int(income.get("regiments", 0)) >= AiArmyReinforce.desired_regiments(config, true):
		return false
	var economy: PlayerEconomy = (
		ai_state.economy_for(config.faction) if ai_state != null else null
	)
	if economy == null:
		return false
	var shortfall: int = maxi(int(income.get("reserve", 0)), 0) + maxi(
		AiArmyReinforce.cheapest_line_price(economy), 0
	)
	return int(income.get("treasury", 0)) < shortfall


## Reader-facing goal for the observer panel and the turn trace.
static func label(goal: String) -> String:
	return String(LABELS.get(goal, LABELS[GOAL_SPEND]))
