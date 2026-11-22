class_name AiSquadronReads
extends RefCounted
## What a squadron is and what water it can reach this turn — one read shared by
## the naval policy ([AiNavalPlanner]) and its station pass ([AiNavalStation])
## (REQ-P3-01). Pure rules: state in, readings out, no orders here
## (REQ-P3-03).


## Own squadrons that can still sail: afloat, un-moved, in id order. A squadron
## carrying an expedition army keeps its course — AiInvasionPlanner steers it
## (wiki: ai-architecture § Overseas invasions).
static func sailing(fleets: Array, owner: int) -> Array[FleetState]:
	var own: Array[FleetState] = []
	for fleet: FleetState in fleets:
		if fleet == null or fleet.owner != owner or fleet.moved or not fleet.is_afloat():
			continue
		if fleet.embarked_army >= 0:
			continue
		own.append(fleet)
	own.sort_custom(func(a: FleetState, b: FleetState) -> bool: return a.id < b.id)
	return own


## A commerce raider needs a warship: a merchant squadron is cargo, not a
## predator (wiki: ships-and-naval § Ship Types).
static func has_warship(fleet: FleetState) -> bool:
	for hull_id: String in fleet.hulls:
		if ShipStats.is_warship(fleet.type_of(hull_id)):
			return true
	return false


## Sea zones this squadron could enter this turn. A home squadron sorties out of
## the seat's port — ships leave the home fleet when they receive a naval move
## order (FleetSortie, DR-20261109-17) — so its reach is the water beside the
## capital; a sea-going squadron reads NavalMovement's own list.
static func destinations(model: MapModel, fleet: FleetState) -> Array[int]:
	if NavalMovement.is_home_fleet(model, fleet):
		return FleetSortie.zones(model, fleet)
	return NavalMovement.destination_zones(model, fleet)


## True when this court's chart holds the sea zone; a null chart (a fixture)
## answers yes, so the published policy is what every other test reads.
static func charts_water(
	charts: CourtCharts, faction: int, region: int, zone: int
) -> bool:
	if charts == null:
		return true
	return charts.knows_zone(faction, region, zone)


## True when a hostile hull is afloat in water this squadron could enter.
static func hostile_beside(
	model: MapModel, fleets: Array, fleet: FleetState, hostile: Dictionary
) -> bool:
	for zone: int in destinations(model, fleet):
		if hostile_strength(fleets, zone, hostile) > 0.0:
			return true
	return false


## Every hostile hull afloat in one zone, as combined side strength.
static func hostile_strength(fleets: Array, zone: int, hostile: Dictionary) -> float:
	var present: Array = []
	for fleet: FleetState in fleets:
		if fleet == null or not fleet.is_at_sea() or not fleet.is_afloat():
			continue
		if fleet.sea_zone != zone or not hostile.has(fleet.owner):
			continue
		present.append(fleet)
	if present.is_empty():
		return 0.0
	return NavalCombat.side_strength(present)
