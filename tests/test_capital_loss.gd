extends GdToolsTest
## Capital loss, reassignment and a crown's fall (wiki: capital-and-connectivity
## §§ Capital loss and reassignment, Great Power fall, Minor Nation and Tribe
## terminal fall). Synthetic islands keep each acceptance case readable.

const WIDTH: int = 14
const HEIGHT: int = 12


func _blank() -> MapModel:
	var model := MapModel.new()
	model.setup(WIDTH, HEIGHT)
	return model


func _add_province(model: MapModel, id: int, owner: int, tiles: Array) -> void:
	var sum := Vector2.ZERO
	for tile: Vector2i in tiles:
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.PLAINS
		model.province[model.index_of(tile.x, tile.y)] = id
		sum += Vector2(tile)
	var typed_tiles: Array[Vector2i] = []
	for tile: Vector2i in tiles:
		typed_tiles.append(tile)
	model.provinces.append(
		ProvinceState.create(
			id, "P%d" % id, typed_tiles, sum / float(tiles.size()), tiles.size(), owner
		)
	)


func _block(x0: int, x1: int, y0: int, y1: int) -> Array:
	var tiles: Array = []
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			tiles.append(Vector2i(x, y))
	return tiles


func _world(model: MapModel) -> WorldMap:
	var world := WorldMap.new()
	world.add_region(model)
	return world


## One open sea zone on every water tile, so province seaboards exist.
func _paint_sea(model: MapModel) -> void:
	for y in model.height:
		for x in model.width:
			if model.is_sea(x, y):
				model.sea_zone[model.index_of(x, y)] = 0


## `get_province(id)` indexes the roster, so synthetic fixtures keep ids dense.
func _order(model: MapModel) -> void:
	model.provinces.sort_custom(func(a: ProvinceState, b: ProvinceState) -> bool: return a.id < b.id)


## Two separate sea-bound islands for the Great Power.
func _great_power_holding() -> MapModel:
	var model := _blank()
	_add_province(model, 0, 0, _block(1, 3, 1, 3))
	_add_province(model, 1, 0, _block(7, 9, 1, 3))
	_add_province(model, 3, 1, _block(1, 7, 9, 9))
	_paint_sea(model)
	_order(model)
	return model


func _take(model: MapModel, province_id: int, owner: int) -> void:
	model.get_province(province_id).owner = owner


# --- Great Power ------------------------------------------------------------


func test_lost_capital_moves_to_another_sea_bound_province() -> void:
	var model := _great_power_holding()
	assert_true(CapitalChoice.place_capital(model, 0)["ok"])
	var world := _world(model)
	_take(model, 0, 1)

	var changes: Array[Dictionary] = CapitalLoss.resolve(world)

	assert_eq(changes.size(), 1)
	var change: Dictionary = changes[0]
	assert_eq(int(change["faction"]), 0)
	assert_false(bool(change["fallen"]))
	assert_eq(int(change["capital_province"]), 1)
	assert_eq(int(change["conqueror"]), 1)
	assert_false(model.get_province(0).capital)
	assert_eq(model.get_province(0).capital_of, MapModel.NO_ID)
	assert_true(model.get_province(1).capital)
	assert_eq(model.get_province(1).capital_of, 0)
	assert_eq(model.get_province(1).town_development, CapitalChoice.CAPITAL_TOWN_DEVELOPMENT)


func test_relocated_seat_has_a_capital_tile_on_its_own_ground() -> void:
	var model := _great_power_holding()
	assert_true(CapitalChoice.place_capital(model, 0)["ok"])
	_take(model, 0, 1)
	CapitalLoss.resolve(_world(model))

	var seat: ProvinceState = model.get_province(1)
	assert_true(seat.capital_tile.x >= 0)
	assert_true(seat.tiles.has(seat.capital_tile))


func test_great_power_falls_when_it_keeps_no_sea_bound_province() -> void:
	var model := _blank()
	_add_province(model, 0, 0, _block(1, 3, 1, 3))
	# P1 sits inside P2's ring (owned by the enemy), so it never touches the sea.
	_add_province(model, 2, 1, _block(6, 9, 1, 4))
	_add_province(model, 1, 0, [Vector2i(7, 2), Vector2i(8, 2)])
	_add_province(model, 3, 1, _block(1, 8, 8, 9))
	_paint_sea(model)
	_order(model)
	assert_true(CapitalChoice.place_capital(model, 0)["ok"])
	var world := _world(model)
	_take(model, 0, 1)

	var changes: Array[Dictionary] = CapitalLoss.resolve(world)

	assert_eq(changes.size(), 1)
	assert_true(bool(changes[0]["fallen"]))
	assert_eq(int(changes[0]["capital_province"]), MapModel.NO_ID)
	assert_eq(model.get_province(1).owner, 1)
	assert_eq(model.get_province(2).owner, 1)
	assert_false(model.get_province(0).capital)


func test_second_resolution_finds_nothing_left_to_do() -> void:
	var model := _great_power_holding()
	assert_true(CapitalChoice.place_capital(model, 0)["ok"])
	var world := _world(model)
	_take(model, 0, 1)
	assert_eq(CapitalLoss.resolve(world).size(), 1)

	assert_eq(CapitalLoss.resolve(world).size(), 0)
	assert_eq(model.get_province(1).capital_of, 0)


# --- Minors and tribes ------------------------------------------------------


func test_minor_relocates_even_to_an_inland_province() -> void:
	var model := _blank()
	_add_province(model, 0, 6, _block(1, 3, 1, 3))
	# The Minor's other holding is inland: a ring owned by the enemy surrounds it.
	_add_province(model, 2, 0, _block(6, 9, 1, 4))
	_add_province(model, 1, 6, [Vector2i(7, 2), Vector2i(8, 2)])
	_add_province(model, 3, 0, _block(1, 8, 8, 9))
	_paint_sea(model)
	_order(model)
	assert_true(CapitalChoice.place_capital(model, 6, CapitalChoice.KIND_MINOR)["ok"])
	var world := _world(model)
	_take(model, 0, 0)

	var changes: Array[Dictionary] = CapitalLoss.resolve(world)

	assert_eq(changes.size(), 1)
	assert_false(bool(changes[0]["fallen"]))
	assert_eq(int(changes[0]["capital_province"]), 1)
	assert_true(model.get_province(1).capital)
	assert_eq(model.get_province(1).capital_of, 6)
	# A Minor keeps the province's own town development.
	assert_eq(model.get_province(1).town_development, 0)


func test_minor_falls_when_it_loses_every_province() -> void:
	var model := _blank()
	_add_province(model, 0, 6, _block(1, 3, 1, 3))
	_add_province(model, 1, 0, _block(1, 8, 8, 9))
	_paint_sea(model)
	_order(model)
	assert_true(CapitalChoice.place_capital(model, 6, CapitalChoice.KIND_MINOR)["ok"])
	var world := _world(model)
	_take(model, 0, 0)

	var changes: Array[Dictionary] = CapitalLoss.resolve(world)

	assert_eq(changes.size(), 1)
	assert_true(bool(changes[0]["fallen"]))
	assert_false(model.get_province(0).capital)
	assert_eq(model.get_province(0).capital_of, MapModel.NO_ID)


# --- Stale seats ------------------------------------------------------------


func test_captured_seat_never_marks_a_capital_for_the_conqueror() -> void:
	var model := _blank()
	_add_province(model, 0, 0, _block(1, 3, 1, 3))
	_add_province(model, 1, 0, _block(6, 8, 1, 3))
	_add_province(model, 2, 1, _block(1, 8, 8, 9))
	_paint_sea(model)
	_order(model)
	assert_true(CapitalChoice.place_capital(model, 0)["ok"])
	assert_true(CapitalChoice.place_capital(model, 1)["ok"])
	var world := _world(model)
	_take(model, 0, 1)

	CapitalLoss.resolve(world)

	assert_false(model.get_province(0).capital)
	assert_eq(model.get_province(0).capital_of, MapModel.NO_ID)
	assert_true(model.get_province(2).capital)
	assert_eq(model.get_province(2).capital_of, 1)
	assert_eq(model.get_province(0).owner, 1)


func test_absorbed_crown_seat_is_retired_without_a_fall() -> void:
	var model := _blank()
	_add_province(model, 0, 6, _block(1, 3, 1, 3))
	_add_province(model, 1, 0, _block(7, 9, 1, 3))
	_paint_sea(model)
	_order(model)
	assert_true(CapitalChoice.place_capital(model, 6, CapitalChoice.KIND_MINOR)["ok"])
	assert_true(CapitalChoice.place_capital(model, 0)["ok"])
	var world := _world(model)
	# Join Empire moves the Minor's only province and retires its seat.
	_take(model, 0, 0)
	CapitalLoss.retire_seat(world, 6)

	assert_eq(CapitalLoss.resolve(world).size(), 0)
	assert_false(model.get_province(0).capital)
	assert_eq(model.get_province(0).capital_of, MapModel.NO_ID)
	assert_true(model.get_province(1).capital)


func test_purge_owner_disbands_only_the_fallen_crowns_regiments() -> void:
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 0, 0, true, ["peasant_levies", "pikemen"]),
		ArmyState.muster(2, 1, 0, true, ["peasant_levies"]),
	]
	assert_eq(ArmyState.purge_owner(armies, 0), 2)
	assert_eq(armies.size(), 1)
	assert_eq(armies[0].owner, 1)


func test_same_board_resolves_the_same_way() -> void:
	var first := _great_power_holding()
	var second := _great_power_holding()
	assert_true(CapitalChoice.place_capital(first, 0)["ok"])
	assert_true(CapitalChoice.place_capital(second, 0)["ok"])
	_take(first, 0, 1)
	_take(second, 0, 1)

	var a: Array[Dictionary] = CapitalLoss.resolve(_world(first))
	var b: Array[Dictionary] = CapitalLoss.resolve(_world(second))

	assert_eq(a.size(), b.size())
	assert_eq(int(a[0]["capital_province"]), int(b[0]["capital_province"]))
	assert_eq(a[0]["capital_tile"], b[0]["capital_tile"])
