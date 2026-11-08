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
const MIN_ISLAND_TILES: int = 10
const BORDER_MARGIN: int = 2
const WORLD_ATTEMPTS: int = 6

## Region generation targets (wiki: game-setup configurable values).
const OLD_WORLD_TILE_TARGET: int = 64
const NEW_WORLD_TILE_TARGET: int = 40
const OLD_WORLD_PROVINCES: Vector2i = Vector2i(24, 64)
const NEW_WORLD_PROVINCES: Vector2i = Vector2i(20, 90)

var _rng := RandomNumberGenerator.new()


## Default entry point: one Old World map (6 Great Powers + 3 Minor Nations).
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
	_build_land(model, seed_value)
	_build_terrain(model, seed_value, region_id)
	_build_provinces(model)
	_build_sea_zones(model)
	_build_resources(model)
	_build_ports(model)
	_assign_factions(model, region_id)
	_place_capitals(model, region_id)
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


# --- land shape -------------------------------------------------------------


func _build_land(model: MapModel, seed_value: int) -> void:
	var shape := FastNoiseLite.new()
	shape.seed = seed_value
	shape.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	shape.frequency = 0.017
	shape.fractal_octaves = 4
	shape.fractal_gain = 0.55

	var detail := FastNoiseLite.new()
	detail.seed = seed_value + 101
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail.frequency = 0.055
	detail.fractal_octaves = 3

	var w: int = model.width
	var h: int = model.height
	var mask := PackedByteArray()
	mask.resize(w * h)
	for y in h:
		for x in w:
			var nx: float = (float(x) / float(w - 1)) * 2.0 - 1.0
			var ny: float = (float(y) / float(h - 1)) * 2.0 - 1.0
			var falloff: float = nx * nx * 0.85 + ny * ny * 1.15
			var value: float = shape.get_noise_2d(float(x), float(y)) * 0.78
			value += detail.get_noise_2d(float(x), float(y)) * 0.22
			value -= falloff * 0.78
			value += 0.30
			mask[y * w + x] = 1 if value > 0.0 else 0

	_smooth_mask(mask, w, h, 2)
	_remove_small_regions(mask, w, h, 1, MIN_ISLAND_TILES)
	_remove_small_regions(mask, w, h, 0, MIN_ISLAND_TILES)
	_seal_border(mask, w, h, BORDER_MARGIN)

	for i in mask.size():
		model.terrain[i] = MapModel.Terrain.PLAINS if mask[i] == 1 else MapModel.Terrain.OCEAN


func _smooth_mask(mask: PackedByteArray, w: int, h: int, passes: int) -> void:
	for _pass in passes:
		var copy := mask.duplicate()
		for y in h:
			for x in w:
				var land_neighbors: int = 0
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						var nx: int = x + ox
						var ny: int = y + oy
						if nx < 0 or ny < 0 or nx >= w or ny >= h:
							continue
						land_neighbors += copy[ny * w + nx]
				mask[y * w + x] = 1 if land_neighbors >= 5 else 0


## Flips connected regions of `value` smaller than `min_size`. Sea regions that
## touch the map border are left alone (they are the ocean, not lakes).
func _remove_small_regions(
	mask: PackedByteArray, w: int, h: int, value: int, min_size: int
) -> void:
	var visited := PackedByteArray()
	visited.resize(w * h)
	visited.fill(0)
	for y in h:
		for x in w:
			var start: int = y * w + x
			if visited[start] == 1 or mask[start] != value:
				continue
			var region: Array[int] = []
			var touches_border: bool = false
			var queue: Array[int] = [start]
			visited[start] = 1
			var head: int = 0
			while head < queue.size():
				var index: int = queue[head]
				head += 1
				region.append(index)
				var cx: int = index % w
				var cy: int = index / w
				if cx == 0 or cy == 0 or cx == w - 1 or cy == h - 1:
					touches_border = true
				for offset: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
					var nx: int = cx + offset.x
					var ny: int = cy + offset.y
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var ni: int = ny * w + nx
					if visited[ni] == 0 and mask[ni] == value:
						visited[ni] = 1
						queue.append(ni)
			if region.size() < min_size and not (value == 0 and touches_border):
				for index: int in region:
					mask[index] = 1 - value


func _seal_border(mask: PackedByteArray, w: int, h: int, margin: int) -> void:
	for y in h:
		for x in w:
			if x < margin or y < margin or x >= w - margin or y >= h - margin:
				mask[y * w + x] = 0


# --- terrain ----------------------------------------------------------------


func _build_terrain(model: MapModel, seed_value: int, region_id: int) -> void:
	var elevation := FastNoiseLite.new()
	elevation.seed = seed_value + 7
	elevation.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	elevation.frequency = 0.045
	elevation.fractal_octaves = 3

	var moisture := FastNoiseLite.new()
	moisture.seed = seed_value + 23
	moisture.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	moisture.frequency = 0.038
	moisture.fractal_octaves = 3

	var new_world: bool = region_id == FactionCatalog.NEW_WORLD
	for y in model.height:
		for x in model.width:
			var index: int = model.index_of(x, y)
			if model.terrain[index] == MapModel.Terrain.OCEAN:
				continue
			var height_value: float = elevation.get_noise_2d(float(x), float(y))
			var wet: float = moisture.get_noise_2d(float(x), float(y))
			var terrain: int = _pick_terrain(height_value, wet, new_world)
			model.terrain[index] = terrain

	for y in model.height:
		for x in model.width:
			var index: int = model.index_of(x, y)
			if model.terrain[index] != MapModel.Terrain.OCEAN:
				continue
			if _near_land(model, x, y, 2):
				model.terrain[index] = MapModel.Terrain.SHALLOW


## Old World keeps temperate blobs; the New World runs wetter and hotter, with
## more forest and marsh (wiki: tile-map-and-generation § Terrain by region).
static func _pick_terrain(height_value: float, wet: float, new_world: bool) -> int:
	if new_world:
		if height_value > 0.46:
			return MapModel.Terrain.MOUNTAINS
		if height_value > 0.26:
			return MapModel.Terrain.HILLS
		if wet > 0.10:
			return MapModel.Terrain.FOREST
		if wet < -0.40:
			return MapModel.Terrain.DESERT
		if wet > -0.06:
			return MapModel.Terrain.SWAMP
		return MapModel.Terrain.PLAINS
	if height_value > 0.42:
		return MapModel.Terrain.MOUNTAINS
	if height_value > 0.22:
		return MapModel.Terrain.HILLS
	if wet > 0.28:
		return MapModel.Terrain.FOREST
	if wet < -0.34:
		return MapModel.Terrain.DESERT
	if wet > 0.12 and height_value < -0.2:
		return MapModel.Terrain.SWAMP
	return MapModel.Terrain.PLAINS


func _near_land(model: MapModel, x: int, y: int, radius: int) -> bool:
	for oy in range(-radius, radius + 1):
		for ox in range(-radius, radius + 1):
			if model.is_land(x + ox, y + oy):
				return true
	return false


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
	var tile_target: int = NEW_WORLD_TILE_TARGET if new_world else OLD_WORLD_TILE_TARGET
	var bounds: Vector2i = NEW_WORLD_PROVINCES if new_world else OLD_WORLD_PROVINCES
	var target: int = clampi(land.size() / tile_target, bounds.x, bounds.y)
	var seeds: Array[Vector2i] = _farthest_point_seeds(model, land, target, true)
	_grow_regions(model, seeds, true)

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
			if model.is_coastal_tile(tile.x, tile.y):
				coastal = true
				break
		model.provinces.append({
			"id": id,
			"name": MapNaming.province_name(used_names, model.region_id, _rng),
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


func _farthest_point_seeds(
	model: MapModel, candidates: Array[Vector2i], count: int, land_only: bool
) -> Array[Vector2i]:
	var seeds: Array[Vector2i] = [candidates[_rng.randi_range(0, candidates.size() - 1)]]
	while seeds.size() < count:
		var distances: PackedInt32Array = _bfs_distances(model, seeds, land_only)
		var best: Vector2i = seeds[0]
		var best_distance: int = -1
		for tile: Vector2i in candidates:
			var distance: int = distances[model.index_of(tile.x, tile.y)]
			if distance > best_distance:
				best_distance = distance
				best = tile
		if best_distance <= 0:
			break
		seeds.append(best)
	return seeds


func _bfs_distances(
	model: MapModel, sources: Array[Vector2i], land_only: bool
) -> PackedInt32Array:
	var distances := PackedInt32Array()
	distances.resize(model.width * model.height)
	distances.fill(-1)
	var queue: Array[Vector2i] = []
	for source: Vector2i in sources:
		distances[model.index_of(source.x, source.y)] = 0
		queue.append(source)
	var head: int = 0
	while head < queue.size():
		var tile: Vector2i = queue[head]
		head += 1
		var distance: int = distances[model.index_of(tile.x, tile.y)]
		for offset: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var nx: int = tile.x + offset.x
			var ny: int = tile.y + offset.y
			if not model.in_bounds(nx, ny):
				continue
			var index: int = model.index_of(nx, ny)
			if distances[index] != -1:
				continue
			if land_only and not model.is_land(nx, ny):
				continue
			if not land_only and not model.is_sea(nx, ny):
				continue
			distances[index] = distance + 1
			queue.append(Vector2i(nx, ny))
	return distances


func _grow_regions(model: MapModel, seeds: Array[Vector2i], land_only: bool) -> void:
	var queue: Array[Vector2i] = []
	for id in seeds.size():
		var seed_tile: Vector2i = seeds[id]
		if land_only:
			model.province[model.index_of(seed_tile.x, seed_tile.y)] = id
		else:
			model.sea_zone[model.index_of(seed_tile.x, seed_tile.y)] = id
		queue.append(seed_tile)
	_shuffle(queue)

	var head: int = 0
	while head < queue.size():
		var tile: Vector2i = queue[head]
		head += 1
		var index: int = model.index_of(tile.x, tile.y)
		var id: int = model.province[index] if land_only else model.sea_zone[index]
		var offsets: Array[Vector2i] = [
			Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP
		]
		_shuffle(offsets)
		for offset: Vector2i in offsets:
			var nx: int = tile.x + offset.x
			var ny: int = tile.y + offset.y
			if not model.in_bounds(nx, ny):
				continue
			var neighbor: int = model.index_of(nx, ny)
			if land_only:
				if model.is_land(nx, ny) and model.province[neighbor] == MapModel.NO_ID:
					model.province[neighbor] = id
					queue.append(Vector2i(nx, ny))
			else:
				if model.is_sea(nx, ny) and model.sea_zone[neighbor] == MapModel.NO_ID:
					model.sea_zone[neighbor] = id
					queue.append(Vector2i(nx, ny))


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
	var seeds: Array[Vector2i] = _farthest_point_seeds(model, sea, target, false)
	_grow_regions(model, seeds, false)

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
			"name": MapNaming.sea_name(used_names, model.region_id),
			"tiles": tiles,
			"center": sum / float(tiles.size()) + Vector2(0.5, 0.5),
			"area": tiles.size(),
		})


# --- resources, ports, owners ----------------------------------------------


static func resource_table() -> Array[Dictionary]:
	var forest: Array = [MapModel.Terrain.FOREST]
	var hills: Array = [MapModel.Terrain.HILLS]
	var peaks: Array = [MapModel.Terrain.MOUNTAINS]
	var plains: Array = [MapModel.Terrain.PLAINS]
	var swamp: Array = [MapModel.Terrain.SWAMP]
	var table: Array[Dictionary] = [
		{"name": "Timber", "icon": "tree", "commodity": "timber", "terrain": forest},
		{"name": "Iron", "icon": "ore", "commodity": "iron", "terrain": hills + peaks},
		{"name": "Coal", "icon": "ore", "commodity": "coal", "terrain": hills},
		{"name": "Gold", "icon": "coin", "commodity": "gold", "terrain": peaks},
		{"name": "Grain", "icon": "wheat", "commodity": "grain", "terrain": plains},
		{"name": "Wool", "icon": "wheat", "commodity": "wool", "terrain": plains + hills},
		{"name": "Horses", "icon": "wheat", "commodity": "horses", "terrain": plains},
		{"name": "Meat", "icon": "wheat", "commodity": "meat", "terrain": plains + hills},
		{"name": "Tin", "icon": "ore", "commodity": "tin", "terrain": swamp},
	]
	return table


static func resource_info(index: int) -> Dictionary:
	var table: Array[Dictionary] = resource_table()
	if index < 0 or index >= table.size():
		return {}
	return table[index]


func _build_resources(model: MapModel) -> void:
	ResourceSeeder.seed_resources(model, resource_table(), _rng)


func _build_ports(model: MapModel) -> void:
	for province: Dictionary in model.provinces:
		if not province["coastal"]:
			continue
		var best: Vector2i = Vector2i(-1, -1)
		var best_score: int = -1
		for tile: Vector2i in province["tiles"]:
			if not model.is_coastal_tile(tile.x, tile.y):
				continue
			var score: int = 0
			for offset: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
				if model.is_sea(tile.x + offset.x, tile.y + offset.y):
					score += 1
			if score > best_score:
				best_score = score
				best = tile
		province["port_tile"] = best


## Region ownership (wiki: game-setup § GP / Minor Nation / Tribe assignment).
## The rules module grows contiguous territories from sea-bound seeds; here we
## only pick which faction roster belongs to the region and record failures.
func _assign_factions(model: MapModel, region_id: int) -> void:
	var report: Dictionary
	if region_id == FactionCatalog.NEW_WORLD:
		report = TerritoryAssignment.assign_new_world(
			model, FactionCatalog.tribe_ids()
		)
	else:
		report = TerritoryAssignment.assign_old_world(
			model, FactionCatalog.great_power_ids(), FactionCatalog.minor_ids()
		)
	if not bool(report.get("ok", false)):
		model.setup_errors.append(String(report.get("error", "assignment_failed")))


## Capital-choice phase (wiki: capital-choice-phase). Great Powers follow the
## sea-bound/coastal rule; Minor Nations and Tribes are assigned any owned
## province during setup.
func _place_capitals(model: MapModel, region_id: int) -> void:
	if region_id == FactionCatalog.NEW_WORLD:
		CapitalChoice.place_all(model, FactionCatalog.tribe_ids(), CapitalChoice.KIND_MINOR)
		return
	CapitalChoice.place_all(
		model, FactionCatalog.great_power_ids(), CapitalChoice.KIND_GREAT_POWER
	)
	CapitalChoice.place_all(
		model, FactionCatalog.minor_ids(), CapitalChoice.KIND_MINOR
	)


# --- names ------------------------------------------------------------------


func _shuffle(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var temp: Variant = items[i]
		items[i] = items[j]
		items[j] = temp
