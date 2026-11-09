class_name NavalRetreat
extends RefCounted
## Retreat from a lost naval engagement (wiki: ships-and-naval § Naval Retreat
## Formula). Pure rules: the beaten side escapes to an adjacent friendly or
## neutral sea zone when the roll succeeds; a failed attempt is a normal rout.
## The roll is deterministic from the campaign seed, turn and zone.

const BASE_CHANCE: float = 0.6


## base 0.6 + speed advantage − the enemy station's aggression.
static func chance(beaten: Array, victor: Array, enemy_mission: int) -> float:
	var speed: float = (
		FleetMissions.avg_speed(beaten) - FleetMissions.avg_speed(victor)
	) * 0.1
	var aggression: float = 0.0
	if enemy_mission == FleetState.Mission.BLOCKADE:
		aggression = 0.2
	elif enemy_mission == FleetState.Mission.PATROL:
		aggression = 0.1
	return clampf(BASE_CHANCE + speed - aggression, 0.0, 1.0)


## Adjacent zones with no fleet hostile to the retreating side.
static func safe_zones(
	model: MapModel,
	zone: int,
	side_owners: Array[int],
	fleets: Array,
	hostile: Callable = Callable()
) -> Array[int]:
	var zones: Array[int] = []
	if model == null:
		return zones
	for neighbor: int in MapGeo.sea_zone_neighbors(model, zone):
		var safe: bool = true
		for fleet: FleetState in fleets:
			if fleet == null or not fleet.is_at_sea() or not fleet.is_afloat():
				continue
			if fleet.sea_zone != neighbor:
				continue
			for owner: int in side_owners:
				if _hostile(hostile, fleet.owner, owner):
					safe = false
					break
			if not safe:
				break
		if safe:
			zones.append(neighbor)
	zones.sort()
	return zones


## Tries the retreat. On success every beaten squadron is at sea in the haven,
## has spent its move and has lost its station.
static func attempt(
	model: MapModel,
	zone: int,
	beaten: Array,
	victor: Array,
	fleets: Array,
	hostile: Callable = Callable(),
	seed_value: int = 0,
	turn: int = 0,
	roll_value: float = -1.0
) -> Dictionary:
	if model == null or beaten.is_empty():
		return {"ok": false, "success": false, "reason": "no water to retreat into"}
	var owners: Array[int] = _owners(beaten)
	var zones: Array[int] = safe_zones(model, zone, owners, fleets, hostile)
	if zones.is_empty():
		return {"ok": false, "success": false, "reason": "no safe adjacent zone"}
	var enemy_mission: int = _enemy_mission(model, victor, hostile)
	var found: float = chance(beaten, victor, enemy_mission)
	var rolled: float = roll_value
	if rolled < 0.0:
		rolled = NavalInterception.roll(seed_value, turn, zone, owners[0], 2)
	var success: bool = rolled < found
	var haven: int = zones[0]
	var ids: Array[int] = []
	if success:
		for fleet: FleetState in beaten:
			ids.append(fleet.id)
			fleet.location = FleetState.Location.AT_SEA
			fleet.sea_zone = haven
			fleet.province = MapModel.NO_ID
			fleet.moved = true
			fleet.clear_beachhead()
			fleet.clear_mission()
	return {
		"ok": true,
		"success": success,
		"zone": haven,
		"chance": found,
		"roll": rolled,
		"enemy_mission": enemy_mission,
		"fleets": ids,
	}


static func _owners(group: Array) -> Array[int]:
	var owners: Array[int] = []
	for fleet: FleetState in group:
		if not owners.has(fleet.owner):
			owners.append(fleet.owner)
	owners.sort()
	return owners


static func _enemy_mission(model: MapModel, victor: Array, hostile: Callable) -> int:
	for fleet: FleetState in victor:
		if fleet.mission == FleetState.Mission.BLOCKADE \
				and FleetMissions.is_blockading(model, fleet, hostile):
			return FleetState.Mission.BLOCKADE
	for fleet: FleetState in victor:
		if fleet.mission == FleetState.Mission.PATROL:
			return FleetState.Mission.PATROL
	return FleetState.Mission.NONE


static func _hostile(hostile: Callable, a: int, b: int) -> bool:
	if a == b:
		return false
	if not hostile.is_valid():
		return true
	return bool(hostile.call(a, b))
