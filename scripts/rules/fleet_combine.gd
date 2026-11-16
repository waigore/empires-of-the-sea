class_name FleetCombine
extends RefCounted
## Folding one of the crown's squadrons into another in the same station (wiki:
## ships-and-naval § Ship instances — combine appends source fleets' instance
## lists onto the target fleet's list, order preserved, and an id never flies
## two colours). Pure rules: the roster surgery is here, markers and toasts
## belong to [ShipLayer] and MapPlayFleetCombine (REQ-P3-03).
##
## The target keeps the station: a patrol, a blockade or a beachhead belongs to
## the squadron that holds it, so the hulls that join take her orders. Every
## hull keeps her instance id, her catalog type and the name she flew, and the
## passengers come aboard when the deck can hold them.

## The rule the sheet prints, so a phone never has to hover for it (REQ-P1-07).
const NOTE: String = (
	"Combine with another of your squadrons here: she keeps every hull, name "
	+ "and passenger, and her orders go to the squadron that keeps the station."
)


## Every other own squadron in the same station, in roster order, with the
## verdict on folding this one into her. A caller with no squadron gets no rows.
static func rows(
	model: MapModel, roster: Array[FleetState], fleet: FleetState
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if fleet == null or not fleet.is_afloat():
		return rows
	for other: FleetState in roster:
		if other == null or other == fleet or other.owner != fleet.owner:
			continue
		if not same_station(fleet, other):
			continue
		var check: Dictionary = can_combine(model, fleet, other)
		rows.append({
			"fleet": other.id,
			"name": flagship(other),
			"type": other.type_of(other.hulls[0]) if other.is_afloat() else "",
			"hulls": other.ship_count(),
			"ok": bool(check["ok"]),
			"reason": String(check["reason"]),
		})
	return rows


## Two squadrons share a station when both lie in the same sea zone or both are
## moored in the same port (wiki: ships-and-naval § Missions and movement).
static func same_station(fleet: FleetState, other: FleetState) -> bool:
	if fleet == null or other == null:
		return false
	if fleet.is_at_sea() != other.is_at_sea():
		return false
	if fleet.is_at_sea():
		return fleet.sea_zone == other.sea_zone
	return fleet.province == other.province


## Whether this squadron may fold into that one: own colours, one station, both
## afloat, neither the home fleet, no beachhead to strand, and a deck that can
## still hold every passenger (one army per squadron, and a squadron carrying an
## army carries no colonists).
static func can_combine(
	model: MapModel, fleet: FleetState, target: FleetState
) -> Dictionary:
	if fleet == null:
		return _deny("There is no squadron to combine.")
	if target == null or target == fleet:
		return _deny("Choose another of your squadrons.")
	if target.owner != fleet.owner:
		return _deny("Only your own squadrons combine.")
	if not same_station(fleet, target):
		return _deny("Squadrons combine only in the same sea zone or the same port.")
	if not fleet.is_afloat() or not target.is_afloat():
		return _deny("A slip with no hulls has nothing to combine.")
	if model != null and (
		NavalMovement.is_home_fleet(model, fleet)
		or NavalMovement.is_home_fleet(model, target)
	):
		return _deny("The home fleet takes her joiners through Join the home fleet.")
	if fleet.has_beachhead():
		return _deny("The squadron holds a beachhead — land the troops before combining.")
	if fleet.embarked_army >= 0 and target.embarked_army >= 0:
		return _deny("Land one of the armies first — a squadron carries one.")
	if fleet.embarked_army >= 0 and target.carries_civilians():
		return _deny("A squadron carrying an army carries no colonists — land one first.")
	if target.embarked_army >= 0 and fleet.carries_civilians():
		return _deny("A squadron carrying an army carries no colonists — land one first.")
	return {"ok": true, "reason": ""}


## Folds this squadron into the target: every hull, name and passenger keeps,
## the target keeps her station, and the emptied squadron leaves the roster.
## Returns the target, the hulls that joined and both flagships, or the gate's
## own refusal with nothing moved.
static func combine(
	model: MapModel,
	roster: Array[FleetState],
	fleet: FleetState,
	target: FleetState
) -> Dictionary:
	var check: Dictionary = can_combine(model, fleet, target)
	if not bool(check.get("ok", false)):
		return _refused(String(check.get("reason", "")))
	var hulls: int = fleet.ship_count()
	var from_name: String = flagship(fleet)
	var into_name: String = flagship(target)
	target.merge_from(fleet)
	# A hull that has already sailed does not sail again: the combined squadron
	# is as ready as the least ready of the two.
	target.moved = target.moved or fleet.moved
	roster.erase(fleet)
	return {
		"ok": true,
		"reason": "",
		"fleet": target,
		"hulls": hulls,
		"name": from_name,
		"into": into_name,
	}


## The name a squadron flies: her flagship's (wiki: ships-and-naval § The
## crown's navy — one heading per squadron, named by the flagship).
static func flagship(fleet: FleetState) -> String:
	if fleet == null or fleet.hulls.is_empty():
		return ""
	return ShipNames.of(fleet, fleet.hulls[0])


static func _refused(reason: String) -> Dictionary:
	return {
		"ok": false, "reason": reason, "fleet": null, "hulls": 0, "name": "", "into": "",
	}


static func _deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
