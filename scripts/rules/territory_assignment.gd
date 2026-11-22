class_name TerritoryAssignment
extends RefCounted
## Old World / New World province assignment (wiki: game-setup). Each faction
## grows from a sea-bound seed inside one P–P continent, so its holdings stay
## contiguous and never span two landmasses. Great Powers and Tribes are seeded
## on sea-bound provinces; Minor Nations may take an inland province. Pure rules:
## no nodes, deterministic, unit-testable. The province graph, the growth pass
## and the Minor share each stand in their own module; this one only decides who
## is seated where.

## Seed rotations tried before a landmass is called infeasible: a faction seeded
## into a pocket too small for its budget leaves the split lopsided (game-setup § Feasibility).
const LAYOUT_ATTEMPTS: int = 6

const ERROR_NO_PROVINCES: String = "no_provinces"
const ERROR_TOO_FEW_PROVINCES: String = "too_few_provinces"
const ERROR_NO_SEA_BOUND_PROVINCE: String = "missing_sea_bound_province"
## Wiki code when a Tribe owns no sea-bound province (game-setup § Tribe assignment).
const ERROR_TRIBE_SEA_BOUND: String = "tribe_missing_sea_bound_province"
## Unfair split: pocket too small for a faction's budget (game-setup § Feasibility).
const ERROR_UNFAIR_SPLIT: String = "unfair_split"


## Old World: Great Powers take the bulk, Minor Nations a small reservation
## (wiki: game-setup § GP / Minor Nation assignment).
static func assign_old_world(
	model: MapModel, gp_ids: Array[int], minor_ids: Array[int]
) -> Dictionary:
	return _assign(model, gp_ids, minor_ids, true)


## New World Tribes need a sea-bound province; miss → ERROR_TRIBE_SEA_BOUND.
static func assign_new_world(model: MapModel, tribe_ids: Array[int]) -> Dictionary:
	return _assign(model, tribe_ids, [] as Array[int], true, ERROR_TRIBE_SEA_BOUND)


static func _assign(
	model: MapModel,
	primary_ids: Array[int],
	minor_ids: Array[int],
	sea_bound_required: bool,
	sea_bound_error: String = ERROR_NO_SEA_BOUND_PROVINCE
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
			var minor_seeds: Array[int] = TerritorySeeds.pick(
				model, remaining, _sea_pool(model, remaining), minors.size()
			)
			if minor_seeds.size() < minors.size():
				return _failure(ERROR_NO_SEA_BOUND_PROVINCE)
			TerritoryGrowth.paint(
				model, remaining, minors, minor_seeds,
				_minor_targets(remaining.size(), minors), false, true
			)
			remaining = MinorShare.trim(model, MinorShare.absorb_pockets(
				model, ids, minors, primary_ids.size()), ids, minors)
		if greats.is_empty():
			continue
		var chunks: Array = ProvinceGraph.components(model, remaining)
		var spread: Array = _spread(chunks, greats)
		var layouts: Array = []
		for chunk_index in chunks.size():
			var chunk_ids: Array = chunks[chunk_index]
			var group: Array = spread[chunk_index]
			if group.is_empty():
				continue
			var pool: Array = _sea_pool(model, chunk_ids) if sea_bound_required else chunk_ids
			if pool.size() < group.size():
				if sea_bound_required:
					return _failure(sea_bound_error)
				pool = chunk_ids
			var targets: Dictionary = {}
			_share(chunk_ids.size(), group, targets)
			layouts.append({"ids": chunk_ids, "group": group, "pool": pool, "targets": targets})
		if not _paint_even(model, layouts, greats):
			return _failure(ERROR_UNFAIR_SPLIT)
	# Pocket absorption can leave a Minor holding land it cannot spare back: the
	# cove it took is too small to seat a Great Power, and every province it owns
	# there is a cut of its own holding. The split is then still lopsided, and
	# the wiki calls the chart infeasible rather than opening the age with one
	# Minor double its neighbours' share (wiki: game-setup § Minor Nation
	# assignment — "within ±1"; § Feasibility).
	if not minor_ids.is_empty():
		var region_ids: Array[int] = []
		for province: ProvinceState in model.provinces:
			region_ids.append(province.id)
		if MinorShare.out_of_band(model, region_ids, minor_ids) != MapModel.NO_ID:
			return _failure(ERROR_UNFAIR_SPLIT)
	return {"ok": true, "error": "", "factions": factions}


## Paints every landmass of the region, keeping the first rotation whose split is
## even across the region; a pocket too small for a faction's budget leaves the
## split lopsided, so the rotation is retried and the landmass reported infeasible
## when none is even (wiki: game-setup § GP assignment).
static func _paint_even(model: MapModel, layouts: Array, factions: Array) -> bool:
	for attempt in LAYOUT_ATTEMPTS:
		for layout: Dictionary in layouts:
			for raw: Variant in layout["ids"]:
				var province: ProvinceState = model.province_data(int(raw))
				if province != null:
					province.owner = MapModel.NO_ID
		for layout: Dictionary in layouts:
			var group: Array = layout["group"]
			var seeds: Array[int] = TerritorySeeds.pick(
				model, layout["ids"], layout["pool"], group.size(), attempt
			)
			if seeds.size() < group.size():
				return false
			TerritoryGrowth.paint(model, layout["ids"], group, seeds, layout["targets"])
		if _split_even(model, _layout_ids(layouts), factions):
			return true
	return false


## Every province the region's Great Powers (or Tribes) can hold.
static func _layout_ids(layouts: Array) -> Array:
	var ids: Array = []
	for layout: Dictionary in layouts:
		ids.append_array(layout["ids"])
	return ids


# --- continents -------------------------------------------------------------


## Connected components of the land subgraph (P–P edges only), largest first,
## each carrying the provinces that touch a sea zone (a valid seed).
static func _continents(model: MapModel) -> Array:
	var ids: Array[int] = []
	for province: ProvinceState in model.provinces:
		ids.append(province.id)
	var result: Array = []
	for group: Array in ProvinceGraph.components(model, ids):
		var sea_bound: Array[int] = []
		for member: int in group:
			if CapitalChoice.is_sea_bound(model, member):
				sea_bound.append(member)
		result.append({"ids": group, "sea_bound": sea_bound})
	return result


## Round-robin factions onto continents, preferring one with a free sea-bound seed.
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


## One Great Power per chunk, then the rest by share so no chunk goes unheld. A
## landmass the Minor reservation took whole yields no chunk, so no group either.
static func _spread(chunks: Array, factions: Array[int]) -> Array:
	var groups: Array = []
	for _index in chunks.size():
		groups.append([] as Array[int])
	if chunks.is_empty():
		return groups
	var start: int = mini(chunks.size(), factions.size())
	for index in start:
		(groups[index] as Array[int]).append(factions[index])
	for slot in range(start, factions.size()):
		var faction_id: int = factions[slot]
		var best: int = 0
		var best_score: float = -1.0
		for index in chunks.size():
			var size: int = (chunks[index] as Array).size()
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


## Minor Nations take MINOR_PROVINCES each, or an even share when the landmass
## cannot seat that floor (wiki: game-setup § Minor Nation assignment).
static func _minor_targets(count: int, minors: Array[int]) -> Dictionary:
	var each: int = mini(
		MinorShare.MINOR_PROVINCES, maxi(1, count / minors.size())
	)
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


## An even split: every faction holds at least one province and no count strays
## more than one from the even share (game-setup § GP / Minor / Tribe, "within ±1").
static func _split_even(model: MapModel, ids: Array, factions: Array) -> bool:
	var counts: Dictionary = ProvinceGraph.owner_counts(model, ids)
	var total: int = 0
	for faction_id: int in factions:
		var count: int = int(counts.get(faction_id, 0))
		if count <= 0:
			return false
		total += count
	var share: float = float(total) / float(factions.size())
	for faction_id: int in factions:
		if absf(float(counts[faction_id]) - share) > 1.0:
			return false
	return true


static func _failure(code: String) -> Dictionary:
	return {"ok": false, "error": code, "factions": []}
