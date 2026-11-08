class_name MapRegions
extends RefCounted
## Farthest-point seeds and flood growth for provinces and sea zones.
## `rng` is the generator's generator, so seed order stays unchanged.


static func farthest_seeds(
	model: MapModel,
	candidates: Array[Vector2i],
	count: int,
	land_only: bool,
	rng: RandomNumberGenerator,
) -> Array[Vector2i]:
	var seeds: Array[Vector2i] = [candidates[rng.randi_range(0, candidates.size() - 1)]]
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


static func grow(
	model: MapModel,
	seeds: Array[Vector2i],
	land_only: bool,
	rng: RandomNumberGenerator,
) -> void:
	var queue: Array[Vector2i] = []
	for id in seeds.size():
		var seed_tile: Vector2i = seeds[id]
		if land_only:
			model.province[model.index_of(seed_tile.x, seed_tile.y)] = id
		else:
			model.sea_zone[model.index_of(seed_tile.x, seed_tile.y)] = id
		queue.append(seed_tile)
	_shuffle(queue, rng)

	var head: int = 0
	while head < queue.size():
		var tile: Vector2i = queue[head]
		head += 1
		var index: int = model.index_of(tile.x, tile.y)
		var id: int = model.province[index] if land_only else model.sea_zone[index]
		var offsets: Array[Vector2i] = [
			Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP,
		]
		_shuffle(offsets, rng)
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
			elif model.is_sea(nx, ny) and model.sea_zone[neighbor] == MapModel.NO_ID:
				model.sea_zone[neighbor] = id
				queue.append(Vector2i(nx, ny))


static func _bfs_distances(
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


static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var temp: Variant = items[i]
		items[i] = items[j]
		items[j] = temp
