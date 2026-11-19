class_name NavalStation
extends RefCounted
## One station read for a whole water: every squadron the station's owner holds
## there, the orders that actually work the station, and the trade raid it
## works. The combat pass, the trade pass and the fleet dossier all read a water
## through this module, so the number a player reads is the number the turn
## rolls (wiki: ships-and-naval § Trade and Transport Interception, § Naval
## Interception Probability; DR-20261120-01, DR-20261120-02; REQ-P2-03).
##
## A station is judged in its own zone, never pooled with a squadron working
## another coast (DR-20261109-16).


## True when one squadron's own orders work a station: a patrol always, a
## blockade while it still stands on an enemy shore (DR-20261120-01).
static func works(
	model: MapModel, fleet: FleetState, hostile: Callable = Callable()
) -> bool:
	if fleet == null:
		return false
	if fleet.mission == FleetState.Mission.PATROL:
		return true
	return fleet.mission == FleetState.Mission.BLOCKADE \
		and FleetMissions.is_blockading(model, fleet, hostile)


## The squadrons holding a station this turn: every squadron of `owner` at sea in
## `zone` whose own orders work it, in roster order. Everything else in the water
## is a bystander for the roll (DR-20261109-16: "each Patrol/Blockade group
## attempts interception"). The dossier prices the same list, so the chance a
## crown reads and the chance the pass rolls can never differ (REQ-P2-03).
static func group(
	model: MapModel, fleets: Array, zone: int, owner: int, hostile: Callable = Callable()
) -> Array:
	var kept: Array = []
	for fleet: FleetState in fleets:
		if fleet == null or fleet.owner != owner or not fleet.is_at_sea():
			continue
		if fleet.sea_zone != zone or not fleet.is_afloat():
			continue
		if not works(model, fleet, hostile):
			continue
		kept.append(fleet)
	return kept


## The squadrons of one group that hold a station: the same reading kept to a
## list the caller already holds in the water.
static func group_from(
	model: MapModel, group: Array, hostile: Callable = Callable()
) -> Array:
	var kept: Array = []
	for fleet: FleetState in group:
		if works(model, fleet, hostile):
			kept.append(fleet)
	return kept


## The station of one fleet read off the roster. A fleet at sea holds a station
## on her own if the roster has none of her consorts.
static func group_of(
	model: MapModel, fleets: Array, fleet: FleetState, hostile: Callable = Callable()
) -> Array:
	if fleet == null:
		return []
	var kept: Array = group(model, fleets, fleet.sea_zone, fleet.owner, hostile)
	if kept.is_empty():
		kept.append(fleet)
	return kept
