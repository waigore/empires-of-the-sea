extends GdToolsTest
## Country borders (view support for wiki: factions / map ownership).
## Ownership changes must produce an explicit line between different nations.

const WIDTH: int = 6
const HEIGHT: int = 3


func _model_with_owners(owners: Array[int]) -> MapModel:
	var model := MapModel.new()
	model.setup(WIDTH, HEIGHT)
	var province_count: int = 3
	for province_id in province_count:
		var tiles: Array[Vector2i] = [
			Vector2i(province_id * 2, 1), Vector2i(province_id * 2 + 1, 1)
		]
		for tile: Vector2i in tiles:
			model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.PLAINS
			model.province[model.index_of(tile.x, tile.y)] = province_id
		model.provinces.append(
			ProvinceState.create(
				province_id,
				"P%d" % province_id,
				tiles,
				Vector2(float(province_id) * 2.0 + 0.5, 1.5),
				tiles.size(),
				owners[province_id]
			)
		)
	return model


func test_borders_split_different_owners() -> void:
	var model: MapModel = _model_with_owners([0, 1, 0])
	var borders: Dictionary = CountryBorders.build(model, 1.0)
	assert_true(borders.has(0))
	assert_true(borders.has(1))
	assert_true(_has_edge(borders[0], Vector2(2, 1), Vector2(2, 2)), "missing 0|1 border")
	assert_true(_has_edge(borders[1], Vector2(4, 1), Vector2(4, 2)), "missing 1|0 border")


func test_no_border_inside_one_nation() -> void:
	var model: MapModel = _model_with_owners([0, 0, 0])
	var borders: Dictionary = CountryBorders.build(model, 1.0)
	assert_true(borders.is_empty(), "same owner should draw no border")


func test_coastline_keeps_its_ink_and_no_country_line() -> void:
	var model: MapModel = _model_with_owners([0, 1, 0])
	var borders: Dictionary = CountryBorders.build(model, 1.0)
	assert_false(_has_edge(borders[0], Vector2(0, 1), Vector2(0, 2)), "west coast got a country line")
	assert_false(_has_edge(borders[0], Vector2(0, 1), Vector2(1, 1)), "north coast got a country line")


func test_unclaimed_land_gets_no_border() -> void:
	var model: MapModel = _model_with_owners([MapModel.NO_ID, 0, 0])
	var borders: Dictionary = CountryBorders.build(model, 1.0)
	assert_true(borders.is_empty(), "unclaimed land has no country border")


func test_missing_model_is_safe() -> void:
	assert_true(CountryBorders.build(null, 1.0).is_empty())


func _has_edge(segments: Array, a: Vector2, b: Vector2) -> bool:
	for segment: PackedVector2Array in segments:
		if segment.size() != 2:
			continue
		if segment[0] == a and segment[1] == b:
			return true
		if segment[0] == b and segment[1] == a:
			return true
	return false
