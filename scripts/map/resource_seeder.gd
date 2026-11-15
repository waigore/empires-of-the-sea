class_name ResourceSeeder
extends RefCounted
## Places extractable resources on province tiles (wiki: tile-map-and-generation,
## resource-terrain-region-rules § Table, § Placement rate, § Forest terrain
## split, § Multi-region resource cap). The first placed tile is the province's
## headline resource for the dossier.
##
## The rate is published: a resource stands on 30% of a region's land tiles
## (DR-20261115-16; #676 raised it from the old one-to-three-per-province draw,
## which measured ~3% and left courts nothing to extract). Every forest cell is
## guaranteed one and is not charged to the share; the rest is split across the
## provinces' resource-legal open ground, and each tile's row is still drawn on
## spawn weight = 1 / default market price.

## Share of a region's land tiles that carry a resource.
const TARGET_SHARE: float = 0.30
## At most this share of the open-ground placements may be `both`-scope rows
## (wiki § Multi-region resource cap); the rest are region-exclusive rows.
const BOTH_SHARE: float = 0.30
## A hardwood New World tile carries the fur catch seven times in ten and timber
## otherwise (wiki: resource-terrain-region-rules § Forest terrain split).
const HARDWOOD_NW_FURS: int = 70


static func seed_resources(
	model: MapModel, table: Array[Dictionary], rng: RandomNumberGenerator
) -> void:
	if model.provinces.is_empty():
		return
	var target: int = _target(model)
	if target <= 0:
		return
	_seed_forest(model, table, rng)
	var placed: int = 0
	for y in model.height:
		for x in model.width:
			if model.resource_at(x, y) != MapModel.NO_ID:
				placed += 1
	# What the forests left of the share goes to the open ground, in proportion
	# to the resource-legal tiles each province holds.
	var pools: Array[Array] = []
	var sizes: Array[int] = []
	for province: ProvinceState in model.provinces:
		var pool: Array = _open_tiles(model, table, province)
		pools.append(pool)
		sizes.append(pool.size())
	_fill_open_ground(model, table, pools, _quotas(maxi(target - placed, 0), sizes), rng)


## Land tiles on the chart, the denominator of the published share: ocean and
## coastal water are excluded, and nothing else (wiki § Placement rate).
static func _target(model: MapModel) -> int:
	var land: int = 0
	for y in model.height:
		for x in model.width:
			if not model.is_sea(x, y):
				land += 1
	return int(round(TARGET_SHARE * float(land)))


## The forest guarantee: every hardwood and scrub cell carries its row, placed
## before the share and never charged to it (wiki § Forest terrain split).
static func _seed_forest(
	model: MapModel, table: Array[Dictionary], rng: RandomNumberGenerator
) -> void:
	for province: ProvinceState in model.provinces:
		for tile: Vector2i in province.tiles:
			var terrain: int = model.terrain_at(tile.x, tile.y)
			if not (
				terrain == MapModel.Terrain.HARDWOOD_FOREST
				or terrain == MapModel.Terrain.SCRUB_FOREST
			):
				continue
			if model.resource_at(tile.x, tile.y) != MapModel.NO_ID:
				continue
			_place(model, province, tile, _forest_pick(model, table, terrain, rng))


## Scrub and Old World hardwood carry timber; New World hardwood is the fur
## country (wiki § Forest terrain split).
static func _forest_pick(
	model: MapModel, table: Array[Dictionary], terrain: int, rng: RandomNumberGenerator
) -> int:
	if terrain == MapModel.Terrain.HARDWOOD_FOREST:
		var furs: int = _index_for(table, "furs")
		if furs >= 0 and _allows(model, table[furs], terrain):
			if rng.randi_range(1, 100) <= HARDWOOD_NW_FURS:
				return furs
	return _index_for(table, "timber")


## This province's free tiles that some published row may stand on, forests
## excluded (they are already placed) and land no row may stand on left out.
static func _open_tiles(
	model: MapModel, table: Array[Dictionary], province: ProvinceState
) -> Array:
	var tiles: Array = []
	for tile: Vector2i in province.tiles:
		# The town tile never carries a resource (wiki: capital-and-connectivity
		# § Town per province); the town is fixed before this pass.
		if tile == province.town_tile:
			continue
		if model.resource_at(tile.x, tile.y) != MapModel.NO_ID:
			continue
		var terrain: int = model.terrain_at(tile.x, tile.y)
		if (
			terrain == MapModel.Terrain.HARDWOOD_FOREST
			or terrain == MapModel.Terrain.SCRUB_FOREST
		):
			continue
		for entry: Dictionary in table:
			if _allows(model, entry, terrain):
				tiles.append(tile)
				break
	return tiles


## Largest-remainder split of `remaining` tiles over the provinces' legal ground,
## ties to the lower province id (wiki § Placement rate; DR-20261115-16).
static func _quotas(remaining: int, sizes: Array[int]) -> Array[int]:
	var quotas: Array[int] = []
	var total: int = 0
	for size: int in sizes:
		total += size
		quotas.append(0)
	if remaining <= 0 or total <= 0:
		return quotas
	var given: int = 0
	while given < remaining:
		var best: int = -1
		var best_owed: float = -INF
		for index in sizes.size():
			if quotas[index] >= sizes[index]:
				continue
			var owed: float = float(remaining) * float(sizes[index]) / float(total)
			owed -= float(quotas[index])
			if owed > best_owed + 0.000001:
				best_owed = owed
				best = index
		if best < 0:
			break
		quotas[best] += 1
		given += 1
	return quotas


## Fills the open ground province by province, holding the multi-region cap as
## the rows land (wiki § Multi-region resource cap).
static func _fill_open_ground(
	model: MapModel,
	table: Array[Dictionary],
	pools: Array[Array],
	quotas: Array[int],
	rng: RandomNumberGenerator
) -> void:
	var open_placed: int = 0
	var both_placed: int = 0
	for index in model.provinces.size():
		var province: ProvinceState = model.provinces[index]
		var pool: Array = pools[index]
		_shuffle(pool, rng)
		for slot in mini(quotas[index], pool.size()):
			var tile: Vector2i = pool[slot]
			var pick: int = _pick_resource(
				model, table, tile, rng, _cap_reached(both_placed, open_placed)
			)
			if pick < 0:
				continue
			_place(model, province, tile, pick)
			open_placed += 1
			if _is_both(table[pick]):
				both_placed += 1


## True once `both`-scope rows hold their 30% of the open-ground placements; a
## tile that still offers a region-exclusive row then takes it.
static func _cap_reached(both_placed: int, open_placed: int) -> bool:
	if open_placed <= 0:
		return false
	return float(both_placed) / float(open_placed) >= BOTH_SHARE


static func _is_both(entry: Dictionary) -> bool:
	var scope: String = String(entry.get("scope", "both"))
	return scope == "both" or scope.is_empty()


## One commodity for a tile: the published weight over the rows its terrain and
## region allow, and only region-exclusive rows once the cap binds.
static func _pick_resource(
	model: MapModel,
	table: Array[Dictionary],
	tile: Vector2i,
	rng: RandomNumberGenerator,
	capped: bool = false
) -> int:
	var terrain: int = model.terrain_at(tile.x, tile.y)
	var options: Array[int] = []
	for index in table.size():
		if _allows(model, table[index], terrain):
			options.append(index)
	if options.is_empty():
		return -1
	if capped:
		var exclusive: Array[int] = []
		for index: int in options:
			if not _is_both(table[index]):
				exclusive.append(index)
		if not exclusive.is_empty():
			options = exclusive
	# Spawn weight = 1 / default market price, so the dearer a resource is the
	# rarer it lies (wiki: resource-terrain-region-rules § Table).
	var total: float = 0.0
	for index: int in options:
		total += _spawn_weight(table, index)
	if total <= 0.0:
		return -1
	var roll: float = rng.randf() * total
	for index: int in options:
		roll -= _spawn_weight(table, index)
		if roll <= 0.0:
			return index
	return options[options.size() - 1]


## Writes one resource, keeping the province's first tile as its headline row.
static func _place(model: MapModel, province: ProvinceState, tile: Vector2i, pick: int) -> void:
	if pick < 0:
		return
	model.resource[model.index_of(tile.x, tile.y)] = pick
	if province.resource == MapModel.NO_ID:
		province.resource = pick
		province.resource_tile = tile


## Fisher-Yates, so each province's slice of the share lands on random tiles.
static func _shuffle(tiles: Array, rng: RandomNumberGenerator) -> void:
	for index in range(tiles.size() - 1, 0, -1):
		var swap: int = rng.randi_range(0, index)
		var held: Variant = tiles[index]
		tiles[index] = tiles[swap]
		tiles[swap] = held


## One resource's share of a tile's draw: the reciprocal of its published price.
static func _spawn_weight(table: Array[Dictionary], index: int) -> float:
	var commodity: String = String(table[index].get("commodity", ""))
	return 1.0 / float(maxi(CommodityCatalog.base_price(commodity), 1))


## True when the row may stand on this terrain in this region.
static func _allows(model: MapModel, entry: Dictionary, terrain: int) -> bool:
	if not (entry.get("terrain", []) as Array).has(terrain):
		return false
	return _scope_allows(model, entry)


## Index of the row whose commodity is `commodity`; -1 when the table has none.
static func _index_for(table: Array[Dictionary], commodity: String) -> int:
	for index in table.size():
		if String(table[index].get("commodity", "")) == commodity:
			return index
	return -1


## Wiki region column: ow / nw / both (default both when omitted).
static func _scope_allows(model: MapModel, entry: Dictionary) -> bool:
	var scope: String = String(entry.get("scope", "both"))
	if scope == "both" or scope.is_empty():
		return true
	var new_world: bool = model.region_id == FactionCatalog.NEW_WORLD
	if scope == "nw":
		return new_world
	if scope == "ow":
		return not new_world
	return true
