extends GdToolsTest
## Placement geometry, estate paint and the multi-region Build/Work pass
## extracted from CivilianLayer (REQ-P3-01, REQ-P3-04).

const Fixture = preload("res://tests/civilian_fixture.gd")


func test_capital_tile_prefers_the_seat() -> void:
	var model: MapModel = Fixture.build()
	var seat: Vector2i = CivilianPlacement.capital_tile(model, 0)
	assert_true(seat.x >= 0)
	assert_true(model.is_land(seat.x, seat.y))


func test_capital_tile_guards_and_falls_back() -> void:
	assert_eq(CivilianPlacement.capital_tile(null, 0), Vector2i(-1, -1))
	var model: MapModel = Fixture.build()
	assert_eq(CivilianPlacement.capital_tile(model, 99), Vector2i(-1, -1))
	var data: ProvinceState = model.province_data(0)
	data.capital_tile = Vector2i(-1, -1)
	var fallback: Vector2i = CivilianPlacement.capital_tile(model, 0)
	assert_eq(fallback, model.province_tiles(0)[0])


func test_mustering_tile_keeps_the_seat_clear() -> void:
	var model: MapModel = Fixture.build()
	var seat: Vector2i = CivilianPlacement.capital_tile(model, 0)
	var tile: Vector2i = CivilianPlacement.mustering_tile(model, [], 0)
	assert_true(tile.x >= 0)
	assert_ne(tile, seat, "fresh crews leave the capital seat readable")


func test_spies_and_nulls_do_not_block_mustering() -> void:
	var model: MapModel = Fixture.build()
	var seat: Vector2i = CivilianPlacement.capital_tile(model, 0)
	var taken: Dictionary = {seat: true}
	var open: Vector2i = CivilianPlacement.free_tile(model, 0, seat, taken)
	assert_true(open.x >= 0)
	var spy := CivilianState.create(1, 0, SpyRules.TYPE, open)
	var tile: Vector2i = CivilianPlacement.mustering_tile(model, [null, spy], 0)
	assert_eq(tile, open, "a spy's tile stays free for mustering")
	assert_eq(CivilianPlacement.free_tile(null, 0, seat, {}), Vector2i(-1, -1))
	assert_eq(CivilianPlacement.mustering_tile(null, [], 0), Vector2i(-1, -1))


func test_a_full_province_reclaims_the_seat() -> void:
	var model: MapModel = Fixture.build()
	var seat: Vector2i = CivilianPlacement.capital_tile(model, 0)
	var units: Array[CivilianState] = []
	var id: int = 1
	for tile: Vector2i in model.province_tiles(0):
		if tile == seat:
			continue
		units.append(CivilianState.create(id, 0, "builder", tile))
		id += 1
	var tile: Vector2i = CivilianPlacement.mustering_tile(model, units, 0)
	assert_eq(tile, seat, "when every other tile is taken the seat musters")


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


func test_turn_pass_guards_and_offscreen_rosters() -> void:
	assert_eq(CivilianTurnPass.resolve(null, null, null).size(), 0)
	var home: MapModel = Fixture.build()
	var away: MapModel = Fixture.build()
	away.region_id = 1
	var world := WorldMap.new()
	world.add_region(home)
	world.add_region(away)
	var layer := CivilianLayer.new()
	layer.spawn(home, 0, 0, [], false)
	var idle: CivilianState = CivilianState.create(9, 0, "explorer", Vector2i(1, 1))
	idle.moved = true
	var remote: Array[CivilianState] = [null, idle]
	layer.regions.set_region(1, remote)
	CivilianTurnPass.resolve(layer, world, null)
	assert_false(idle.moved, "an off-screen crew still gets its move back")
	layer.free()


func test_paint_covers_roads_rails_mines_woods_riches_and_ports() -> void:
	LandWorksPaint.paint(null, null, null, 22.0)
	var model: MapModel = Fixture.build()
	var works := LandWorks.new()
	works.set_transport(model, Fixture.IRON_TILE, LandWorks.TRANSPORT_RAIL)
	works.set_improvement(model, Fixture.IRON_TILE, 2)
	works.set_improvement(model, Fixture.TIMBER_TILE, 1)
	var gold := Vector2i(2, 2)
	model.resource[model.index_of(gold.x, gold.y)] = 3
	works.set_improvement(model, gold, 1)
	var farm := Vector2i(0, 1)
	model.resource[model.index_of(farm.x, farm.y)] = 4
	works.set_improvement(model, farm, 1)
	works.set_transport(model, farm, LandWorks.TRANSPORT_ROAD)
	works.add_port(model, Fixture.COAST_TILE)
	var layer := CivilianLayer.new()
	add_child(layer)
	layer.model = model
	layer.works = works
	layer.queue_redraw()
	await get_tree().process_frame
	layer.free()
