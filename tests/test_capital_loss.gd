extends GdToolsTest
## A captured capital re-seats the court or ends the crown (wiki:
## capital-and-connectivity § Capital loss and reassignment; DR-20261109-02).
## Synthetic islands keep each acceptance case readable.

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


## `get_province(id)` indexes the roster, so synthetic fixtures keep ids dense.
func _order(model: MapModel) -> void:
	model.provinces.sort_custom(func(a: ProvinceState, b: ProvinceState) -> bool: return a.id < b.id)


## One open sea zone on every water tile, so province seaboards exist.
func _paint_sea(model: MapModel) -> void:
	for y in model.height:
		for x in model.width:
			if model.is_sea(x, y):
				model.sea_zone[model.index_of(x, y)] = 0


func _take(model: MapModel, province_id: int, owner: int) -> void:
	model.get_province(province_id).owner = owner


## Two separate sea-bound islands for the Great Power plus the enemy's holding.
func _great_power_holding() -> MapModel:
	var model := _blank()
	_add_province(model, 0, 0, _block(1, 3, 1, 3))
	_add_province(model, 1, 0, _block(7, 9, 1, 3))
	_add_province(model, 3, 1, _block(1, 7, 9, 9))
	_paint_sea(model)
	_order(model)
	return model


# --- Great Power ------------------------------------------------------------


func test_lost_capital_moves_to_another_sea_bound_province() -> void:
	var model := _great_power_holding()
	assert_true(CapitalChoice.place_capital(model, 0)["ok"])
	var world := _world(model)
	var seats: Dictionary = CapitalLoss.snapshot(world)
	_take(model, 0, 1)

	var changes: Array[Dictionary] = CapitalLoss.resolve(world, seats)

	assert_eq(changes.size(), 1)
	var change: Dictionary = changes[0]
	assert_eq(int(change["faction"]), 0)
	assert_false(bool(change["fallen"]))
	assert_eq(int(change["capital_province"]), 1)
	assert_eq(int(change["conqueror"]), 1)
	assert_false(model.get_province(0).capital)
	assert_true(model.get_province(1).capital)
	assert_eq(model.get_province(1).town_development, CapitalChoice.CAPITAL_TOWN_DEVELOPMENT)


func test_relocated_seat_has_a_capital_tile_on_its_own_ground() -> void:
	var model := _great_power_holding()
	assert_true(CapitalChoice.place_capital(model, 0)["ok"])
	var world := _world(model)
	var seats: Dictionary = CapitalLoss.snapshot(world)
	_take(model, 0, 1)
	CapitalLoss.resolve(world, seats)

	var seat: ProvinceState = model.get_province(1)
	assert_true(seat.capital_tile.x >= 0)
	assert_true(seat.tiles.has(seat.capital_tile))


func test_a_sea_bound_province_is_chosen_before_an_inland_one() -> void:
	var model := _blank()
	# P0 is the capital; P1 is another sea-bound island; P2 sits inland inside
	# the enemy's ring, so only P1 satisfies the seaboard preference.
	_add_province(model, 0, 0, _block(1, 3, 1, 3))
	_add_province(model, 1, 0, _block(7, 9, 1, 3))
	_add_province(model, 4, 1, _block(6, 9, 6, 9))
	_add_province(model, 2, 0, [Vector2i(7, 7), Vector2i(8, 7)])
	_add_province(model, 3, 1, _block(1, 7, 10, 11))
	_paint_sea(model)
	_order(model)
	assert_true(CapitalChoice.place_capital(model, 0)["ok"])
	var world := _world(model)
	var seats: Dictionary = CapitalLoss.snapshot(world)
	_take(model, 0, 1)

	var changes: Array[Dictionary] = CapitalLoss.resolve(world, seats)

	assert_false(bool(changes[0]["fallen"]))
	assert_eq(int(changes[0]["capital_province"]), 1)


func test_great_power_with_only_inland_provinces_keeps_its_court() -> void:
	var model := _blank()
	_add_province(model, 0, 0, _block(1, 3, 1, 3))
	_add_province(model, 2, 1, _block(6, 9, 1, 4))
	_add_province(model, 1, 0, [Vector2i(7, 2), Vector2i(8, 2)])
	_add_province(model, 3, 1, _block(1, 8, 8, 9))
	_paint_sea(model)
	_order(model)
	assert_true(CapitalChoice.place_capital(model, 0)["ok"])
	var world := _world(model)
	var seats: Dictionary = CapitalLoss.snapshot(world)
	_take(model, 0, 1)

	var changes: Array[Dictionary] = CapitalLoss.resolve(world, seats)

	assert_false(bool(changes[0]["fallen"]))
	assert_eq(int(changes[0]["capital_province"]), 1)


func test_crown_with_no_province_left_in_the_region_falls() -> void:
	var model := _blank()
	_add_province(model, 0, 0, _block(1, 3, 1, 3))
	_add_province(model, 1, 1, _block(1, 8, 8, 9))
	_paint_sea(model)
	_order(model)
	assert_true(CapitalChoice.place_capital(model, 0)["ok"])
	var world := _world(model)
	var seats: Dictionary = CapitalLoss.snapshot(world)
	_take(model, 0, 1)

	var changes: Array[Dictionary] = CapitalLoss.resolve(world, seats)

	assert_eq(changes.size(), 1)
	assert_true(bool(changes[0]["fallen"]))
	assert_eq(int(changes[0]["capital_province"]), MapModel.NO_ID)
	assert_false(model.get_province(0).capital)


func test_second_resolution_finds_nothing_left_to_do() -> void:
	var model := _great_power_holding()
	assert_true(CapitalChoice.place_capital(model, 0)["ok"])
	var world := _world(model)
	var seats: Dictionary = CapitalLoss.snapshot(world)
	_take(model, 0, 1)
	assert_eq(CapitalLoss.resolve(world, seats).size(), 1)

	assert_eq(CapitalLoss.resolve(world, CapitalLoss.snapshot(world)).size(), 0)
	assert_true(model.get_province(1).capital)


# --- Minors and tribes ------------------------------------------------------


func test_minor_relocates_to_an_inland_province() -> void:
	var model := _blank()
	_add_province(model, 0, 6, _block(1, 3, 1, 3))
	_add_province(model, 2, 0, _block(6, 9, 1, 4))
	_add_province(model, 1, 6, [Vector2i(7, 2), Vector2i(8, 2)])
	_add_province(model, 3, 0, _block(1, 8, 8, 9))
	_paint_sea(model)
	_order(model)
	assert_true(CapitalChoice.place_capital(model, 6, CapitalChoice.KIND_MINOR)["ok"])
	var world := _world(model)
	var seats: Dictionary = CapitalLoss.snapshot(world)
	_take(model, 0, 0)

	var changes: Array[Dictionary] = CapitalLoss.resolve(world, seats)

	assert_false(bool(changes[0]["fallen"]))
	assert_eq(int(changes[0]["capital_province"]), 1)
	assert_true(model.get_province(1).capital)
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
	var seats: Dictionary = CapitalLoss.snapshot(world)
	_take(model, 0, 0)

	var changes: Array[Dictionary] = CapitalLoss.resolve(world, seats)

	assert_eq(changes.size(), 1)
	assert_true(bool(changes[0]["fallen"]))
	assert_false(model.get_province(0).capital)


# --- Seats and stale flags --------------------------------------------------


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
	var seats: Dictionary = CapitalLoss.snapshot(world)
	_take(model, 0, 1)

	CapitalLoss.resolve(world, seats)

	assert_false(model.get_province(0).capital)
	assert_true(model.get_province(2).capital)
	assert_eq(model.get_province(0).owner, 1)


func test_absorption_leaves_no_verdict_when_the_seat_is_already_gone() -> void:
	var model := _blank()
	_add_province(model, 0, 6, _block(1, 3, 1, 3))
	_add_province(model, 1, 0, _block(7, 9, 1, 3))
	_paint_sea(model)
	_order(model)
	assert_true(CapitalChoice.place_capital(model, 6, CapitalChoice.KIND_MINOR)["ok"])
	assert_true(CapitalChoice.place_capital(model, 0)["ok"])
	var world := _world(model)
	# Join Empire moves the Minor's only province before Combat resolves.
	_take(model, 0, 0)

	assert_eq(CapitalLoss.resolve(world, CapitalLoss.snapshot(world)).size(), 0)


func test_seat_tile_is_nearest_the_province_centre() -> void:
	var province := ProvinceState.create(
		0, "P0", [Vector2i(0, 0), Vector2i(3, 0), Vector2i(0, 2)], Vector2(1, 1), 3, 0
	)
	assert_eq(CapitalLoss.seat_tile(province), Vector2i(0, 0))


func test_seat_tile_ties_go_by_row_then_column() -> void:
	var province := ProvinceState.create(
		0, "P0", [Vector2i(2, 0), Vector2i(0, 2)], Vector2(1, 1), 2, 0
	)
	assert_eq(CapitalLoss.seat_tile(province), Vector2i(2, 0))


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
	var first_world := _world(first)
	var second_world := _world(second)
	var first_seats: Dictionary = CapitalLoss.snapshot(first_world)
	var second_seats: Dictionary = CapitalLoss.snapshot(second_world)
	_take(first, 0, 1)
	_take(second, 0, 1)

	var a: Array[Dictionary] = CapitalLoss.resolve(first_world, first_seats)
	var b: Array[Dictionary] = CapitalLoss.resolve(second_world, second_seats)

	assert_eq(a.size(), b.size())
	assert_eq(int(a[0]["capital_province"]), int(b[0]["capital_province"]))
	assert_eq(a[0]["capital_tile"], b[0]["capital_tile"])
