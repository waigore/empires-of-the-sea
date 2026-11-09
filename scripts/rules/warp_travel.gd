class_name WarpTravel
extends RefCounted
## Crossings through warp zones (wiki: map-topology § Warp zones).
## A warp zone — the “Passage” ring on the chart — links to exactly one sea
## zone on the counterpart map. A fleet at sea in one may cross it as its move
## for the turn, which is the only way between the Old and New World. Pure
## rules: the caller re-seats the fleet in the other region's roster and moves
## the view (REQ-P3-03). Sea-zone ids are region-local, so a destination zone
## is only meaningful together with its region.

## One counterpart map today; a zone pairing with several maps returns the
## first link (wiki allows one link per other map).
static func link(world: WorldMap, region_index: int, zone_id: int) -> Dictionary:
	if world == null or zone_id < 0:
		return {}
	return world.warp_partner(region_index, zone_id)


## Validates a crossing without mutating anything.
static func can_cross(
	world: WorldMap, region_index: int, fleet: FleetState
) -> Dictionary:
	if fleet == null:
		return _deny("There is no fleet to order.")
	if fleet.moved:
		return _deny("This fleet has already moved this turn.")
	if not fleet.is_at_sea():
		return _deny("A fleet must be at sea to take a passage.")
	var warp: Dictionary = link(world, region_index, fleet.sea_zone)
	if warp.is_empty():
		return _deny("This sea zone has no passage to another world.")
	return {
		"ok": true,
		"reason": "",
		"to_region": int(warp["to_region"]),
		"to_zone": int(warp["to_zone"]),
	}


## Validates, moves the fleet into the paired zone on the other map, and spends
## its move. Hulls keep their instance ids; ids of fleets are the caller's.
static func apply_crossing(
	world: WorldMap, region_index: int, fleet: FleetState
) -> Dictionary:
	var check: Dictionary = can_cross(world, region_index, fleet)
	if not bool(check.get("ok", false)):
		return {
			"ok": false,
			"reason": String(check.get("reason", "")),
			"from_region": region_index,
			"from_zone": -1,
			"to_region": -1,
			"to_zone": -1,
		}
	var from_zone: int = fleet.sea_zone
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = int(check["to_zone"])
	fleet.province = MapModel.NO_ID
	# A crossing is the squadron's sail: it gives up its station and its landing
	# site (wiki: ships-and-naval § Missions and Movement — a mission persists
	# until the squadron sails; § Naval transport — the beachhead marker is lost
	# if the squadron sails). Province ids are region-local, so a marker carried
	# into the other map would name an unrelated coast there.
	fleet.clear_beachhead()
	fleet.clear_mission()
	fleet.moved = true
	return {
		"ok": true,
		"reason": "",
		"from_region": region_index,
		"from_zone": from_zone,
		"to_region": int(check["to_region"]),
		"to_zone": int(check["to_zone"]),
	}


static func _deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "to_region": -1, "to_zone": -1}
