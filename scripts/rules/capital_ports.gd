class_name CapitalPorts
extends RefCounted
## Capital Setup harbour maths (wiki: capital-and-connectivity § Capital Setup).
## One port per seaboard the province touches, and an ink road from every
## outlying port back to the seat. Pure rules: deterministic BFS over the
## province's own tiles, no nodes (REQ-P3-03).

const NO_TILE: Vector2i = Vector2i(-1, -1)
const ORTHO: Array[Vector2i] = [
	Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP
]


## Ports per sea zone plus the road paths that reach an outlying port.
## `zones` is the province's seaboard list, ascending (one entry per P-S edge).
static func layout(
	model: MapModel, province_id: int, capital_tile: Vector2i, zones: Array[int]
) -> Dictionary:
	var ports: Dictionary = {}
	var road_paths: Array = []
	var search: Dictionary = _bfs_from(model, province_id, capital_tile)
	for zone: int in zones:
		var port_tile: Vector2i = NO_TILE
		if _touches_zone(model, capital_tile, zone):
			port_tile = capital_tile
		else:
			port_tile = _nearest_port_tile(model, province_id, zone, search)
		if port_tile == NO_TILE:
			continue
		ports[zone] = port_tile
		if port_tile == capital_tile:
			continue
		var path: Array[Vector2i] = _path_to_capital(
			port_tile, capital_tile, search["parent"]
		)
		if not path.is_empty() and not road_paths.has(path):
			road_paths.append(path)
	return {"ports": ports, "road_paths": road_paths}


## Deterministic BFS over province tiles; 4-neighbour order matches the wiki's
## port-to-capital expansion order.
static func _bfs_from(
	model: MapModel, province_id: int, start: Vector2i
) -> Dictionary:
	var distances: Dictionary = {start: 0}
	var discovery: Dictionary = {start: 0}
	var parent: Dictionary = {}
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	var order: int = 1
	while head < queue.size():
		var tile: Vector2i = queue[head]
		head += 1
		for offset: Vector2i in ORTHO:
			var next := Vector2i(tile.x + offset.x, tile.y + offset.y)
			if model.province_at(next.x, next.y) != province_id:
				continue
			if distances.has(next):
				continue
			distances[next] = int(distances[tile]) + 1
			parent[next] = tile
			discovery[next] = order
			order += 1
			queue.append(next)
	return {"distances": distances, "discovery": discovery, "parent": parent}


static func _nearest_port_tile(
	model: MapModel, province_id: int, zone: int, search: Dictionary
) -> Vector2i:
	var distances: Dictionary = search["distances"]
	var discovery: Dictionary = search["discovery"]
	var best: Vector2i = NO_TILE
	var best_distance: int = -1
	var best_order: int = -1
	for tile: Vector2i in model.province_tiles(province_id):
		if not distances.has(tile) or not _touches_zone(model, tile, zone):
			continue
		var distance: int = int(distances[tile])
		var order: int = int(discovery[tile])
		var better: bool = distance < best_distance
		if best_distance < 0 or better or (distance == best_distance and order < best_order):
			best = tile
			best_distance = distance
			best_order = order
	return best


static func _touches_zone(model: MapModel, tile: Vector2i, zone: int) -> bool:
	for offset: Vector2i in ORTHO:
		var nx: int = tile.x + offset.x
		var ny: int = tile.y + offset.y
		if not model.in_bounds(nx, ny):
			continue
		if model.is_sea(nx, ny) and model.sea_zone_at(nx, ny) == zone:
			return true
	return false


static func _path_to_capital(
	port_tile: Vector2i, capital_tile: Vector2i, parent: Dictionary
) -> Array[Vector2i]:
	var path: Array[Vector2i] = [port_tile]
	var current: Vector2i = port_tile
	var guard: int = 0
	while current != capital_tile:
		if not parent.has(current) or guard > 4096:
			return []
		current = parent[current]
		path.append(current)
		guard += 1
	return path
