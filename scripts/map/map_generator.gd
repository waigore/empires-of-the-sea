class_name MapGenerator
extends RefCounted
## Deterministic per-region map generation (wiki: tile-map-and-generation).
## Land shape -> terrain blobs -> provinces (Voronoi on land) -> sea zones ->
## resources -> ports -> faction ownership -> capitals. Same seed always yields
## the same map. A world is one map per region joined by warp zones.

const TILE_SIZE: int = 22
const TILES_PER_SEA_ZONE: int = 620
const MIN_SEA_ZONES: int = 8
const MAX_SEA_ZONES: int = 20
const WORLD_ATTEMPTS: int = 6

## Fixed political map (wiki: naming § default ruleset, advanced-starts § locked
## full-init profile: 60 Old World and 30 New World provinces shared by
## 6 Great Powers + 6 Minor Nations and 10 Tribes). Map size changes the tiles
## per province, not how many parties hold the chart.
const OLD_WORLD_PROVINCES: int = 60
const NEW_WORLD_PROVINCES: int = 30

var _rng := RandomNumberGenerator.new()


## Default entry point: one Old World map (6 Great Powers + 6 Minor Nations).
func generate(seed_value: int, p_width: int = 128, p_height: int = 84) -> MapModel:
	return generate_region(seed_value, FactionCatalog.OLD_WORLD, p_width, p_height)


func generate_region(
	seed_value: int, region_id: int, p_width: int, p_height: int
) -> MapModel:
	_rng.seed = seed_value
	var model := MapModel.new()
	model.setup(p_width, p_height)
	model.region_id = region_id
	model.region_key = FactionCatalog.region_key(region_id)
	model.faction_ids = FactionCatalog.ids_in_region(region_id)
	MapLandform.build(model, seed_value, region_id)
	_build_provinces(model)
	_build_sea_zones(model)
	_build_resources(model)
	_build_ports(model)
	_assign_factions(model, region_id)
	_place_capitals(model, region_id)
	_assign_town_tiles(model)
	_name_provinces(model)
	return model


## Two-region world, regenerated with bumped seeds while ownership is infeasible
## (wiki: game-setup § Tribe assignment regen-until-pass).
func generate_world(seed_value: int, p_width: int = 128, p_height: int = 84) -> WorldMap:
	var new_width: int = maxi(48, int(round(float(p_width) * 0.88)))
	var new_height: int = maxi(36, int(round(float(p_height) * 0.9)))
	var world := WorldMap.new()
	var old_world: MapModel = null
	var new_world: MapModel = null
	for attempt in WORLD_ATTEMPTS:
		var bump: int = attempt * 104729
		old_world = generate_region(
			seed_value + bump, FactionCatalog.OLD_WORLD, p_width, p_height
		)
		new_world = generate_region(
			seed_value + bump + 7919, FactionCatalog.NEW_WORLD, new_width, new_height
		)
		if old_world.setup_errors.is_empty() and new_world.setup_errors.is_empty():
			break
	world.add_region(old_world)
	world.add_region(new_world)
	world.warp_links = WorldMap.pair_warp_zones(world.regions)
	return world


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

	var new_world: bool = model.region_id == FactionCatalog.NEW_WORLD
	var wanted: int = NEW_WORLD_PROVINCES if new_world else OLD_WORLD_PROVINCES
	var target: int = mini(wanted, land.size())
	var seeds: Array[Vector2i] = MapRegions.farthest_seeds(model, land, target, true, _rng)
	MapRegions.grow(model, seeds, true, _rng)

	var buckets: Dictionary = _tile_buckets(model, land, true)
	var ids: Array = buckets.keys()
	ids.sort()
	for id: int in ids:
		var tiles: Array[Vector2i] = buckets[id]["tiles"]
		var sum: Vector2 = buckets[id]["sum"]
		var center: Vector2 = sum / float(tiles.size()) + Vector2(0.5, 0.5)
		var coastal: bool = false
		for tile: Vector2i in tiles:
			if MapGeo.is_coastal_tile(model, tile.x, tile.y):
				coastal = true
				break
		var province := ProvinceState.create(
			id,
			"",
			tiles,
			center,
			tiles.size()
		)
		province.coastal = coastal
		model.provinces.append(province)


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

	var buckets: Dictionary = _tile_buckets(model, sea, false)
	var ids: Array = buckets.keys()
	ids.sort()
	for order in ids.size():
		var id: int = int(ids[order])
		var tiles: Array[Vector2i] = buckets[id]["tiles"]
		var sum: Vector2 = buckets[id]["sum"]
		model.sea_zones.append(
			SeaZoneState.create(
				id,
				MapNaming.sea_name(order, model.region_id),
				tiles,
				sum / float(tiles.size()) + Vector2(0.5, 0.5),
				tiles.size()
			)
		)


## Groups tiles by province (land_only) or sea zone into {tiles, sum} buckets.
func _tile_buckets(model: MapModel, tiles: Array[Vector2i], land_only: bool) -> Dictionary:
	var buckets: Dictionary = {}
	for tile: Vector2i in tiles:
		var id: int = (
			model.province_at(tile.x, tile.y) if land_only
			else model.sea_zone_at(tile.x, tile.y)
		)
		if id == MapModel.NO_ID:
			continue
		if not buckets.has(id):
			buckets[id] = {"tiles": [] as Array[Vector2i], "sum": Vector2.ZERO}
		var bucket: Dictionary = buckets[id]
		var group: Array[Vector2i] = bucket["tiles"]
		group.append(tile)
		bucket["sum"] = Vector2(bucket["sum"]) + Vector2(tile)
	return buckets


# --- resources, ports, owners ----------------------------------------------


func _build_resources(model: MapModel) -> void:
	ResourceSeeder.seed_resources(model, resource_table(), _rng)


func _build_ports(model: MapModel) -> void:
	for province: ProvinceState in model.provinces:
		if not province.coastal:
			continue
		var best: Vector2i = Vector2i(-1, -1)
		var best_score: int = -1
		for tile: Vector2i in province.tiles:
			if not MapGeo.is_coastal_tile(model, tile.x, tile.y):
				continue
			var score: int = 0
			for offset: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
				if model.is_sea(tile.x + offset.x, tile.y + offset.y):
					score += 1
			if score > best_score:
				best_score = score
				best = tile
		province.port_tile = best


## Region ownership (wiki: game-setup § GP / Minor Nation / Tribe assignment).
## The rules module grows contiguous territories from sea-bound seeds; here we
## only pick which faction roster belongs to the region and record failures.
func _assign_factions(model: MapModel, region_id: int) -> void:
	var report: Dictionary
	if region_id == FactionCatalog.NEW_WORLD:
		report = TerritoryAssignment.assign_new_world(model, FactionCatalog.tribe_ids())
	else:
		report = TerritoryAssignment.assign_old_world(
			model, FactionCatalog.great_power_ids(), FactionCatalog.minor_ids()
		)
	if not bool(report.get("ok", false)):
		model.setup_errors.append(String(report.get("error", "assignment_failed")))


## Capital-choice phase (wiki: capital-choice-phase). Great Powers follow the
## sea-bound/coastal rule; Minor Nations and Tribes get any owned province.
func _place_capitals(model: MapModel, region_id: int) -> void:
	if region_id == FactionCatalog.NEW_WORLD:
		CapitalChoice.place_all(model, FactionCatalog.tribe_ids(), CapitalChoice.KIND_MINOR)
		return
	CapitalChoice.place_all(
		model, FactionCatalog.great_power_ids(), CapitalChoice.KIND_GREAT_POWER
	)
	CapitalChoice.place_all(model, FactionCatalog.minor_ids(), CapitalChoice.KIND_MINOR)


## Town per province (wiki: capital-and-connectivity § Town per province).
## The capital tile for a capital province, else the registered port, else the
## plains-preferred tile nearest the centroid (ties row then column). The town
## tile is converted to plains and never carries a resource or improvement.
func _assign_town_tiles(model: MapModel) -> void:
	for province: ProvinceState in model.provinces:
		var town: Vector2i = _town_candidate(model, province)
		if town.x < 0:
			continue
		province.town_tile = town
		if province.town_development <= 0:
			province.town_development = 1
		var index: int = model.index_of(town.x, town.y)
		if model.terrain[index] != MapModel.Terrain.PLAINS:
			model.terrain[index] = MapModel.Terrain.PLAINS
		if model.resource[index] != MapModel.NO_ID:
			model.resource[index] = MapModel.NO_ID
			if province.resource_tile == town:
				_reheadline(model, province)


func _town_candidate(model: MapModel, province: ProvinceState) -> Vector2i:
	if province.capital and province.capital_tile.x >= 0:
		return province.capital_tile
	if province.port_tile.x >= 0:
		return province.port_tile
	var plains: Array[Vector2i] = []
	var all: Array[Vector2i] = []
	for tile: Vector2i in province.tiles:
		if not model.is_land(tile.x, tile.y):
			continue
		all.append(tile)
		if model.terrain_at(tile.x, tile.y) == MapModel.Terrain.PLAINS:
			plains.append(tile)
	var pool: Array[Vector2i] = plains if not plains.is_empty() else all
	if pool.is_empty():
		return Vector2i(-1, -1)
	pool.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var left: float = Vector2(a).distance_squared_to(province.center)
		var right: float = Vector2(b).distance_squared_to(province.center)
		if is_equal_approx(left, right):
			if a.y == b.y:
				return a.x < b.x
			return a.y < b.y
		return left < right
	)
	return pool[0]


## Re-point a province's dossier headline at another resource after the town
## conversion clears the tile it used to name.
static func _reheadline(model: MapModel, province: ProvinceState) -> void:
	province.resource = MapModel.NO_ID
	province.resource_tile = Vector2i(-1, -1)
	for tile: Vector2i in province.tiles:
		var index: int = model.index_of(tile.x, tile.y)
		if model.resource[index] != MapModel.NO_ID:
			province.resource = model.resource[index]
			province.resource_tile = tile
			return


## Naming phase: needs ownership (and capitals) first, so every province draws
## from its nation's historical pool instead of a shared European pool
## (wiki: naming, factions). Capitals take their nation's capital-city name.
func _name_provinces(model: MapModel) -> void:
	var used: Dictionary = {}
	for province: ProvinceState in model.provinces:
		if not province.capital or province.owner == MapModel.NO_ID:
			continue
		var capital: String = MapNaming.capital_name(province.owner)
		if capital.is_empty() or used.has(capital):
			continue
		province.name = capital
		used[capital] = true
	for province: ProvinceState in model.provinces:
		if not province.name.is_empty():
			continue
		province.name = MapNaming.province_name(
			used, model.region_id, _rng, province.owner
		)
