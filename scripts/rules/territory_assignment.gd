class_name TerritoryAssignment
extends RefCounted
## Old World / New World province assignment (wiki: game-setup).
## Each faction grows from a sea-bound seed inside one P–P continent, so a
## faction's holdings stay contiguous and never span two landmasses. Great
## Powers and Tribes are seeded on sea-bound provinces; Minor Nations may take an
## inland province. Pure rules: no nodes, deterministic, unit-testable.

const MINOR_PROVINCES: int = 3

const ERROR_NO_PROVINCES: String = "no_provinces"
const ERROR_TOO_FEW_PROVINCES: String = "too_few_provinces"
const ERROR_NO_SEA_BOUND_PROVINCE: String = "missing_sea_bound_province"


## Old World: Great Powers take the bulk, Minor Nations a small reservation
## (wiki: game-setup § GP / Minor Nation assignment).
static func assign_old_world(
	model: MapModel, gp_ids: Array[int], minor_ids: Array[int]
) -> Dictionary:
	return _assign(model, gp_ids, minor_ids, true)


## New World: every Tribe must own at least one sea-bound province so fleets can
## discover it (wiki: game-setup § Tribe assignment).
static func assign_new_world(model: MapModel, tribe_ids: Array[int]) -> Dictionary:
	return _assign(model, tribe_ids, [] as Array[int], true)


static func _assign(
	model: MapModel,
	primary_ids: Array[int],
	minor_ids: Array[int],
	sea_bound_required: bool
) -> Dictionary:
	if model.provinces.is_empty():
		return _failure(ERROR_NO_PROVINCES)
	var factions: Array[int] = primary_ids.duplicate()
	factions.append_array(minor_ids)
	if factions.size() == 0:
		return _failure(ERROR_NO_PROVINCES)
	if model.provinces.size() < factions.size():
		return _failure(ERROR_TOO_FEW_PROVINCES)

	var continents: Array = _continents(model)
	if continents.is_empty():
		return _failure(ERROR_NO_PROVINCES)
	var groups: Array = _distribute(continents, factions, sea_bound_required)

	for index in continents.size():
		var faction_group: Array = groups[index]
		if faction_group.is_empty():
			continue
		var ids: Array = (continents[index] as Dictionary)["ids"]
		var minors: Array[int] = []
		var greats: Array[int] = []
		for faction_id: int in faction_group:
			if minor_ids.has(faction_id):
				minors.append(faction_id)
			else:
				greats.append(faction_id)
		var remaining: Array = ids.duplicate()
		# Minor Nations are reserved first; Great Powers split only what is left
		# (wiki: game-setup § GP assignment).
		if not minors.is_empty():
			var minor_seeds: Array[int] = _farthest_seeds(
				model, _sea_pool(model, remaining), minors.size()
			)
			if minor_seeds.size() < minors.size():
				return _failure(ERROR_NO_SEA_BOUND_PROVINCE)
			TerritoryGrowth.paint(
				model, remaining, minors, minor_seeds,
				_minor_targets(remaining.size(), minors), false, true
			)
			remaining = _absorb_pockets(model, ids, minors, primary_ids.size())
		if greats.is_empty():
			continue
		var chunks: Array = _chunks(model, remaining)
		var spread: Array = _spread(chunks, greats)
		for chunk_index in chunks.size():
			var chunk_ids: Array = (chunks[chunk_index] as Dictionary)["ids"]
			var group: Array = spread[chunk_index]
			if group.is_empty():
				continue
			var pool: Array = _sea_pool(model, chunk_ids) if sea_bound_required else chunk_ids
			if pool.size() < group.size():
				if sea_bound_required:
					return _failure(ERROR_NO_SEA_BOUND_PROVINCE)
				pool = chunk_ids
			var seeds: Array[int] = _farthest_seeds(model, pool, group.size())
			if seeds.size() < group.size():
				return _failure(ERROR_NO_SEA_BOUND_PROVINCE)
			var targets: Dictionary = {}
			_share(chunk_ids.size(), group, targets)
			TerritoryGrowth.paint(model, chunk_ids, group, seeds, targets)
	return {"ok": true, "error": "", "factions": factions}


# --- continents -------------------------------------------------------------


## Connected components of the land subgraph (P–P edges only), largest first.
static func _continents(model: MapModel) -> Array:
	var seen: Dictionary = {}
	var ids: Array[int] = []
	for province: ProvinceState in model.provinces:
		ids.append(province.id)
	ids.sort()
	var result: Array = []
	for province_id: int in ids:
		if seen.has(province_id):
			continue
		var group: Array[int] = _component(model, province_id, seen)
		group.sort()
		var sea_bound: Array[int] = []
		for member: int in group:
			if CapitalChoice.is_sea_bound(model, member):
				sea_bound.append(member)
		result.append({"ids": group, "sea_bound": sea_bound})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var size_a: int = (a["ids"] as Array).size()
		var size_b: int = (b["ids"] as Array).size()
		if size_a != size_b:
			return size_a > size_b
		return int((a["ids"] as Array)[0]) < int((b["ids"] as Array)[0])
	)
	return result


static func _component(model: MapModel, start: int, seen: Dictionary) -> Array[int]:
	var group: Array[int] = []
	var queue: Array[int] = [start]
	seen[start] = true
	var head: int = 0
	while head < queue.size():
		var current: int = queue[head]
		head += 1
		group.append(current)
		for neighbor: int in MapGeo.province_neighbors(model, current):
			if seen.has(neighbor):
				continue
			seen[neighbor] = true
			queue.append(neighbor)
	return group


## Round-robin factions onto continents, preferring a continent that still has a
## free sea-bound province for the next seed.
static func _distribute(
	continents: Array, factions: Array[int], sea_bound_required: bool
) -> Array:
	var groups: Array = []
	for _index in continents.size():
		groups.append([] as Array[int])
	for faction_id: int in factions:
		var pick: int = _next_continent(continents, groups, sea_bound_required)
		var group: Array[int] = groups[pick]
		group.append(faction_id)
	return groups


static func _next_continent(
	continents: Array, groups: Array, sea_bound_required: bool
) -> int:
	var best_index: int = 0
	var best_free: int = -1000000
	var best_size: int = -1
	for index in continents.size():
		var continent: Dictionary = continents[index]
		var capacity: int = (
			(continent["sea_bound"] as Array).size()
			if sea_bound_required
			else (continent["ids"] as Array).size()
		)
		var group: Array = groups[index]
		var free: int = capacity - group.size()
		var size: int = (continent["ids"] as Array).size()
		var better: bool = (
			free > best_free or (free == best_free and size > best_size)
		)
		if better:
			best_free = free
			best_size = size
			best_index = index
	return best_index


# --- targets and seeds ------------------------------------------------------


## Connected chunks of a province set (largest first, then lowest first id).
static func _chunks(model: MapModel, ids: Array) -> Array:
	var lookup: Dictionary = {}
	for raw: Variant in ids:
		lookup[int(raw)] = true
	var seen: Dictionary = {}
	var result: Array = []
	var ordered: Array = ids.duplicate()
	ordered.sort()
	for raw: Variant in ordered:
		var start: int = int(raw)
		if seen.has(start):
			continue
		var group: Array[int] = []
		var queue: Array[int] = [start]
		seen[start] = true
		var head: int = 0
		while head < queue.size():
			var current: int = queue[head]
			head += 1
			group.append(current)
			for neighbor: int in MapGeo.province_neighbors(model, current):
				if lookup.has(neighbor) and not seen.has(neighbor):
					seen[neighbor] = true
					queue.append(neighbor)
		result.append({"ids": group})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var size_a: int = (a["ids"] as Array).size()
		var size_b: int = (b["ids"] as Array).size()
		if size_a != size_b:
			return size_a > size_b
		return int((a["ids"] as Array)[0]) < int((b["ids"] as Array)[0])
	)
	return result


## One Great Power per chunk, then the rest by share so no chunk goes unheld.
static func _spread(chunks: Array, factions: Array[int]) -> Array:
	var groups: Array = []
	for _index in chunks.size():
		groups.append([] as Array[int])
	var start: int = mini(chunks.size(), factions.size())
	for index in start:
		(groups[index] as Array[int]).append(factions[index])
	for slot in range(start, factions.size()):
		var faction_id: int = factions[slot]
		var best: int = 0
		var best_score: float = -1.0
		for index in chunks.size():
			var size: int = (chunks[index]["ids"] as Array).size()
			var taken: int = (groups[index] as Array).size()
			var score: float = float(size) / float(taken + 1)
			if score > best_score:
				best_score = score
				best = index
		var group: Array[int] = groups[best]
		group.append(faction_id)
	return groups


static func _sea_pool(model: MapModel, ids: Array) -> Array:
	var pool: Array = []
	for raw: Variant in ids:
		if CapitalChoice.is_sea_bound(model, int(raw)):
			pool.append(int(raw))
	return pool


static func _unowned(model: MapModel, ids: Array) -> Array:
	var open: Array = []
	for raw: Variant in ids:
		var province: ProvinceState = model.province_data(int(raw))
		if province != null and province.owner == MapModel.NO_ID:
			open.append(int(raw))
	open.sort()
	return open


## A Minor Nation's cell can seal off a cove of a province or two. Such a pocket
## is too small to seat a Great Power, so the bordering Minor Nation takes it.
static func _absorb_pockets(
	model: MapModel, ids: Array, minors: Array[int], max_chunks: int
) -> Array:
	var changed: bool = true
	while changed:
		changed = false
		var counts: Dictionary = _owner_counts(model, ids)
		var chunks: Array = _chunks(model, _unowned(model, ids))
		for chunk: Dictionary in chunks:
			var chunk_ids: Array = chunk["ids"]
			var too_small: bool = chunk_ids.size() < MINOR_PROVINCES
			var too_many: bool = chunks.size() > max_chunks and chunk == chunks[-1]
			if not too_small and not too_many:
				continue
			var taker: int = _bordering_minor(model, chunk_ids, minors, counts)
			if taker == MapModel.NO_ID:
				continue
			for raw: Variant in chunk_ids:
				var province_id: int = int(raw)
				var province: ProvinceState = model.province_data(province_id)
				province.owner = taker
				province.population = 180 + province.area * 9 + (province_id * 37) % 90
			counts[taker] = int(counts.get(taker, 0)) + chunk_ids.size()
			changed = true
	return _unowned(model, ids)


static func _owner_counts(model: MapModel, ids: Array) -> Dictionary:
	var counts: Dictionary = {}
	for raw: Variant in ids:
		var province: ProvinceState = model.province_data(int(raw))
		if province != null and province.owner != MapModel.NO_ID:
			counts[province.owner] = int(counts.get(province.owner, 0)) + 1
	return counts


## Minor Nation touching the pocket that holds fewest provinces (ties: lowest id).
static func _bordering_minor(
	model: MapModel, chunk_ids: Array, minors: Array[int], counts: Dictionary
) -> int:
	var best: int = MapModel.NO_ID
	for raw: Variant in chunk_ids:
		for neighbor: int in MapGeo.province_neighbors(model, int(raw)):
			var owner: int = model.province_data(neighbor).owner
			if not minors.has(owner):
				continue
			if best == MapModel.NO_ID or int(counts.get(owner, 0)) < int(counts.get(best, 0)):
				best = owner
	return best


## Minor Nations take MINOR_PROVINCES each, or an even share when the landmass
## cannot seat that floor (wiki: game-setup § Minor Nation assignment).
static func _minor_targets(count: int, minors: Array[int]) -> Dictionary:
	var each: int = mini(MINOR_PROVINCES, maxi(1, count / minors.size()))
	var targets: Dictionary = {}
	_share(mini(count, each * minors.size()), minors, targets)
	return targets


static func _share(total: int, factions: Array[int], targets: Dictionary) -> void:
	if factions.is_empty():
		return
	var base: int = total / factions.size()
	var remainder: int = total % factions.size()
	for index in factions.size():
		targets[factions[index]] = base + (1 if index < remainder else 0)


## Deterministic farthest-point seeds over the pool (ties: lowest id).
static func _farthest_seeds(
	model: MapModel, pool: Array, count: int
) -> Array[int]:
	var seeds: Array[int] = []
	if pool.is_empty() or count <= 0:
		return seeds
	var candidates: Array[int] = []
	for raw: Variant in pool:
		candidates.append(int(raw))
	candidates.sort()
	seeds.append(candidates[0])
	while seeds.size() < count:
		var best: int = MapModel.NO_ID
		var best_distance: float = -1.0
		for province_id: int in candidates:
			if seeds.has(province_id):
				continue
			var nearest: float = INF
			for seed: int in seeds:
				var distance: float = model.province_center(province_id).distance_to(
					model.province_center(seed)
				)
				nearest = minf(nearest, distance)
			if nearest > best_distance:
				best_distance = nearest
				best = province_id
		if best == MapModel.NO_ID:
			break
		seeds.append(best)
	return seeds


static func _failure(code: String) -> Dictionary:
	return {"ok": false, "error": code, "factions": []}
