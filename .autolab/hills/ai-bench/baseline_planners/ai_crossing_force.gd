class_name MainlineAiCrossingForce
extends RefCounted
## Which squadron and which army make a crossing (wiki: ships-and-naval § Naval
## transport; DR-20261110-02). One hull carries one regiment, so a court with a
## small squadron lands a beachhead force it can actually carry instead of
## keeping the whole host at home. Pure selection over the rosters: the planner
## still asks NavalTransport and NavalMovement to execute every step
## (REQ-P2-03, REQ-P3-03).


## The squadron with the most room: afloat, un-moved, no army and no colonists
## aboard. Ties go to the lowest id, so the same state always picks the same
## hulls.
static func fleet(fleets: Array, owner: int) -> FleetState:
	var best: FleetState = null
	for raw: Variant in fleets:
		var candidate: FleetState = raw
		if candidate == null or candidate.owner != owner or candidate.moved:
			continue
		if not candidate.is_afloat() or candidate.embarked_army >= 0:
			continue
		if candidate.carries_civilians() or candidate.ship_count() < 1:
			continue
		if best == null or candidate.ship_count() > best.ship_count():
			best = candidate
	return best


## The field army that fits the squadron's hulls: the biggest force that fits,
## ties to the lowest id.
static func army(
	model: MapModel, armies: Array, owner: int, hulls: int
) -> ArmyState:
	var best: ArmyState = null
	for raw: Variant in armies:
		var candidate: ArmyState = raw
		if candidate == null or candidate.owner != owner or candidate.home:
			continue
		if candidate.is_empty() or candidate.count() > hulls:
			continue
		if not may_sail(model, candidate, owner):
			continue
		if best == null or candidate.count() > best.count():
			best = candidate
	return best


## A field army that can march to a harbour and sail: un-moved, non-empty and
## standing in an own coastal province with a harbour.
static func may_sail(model: MapModel, army: ArmyState, owner: int) -> bool:
	if army == null or army.moved or army.is_embarked() or army.is_empty():
		return false
	if model.province_owner(army.province) != owner:
		return false
	return NavalMovement.has_harbour(model, army.province)