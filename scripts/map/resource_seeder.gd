class_name ResourceSeeder
extends RefCounted
## Places extractable resources on land tiles (wiki: tile-map-and-generation,
## resource-terrain-region-rules). A region carries a resource on
## `TARGET_SHARE` of its land tiles: every forest tile (the published 100%
## guarantee), then the cheapest, most wanted rows spread over the rest of the
## ground by the published spawn weight. The first tile a province receives is
## its dossier headline resource.
##
## Decisions: DR-20261115-16 (density), wiki § Forest terrain split (the 100%
## guarantee), § Multi-region cap (at most `BOTH_SHARE` "both" rows).

## Share of a region's land tiles that carry a resource (issue #676).
const TARGET_SHARE: float = 0.30
## At most this share of placed resources may be multi-region ("both") rows,
## and only where the tile offered no region-exclusive alternative.
const BOTH_SHARE: float = 0.30
## A hardwood New World tile carries the fur catch seven times in ten and timber
## otherwise (wiki: resource-terrain-region-rules § Forest terrain split).
const HARDWOOD_NW_FURS: int = 70


static func seed_resources(
	model: MapModel, table: Array[Dictionary], rng: RandomNumberGenerator
) -> void:
	var tally: Dictionary = {"both": 0, "exclusive": 0}
	_seed_forest(model, table, rng, tally)
	var placed: int = int(tally["both"]) + int(tally["exclusive"])
	_fill_open_ground(model, table, rng, tally, _target(model) - placed)


## Land tiles that should carry a resource in this region: the published share of
## the land.
static func _target(model: MapModel) -> int:
	var land: int = 0
	for y in model.height:
		for x in model.width:
			if model.is_land(x, y):
				land += 1
	return int(round(float(land) * TARGET_SHARE))


# --- the forest's guarantee --------------------------------------------------


## Every forest tile always carries a resource (wiki § Forest terrain split), so
## the guarantee is placed before the ground's share is spent. It walks the grid,
## because a forest cell between provinces still carries its timber.
static func _seed_forest(
	model: MapModel,
	table: Array[Dictionary],
	rng: RandomNumberGenerator,
	tally: Dictionary
) -> void:
	for y in model.height:
		for x in model.width:
			if not model.is_land(x, y):
				continue
			var terrain: int = model.terrain_at(x, y)
			if terrain != MapModel.Terrain.SCRUB_FOREST \
					and terrain != MapModel.Terrain.HARDWOOD_FOREST:
				continue
			if model.resource_at(x, y) != MapModel.NO_ID:
				continue
			var pick: int = _forest_pick(model, table, terrain, rng)
			if pick >= 0:
				var province: ProvinceState = model.get_province(model.province_at(x, y))
				_place(model, table, province, Vector2i(x, y), pick, tally)


static func _forest_pick(
	model: MapModel, table: Array[Dictionary], terrain: int, rng: RandomNumberGenerator
) -> int:
	if terrain == MapModel.Terrain.HARDWOOD_FOREST:
		# Hardwood is the fur country in the New World: furs seven times in ten,
		# timber otherwise, and timber always in the Old World.
		var furs: int = _index_for(table, "furs")
		if furs >= 0 and _allows(model, table[furs], terrain):
			if rng.randi_range(1, 100) <= HARDWOOD_NW_FURS:
				return furs
	return _index_for(table, "timber")


# --- the rest of the ground --------------------------------------------------


## Spend what the forest guarantee left of the region's share over the open
## ground, each province taking a slice in proportion to the tiles it can host.
static func _fill_open_ground(
	model: MapModel,
	table: Array[Dictionary],
	rng: RandomNumberGenerator,
	tally: Dictionary,
	left: int
) -> void:
	if left <= 0:
		return
	var open: Array[Array] = []
	var weights: Array[int] = []
	var total: int = 0
	for province: ProvinceState in model.provinces:
		var tiles: Array[Vector2i] = _open_tiles(model, table, province)
		open.append(tiles)
		weights.append(tiles.size())
		total += tiles.size()
	if total <= 0:
		return
	var quotas: Array[int] = _quotas(weights, total, mini(left, total))
	for index in open.size():
		var tiles: Array[Vector2i] = open[index]
		_shuffle(tiles, rng)
		var province: ProvinceState = model.provinces[index]
		for slot in mini(quotas[index], tiles.size()):
			var pick: int = _pick_resource(model, table, tiles[slot], rng, tally)
			if pick >= 0:
				_place(model, table, province, tiles[slot], pick, tally)


## Every land tile of the province a published row may stand on and that carries
## no resource yet. Forest tiles are already spent by the guarantee.
static func _open_tiles(
	model: MapModel, table: Array[Dictionary], province: ProvinceState
) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for tile: Vector2i in province.tiles:
		if not model.is_land(tile.x, tile.y):
			continue
		if model.resource_at(tile.x, tile.y) != MapModel.NO_ID:
			continue
		var terrain: int = model.terrain_at(tile.x, tile.y)
		if terrain == MapModel.Terrain.SCRUB_FOREST \
				or terrain == MapModel.Terrain.HARDWOOD_FOREST:
			continue
		for entry: Dictionary in table:
			if _allows(model, entry, terrain):
				tiles.append(tile)
				break
	return tiles


## Largest-remainder split of `left` places over the provinces' eligible tiles.
static func _quotas(weights: Array[int], total: int, left: int) -> Array[int]:
	var quotas: Array[int] = []
	var remainders: Array[float] = []
	var spent: int = 0
	for weight: int in weights:
		var exact: float = float(left) * float(weight) / float(maxi(total, 1))
		var whole: int = mini(int(floor(exact)), weight)
		quotas.append(whole)
		remainders.append(exact - float(whole))
		spent += whole
	var order: Array[int] = []
	for index in weights.size():
		order.append(index)
	order.sort_custom(func(a: int, b: int) -> bool:
		if is_equal_approx(remainders[a], remainders[b]):
			return a < b
		return remainders[a] > remainders[b]
	)
	var cursor: int = 0
	while spent < left and cursor < order.size():
		var index: int = order[cursor]
		if quotas[index] < weights[index]:
			quotas[index] += 1
			spent += 1
		cursor += 1
	return quotas


## Deterministic Fisher-Yates, so a seed's picks survive a refactor.
static func _shuffle(tiles: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	for index in range(tiles.size() - 1, 0, -1):
		var swap: int = rng.randi_range(0, index)
		if swap == index:
			continue
		var held: Vector2i = tiles[index]
		tiles[index] = tiles[swap]
		tiles[swap] = held


# --- picking a row ----------------------------------------------------------


static func _pick_resource(
	model: MapModel,
	table: Array[Dictionary],
	tile: Vector2i,
	rng: RandomNumberGenerator,
	tally: Dictionary
) -> int:
	var terrain: int = model.terrain_at(tile.x, tile.y)
	var options: Array[int] = []
	for index in table.size():
		if _allows(model, table[index], terrain):
			options.append(index)
	if options.is_empty():
		return -1
	# Multi-region cap: once "both" rows hold their published share, a tile that
	# offers a region-exclusive row takes it (wiki § Multi-region cap).
	if not both_allowed(int(tally["both"]), int(tally["exclusive"])):
		var exclusive: Array[int] = []
		for index: int in options:
			if not _is_both(table, index):
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


static func _place(
	model: MapModel,
	table: Array[Dictionary],
	province: ProvinceState,
	tile: Vector2i,
	pick: int,
	tally: Dictionary
) -> void:
	model.resource[model.index_of(tile.x, tile.y)] = pick
	var key: String = "both" if _is_both(table, pick) else "exclusive"
	tally[key] = int(tally[key]) + 1
	if province != null and province.resource == MapModel.NO_ID:
		province.resource = pick
		province.resource_tile = tile


## The published multi-region cap: whether a tile may still take a "both" row,
## given the tallies so far (wiki § Multi-region resource cap). Whole permille
## arithmetic, so the 30% line reads the same on every machine.
static func both_allowed(both: int, exclusive: int) -> bool:
	var placed: int = both + exclusive
	if placed <= 0:
		return true
	return both * 1000 < placed * int(round(BOTH_SHARE * 1000.0))


## One resource's share of a tile's draw: the reciprocal of its published price.
static func _spawn_weight(table: Array[Dictionary], index: int) -> float:
	var commodity: String = String(table[index].get("commodity", ""))
	return 1.0 / float(maxi(CommodityCatalog.base_price(commodity), 1))


## True when the row's region scope is the multi-region one ("both").
static func _is_both(table: Array[Dictionary], index: int) -> bool:
	var scope: String = String(table[index].get("scope", "both"))
	return scope == "both" or scope.is_empty()


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
