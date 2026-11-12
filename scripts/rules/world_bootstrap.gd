class_name WorldBootstrap
extends RefCounted
## Setup post-pass that wires generated maps to the extraction rules
## (wiki: capital-and-connectivity § Init town roads,
## tile-map-and-generation § Great Power starting grain).
##
## The generator records capital ports and harbour roads on the province data;
## this pass turns that plan into real LandWorks state, gives every Great Power
## its four guaranteed grain farms, and makes sure those farms reach the crown.
## Pure rules: no nodes, deterministic, safe to re-run once per region.

const GRAIN_RESOURCE: int = 4
const GRAIN_FARMS: int = 4
const FARM_LEVEL: int = 1
const CAPITAL_TOWN_DEVELOPMENT: int = 4
const ORTHO: Array[Vector2i] = [
	Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP
]


static func apply(model: MapModel, works: LandWorks) -> Dictionary:
	var report: Dictionary = {
		"ports": 0,
		"roads": 0,
		"farms": 0,
		"farms_levelled": 0,
		"town_roads": 0,
		"town_development": 0,
	}
	if model == null or works == null:
		return report
	_seed_ports(model, works, report)
	_seed_roads(model, works, report)
	_seed_town_development(model, report)
	if model.region_id == FactionCatalog.OLD_WORLD:
		_seed_grain_farms(model, works, report)
	_seed_town_roads(model, works, report)
	return report


# --- capital works -----------------------------------------------------------


## Every registered seaboard port becomes a real port tile.
static func _seed_ports(model: MapModel, works: LandWorks, report: Dictionary) -> void:
	for province: ProvinceState in model.provinces:
		for raw: Variant in province.ports.values():
			var tile: Vector2i = raw
			if not model.is_land(tile.x, tile.y):
				continue
			if works.has_port(model, tile):
				continue
			works.add_port(model, tile)
			report["ports"] = int(report["ports"]) + 1


## The capital-choice roads from a seaboard port to the seat carry transport.
static func _seed_roads(model: MapModel, works: LandWorks, report: Dictionary) -> void:
	var seen: Dictionary = {}
	for province: ProvinceState in model.provinces:
		for raw: Variant in province.road_paths:
			var path: Array = raw
			for tile: Vector2i in path:
				var index: int = model.index_of(tile.x, tile.y)
				if seen.has(index):
					continue
				seen[index] = true
				works.set_transport(model, tile, LandWorks.TRANSPORT_ROAD)
				report["roads"] = int(report["roads"]) + 1


## Great Power capital provinces start at town development 4 (the map's
## generator already sets it; this keeps hand-built maps honest).
static func _seed_town_development(model: MapModel, report: Dictionary) -> void:
	for province: ProvinceState in model.provinces:
		if province.town_development <= 0:
			province.town_development = 1
			report["town_development"] = int(report["town_development"]) + 1
		if not province.capital:
			continue
		if FactionCatalog.type_of(province.owner) != FactionCatalog.Type.GREAT_POWER:
			continue
		if province.town_development == CAPITAL_TOWN_DEVELOPMENT:
			continue
		province.town_development = CAPITAL_TOWN_DEVELOPMENT
		report["town_development"] = int(report["town_development"]) + 1


# --- init town roads ---------------------------------------------------------


## Every owned town reaches its crown on owned land (wiki: capital-and-connectivity
## § Init town roads). One globally shortest path per province raises road level to
## at least 1, merged with the harbour roads above so nothing is downgraded. The
## Old World is the default wiring region: New World tribes keep their towns
## unlinked until a crown builds roads to them.
static func _seed_town_roads(
	model: MapModel, works: LandWorks, report: Dictionary
) -> void:
	if model.region_id != FactionCatalog.OLD_WORLD:
		return
	for faction: int in FactionCatalog.ids_in_region(model.region_id):
		var seat: int = capital_province(model, faction)
		if seat < 0:
			continue
		var capital: Vector2i = model.capital_tile_of(seat)
		if capital.x < 0:
			continue
		for province: ProvinceState in model.provinces:
			if province.owner != faction:
				continue
			var town: Vector2i = province.town_tile
			if town.x < 0 or town == capital:
				continue
			var path: Array[Vector2i] = _path(model, faction, capital, town)
			if path.size() < 2:
				continue
			for tile: Vector2i in path:
				if works.transport_at(model, tile) < LandWorks.TRANSPORT_ROAD:
					works.set_transport(model, tile, LandWorks.TRANSPORT_ROAD)
			province.road_paths.append(path)
			report["town_roads"] = int(report["town_roads"]) + 1


# --- guaranteed grain --------------------------------------------------------


## Four grain tiles, improvement 1, nearest the capital, wired by road. Grain
## grows on plains only (wiki: resource-terrain-region-rules § Table), so a
## capital province too thin in plains has its remaining farm sites levelled to
## plains rather than seeded with a crop its ground cannot carry — the same
## select-then-convert the town assignment already uses.
static func _seed_grain_farms(
	model: MapModel, works: LandWorks, report: Dictionary
) -> void:
	for faction: int in FactionCatalog.great_power_ids():
		var province_id: int = capital_province(model, faction)
		if province_id < 0:
			continue
		var capital: Vector2i = model.capital_tile_of(province_id)
		if capital.x < 0:
			continue
		var placed: int = 0
		var legal: Array = grain_terrains()
		for tile: Vector2i in farm_candidates(model, province_id, capital):
			if placed >= GRAIN_FARMS:
				break
			var index: int = model.index_of(tile.x, tile.y)
			if not legal.has(model.terrain_at(tile.x, tile.y)):
				model.terrain[index] = MapModel.Terrain.PLAINS
				report["farms_levelled"] = int(report.get("farms_levelled", 0)) + 1
			model.resource[index] = GRAIN_RESOURCE
			_sync_headline(model, province_id, tile)
			works.set_improvement(model, tile, FARM_LEVEL)
			_connect(model, works, province_id, faction, capital, tile)
			placed += 1
		report["farms"] = int(report["farms"]) + placed


## Terrains that may legally carry the bootstrap grain, read from the map's own
## resource catalog so the ruleset table has one home (wiki:
## resource-terrain-region-rules § Table — grain is Old World plains).
static func grain_terrains() -> Array:
	return MapGenerator.resource_info(GRAIN_RESOURCE).get("terrain", []) as Array


static func may_host_grain(model: MapModel, tile: Vector2i) -> bool:
	return grain_terrains().has(model.terrain_at(tile.x, tile.y))


## Keep the province dossier's headline resource honest when a bootstrap farm
## replaces the tile it pointed at.
static func _sync_headline(model: MapModel, province_id: int, tile: Vector2i) -> void:
	var province: ProvinceState = model.province_data(province_id)
	if province == null or not province.has_resource_tile():
		return
	if province.resource_tile == tile:
		province.resource = GRAIN_RESOURCE


## The faction's seat as {province, tile}; both read -1 / (-1, -1) when this
## region holds no capital for the faction (a colony or a foreign shore).
static func capital_seat(model: MapModel, faction: int) -> Dictionary:
	var province: int = capital_province(model, faction)
	return {"province": province, "tile": model.capital_tile_of(province)}


## The faction's capital province in this region, or -1.
static func capital_province(model: MapModel, faction: int) -> int:
	for province: ProvinceState in model.provinces:
		if province.owner == faction and province.capital:
			return province.id
	return MapModel.NO_ID


## Eligible farm sites, nearest the seat first (ties: lower y, then lower x).
## The capital and the province town are never eligible, and ground that can
## legally carry grain comes first; the rest is a fallback that the seeding pass
## levels to plains, so a thin capital province still gets its four farms
## (wiki: tile-map-and-generation § Great Power starting grain).
static func farm_candidates(
	model: MapModel, province_id: int, capital: Vector2i
) -> Array[Vector2i]:
	var host: Array[Vector2i] = []
	var levelled: Array[Vector2i] = []
	var legal: Array = grain_terrains()
	var province: ProvinceState = model.province_data(province_id)
	var town: Vector2i = (
		province.town_tile if province != null else Vector2i(-1, -1)
	)
	for tile: Vector2i in model.province_tiles(province_id):
		if tile == capital or tile == town:
			continue
		if not model.is_land(tile.x, tile.y):
			continue
		if legal.has(model.terrain_at(tile.x, tile.y)):
			host.append(tile)
		else:
			levelled.append(tile)
	host.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _nearest(a, b, capital)
	)
	levelled.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _nearest(a, b, capital)
	)
	var result: Array[Vector2i] = host
	result.append_array(levelled)
	return result


static func _nearest(a: Vector2i, b: Vector2i, origin: Vector2i) -> bool:
	var da: int = absi(a.x - origin.x) + absi(a.y - origin.y)
	var db: int = absi(b.x - origin.x) + absi(b.y - origin.y)
	if da != db:
		return da < db
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x


# --- roads to the farms ------------------------------------------------------


## Shortest owned-land path from the capital to a farm; every tile on it gains a
## road so the estate satisfies the road rule.
static func _connect(
	model: MapModel,
	works: LandWorks,
	province_id: int,
	faction: int,
	capital: Vector2i,
	target: Vector2i
) -> void:
	var path: Array[Vector2i] = _path(model, faction, capital, target)
	if path.is_empty():
		return
	for tile: Vector2i in path:
		works.set_transport(model, tile, LandWorks.TRANSPORT_ROAD)
	var province: ProvinceState = model.province_data(province_id)
	if province != null:
		province.road_paths.append(path)


## Breadth-first walk over land the faction owns; returns [] when unreachable.
static func _path(
	model: MapModel, faction: int, start: Vector2i, goal: Vector2i
) -> Array[Vector2i]:
	if start == goal:
		return [start]
	var parent: Dictionary = {}
	var seen: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	while head < queue.size():
		var tile: Vector2i = queue[head]
		head += 1
		for offset: Vector2i in ORTHO:
			var next := Vector2i(tile.x + offset.x, tile.y + offset.y)
			if seen.has(next) or not model.in_bounds(next.x, next.y):
				continue
			if not model.is_land(next.x, next.y):
				continue
			var province: int = model.province_at(next.x, next.y)
			if model.province_owner(province) != faction:
				continue
			parent[next] = tile
			if next == goal:
				return _rebuild(parent, start, goal)
			seen[next] = true
			queue.append(next)
	var empty: Array[Vector2i] = []
	return empty


static func _rebuild(
	parent: Dictionary, start: Vector2i, goal: Vector2i
) -> Array[Vector2i]:
	var path: Array[Vector2i] = [goal]
	var current: Vector2i = goal
	var guard: int = 0
	while current != start and guard < 4096:
		if not parent.has(current):
			var empty: Array[Vector2i] = []
			return empty
		current = parent[current]
		path.append(current)
		guard += 1
	path.reverse()
	return path
