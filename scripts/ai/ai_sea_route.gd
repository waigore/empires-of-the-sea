class_name AiSeaRoute
extends RefCounted
## Sea-zone pathing shared by the rival voyage planners (colonisation, invasion).
## A squadron sails one zone a turn, so a planner asks for the next zone toward a
## goal and lets NavalMovement own legality (wiki: ai-architecture § Naval policy;
## REQ-P2-03, REQ-P3-03).


## Next zone on the way to a goal: from a port the adjacent water nearest the
## goal, from open sea the first breadth-first step.
static func sail_toward(model: MapModel, fleet: FleetState, goals: Array[int]) -> int:
	if goals.is_empty() or fleet == null or model == null:
		return -1
	if fleet.is_at_sea():
		return step_toward(model, fleet.sea_zone, goals)
	var best: int = -1
	var best_distance: int = 1 << 30
	for zone: int in NavalMovement.province_sea_zones(model, fleet.province):
		var distance: int = distance_to_goal(model, zone, goals)
		if distance < best_distance:
			best = zone
			best_distance = distance
	return best


## First step of a breadth-first walk from `start` to any goal zone; -1 when the
## goal is already reached or no route exists.
static func step_toward(model: MapModel, start: int, goals: Array[int]) -> int:
	if goals.has(start):
		return -1
	var queue: Array[int] = [start]
	var first_step: Dictionary = {start: -1}
	var head: int = 0
	while head < queue.size():
		var zone: int = queue[head]
		head += 1
		if goals.has(zone) and zone != start:
			return int(first_step[zone])
		for next: int in MapGeo.sea_zone_neighbors(model, zone):
			if first_step.has(next):
				continue
			first_step[next] = next if zone == start else int(first_step[zone])
			queue.append(next)
	return -1


## Zone hops from `start` to the nearest goal, or a large sentinel when none.
static func distance_to_goal(model: MapModel, start: int, goals: Array[int]) -> int:
	if goals.has(start):
		return 0
	var seen: Dictionary = {start: true}
	var queue: Array[Vector2i] = [Vector2i(start, 0)]
	var head: int = 0
	while head < queue.size():
		var entry: Vector2i = queue[head]
		head += 1
		for next: int in MapGeo.sea_zone_neighbors(model, entry.x):
			if seen.has(next):
				continue
			if goals.has(next):
				return entry.y + 1
			seen[next] = true
			queue.append(Vector2i(next, entry.y + 1))
	return 1 << 30
