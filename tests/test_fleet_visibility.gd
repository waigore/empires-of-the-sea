extends GdToolsTest
## Fleet-driven fog rules (wiki: fog-and-exploration, ships-and-naval).

const NavalFixture = preload("res://tests/naval_fixture.gd")

var _model: MapModel = null


func before_each() -> void:
	_model = NavalFixture.build()


func test_water_tiles_are_only_sea() -> void:
	var tiles: Array[Vector2i] = FleetVisibility.water_tiles(_model, 0)
	assert_true(tiles.has(Vector2i(2, 0)))
	assert_false(tiles.has(Vector2i(1, 0)))
	assert_eq(tiles.size(), 6)


func test_ring_reveals_water_and_the_coastal_land_ring() -> void:
	var tiles: Array[Vector2i] = FleetVisibility.ring_tiles(_model, 0)
	assert_true(tiles.has(Vector2i(2, 0)))
	assert_true(tiles.has(Vector2i(1, 0)))
	assert_false(tiles.has(Vector2i(0, 0)))


func test_coastal_zones_follow_owned_provinces() -> void:
	assert_eq(FleetVisibility.coastal_zones(_model, 0), [0])
	assert_eq(FleetVisibility.coastal_zones(_model, 1), [1])
	assert_eq(FleetVisibility.coastal_zones(_model, 2), [])


func test_distant_zones_are_refogged() -> void:
	assert_eq(FleetVisibility.zones_to_refog(_model, 0, []), [1])
	assert_eq(FleetVisibility.zones_to_refog(_model, 1, []), [0])
	assert_eq(FleetVisibility.zones_to_refog(_model, 2, []), [0, 1])


func test_fleets_at_sea_keep_their_zone_known() -> void:
	var occupied: Array[int] = [1]
	assert_eq(FleetVisibility.zones_to_refog(_model, 0, occupied), [])


func test_moving_coastline_changes_the_coastal_set() -> void:
	_model.provinces[1]["owner"] = 0
	assert_eq(FleetVisibility.coastal_zones(_model, 0), [0, 1])
	assert_eq(FleetVisibility.zones_to_refog(_model, 0, []), [])
