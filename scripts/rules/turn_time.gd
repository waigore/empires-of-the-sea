class_name TurnTime
extends RefCounted
## Turn-to-calendar mapping (wiki: turn-time-mapping, GDD 01 defaults).

const START_YEAR: int = 1500
const CUTOFF_YEAR: int = 1700
const YEARS_BEFORE_CUTOFF: int = 2
const YEARS_AFTER_CUTOFF: int = 1
const TURNS_BEFORE_CUTOFF: int = (CUTOFF_YEAR - START_YEAR) / YEARS_BEFORE_CUTOFF


static func year_for_turn(turn: int) -> int:
	if turn <= 1:
		return START_YEAR
	var elapsed: int = turn - 1
	if elapsed <= TURNS_BEFORE_CUTOFF:
		return START_YEAR + elapsed * YEARS_BEFORE_CUTOFF
	return CUTOFF_YEAR + (elapsed - TURNS_BEFORE_CUTOFF) * YEARS_AFTER_CUTOFF


static func label_for_turn(turn: int) -> String:
	return "Turn %d  ·  %d" % [turn, year_for_turn(turn)]
