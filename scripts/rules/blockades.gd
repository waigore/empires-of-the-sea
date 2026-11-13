class_name Blockades
extends RefCounted
## Sealed ports and the sea paths they cut (wiki: capital-and-connectivity
## § Blockade; ships-and-naval § Missions and Movement).
##
## A blockade is not only a raid: a hostile squadron at sea on the Blockade
## mission severs the port province it holds, and a blockade of the crown's own
## capital province severs every sea path at once, leaving only ground the crown
## can still reach by road. The reading is taken from the fleet stations every
## time it is asked, so no save carries it and no mission can outlive its war
## (REQ-P2-03).

## region id -> { province id: true } for the court's own provinces a hostile
## squadron holds sealed this turn.
var sealed: Dictionary = {}
## True when the crown's capital province is one of them.
var sea_cut: bool = false


## The ports sealed against `owner` this turn: one walk over both regions'
## rosters. A squadron in port, a coast its court is at peace with and a coast
## the crown no longer holds all seal nothing — the station's own gate decides
## (FleetMissions.is_blockading).
static func read(
	world: WorldMap,
	rosters: Dictionary,
	owner: int,
	capital_region: int,
	capital_province: int,
	hostile: Callable = Callable()
) -> Blockades:
	var result := Blockades.new()
	if world == null or owner < 0:
		return result
	for region in world.region_count():
		var model: MapModel = world.region(region)
		if model == null:
			continue
		var roster: Array = rosters.get(region, [])
		for entry: Variant in roster:
			var fleet: FleetState = entry
			if fleet == null or fleet.owner == owner or not fleet.is_at_sea():
				continue
			if not FleetMissions.is_blockading(model, fleet, hostile):
				continue
			var province_id: int = fleet.blockade_province
			if model.province_owner(province_id) != owner:
				continue
			if not result.sealed.has(region):
				result.sealed[region] = {}
			(result.sealed[region] as Dictionary)[province_id] = true
	result.sea_cut = result.seals(capital_region, capital_province)
	return result


## True when this province's own harbour is held by a hostile squadron.
func seals(region: int, province_id: int) -> bool:
	var in_region: Dictionary = sealed.get(region, {})
	return bool(in_region.get(province_id, false))


## True when nothing in this province may reach the crown by sea: its own port
## is sealed, or the capital's is, which cuts every sea path at once.
func cuts(region: int, province_id: int) -> bool:
	return sea_cut or seals(region, province_id)


## True when any sea path of this court's is cut.
func any() -> bool:
	return sea_cut or not sealed.is_empty()


## The despatch line naming what the sea shut this turn (REQ-P5-05): a court
## must never read a lean harvest without the reason. Empty when no port of its
## own is held.
static func note(seals: Blockades, world: WorldMap) -> String:
	if seals == null or world == null or not seals.any():
		return ""
	if seals.sea_cut:
		return (
			"The capital's harbour is blockaded — only what the roads reach yields"
			+ " this turn"
		)
	var names: Array[String] = []
	for raw_region: Variant in seals.sealed.keys():
		var model: MapModel = world.region(int(raw_region))
		var provinces: Dictionary = seals.sealed[raw_region]
		for raw_province: Variant in provinces.keys():
			var place: String = (
				model.province_name(int(raw_province)) if model != null else "a port"
			)
			if not names.has(place):
				names.append(place)
	names.sort()
	if names.is_empty():
		return ""
	return "Blockaded: %s — nothing there reaches the crown by sea this turn" % (
		", ".join(names)
	)
