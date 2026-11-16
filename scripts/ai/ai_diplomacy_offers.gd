class_name AiDiplomacyOffers
extends RefCounted
## Peaceful orders a rival court weighs against war: the overture chain, a formal
## alliance, trade pacts, boycotts, subsidies and foreign aid (wiki: diplomacy
## § Diplomatic Order Types, § GP AI policy for war vs. relations). One order per
## court per turn stays the rule (DR-20261108-01), so this module ranks the
## peaceful candidates for one target and hands the winner back to the planner.
## Every candidate asks the same rules module the court panel calls, so a rival
## never offers what the player could not (REQ-P2-03). Pure rules: state in,
## candidate out (REQ-P3-03).
##
## Utilities are fixed data (DR-20261110-15): a friendly act is worth the
## improve-relations desire less what it spends, and retaliation is worth how
## far the standing has fallen.

const KIND_ALLIANCE: String = DiplomacyOrders.KIND_ALLIANCE
const KIND_OVERTURE: String = DiplomacyOrders.KIND_OVERTURE
const KIND_FTP: String = DiplomacyOrders.KIND_FTP
const KIND_REVOKE_FTP: String = DiplomacyOrders.KIND_REVOKE_FTP
const KIND_BOYCOTT: String = DiplomacyOrders.KIND_BOYCOTT
const KIND_REVOKE_BOYCOTT: String = DiplomacyOrders.KIND_REVOKE_BOYCOTT
const KIND_AID: String = DiplomacyOrders.KIND_AID
const KIND_SUBSIDY: String = DiplomacyOrders.KIND_SUBSIDY
const KIND_CANCEL_SUBSIDY: String = DiplomacyOrders.KIND_CANCEL_SUBSIDY
const KIND_BREAK: String = DiplomacyOrders.KIND_BREAK
const KIND_BREAK_NAP: String = DiplomacyOrders.KIND_BREAK_NAP

## Every kind this module can emit; the planner adds Declare War and Offer Peace.
const KINDS: Array[String] = [
	KIND_ALLIANCE,
	KIND_OVERTURE,
	KIND_FTP,
	KIND_REVOKE_FTP,
	KIND_BOYCOTT,
	KIND_REVOKE_BOYCOTT,
	KIND_AID,
	KIND_SUBSIDY,
	KIND_CANCEL_SUBSIDY,
	KIND_BREAK,
	KIND_BREAK_NAP,
]

## What a friendly order costs the giver: aid drains the treasury, a subsidy
## buys the target's goods dearer, a pact costs nothing in pounds.
const AID_UTILITY_COST: int = 25
const SUBSIDY_UTILITY_COST: int = 20
const FTP_UTILITY_COST: int = 10
## One step per turn: the wiki default aid amount and opening subsidy.
const AID_AMOUNT: int = DiplomacyCatalog.GRANT_AID_STEP
const SUBSIDY_PERCENT: int = DiplomacyCatalog.SUBSIDY_MIN
## Aid stops once the standing can carry a trade pact: money no longer buys
## goodwill, and a court does not gift its treasury forever.
const AID_MAX_RELATION: float = DiplomacyCatalog.FTP_MIN_SCORE
## Retaliation bands: measures are aimed below the equilibrium and lifted once
## the standing recovers past the pact bar.
const BOYCOTT_MAX_RELATION: float = 45.0
const BOYCOTT_UTILITY_BASE: int = 55
const REVOKE_MAX_RELATION: float = 35.0
const RECOVERED_RELATION: float = 60.0
const REVOKE_UTILITY_COST: int = 15
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

## Highest-utility peaceful candidate for one court, or a blocked explanation
## the turn trace can print. `context` carries the planner read model:
## "treasury" and "tech" maps by faction plus the human court id.
static func best(
	config: AiConfig,
	state: DiplomacyState,
	ai_state: AiState,
	world: WorldMap,
	turn: int,
	target: int,
	desire: int,
	context: Dictionary
) -> Dictionary:
	var entries: Array[Dictionary] = candidates(
		config, state, ai_state, world, turn, target, desire, context
	)
	var winner: Dictionary = {}
	for entry: Dictionary in entries:
		if not bool(entry.get("ok", false)):
			continue
		if winner.is_empty() or int(entry["utility"]) > int(winner["utility"]):
			winner = entry
	if winner.is_empty():
		return {
			"ok": false,
			"blocked": _blocked_reason(entries),
			"candidates": entries,
		}
	winner = winner.duplicate()
	# Every candidate and its refusal travel with the winner, so a turn trace
	# can explain what the court passed over (wiki: turn-trace-interpretation).
	winner["candidates"] = entries
	return winner


## One candidate per order type this court could put to `target`, legal ones
## flagged `ok` and illegal ones carrying the reason they were refused.
static func candidates(
	config: AiConfig,
	state: DiplomacyState,
	ai_state: AiState,
	world: WorldMap,
	turn: int,
	target: int,
	desire: int,
	context: Dictionary
) -> Array[Dictionary]:
	var faction: int = config.faction
	var record: DiplomacyRelation = state.relation(faction, target)
	if record == null:
		return []
	# A rival never opens a second front while the court has a proposal waiting.
	if target == int(context.get("player", -1)) and DiplomacyProposals.has_pending(
		state, target
	):
		return [_blocked("the court is already considering a proposal")]
	var improve: int = 100 - desire
	var min_improve: int = config.parameter("diplomacy.improve_min_desire")
	var treasury: int = int((context.get("treasury", {}) as Dictionary).get(faction, 0))
	var tech: Dictionary = (context.get("tech", {}) as Dictionary).get(faction, {})
	var charts: CourtCharts = context.get("charts", null)
	var income: Dictionary = context.get("income", {})
	var saving: String = AiIncome.saving_reason(income)
	var gift: String = AiIncome.saving_reason(income, AID_AMOUNT)
	return [
		AiDiplomacyTreaties.best(
			config, state, ai_state, world, turn, target, improve, min_improve,
			treasury, tech, context
		),
		_trade_pact(config, state, faction, target, desire, improve, min_improve, record.score),
		_aid(state, faction, target, improve, min_improve, treasury, record.score, gift),
		_subsidy(config, state, faction, target, desire, improve, min_improve, saving),
		_boycott(state, faction, target, record.score, improve),
		_break_alliance(state, faction, target, record, desire),
		_break_nap(
			config, state, world, ai_state, turn, faction, target, record, desire, context
		),
	]


## A favoured trading pact while the standing is warm; the way back out once it
## has cooled below the pact bar (wiki: world-market § FTP). An agenda that keeps
## to itself values the same pact less, so the court stays on the overture chain
## (wiki: hidden-agendas — isolationist minimal trade; DR-20261111-27).
static func _trade_pact(
	config: AiConfig,
	state: DiplomacyState,
	faction: int,
	target: int,
	desire: int,
	improve: int,
	min_improve: int,
	relation: float
) -> Dictionary:
	if DiplomacyTrade.is_ftp(state, faction, target):
		if relation > REVOKE_MAX_RELATION:
			return _blocked("the trade pact still matches the standing", KIND_REVOKE_FTP)
		var revoke: Dictionary = DiplomacyTrade.can_revoke_ftp(state, faction, target)
		if not bool(revoke.get("ok", false)):
			return _blocked(String(revoke.get("reason", "no trade order")), KIND_REVOKE_FTP)
		return _offer(KIND_REVOKE_FTP, target, desire - REVOKE_UTILITY_COST)
	if improve < min_improve or relation < DiplomacyCatalog.FTP_MIN_SCORE:
		return _blocked("the court is not warm enough for a trade pact", KIND_FTP)
	var check: Dictionary = DiplomacyTrade.can_establish_ftp(state, faction, target)
	if not bool(check.get("ok", false)):
		return _blocked(String(check.get("reason", "no trade pact")), KIND_FTP)
	return _offer(KIND_FTP, target, improve - FTP_UTILITY_COST + config.trade_bias())


## One gift of gold: only to a court this one wants to keep close, while its own
## purse covers the step and keeps the reserve it is saving (diplomacy § GP–Minor
## Rules; issue #484).
static func _aid(
	state: DiplomacyState,
	faction: int,
	target: int,
	improve: int,
	min_improve: int,
	treasury: int,
	relation: float, saving: String = ""
) -> Dictionary:
	if not saving.is_empty():
		return _blocked(saving, KIND_AID)
	if improve < min_improve:
		return _blocked("aid is spent only on friends", KIND_AID)
	if relation >= AID_MAX_RELATION:
		return _blocked("the standing no longer needs gifts", KIND_AID)
	var check: Dictionary = DiplomacyAid.can_grant_aid(
		state, faction, target, AID_AMOUNT, treasury
	)
	if not bool(check.get("ok", false)):
		return _blocked(String(check.get("reason", "no aid")), KIND_AID)
	var entry: Dictionary = _offer(KIND_AID, target, improve - AID_UTILITY_COST)
	entry["amount"] = AID_AMOUNT
	return entry


## A subsidy to a Minor or Tribe while the friendship holds; cancelled once the
## court stops wanting it (wiki: world-market § Subsidy price adjustment). An
## agenda that keeps to itself values it as little as a pact; a saver sets none (#580).
static func _subsidy(
	config: AiConfig,
	state: DiplomacyState,
	faction: int,
	target: int,
	desire: int,
	improve: int,
	min_improve: int, saving: String = ""
) -> Dictionary:
	if state.subsidy(faction, target) > 0:
		if improve >= min_improve:
			return _blocked("the subsidy still buys goodwill", KIND_CANCEL_SUBSIDY)
		return _offer(KIND_CANCEL_SUBSIDY, target, desire - SUBSIDY_UTILITY_COST)
	if not saving.is_empty():
		return _blocked(saving, KIND_SUBSIDY)
	if improve < min_improve:
		return _blocked("subsidies are for friends", KIND_SUBSIDY)
	var check: Dictionary = DiplomacyAid.can_set_subsidy(
		state, faction, target, SUBSIDY_PERCENT
	)
	if not bool(check.get("ok", false)):
		return _blocked(String(check.get("reason", "no subsidy")), KIND_SUBSIDY)
	var entry: Dictionary = _offer(
		KIND_SUBSIDY, target, improve - SUBSIDY_UTILITY_COST + config.trade_bias()
	)
	entry["amount"] = SUBSIDY_PERCENT
	return entry


## A colonial boycott of a court this one has fallen out with, lifted once the
## standing recovers (wiki: diplomacy § GP–Tribe — Boycott).
static func _boycott(
	state: DiplomacyState, faction: int, target: int, relation: float, improve: int
) -> Dictionary:
	if DiplomacyTrade.is_boycotting(state, faction, target):
		if relation < RECOVERED_RELATION:
			return _blocked("the standing has not recovered", KIND_REVOKE_BOYCOTT)
		var revoke: Dictionary = DiplomacyTrade.can_revoke_boycott(state, faction, target)
		if not bool(revoke.get("ok", false)):
			return _blocked(String(revoke.get("reason", "no boycott order")), KIND_REVOKE_BOYCOTT)
		return _offer(KIND_REVOKE_BOYCOTT, target, improve - FTP_UTILITY_COST)
	if relation > BOYCOTT_MAX_RELATION:
		return _blocked("relations are not cold enough for a boycott", KIND_BOYCOTT)
	var check: Dictionary = DiplomacyTrade.can_boycott(state, faction, target)
	if not bool(check.get("ok", false)):
		return _blocked(String(check.get("reason", "no boycott")), KIND_BOYCOTT)
	return _offer(
		KIND_BOYCOTT,
		target,
		clampi(int(roundf(float(BOYCOTT_UTILITY_BASE) - relation)), 5, BOYCOTT_UTILITY_BASE),
	)


## A treaty the court no longer means to honour is dissolved before it costs
## more than the standing it was signed on (wiki: diplomacy § Breaking an
## alliance). While the pact stands, one Break NAP clears pact and alliance
## together, so the alliance-only break would be a wasted turn (issue #752).
static func _break_alliance(
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
## (issues #724, #752).
static func _break_nap(
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
	if ai_state.war_on_cooldown(
		faction, target, turn, config.parameter("diplomacy.war_cooldown_turns")
	):
		return _blocked("the pair is on its war cooldown", KIND_BREAK_NAP)
	# A pact break to open a new front while the court is already fighting is
	# how crowns drown: the ban stands until this court is at peace elsewhere
	# (wiki: diplomacy § Breaking a pact; issue #752).
	for other: DiplomacyRelation in state.relations_of(faction):
		if other.at_war:
			return _blocked("the court is at war on another front", KIND_BREAK_NAP)
	var colony: Dictionary = AiTribeColony.ambition(
		state, world, context.get("charts", null), faction, target,
		int((context.get("treasury", {}) as Dictionary).get(faction, 0)),
		(context.get("tech", {}) as Dictionary).get(faction, {})
	)
	if bool(colony.get("wanted", false)) or bool(colony.get("held", false)):
		return _blocked("an envoy chain has a claim on that court", KIND_BREAK_NAP)
	var posture: String = AiPhasePlanner.phase_for(config, state)
	if (
		FactionCatalog.type_of(target) == FactionCatalog.Type.GREAT_POWER
		and not AiPhasePlanner.opens(posture, AiPhasePlanner.SLOT_DECLARE_WAR)
		and not _outmatches(faction, target, context)
	):
		return _blocked("overstretched: no third front", KIND_BREAK_NAP)
	return _offer(KIND_BREAK_NAP, target, desire - BREAK_NAP_UTILITY_COST)


## Whether this court is the stronger of the pair on the published power score —
## the same read the planner's war gate applies (DR-20261114-11).
static func _outmatches(faction: int, target: int, context: Dictionary) -> bool:
	var powers: Dictionary = context.get("power", {})
	if not powers.has(faction) or not powers.has(target):
		return true
	return int(powers[faction]) > int(powers[target])


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


static func _blocked_reason(entries: Array[Dictionary]) -> String:
	for entry: Dictionary in entries:
		var reason: String = String(entry.get("blocked", ""))
		if not reason.is_empty() and reason != "no legal treaty":
			return reason
	return "no legal treaty"
