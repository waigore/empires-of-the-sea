extends GdToolsTest
## Placement geometry and the multi-region Build/Work pass extracted from
## CivilianLayer (REQ-P3-01, REQ-P3-04).

const Fixture = preload("res://tests/civilian_fixture.gd")


func test_capital_tile_prefers_the_seat() -> void:
	var model: MapModel = Fixture.build()
	var seat: Vector2i = CivilianPlacement.capital_tile(model, 0)
	assert_true(seat.x >= 0)
	assert_true(model.is_land(seat.x, seat.y))


func test_mustering_tile_keeps_the_seat_clear() -> void:
	var model: MapModel = Fixture.build()
	var seat: Vector2i = CivilianPlacement.capital_tile(model, 0)
	var tile: Vector2i = CivilianPlacement.mustering_tile(model, [], 0)
	assert_true(tile.x >= 0)
	assert_ne(tile, seat, "fresh crews leave the capital seat readable")


func test_spies_do_not_block_mustering() -> void:
	var model: MapModel = Fixture.build()
	var seat: Vector2i = CivilianPlacement.capital_tile(model, 0)
	var taken: Dictionary = {seat: true}
	var open: Vector2i = CivilianPlacement.free_tile(model, 0, seat, taken)
	assert_true(open.x >= 0)
	var spy := CivilianState.create(1, 0, SpyRules.TYPE, open)
	var tile: Vector2i = CivilianPlacement.mustering_tile(model, [spy], 0)
	assert_eq(tile, open, "a spy's tile stays free for mustering")


func test_turn_pass_restores_moves_on_every_region() -> void:
	var model: MapModel = Fixture.build()
	var world := WorldMap.new()
	world.add_region(model)
	var layer := CivilianLayer.new()
	layer.spawn(model, 0, 0, [], false)
	var explorer: CivilianState = layer.add_unit(0, "explorer", Vector2i(1, 1))
	layer.regions.set_region(model.region_id, layer.units)
	assert_true(bool(CivilianMovement.apply_move(model, explorer, Vector2i(2, 1))["ok"]))
	assert_true(explorer.moved)
	CivilianTurnPass.resolve(layer, world, null)
	assert_false(explorer.moved, "the pass restores moves without the layer")
	layer.free()
