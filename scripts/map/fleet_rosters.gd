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


## Fleet by instance id in one roster, or null.
static func find(fleets: Array[FleetState], fleet_id: int) -> FleetState:
	for fleet: FleetState in fleets:
		if fleet != null and fleet.id == fleet_id:
			return fleet
	return null


## Next free fleet id across every region, so a squadron crossing into another
## map cannot collide with an id that region already uses.
static func next_id_all(regions: MapRegionTable) -> int:
	var next: int = 0
	for roster: Array in all(regions):
		var fleets: Array[FleetState] = []
		fleets.assign(roster)
		next = maxi(next, next_id(fleets))
	return next


## Civilian seats afloat in any region: unit id -> the squadron that lists it.
## The roster is the truth; a passenger's own pointer lags a renumbered or
## merged squadron, so transport-loss checks read this side (DR-20261109-17).
static func carried_civilians(regions: MapRegionTable) -> Dictionary:
	var seats: Dictionary = {}
	for roster: Array in all(regions):
		var fleets: Array[FleetState] = []
		fleets.assign(roster)
		for fleet: FleetState in fleets:
			if fleet == null or not fleet.is_afloat():
				continue
			for unit_id: int in fleet.embarked_civilians:
				seats[unit_id] = fleet.id
	return seats


## Army seats afloat in any region: army id -> the squadron that lists it.
static func carried_armies(regions: MapRegionTable) -> Dictionary:
	var seats: Dictionary = {}
	for roster: Array in all(regions):
		var fleets: Array[FleetState] = []
		fleets.assign(roster)
		for fleet: FleetState in fleets:
			if fleet == null or not fleet.is_afloat() or fleet.embarked_army < 0:
				continue
			seats[fleet.embarked_army] = fleet.id
	return seats


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
