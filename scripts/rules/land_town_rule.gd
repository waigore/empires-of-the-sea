class_name LandTownRule
extends RefCounted
## Town rule for tile extraction (wiki: capital-and-connectivity; extraction-and-
## improvements § Extraction formula and town development cap). Marks tiles
## 4-adjacent to a connected town, walks town-road manufacture reach, and reads
## the yield cap town development imposes. Pure rules; LandConnectivity owns the
## road/port network and calls [method apply] after it resolves (REQ-P3-01).

const NEIGHBORS: Array[Vector2i] = [
	Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP
]


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


## Yield cap from town development for one connected tile (wiki: extraction-and-
## improvements § Extraction formula and town development cap). MAX_IMPROVEMENT
## when town development does not limit this tile at all.
static func town_cap_for(
	model: MapModel, resolved: Dictionary, province_id: int, index: int
) -> int:
	var province: ProvinceState = model.province_data(province_id)
	if province == null or province.town_development <= 0:
		return LandWorks.MAX_IMPROVEMENT
	if not town_caps_yield(model, resolved, province_id, index):
		return LandWorks.MAX_IMPROVEMENT
	return province.town_development


## True when town development limits this tile's yield: a capital province
## always caps at its town level; a non-capital estate caps only when the Town
## rule is its only link to the crown (beside a port town that reaches the
## capital), because an estate on a road path to the crown is not limited by
## town development. The reading and the yield share this one predicate.
static func town_caps_yield(
	model: MapModel, resolved: Dictionary, province_id: int, index: int
) -> bool:
	var province: ProvinceState = model.province_data(province_id)
	if province == null or province.town_development <= 0:
		return false
	if province.capital:
		return true
	if not town_caps_province(model, resolved, province_id):
		return false
	var entry: Dictionary = (resolved.get("tiles", {}) as Dictionary).get(index, {})
	return bool(entry.get("town", false)) and not bool(entry.get("road", false))


## True when town development reaches this province's town-connected estates: a
## capital province, or a province whose town tile carries a port. A town that
## merely stands beside a landfall port is inland for this rule, so nothing caps
## the estates around it (wiki: extraction-and-improvements § Extraction formula
## and town development cap).
static func town_caps_province(
	model: MapModel, resolved: Dictionary, province_id: int
) -> bool:
	var province: ProvinceState = model.province_data(province_id)
	if province == null or province.town_development <= 0:
		return false
	if province.capital:
		return true
	var ports: Dictionary = resolved.get("town_port_connected", {}) as Dictionary
	return bool(ports.get(province_id, false))


## Marks town tiles and their 4-neighbours on an already-resolved road/port
## `tiles` map, and records each owned province's town index and whether that
## town carries a port. Called from [method LandConnectivity.resolve].
static func apply(
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


static func _transport(model: MapModel, works: LandWorks, tile: Vector2i) -> int:
	if works.has_port(model, tile):
		return LandWorks.TRANSPORT_RAIL
	return works.transport_at(model, tile)


static func _tile_of(model: MapModel, index: int) -> Vector2i:
	var y: int = int(float(index) / float(model.width))
	return Vector2i(index - y * model.width, y)
