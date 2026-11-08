class_name TurnTime
extends RefCounted
## Turn-to-calendar mapping (wiki: turn-time-mapping, GDD 01 defaults).

const START_YEAR: int = 1500
const CUTOFF_YEAR: int = 1700
const YEARS_BEFORE_CUTOFF: int = 2
const YEARS_AFTER_CUTOFF: int = 1
const TURNS_BEFORE_CUTOFF: int = (CUTOFF_YEAR - START_YEAR) / YEARS_BEFORE_CUTOFF
## Normative stop year: the campaign calendar cap closes after the last full
## turn that starts in 1800 (wiki: turn-time-mapping § Campaign calendar cap).
const STOP_YEAR: int = 1800


static func year_for_turn(turn: int) -> int:
	if turn <= 1:
		return START_YEAR
	var elapsed: int = turn - 1
	if elapsed <= TURNS_BEFORE_CUTOFF:
		return START_YEAR + elapsed * YEARS_BEFORE_CUTOFF
	return CUTOFF_YEAR + (elapsed - TURNS_BEFORE_CUTOFF) * YEARS_AFTER_CUTOFF


## First turn whose start year is `year`, or -1 when no turn starts in that year
## (the two-segment pacing skips every odd year before the cutoff).
static func turn_for_year(year: int) -> int:
	if year < START_YEAR:
		return -1
	if year <= CUTOFF_YEAR:
		var offset: int = year - START_YEAR
		if offset % YEARS_BEFORE_CUTOFF != 0:
			return -1
		return offset / YEARS_BEFORE_CUTOFF + 1
	return TURNS_BEFORE_CUTOFF + (year - CUTOFF_YEAR) + 1


## Turn on which the calendar cap falls; -1 when the mapping never starts that
## year (a custom mapping with pacing gaps disables the cap).
static func cap_turn() -> int:
	return turn_for_year(STOP_YEAR)


## True for the last turn the campaign may resolve.
static func is_cap_turn(turn: int) -> bool:
	var cap: int = cap_turn()
	return cap > 0 and turn >= cap


static func label_for_turn(turn: int) -> String:
	return "Turn %d  ·  %d" % [turn, year_for_turn(turn)]
