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
	return [
		_treaty(
			config, state, ai_state, world, turn, target, improve, min_improve,
			treasury, tech
		),
		_trade_pact(state, faction, target, desire, improve, min_improve, record.score),
		_aid(state, faction, target, improve, min_improve, treasury, record.score),
		_subsidy(state, faction, target, desire, improve, min_improve),
		_boycott(state, faction, target, record.score, improve),
		_break_alliance(target, record, desire),
	]


## The next free overture, or a formal alliance once the pair is Allied. The
## proposing court pays its own stage cost, so the treasury read is its own.
static func _treaty(
	config: AiConfig,
	state: DiplomacyState,
	ai_state: AiState,
	world: WorldMap,
	turn: int,
	target: int,
	improve: int,
	min_improve: int,
	treasury: int,
	tech: Dictionary
) -> Dictionary:
	if improve < min_improve:
		return _blocked("improve-relations desire too low", KIND_OVERTURE)
	var cooldown: int = config.parameter("diplomacy.overture_cooldown_turns")
	if ai_state.overture_on_cooldown(config.faction, target, turn, cooldown):
		return _blocked("overture cooldown", KIND_OVERTURE)
	var best_entry: Dictionary = {}
	var record: DiplomacyRelation = state.relation(config.faction, target)
	if record != null and record.score >= DiplomacyCatalog.ALLIANCE_CLAMP:
		var alliance: Dictionary = DiplomacyRules.can_form_alliance(
			state, config.faction, target
		)
		if bool(alliance.get("ok", false)):
			best_entry = _offer(
				KIND_ALLIANCE,
				target,
				improve + int(config.agenda_traits.get("alliance_bias", 0)),
			)
	var next: String = DiplomacyCatalog.next_stage(state.overture(config.faction, target))
	if not next.is_empty():
		var check: Dictionary = DiplomacyRules.can_establish_overture(
			state, world, config.faction, target, next, treasury, tech
		)
		if bool(check.get("ok", false)) and (
			best_entry.is_empty() or improve > int(best_entry["utility"])
		):
			best_entry = _offer(KIND_OVERTURE, target, improve)
			best_entry["stage"] = next
	if best_entry.is_empty():
		return _blocked("no legal treaty", KIND_OVERTURE)
	return best_entry


## A favoured trading pact while the standing is warm; the way back out once it
## has cooled below the pact bar (wiki: world-market § FTP).
static func _trade_pact(
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
	return _offer(KIND_FTP, target, improve - FTP_UTILITY_COST)


## One gift of gold: only to a court this one wants to keep close, and only
## while its own treasury covers the step (wiki: diplomacy § GP–Minor Rules).
static func _aid(
	state: DiplomacyState,
	faction: int,
	target: int,
	improve: int,
	min_improve: int,
	treasury: int,
	relation: float
) -> Dictionary:
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
## court stops wanting it (wiki: world-market § Subsidy price adjustment).
static func _subsidy(
	state: DiplomacyState,
	faction: int,
	target: int,
	desire: int,
	improve: int,
	min_improve: int
) -> Dictionary:
	if state.subsidy(faction, target) > 0:
		if improve >= min_improve:
			return _blocked("the subsidy still buys goodwill", KIND_CANCEL_SUBSIDY)
		return _offer(KIND_CANCEL_SUBSIDY, target, desire - SUBSIDY_UTILITY_COST)
	if improve < min_improve:
		return _blocked("subsidies are for friends", KIND_SUBSIDY)
	var check: Dictionary = DiplomacyAid.can_set_subsidy(
		state, faction, target, SUBSIDY_PERCENT
	)
	if not bool(check.get("ok", false)):
		return _blocked(String(check.get("reason", "no subsidy")), KIND_SUBSIDY)
	var entry: Dictionary = _offer(KIND_SUBSIDY, target, improve - SUBSIDY_UTILITY_COST)
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
## alliance).
static func _break_alliance(
	target: int, record: DiplomacyRelation, desire: int
) -> Dictionary:
	if record == null or not record.formal_alliance:
		return _blocked("no formal alliance stands", KIND_BREAK)
	if desire < BREAK_MIN_DESIRE:
		return _blocked("the alliance still serves", KIND_BREAK)
	return _offer(KIND_BREAK, target, desire - BREAK_UTILITY_COST)


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
