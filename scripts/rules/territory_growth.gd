class_name TerritoryGrowth
extends RefCounted
## Province painting for one landmass (wiki: game-setup § GP, Minor Nation and
## Tribe assignment): grow each faction one province per round from its seed,
## then hand border provinces from over- to under-budget factions until each
## holds its share. Every holding stays one contiguous set.


## Paint `ids` (one landmass) and write owner + population onto the provinces.
static func paint(
	model: MapModel, ids: Array, factions: Array[int], seeds: Array[int],
	targets: Dictionary, fill: bool = true, capped: bool = false
) -> void:
	var lookup: Dictionary = {}
	for raw: Variant in ids:
		lookup[int(raw)] = true
	var owner: Dictionary = {}
	var counts: Dictionary = {}
	var distances: Array[Dictionary] = []
	for index in factions.size():
		owner[seeds[index]] = factions[index]
		counts[factions[index]] = 1
		distances.append(_distances(model, lookup, seeds[index]))
	_grow(model, lookup, owner, counts, factions, distances, targets, capped)
	if fill:
		_settle(model, lookup, owner, counts, targets)
	_rebalance(model, lookup, owner, counts, targets)
	for raw: Variant in owner.keys():
		var province_id: int = int(raw)
		var province: ProvinceState = model.province_data(province_id)
		if province == null:
			continue
		province.owner = int(owner[raw])
		province.population = 180 + province.area * 9 + (province_id * 37) % 90


## One claim per faction per round keeps the holdings within a province or two
## of each other; a faction with no frontier simply sits the round out.
static func _grow(
	model: MapModel, lookup: Dictionary, owner: Dictionary, counts: Dictionary,
	factions: Array[int], distances: Array[Dictionary], targets: Dictionary, capped: bool
) -> void:
	var remaining: int = lookup.size() - factions.size()
	var round_index: int = 0
	while remaining > 0:
		var grew: bool = false
		for step in factions.size():
			# Rotate each round so no faction always loses the contested province.
			var index: int = (round_index + step) % factions.size()
			var faction_id: int = factions[index]
			if capped and int(counts[faction_id]) >= int(targets.get(faction_id, 0)):
				continue
			var pick: int = _frontier(model, lookup, owner, faction_id, distances[index])
			if pick == MapModel.NO_ID:
				continue
			owner[pick] = faction_id
			counts[faction_id] = int(counts[faction_id]) + 1
			remaining -= 1
			grew = true
		round_index += 1
		if not grew:
			return


## Unowned province bordering the faction, nearest its seed (ties: lowest id).
static func _frontier(
	model: MapModel, lookup: Dictionary, owner: Dictionary, faction_id: int, distances: Dictionary
) -> int:
	var best: int = MapModel.NO_ID
	var best_distance: float = INF
	var ordered: Array = lookup.keys()
	ordered.sort()
	for raw: Variant in ordered:
		var province_id: int = int(raw)
		if owner.has(province_id):
			continue
		if not _borders_owner(model, province_id, owner, faction_id):
			continue
		var distance: float = float(distances.get(province_id, INF))
		if best == MapModel.NO_ID or distance < best_distance:
			best = province_id
			best_distance = distance
	return best


## BFS step count from the seed to every province of the landmass.
static func _distances(model: MapModel, lookup: Dictionary, seed_id: int) -> Dictionary:
	var distances: Dictionary = {seed_id: 0}
	var queue: Array[int] = [seed_id]
	var head: int = 0
	while head < queue.size():
		var current: int = queue[head]
		head += 1
		var step: int = int(distances[current]) + 1
		for neighbor: int in MapGeo.province_neighbors(model, current):
			if not lookup.has(neighbor) or distances.has(neighbor):
				continue
			distances[neighbor] = step
			queue.append(neighbor)
	return distances


## Any province no faction could reach joins the neediest neighbour. Holdings
## stay contiguous and the whole landmass ends up owned.
static func _settle(
	model: MapModel, lookup: Dictionary, owner: Dictionary, counts: Dictionary, targets: Dictionary
) -> void:
	var keys: Array = lookup.keys()
	keys.sort()
	var open: Array[int] = []
	for raw: Variant in keys:
		if not owner.has(int(raw)):
			open.append(int(raw))
	while not open.is_empty():
		var claimed: bool = false
		for province_id: int in open.duplicate():
			var pick: int = MapModel.NO_ID
			for neighbor: int in MapGeo.province_neighbors(model, province_id):
				if not owner.has(neighbor):
					continue
				var holder: int = int(owner[neighbor])
				if pick == MapModel.NO_ID or _need(holder, counts, targets) > _need(pick, counts, targets):
					pick = holder
			if pick == MapModel.NO_ID:
				continue
			owner[province_id] = pick
			counts[pick] = int(counts[pick]) + 1
			open.erase(province_id)
			claimed = true
		if not claimed:
			return


## Hand provinces from the most over-budget faction to its neediest neighbour
## until no such move exists. Each move shrinks the surplus, so it terminates.
static func _rebalance(
	model: MapModel, lookup: Dictionary, owner: Dictionary, counts: Dictionary, targets: Dictionary
) -> void:
	var provinces: Array = lookup.keys()
	provinces.sort()
	var moved: bool = true
	while moved:
		moved = false
		for donor: int in _by_gap(counts, targets, true):
			for recipient: int in _needy_neighbours(
				model, owner, counts, targets, donor, provinces
			):
				var move: Array[int] = _move_set(model, owner, donor, recipient, provinces)
				if move.is_empty():
					continue
				# Never overshoot, or the province could be handed straight back.
				if move.size() > -_need(donor, counts, targets):
					continue
				if move.size() > _need(recipient, counts, targets):
					continue
				for province_id: int in move:
					owner[province_id] = recipient
				counts[donor] = int(counts[donor]) - move.size()
				counts[recipient] = int(counts[recipient]) + move.size()
				moved = true
				break
			if moved:
				break
		if not moved:
			moved = _shift_chain(model, owner, counts, targets, provinces)


## A boxed-in faction borders only factions already at budget. Pass one province
## along a chain of neighbours so only the two ends change count.
static func _shift_chain(
	model: MapModel, owner: Dictionary, counts: Dictionary, targets: Dictionary, provinces: Array
) -> bool:
	var links: Dictionary = _faction_links(model, owner, provinces)
	for recipient: int in _by_gap(counts, targets, false):
		var path: Array[int] = _chain_to_donor(links, recipient, counts, targets)
		if path.size() < 2:
			continue
		if not _shift(model, owner, path, provinces):
			continue
		counts[path[0]] = int(counts[path[0]]) - 1
		counts[path[-1]] = int(counts[path[-1]]) + 1
		return true
	return false


## Faction -> factions it shares a province border with.
static func _faction_links(model: MapModel, owner: Dictionary, provinces: Array) -> Dictionary:
	var links: Dictionary = {}
	for raw: Variant in provinces:
		var province_id: int = int(raw)
		var holder: int = int(owner.get(province_id, MapModel.NO_ID))
		if holder == MapModel.NO_ID:
			continue
		for neighbor: int in MapGeo.province_neighbors(model, province_id):
			var other: int = int(owner.get(neighbor, MapModel.NO_ID))
			if other == MapModel.NO_ID or other == holder:
				continue
			if not links.has(holder):
				links[holder] = {}
			(links[holder] as Dictionary)[other] = true
	return links


## Shortest border path from an over-budget faction to `recipient` (donor first).
static func _chain_to_donor(
	links: Dictionary, recipient: int, counts: Dictionary, targets: Dictionary
) -> Array[int]:
	var parents: Dictionary = {recipient: -1}
	var queue: Array[int] = [recipient]
	var head: int = 0
	var donor: int = MapModel.NO_ID
	while head < queue.size() and donor == MapModel.NO_ID:
		var current: int = queue[head]
		head += 1
		var peers: Dictionary = links.get(current, {})
		for peer: int in peers.keys():
			if parents.has(peer):
				continue
			parents[peer] = current
			if _need(peer, counts, targets) < 0:
				donor = peer
				break
			queue.append(peer)
	if donor == MapModel.NO_ID:
		return [] as Array[int]
	var path: Array[int] = [donor]
	while int(path[-1]) != recipient:
		path.push_back(int(parents[path[-1]]))
	return path


## Hand one province down the chain (recipient end first); nothing else changes.
static func _shift(model: MapModel, owner: Dictionary, path: Array[int], provinces: Array) -> bool:
	var sim: Dictionary = owner.duplicate()
	var picks: Array[int] = []
	for index in range(path.size() - 2, -1, -1):
		var pick: int = _spare(model, sim, path[index], path[index + 1], provinces)
		if pick == MapModel.NO_ID:
			return false
		sim[pick] = path[index + 1]
		picks.append(pick)
	for pick: int in picks:
		owner[pick] = int(sim[pick])
	return true


## Lowest-id province `giver` can hand `taker` without splitting its holding.
static func _spare(
	model: MapModel, owner: Dictionary, giver: int, taker: int, provinces: Array
) -> int:
	for raw: Variant in provinces:
		var province_id: int = int(raw)
		if int(owner.get(province_id, MapModel.NO_ID)) != giver:
			continue
		if not _borders_owner(model, province_id, owner, taker):
			continue
		if not _keeps_sea_bound(model, owner, giver, [province_id], provinces):
			continue
		if _pockets(model, owner, giver, province_id, provinces).is_empty():
			return province_id
	return MapModel.NO_ID


## Great Powers and Tribes must keep at least one sea-bound province, so a move
## never takes the last one away (wiki: game-setup § GP / Tribe assignment).
static func _keeps_sea_bound(
	model: MapModel, owner: Dictionary, giver: int, moving: Array[int], provinces: Array
) -> bool:
	var sea: Array[int] = []
	for raw: Variant in provinces:
		var province_id: int = int(raw)
		if int(owner.get(province_id, MapModel.NO_ID)) == giver:
			if CapitalChoice.is_sea_bound(model, province_id):
				sea.append(province_id)
	for province_id: int in sea:
		if not moving.has(province_id):
			return true
	return sea.is_empty()


## Factions over (or under) budget, largest gap first (ties: lowest id).
static func _by_gap(counts: Dictionary, targets: Dictionary, over: bool) -> Array[int]:
	var result: Array[int] = []
	for faction_id: int in counts.keys():
		var gap: int = int(counts[faction_id]) - int(targets.get(faction_id, 0))
		if gap != 0 and (gap > 0) == over:
			result.append(faction_id)
	result.sort_custom(func(a: int, b: int) -> bool:
		var gap_a: int = int(counts[a]) - int(targets.get(a, 0))
		var gap_b: int = int(counts[b]) - int(targets.get(b, 0))
		if gap_a != gap_b:
			return gap_a > gap_b if over else gap_a < gap_b
		return a < b
	)
	return result


## Neighbours of `donor` under budget, largest deficit first (ties: lowest id).
static func _needy_neighbours(
	model: MapModel, owner: Dictionary, counts: Dictionary, targets: Dictionary,
	donor: int, provinces: Array
) -> Array[int]:
	var result: Array[int] = []
	for raw: Variant in provinces:
		var province_id: int = int(raw)
		if int(owner.get(province_id, MapModel.NO_ID)) != donor:
			continue
		for neighbor: int in MapGeo.province_neighbors(model, province_id):
			var other: int = int(owner.get(neighbor, MapModel.NO_ID))
			if other == MapModel.NO_ID or other == donor or result.has(other):
				continue
			if _need(other, counts, targets) > 0:
				result.append(other)
	result.sort_custom(func(a: int, b: int) -> bool:
		var need_a: int = _need(a, counts, targets)
		var need_b: int = _need(b, counts, targets)
		if need_a != need_b:
			return need_a > need_b
		return a < b
	)
	return result


## Smallest set of `giver` provinces bordering `taker`: one border province plus
## any pocket it would cut off, so the giver stays contiguous.
static func _move_set(
	model: MapModel, owner: Dictionary, giver: int, taker: int, provinces: Array
) -> Array[int]:
	var owned: Array[int] = []
	for raw: Variant in provinces:
		var province_id: int = int(raw)
		if int(owner.get(province_id, MapModel.NO_ID)) == giver:
			owned.append(province_id)
	if owned.size() <= 1:
		return [] as Array[int]
	var best: Array[int] = [] as Array[int]
	for province_id: int in owned:
		if not _borders_owner(model, province_id, owner, taker):
			continue
		var move: Array[int] = [province_id]
		move.append_array(_pockets(model, owner, giver, province_id, provinces))
		if move.size() >= owned.size():
			continue
		if not _keeps_sea_bound(model, owner, giver, move, provinces):
			continue
		if best.is_empty() or move.size() < best.size():
			best = move
	return best


## Giver provinces cut off from the main body when `removed` changes hands.
static func _pockets(
	model: MapModel, owner: Dictionary, giver: int, removed: int, provinces: Array
) -> Array[int]:
	var remaining: Dictionary = {}
	for raw: Variant in provinces:
		var province_id: int = int(raw)
		if province_id != removed and int(owner.get(province_id, MapModel.NO_ID)) == giver:
			remaining[province_id] = true
	if remaining.is_empty():
		return [] as Array[int]
	var components: Array = []
	var seen: Dictionary = {}
	var keys: Array = remaining.keys()
	keys.sort()
	for raw: Variant in keys:
		var start: int = int(raw)
		if seen.has(start):
			continue
		var component: Array[int] = [start]
		seen[start] = true
		var head: int = 0
		while head < component.size():
			var current: int = component[head]
			head += 1
			for neighbor: int in MapGeo.province_neighbors(model, current):
				if remaining.has(neighbor) and not seen.has(neighbor):
					seen[neighbor] = true
					component.append(neighbor)
		components.append(component)
	if components.size() <= 1:
		return [] as Array[int]
	components.sort_custom(func(a: Array, b: Array) -> bool: return a.size() > b.size())
	var pockets: Array[int] = []
	for index in range(1, components.size()):
		pockets.append_array(components[index])
	return pockets


## How far a faction still is from its budget (negative once it is over).
static func _need(faction_id: int, counts: Dictionary, targets: Dictionary) -> int:
	return int(targets.get(faction_id, 0)) - int(counts.get(faction_id, 0))

static func _borders_owner(
	model: MapModel, province_id: int, owner: Dictionary, faction_id: int
) -> bool:
	for neighbor: int in MapGeo.province_neighbors(model, province_id):
		if int(owner.get(neighbor, MapModel.NO_ID)) == faction_id:
			return true
	return false
