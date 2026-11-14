class_name FleetRosters
extends RefCounted
## Roster arithmetic shared by the fleet layer, the save module and the turn
## tick: every region a crown keeps squadrons in, the next free fleet id, and the
## list surgery a battle, a hand-over or a passage needs. Kept node-free so one
## reader serves orders, save capture and battles (REQ-P3-02, REQ-P3-03).


## Every region's roster as typed arrays, including the shown region's live one.
static func all(regions: MapRegionTable) -> Array[Array]:
	var rosters: Array[Array] = []
	for raw: Variant in regions.values():
		var stored: Array[FleetState] = []
		stored.assign(raw)
		rosters.append(stored)
	return rosters


## Runs one per-squadron pass over every stored roster, so a layer never writes
## the same region walk twice (REQ-P3-03). The pass mutates fleets, not the list
## itself: rosters that must lose a command use [method prune] or the caller
## stores the list again.
static func each(regions: MapRegionTable, pass_fn: Callable) -> void:
	for raw: Variant in regions.values():
		var stored: Array[FleetState] = []
		stored.assign(raw)
		pass_fn.call(stored)


## Drops squadrons with no hull left (sunk in a battle): a roster carries live
## commands only, and every region prunes its own (wiki: ships-and-naval
## § Naval Combat). The caller repaints its markers.
static func prune(fleets: Array[FleetState]) -> void:
	var index: int = fleets.size() - 1
	while index >= 0:
		var fleet: FleetState = fleets[index]
		if fleet != null and not fleet.is_afloat():
			fleets.remove_at(index)
		index -= 1


## Join Empire absorption and a terminal fall, in place: an absorbed crown's
## squadrons change colours; `to_id == MapModel.NO_ID` retires them, so the
## roster loses those commands (wiki: diplomacy § GP–Minor Rules;
## capital-and-connectivity § Capital loss). The caller stores the roster again.
static func hand_over(fleets: Array[FleetState], from_id: int, to_id: int) -> void:
	var index: int = fleets.size() - 1
	while index >= 0:
		var fleet: FleetState = fleets[index]
		if fleet == null or fleet.owner != from_id:
			index -= 1
			continue
		if to_id == MapModel.NO_ID:
			fleets.remove_at(index)
		else:
			fleet.owner = to_id
		index -= 1


## Hands one squadron to another region's roster, renumbered so two regions
## never share an id (wiki: map-topology § two regions). The from-roster is
## written to the table before the id is drawn, so the crossing hull is not its
## own successor. Returns the destination roster for the caller to store.
static func hand_to_region(
	regions: MapRegionTable,
	from_region: int,
	fleet: FleetState,
	to_region: int,
	from_roster: Array[FleetState]
) -> Array[FleetState]:
	from_roster.erase(fleet)
	regions.set_region(from_region, from_roster)
	fleet.id = next_id_all(regions)
	var destination: Array[FleetState] = []
	destination.assign(regions.value(to_region, []))
	destination.append(fleet)
	regions.set_region(to_region, destination)
	return destination


## Sea zones one crown's squadrons hold in one roster, in roster order: the
## ledger's watch, the missions pass and the dossier read alike.
static func zones_at_sea(fleets: Array[FleetState], owner: int) -> Array[int]:
	var zones: Array[int] = []
	for fleet: FleetState in fleets:
		if fleet == null or fleet.owner != owner or not fleet.is_at_sea():
			continue
		if not zones.has(fleet.sea_zone):
			zones.append(fleet.sea_zone)
	return zones


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
