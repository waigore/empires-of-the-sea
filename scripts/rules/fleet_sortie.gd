class_name FleetSortie
extends RefCounted
## The home squadron puts to sea (wiki: ships-and-naval § Home Fleet — ships
## leave the home fleet when they receive a naval move order; DR-20261109-17).
## Pure rules: the layer only moves the marker and reveals the new zone.
##
## The product's single-squadron model parks one squadron in port at the seat;
## while it sits there it is the home fleet and never sails. A sortie spends
## that squadron's move and turns it into an ordinary sea-going fleet — it loses
## the home holds until it moors at the seat again.

## Sea zones the home squadron could put to sea into right now.
static func zones(model: MapModel, fleet: FleetState) -> Array[int]:
	if model == null or fleet == null:
		return []
	if not NavalMovement.is_home_fleet(model, fleet):
		return []
	return NavalMovement.province_sea_zones(model, fleet.province)


## Validates the sortie without mutating the fleet.
static func can_sortie(
	model: MapModel, fleet: FleetState, zone: int
) -> Dictionary:
	if model == null or fleet == null:
		return OrderVerdict.deny("No squadron can put to sea.")
	if not NavalMovement.is_home_fleet(model, fleet):
		return OrderVerdict.deny("Only the home squadron sorties from the capital.")
	if fleet.moved:
		return OrderVerdict.deny("This squadron has already sailed or taken a mission this turn.")
	if not fleet.is_afloat():
		return OrderVerdict.deny("A squadron with no hulls cannot put to sea.")
	if not zones(model, fleet).has(zone):
		return OrderVerdict.deny("That sea zone does not border the capital port.")
	return OrderVerdict.allow()


## Spends the move and turns the home squadron into a sea-going fleet.
static func apply(
	model: MapModel, fleet: FleetState, zone: int
) -> Dictionary:
	var check: Dictionary = can_sortie(model, fleet, zone)
	if not bool(check.get("ok", false)):
		return check
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = zone
	fleet.province = MapModel.NO_ID
	fleet.clear_beachhead()
	fleet.moved = true
	return {"ok": true, "reason": "", "zone": zone, "entered_zone": zone}
