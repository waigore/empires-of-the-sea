class_name ResourceSeeder
extends RefCounted
## Places extractable resources on land tiles (wiki: tile-map-and-generation,
## resource-terrain-region-rules). A region's open ground carries a resource on
## `TARGET_SHARE` of its land tiles. Every forest tile carries its guaranteed row
## (the published 100% forest guarantee) on top of that share, and no forest row
## is charged to the share or to the multi-region cap.
##
## The New World's open ground splits its slots: `ResourceSlots` gives
## `MONEY_SHARE` to the region-exclusive money-makers (the cash crops and the
## riches) and the rest to the `both`-scope ores, so a colony can fund a win.
## Each province takes a slice of that ground in proportion to the tiles it
## holds, and every province keeps the money-maker floor where its ground can
## host one. The Old World keeps the published price-weighted draw under the 30%
## multi-region cap.
##
## Decisions: DR-20261115-16 (density), DR-20261126-01 (open share, New World
## money-makers), wiki § Forest terrain split (the 100% guarantee), § Open-ground
## split, § Multi-region cap.

## Share of a region's land tiles its open ground carries a resource on (issue
## #676; issue #1520). The forest guarantee stands outside this share.
const TARGET_SHARE: float = 0.30
## At most this share of the Old World's open-ground rows may be multi-region
## ("both") rows, and only where the tile offered no region-exclusive alternative.
const BOTH_SHARE: float = 0.30
## A hardwood New World tile carries the fur catch seven times in ten and timber
## otherwise (wiki: resource-terrain-region-rules § Forest terrain split).
const HARDWOOD_NW_FURS: int = 70


static func seed_resources(
	model: MapModel, table: Array[Dictionary], rng: RandomNumberGenerator
) -> void:
	ResourceGround.open_money_ground(model, table)
	var tally: Dictionary = {"both": 0, "exclusive": 0}
	_seed_forest(model, table, rng)
	_fill_open_ground(model, table, rng, tally)


## Land tiles that should carry a resource on the open ground in this region:
## the published share of the land, whatever the forests already carry.
static func _target(model: MapModel) -> int:
	var land: int = 0
	for y in model.height:
		for x in model.width:
			if model.is_land(x, y):
				land += 1
	return int(round(float(land) * TARGET_SHARE))


# --- the forest's guarantee --------------------------------------------------


## Every forest tile always carries a resource (wiki § Forest terrain split), and
## the guarantee is not charged to the open ground's share nor to the cap. It
## walks the grid, because a forest cell between provinces still carries its
## timber.
static func _seed_forest(
	model: MapModel, table: Array[Dictionary], rng: RandomNumberGenerator
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
				_place(model, table, province, Vector2i(x, y), pick)


static func _forest_pick(
	model: MapModel, table: Array[Dictionary], terrain: int, rng: RandomNumberGenerator
) -> int:
	if terrain == MapModel.Terrain.HARDWOOD_FOREST:
		# Hardwood is the fur country in the New World: furs seven times in ten,
		# timber otherwise, and timber always in the Old World.
		var furs: int = _index_for(table, "furs")
		if furs >= 0 and ResourceGround.allows(model, table[furs], terrain):
			if rng.randi_range(1, 100) <= HARDWOOD_NW_FURS:
				return furs
	return _index_for(table, "timber")


# --- the rest of the ground ---------------------------------------------------


## Spend the open ground's published share over the region's open tiles, each
## province taking a slice in proportion to the tiles it can host, split by class
## as `ResourceSlots` plans it.
static func _fill_open_ground(
	model: MapModel,
	table: Array[Dictionary],
	rng: RandomNumberGenerator,
	tally: Dictionary
) -> void:
	var target: int = _target(model)
	if target <= 0:
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
	var places: int = mini(target, total)
	var quotas: Array[int] = ResourceSlots.quotas(weights, total, places)
	var plan: Dictionary = ResourceSlots.plan(model, table, open, quotas, places)
	var cash: Array[int] = plan["cash"]
	var rich: Array[int] = plan["rich"]
	var seam: Array[int] = plan["seam"]
	var ore: Array[int] = plan["ore"]
	# The Old World spends its whole slice on one published draw (the multi-region
	# cap binds there); the New World's slice arrives split by class.
	var ore_slot: int = (
		ResourceGround.SLOT_ANY if model.region_id != FactionCatalog.NEW_WORLD
		else ResourceGround.SLOT_ORE
	)
	for index in open.size():
		var tiles: Array[Vector2i] = open[index]
		_shuffle(tiles, rng)
		var province: ProvinceState = model.provinces[index]
		var wanted: int = cash[index] + rich[index] + seam[index] + ore[index]
		var spent: int = _seed_class(
			model, table, rng, province, tiles, cash[index], ResourceGround.SLOT_CASH, tally
		)
		spent += _seed_class(
			model, table, rng, province, tiles, rich[index], ResourceGround.SLOT_RICH, tally
		)
		spent += _seed_class(
			model, table, rng, province, tiles, seam[index], ResourceGround.SLOT_SEAM, tally
		)
		spent += _seed_class(
			model, table, rng, province, tiles, ore[index], ore_slot, tally
		)
		# A class can run out of free ground where two classes share a terrain
		# (hills host silver and ore); the rest of the slice takes any legal row.
		_seed_class(
			model, table, rng, province, tiles, maxi(0, wanted - spent),
			ResourceGround.SLOT_ANY, tally
		)


## Places up to `want` rows of one slot class on the province's free tiles.
## Returns how many it placed.
static func _seed_class(
	model: MapModel,
	table: Array[Dictionary],
	rng: RandomNumberGenerator,
	province: ProvinceState,
	tiles: Array[Vector2i],
	want: int,
	slot: int,
	tally: Dictionary
) -> int:
	if want <= 0:
		return 0
	var placed: int = 0
	for tile: Vector2i in tiles:
		if placed >= want:
			break
		if model.resource_at(tile.x, tile.y) != MapModel.NO_ID:
			continue
		var pick: int = _pick_resource(model, table, tile, rng, slot, tally)
		if pick < 0:
			continue
		_place(model, table, province, tile, pick)
		var key: String = "both" if _is_both(table, pick) else "exclusive"
		tally[key] = int(tally[key]) + 1
		placed += 1
	return placed


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
			if ResourceGround.allows(model, entry, terrain):
				tiles.append(tile)
				break
	return tiles


## Deterministic Fisher-Yates, so a seed's picks survive a refactor.
static func _shuffle(tiles: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	for index in range(tiles.size() - 1, 0, -1):
		var swap: int = rng.randi_range(0, index)
		if swap == index:
			continue
		var held: Vector2i = tiles[index]
		tiles[index] = tiles[swap]
		tiles[swap] = held


# --- picking a row -----------------------------------------------------------


## Draws a row for the tile among the rows its slot may host. The spawn weight is
## 1 / default market price, so the dearer a resource is the rarer it lies; the
## multi-region cap binds the Old World's published draw (wiki § Table, § Cap).
static func _pick_resource(
	model: MapModel,
	table: Array[Dictionary],
	tile: Vector2i,
	rng: RandomNumberGenerator,
	slot: int,
	tally: Dictionary
) -> int:
	var terrain: int = model.terrain_at(tile.x, tile.y)
	var options: Array[int] = []
	for index in table.size():
		if not ResourceGround.allows(model, table[index], terrain):
			continue
		if not ResourceGround.fits_slot(model, table, index, terrain, slot):
			continue
		options.append(index)
	if options.is_empty():
		return -1
	# Multi-region cap (Old World): once "both" rows hold their published share,
	# a tile that offers a region-exclusive row takes it.
	if slot == ResourceGround.SLOT_ANY \
			and not both_allowed(int(tally["both"]), int(tally["exclusive"])):
		var exclusive: Array[int] = []
		for index: int in options:
			if not _is_both(table, index):
				exclusive.append(index)
		if not exclusive.is_empty():
			options = exclusive
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
	pick: int
) -> void:
	model.resource[model.index_of(tile.x, tile.y)] = pick
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


## Index of the row whose commodity is `commodity`; -1 when the table has none.
static func _index_for(table: Array[Dictionary], commodity: String) -> int:
	for index in table.size():
		if String(table[index].get("commodity", "")) == commodity:
			return index
	return -1