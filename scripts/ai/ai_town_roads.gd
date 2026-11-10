class_name AiTownRoads
extends RefCounted
## Rival engineer policy for province towns (wiki: capital-and-connectivity
## § Town per province, § Init town roads; civilian-work-planner).
##
## Every province has one town tile, and the Town rule only connects estates
## beside a town that itself reaches the capital. This scorer walks the owned
## land from each unconnected town toward the crown's road network and offers
## the first unroaded tile on that shortest path, so an Engineer extends the
## network one legal work order at a time. Pure rules: CivilianWork validates
## every candidate before it is emitted (REQ-P2-03, REQ-P3-03).

const NEIGHBORS: Array[Vector2i] = [
	Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP
]


## Highest-scoring legal town-road order for this Engineer, or an empty
## dictionary when every owned town already reaches the network (or no legal
## step exists). `connected` is the capital network from ImprovementSystem.
static func best_candidate(
	config: AiConfig,
	model: MapModel,
	unit: CivilianState,
	works: LandWorks,
	units: Array,
	stockpile: Dictionary,
	tech_caps: Dictionary,
	tech_unlocked: Dictionary,
	context: Dictionary,
	connected: Dictionary,
	reserved: Dictionary
) -> Dictionary:
	var best: Dictionary = {}
	if config == null or model == null or unit == null or works == null:
		return best
	if connected.is_empty():
		return best
	var weight: int = config.parameter("civilian.town_road_weight")
	for province: ProvinceState in model.provinces:
		if province.owner != unit.owner:
			continue
		var town: Vector2i = ImprovementSystem.town_tile(
			model, works, province.id, CivilianState.NO_TILE
		)
		if town.x < 0 or reserved.has(town):
			continue
		if connected.has(model.index_of(town.x, town.y)):
			continue
		var step: Vector2i = _first_unroaded(
			model, works, unit.owner, town, connected
		)
		if step.x < 0 or reserved.has(step):
			continue
		var score: int = weight + province.town_level() * 10
		if province.capital:
			score += 10
		var candidate: Dictionary = _candidate(
			model, unit, "build_road", step, works, units, stockpile,
			tech_caps, tech_unlocked, context, score
		)
		best = _better(best, candidate)
	return best


## First tile without a road on the shortest owned-land path from the town to
## the capital network. Empty when no such path exists.
static func _first_unroaded(
	model: MapModel,
	works: LandWorks,
	owner: int,
	start: Vector2i,
	connected: Dictionary
) -> Vector2i:
	var path: Array[Vector2i] = _path_to_network(model, owner, start, connected)
	for tile: Vector2i in path:
		if works.transport_at(model, tile) < LandWorks.TRANSPORT_ROAD:
			return tile
	return CivilianState.NO_TILE


## Shortest 4-neighbour path over crown land from `start` to a connected tile,
## inclusive of both ends. Row-major expansion and sorted neighbours keep the
## choice deterministic.
static func _path_to_network(
	model: MapModel, owner: int, start: Vector2i, connected: Dictionary
) -> Array[Vector2i]:
	var start_index: int = model.index_of(start.x, start.y)
	var queue: Array[Vector2i] = [start]
	var parent: Dictionary = {start_index: -1}
	var head: int = 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		var index: int = model.index_of(current.x, current.y)
		if index != start_index and connected.has(index):
			return _walk_back(model, parent, current)
		for offset: Vector2i in NEIGHBORS:
			var next: Vector2i = current + offset
			if not model.in_bounds(next.x, next.y) or not model.is_land(next.x, next.y):
				continue
			if model.owner_at(next.x, next.y) != owner:
				continue
			var next_index: int = model.index_of(next.x, next.y)
			if parent.has(next_index):
				continue
			parent[next_index] = index
			queue.append(next)
	return []


static func _walk_back(
	model: MapModel, parent: Dictionary, end: Vector2i
) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var cursor: Vector2i = end
	while cursor.x >= 0:
		path.append(cursor)
		var index: int = model.index_of(cursor.x, cursor.y)
		var previous: int = int(parent.get(index, -1))
		if previous < 0:
			break
		var y: int = int(previous / model.width)
		cursor = Vector2i(previous - y * model.width, y)
	path.reverse()
	return path


## Runs the shared validation so the emitted order is exactly one the player
## could issue through CivilianWork.
static func _candidate(
	model: MapModel,
	unit: CivilianState,
	action: String,
	tile: Vector2i,
	works: LandWorks,
	units: Array,
	stockpile: Dictionary,
	tech_caps: Dictionary,
	tech_unlocked: Dictionary,
	context: Dictionary,
	score: int
) -> Dictionary:
	var roster: Array[CivilianState] = []
	roster.assign(units)
	var check: Dictionary = CivilianWork.validate(
		model, unit, action, works, roster, stockpile, null, tile, tech_caps,
		tech_unlocked, context
	)
	if not bool(check.get("ok", false)):
		return {}
	return {
		"action": action,
		"tile": tile,
		"score": score,
		"cost": check.get("cost", {}),
		"duration": int(check.get("duration", 1)),
	}


## Higher score wins; row-major tile then action name break ties, matching the
## civilian planner's own ordering.
static func _better(best: Dictionary, candidate: Dictionary) -> Dictionary:
	if candidate.is_empty():
		return best
	if best.is_empty():
		return candidate
	if int(candidate["score"]) != int(best["score"]):
		return candidate if int(candidate["score"]) > int(best["score"]) else best
	var left: Vector2i = candidate["tile"]
	var right: Vector2i = best["tile"]
	if left.y != right.y:
		return candidate if left.y < right.y else best
	if left.x != right.x:
		return candidate if left.x < right.x else best
	return candidate if String(candidate["action"]) < String(best["action"]) else best
