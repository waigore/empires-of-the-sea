class_name AdvancedWorld
extends RefCounted
## New World state for an advanced start: rival colonies, the reveal the crown
## inherits and the sea-lane knowledge that goes with it (wiki:
## advanced-starts § Tier tables, § NW sea-zone visibility). Pure map mutation:
## ownership and fog only, no nodes (REQ-P3-03).

## Sea knowledge for a revealed-but-not-owned shore: charted, not surveyed.
const CHARTED: int = VisibilityModel.Level.FOGGED


## Great Power colonies: up to `count` contiguous Tribe provinces per crown,
## grown from the Passage shore. A Tribe keeps at least one province and never
## loses its capital seat (wiki § Bootstrap step 9). Crowns claim in rotation —
## one province per round — so no court is boxed out of the land it was
## promised; where the map cannot seat the full tier, some crowns hold fewer.
static func claim(world: WorldMap, count: int, factions: Array[int]) -> Dictionary:
	var claimed: Dictionary = {}
	if world == null or count <= 0 or factions.is_empty():
		return claimed
	var model: MapModel = _new_world(world)
	if model == null:
		return claimed
	var zones: Array[int] = world.warp_zones(world.region_count() - 1)
	var taken: Dictionary = {}
	var tribe_total: Dictionary = _tribe_totals(model)
	var shares: Array[int] = _shares(count, factions.size(), tribe_total)
	var chosen: Dictionary = {}
	var frontier: Dictionary = {}
	var seeds: Array[int] = []
	for index in factions.size():
		var faction: int = factions[index]
		var seed: int = _seed(model, factions, taken, tribe_total, zones, seeds)
		if seed < 0:
			continue
		seeds.append(seed)
		chosen[faction] = [seed]
		frontier[faction] = _neighbours(model, seed, factions, taken, tribe_total)
		_occupy(model, seed, faction, taken, tribe_total)
	var progress: bool = true
	while progress:
		progress = false
		for index in factions.size():
			var faction: int = factions[index]
			if not chosen.has(faction) or chosen[faction].size() >= shares[index]:
				continue
			var province_id: int = _next(model, frontier[faction], factions, taken, tribe_total)
			if province_id < 0:
				continue
			chosen[faction].append(province_id)
			for raw: Variant in _neighbours(model, province_id, factions, taken, tribe_total):
				if not frontier[faction].has(int(raw)):
					frontier[faction].append(int(raw))
			_occupy(model, province_id, faction, taken, tribe_total)
			progress = true
	for index in factions.size():
		var faction: int = factions[index]
		if chosen.has(faction):
			claimed[faction] = chosen[faction]
	return claimed


## Beachhead for a crown: the claimable Passage province closest to the water
## that does not touch an earlier crown's beachhead (ties by province id), so
## the crowns fan out along the shore instead of boxing each other in. A
## second pass drops the spacing when the coast is too short.
static func _seed(
	model: MapModel,
	factions: Array[int],
	taken: Dictionary,
	tribe_total: Dictionary,
	zones: Array[int],
	seeds: Array[int]
) -> int:
	var order: Array[int] = _shore_order(model, zones)
	for province_id: int in order:
		if not _claimable(model.get_province(province_id), factions, taken, tribe_total):
			continue
		if _touches_seed(model, province_id, seeds):
			continue
		return province_id
	for province_id: int in order:
		if _claimable(model.get_province(province_id), factions, taken, tribe_total):
			return province_id
	return -1


static func _touches_seed(model: MapModel, province_id: int, seeds: Array[int]) -> bool:
	for raw: Variant in MapGeo.province_neighbors(model, province_id):
		if seeds.has(int(raw)):
			return true
	return false


## Province ids ordered by their distance from the Passage shore, ties by id.
static func _shore_order(model: MapModel, zones: Array[int]) -> Array[int]:
	var distance: Dictionary = {}
	var queue: Array[int] = []
	for province: ProvinceState in model.provinces:
		if _on_passage(model, province.id, zones):
			distance[province.id] = 0
			queue.append(province.id)
	var head: int = 0
	while head < queue.size():
		var province_id: int = queue[head]
		head += 1
		for raw: Variant in MapGeo.province_neighbors(model, province_id):
			var neighbour: int = int(raw)
			if distance.has(neighbour):
				continue
			distance[neighbour] = int(distance[province_id]) + 1
			queue.append(neighbour)
	var order: Array[int] = []
	for raw: Variant in distance.keys():
		order.append(int(raw))
	order.sort_custom(func(a: int, b: int) -> bool:
		if int(distance[a]) != int(distance[b]):
			return int(distance[a]) < int(distance[b])
		return a < b
	)
	return order


## Lowest-id claimable entry on a crown's growth frontier, or -1.
static func _next(
	model: MapModel,
	frontier: Array[int],
	factions: Array[int],
	taken: Dictionary,
	tribe_total: Dictionary
) -> int:
	frontier.sort()
	for raw: Variant in frontier:
		if _claimable(
			model.get_province(int(raw)), factions, taken, tribe_total
		):
			return int(raw)
	return -1


## Tribe land turned over to a crown: ownership, the phase ledger and the
## Tribe's remaining count all move together.
static func _occupy(
	model: MapModel,
	province_id: int,
	faction: int,
	taken: Dictionary,
	tribe_total: Dictionary
) -> void:
	var province: ProvinceState = model.get_province(province_id)
	if province == null:
		return
	taken[province_id] = faction
	tribe_total[province.owner] = maxi(int(tribe_total.get(province.owner, 0)) - 1, 0)
	province.owner = faction


## Claimable Tribe neighbours of a province, in id order.
static func _neighbours(
	model: MapModel,
	province_id: int,
	factions: Array[int],
	taken: Dictionary,
	tribe_total: Dictionary
) -> Array[int]:
	var found: Array[int] = []
	for raw: Variant in MapGeo.province_neighbors(model, province_id):
		if _claimable(model.get_province(int(raw)), factions, taken, tribe_total):
			found.append(int(raw))
	found.sort()
	return found


## Even share of the claimable land, capped at the tier count. `budget` keeps
## one province in every Tribe, so a tribe is never wiped off the map.
static func _shares(
	count: int, crowns: int, tribe_total: Dictionary
) -> Array[int]:
	var shares: Array[int] = []
	if crowns <= 0:
		return shares
	var budget: int = 0
	for owner: Variant in tribe_total.keys():
		budget += maxi(int(tribe_total[owner]) - 1, 0)
	var each: int = mini(count, budget / crowns)
	var extra: int = budget - each * crowns
	for index in crowns:
		var share: int = each
		if index < extra:
			share += 1
		shares.append(mini(share, count))
	return shares


## Grows one crown's colonies contiguously from the Passage coast, in
## province-id order so the seed reproduces the same colonies. The tribe ledger
## is shared and debited per claim, so no Tribe is ever emptied.
static func _grow(
	model: MapModel,
	count: int,
	factions: Array[int],
	taken: Dictionary,
	tribe_total: Dictionary,
	zones: Array[int]
) -> Array[int]:
	var chosen: Array[int] = []
	var frontier: Array[int] = []
	for province: ProvinceState in model.provinces:
		if _claimable(province, factions, taken, tribe_total) and _on_passage(model, province.id, zones):
			frontier.append(province.id)
	frontier.sort()
	if frontier.is_empty():
		return chosen
	# One beachhead; every later claim grows from land already held, so the
	# colony is one contiguous holding instead of scattered shore provinces.
	var seed: int = frontier[0]
	frontier = [seed]
	while chosen.size() < count and not frontier.is_empty():
		frontier.sort()
		var province_id: int = frontier.pop_front()
		var province: ProvinceState = model.get_province(province_id)
		if province == null or not _claimable(province, factions, taken, tribe_total):
			continue
		chosen.append(province_id)
		tribe_total[province.owner] = maxi(int(tribe_total.get(province.owner, 0)) - 1, 0)
		for raw: Variant in MapGeo.province_neighbors(model, province_id):
			var neighbour: int = int(raw)
			if not frontier.has(neighbour) and _claimable(
				model.get_province(neighbour), factions, taken, tribe_total
			):
				frontier.append(neighbour)
	return chosen


## Tribe land still in play: the owner is a Tribe with a province to spare, the
## province is not its capital, and no crown has claimed it.
static func _claimable(
	province: ProvinceState,
	factions: Array[int],
	taken: Dictionary,
	tribe_total: Dictionary
) -> bool:
	if province == null or province.capital or taken.has(province.id):
		return false
	if FactionCatalog.type_of(province.owner) != FactionCatalog.Type.TRIBE:
		return false
	if factions.has(province.owner):
		return false
	return int(tribe_total.get(province.owner, 0)) > 1


static func _tribe_totals(model: MapModel) -> Dictionary:
	var totals: Dictionary = {}
	for province: ProvinceState in model.provinces:
		if FactionCatalog.type_of(province.owner) == FactionCatalog.Type.TRIBE:
			totals[province.owner] = int(totals.get(province.owner, 0)) + 1
	return totals


static func _on_passage(model: MapModel, province_id: int, zones: Array[int]) -> bool:
	if zones.is_empty():
		return true
	for zone: int in NavalMovement.province_sea_zones(model, province_id):
		if zones.has(zone):
			return true
	return false


## Provinces a reveal share charts for a crown (contiguous from the Passage).
static func charted_provinces(world: WorldMap, share: float) -> Array[int]:
	var model: MapModel = _new_world(world)
	if model == null or share <= 0.0:
		return []
	return _reveal_set(model, share, world.warp_zones(world.region_count() - 1))


## The crown's inherited chart (wiki § NW sea-zone visibility): `share` of the
## New World provinces, contiguous from the Passage, plus the seas touching
## them charted at fogged. A fully revealed tier also paints the coastal water
## of every Great Power colony fully visible (the standard coastal pass).
static func reveal(
	world: WorldMap, visibility: VisibilityModel, faction: int, share: float
) -> int:
	if world == null or visibility == null or share <= 0.0:
		return 0
	var model: MapModel = _new_world(world)
	if model == null:
		return 0
	var reveal_ids: Array[int] = charted_provinces(world, share)
	for province_id: int in reveal_ids:
		visibility.reveal_province(province_id)
		_chart_seas(model, visibility, province_id, faction)
	return reveal_ids.size()


## Contiguous-from-the-Passage province set for a reveal share: breadth-first
## outward from the Passage shore, then the rest in id order until the share is
## covered (wiki § NW sea-zone visibility).
static func _reveal_set(model: MapModel, share: float, zones: Array[int]) -> Array[int]:
	var order: Array[int] = []
	var seen: Dictionary = {}
	var queue: Array[int] = []
	for province: ProvinceState in model.provinces:
		if _on_passage(model, province.id, zones):
			queue.append(province.id)
	queue.sort()
	var head: int = 0
	while head < queue.size():
		var province_id: int = queue[head]
		head += 1
		if seen.has(province_id):
			continue
		seen[province_id] = true
		order.append(province_id)
		var neighbours: Array = MapGeo.province_neighbors(model, province_id)
		neighbours.sort()
		for raw: Variant in neighbours:
			if not seen.has(int(raw)):
				queue.append(int(raw))
	for province: ProvinceState in model.provinces:
		if not seen.has(province.id):
			order.append(province.id)
	var want: int = clampi(ceili(float(order.size()) * clampf(share, 0.0, 1.0)), 0, order.size())
	return order.slice(0, want)


## Water touching a revealed shore: fogged, unless the crown owns the shore —
## then the ordinary coastal pass makes it fully visible.
static func _chart_seas(
	model: MapModel, visibility: VisibilityModel, province_id: int, faction: int
) -> void:
	var owner: int = model.province_owner(province_id)
	for zone: int in NavalMovement.province_sea_zones(model, province_id):
		if owner == faction:
			visibility.reveal_sea_zone(zone)
			continue
		var data: SeaZoneState = model.sea_zone_data(zone)
		if data == null:
			continue
		for tile: Vector2i in data.tiles:
			visibility.raise_to(model.index_of(tile.x, tile.y), CHARTED)


static func _new_world(world: WorldMap) -> MapModel:
	if world.region_count() < 2:
		return null
	return world.region(world.region_count() - 1)
