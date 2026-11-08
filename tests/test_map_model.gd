extends GdToolsTest
## Tile model queries used by both the generator and the renderer.

var _model: MapModel = null


func before_each() -> void:
	_model = MapModel.new()
	_model.setup(4, 3)
	for x in 4:
		_model.terrain[_model.index_of(x, 0)] = MapModel.Terrain.PLAINS
	_model.terrain[_model.index_of(1, 1)] = MapModel.Terrain.FOREST
	_model.terrain[_model.index_of(2, 1)] = MapModel.Terrain.SHALLOW
	_model.province[_model.index_of(0, 0)] = 0
	_model.province[_model.index_of(1, 0)] = 0
	_model.province[_model.index_of(1, 1)] = 1
	_model.sea_zone[_model.index_of(2, 1)] = 0
	_model.sea_zone[_model.index_of(3, 1)] = 0
	_model.provinces = [
		{"id": 0, "name": "Cádiz", "tiles": [Vector2i(0, 0), Vector2i(1, 0)],
			"center": Vector2(1.0, 0.5), "area": 2, "owner": 0, "capital": true},
		{"id": 1, "name": "Coro", "tiles": [Vector2i(1, 1)],
			"center": Vector2(1.5, 1.5), "area": 1, "owner": 1, "capital": false},
	]
	_model.sea_zones = [
		{"id": 0, "name": "Mar Caribe", "tiles": [Vector2i(2, 1), Vector2i(3, 1)],
			"center": Vector2(3.0, 1.5), "area": 2},
	]


func test_setup_sizes_and_clears_arrays() -> void:
	var fresh := MapModel.new()
	fresh.setup(7, 5)
	assert_eq(fresh.terrain.size(), 35)
	assert_eq(fresh.province.size(), 35)
	assert_eq(fresh.province[0], MapModel.NO_ID)
	assert_eq(fresh.province_count(), 0)


func test_land_and_sea_classification() -> void:
	assert_true(_model.is_land(0, 0))
	assert_false(_model.is_land(2, 1))
	assert_true(_model.is_sea(2, 1))
	assert_false(_model.is_land(-1, 0))
	assert_false(_model.is_land(0, 99))


func test_out_of_bounds_reads_as_ocean_and_no_id() -> void:
	assert_eq(_model.terrain_at(50, 50), MapModel.Terrain.OCEAN)
	assert_eq(_model.province_at(50, 50), MapModel.NO_ID)
	assert_eq(_model.sea_zone_at(-3, 0), MapModel.NO_ID)


func test_province_lookup_helpers() -> void:
	assert_eq(_model.province_at(1, 0), 0)
	assert_eq(_model.province_name(1), "Coro")
	assert_eq(_model.province_owner(1), 1)
	assert_eq(_model.province_owner(99), MapModel.NO_ID)
	assert_eq(_model.province_center(0), Vector2(1.0, 0.5))
	assert_eq(_model.province_tiles(99), [])


func test_coastal_tiles_touch_sea() -> void:
	assert_true(MapGeo.is_coastal_tile(_model, 1, 1))
	assert_false(MapGeo.is_coastal_tile(_model, 1, 0))
	assert_false(MapGeo.is_coastal_tile(_model, 2, 1))
	assert_eq(MapGeo.coastal_tiles(_model, 1), [Vector2i(1, 1)])


func test_map_border_is_not_a_coast() -> void:
	var border := MapModel.new()
	border.setup(3, 3)
	for index in border.terrain.size():
		border.terrain[index] = MapModel.Terrain.PLAINS
	assert_false(MapGeo.is_coastal_tile(border, 0, 0))
	assert_false(MapGeo.is_coastal_tile(border, 2, 2))


func test_province_neighbors_are_cached_and_sorted() -> void:
	assert_eq(MapGeo.province_neighbors(_model, 0), [1])
	assert_true(_model.provinces[0].has("neighbors"))
	assert_eq(MapGeo.province_neighbors(_model, 99), [])


func test_sea_zone_neighbors() -> void:
	var second := MapModel.new()
	second.setup(3, 1)
	second.sea_zone[0] = 0
	second.sea_zone[1] = 0
	second.sea_zone[2] = 1
	second.sea_zones = [
		{"id": 0, "name": "A", "tiles": [Vector2i(0, 0), Vector2i(1, 0)], "center": Vector2.ZERO},
		{"id": 1, "name": "B", "tiles": [Vector2i(2, 0)], "center": Vector2.ZERO},
	]
	assert_eq(MapGeo.sea_zone_neighbors(second, 0), [1])
	assert_eq(MapGeo.sea_zone_neighbors(second, 99), [])


func test_world_helpers() -> void:
	assert_eq(MapGeo.world_size(_model, 10.0), Vector2(40.0, 30.0))
	assert_eq(MapGeo.tile_center(0, 0, 10.0), Vector2(5.0, 5.0))
	assert_eq(MapGeo.tile_at_world(Vector2(15.0, 25.0), 10.0), Vector2i(1, 2))


func test_land_tile_count() -> void:
	assert_eq(MapGeo.land_tile_count(_model), 5)


func test_terrain_labels_cover_every_type() -> void:
	for terrain in MapModel.Terrain.values():
		assert_true(MapModel.TERRAIN_LABELS.has(terrain))


func test_palette_covers_every_terrain() -> void:
	for terrain in MapModel.Terrain.values():
		assert_true(terrain < Palette.TERRAIN_COLORS.size())
	assert_eq(Palette.faction_color(-1), Palette.INK_LINE)
	assert_eq(Palette.faction_color(99), Palette.INK_LINE)
	assert_eq(Palette.terrain_color(99), Color(0.5, 0.5, 0.5))
