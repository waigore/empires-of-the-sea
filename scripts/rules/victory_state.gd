class_name VictoryState
extends RefCounted
## A decided campaign (wiki: victory). The finished game is a typed record so the
## HUD, toasts and tests read the same fields instead of Dictionary keys.
## Military victory is the only type this milestone ships; the calendar-cap
## variant still reports through the session, not through this record.

enum Type { MILITARY }

const TYPE_LABELS: Dictionary = {Type.MILITARY: "Military victory"}

var winner_player_id: int = MapModel.NO_ID
var type: int = Type.MILITARY
var turn_number: int = 0


static func military(p_winner: int, p_turn: int) -> VictoryState:
	var state := VictoryState.new()
	state.winner_player_id = p_winner
	state.type = Type.MILITARY
	state.turn_number = p_turn
	return state


func winner_name() -> String:
	return FactionCatalog.name_of(winner_player_id)


func type_label() -> String:
	return String(TYPE_LABELS.get(type, "Victory"))


func won_by(faction_id: int) -> bool:
	return winner_player_id == faction_id


## One-line record for toasts and the overlay subtitle.
func summary() -> String:
	return "%s — %s, turn %d" % [winner_name(), type_label(), turn_number]
