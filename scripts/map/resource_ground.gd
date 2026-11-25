class_name ResourceGround
extends RefCounted
## Reads the published resource-terrain-region table for one map (wiki:
## resource-terrain-region-rules): which rows a tile may host, which of them are
## the New World's money-makers, and the ground a province's money floor needs.
## The seeder places rows; this class only answers what the ground allows.

## The New World's cash crops: region-exclusive rows that fund a colony.
const MONEY_CROPS: Array[String] = ["sugarCane", "tobacco", "cotton"]
## Every New World province carries at least this many money-maker tiles where
## its ground can host them (issue #1520).
const PROVINCE_MONEY_FLOOR: int = 2
## The seeder keeps one row more than the published floor: the town pass levels
## its tile to plains and clears any row there, so a province sitting on exactly
## two could drop to one after the town is seated.
const PROVINCE_MONEY_MARGIN: int = PROVINCE_MONEY_FLOOR + 1
## The slot classes the open ground's fill draws by.
const SLOT_ANY: int = -1
const SLOT_ORE: int = 0
const SLOT_CASH: int = 1
const SLOT_RICH: int = 2
const SLOT_SEAM: int = 3


## True when the row fits the slot's class on this terrain.
static func fits_slot(
	model: MapModel, table: Array[Dictionary], index: int, terrain: int, slot: int
) -> bool:
	if slot == SLOT_ANY:
		return true
	var money: bool = is_money(table, index)
	if slot == SLOT_ORE:
		return not money
	if slot == SLOT_SEAM:
		return not money and not terrain_money(model, table, terrain)
	if not money:
		return false
	if slot == SLOT_CASH:
		return terrain == MapModel.Terrain.PLAINS
	if slot == SLOT_RICH:
		return terrain != MapModel.Terrain.PLAINS
	return true


## True when the row may stand on this terrain in this region.
static func allows(model: MapModel, entry: Dictionary, terrain: int) -> bool:
	if not (entry.get("terrain", []) as Array).has(terrain):
		return false
	return scope_allows(model, entry)


## Wiki region column: ow / nw / both (default both when omitted).
static func scope_allows(model: MapModel, entry: Dictionary) -> bool:
	var scope: String = String(entry.get("scope", "both"))
	if scope == "both" or scope.is_empty():
		return true
	var new_world: bool = model.region_id == FactionCatalog.NEW_WORLD
	if scope == "nw":
		return new_world
	if scope == "ow":
		return not new_world
	return true


## True when the row is one of the New World's money-makers: a cash crop or a
## rich. They are the rows that fund a colony (issue #1520).
static func is_money(table: Array[Dictionary], index: int) -> bool:
	if index < 0 or index >= table.size():
		return false
	var commodity: String = String(table[index].get("commodity", ""))
	return MONEY_CROPS.has(commodity) or CommodityCatalog.is_riches(commodity)


## True when this terrain may host a row of the asked class in this region.
static func terrain_money(model: MapModel, table: Array[Dictionary], terrain: int) -> bool:
	for index in table.size():
		if is_money(table, index) and allows(model, table[index], terrain):
			return true
	return false


## True when this terrain may host a row that is not a money-maker — the ores a
## money slot's ground could be spent on instead.
static func terrain_ore(model: MapModel, table: Array[Dictionary], terrain: int) -> bool:
	for index in table.size():
		if not is_money(table, index) and allows(model, table[index], terrain):
			return true
	return false


## How many of `tiles` host a money-maker row on plains ground (the cash crops'
## ground) or off it (the rich ground: hills, peaks, desert).
static func money_ground_count(
	model: MapModel, table: Array[Dictionary], tiles: Array[Vector2i], plains: bool
) -> int:
	var count: int = 0
	for tile: Vector2i in tiles:
		var terrain: int = model.terrain_at(tile.x, tile.y)
		if (terrain == MapModel.Terrain.PLAINS) != plains:
			continue
		if terrain_money(model, table, terrain):
			count += 1
	return count


## How many of `tiles` host an ore that no money-maker row competes for (the
## swamp's tin), the seams the ore slots can spend without touching rich ground.
static func exclusive_seam_count(
	model: MapModel, table: Array[Dictionary], tiles: Array[Vector2i]
) -> int:
	var count: int = 0
	for tile: Vector2i in tiles:
		var terrain: int = model.terrain_at(tile.x, tile.y)
		if terrain_ore(model, table, terrain) and not terrain_money(model, table, terrain):
			count += 1
	return count


## True when the tile offers at least one published row of the asked class.
static func offers(
	model: MapModel, table: Array[Dictionary], tile: Vector2i, money: bool
) -> bool:
	var terrain: int = model.terrain_at(tile.x, tile.y)
	return terrain_money(model, table, terrain) if money else terrain_ore(model, table, terrain)


## How many of `tiles` still offer a row of the asked class.
static func class_count(
	model: MapModel, table: Array[Dictionary], tiles: Array[Vector2i], money: bool
) -> int:
	var count: int = 0
	for tile: Vector2i in tiles:
		if model.resource_at(tile.x, tile.y) != MapModel.NO_ID:
			continue
		if offers(model, table, tile, money):
			count += 1
	return count


# --- ground for the money-maker floor ----------------------------------------


## The New World's per-province money floor needs ground to stand on: a province
## whose open land hosts fewer than `PROVINCE_MONEY_FLOOR` money-maker sites has
## the thinnest of its cover levelled to plains first, the same
## select-then-convert the capital farms use (wiki § Open-ground split). Swamp
## goes first, then scrub, then hardwood; nearest the province centre, ties to
## the lower row then the lower column.
static func open_money_ground(model: MapModel, table: Array[Dictionary]) -> void:
	if model.region_id != FactionCatalog.NEW_WORLD:
		return
	for province: ProvinceState in model.provinces:
		var capable: int = 0
		var cover: Array[Vector2i] = []
		for tile: Vector2i in province.tiles:
			if not model.is_land(tile.x, tile.y):
				continue
			var terrain: int = model.terrain_at(tile.x, tile.y)
			if terrain_money(model, table, terrain):
				capable += 1
				continue
			if _cover_rank(terrain) >= 0:
				cover.append(tile)
		var short: int = PROVINCE_MONEY_MARGIN - capable
		if short <= 0 or cover.is_empty():
			continue
		cover.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var order_a: int = _cover_rank(model.terrain_at(a.x, a.y))
			var order_b: int = _cover_rank(model.terrain_at(b.x, b.y))
			if order_a != order_b:
				return order_a < order_b
			var left: float = Vector2(a).distance_squared_to(province.center)
			var right: float = Vector2(b).distance_squared_to(province.center)
			if is_equal_approx(left, right):
				if a.y == b.y:
					return a.x < b.x
				return a.y < b.y
			return left < right
		)
		for index in mini(short, cover.size()):
			var tile: Vector2i = cover[index]
			model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.PLAINS


## Which cover is thinned first when a province has no money-maker ground;
## -1 for ground that is not cover.
static func _cover_rank(terrain: int) -> int:
	if terrain == MapModel.Terrain.SWAMP:
		return 0
	if terrain == MapModel.Terrain.SCRUB_FOREST:
		return 1
	if terrain == MapModel.Terrain.HARDWOOD_FOREST:
		return 2
	return -1