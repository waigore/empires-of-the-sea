class_name MapGenerator
extends RefCounted
## Deterministic Old World map generation (wiki: tile-map-and-generation).
## Land shape -> terrain blobs -> provinces (Voronoi on land) -> sea zones ->
## resources -> ports -> faction ownership. Same seed always yields the same map.

const TILE_SIZE: int = 22
const TILES_PER_PROVINCE: int = 80
const TILES_PER_SEA_ZONE: int = 620
const MIN_PROVINCES: int = 18
const MAX_PROVINCES: int = 56
const MIN_SEA_ZONES: int = 8
const MAX_SEA_ZONES: int = 20
const MIN_ISLAND_TILES: int = 10
const BORDER_MARGIN: int = 2

const FACTION_NAMES: Array[String] = ["Spain", "England", "France", "Portugal"]
const FACTION_COLORS: Array[Color] = [
	Color(0.639, 0.169, 0.169),
	Color(0.176, 0.267, 0.435),
	Color(0.435, 0.325, 0.502),
	Color(0.243, 0.376, 0.267),
]

const PROVINCE_ROOTS: Array[String] = [
	"Cádiz", "Marcos", "Cruz", "Rica", "Cartagena", "Veracruz", "Habana", "Domingo",
	"Trujillo", "Panamá", "Juan", "Cumaná", "Maracaibo", "Coro", "Margarita", "Trinidad",
	"Santiago", "Isabel", "Fernando", "Agustín", "Miguel", "Cristóbal", "Antonio", "Lucía",
	"Elena", "Rosa", "Pedro", "Andrés", "Felipe", "Blas", "Jerónimo", "Catalina",
]

const PROVINCE_PREFIXES: Array[String] = ["San", "Santa", "Puerto", "Villa", "Nueva", "Real"]

const SEA_NAMES: Array[String] = [
	"Mar del Norte", "Golfo de las Perlas", "Mar Caribe", "Bahía de Cádiz",
	"Estrecho de Gibraltar", "Mar de las Antillas", "Golfo de México", "Océano Atlántico",
	"Mar Mediterráneo", "Canal de las Bahamas", "Mar de los Sargazos", "Golfo de Guinea",
	"Mar Tirreno", "Bahía de Vizcaya", "Canal de la Mancha", "Mar Báltico",
	"Golfo de León", "Mar de Alborán", "Mar de Azov", "Golfo de Cádiz",
]

var _rng := RandomNumberGenerator.new()


func generate(seed_value: int, p_width: int = 128, p_height: int = 84) -> MapModel:
	_rng.seed = seed_value
	var model := MapModel.new()
	model.setup(p_width, p_height)
	_build_land(model, seed_value)
	_build_terrain(model, seed_value)
	_build_provinces(model)
	_build_sea_zones(model)
	_build_resources(model)
	_build_ports(model)
	_assign_owners(model)
	_place_capitals(model)
	return model


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


func _build_terrain(model: MapModel, seed_value: int) -> void:
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

	for y in model.height:
		for x in model.width:
			var index: int = model.index_of(x, y)
			if model.terrain[index] == MapModel.Terrain.OCEAN:
				continue
			var height_value: float = elevation.get_noise_2d(float(x), float(y))
			var wet: float = moisture.get_noise_2d(float(x), float(y))
			var terrain: int = MapModel.Terrain.PLAINS
			if height_value > 0.42:
				terrain = MapModel.Terrain.MOUNTAINS
			elif height_value > 0.22:
				terrain = MapModel.Terrain.HILLS
			elif wet > 0.28:
				terrain = MapModel.Terrain.FOREST
			elif wet < -0.34:
				terrain = MapModel.Terrain.DESERT
			elif wet > 0.12 and height_value < -0.2:
				terrain = MapModel.Terrain.SWAMP
			model.terrain[index] = terrain

	for y in model.height:
		for x in model.width:
			var index: int = model.index_of(x, y)
			if model.terrain[index] != MapModel.Terrain.OCEAN:
				continue
			if _near_land(model, x, y, 2):
				model.terrain[index] = MapModel.Terrain.SHALLOW


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

	var target: int = clampi(land.size() / TILES_PER_PROVINCE, MIN_PROVINCES, MAX_PROVINCES)
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
			"name": _unique_name(used_names, PROVINCE_PREFIXES, PROVINCE_ROOTS),
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
			"name": _unique_sea_name(used_names),
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


# --- names ------------------------------------------------------------------


func _unique_name(used: Dictionary, prefixes: Array[String], roots: Array[String]) -> String:
	for _attempt in 40:
		var root: String = roots[_rng.randi_range(0, roots.size() - 1)]
		var roll: float = _rng.randf()
		var name: String = root
		if roll < 0.45:
			name = "%s %s" % [prefixes[_rng.randi_range(0, prefixes.size() - 1)], root]
		elif roll < 0.6:
			name = "Nueva %s" % root
		if not used.has(name):
			used[name] = true
			return name
	var fallback: String = "Tierra %d" % (used.size() + 1)
	used[fallback] = true
	return fallback


func _unique_sea_name(used: Dictionary) -> String:
	for name: String in SEA_NAMES:
		if not used.has(name):
			used[name] = true
			return name
	var fallback: String = "Mar %d" % (used.size() + 1)
	used[fallback] = true
	return fallback


func _shuffle(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var temp: Variant = items[i]
		items[i] = items[j]
		items[j] = temp
