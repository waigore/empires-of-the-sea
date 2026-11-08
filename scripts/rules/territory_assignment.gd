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
		var continent: Dictionary = continents[index]
		var faction_group: Array = groups[index]
		if faction_group.is_empty():
			continue
		var ids: Array = continent["ids"]
		var pool: Array = continent["sea_bound"] if sea_bound_required else ids
		if pool.size() < faction_group.size():
			if sea_bound_required:
				return _failure(ERROR_NO_SEA_BOUND_PROVINCE)
			pool = ids
		var seeds: Array[int] = _farthest_seeds(model, pool, faction_group.size())
		if seeds.size() < faction_group.size():
			return _failure(ERROR_NO_SEA_BOUND_PROVINCE)
		var targets: Dictionary = _plan_targets(
			ids.size(), faction_group, minor_ids
		)
		_grow(model, ids, faction_group, seeds, targets)
	return {"ok": true, "error": "", "factions": factions}


# --- continents -------------------------------------------------------------


## Connected components of the land subgraph (P–P edges only), largest first.
static func _continents(model: MapModel) -> Array:
	var seen: Dictionary = {}
	var ids: Array[int] = []
	for province: Dictionary in model.provinces:
		ids.append(int(province["id"]))
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
		for neighbor: int in model.province_neighbors(current):
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


## Balanced province budgets: Minor Nations reserve at most MINOR_PROVINCES
## each, the rest splits evenly across the Great Powers on that continent.
static func _plan_targets(
	count: int, factions: Array[int], minor_ids: Array[int]
) -> Dictionary:
	var minors: Array[int] = []
	var greats: Array[int] = []
	for faction_id: int in factions:
		if minor_ids.has(faction_id):
			minors.append(faction_id)
		else:
			greats.append(faction_id)
	var reserve: int = 0
	if not minors.is_empty():
		if greats.is_empty():
			reserve = count
		else:
			reserve = mini(count - greats.size(), minors.size() * MINOR_PROVINCES)
	var targets: Dictionary = {}
	_share(count - reserve, greats, targets)
	_share(reserve, minors, targets)
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


# --- growth -----------------------------------------------------------------


static func _grow(
	model: MapModel,
	ids: Array,
	factions: Array[int],
	seeds: Array[int],
	targets: Dictionary
) -> void:
	var lookup: Dictionary = {}
	for raw: Variant in ids:
		lookup[int(raw)] = true
	var owner: Dictionary = {}
	var counts: Dictionary = {}
	var distances: Array[Dictionary] = []
	for index in factions.size():
		var faction_id: int = factions[index]
		var seed_id: int = seeds[index]
		owner[seed_id] = faction_id
		counts[faction_id] = 1
		distances.append(_province_distances(model, seed_id, lookup))

	var remaining: int = ids.size() - seeds.size()
	while remaining > 0:
		var grew: bool = false
		for index in factions.size():
			var faction_id: int = factions[index]
			if int(counts[faction_id]) >= int(targets.get(faction_id, 0)):
				continue
			var pick: int = _best_frontier(
				model, lookup, owner, faction_id, distances[index]
			)
			if pick < 0:
				continue
			owner[pick] = faction_id
			counts[faction_id] = int(counts[faction_id]) + 1
			remaining -= 1
			grew = true
		if not grew:
			break

	# Leftover provinces balance the smallest holdings first (within ±1).
	while remaining > 0:
		var order: Array[int] = factions.duplicate()
		order.sort_custom(func(a: int, b: int) -> bool:
			var count_a: int = int(counts[a])
			var count_b: int = int(counts[b])
			if count_a != count_b:
				return count_a < count_b
			return a < b
		)
		var grew: bool = false
		for faction_id: int in order:
			var index: int = factions.find(faction_id)
			var pick: int = _best_frontier(
				model, lookup, owner, faction_id, distances[index]
			)
			if pick < 0:
				continue
			owner[pick] = faction_id
			counts[faction_id] = int(counts[faction_id]) + 1
			remaining -= 1
			grew = true
			break
		if not grew:
			break

	for raw: Variant in owner.keys():
		var province_id: int = int(raw)
		var province: Dictionary = model.province_data(province_id)
		if province.is_empty():
			continue
		province["owner"] = int(owner[raw])
		province["population"] = (
			180 + int(province["area"]) * 9 + (province_id * 37) % 90
		)


static func _province_distances(
	model: MapModel, seed_id: int, lookup: Dictionary
) -> Dictionary:
	var distances: Dictionary = {seed_id: 0}
	var queue: Array[int] = [seed_id]
	var head: int = 0
	while head < queue.size():
		var current: int = queue[head]
		head += 1
		var step: int = int(distances[current]) + 1
		for neighbor: int in model.province_neighbors(current):
			if not lookup.has(neighbor) or distances.has(neighbor):
				continue
			distances[neighbor] = step
			queue.append(neighbor)
	return distances


## Unowned province bordering `faction_id`, nearest to its seed, lowest id first.
static func _best_frontier(
	model: MapModel,
	lookup: Dictionary,
	owner: Dictionary,
	faction_id: int,
	distances: Dictionary
) -> int:
	var best: int = MapModel.NO_ID
	var best_distance: float = INF
	var keys: Array = lookup.keys()
	keys.sort()
	for raw: Variant in keys:
		var province_id: int = int(raw)
		if owner.has(province_id):
			continue
		if not _borders_owner(model, province_id, owner, faction_id):
			continue
		var distance: float = float(distances.get(province_id, INF))
		var better: bool = (
			best == MapModel.NO_ID
			or distance < best_distance
			or (distance == best_distance and province_id < best)
		)
		if better:
			best = province_id
			best_distance = distance
	return best


static func _borders_owner(
	model: MapModel, province_id: int, owner: Dictionary, faction_id: int
) -> bool:
	for neighbor: int in model.province_neighbors(province_id):
		if int(owner.get(neighbor, MapModel.NO_ID)) == faction_id:
			return true
	return false


static func _failure(code: String) -> Dictionary:
	return {"ok": false, "error": code, "factions": []}
