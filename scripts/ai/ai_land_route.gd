class_name AiLandRoute
extends RefCounted
## Land pathing shared by the rival civilian planners (explorer, merchant, spy).
## A civilian walks one orthogonal land tile a turn, so a planner asks for the
## next step toward a goal and lets CivilianMovement own legality — the land
## counterpart of [AiSeaRoute] (wiki: civilian-work-planner § Relations;
## REQ-P2-03, REQ-P3-03). Pure rules: state in, step out.

## The order a march is emitted as, so every planner names a move one way.
const KIND_MOVE: String = "move"
## A distance no walk reaches: a sparse field reads it as "no route from here".
const UNREACHABLE: int = 1 << 30


## One legal march toward `goal`, or {} when the unit may not move or the goal is
## unset. The lower tile breaks a tie, so the same state always walks the same
## way.
static func step_toward(
	model: MapModel, unit: CivilianState, goal: Vector2i,
	view: VisibilityModel = null
) -> Dictionary:
	if model == null or unit == null or goal.x < 0:
		return {}
	var best: Dictionary = {}
	for tile: Vector2i in CivilianMovement.valid_tiles(model, unit, view):
		best = _closer(best, unit, tile, manhattan(tile, goal))
	return best


## One legal march that shortens the caller's own distance field. A Spy walks the
## cheapest charted step of a field, which a plain walk cannot see across water.
## A tile the field has no entry for is not a step.
static func step_by_field(
	model: MapModel, unit: CivilianState, field: Dictionary,
	view: VisibilityModel = null
) -> Dictionary:
	if model == null or unit == null or field.is_empty():
		return {}
	var best: Dictionary = {}
	for tile: Vector2i in CivilianMovement.valid_tiles(model, unit, view):
		var distance: int = int(field.get(tile, UNREACHABLE))
		if distance >= UNREACHABLE:
			continue
		best = _closer(best, unit, tile, distance)
	return best


## Nearest tile of `goals` to `from`; the lower tile breaks a tie, and no goal is
## [constant CivilianState.NO_TILE].
static func nearest(goals: Array[Vector2i], from: Vector2i) -> Vector2i:
	var best: Vector2i = CivilianState.NO_TILE
	var best_distance: int = UNREACHABLE
	for tile: Vector2i in goals:
		var distance: int = manhattan(tile, from)
		if distance < best_distance or (distance == best_distance and tile < best):
			best = tile
			best_distance = distance
	return best


## Tiles walked, ignoring water and province borders a caller may still enforce.
static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## Land-only breadth-first distances (in tiles) from a set of target tiles: a
## civilian walks one orthogonal land tile a turn, so open water simply has no
## entry. `UNREACHABLE` marks what the field cannot reach.
static func distance_field(model: MapModel, targets: Array) -> Dictionary:
	var distance: Dictionary = {}
	var frontier: Array[Vector2i] = []
	for raw: Variant in targets:
		var tile: Vector2i = raw
		if not model.is_land(tile.x, tile.y) or distance.has(tile):
			continue
		distance[tile] = 0
		frontier.append(tile)
	while not frontier.is_empty():
		var next: Array[Vector2i] = []
		for tile: Vector2i in frontier:
			var step: int = int(distance[tile]) + 1
			for offset: Vector2i in CivilianMovement.NEIGHBORS:
				var neighbour: Vector2i = tile + offset
				if not model.in_bounds(neighbour.x, neighbour.y):
					continue
				if not model.is_land(neighbour.x, neighbour.y) or distance.has(neighbour):
					continue
				distance[neighbour] = step
				next.append(neighbour)
		frontier = next
	return distance


## The step so far that walks least toward the goal; the lower tile wins a tie.
static func _closer(
	best: Dictionary, unit: CivilianState, tile: Vector2i, distance: int
) -> Dictionary:
	if not best.is_empty() and distance > int(best["distance"]):
		return best
	if not best.is_empty() and distance == int(best["distance"]) and tile > Vector2i(best["tile"]):
		return best
	return {"kind": KIND_MOVE, "unit_id": unit.id, "tile": tile, "distance": distance}
