class_name AdvancedEstates
extends RefCounted
## Estates a progressed campaign already stands on: prospecting, level-1
## developments with roads, and the deeds Great Powers hold in Minor Nations
## (wiki: advanced-starts § Tier tables, § Bootstrap steps 10–11). Pure map and
## works mutation, deterministic in region / province / tile order (REQ-P3-03).
##
## Setup history, not orders: the share is applied as if the work had long since
## completed, so order gates (embassy, prospecting, worker) are not replayed.
## Tiles travel with their region record — both regions share grid coordinates.

const LEVEL_ONE: int = 1
const ORTHO: Array[Vector2i] = [
	Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP
]


## Marks `share` of each crown's prospect-required mineral tiles prospected.
static func prospect(
	world: WorldMap, works_by_region: Dictionary, factions: Array[int], share: float
) -> int:
	var marked: int = 0
	for faction: int in factions:
		var spots: Array[Dictionary] = _mineral_tiles(world, faction)
		var want: int = _share_count(spots.size(), share)
		var placed: int = 0
		for spot: Dictionary in spots:
			if placed >= want:
				break
			var model: MapModel = spot["model"]
			var tile: Vector2i = spot["tile"]
			var works: LandWorks = works_for(works_by_region, model)
			if works == null or works.is_prospected(faction, model, tile):
				continue
			works.set_prospected(faction, model, tile)
			placed += 1
			marked += 1
	return marked


## Raises level-1 improvements on `share` of a crown's developable tiles and
## roads each one back to its province town (wiki § Tier tables, § Bootstrap 11).
static func develop(
	world: WorldMap, works_by_region: Dictionary, factions: Array[int], share: float
) -> int:
	var raised: int = 0
	for faction: int in factions:
		var spots: Array[Dictionary] = _developable_tiles(world, faction)
		var want: int = _share_count(spots.size(), share)
		var placed: int = 0
		for spot: Dictionary in spots:
			if placed >= want:
				break
			if _develop(works_by_region, faction, spot["model"], spot["tile"], true):
				placed += 1
				raised += 1
	return raised


## Minor Nation land Great Powers already bought round-robin, at level 1. The
## deed is recorded on the tile; the province stays with its Minor
## (wiki: civilian-units § Merchant; § Tier tables "Minor development"). A deed
## lifts the seller's town the same way the Merchant's completion does
## (wiki: world-market § Minor and tribe auto-sell — the town stands at
## `min(4, 1 + deeds)`, DR-20261112-01), so the manufactures follow the land
## this tier already sold.
static func purchase_minor_land(
	world: WorldMap, works_by_region: Dictionary, buyers: Array[int], share: float
) -> int:
	if world == null or buyers.is_empty() or share <= 0.0:
		return 0
	var bought: int = 0
	var cursor: int = 0
	for model: MapModel in world.regions:
		for province: ProvinceState in model.provinces:
			if FactionCatalog.type_of(model.province_owner(province.id)) != FactionCatalog.Type.MINOR_NATION:
				continue
			var tiles: Array[Vector2i] = _province_resource_tiles(model, province.id)
			var want: int = _share_count(tiles.size(), share)
			var placed: int = 0
			for tile: Vector2i in tiles:
				if placed >= want:
					break
				if model.is_purchased_tile(tile):
					continue
				var buyer: int = buyers[cursor % buyers.size()]
				if not model.purchase_tile(tile, buyer):
					continue
				cursor += 1
				placed += 1
				_develop(works_by_region, buyer, model, tile, false)
				MinorTownGrowth.apply(model, province)
				bought += 1
	return bought


## One level-1 improvement; mineral tiles are prospected first so the estate is
## legally worked. Roads follow owned land to the province town when asked.
static func _develop(
	works_by_region: Dictionary,
	faction: int,
	model: MapModel,
	tile: Vector2i,
	roads: bool
) -> bool:
	var works: LandWorks = works_for(works_by_region, model)
	if model == null or works == null:
		return false
	var resource: int = model.resource_at(tile.x, tile.y)
	if resource < 0 or not ImprovementCatalog.known(resource):
		return false
	if works.improvement_at(model, tile) > 0:
		return false
	if ImprovementCatalog.needs_prospecting(resource):
		works.set_prospected(faction, model, tile)
	works.set_improvement(model, tile, LEVEL_ONE)
	if roads:
		_road_to_town(model, works, faction, tile)
	return true


## Owned land path from the estate to the province town, every tile roaded.
static func _road_to_town(
	model: MapModel, works: LandWorks, faction: int, tile: Vector2i
) -> void:
	var province: ProvinceState = model.get_province(model.province_at(tile.x, tile.y))
	if province == null:
		return
	var goal: Vector2i = province.town_tile
	if goal.x < 0:
		goal = province.capital_tile
	var path: Array[Vector2i] = _path(model, faction, tile, goal)
	for step: Vector2i in path:
		if works.transport_at(model, step) < LandWorks.TRANSPORT_ROAD:
			works.set_transport(model, step, LandWorks.TRANSPORT_ROAD)


## Breadth-first over land this crown owns; [] when the town is unreachable.
static func _path(
	model: MapModel, faction: int, start: Vector2i, goal: Vector2i
) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if goal.x < 0:
		return empty
	if start == goal:
		return [start]
	var parent: Dictionary = {}
	var seen: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	while head < queue.size():
		var tile: Vector2i = queue[head]
		head += 1
		for offset: Vector2i in ORTHO:
			var next := Vector2i(tile.x + offset.x, tile.y + offset.y)
			if seen.has(next) or not model.is_land(next.x, next.y):
				continue
			if model.owner_at(next.x, next.y) != faction:
				continue
			parent[next] = tile
			if next == goal:
				return _rebuild(parent, start, goal)
			seen[next] = true
			queue.append(next)
	return empty


static func _rebuild(
	parent: Dictionary, start: Vector2i, goal: Vector2i
) -> Array[Vector2i]:
	var path: Array[Vector2i] = [goal]
	var current: Vector2i = goal
	while current != start and path.size() < 4096:
		if not parent.has(current):
			var empty: Array[Vector2i] = []
			return empty
		current = parent[current]
		path.append(current)
	path.reverse()
	return path


## Land the crown holds (province or deed) with a resource, one stable order.
static func _developable_tiles(world: WorldMap, faction: int) -> Array[Dictionary]:
	var spots: Array[Dictionary] = []
	if world == null:
		return spots
	for model: MapModel in world.regions:
		for province: ProvinceState in model.provinces:
			if model.province_owner(province.id) != faction:
				continue
			for tile: Vector2i in _province_resource_tiles(model, province.id):
				if model.owner_at(tile.x, tile.y) == faction:
					spots.append({"model": model, "tile": tile})
		for tile: Vector2i in _deed_tiles(model, faction):
			if model.province_owner(model.province_at(tile.x, tile.y)) != faction:
				spots.append({"model": model, "tile": tile})
	return spots


static func _mineral_tiles(world: WorldMap, faction: int) -> Array[Dictionary]:
	var spots: Array[Dictionary] = []
	for spot: Dictionary in _developable_tiles(world, faction):
		var model: MapModel = spot["model"]
		var tile: Vector2i = spot["tile"]
		if ImprovementCatalog.needs_prospecting(model.resource_at(tile.x, tile.y)):
			spots.append(spot)
	return spots


static func _deed_tiles(model: MapModel, faction: int) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for province: ProvinceState in model.provinces:
		for tile: Vector2i in province.tiles:
			if model.is_purchased_tile(tile) and model.owner_at(tile.x, tile.y) == faction:
				tiles.append(tile)
	return tiles


static func _province_resource_tiles(model: MapModel, province_id: int) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for tile: Vector2i in model.province_tiles(province_id):
		var resource: int = model.resource_at(tile.x, tile.y)
		if resource >= 0 and ImprovementCatalog.known(resource):
			tiles.append(tile)
	return tiles


static func _share_count(total: int, share: float) -> int:
	if total <= 0 or share <= 0.0:
		return 0
	return clampi(ceili(float(total) * clampf(share, 0.0, 1.0)), 0, total)


## Works record for a region, created on first use and shared with the layer.
static func works_for(works_by_region: Dictionary, model: MapModel) -> LandWorks:
	if model == null:
		return null
	var key: int = model.region_id
	if not works_by_region.has(key) or works_by_region[key] == null:
		works_by_region[key] = LandWorks.new()
	return works_by_region[key] as LandWorks
