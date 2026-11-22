class_name MinorShare
extends RefCounted
## Keeps a Minor Nation's holding inside the even split of its share (wiki:
## game-setup § Minor Nation assignment — "Per-minor count from even split of
## remaining OW total (within ±1)"). A Minor's own cell can seal off a cove of a
## province or two; that cove is too small to seat a Great Power, so the bordering
## Minor takes it (`absorb_pockets`). The cove can carry the court past the band,
## so land it can spare goes back to the Great-Power pool: a province it owns that
## already borders that pool and whose loss leaves the court's holding one
## connected set. Pure rules over the province graph (REQ-P2-03, REQ-P3-03).

## Provinces a Minor Nation is owed before the even share decides
## (wiki: game-setup § Minor Nation assignment).
const MINOR_PROVINCES: int = 3


## A Minor Nation's cell can seal off a cove of a province or two. Such a pocket
## is too small to seat a Great Power, so the bordering Minor Nation takes it.
## Returns the enlarged Great-Power pool, ascending.
static func absorb_pockets(
	model: MapModel, ids: Array, minors: Array[int], max_chunks: int
) -> Array:
	var changed: bool = true
	while changed:
		changed = false
		var counts: Dictionary = ProvinceGraph.owner_counts(model, ids)
		var chunks: Array = ProvinceGraph.components(
			model, ProvinceGraph.unowned(model, ids)
		)
		for index in chunks.size():
			var chunk_ids: Array = chunks[index]
			var too_small: bool = chunk_ids.size() < MINOR_PROVINCES
			# A landmass carrying more chunks than it has Great Powers cannot seat
			# every court, so its last (smallest) chunk joins a Minor too.
			var too_many: bool = chunks.size() > max_chunks and index == chunks.size() - 1
			if not too_small and not too_many:
				continue
			var taker: int = _bordering_minor(model, chunk_ids, minors, counts)
			if taker == MapModel.NO_ID:
				continue
			_paint_pocket(model, chunk_ids, taker)
			counts[taker] = int(counts.get(taker, 0)) + chunk_ids.size()
			changed = true
	return ProvinceGraph.unowned(model, ids)


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


## The first Minor Nation holding land outside the published band — the even
## split of the region's Minor land, ±1 — or NO_ID when every court sits inside
## it (wiki: game-setup § Minor Nation assignment; § Feasibility: a chart whose
## split cannot be made even is infeasible and the world is regenerated, never
## quietly opened with one Minor holding twice its neighbours' share).
## `ids` is the region's province set; unowned and non-Minor land is ignored.
static func out_of_band(model: MapModel, ids: Array, minors: Array[int]) -> int:
	if model == null or minors.is_empty():
		return MapModel.NO_ID
	var counts: Dictionary = {}
	var total: int = 0
	for raw: Variant in ids:
		var province: ProvinceState = model.province_data(int(raw))
		if province == null or not minors.has(province.owner):
			continue
		counts[province.owner] = int(counts.get(province.owner, 0)) + 1
		total += 1
	if total == 0:
		return MapModel.NO_ID
	var share: float = float(total) / float(minors.size())
	for faction: int in minors:
		if absf(float(counts.get(faction, 0)) - share) > 1.0:
			return faction
	return MapModel.NO_ID


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
		if ProvinceGraph.is_contiguous(model, _without(owned, province_id)):
			return province_id
	return MapModel.NO_ID


## `owned` minus one province, in its original (ascending) order.
static func _without(owned: Array[int], removed: int) -> Array[int]:
	var kept: Array[int] = []
	for province_id: int in owned:
		if province_id != removed:
			kept.append(province_id)
	return kept


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


static func _paint_pocket(model: MapModel, chunk_ids: Array, taker: int) -> void:
	for raw: Variant in chunk_ids:
		var province_id: int = int(raw)
		var province: ProvinceState = model.province_data(province_id)
		province.owner = taker
		# A taken province carries no seat to its taker (wiki:
		# capital-and-connectivity § Capital loss and reassignment).
		CapitalLoss.clear_seat(province)
		province.population = 180 + province.area * 9 + (province_id * 37) % 90
