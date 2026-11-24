class_name MapPlayCourtRoster
extends RefCounted
## Where a named army or squadron stands: region rosters, id lookups, the
## army-order trace row, and the on-screen hull refresh (REQ-P2-03, REQ-P3-01,
## REQ-P3-02).
##
## Split from [MapPlayCourt] so the seat/planner gate and the holdings read stay
## one question each. Pure state reads and the one trace row an army order
## records: nothing here issues an order or changes a roster.

## `-1` reads as "any owner" for the roster lookups.
const NO_OWNER: int = -1


## Squadrons stored in one region, as the passes copy them before planning.
static func region_fleets(play: PlaySession, region: int) -> Array[FleetState]:
	var roster: Array[FleetState] = []
	if play == null or play.ship_layer == null:
		return roster
	roster.assign(play.ship_layer.regions.value(region, []))
	return roster


## Armies stored in one region, as the land pass copies them before planning.
static func region_armies(play: PlaySession, region: int) -> Array[ArmyState]:
	var roster: Array[ArmyState] = []
	if play == null or play.army_layer == null:
		return roster
	roster.assign(play.army_layer.regions.value(region, []))
	return roster


## Armies in one region as the view holds them: the region on screen answers
## from the live marker roster, so a march the court is watching is not planned
## from a stale copy; every other region answers from its stored roster.
static func visible_armies(play: PlaySession, region: int) -> Array[ArmyState]:
	if play == null or play.army_layer == null:
		return []
	if play.army_layer.model != null and play.army_layer.model.region_id == region:
		return play.army_layer.armies
	return region_armies(play, region)


## The squadron with this id in a roster, optionally narrowed to one owner.
static func fleet_by_id(roster: Array, fleet_id: int, owner: int = NO_OWNER) -> FleetState:
	for raw: Variant in roster:
		var fleet: FleetState = raw
		if fleet == null or fleet.id != fleet_id:
			continue
		if owner != NO_OWNER and fleet.owner != owner:
			continue
		return fleet
	return null


## The army with this id in a roster, optionally narrowed to one owner.
static func army_by_id(armies: Array, army_id: int, owner: int = NO_OWNER) -> ArmyState:
	for raw: Variant in armies:
		var army: ArmyState = raw
		if army == null or army.id != army_id:
			continue
		if owner != NO_OWNER and army.owner != owner:
			continue
		return army
	return null


## The one row every rival land order records: the court, the kind, the standard
## and the ground it stands on, named for the trace's readers. The army pass, its
## muster and the invasion pass all spell it here, so a new key lands once
## (wiki: turn-trace-interpretation).
static func army_trace(
	model: MapModel, faction: int, kind: String, army: int, province: int
) -> Dictionary:
	return {
		"faction": faction,
		"kind": kind,
		"army": army,
		"province": province,
		"province_name": model.province_name(province),
		"region": model.region_id,
	}


## The squadron with this id stored in `region`, at any owner: a voyage or a
## crossing may be planned across a court's charted water.
static func fleet_in(
	play: PlaySession, region: int, fleet_id: int, owner: int = NO_OWNER
) -> FleetState:
	return fleet_by_id(region_fleets(play, region), fleet_id, owner)


## Rebuilds the on-screen hull markers after a rival moved a squadron, keeping
## the player's selected marker when it still stands. The view never follows a
## rival's sail.
static func refresh_hulls(play: PlaySession) -> void:
	if play == null or play.ship_layer == null or play.ship_layer.model == null:
		return
	var selected: FleetState = play.ship_layer.fleet_of(play.ship_layer.selected())
	play.ship_layer.spawn(
		play.ship_layer.model, 0, 0, -1, false, play.player_faction
	)
	if selected != null:
		play.ship_layer.select(play.ship_layer.ship_for(selected))
