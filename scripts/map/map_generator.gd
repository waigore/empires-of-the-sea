class_name MapGenerator
extends RefCounted
## Deterministic Old World map generation (wiki: tile-map-and-generation).
## Land shape -> terrain blobs -> provinces (Voronoi on land) -> sea zones ->
## resources -> ports -> faction ownership. Same seed always yields the same map.
## Land, regions, and name tables live in MapLandform, MapRegions, and MapCatalog.

const TILE_SIZE: int = 22
const TILES_PER_PROVINCE: int = 80
const TILES_PER_SEA_ZONE: int = 620
const MIN_PROVINCES: int = 18
const MAX_PROVINCES: int = 56
const MIN_SEA_ZONES: int = 8
const MAX_SEA_ZONES: int = 20

const FACTION_NAMES: Array[String] = ["Spain", "England", "France", "Portugal"]
const FACTION_COLORS: Array[Color] = [
	Color(0.639, 0.169, 0.169),
	Color(0.176, 0.267, 0.435),
	Color(0.435, 0.325, 0.502),
	Color(0.243, 0.376, 0.267),
]

var _rng := RandomNumberGenerator.new()


func generate(seed_value: int, p_width: int = 128, p_height: int = 84) -> MapModel:
	_rng.seed = seed_value
	var model := MapModel.new()
	model.setup(p_width, p_height)
	MapLandform.build(model, seed_value)
	_build_provinces(model)
	_build_sea_zones(model)
	_build_resources(model)
	_build_ports(model)
	_assign_owners(model)
	_place_capitals(model)
	return model


static func resource_table() -> Array[Dictionary]:
	return MapCatalog.resource_table()


static func resource_info(index: int) -> Dictionary:
	return MapCatalog.resource_info(index)


# --- provinces --------------------------------------------------------------


func _build_provinces(model: MapModel) -> void:
	var land: Array[Vector2i] = []
	for y in model.height:
		for x in model.width:
			if model.is_land(x, y):
				land.append(Vector2i(x, y))
	if land.is_empty():
		return

	var target: int = clampi(land.size() / TILES_PER_PROVINCE, MIN_PROVINCES, MAX_PROVINCES)
	var seeds: Array[Vector2i] = MapRegions.farthest_seeds(model, land, target, true, _rng)
	MapRegions.grow(model, seeds, true, _rng)

	var buckets: Dictionary = {}
	for tile: Vector2i in land:
		var id: int = model.province_at(tile.x, tile.y)
		if id == MapModel.NO_ID:
			continue
		if not buckets.has(id):
			buckets[id] = {"tiles": [] as Array[Vector2i], "sum": Vector2.ZERO}
		var bucket: Dictionary = buckets[id]
		var tiles: Array[Vector2i] = bucket["tiles"]
		tiles.append(tile)
		bucket["sum"] = Vector2(bucket["sum"]) + Vector2(tile)

	var used_names: Dictionary = {}
	var ids: Array = buckets.keys()
	ids.sort()
	for id: int in ids:
		var bucket: Dictionary = buckets[id]
		var tiles: Array[Vector2i] = bucket["tiles"]
		var sum: Vector2 = bucket["sum"]
		var center: Vector2 = sum / float(tiles.size()) + Vector2(0.5, 0.5)
		var coastal: bool = false
		for tile: Vector2i in tiles:
			if MapGeo.is_coastal_tile(model, tile.x, tile.y):
				coastal = true
				break
		model.provinces.append({
			"id": id,
			"name": MapCatalog.unique_province_name(_rng, used_names),
			"tiles": tiles,
			"center": center,
			"area": tiles.size(),
			"coastal": coastal,
			"port_tile": Vector2i(-1, -1),
			"owner": MapModel.NO_ID,
			"capital": false,
			"capital_tile": CapitalChoice.NO_TILE,
			"ports": {},
			"road_paths": [],
			"town_development": 0,
			"resource": MapModel.NO_ID,
			"population": 0,
		})


# --- sea zones --------------------------------------------------------------


func _build_sea_zones(model: MapModel) -> void:
	var sea: Array[Vector2i] = []
	for y in model.height:
		for x in model.width:
			if model.is_sea(x, y):
				sea.append(Vector2i(x, y))
	if sea.is_empty():
		return

	var target: int = clampi(sea.size() / TILES_PER_SEA_ZONE, MIN_SEA_ZONES, MAX_SEA_ZONES)
	var seeds: Array[Vector2i] = MapRegions.farthest_seeds(model, sea, target, false, _rng)
	MapRegions.grow(model, seeds, false, _rng)

	var buckets: Dictionary = {}
	for tile: Vector2i in sea:
		var id: int = model.sea_zone_at(tile.x, tile.y)
		if id == MapModel.NO_ID:
			continue
		if not buckets.has(id):
			buckets[id] = {"tiles": [] as Array[Vector2i], "sum": Vector2.ZERO}
		var bucket: Dictionary = buckets[id]
		var tiles: Array[Vector2i] = bucket["tiles"]
		tiles.append(tile)
		bucket["sum"] = Vector2(bucket["sum"]) + Vector2(tile)

	var used_names: Dictionary = {}
	var ids: Array = buckets.keys()
	ids.sort()
	for id: int in ids:
		var bucket: Dictionary = buckets[id]
		var tiles: Array[Vector2i] = bucket["tiles"]
		var sum: Vector2 = bucket["sum"]
		model.sea_zones.append({
			"id": id,
			"name": MapCatalog.unique_sea_name(used_names),
			"tiles": tiles,
			"center": sum / float(tiles.size()) + Vector2(0.5, 0.5),
			"area": tiles.size(),
		})


# --- resources, ports, owners ----------------------------------------------


func _build_resources(model: MapModel) -> void:
	ResourceSeeder.seed_resources(model, resource_table(), _rng)


func _build_ports(model: MapModel) -> void:
	for province: Dictionary in model.provinces:
		if not province["coastal"]:
			continue
		var best: Vector2i = Vector2i(-1, -1)
		var best_score: int = -1
		for tile: Vector2i in province["tiles"]:
			if not MapGeo.is_coastal_tile(model, tile.x, tile.y):
				continue
			var score: int = 0
			for offset: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
				if model.is_sea(tile.x + offset.x, tile.y + offset.y):
					score += 1
			if score > best_score:
				best_score = score
				best = tile
		province["port_tile"] = best


## Spreads ownership by nearest seed province. Seeds are drawn from sea-bound
## provinces so every faction can satisfy the capital-choice rule.
func _assign_owners(model: MapModel) -> void:
	if model.provinces.is_empty():
		return
	var faction_count: int = mini(FACTION_NAMES.size(), model.provinces.size())
	var eligible: Array[int] = _sea_bound_ids(model)
	if eligible.size() < faction_count:
		eligible = []
		for id in model.provinces.size():
			eligible.append(id)
	if eligible.is_empty():
		return

	var seeds: Array[int] = [eligible[_rng.randi_range(0, eligible.size() - 1)]]
	while seeds.size() < faction_count:
		var best: int = -1
		var best_distance: float = -1.0
		for id: int in eligible:
			if seeds.has(id):
				continue
			var nearest: float = INF
			for seed: int in seeds:
				nearest = minf(
					nearest,
					model.province_center(id).distance_to(model.province_center(seed))
				)
			if nearest > best_distance:
				best_distance = nearest
				best = id
		if best < 0:
			break
		seeds.append(best)

	for id in model.provinces.size():
		var nearest_owner: int = 0
		var nearest_distance: float = INF
		for faction in seeds.size():
			var distance: float = model.province_center(id).distance_to(
				model.province_center(seeds[faction])
			)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_owner = faction
		var province: Dictionary = model.provinces[id]
		province["owner"] = nearest_owner
		province["population"] = 180 + int(province["area"]) * 9 + _rng.randi_range(0, 90)


func _sea_bound_ids(model: MapModel) -> Array[int]:
	var ids: Array[int] = []
	for province: Dictionary in model.provinces:
		if CapitalChoice.is_sea_bound(model, int(province["id"])):
			ids.append(int(province["id"]))
	return ids


## Capital-choice phase (wiki: capital-choice-phase). All four crowns are Great
## Powers, so each gets the sea-bound capital rule and its ports/roads.
func _place_capitals(model: MapModel) -> void:
	var factions: Array[int] = []
	for faction in mini(FACTION_NAMES.size(), model.provinces.size()):
		factions.append(faction)
	CapitalChoice.place_all(model, factions, CapitalChoice.KIND_GREAT_POWER)
