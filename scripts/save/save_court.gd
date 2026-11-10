class_name SaveCourt
extends RefCounted
## Save shape of the courts: the diplomacy ledger, the rival AI bookkeeping and
## the decided campaign. Kept out of SaveCodec so each save module owns one
## domain and stays inside the size bars (REQ-P3-01).


# --- diplomacy ---------------------------------------------------------------


static func capture_diplomacy(state: DiplomacyState) -> Dictionary:
	if state == null:
		return {}
	var records: Dictionary = {}
	for key: String in state.relations.keys():
		var record: DiplomacyRelation = state.relations[key]
		if record != null:
			records[key] = record.to_dict()
	return {
		"turn": state.turn,
		"relations": records,
		"overtures": state.overtures.duplicate(),
		"subsidies": state.subsidies.duplicate(),
		"ftps": state.ftps.duplicate(),
		"boycotts": state.boycotts.duplicate(),
		"colonies": state.colonies.duplicate(),
		"events": state.events.duplicate(true),
		"modified": state._modified.duplicate(),
		"order_counts": state._order_counts.duplicate(),
		"alliance_snapshot": state.alliance_snapshot.duplicate(),
		"pending_calls": state.pending_calls.duplicate(true),
		"pending_interventions": state.pending_interventions.duplicate(true),
		"pending_offers": state.pending_offers.duplicate(true),
	}


static func restore_diplomacy(play: PlaySession, data: Dictionary) -> void:
	var snapshot: Variant = data.get("diplomacy", {})
	if typeof(snapshot) == TYPE_DICTIONARY and not snapshot.is_empty():
		play.diplomacy = _diplomacy_from(snapshot)
	var ai: Dictionary = _dictionary(data.get("ai", {}))
	if not ai.is_empty():
		play.ai = AiState.from_dict(ai)


static func _diplomacy_from(data: Dictionary) -> DiplomacyState:
	var state := DiplomacyState.new()
	state.turn = int(data.get("turn", 0))
	var records: Dictionary = data.get("relations", {})
	for key: Variant in records.keys():
		var entry: Variant = records[key]
		if typeof(entry) == TYPE_DICTIONARY:
			state.relations[String(key)] = DiplomacyRelation.from_dict(entry)
	state.overtures = data.get("overtures", {}).duplicate()
	state.subsidies = data.get("subsidies", {}).duplicate()
	state.ftps = data.get("ftps", {}).duplicate()
	state.boycotts = data.get("boycotts", {}).duplicate()
	state.colonies = data.get("colonies", {}).duplicate()
	for event: Variant in data.get("events", []):
		if typeof(event) == TYPE_DICTIONARY:
			state.events.append(event.duplicate(true))
	state._modified = data.get("modified", {}).duplicate()
	state._order_counts = data.get("order_counts", {}).duplicate()
	state.alliance_snapshot = data.get("alliance_snapshot", {}).duplicate()
	state.pending_calls.assign(data.get("pending_calls", []))
	state.pending_interventions.assign(data.get("pending_interventions", []))
	state.pending_offers.assign(data.get("pending_offers", []))
	return state


# --- victory -----------------------------------------------------------------


## Decided campaign (wiki: campaign-persistence § Snapshot contract, victory
## § Persistence). An undecided campaign writes an empty entry.
static func capture_victory(state: VictoryState) -> Dictionary:
	if state == null:
		return {}
	return {"winner": state.winner_player_id, "type": state.type, "turn": state.turn_number}


## A save from before victory state was captured (or a malformed entry) loads as
## an undecided campaign, so legacy slots still resume with turns open.
static func victory_from(raw: Variant) -> VictoryState:
	if typeof(raw) != TYPE_DICTIONARY:
		return null
	var data: Dictionary = raw
	var winner: int = int(data.get("winner", MapModel.NO_ID))
	if not FactionCatalog.can_win(winner):
		return null
	if int(data.get("type", VictoryState.Type.MILITARY)) != VictoryState.Type.MILITARY:
		return null
	var turn: int = int(data.get("turn", -1))
	if turn < 0:
		return null
	return VictoryState.military(winner, turn)


static func _dictionary(raw: Variant) -> Dictionary:
	if typeof(raw) == TYPE_DICTIONARY:
		return raw
	return {}
