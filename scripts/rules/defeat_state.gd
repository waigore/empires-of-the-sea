class_name DefeatState
extends RefCounted
## A human Great Power's terminal fall (wiki: victory § Great Power defeat;
## DR-20261109-05). Deliberately separate from VictoryState: defeat seals the
## human session but never grants the conqueror a military victory.

var fallen_player_id: int = MapModel.NO_ID
var conqueror_player_id: int = MapModel.NO_ID
var turn_number: int = 0


static func terminal_fall(fallen: int, conqueror: int, turn: int) -> DefeatState:
	var state := DefeatState.new()
	state.fallen_player_id = fallen
	state.conqueror_player_id = conqueror
	state.turn_number = turn
	return state


func fallen_name() -> String:
	return FactionCatalog.name_of(fallen_player_id)


func conqueror_name() -> String:
	return FactionCatalog.name_of(conqueror_player_id)


## One-line record for toasts and the overlay subtitle.
func summary() -> String:
	return "%s falls to %s — defeat, turn %d" % [
		fallen_name(), conqueror_name(), turn_number
	]
