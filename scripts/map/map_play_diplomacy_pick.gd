class_name MapPlayDiplomacyPick
extends RefCounted
## What the court's own envoy would do with her one diplomacy order this turn,
## crown by crown (wiki: diplomacy § GP AI policy for war vs. relations,
## diplomacy-planner; DR-20261121-05).
##
## The plan is not a second opinion: it is `AiDiplomacyPlanner.decide`, the call
## the rival pass books every court's order from, asked for this crown on her own
## relations, purse and footing — so the advice and the pass cannot disagree
## (REQ-P2-03). The read it decides with is `AiTurnRead.court`, the same read the
## pass builds, over the crown's own ledger (bound with the Auto seat's own call,
## `MapPlayAuto.ensure_seat_ledger`), so a gate that prices the purse prices the
## one the crown holds.
##
## A reading only: nothing here declares, offers, gifts, boycotts or signs, and
## the crown still presses her own order (REQ-P3-03, REQ-P5-06).

## The envoy's one order is for this crown.
const KIND_ORDER: String = "order"
## The envoy's one order is spent on another crown this turn.
const KIND_ELSEWHERE: String = "elsewhere"
## The envoy has nothing to say to this crown.
const KIND_HOLD: String = "hold"


## The court's own decision this turn: the planner's plan, or {} when the court
## runs no planner, the campaign is decided, or the session holds no relations
## to weigh.
static func plan(play: PlaySession) -> Dictionary:
	if not MapPlayPickProse.crown_ready(play):
		return {}
	if play.diplomacy == null or play.world == null:
		return {}
	var court_read: Dictionary = court(play, play.player_faction)
	if court_read.is_empty():
		return {}
	return AiDiplomacyPlanner.decide(
		court_read["config"], play.diplomacy, play.ensure_ai(), play.world, play.turn,
		court_read["read"]
	)


## The read the crown's own decision is made with: `AiTurnRead.court` over its
## own purse and studies, plus the config the seed and the bound temperament gave
## it. {} when the court runs no planner or owns no ledger.
static func court(play: PlaySession, faction: int) -> Dictionary:
	if play == null or play.diplomacy == null or play.world == null:
		return {}
	var opened: Dictionary = AiControl.court(play, faction)
	if opened.is_empty():
		return {}
	var config: Variant = opened["config"]
	if not (config is AiConfig):
		return {}
	var shared: Dictionary = _shared(play, faction)
	if shared.is_empty():
		return {}
	var read: Dictionary = AiTurnRead.court(
		play.diplomacy, play.world, play.ensure_ai(), faction, shared, config
	)
	if read.is_empty():
		return {}
	read["config"] = config
	return read


## One pick per crown the court is in contact with: target -> the pick itself,
## its `kind` naming whether the envoy's one order is bound for that crown
## (`KIND_ORDER`), spent elsewhere, or held by a gate. The sheet prints the
## sentence and marks the row from the same read (DR-20261121-05,
## DR-20261122-11). Empty when the court would give the turn no order and can
## weigh none, or when the session has no planner to read.
static func picks(play: PlaySession) -> Dictionary:
	var plan_now: Dictionary = plan(play)
	if plan_now.is_empty():
		return {}
	var action: Dictionary = plan_now.get("action", {}) as Dictionary
	var chosen: int = int(action.get("target", MapModel.NO_ID))
	var out: Dictionary = {}
	for record: DiplomacyRelation in play.diplomacy.relations_of(play.player_faction):
		var target: int = record.other(play.player_faction)
		var pick: Dictionary = of(action, chosen, plan_now, target)
		if not String(pick.get("line", "")).is_empty():
			out[target] = pick
	return out


## The pick for one crown, as the sheet reads it: `{kind, order, target, other,
## why, line}`. Empty when the court has no envoy reading for it.
static func pick(play: PlaySession, target: int) -> Dictionary:
	var plan_now: Dictionary = plan(play)
	if plan_now.is_empty():
		return {}
	var action: Dictionary = plan_now.get("action", {}) as Dictionary
	return of(action, int(action.get("target", MapModel.NO_ID)), plan_now, target)


## The court sheet's line for one crown, or "" when there is none to print.
static func line(play: PlaySession, target: int) -> String:
	return MapPlayPickProse.sentence_of(pick(play, target))


## One crown's reading off the court's plan: the order if the envoy is bound for
## this crown, where the order went if it is bound elsewhere, else the gate the
## planner named for this crown. Pure — a plan in, a reading out — so a sheet
## and a suite could drive it without a session.
static func of(
	action: Dictionary, chosen: int, plan_now: Dictionary, target: int
) -> Dictionary:
	if not action.is_empty():
		if chosen == target:
			var kind: String = String(action.get("kind", ""))
			var order: String = MapPlayDiplomacyPickWords.order_line(kind, target, action)
			if order.is_empty():
				return {}
			return _worded(KIND_ORDER, kind, target, target, "", order, action)
		var other: String = MapPlayDiplomacyPickWords.elsewhere_line(target, chosen)
		if other.is_empty():
			return {}
		return _worded(KIND_ELSEWHERE, "", target, chosen, "", other)
	var why: String = _blocked(plan_now, target)
	return _worded(
		KIND_HOLD, "", target, MapModel.NO_ID, why,
		MapPlayDiplomacyPickWords.hold_line(target, why)
	)


## The gate the planner named for this crown, in its own words: the candidate
## row the pass scores it on. A row that was legal but lost the one order names
## no gate, and the sheet says so plainly rather than inventing one.
static func _blocked(plan_now: Dictionary, target: int) -> String:
	for raw: Variant in plan_now.get("candidates", []):
		if not (raw is Dictionary):
			continue
		var entry: Dictionary = raw
		if int(entry.get("target", MapModel.NO_ID)) != target:
			continue
		return String(entry.get("blocked", ""))
	return ""


## The shared docket as the crown's own court reads it: every rival's published
## order of battle, the pass's charts, and the crown's real purse and studies.
static func _shared(play: PlaySession, faction: int) -> Dictionary:
	var economy: PlayerEconomy = play.ledger_for(faction)
	if economy == null:
		return {}
	# The planners price one ledger per court; for the crown that is its own real
	# ledger, exactly as the Auto seat binds it (wiki: ai-architecture
	# § Provisioning; REQ-P2-03).
	MapPlayAuto.ensure_seat_ledger(play)
	var ai_state: AiState = play.ensure_ai()
	var shared: Dictionary = AiTurnRead.context(
		play.world, MapPlayDiplomacyAi.context(play), faction
	)
	AiTurnRead.stamp_ledgers(shared, ai_state, faction)
	# The pass keeps the crown out of its stamped dockets; the crown's own read
	# takes the purse and the studies the court actually holds.
	var treasury: Dictionary = shared.get("treasury", {}) as Dictionary
	var tech: Dictionary = shared.get("tech", {}) as Dictionary
	treasury[faction] = economy.treasury
	tech[faction] = economy.tech_unlocked
	shared["profiles"] = ai_state.profiles
	return shared


static func _worded(
	kind: String, order: String, target: int, other: int, why: String, line: String,
	action: Dictionary = {}
) -> Dictionary:
	if line.is_empty():
		return {}
	var pick: Dictionary = {
		"kind": kind,
		"order": order,
		"target": target,
		"other": other,
		"why": why,
		"line": line,
	}
	# The press the sheet marks reads the action's own arguments, so the mark and
	# the gold line come off one read (DR-20261123-01).
	if not action.is_empty():
		pick["stage"] = String(action.get("stage", ""))
		pick["amount"] = int(action.get("amount", 0))
	return pick


## The press the gold line names, keyed the way THE COURT's order list keys its
## own buttons: `{kind, arg}`, the order catalogue's kind and the argument that
## list prints beside it — an overture's stage, a subsidy's percent. {} when the
## line names no press: another court's order, a gate, a hold, or a kind whose
## row is the crown's own sum (a gift steps its face, so the line names the sum
## and the press stays plain) (wiki: diplomacy § The crown's own envoy;
## DR-20261123-01).
static func press(pick: Dictionary) -> Dictionary:
	if String(pick.get("kind", "")) != KIND_ORDER:
		return {}
	var order: String = String(pick.get("order", ""))
	if order.is_empty():
		return {}
	var arg: String = ""
	match order:
		DiplomacyOrders.KIND_OVERTURE:
			arg = String(pick.get("stage", ""))
		DiplomacyOrders.KIND_SUBSIDY:
			arg = str(int(pick.get("amount", 0)))
		DiplomacyOrders.KIND_AID:
			return {}
	if order == DiplomacyOrders.KIND_OVERTURE and arg.is_empty():
		return {}
	if order == DiplomacyOrders.KIND_SUBSIDY and arg == "0":
		return {}
	return {"kind": order, "arg": arg}
