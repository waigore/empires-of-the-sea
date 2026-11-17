class_name LandConnectivity
extends RefCounted
## Tile-level road/port extraction connectivity (wiki: capital-and-connectivity).
## Resolves the Road rule (on or beside a contiguous road/rail/port path to the
## capital) and the path transport cap: the bottleneck of the best path, taking
## the maximum when several paths exist. The Town rule — adjacent-town marks and
## town-development yield caps — lives in LandTownRule (REQ-P3-01). Pure rules;
## Extraction and the estates ledger share the resolve map.

const NEIGHBORS: Array[Vector2i] = [
	Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP
]
## The capital tile is connected by definition and carries a full town/port.
const CAPITAL_TRANSPORT: int = 4


## Returns {tiles: index -> {transport, road, town}, network: index -> transport,
## towns: province -> index, town_port_connected: province -> bool}. `network` is
## the roaded crown network itself (the tiles a crew can extend); `tiles` also
## carries the ring beside it and the Town-rule neighbours.
static func resolve(
	model: MapModel,
	works: LandWorks,
	owner: int,
	capital_tile: Vector2i,
	blockade: Blockades = null
) -> Dictionary:
	var tiles: Dictionary = {}
	var towns: Dictionary = {}
	var town_ports: Dictionary = {}
	var result: Dictionary = {
		"tiles": tiles, "network": {}, "towns": towns,
		"town_port_connected": town_ports,
	}
	if model == null or works == null or owner < 0:
		return result
	var owned: Dictionary = model.ownership.owned_indices(model, owner)
	if owned.is_empty():
		return result
	# Two networks: the one the crown's roads reach from its capital tile, and
	# the wider one a landfall port seeds abroad. Only the first makes an estate
	# "on a road to the crown", so only it exempts a tile from the town cap
	# (wiki: extraction-and-improvements § Extraction formula and town
	# development cap).
	var land: Dictionary = {}
	var land_queue: Array[Vector2i] = []
	_seed_capital(model, owned, capital_tile, land, land_queue)
	_spread(model, works, owned, land, land_queue)
	var best: Dictionary = land.duplicate()
	var queue: Array[Vector2i] = []
	_seed_ports(model, works, owned, best, queue, blockade)
	_spread(model, works, owned, best, queue)
	_grant_beside_ports(model, works, owned, best, queue, blockade)
	for raw: Variant in best.keys():
		tiles[int(raw)] = {
			"transport": int(best[raw]), "road": true, "town": false,
		}
	_edges(model, works, owned, best, land, tiles)
	LandTownRule.apply(
		model, works, owner, capital_tile, owned, tiles, towns, town_ports
	)
	result["network"] = best
	return result


## Crown-network summary for the province dossier:
## {linked, roads, distance, town}. `linked` is the province town reaching the
## capital (Road or Town rule), `roads` counts the province's road/port tiles,
## and `distance` is how many road tiles still separate an unlinked town from
## the crown network (-1 when no owned-land route exists, 0 when linked).
static func province_link(
	model: MapModel, works: LandWorks, owner: int, capital_tile: Vector2i,
	province_id: int, blockade: Blockades = null
) -> Dictionary:
	var result: Dictionary = {
		"linked": false, "roads": 0, "distance": -1,
		"town": Vector2i(-1, -1), "blockaded": false,
	}
	if model == null or works == null or province_id < 0 or owner < 0:
		return result
	var town: Vector2i = ImprovementSystem.town_tile(
		model, works, province_id, capital_tile
	)
	result["town"] = town
	if blockade != null:
		result["blockaded"] = blockade.cuts(model.region_id, province_id)
	var roads: int = 0
	for tile: Vector2i in model.province_tiles(province_id):
		if works.transport_at(model, tile) >= LandWorks.TRANSPORT_ROAD:
			roads += 1
		elif works.has_port(model, tile):
			roads += 1
	result["roads"] = roads
	if town.x < 0:
		return result
	var resolved: Dictionary = resolve(model, works, owner, capital_tile, blockade)
	if (resolved.get("tiles", {}) as Dictionary).has(model.index_of(town.x, town.y)):
		result["linked"] = true
		result["distance"] = 0
		return result
	result["distance"] = road_gap(
		model, owner, resolved.get("network", {}) as Dictionary, town
	)
	return result


## Road tiles still to lay before each owned tile reaches the crown network:
## index -> gap. 0 means the tile is on (or beside) a road already; tiles with no
## owned-land route are absent. A tile beside the network already extracts, so
## the count stops one step short. `network` is `resolve()["network"]`.
static func network_gaps(
	model: MapModel, owner: int, network: Dictionary
) -> Dictionary:
	var gaps: Dictionary = {}
	if model == null or owner < 0 or network.is_empty():
		return gaps
	var depth: Dictionary = {}
	var queue: Array[Vector2i] = []
	for raw: Variant in network.keys():
		var index: int = int(raw)
		depth[index] = 0
		gaps[index] = 0
		queue.append(_tile_of(model, index))
	var head: int = 0
	while head < queue.size():
		var tile: Vector2i = queue[head]
		head += 1
		var step: int = int(depth[model.index_of(tile.x, tile.y)]) + 1
		for offset: Vector2i in NEIGHBORS:
			var next: Vector2i = tile + offset
			if not model.in_bounds(next.x, next.y):
				continue
			if not model.is_land(next.x, next.y):
				continue
			if model.owner_at(next.x, next.y) != owner:
				continue
			var index: int = model.index_of(next.x, next.y)
			if depth.has(index):
				continue
			depth[index] = step
			gaps[index] = maxi(step - 1, 0)
			queue.append(next)
	return gaps


## Road tiles still to lay before one tile reaches the crown network; -1 when
## no owned-land route exists. Used by the province dossier.
static func road_gap(
	model: MapModel, owner: int, network: Dictionary, from: Vector2i
) -> int:
	if model == null or from.x < 0:
		return -1
	var index: int = model.index_of(from.x, from.y)
	if network.has(index):
		return 0
	return int(network_gaps(model, owner, network).get(index, -1))


# --- road rule --------------------------------------------------------------


static func _seed_capital(
	model: MapModel,
	owned: Dictionary,
	capital_tile: Vector2i,
	best: Dictionary,
	queue: Array[Vector2i]
) -> void:
	if capital_tile.x < 0:
		return
	var capital_index: int = model.index_of(capital_tile.x, capital_tile.y)
	if owned.has(capital_index):
		_raise(model, best, queue, capital_tile, CAPITAL_TRANSPORT)


## A port is a landfall: it seeds the province's own roads, but it is not a road
## to the crown, so its bare tile does not exempt its neighbours from the town
## cap (overseas provinces have no road path to the capital at all).
## A sealed harbour is no landfall: a hostile squadron holding the coast cuts the
## province's sea path, and a blockade of the capital cuts every one of them
## (wiki: capital-and-connectivity § Blockade).
static func _seed_ports(
	model: MapModel, works: LandWorks, owned: Dictionary, best: Dictionary,
	queue: Array[Vector2i], blockade: Blockades = null
) -> void:
	for raw: Variant in works.ports.keys():
		var index: int = int(raw)
		if not owned.has(index):
			continue
		if blockade != null:
			var tile: Vector2i = _tile_of(model, index)
			if blockade.cuts(model.region_id, model.province_at(tile.x, tile.y)):
				continue
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


## A tile beside a crown harbour carries the harbour's level whatever road it
## also lays: "Adjacent port tile grants level 4 to that tile" (wiki:
## extraction-and-improvements § Transport Level). Without the grant a primitive
## road laid beside a port would *replace* the adjoining cap with its own 1, so
## the Engineer's own order would cut the estate's yield.
## Only tiles the network already reaches are raised, so a bare port still leaves
## its ring to [method _edges] and the Town rule's own cap.
static func _grant_beside_ports(
	model: MapModel, works: LandWorks, owned: Dictionary, best: Dictionary,
	queue: Array[Vector2i], blockade: Blockades = null
) -> void:
	var granted: bool = true
	var guard: int = 0
	# A raised tile can carry the grant one step further along a road, so the
	# pass repeats until nothing moves (bounded: the raises are monotone).
	while granted and guard < 4:
		granted = false
		guard += 1
		for raw: Variant in works.ports.keys():
			var index: int = int(raw)
			if not owned.has(index):
				continue
			var port: Vector2i = _tile_of(model, index)
			if blockade != null and blockade.cuts(
				model.region_id, model.province_at(port.x, port.y)
			):
				continue
			for offset: Vector2i in NEIGHBORS:
				var next: Vector2i = port + offset
				if not model.in_bounds(next.x, next.y):
					continue
				var next_index: int = model.index_of(next.x, next.y)
				if not owned.has(next_index) or not best.has(next_index):
					continue
				if int(best[next_index]) >= CAPITAL_TRANSPORT:
					continue
				_raise(model, best, queue, next, CAPITAL_TRANSPORT)
				granted = true
		_spread(model, works, owned, best, queue)


## Tiles beside the network are "on or next to" a road and take its cap. The
## `road` flag means "reaches the crown along a road": true beside the capital's
## own network or beside a real road/rail tile, false beside a bare landfall port
## (that tile is Town-rule connected, so the province's town development caps it).
static func _edges(
	model: MapModel, works: LandWorks, owned: Dictionary, best: Dictionary,
	land: Dictionary, tiles: Dictionary
) -> void:
	for raw: Variant in owned.keys():
		var index: int = int(raw)
		if best.has(index):
			continue
		var tile: Vector2i = _tile_of(model, index)
		var cap: int = 0
		var road: bool = false
		for offset: Vector2i in NEIGHBORS:
			var next: Vector2i = tile + offset
			if not model.in_bounds(next.x, next.y):
				continue
			var next_index: int = model.index_of(next.x, next.y)
			if not best.has(next_index):
				continue
			cap = maxi(cap, int(best[next_index]))
			if land.has(next_index) or works.transport_at(model, next) >= 1:
				road = true
		if cap > 0:
			tiles[index] = {"transport": cap, "road": road, "town": false}


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
