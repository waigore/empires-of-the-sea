extends GdToolsTest
## Civilian land movement (wiki: civilian-units § Relations).

const Fixture = preload("res://tests/civilian_fixture.gd")

var _model: MapModel = null


func before_each() -> void:
	_model = Fixture.build()


func test_explorer_walks_one_orthogonal_land_tile() -> void:
	var explorer := Fixture.unit("explorer", Vector2i(1, 1))
	var tiles: Array[Vector2i] = CivilianMovement.valid_tiles(_model, explorer)
	assert_eq(tiles.size(), 4)
	for tile: Vector2i in [
		Vector2i(0, 1), Vector2i(2, 1), Vector2i(1, 0), Vector2i(1, 2)
	]:
		assert_true(tiles.has(tile), str(tile))


func test_sea_and_diagonals_are_out_of_reach() -> void:
	var explorer := Fixture.unit("explorer", Fixture.COAST_TILE)
	var tiles: Array[Vector2i] = CivilianMovement.valid_tiles(_model, explorer)
	assert_false(tiles.has(Vector2i(1, 4)), "sea row")
	assert_eq(CivilianMovement.apply_move(
		_model, explorer, Vector2i(1, 4)
	)["ok"], false)


func test_builder_keeps_to_its_crowns_land() -> void:
	var builder := Fixture.unit("builder", Vector2i(2, 1))
	var tiles: Array[Vector2i] = CivilianMovement.valid_tiles(_model, builder)
	assert_false(tiles.has(Vector2i(3, 1)))
	assert_true(tiles.has(Vector2i(2, 0)))
	var refused: Dictionary = CivilianMovement.apply_move(
		_model, builder, Vector2i(3, 1)
	)
	assert_false(bool(refused["ok"]))
	assert_true(String(refused["reason"]).contains("without a war"))
	assert_eq(builder.tile, Vector2i(2, 1))


func test_explorer_may_cross_into_a_rival_province() -> void:
	var explorer := Fixture.unit("explorer", Vector2i(2, 1))
	var result: Dictionary = CivilianMovement.apply_move(
		_model, explorer, Vector2i(3, 1)
	)
	assert_true(bool(result["ok"]))
	assert_eq(explorer.tile, Vector2i(3, 1))


func test_one_move_per_turn() -> void:
	var explorer := Fixture.unit("explorer", Vector2i(1, 1))
	assert_true(bool(CivilianMovement.apply_move(
		_model, explorer, Vector2i(2, 1)
	)["ok"]))
	var second: Dictionary = CivilianMovement.apply_move(
		_model, explorer, Vector2i(2, 2)
	)
	assert_false(bool(second["ok"]))
	assert_true(String(second["reason"]).contains("already moved"))
	assert_eq(explorer.tile, Vector2i(2, 1))


func test_begin_turn_restores_the_move() -> void:
	var explorer := Fixture.unit("explorer", Vector2i(1, 1))
	CivilianMovement.apply_move(_model, explorer, Vector2i(2, 1))
	var units: Array[CivilianState] = [explorer]
	CivilianMovement.begin_turn(units)
	assert_false(explorer.moved)
	assert_true(bool(CivilianMovement.apply_move(
		_model, explorer, Vector2i(2, 2)
	)["ok"]))


func test_working_civilians_stay_on_their_tile() -> void:
	var builder := Fixture.unit("builder", Fixture.IRON_TILE)
	builder.start_work("build_improvement", Fixture.IRON_TILE, 1)
	var result: Dictionary = CivilianMovement.apply_move(
		_model, builder, Vector2i(0, 1)
	)
	assert_false(bool(result["ok"]))
	assert_eq(CivilianMovement.valid_tiles(_model, builder), [])


func test_non_adjacent_tiles_are_refused() -> void:
	var explorer := Fixture.unit("explorer", Vector2i(0, 0))
	var result: Dictionary = CivilianMovement.apply_move(
		_model, explorer, Vector2i(2, 2)
	)
	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("one tile"))
	assert_eq(explorer.tile, Vector2i(0, 0))


func test_out_of_bounds_land_is_refused() -> void:
	assert_false(CivilianMovement.may_enter(_model, "explorer", 0, Vector2i(-1, 0)))
	assert_false(CivilianMovement.may_enter(_model, "explorer", 0, Vector2i(9, 9)))
	assert_true(CivilianMovement.may_enter(_model, "explorer", 0, Vector2i(0, 0)))
