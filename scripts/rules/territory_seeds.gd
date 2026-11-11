class_name TerritorySeeds
extends RefCounted
## Seed placement for province assignment (wiki: game-setup § GP / Minor Nation /
## Tribe assignment). A faction grows from one seed, so the seeds must sit far
## apart on the land: Euclidean spacing over a coastal pool can leave one court
## boxed in a bay while its neighbour holds open country, so distance is measured
## in land hops. Pure rules, deterministic (REQ-P3-03).


## Farthest-point seeds over `pool` inside the landmass `ids` (ties: lowest id).
## `start` rotates the first pick so a retried layout seeds a different province.
static func pick(
	model: MapModel, ids: Array, pool: Array, count: int, start: int = 0
) -> Array[int]:
	var seeds: Array[int] = []
	if pool.is_empty() or count <= 0:
		return seeds
	var candidates: Array[int] = []
	for raw: Variant in pool:
		candidates.append(int(raw))
	candidates.sort()
	var maps: Dictionary = {}
	seeds.append(candidates[posmod(start, candidates.size())])
	while seeds.size() < count:
		var best: int = MapModel.NO_ID
		var best_distance: float = -1.0
		for province_id: int in candidates:
			if seeds.has(province_id):
				continue
			var nearest: float = INF
			for seed: int in seeds:
				var hops: Dictionary = _hops(model, ids, seed, maps)
				nearest = minf(nearest, float(hops.get(province_id, INF)))
			if nearest > best_distance:
				best_distance = nearest
				best = province_id
		if best == MapModel.NO_ID:
			break
		seeds.append(best)
	return seeds


## BFS hops from `seed` across the landmass, cached per seed.
static func _hops(
	model: MapModel, ids: Array, seed: int, cache: Dictionary
) -> Dictionary:
	if cache.has(seed):
		return cache[seed]
	var allowed: Dictionary = {}
	for raw: Variant in ids:
		allowed[int(raw)] = true
	var distance: Dictionary = {seed: 0}
	var queue: Array[int] = [seed]
	var head: int = 0
	while head < queue.size():
		var current: int = queue[head]
		head += 1
		var step: int = int(distance[current]) + 1
		for neighbor: int in MapGeo.province_neighbors(model, current):
			if not allowed.has(neighbor) or distance.has(neighbor):
				continue
			distance[neighbor] = step
			queue.append(neighbor)
	cache[seed] = distance
	return distance
