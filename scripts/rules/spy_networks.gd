class_name SpyNetworks
extends RefCounted
## Espionage's quiet half (wiki: civilian-units § Spy; fog-and-exploration
## § Explorer vs Spy; tech-tree § Research Model; DR-20261110-03).
##
## A Spy posted on another crown's land charts nothing new — the fog rules hold
## it to terrain the crown already glimpsed (VisibilityModel.hold_explored_province).
## What it does add is a quickened Research phase: every rival Great Power that
## shelters one of the crown's spies hands over a share of what it already knows,
## so slots studying a tech that rival has finished earn extra points.
##
## Pure maths over the roster: no nodes, no stored state, so the Research phase,
## the ledger and tests read the same numbers (REQ-P3-03).

## Research-point bonus each qualifying rival Great Power grants (percent).
const BOOST_PERCENT: int = 15
const SPY_TYPE: String = "spy"


## Great Powers (ascending, unique) on whose land at least one of `owner`'s
## spies stands. A deed sold to a crown counts as that crown's land, so the host
## is the tile owner, not the province owner. The crown's own land, Minor
## Nations and Tribes are never qualifying rivals.
static func qualifying_rivals(
	model: MapModel, units: Array, owner: int
) -> Array[int]:
	var rivals: Array[int] = []
	if model == null:
		return rivals
	var great_powers: Array[int] = FactionCatalog.great_power_ids()
	for raw: Variant in units:
		var unit: CivilianState = raw
		if unit == null or unit.owner != owner or unit.type_id != SPY_TYPE:
			continue
		if not model.in_bounds(unit.tile.x, unit.tile.y):
			continue
		var host: int = model.owner_at(unit.tile.x, unit.tile.y)
		if host == owner or host == MapModel.NO_ID:
			continue
		if not great_powers.has(host) or rivals.has(host):
			continue
		rivals.append(host)
	rivals.sort()
	return rivals


## Tech id -> percent bonus, summed over the rivals that already unlocked it.
## A tech no qualifying rival knows earns nothing, however many spies wait.
static func research_boost(rivals: Array, rival_tech: Dictionary) -> Dictionary:
	var boost: Dictionary = {}
	for raw: Variant in rivals:
		var table: Dictionary = rival_tech.get(int(raw), {}) as Dictionary
		for key: Variant in table.keys():
			if not bool(table[key]):
				continue
			var tech_id: String = String(key)
			boost[tech_id] = int(boost.get(tech_id, 0)) + BOOST_PERCENT
	return boost


## Bonus percent for one tech, or 0 when no spy network covers it.
static func boost_for(boost: Dictionary, tech_id: String) -> int:
	return int(boost.get(tech_id, 0))


## Rival names for the ledger line, e.g. "England, France".
static func rival_names(rivals: Array) -> String:
	var names: PackedStringArray = PackedStringArray()
	for raw: Variant in rivals:
		names.append(FactionCatalog.name_of(int(raw)))
	return ", ".join(names)
