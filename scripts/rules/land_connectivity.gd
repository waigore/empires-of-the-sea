class_name LandConnectivity
extends RefCounted
## Tile-level extraction connectivity (wiki: capital-and-connectivity).
## Resolves the Road rule (on or beside a contiguous road/rail/port path to the
## capital) and the Town rule (4-adjacent to a connected town), plus the path
## transport cap: the bottleneck of the best path, taking the maximum when
## several paths exist. Pure rules; Extraction and the estates ledger share it.

const NEIGHBORS: Array[Vector2i] = [
	Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP
]
## The capital tile is connected by definition and carries a full town/port.
const CAPITAL_TRANSPORT: int = 4


## Returns {tiles: index -> {transport, road, town}, towns: province -> index,
## town_port_connected: province -> bool}.
static func resolve(
	model: MapModel, works: LandWorks, owner: int, capital_tile: Vector2i
) -> Dictionary:
	var tiles: Dictionary = {}
	var towns: Dictionary = {}
	var town_ports: Dictionary = {}
	var result: Dictionary = {
		"tiles": tiles, "towns": towns, "town_port_connected": town_ports,
	}
	if model == null or works == null or owner < 0:
		return result
	var owned: Dictionary = model.ownership.owned_indices(model, owner)
	if owned.is_empty():
		return result
	var best: Dictionary = {}
	var queue: Array[Vector2i] = []
	_seed(model, works, owned, capital_tile, best, queue)
	_spread(model, works, owned, best, queue)
	for raw: Variant in best.keys():
		tiles[int(raw)] = {
			"transport": int(best[raw]), "road": true, "town": false,
		}
	_edges(model, owned, best, tiles)
	_town_rule(model, works, owner, capital_tile, owned, tiles, towns, town_ports)
	return result


## Town-connected tiles in one province: 4-adjacent to the town, or reached
## along a path of province tiles with transport >= 1 (wiki: stockpiles and
## production § town manufacturing bonus).
static func town_connected(
	model: MapModel, works: LandWorks, province_id: int, town_index: int
) -> Dictionary:
	var connected: Dictionary = {}
	if model == null or works == null or province_id < 0 or town_index < 0:
		return connected
	var town: Vector2i = _tile_of(model, town_index)
	connected[town_index] = true
	var queue: Array[Vector2i] = [town]
	var head: int = 0
	while head < queue.size():
		var tile: Vector2i = queue[head]
		head += 1
		# Leaving the town may step onto any province tile; afterwards the path
		# must carry transport so it stays a town road.
		if tile != town and _transport(model, works, tile) < 1:
			continue
		for offset: Vector2i in NEIGHBORS:
			var next: Vector2i = tile + offset
			if not model.in_bounds(next.x, next.y):
				continue
			if model.province_at(next.x, next.y) != province_id:
				continue
			var index: int = model.index_of(next.x, next.y)
			if connected.has(index):
				continue
			connected[index] = true
			queue.append(next)
	return connected


## Yield cap from town development for one connected tile (wiki: extraction
## formula and town development cap). Road-connected non-capital tiles are not
## limited; a port town connected to the capital limits its town-connected tiles.
static func town_cap_for(
	model: MapModel, resolved: Dictionary, province_id: int, index: int
) -> int:
	var province: ProvinceState = model.province_data(province_id)
	if province == null or province.town_development <= 0:
		return LandWorks.MAX_IMPROVEMENT
	var level: int = province.town_development
	if province.capital:
		return level
	var entry: Dictionary = (resolved.get("tiles", {}) as Dictionary).get(index, {})
	if bool(entry.get("road", false)):
		return LandWorks.MAX_IMPROVEMENT
	var ports: Dictionary = resolved.get("town_port_connected", {}) as Dictionary
	if bool(entry.get("town", false)) and bool(ports.get(province_id, false)):
		return level
	return LandWorks.MAX_IMPROVEMENT


# --- road rule --------------------------------------------------------------


static func _seed(
	model: MapModel,
	works: LandWorks,
	owned: Dictionary,
	capital_tile: Vector2i,
	best: Dictionary,
	queue: Array[Vector2i]
) -> void:
	if capital_tile.x >= 0:
		var capital_index: int = model.index_of(capital_tile.x, capital_tile.y)
		if owned.has(capital_index):
			_raise(model, best, queue, capital_tile, CAPITAL_TRANSPORT)
	for raw: Variant in works.ports.keys():
		var index: int = int(raw)
		if owned.has(index):
			_raise(model, best, queue, _tile_of(model, index), CAPITAL_TRANSPORT)


## Maximise the bottleneck: a tile's path cap can only improve, so re-queue it
## whenever a better route reaches it.
static func _spread(
	model: MapModel, works: LandWorks, owned: Dictionary, best: Dictionary,
	queue: Array[Vector2i]
) -> void:
	var head: int = 0
	while head < queue.size():
		var tile: Vector2i = queue[head]
		head += 1
		var index: int = model.index_of(tile.x, tile.y)
		var cap: int = int(best.get(index, 0))
		for offset: Vector2i in NEIGHBORS:
			var next: Vector2i = tile + offset
			if not model.in_bounds(next.x, next.y):
				continue
			var next_index: int = model.index_of(next.x, next.y)
			if not owned.has(next_index):
				continue
			var transport: int = _transport(model, works, next)
			if transport < 1:
				continue
			var reached: int = mini(cap, transport)
			if reached > int(best.get(next_index, 0)):
				_raise(model, best, queue, next, reached)


## Tiles beside the network are "on or next to" a road and take its cap.
static func _edges(
	model: MapModel, owned: Dictionary, best: Dictionary, tiles: Dictionary
) -> void:
	for raw: Variant in owned.keys():
		var index: int = int(raw)
		if best.has(index):
			continue
		var tile: Vector2i = _tile_of(model, index)
		var cap: int = 0
		for offset: Vector2i in NEIGHBORS:
			var next: Vector2i = tile + offset
			if not model.in_bounds(next.x, next.y):
				continue
			cap = maxi(cap, int(best.get(model.index_of(next.x, next.y), 0)))
		if cap > 0:
			tiles[index] = {"transport": cap, "road": true, "town": false}


# --- town rule --------------------------------------------------------------


static func _town_rule(
	model: MapModel,
	works: LandWorks,
	owner: int,
	capital_tile: Vector2i,
	owned: Dictionary,
	tiles: Dictionary,
	towns: Dictionary,
	town_ports: Dictionary
) -> void:
	for province: ProvinceState in model.provinces:
		if province.owner != owner:
			continue
		var town: Vector2i = ImprovementSystem.town_tile(
			model, works, province.id, capital_tile
		)
		if town.x < 0:
			continue
		var town_index: int = model.index_of(town.x, town.y)
		towns[province.id] = town_index
		if not tiles.has(town_index):
			continue
		town_ports[province.id] = works.has_port(model, town)
		(tiles[town_index] as Dictionary)["town"] = true
		var cap: int = int((tiles[town_index] as Dictionary).get("transport", 1))
		for offset: Vector2i in NEIGHBORS:
			var next: Vector2i = town + offset
			if not model.in_bounds(next.x, next.y):
				continue
			var index: int = model.index_of(next.x, next.y)
			if not owned.has(index):
				continue
			if tiles.has(index):
				(tiles[index] as Dictionary)["town"] = true
			else:
				tiles[index] = {
					"transport": maxi(cap, 1), "road": false, "town": true,
				}


# --- helpers ----------------------------------------------------------------


static func _raise(
	model: MapModel, best: Dictionary, queue: Array[Vector2i], tile: Vector2i,
	cap: int
) -> void:
	var index: int = model.index_of(tile.x, tile.y)
	if cap <= int(best.get(index, 0)):
		return
	best[index] = cap
	queue.append(tile)


static func _transport(model: MapModel, works: LandWorks, tile: Vector2i) -> int:
	if works.has_port(model, tile):
		return LandWorks.TRANSPORT_RAIL
	return works.transport_at(model, tile)


static func _tile_of(model: MapModel, index: int) -> Vector2i:
	var y: int = int(float(index) / float(model.width))
	return Vector2i(index - y * model.width, y)
