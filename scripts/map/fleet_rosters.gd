class_name FleetRosters
extends RefCounted
## Roster arithmetic shared by the fleet layer, the save module and the turn
## tick: every region a crown keeps squadrons in and the next free fleet id.
## Kept node-free so one reader serves orders, save capture and battles
## (REQ-P3-02, REQ-P3-03).


## Every region's roster as typed arrays, including the shown region's live one.
static func all(regions: MapRegionTable) -> Array[Array]:
	var rosters: Array[Array] = []
	for raw: Variant in regions.values():
		var stored: Array[FleetState] = []
		stored.assign(raw)
		rosters.append(stored)
	return rosters


## Next free fleet id in one roster; regions never share an id.
static func next_id(fleets: Array[FleetState]) -> int:
	var next: int = 0
	for fleet: FleetState in fleets:
		if fleet != null:
			next = maxi(next, fleet.id + 1)
	return next


## Next free fleet id across every region, so a squadron crossing into another
## map cannot collide with an id that region already uses.
static func next_id_all(regions: MapRegionTable) -> int:
	var next: int = 0
	for roster: Array in all(regions):
		var fleets: Array[FleetState] = []
		fleets.assign(roster)
		next = maxi(next, next_id(fleets))
	return next


## Hulls afloat for one crown across every region: another map must not hide
## them from upkeep, the ledger or the dossier.
static func hulls_afloat(regions: MapRegionTable, owner: int) -> int:
	var total: int = 0
	for roster: Array in all(regions):
		var fleets: Array[FleetState] = []
		fleets.assign(roster)
		for fleet: FleetState in fleets:
			if fleet != null and fleet.owner == owner:
				total += fleet.ship_count()
	return total
