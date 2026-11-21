class_name AiDiplomacyPacts
extends RefCounted
## The treaty breaks a rival court weighs against its standing: a formal
## alliance it no longer means to honour, and the non-aggression pact its
## conquest waits behind (wiki: diplomacy § Breaking an alliance, § Breaking a
## pact; issues #752, #995). Split from [AiDiplomacyOffers] so the court menu's
## rung list keeps its own reads and no AI module outgrows the size bar
## (REQ-P3-01). Pure rules: state in, candidate out (REQ-P3-03).

const KIND_BREAK: String = DiplomacyOrders.KIND_BREAK
const KIND_BREAK_NAP: String = DiplomacyOrders.KIND_BREAK_NAP

## An alliance that no longer matches the standing is dissolved, never defended.
const BREAK_MIN_DESIRE: int = 60
const BREAK_UTILITY_COST: int = 20
## A pact the court means to march on is broken first: the war ban lifts at the
## next turn, so the break is worth `warDesireScore − 10` — cheaper resolve than
## the alliance break it may carry, and the price it pays is the relation
## cascade, not a second discount on the resolve it takes to march
## (wiki: diplomacy § Planner selection — a blocked war is a break, not a stall;
## issue #752).
const BREAK_NAP_UTILITY_COST: int = 10


## A treaty the court no longer means to honour is dissolved before it costs
## more than the standing it was signed on (wiki: diplomacy § Breaking an
## alliance). While the pact stands, one Break NAP clears pact and alliance
## together, so the alliance-only break would be a wasted turn (issue #752).
static func break_alliance(
	state: DiplomacyState, faction: int, target: int,
	record: DiplomacyRelation, desire: int
) -> Dictionary:
	if record == null or not record.formal_alliance:
		return _blocked("no formal alliance stands", KIND_BREAK)
	if state != null and DiplomacyRules.has_pact(state, faction, target):
		return _blocked("the pact break clears the alliance too", KIND_BREAK)
	if desire < BREAK_MIN_DESIRE:
		return _blocked("the alliance still serves", KIND_BREAK)
	return _offer(KIND_BREAK, target, desire - BREAK_UTILITY_COST)


## The pact the court means to march on is broken first: the war ban lifts at
## the next turn, and a formal alliance rides the break at the alliance price
## (wiki: diplomacy § Breaking a pact; issue #752). The break is only worth the
## price it pays when the war could actually follow: the pair off its war
## cooldown, no envoy chain with a claim on the target (a declaration would
## clear what the court has paid for), and a footing that opens the front
## (issues #724, #752) — the planner's own war gate, read from
## AiDiplomacyGates.
static func break_nap(
	config: AiConfig,
	state: DiplomacyState,
	world: WorldMap,
	ai_state: AiState,
	turn: int,
	faction: int,
	target: int,
	record: DiplomacyRelation,
	desire: int,
	context: Dictionary
) -> Dictionary:
	if record == null or not DiplomacyRules.has_pact(state, faction, target):
		return _blocked("no non-aggression pact stands", KIND_BREAK_NAP)
	if desire < BREAK_MIN_DESIRE:
		return _blocked("the pact still serves", KIND_BREAK_NAP)
	# The conquest bank (issue #995): a pact break that cannot yet be followed
	# by its war waits behind the bank — the relation cascade is spent the
	# turn the host it arms can march, and a court still banking has built no
	# host (the war gate holds the declaration until the bank releases). The
	# break leads again the turn the host stands, where the planner ranks it
	# first (issue #995's pact wall). The trace names the aim the purse is
	# held for (issue #1135).
	var banked_break: String = AiIncome.bank_refusal(
		config, ai_state, (context.get("income", {}) as Dictionary)
	)
	if not banked_break.is_empty():
		return _blocked(banked_break, KIND_BREAK_NAP)
	# The war the break opens: one shared gate with the planner, so a break the
	# court would not follow with a declaration is never offered (see
	# `AiDiplomacyGates.pact_break_block`).
	var blocked_war: String = AiDiplomacyGates.pact_break_block(
		config, state, world, ai_state, turn, target, context
	)
	if not blocked_war.is_empty():
		return _blocked(blocked_war, KIND_BREAK_NAP)
	return _offer(KIND_BREAK_NAP, target, desire - BREAK_NAP_UTILITY_COST)


static func _offer(kind: String, target: int, utility: int) -> Dictionary:
	return {
		"ok": true,
		"kind": kind,
		"target": target,
		"utility": clampi(utility, 0, 100),
		"stage": "",
		"amount": 0,
	}


## A refused candidate keeps its kind, so the turn trace names what the court
## would not offer and why (wiki: turn-trace-interpretation).
static func _blocked(reason: String, kind: String = "") -> Dictionary:
	return {"ok": false, "kind": kind, "blocked": reason}
