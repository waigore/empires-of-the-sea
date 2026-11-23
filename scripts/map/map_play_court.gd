class_name MapPlayCourt
extends RefCounted
## Which courts run a planner this session, where the crown's seat stands, and
## whether a court is at war — so every rival pass asks the same question once
## instead of carrying its own copy (REQ-P2-03, REQ-P3-01, REQ-P3-02).
##
## The answers live where their owners do: the seat and the war footing in
## [MapPlayCourtHoldings], a named army or squadron in [MapPlayCourtRoster].
## These names keep the one call site that predates the split working without
## a second copy of any read. Pure state reads: nothing here issues an order or
## changes a roster.


## The chart the crown's seat stands on: `{region, province, model}`. See
## [method MapPlayCourtHoldings.crown_seat].
static func crown_seat(play: PlaySession) -> Dictionary:
	return MapPlayCourtHoldings.crown_seat(play)


## The Great Powers that run a planner this session, in catalog order. See
## [method MapPlayCourtHoldings.planning_factions].
static func planning_factions(play: PlaySession) -> Array[int]:
	return MapPlayCourtHoldings.planning_factions(play)


## True while the crown still holds a province in either world. See
## [method MapPlayCourtHoldings.holds_land].
static func holds_land(play: PlaySession, faction: int) -> bool:
	return MapPlayCourtHoldings.holds_land(play, faction)


## True when any court holds a declared war on this one. See
## [method MapPlayCourtHoldings.at_war].
static func at_war(play: PlaySession, faction: int) -> bool:
	return MapPlayCourtHoldings.at_war(play, faction)


## The courts at war with this one, in relation order. See
## [method MapPlayCourtHoldings.at_war_with].
static func at_war_with(play: PlaySession, faction: int) -> Array[int]:
	return MapPlayCourtHoldings.at_war_with(play, faction)
