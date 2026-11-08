class_name CapitalChoice
extends RefCounted
## Capital-choice phase (wiki: capital-choice-phase, capital-and-connectivity).
## Auto-choice during setup: sea-bound province -> coastal Class A/B/C tile ->
## convert to plains -> capital ports and roads. Pure logic, no nodes, so the
## rules run headless and are unit-tested (REQ-P3-03, REQ-P2-04).

const KIND_GREAT_POWER: int = 0
const KIND_MINOR: int = 1

const CLASS_A: int = 0
const CLASS_B: int = 1
const CLASS_C: int = 2

const NO_TILE: Vector2i = Vector2i(-1, -1)
const CAPITAL_TOWN_DEVELOPMENT: int = 4

const ERROR_NO_OWNED_PROVINCE: String = "no_owned_capital_province"
const ERROR_NO_SEA_BOUND_PROVINCE: String = "no_sea_bound_capital_province"
const ERROR_NO_CAPITAL_TILE: String = "no_capital_tile_in_province"
const ERROR_NO_COASTAL_TILE: String = "no_coastal_capital_tile_for_gp"

const ORTHO: Array[Vector2i] = [
	Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP
]


## Runs the phase for every faction, in the order given (GPs, then Minors).
static func place_all(
	model: MapModel, factions: Array[int], kind: int = KIND_GREAT_POWER
) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for faction: int in factions:
		results.append(place_capital(model, faction, kind))
	return results


## Places one faction's capital and its ports/roads. On failure the model is
## left untouched and the result carries the setup error code.
static func place_capital(
	model: MapModel, faction_id: int, kind: int = KIND_GREAT_POWER
) -> Dictionary:
	var pick: Dictionary = pick_province(model, faction_id, kind)
	var province_id: int = int(pick["province_id"])
	if province_id < 0:
		return _failure(String(pick["error"]))
	var tile: Vector2i = choose_tile(model, province_id, kind)
	if tile == NO_TILE:
		var code: String = (
			ERROR_NO_COASTAL_TILE if kind == KIND_GREAT_POWER else ERROR_NO_CAPITAL_TILE
		)
		return _failure(code)

	_clear_faction_capitals(model, faction_id)
	var converted: bool = _convert_to_plains(model, province_id, tile)
	var ports: Dictionary = {}
	var road_paths: Array = []
	if is_sea_bound(model, province_id):
		var layout: Dictionary = _layout_ports(model, province_id, tile)
		ports = layout["ports"]
		road_paths = layout["road_paths"]

	var province: Dictionary = model.province_data(province_id)
	province["capital"] = true
	province["capital_tile"] = tile
	province["ports"] = ports
	province["road_paths"] = road_paths
	if kind == KIND_GREAT_POWER:
		province["town_development"] = CAPITAL_TOWN_DEVELOPMENT
	return {
		"ok": true,
		"error": "",
		"province_id": province_id,
		"tile": tile,
		"ports": ports,
		"road_paths": road_paths,
		"converted": converted,
	}


# --- province choice --------------------------------------------------------


## Great Powers: lowest-id owned sea-bound province, or an error.
## Minors/Tribes: lowest-id owned sea-bound province, else lowest-id inland one.
static func pick_province(
	model: MapModel, faction_id: int, kind: int = KIND_GREAT_POWER
) -> Dictionary:
	var owned: Array[int] = owned_provinces(model, faction_id)
	if owned.is_empty():
		return {"province_id": -1, "error": ERROR_NO_OWNED_PROVINCE}
	var sea_bound: Array[int] = []
	var inland: Array[int] = []
	for id: int in owned:
		if is_sea_bound(model, id):
			sea_bound.append(id)
		else:
			inland.append(id)
	if not sea_bound.is_empty():
		return {"province_id": sea_bound[0], "error": ""}
	if kind == KIND_GREAT_POWER:
		return {"province_id": -1, "error": ERROR_NO_SEA_BOUND_PROVINCE}
	if not inland.is_empty():
		return {"province_id": inland[0], "error": ""}
	return {"province_id": -1, "error": ERROR_NO_SEA_BOUND_PROVINCE}


static func owned_provinces(model: MapModel, faction_id: int) -> Array[int]:
	var owned: Array[int] = []
	for province: Dictionary in model.provinces:
		if int(province["owner"]) == faction_id:
			owned.append(int(province["id"]))
	owned.sort()
	return owned


## A province is sea-bound when it has at least one P-S edge (wiki: map-topology).
static func is_sea_bound(model: MapModel, province_id: int) -> bool:
	return not sea_bound_sea_zones(model, province_id).is_empty()


## Sea zones adjacent to the province, ascending (one entry per seaboard).
static func sea_bound_sea_zones(model: MapModel, province_id: int) -> Array[int]:
	var zones: Array[int] = []
	for tile: Vector2i in model.province_tiles(province_id):
		for offset: Vector2i in ORTHO:
			var nx: int = tile.x + offset.x
			var ny: int = tile.y + offset.y
			if not model.in_bounds(nx, ny) or not model.is_sea(nx, ny):
				continue
			var zone: int = model.sea_zone_at(nx, ny)
			if zone != MapModel.NO_ID and not zones.has(zone):
				zones.append(zone)
	zones.sort()
	return zones


# --- tile choice ------------------------------------------------------------


## Class A: coastal, not adjacent to another province.
## Class B: interior, not adjacent to another province.
## Class C: everything else.
static func tile_class(model: MapModel, province_id: int, tile: Vector2i) -> int:
	if _touches_other_province(model, province_id, tile):
		return CLASS_C
	if model.is_coastal_tile(tile.x, tile.y):
		return CLASS_A
	return CLASS_B


static func choose_tile(
	model: MapModel, province_id: int, kind: int = KIND_GREAT_POWER
) -> Vector2i:
	var groups: Array = _tiles_by_class(model, province_id)
	if kind == KIND_GREAT_POWER:
		var pick_a: Vector2i = _plains_first(model, groups[CLASS_A])
		if pick_a != NO_TILE:
			return pick_a
		var coastal_c: Array = []
		for tile: Vector2i in groups[CLASS_C]:
			if model.is_coastal_tile(tile.x, tile.y):
				coastal_c.append(tile)
		return _plains_first(model, coastal_c)
	for cls: int in [CLASS_A, CLASS_B, CLASS_C]:
		var pick: Vector2i = _plains_first(model, groups[cls])
		if pick != NO_TILE:
			return pick
	return NO_TILE


## Tile lists per class, each in row-major order (y, then x).
static func _tiles_by_class(model: MapModel, province_id: int) -> Array:
	var groups: Array = [[], [], []]
	var tiles: Array[Vector2i] = []
	for tile: Vector2i in model.province_tiles(province_id):
		tiles.append(tile)
	tiles.sort_custom(_row_major)
	for tile: Vector2i in tiles:
		var cls: int = tile_class(model, province_id, tile)
		var group: Array = groups[cls]
		group.append(tile)
	return groups


static func _row_major(a: Vector2i, b: Vector2i) -> bool:
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x


## Prefers the first plains tile in the list, else its first tile.
static func _plains_first(model: MapModel, tiles: Array) -> Vector2i:
	for tile: Vector2i in tiles:
		if model.terrain_at(tile.x, tile.y) == MapModel.Terrain.PLAINS:
			return tile
	if tiles.is_empty():
		return NO_TILE
	return tiles[0]


static func _touches_other_province(
	model: MapModel, province_id: int, tile: Vector2i
) -> bool:
	for offset: Vector2i in ORTHO:
		var other: int = model.province_at(tile.x + offset.x, tile.y + offset.y)
		if other != MapModel.NO_ID and other != province_id:
			return true
	return false


## Select-then-convert: the capital tile becomes plains; its resource and
## extraction are cleared (wiki: capital-choice-phase step 3).
static func _convert_to_plains(
	model: MapModel, province_id: int, tile: Vector2i
) -> bool:
	var index: int = model.index_of(tile.x, tile.y)
	var converted: bool = model.terrain[index] != MapModel.Terrain.PLAINS
	model.terrain[index] = MapModel.Terrain.PLAINS
	model.resource[index] = MapModel.NO_ID
	var province: Dictionary = model.province_data(province_id)
	if province.has("resource_tile"):
		if Vector2i(province["resource_tile"]) == tile:
			province.erase("resource_tile")
			province["resource"] = MapModel.NO_ID
	return converted


# --- capital setup: ports and roads ----------------------------------------


## One port per seaboard. The capital tile is the port when it touches that sea
## zone; otherwise the closest seaboard tile, with a road back to the capital.
static func _layout_ports(
	model: MapModel, province_id: int, capital_tile: Vector2i
) -> Dictionary:
	var ports: Dictionary = {}
	var road_paths: Array = []
	var search: Dictionary = _bfs_from(model, province_id, capital_tile)
	for zone: int in sea_bound_sea_zones(model, province_id):
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


static func _clear_faction_capitals(model: MapModel, faction_id: int) -> void:
	for province: Dictionary in model.provinces:
		if int(province["owner"]) != faction_id:
			continue
		province["capital"] = false
		province["capital_tile"] = NO_TILE
		province["ports"] = {}
		province["road_paths"] = []
		province["town_development"] = 0


static func _failure(code: String) -> Dictionary:
	return {
		"ok": false,
		"error": code,
		"province_id": -1,
		"tile": NO_TILE,
		"ports": {},
		"road_paths": [],
		"converted": false,
	}
