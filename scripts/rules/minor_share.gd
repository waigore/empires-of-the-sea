class_name MinorShare
extends RefCounted
## Keeps a Minor Nation's holding inside the even split of its share (wiki:
## game-setup § Minor Nation assignment — "Per-minor count from even split of
## remaining OW total (within ±1)"). A Minor's own cell can seal off a cove of a
## province or two; that cove is too small to seat a Great Power, so the bordering
## Minor takes it (`TerritoryAssignment._absorb_pockets`). The cove can carry the
## court past the band, so land it can spare goes back to the Great-Power pool:
## a province it owns that already borders that pool and whose loss leaves the
## court's holding one connected set. Pure rules over the province graph
## (REQ-P2-03, REQ-P3-03).


## Hands back land from any Minor above the band and returns the enlarged
## Great-Power pool. A court that cannot spare a province keeps its land; the
## caller's even-split check then reports the chart infeasible.
static func trim(
	model: MapModel, remaining: Array, ids: Array, minors: Array[int]
) -> Array:
	var pool: Array = remaining.duplicate()
	if model == null or minors.is_empty():
		return pool
	var trimmed: bool = true
	while trimmed:
		trimmed = false
		var counts: Dictionary = {}
		var total: int = 0
		for raw: Variant in ids:
			var province: ProvinceState = model.province_data(int(raw))
			if province == null or not minors.has(province.owner):
				continue
			counts[province.owner] = int(counts.get(province.owner, 0)) + 1
			total += 1
		var ceiling: int = int(floor(float(total) / float(minors.size()) + 1.0))
		for donor: int in _over_band(counts, ceiling):
			var pick: int = _spare_land(model, donor, ids, pool)
			if pick == MapModel.NO_ID:
				continue
			model.province_data(pick).owner = MapModel.NO_ID
			pool.append(pick)
			pool.sort()
			trimmed = true
			break
	return pool


## Minor Nations holding more than the band allows, most over first (ties: id).
static func _over_band(counts: Dictionary, ceiling: int) -> Array[int]:
	var result: Array[int] = []
	for raw: Variant in counts.keys():
		if int(counts[raw]) > ceiling:
			result.append(int(raw))
	result.sort_custom(func(a: int, b: int) -> bool:
		if int(counts[a]) != int(counts[b]):
			return int(counts[a]) > int(counts[b])
		return a < b
	)
	return result


## Lowest-id province the court can hand the pool, or NO_ID when every province
## it owns either sits inland or holds its holding together.
static func _spare_land(
	model: MapModel, donor: int, ids: Array, pool: Array
) -> int:
	var pool_set: Dictionary = {}
	for raw: Variant in pool:
		pool_set[int(raw)] = true
	var owned: Array[int] = []
	for raw: Variant in ids:
		var province: ProvinceState = model.province_data(int(raw))
		if province != null and province.owner == donor:
			owned.append(int(raw))
	owned.sort()
	if owned.size() <= 1:
		return MapModel.NO_ID
	for province_id: int in owned:
		var touches_pool: bool = false
		for neighbor: int in MapGeo.province_neighbors(model, province_id):
			if pool_set.has(neighbor):
				touches_pool = true
				break
		if not touches_pool:
			continue
		if _stays_connected(model, owned, province_id):
			return province_id
	return MapModel.NO_ID


## True when `owned` minus `removed` is still one province-connected set, so the
## court that gave land away never splits its own holding.
static func _stays_connected(model: MapModel, owned: Array[int], removed: int) -> bool:
	var lookup: Dictionary = {}
	var start: int = MapModel.NO_ID
	for province_id: int in owned:
		if province_id == removed:
			continue
		lookup[province_id] = true
		if start == MapModel.NO_ID:
			start = province_id
	if lookup.is_empty():
		return false
	var seen: Dictionary = {start: true}
	var queue: Array[int] = [start]
	var head: int = 0
	while head < queue.size():
		var current: int = queue[head]
		head += 1
		for neighbor: int in MapGeo.province_neighbors(model, current):
			if lookup.has(neighbor) and not seen.has(neighbor):
				seen[neighbor] = true
				queue.append(neighbor)
	return seen.size() == lookup.size()
