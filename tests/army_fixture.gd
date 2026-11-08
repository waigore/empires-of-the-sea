extends RefCounted
## Synthetic land map for army rules tests: two player provinces that do not
## touch, one enemy province beside the capital, one neutral province beside the
## far colony, and a second enemy province beside it.


static func build() -> MapModel:
	var model := MapModel.new()
	model.setup(9, 3)
	for y in 3:
		for x in 9:
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
	# Open water keeps the island colony out of land movement.
	for y in 3:
		model.terrain[model.index_of(7, y)] = MapModel.Terrain.OCEAN
	_set_province(model, 0, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)], 0, true)
	_set_province(model, 1, [Vector2i(4, 0), Vector2i(5, 0), Vector2i(4, 1), Vector2i(5, 1)], 0, false)
	_set_province(model, 2, [Vector2i(2, 0), Vector2i(2, 1)], 1, false)
	_set_province(model, 3, [Vector2i(3, 0), Vector2i(3, 1)], MapModel.NO_ID, false)
	_set_province(model, 4, [Vector2i(6, 0), Vector2i(6, 1)], 1, false)
	_set_province(model, 5, [Vector2i(8, 0), Vector2i(8, 1)], 0, false)
	# Owned corridor along the south coast links the capital to the colony.
	_set_province(
		model,
		6,
		[
			Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2),
			Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2),
		],
		0,
		false
	)
	model.faction_ids = [0, 1]
	return model


static func _set_province(
	model: MapModel,
	id: int,
	tiles: Array[Vector2i],
	owner: int,
	capital: bool
) -> void:
	var center := Vector2.ZERO
	for tile: Vector2i in tiles:
		model.province[model.index_of(tile.x, tile.y)] = id
		center += Vector2(tile)
	center /= float(tiles.size())
	var province := ProvinceState.create(id, "Province %d" % id, tiles, center, tiles.size(), owner, capital)
	if capital:
		province.capital_tile = tiles[0]
	model.provinces.append(province)


static func army(
	id: int,
	owner: int,
	province: int,
	types: Array[String],
	home: bool = false
) -> ArmyState:
	return ArmyState.muster(id, owner, province, home, types, id * 100 + 1)
