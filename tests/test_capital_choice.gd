extends GdToolsTest
## Capital-choice phase rules (wiki: capital-choice-phase, capital-and-connectivity
## § Capital Setup). Synthetic maps keep each acceptance case readable.

const WIDTH: int = 12
const HEIGHT: int = 9


func _blank() -> MapModel:
	var model := MapModel.new()
	model.setup(WIDTH, HEIGHT)
	return model


## Claims tiles for a province, starting from ocean, and registers the province.
func _add_province(
	model: MapModel, id: int, owner: int, tiles: Array, terrain: int = MapModel.Terrain.PLAINS
) -> void:
	var sum := Vector2.ZERO
	for tile: Vector2i in tiles:
		model.terrain[model.index_of(tile.x, tile.y)] = terrain
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


## Paints every sea tile with a zone id chosen by position.
func _paint_sea(model: MapModel, zones: Callable) -> void:
	for y in model.height:
		for x in model.width:
			if model.is_sea(x, y):
				model.sea_zone[model.index_of(x, y)] = zones.call(x, y)


## 5x3 island at (3,3)-(7,5) with one sea zone on each side.
func _island_with_four_seaboards() -> MapModel:
	var model := _blank()
	_add_province(model, 0, 0, _block(3, 7, 3, 5))
	_paint_sea(model, func(x: int, y: int) -> int:
		if y <= 2:
			return 0
		if y >= 6:
			return 2
		if x <= 2:
			return 1
		return 3
	)
	return model


## Two separate islands, every sea tile in one zone.
func _two_islands() -> MapModel:
	var model := _blank()
	_add_province(model, 0, 0, _block(2, 4, 2, 4))
	_add_province(model, 1, 1, _block(7, 8, 6, 7))
	_paint_sea(model, func(_x: int, _y: int) -> int: return 0)
	return model


# --- province choice --------------------------------------------------------


func test_sea_bound_lookup_and_sorted_seaboards() -> void:
	var model := _island_with_four_seaboards()
	assert_true(CapitalChoice.is_sea_bound(model, 0))
	assert_eq(CapitalChoice.sea_bound_sea_zones(model, 0), [0, 1, 2, 3])


func test_great_power_skips_lower_id_inland_province() -> void:
	var model := _blank()
	_add_province(model, 0, 0, [Vector2i(2, 2)])
	_add_province(model, 1, 0, [Vector2i(1, 2), Vector2i(3, 2), Vector2i(2, 1), Vector2i(2, 3)])
	_add_province(model, 2, 1, [Vector2i(6, 6), Vector2i(7, 6)])
	_paint_sea(model, func(_x: int, _y: int) -> int: return 0)
	assert_false(CapitalChoice.is_sea_bound(model, 0))
	assert_true(CapitalChoice.is_sea_bound(model, 1))

	var result: Dictionary = CapitalChoice.place_capital(model, 0)
	assert_true(result["ok"])
	assert_eq(int(result["province_id"]), 1)


func test_great_power_without_sea_bound_province_fails_setup() -> void:
	var model := _blank()
	_add_province(model, 0, 0, [Vector2i(2, 2)])
	_add_province(model, 1, 1, [Vector2i(1, 2), Vector2i(3, 2), Vector2i(2, 1), Vector2i(2, 3)])
	_paint_sea(model, func(_x: int, _y: int) -> int: return 0)

	var result: Dictionary = CapitalChoice.place_capital(model, 0)
	assert_false(result["ok"])
	assert_eq(String(result["error"]), CapitalChoice.ERROR_NO_SEA_BOUND_PROVINCE)
	assert_false(model.provinces[0].capital)


func test_faction_without_provinces_fails_setup() -> void:
	var model := _island_with_four_seaboards()
	var result: Dictionary = CapitalChoice.place_capital(model, 7)
	assert_false(result["ok"])
	assert_eq(String(result["error"]), CapitalChoice.ERROR_NO_OWNED_PROVINCE)


func test_minor_prefers_sea_bound_then_falls_back_to_inland() -> void:
	var model := _blank()
	_add_province(model, 0, 0, [Vector2i(2, 2)])
	_add_province(model, 1, 0, [Vector2i(1, 2), Vector2i(3, 2), Vector2i(2, 1), Vector2i(2, 3)])
	_add_province(model, 2, 1, [Vector2i(7, 7)])
	_paint_sea(model, func(_x: int, _y: int) -> int: return 0)

	var pick: Dictionary = CapitalChoice.pick_province(model, 0, CapitalChoice.KIND_MINOR)
	assert_eq(int(pick["province_id"]), 1)

	var inland := _blank()
	_add_province(inland, 0, 0, [Vector2i(2, 2)])
	_add_province(inland, 1, 1, [Vector2i(1, 2), Vector2i(3, 2), Vector2i(2, 1), Vector2i(2, 3)])
	_paint_sea(inland, func(_x: int, _y: int) -> int: return 0)
	var fallback: Dictionary = CapitalChoice.pick_province(
		inland, 0, CapitalChoice.KIND_MINOR
	)
	assert_eq(int(fallback["province_id"]), 0)


# --- tile choice ------------------------------------------------------------


func test_great_power_takes_first_plains_class_a_tile() -> void:
	var model := _two_islands()
	model.terrain[model.index_of(2, 2)] = MapModel.Terrain.FOREST
	assert_eq(CapitalChoice.tile_class(model, 0, Vector2i(2, 2)), CapitalChoice.CLASS_A)
	assert_eq(CapitalChoice.tile_class(model, 0, Vector2i(3, 3)), CapitalChoice.CLASS_B)
	assert_eq(CapitalChoice.choose_tile(model, 0), Vector2i(3, 2))


func test_class_rank_beats_plains() -> void:
	var model := _two_islands()
	for tile: Vector2i in model.province_tiles(0):
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.FOREST
	model.terrain[model.index_of(3, 3)] = MapModel.Terrain.PLAINS
	assert_eq(CapitalChoice.choose_tile(model, 0), Vector2i(2, 2))


func test_great_power_falls_back_to_coastal_class_c() -> void:
	var model := _blank()
	_add_province(model, 0, 0, [Vector2i(2, 2)])
	_add_province(model, 1, 1, [Vector2i(1, 2), Vector2i(2, 1)])
	_paint_sea(model, func(_x: int, _y: int) -> int: return 0)
	assert_eq(CapitalChoice.tile_class(model, 0, Vector2i(2, 2)), CapitalChoice.CLASS_C)
	assert_eq(CapitalChoice.choose_tile(model, 0), Vector2i(2, 2))


func test_minor_takes_class_a_before_class_b() -> void:
	var model := _two_islands()
	for tile: Vector2i in model.province_tiles(0):
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.FOREST
	model.terrain[model.index_of(3, 3)] = MapModel.Terrain.PLAINS
	assert_eq(
		CapitalChoice.choose_tile(model, 0, CapitalChoice.KIND_MINOR), Vector2i(2, 2)
	)


func test_capital_tile_becomes_plains_and_loses_its_resource() -> void:
	var model := _two_islands()
	var seat := Vector2i(2, 2)
	for tile: Vector2i in model.province_tiles(0):
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.FOREST
	model.resource[model.index_of(seat.x, seat.y)] = 3
	model.provinces[0].resource = 3
	model.provinces[0].resource_tile = seat

	var result: Dictionary = CapitalChoice.place_capital(model, 0)
	assert_true(result["ok"])
	assert_true(bool(result["converted"]))
	assert_eq(model.terrain_at(seat.x, seat.y), MapModel.Terrain.PLAINS)
	assert_eq(model.resource_at(seat.x, seat.y), MapModel.NO_ID)
	assert_eq(model.provinces[0].resource, MapModel.NO_ID)
	assert_false(model.provinces[0].has_resource_tile())


# --- capital setup: ports, roads, town development -------------------------


func test_one_port_per_seaboard_with_roads_to_the_capital() -> void:
	var model := _island_with_four_seaboards()
	var result: Dictionary = CapitalChoice.place_capital(model, 0)
	assert_true(result["ok"])
	var seat := Vector2i(3, 3)
	assert_eq(Vector2i(result["tile"]), seat)

	var ports: Dictionary = result["ports"]
	assert_eq(ports.size(), 4)
	assert_eq(ports[0], seat)
	assert_eq(ports[1], seat)
	assert_eq(ports[2], Vector2i(3, 5))
	assert_eq(ports[3], Vector2i(7, 3))

	var roads: Array = result["road_paths"]
	assert_eq(roads.size(), 2)
	var port_tiles: Array = ports.values()
	for path: Array in roads:
		assert_true(port_tiles.has(path[0]))
		assert_eq(path[path.size() - 1], seat)
		assert_true(_is_contiguous(path))
	assert_eq(model.provinces[0].town_development, 4)


func test_inland_minor_gets_no_ports_or_roads() -> void:
	var model := _blank()
	_add_province(model, 0, 0, [Vector2i(2, 2)])
	_add_province(model, 1, 1, [Vector2i(1, 2), Vector2i(3, 2), Vector2i(2, 1), Vector2i(2, 3)])
	_paint_sea(model, func(_x: int, _y: int) -> int: return 0)

	var result: Dictionary = CapitalChoice.place_capital(
		model, 0, CapitalChoice.KIND_MINOR
	)
	assert_true(result["ok"])
	assert_eq(int(result["province_id"]), 0)
	assert_true((result["ports"] as Dictionary).is_empty())
	assert_true((result["road_paths"] as Array).is_empty())
	assert_eq(model.provinces[0].town_development, 0)


func test_capital_choice_is_deterministic() -> void:
	var first := _island_with_four_seaboards()
	var second := _island_with_four_seaboards()
	var a: Dictionary = CapitalChoice.place_capital(first, 0)
	var b: Dictionary = CapitalChoice.place_capital(second, 0)
	assert_eq(a["tile"], b["tile"])
	assert_eq(a["ports"], b["ports"])
	assert_eq(a["road_paths"], b["road_paths"])


func test_place_all_reports_one_result_per_faction() -> void:
	var model := _two_islands()
	var results: Array[Dictionary] = CapitalChoice.place_all(model, [0, 1])
	assert_eq(results.size(), 2)
	assert_eq(int(results[0]["province_id"]), 0)
	assert_eq(int(results[1]["province_id"]), 1)
	assert_true(model.provinces[1].capital)


func _is_contiguous(path: Array) -> bool:
	for i in range(1, path.size()):
		var step: Vector2i = path[i] - path[i - 1]
		if absi(step.x) + absi(step.y) != 1:
			return false
	return true
