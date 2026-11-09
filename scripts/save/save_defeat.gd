class_name SaveDefeat
extends RefCounted
## Save shape for the human defeat record (wiki: campaign-persistence
## § Snapshot contract, victory § Great Power defeat). Kept out of SaveCodec so
## the codec stays inside the module size budget (REQ-P3-01).


## An undefeated campaign writes an empty entry.
static func capture(state: DefeatState) -> Dictionary:
	if state == null:
		return {}
	return {
		"fallen": state.fallen_player_id,
		"conqueror": state.conqueror_player_id,
		"turn": state.turn_number,
	}


## Legacy or malformed entries load as an undefeated campaign; only the human
## Great Power's own fall is a defeat.
static func from_dict(raw: Variant, player_faction: int) -> DefeatState:
	if typeof(raw) != TYPE_DICTIONARY:
		return null
	var data: Dictionary = raw
	var fallen: int = int(data.get("fallen", MapModel.NO_ID))
	if fallen != player_faction or not FactionCatalog.can_win(fallen):
		return null
	var turn: int = int(data.get("turn", -1))
	if turn < 0:
		return null
	return DefeatState.terminal_fall(
		fallen, int(data.get("conqueror", MapModel.NO_ID)), turn
	)
