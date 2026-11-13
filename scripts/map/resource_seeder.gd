class_name ResourceSeeder
extends RefCounted
## Places extractable resources on province tiles (wiki: tile-map-and-generation,
## resource-terrain-region-rules). Provinces carry one to three developed resource
## tiles, the way the era's provinces do; the first placed tile is the province's
## headline resource for the dossier.

const MIN_PER_PROVINCE: int = 1
const MAX_PER_PROVINCE: int = 3
const EMPTY_CHANCE: float = 0.15
## A hardwood New World tile carries the fur catch seven times in ten and timber
## otherwise (wiki: resource-terrain-region-rules § Forest terrain split).
const HARDWOOD_NW_FURS: int = 70


static func seed_resources(
	model: MapModel, table: Array[Dictionary], rng: RandomNumberGenerator
) -> void:
	for province: ProvinceState in model.provinces:
		var wanted: int = rng.randi_range(MIN_PER_PROVINCE, MAX_PER_PROVINCE)
		if rng.randf() < EMPTY_CHANCE:
			wanted = 0
		for _slot in wanted:
			var tile: Vector2i = _free_tile(model, table, province, rng)
			if tile.x < 0:
				break
			var pick: int = _pick_resource(model, table, tile, rng)
			if pick < 0:
				break
			model.resource[model.index_of(tile.x, tile.y)] = pick
			if province.resource == MapModel.NO_ID:
				province.resource = pick
				province.resource_tile = tile


static func _free_tile(
	model: MapModel, table: Array[Dictionary], province: ProvinceState, rng: RandomNumberGenerator
) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for tile: Vector2i in province.tiles:
		if model.resource_at(tile.x, tile.y) != MapModel.NO_ID:
			continue
		var terrain: int = model.terrain_at(tile.x, tile.y)
		for entry: Dictionary in table:
			if not _allows(model, entry, terrain):
				continue
			candidates.append(tile)
			break
	if candidates.is_empty():
		return Vector2i(-1, -1)
	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func _pick_resource(
	model: MapModel, table: Array[Dictionary], tile: Vector2i, rng: RandomNumberGenerator
) -> int:
	var terrain: int = model.terrain_at(tile.x, tile.y)
	# Scrub forest always carries timber (wiki: resource-terrain-region-rules).
	if terrain == MapModel.Terrain.SCRUB_FOREST:
		return _index_for(table, "timber")
	if terrain == MapModel.Terrain.HARDWOOD_FOREST:
		# Hardwood is the fur country in the New World: furs seven times in ten
		# and timber otherwise (wiki: § Forest terrain split).
		var furs: int = _index_for(table, "furs")
		if furs >= 0 and _allows(model, table[furs], terrain):
			if rng.randi_range(1, 100) <= HARDWOOD_NW_FURS:
				return furs
		return _index_for(table, "timber")
	var options: Array[int] = []
	for index in table.size():
		if _allows(model, table[index], terrain):
			options.append(index)
	if options.is_empty():
		return -1
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
