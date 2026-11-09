class_name CallToArms
extends RefCounted
## Mutual defence: when a Great Power declares war on another Great Power, each
## other court holding a formal alliance with the declared-upon court at the end
## of the preceding turn is called to arms once (wiki: diplomacy § Alliances).
## AI allies answer by their relation with the defender; the human court's call
## waits for a consent decision. Pure rules, no node deps (REQ-P3-03).

const KIND_JOIN: String = "call_to_arms_join"
const KIND_REFUSE: String = "call_to_arms_refuse"


## Queues or resolves one call per eligible ally. Returns player-facing lines.
static func on_war_declared(
	state: DiplomacyState, aggressor: int, defender: int
) -> Array[String]:
	var messages: Array[String] = []
	if state == null:
		return messages
	if not _both_great_powers(aggressor, defender):
		return messages
	for ally: int in candidates(state, aggressor, defender):
		if ally == state.human_faction:
			if queue_human_call(state, aggressor, defender, ally):
				messages.append(
					"%s calls on our alliance against %s."
					% [FactionCatalog.name_of(defender), FactionCatalog.name_of(aggressor)]
				)
			continue
		var join: bool = ai_joins(state, ally, defender)
		var message: String = _resolve(state, ally, aggressor, defender, join)
		if not message.is_empty():
			messages.append(message)
	return messages


## Courts bound to the defender by a formal alliance at the close of the
## preceding turn, at peace with the defender and not already at war with the
## aggressor. The informal Allied band alone never triggers a call.
static func candidates(state: DiplomacyState, aggressor: int, defender: int) -> Array[int]:
	var result: Array[int] = []
	for gp: int in FactionCatalog.great_power_ids():
		if gp == aggressor or gp == defender:
			continue
		if not allied_in_snapshot(state, gp, defender):
			continue
		var with_defender: DiplomacyRelation = state.relation(gp, defender)
		if with_defender == null or with_defender.at_war:
			continue
		var with_aggressor: DiplomacyRelation = state.relation(gp, aggressor)
		if with_aggressor == null or with_aggressor.at_war:
			continue
		result.append(gp)
	return result


## AI allies join while their relation with the defended ally holds at 50+
## (DiplomacyCatalog.ALLY_DEFENCE_MIN_SCORE).
static func ai_joins(state: DiplomacyState, ally: int, defender: int) -> bool:
	var record: DiplomacyRelation = state.relation(ally, defender)
	return record != null and record.score >= DiplomacyCatalog.ALLY_DEFENCE_MIN_SCORE


static func has_pending(state: DiplomacyState, human: int) -> bool:
	return state != null and not pending_call_for(state, human).is_empty()


## Freezes the formal alliances of the closing turn; calls read only this map.
static func freeze_alliances(state: DiplomacyState) -> void:
	state.alliance_snapshot.clear()
	for key: String in state.relations.keys():
		var record: DiplomacyRelation = state.relations[key]
		if record != null and record.formal_alliance and not record.at_war:
			state.alliance_snapshot[key] = true


static func allied_in_snapshot(state: DiplomacyState, a: int, b: int) -> bool:
	return state.alliance_snapshot.has(state.pair_key(a, b))


static func pending_call_for(state: DiplomacyState, ally: int) -> Dictionary:
	for call: Dictionary in state.pending_calls:
		if int(call.get("ally", -1)) == ally:
			return call
	return {}


## Queues exactly one call per aggressor–defender pair for the human court.
static func queue_human_call(
	state: DiplomacyState, aggressor: int, defender: int, ally: int
) -> bool:
	for call: Dictionary in state.pending_calls:
		if (
			int(call.get("ally", -1)) == ally
			and int(call.get("aggressor", -1)) == aggressor
			and int(call.get("defender", -1)) == defender
		):
			return false
	state.pending_calls.append({"aggressor": aggressor, "defender": defender, "ally": ally})
	state.record_event("callToArmsOffered", ally, defender, {"aggressor": aggressor})
	return true


## Removes and returns the oldest call waiting on `ally`.
static func take_pending_call(state: DiplomacyState, ally: int) -> Dictionary:
	for index in state.pending_calls.size():
		var call: Dictionary = state.pending_calls[index]
		if int(call.get("ally", -1)) == ally:
			state.pending_calls.remove_at(index)
			return call
	return {}


## Applies the human court's answer to the oldest pending call.
static func resolve_human(state: DiplomacyState, accept: bool) -> Dictionary:
	if state == null:
		return {"ok": false, "reason": "No court to answer for."}
	var call: Dictionary = take_pending_call(state, state.human_faction)
	if call.is_empty():
		return {"ok": false, "reason": "No call to arms awaits an answer."}
	var message: String = _resolve(
		state,
		state.human_faction,
		int(call["aggressor"]),
		int(call["defender"]),
		accept
	)
	return {
		"ok": true,
		"accepted": accept,
		"message": message,
		"aggressor": int(call["aggressor"]),
		"defender": int(call["defender"]),
	}


static func _resolve(
	state: DiplomacyState, ally: int, aggressor: int, defender: int, join: bool
) -> String:
	if join:
		return _join(state, ally, aggressor, defender)
	return _refuse(state, ally, aggressor, defender)


## Joining enters the war with the aggressor; its subsidies fall like any war's.
static func _join(state: DiplomacyState, ally: int, aggressor: int, defender: int) -> String:
	var war: Dictionary = DiplomacyRules.declare_war(state, ally, aggressor, false)
	if not bool(war.get("ok", false)):
		return ""
	state.touch(ally, defender, "callToArmsAccepted", {"aggressor": aggressor})
	return "%s answers the call to arms and joins the war against %s." % [
		FactionCatalog.name_of(ally), FactionCatalog.name_of(aggressor)
	]


## Refusing breaks the alliance with the unified penalty: −50 with the ally and
## −10 with every other Great Power except the ally and the aggressor.
static func _refuse(state: DiplomacyState, ally: int, aggressor: int, defender: int) -> String:
	var record: DiplomacyRelation = state.relation(ally, defender)
	if record != null:
		record.formal_alliance = false
	state.apply_delta(
		ally, defender, -DiplomacyCatalog.BREAK_ALLY_PENALTY, "allianceBroken",
		{"aggressor": aggressor, "call_to_arms": true}
	)
	for other: DiplomacyRelation in state.relations_of(ally):
		var peer: int = other.other(ally)
		if peer == defender or peer == aggressor:
			continue
		if FactionCatalog.type_of(peer) != FactionCatalog.Type.GREAT_POWER:
			continue
		state.apply_delta(
			ally, peer, -DiplomacyCatalog.BREAK_CASCADE_PENALTY, "allianceBreakCascade"
		)
	state.record_event("callToArmsRefused", ally, defender, {"aggressor": aggressor})
	return "%s refuses the call to arms; the alliance with %s is broken." % [
		FactionCatalog.name_of(ally), FactionCatalog.name_of(defender)
	]


static func _both_great_powers(a: int, b: int) -> bool:
	return (
		FactionCatalog.type_of(a) == FactionCatalog.Type.GREAT_POWER
		and FactionCatalog.type_of(b) == FactionCatalog.Type.GREAT_POWER
	)
