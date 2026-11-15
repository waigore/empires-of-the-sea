class_name ProvinceGraph
extends RefCounted
## Walks the province adjacency graph (wiki: map-topology): connected components
## and land-hop distances inside an induced set of provinces, plus the ownership
## tallies over that set. Territory assignment, the growth/seeding pass and the
## Minor share all read the same graph, so the walk lives here once
## (REQ-P3-03). Pure rules: no nodes, deterministic (lowest id first).


## Connected components of the subgraph induced by `ids`, every component
## ascending and the list largest first (ties: lowest first id).
static func components(model: MapModel, ids: Array) -> Array:
	var allowed: Dictionary = _allowed(ids)
	var seen: Dictionary = {}
	var result: Array = []
	for start: int in _ordered(allowed):
		if seen.has(start):
			continue
		result.append(_walk(model, allowed, start, seen))
	result.sort_custom(func(a: Array, b: Array) -> bool:
		if a.size() != b.size():
			return a.size() > b.size()
		return int(a[0]) < int(b[0])
	)
	return result


## True when `ids` is one contiguous set: an empty set is no holding, and any
## island splits it.
static func is_contiguous(model: MapModel, ids: Array) -> bool:
	if ids.is_empty():
		return false
	var allowed: Dictionary = _allowed(ids)
	var seen: Dictionary = {}
	_walk(model, allowed, int(_ordered(allowed)[0]), seen)
	return seen.size() == allowed.size()


## Land hops from `source` to every province of `ids` it can reach. `source` is
## 0, and a source outside `ids` reaches nothing.
static func hops(model: MapModel, ids: Array, source: int) -> Dictionary:
	var allowed: Dictionary = _allowed(ids)
	if not allowed.has(source):
		return {}
	var distance: Dictionary = {source: 0}
	var queue: Array[int] = [source]
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
	return distance


## Province count per owner inside `ids`; unowned provinces are not counted.
static func owner_counts(model: MapModel, ids: Array) -> Dictionary:
	var counts: Dictionary = {}
	for raw: Variant in ids:
		var province: ProvinceState = model.province_data(int(raw))
		if province != null and province.owner != MapModel.NO_ID:
			counts[province.owner] = int(counts.get(province.owner, 0)) + 1
	return counts


## Ids of `ids` with no owner, ascending.
static func unowned(model: MapModel, ids: Array) -> Array:
	var open: Array = []
	for raw: Variant in ids:
		var province: ProvinceState = model.province_data(int(raw))
		if province != null and province.owner == MapModel.NO_ID:
			open.append(int(raw))
	open.sort()
	return open


static func _allowed(ids: Array) -> Dictionary:
	var allowed: Dictionary = {}
	for raw: Variant in ids:
		allowed[int(raw)] = true
	return allowed


static func _ordered(allowed: Dictionary) -> Array[int]:
	var ids: Array[int] = []
	for raw: Variant in allowed.keys():
		ids.append(int(raw))
	ids.sort()
	return ids


## Breadth-first walk of the component holding `start`; returns its ids ascending
## and marks every member in `seen` so one pass covers the whole set.
static func _walk(
	model: MapModel, allowed: Dictionary, start: int, seen: Dictionary
) -> Array[int]:
	var group: Array[int] = []
	var queue: Array[int] = [start]
	seen[start] = true
	var head: int = 0
	while head < queue.size():
		var current: int = queue[head]
		head += 1
		group.append(current)
		for neighbor: int in MapGeo.province_neighbors(model, current):
			if not allowed.has(neighbor) or seen.has(neighbor):
				continue
			seen[neighbor] = true
			queue.append(neighbor)
	group.sort()
	return group
