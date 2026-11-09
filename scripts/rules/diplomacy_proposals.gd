class_name DiplomacyProposals
extends RefCounted
## Rival proposals that need the human court's answer: an alliance offer, the
## next overture in the chain, or a white peace (wiki: diplomacy § GP AI policy
## — the AI never resolves a decision the human must make). Pure rules: state
## in, answer out; the turn resolver and the court panel share this module
## (REQ-P3-03).

const KIND_ALLIANCE: String = "alliance"
const KIND_OVERTURE: String = "overture"
const KIND_PEACE: String = "peace"
const KIND_ACCEPT: String = "accept_offer"
const KIND_REFUSE: String = "refuse_offer"


## Queues one proposal from a rival court. Only free overture stages can be
## offered while rival treasuries stay untracked, so a Consulate/Embassy/Join
## Empire offer waits for the AI economy. A white-peace proposal is legal only
## while the pair is at war (wiki: diplomacy § Court proposals).
static func queue(
	state: DiplomacyState, world: WorldMap, from_id: int, kind: String, stage: String = ""
) -> Dictionary:
	if state == null:
		return _deny("No court is open.")
	var human: int = state.human_faction
	if from_id == human:
		return _deny("A court cannot propose to itself.")
	if FactionCatalog.type_of(from_id) != FactionCatalog.Type.GREAT_POWER:
		return _deny("Only a Great Power keeps a court to treat with.")
	if has_pending(state, human):
		return _deny("The court already has a proposal to answer.")
	if not state.has_relation(from_id, human):
		return _deny("No envoy has reached that court.")
	var check: Dictionary
	match kind:
		KIND_ALLIANCE:
			check = DiplomacyRules.can_form_alliance(state, from_id, human)
		KIND_OVERTURE:
			if stage.is_empty():
				return _deny("An overture needs a stage.")
			check = DiplomacyRules.can_establish_overture(
				state, world, from_id, human, stage, 0, {}
			)
		KIND_PEACE:
			check = DiplomacyRules.can_make_peace(state, from_id, human)
		_:
			return _deny("Unknown proposal.")
	if not bool(check.get("ok", false)):
		return check
	state.pending_offers.append({"from": from_id, "kind": kind, "stage": stage})
	state.record_event("proposalMade", from_id, human, {"kind": kind, "stage": stage})
	return {"ok": true, "reason": "", "from": from_id, "kind": kind, "stage": stage}


static func has_pending(state: DiplomacyState, human: int) -> bool:
	return not pending_for(state, human).is_empty()


## Oldest unanswered proposal for the court.
static func pending_for(state: DiplomacyState, human: int) -> Dictionary:
	if state == null:
		return {}
	for offer: Dictionary in state.pending_offers:
		if int(offer.get("from", -1)) != human:
			return offer
	return {}


static func take_pending(state: DiplomacyState, human: int) -> Dictionary:
	if state == null:
		return {}
	for index in state.pending_offers.size():
		var offer: Dictionary = state.pending_offers[index]
		if int(offer.get("from", -1)) != human:
			state.pending_offers.remove_at(index)
			return offer
	return {}


## Applies the court's answer through the shared diplomacy rules. The proposing
## rival pays its own costs; the human treasury is never charged for accepting.
static func resolve_human(
	state: DiplomacyState, world: WorldMap, accept: bool
) -> Dictionary:
	if state == null:
		return _deny("No court to answer for.")
	var offer: Dictionary = take_pending(state, state.human_faction)
	if offer.is_empty():
		return _deny("No proposal awaits an answer.")
	var from_id: int = int(offer["from"])
	var kind: String = String(offer["kind"])
	var stage: String = String(offer.get("stage", ""))
	var decision: String = (
		DiplomacyRules.DECISION_ACCEPT if accept else DiplomacyRules.DECISION_REFUSE
	)
	var result: Dictionary
	if kind == KIND_ALLIANCE:
		result = DiplomacyRules.form_alliance(state, from_id, state.human_faction, decision)
	elif kind == KIND_OVERTURE:
		result = DiplomacyRules.establish_overture(
			state, null, world, from_id, state.human_faction, stage, {}, decision
		)
	elif kind == KIND_PEACE:
		# The human answers the rival's offer; a refusal leaves the war and the
		# relation score untouched (wiki: diplomacy § GP–GP Rules — peace needs
		# both sides).
		result = DiplomacyRules.make_peace(
			state, state.human_faction, from_id, decision
		)
		if bool(result.get("ok", false)) and not bool(result.get("accepted", true)):
			result["message"] = (
				"The white peace with %s is refused." % FactionCatalog.name_of(from_id)
			)
	else:
		return _deny("Unknown proposal.")
	if bool(result.get("ok", false)):
		state.record_event(
			"proposalAccepted" if accept else "proposalRefused",
			from_id,
			state.human_faction,
			{"kind": kind, "stage": stage}
		)
	result["from"] = from_id
	result["kind"] = kind
	result["stage"] = stage
	return result


## Player-facing phrase: "a formal alliance" / "the Non-Aggression Pact" /
## "a white peace".
static func describe(kind: String, stage: String) -> String:
	if kind == KIND_ALLIANCE:
		return "a formal alliance"
	if kind == KIND_PEACE:
		return "a white peace"
	return "the %s" % DiplomacyCatalog.stage_label(stage)


static func _deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
