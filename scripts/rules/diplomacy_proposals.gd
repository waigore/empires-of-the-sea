class_name DiplomacyProposals
extends RefCounted
## Rival court proposals to the human court (wiki: diplomacy § Court proposals;
## DR-20261109-06). A proposal is queued, never applied: the diplomacy phase
## suspends and the court answers Accept or Refuse. Only one rival proposal may
## wait at a time, the proposing rival pays, and refusal changes no relation
## score. Pure rules, no node deps (REQ-P3-03).

const KIND_ACCEPT: String = "proposal_accept"
const KIND_REFUSE: String = "proposal_refuse"

const OFFER_ALLIANCE: String = "alliance"
const OFFER_OVERTURE: String = "overture"


static func has_pending(state: DiplomacyState, court: int) -> bool:
	return not pending_for(state, court).is_empty()


static func pending_for(state: DiplomacyState, court: int) -> Dictionary:
	if state == null:
		return {}
	for offer: Dictionary in state.pending_proposals:
		if int(offer.get("to", -1)) == court:
			return offer
	return {}


## Queues a rival's proposal for the human court. At most one waits at a time;
## the offer is validated against the shared relation rules, never applied.
static func offer(
	state: DiplomacyState, from_id: int, to_id: int, offer_kind: String, stage: String = ""
) -> Dictionary:
	if state == null:
		return _deny("No court to propose to.")
	if from_id == to_id:
		return _deny("A crown cannot treat with itself.")
	if (
		FactionCatalog.type_of(from_id) != FactionCatalog.Type.GREAT_POWER
		or FactionCatalog.type_of(to_id) != FactionCatalog.Type.GREAT_POWER
	):
		return _deny("Only Great Powers exchange proposals.")
	if to_id != state.human_faction:
		return _deny("Proposals go to the human court only.")
	if not state.pending_proposals.is_empty():
		return _deny("Another proposal already waits on the court.")
	var record: DiplomacyRelation = state.relation(from_id, to_id)
	if record == null or record.at_war:
		return _deny("No proposal can be made while at war.")
	match offer_kind:
		OFFER_ALLIANCE:
			if record.formal_alliance:
				return _deny("A formal alliance already binds us.")
			stage = ""
		OFFER_OVERTURE:
			if (
				stage.is_empty()
				or not DiplomacyCatalog.knows_stage(stage)
				or stage == DiplomacyCatalog.STAGE_NONE
				or DiplomacyCatalog.stage_cost(stage) > 0
			):
				return _deny("Rivals offer only cost-free overture stages.")
		_:
			return _deny("Unknown proposal.")
	state.pending_proposals.append(
		{"from": from_id, "to": to_id, "offer": offer_kind, "stage": stage}
	)
	state.record_event("proposalOffered", from_id, to_id, {"offer": offer_kind, "stage": stage})
	return {
		"ok": true,
		"reason": "",
		"message": "%s proposes %s." % [
			FactionCatalog.name_of(from_id), offer_label({"offer": offer_kind, "stage": stage})
		],
	}


## Applies the human court's answer to the waiting proposal. Accepting runs the
## shared alliance / overture acceptance; the proposing rival pays. The
## improve-relations cooldown starts when the court answers, accept or refuse.
static func resolve_human(
	state: DiplomacyState, ai_state: AiState, accept: bool
) -> Dictionary:
	if state == null:
		return {"ok": false, "reason": "No court to answer for."}
	var offer: Dictionary = _take_pending(state, state.human_faction)
	if offer.is_empty():
		return {"ok": false, "reason": "No proposal awaits an answer."}
	var proposer: int = int(offer["from"])
	var human: int = int(offer["to"])
	if ai_state != null:
		ai_state.note_overture(proposer, human, state.turn)
	if not accept:
		state.record_event(
			"proposalRefused", proposer, human,
			{"offer": String(offer["offer"]), "stage": String(offer.get("stage", ""))}
		)
		return {
			"ok": true,
			"accepted": false,
			"from": proposer,
			"offer": String(offer["offer"]),
			"message": "%s's proposal is refused." % FactionCatalog.name_of(proposer),
		}
	if String(offer["offer"]) == OFFER_ALLIANCE:
		var sealed: Dictionary = DiplomacyRules.form_alliance(state, proposer, human)
		return {
			"ok": true,
			"accepted": bool(sealed.get("accepted", false)),
			"from": proposer,
			"offer": OFFER_ALLIANCE,
			"message": String(sealed.get("message", "")),
		}
	var stage: String = String(offer.get("stage", ""))
	var advanced: Dictionary = DiplomacyRules.advance_overture(state, proposer, human, stage)
	return {
		"ok": true,
		"accepted": bool(advanced.get("accepted", false)),
		"from": proposer,
		"offer": OFFER_OVERTURE,
		"stage": stage,
		"message": "We accept %s's %s." % [
			FactionCatalog.name_of(proposer), DiplomacyCatalog.stage_label(stage)
		],
	}


## Human-readable form of a queued offer, shared by the court panel and toasts.
static func offer_label(offer: Dictionary) -> String:
	if String(offer.get("offer", "")) == OFFER_ALLIANCE:
		return "a formal alliance"
	return "a %s" % DiplomacyCatalog.stage_label(String(offer.get("stage", "")))


static func _take_pending(state: DiplomacyState, court: int) -> Dictionary:
	for index in state.pending_proposals.size():
		var offer: Dictionary = state.pending_proposals[index]
		if int(offer.get("to", -1)) == court:
			state.pending_proposals.remove_at(index)
			return offer
	return {}


static func _deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "message": ""}