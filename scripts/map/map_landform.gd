class_name MapLandform
extends RefCounted
## Land mask and terrain paint for one generated map.
## Noise only — the generator's RNG is not touched, so later stages stay aligned.


const MIN_ISLAND_TILES: int = 10
const BORDER_MARGIN: int = 2


static func build(
	model: MapModel, seed_value: int, region_id: int = FactionCatalog.OLD_WORLD
) -> void:
	_apply_mask(model, seed_value)
	_paint_terrain(model, seed_value, region_id)


static func _apply_mask(model: MapModel, seed_value: int) -> void:
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


static func _smooth_mask(mask: PackedByteArray, w: int, h: int, passes: int) -> void:
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
static func _remove_small_regions(
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


static func _seal_border(mask: PackedByteArray, w: int, h: int, margin: int) -> void:
	for y in h:
		for x in w:
			if x < margin or y < margin or x >= w - margin or y >= h - margin:
				mask[y * w + x] = 0


static func _paint_terrain(model: MapModel, seed_value: int, region_id: int) -> void:
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
			model.terrain[index] = terrain_for(height_value, wet, new_world)

	for y in model.height:
		for x in model.width:
			var index: int = model.index_of(x, y)
			if model.terrain[index] != MapModel.Terrain.OCEAN:
				continue
			if _near_land(model, x, y, 2):
				model.terrain[index] = MapModel.Terrain.SHALLOW


## Old World keeps temperate blobs; the New World runs wetter and hotter, with
## more forest and marsh (wiki: tile-map-and-generation § Terrain by region).
static func terrain_for(height_value: float, wet: float, new_world: bool) -> int:
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


static func _near_land(model: MapModel, x: int, y: int, radius: int) -> bool:
	for oy in range(-radius, radius + 1):
		for ox in range(-radius, radius + 1):
			if model.is_land(x + ox, y + oy):
				return true
	return false
