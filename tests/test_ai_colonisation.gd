extends GdToolsTest
## Rival colonisation voyages (wiki: civilian-units § Overseas deployment;
## DR-20261109-17): board, sail, cross a Passage and land, one legal step a turn.

const OWNER: int = 1
const CivilianFixture = preload("res://tests/civilian_fixture.gd")


func _old_world() -> MapModel:
	var model := MapModel.new()
	model.setup(5, 3)
	model.region_id = WorldMap.OLD_WORLD
	model.region_key = "old_world"
	var tiles: Array[Vector2i] = []
	for y in 2:
		for x in 5:
			var tile := Vector2i(x, y)
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			model.province[model.index_of(x, y)] = 0
			tiles.append(tile)
	for x in 5:
		var index: int = model.index_of(x, 2)
		model.terrain[index] = MapModel.Terrain.OCEAN
		model.sea_zone[index] = 0
	var province := ProvinceState.create(
		0, "Seat", tiles, Vector2(2.0, 0.5), tiles.size(), OWNER, true
	)
	province.capital_tile = Vector2i(0, 0)
	province.port_tile = Vector2i(0, 1)
	province.coastal = true
	model.provinces = [province]
	var sea: Array[Vector2i] = []
	for x in 5:
		sea.append(Vector2i(x, 2))
	model.sea_zones = [SeaZoneState.create(0, "Home Waters", sea, Vector2(2.0, 2.0), 5)]
	return model


func _new_world() -> MapModel:
	var model := MapModel.new()
	model.setup(4, 3)
	model.region_id = WorldMap.NEW_WORLD
	model.region_key = "new_world"
	for y in 2:
		for x in 4:
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
	for x in 4:
		var index: int = model.index_of(x, 2)
		model.terrain[index] = MapModel.Terrain.OCEAN
		model.sea_zone[index] = 0
	var sea: Array[Vector2i] = []
	for x in 4:
		sea.append(Vector2i(x, 2))
	model.sea_zones = [SeaZoneState.create(0, "Far Shore", sea, Vector2(1.5, 2.0), 4)]
	return model


func _world() -> WorldMap:
	var map := WorldMap.new()
	map.add_region(_old_world())
	map.add_region(_new_world())
	map.warp_links = [
		{"from_region": 0, "from_zone": 0, "to_region": 1, "to_zone": 0},
		{"from_region": 1, "from_zone": 0, "to_region": 0, "to_zone": 0},
	]
	return map


func _config() -> AiConfig:
	return AiConfig.build(OWNER, 1500)


func test_an_idle_explorer_boards_a_squadron_in_port() -> void:
	var world: WorldMap = _world()
	var old_world: MapModel = world.region(0)
	var fleet: FleetState = FleetState.in_port(1, OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, OWNER, "explorer", Vector2i(0, 0))
	var order: Dictionary = AiColonisationPlanner.plan(
		_config(), world, 0, old_world, [fleet], [unit], {}
	)
	assert_eq(String(order.get("kind", "")), "embark")
	assert_eq(int(order.get("unit", -1)), 1)


func test_a_passenger_sails_crosses_and_lands() -> void:
	var world: WorldMap = _world()
	var old_world: MapModel = world.region(0)
	var new_world: MapModel = world.region(1)
	var fleet: FleetState = FleetState.in_port(1, OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, OWNER, "explorer", Vector2i(0, 0))
	assert_true(bool(CivilianVoyage.embark(old_world, unit, fleet)["ok"]))
	var sail: Dictionary = AiColonisationPlanner.plan(
		_config(), world, 0, old_world, [fleet], [unit], {}
	)
	assert_eq(String(sail.get("kind", "")), "sail")
	assert_eq(int(sail.get("zone", -1)), 0)
	assert_true(
		bool(FleetSortie.apply(old_world, fleet, 0)["ok"]),
		"a squadron in port at its own capital sorties"
	)
	fleet.moved = false
	var cross: Dictionary = AiColonisationPlanner.plan(
		_config(), world, 0, old_world, [fleet], [unit], {}
	)
	assert_eq(String(cross.get("kind", "")), "cross")
	var crossed: Dictionary = WarpTravel.apply_crossing(world, 0, fleet)
	assert_true(bool(crossed["ok"]))
	fleet.moved = false
	var land: Dictionary = AiColonisationPlanner.plan(
		_config(), world, 1, new_world, [fleet], [unit], {}
	)
	assert_eq(String(land.get("kind", "")), "land")
	assert_eq(Vector2i(land.get("tile", Vector2i(-1, -1))), Vector2i(0, 1))


func test_no_second_expedition_when_a_colonist_is_already_abroad() -> void:
	var world: WorldMap = _world()
	var old_world: MapModel = world.region(0)
	var fleet: FleetState = FleetState.in_port(1, OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, OWNER, "explorer", Vector2i(0, 0))
	var order: Dictionary = AiColonisationPlanner.plan(
		_config(), world, 0, old_world, [fleet], [unit], {"explorer": 1}
	)
	assert_true(order.is_empty())


func test_the_map_adapter_embarks_and_sails_the_rival() -> void:
	var world: WorldMap = _world()
	var old_world: MapModel = world.region(0)
	var fleet: FleetState = FleetState.in_port(1, OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, OWNER, "explorer", Vector2i(0, 0))
	var play := PlaySession.new()
	play.player_faction = 0
	play.region_index = 0
	play.map_seed = 1500
	play.world = world
	play.model = old_world
	play.ship_layer = ShipLayer.new()
	play.ship_layer.model = old_world
	play.ship_layer.world = world
	play.ship_layer.regions.set_region(0, [fleet])
	play.ship_layer.regions.set_region(1, [])
	play.civilian_layer = CivilianLayer.new()
	play.civilian_layer.model = old_world
	play.civilian_layer.units = [unit]
	play.civilian_layer.regions.set_region(0, [unit])
	play.civilian_layer.regions.set_region(1, [])
	var first: Array[Dictionary] = MapPlayColonisationAi.run(play)
	assert_eq(first.size(), 1)
	assert_eq(String(first[0]["kind"]), "embark")
	assert_true(unit.is_embarked())
	assert_eq(fleet.civilian_count(), 1)
	var second: Array[Dictionary] = MapPlayColonisationAi.run(play)
	assert_eq(second.size(), 1)
	assert_eq(String(second[0]["kind"]), "sail")
	assert_true(fleet.is_at_sea())
	play.ship_layer.free()
	play.civilian_layer.free()


func test_a_squadron_at_sea_docks_for_its_colonist() -> void:
	var world: WorldMap = _world()
	var old_world: MapModel = world.region(0)
	var fleet: FleetState = FleetState.at_sea(1, OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, OWNER, "explorer", Vector2i(0, 0))
	var order: Dictionary = AiColonisationPlanner.plan(
		_config(), world, 0, old_world, [fleet], [unit], {}
	)
	assert_eq(String(order.get("kind", "")), "dock")
	assert_eq(int(order.get("province", -1)), 0)


func test_a_builder_boards_when_the_crown_owns_overseas_land() -> void:
	var world: WorldMap = _world()
	var old_world: MapModel = world.region(0)
	var new_world: MapModel = world.region(1)
	var tiles: Array[Vector2i] = []
	for y in 2:
		for x in 4:
			tiles.append(Vector2i(x, y))
	var colony := ProvinceState.create(0, "Colony", tiles, Vector2(1.5, 0.5), 8, OWNER, false)
	colony.town_tile = Vector2i(0, 0)
	new_world.provinces = [colony]
	var fleet: FleetState = FleetState.in_port(1, OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, OWNER, "builder", Vector2i(0, 0))
	var order: Dictionary = AiColonisationPlanner.plan(
		_config(), world, 0, old_world, [fleet], [unit], {}
	)
	assert_eq(String(order.get("kind", "")), "embark")
	assert_eq(int(order.get("unit", -1)), 1)


func test_a_docked_passenger_lands_without_sailing_first() -> void:
	var world: WorldMap = _world()
	var new_world: MapModel = world.region(1)
	var tiles: Array[Vector2i] = []
	for y in 2:
		for x in 4:
			var tile := Vector2i(x, y)
			tiles.append(tile)
			new_world.province[new_world.index_of(x, y)] = 0
	var colony := ProvinceState.create(0, "Colony", tiles, Vector2(1.5, 0.5), 8, OWNER, false)
	colony.port_tile = Vector2i(0, 1)
	colony.coastal = true
	new_world.provinces = [colony]
	var fleet: FleetState = FleetState.in_port(1, OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, OWNER, "builder", Vector2i(0, 0))
	assert_true(bool(CivilianVoyage.embark(new_world, unit, fleet)["ok"]))
	var order: Dictionary = AiColonisationPlanner.plan(
		_config(), world, 1, new_world, [fleet], [unit], {}
	)
	assert_eq(String(order.get("kind", "")), "land")


func test_the_map_adapter_crosses_and_lands() -> void:
	var world: WorldMap = _world()
	var old_world: MapModel = world.region(0)
	var fleet: FleetState = FleetState.in_port(1, OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, OWNER, "explorer", Vector2i(0, 0))
	var play := PlaySession.new()
	play.player_faction = 0
	play.region_index = 0
	play.map_seed = 1500
	play.world = world
	play.model = old_world
	play.ship_layer = ShipLayer.new()
	play.ship_layer.model = old_world
	play.ship_layer.world = world
	play.ship_layer.regions.set_region(0, [fleet])
	play.ship_layer.regions.set_region(1, [])
	play.civilian_layer = CivilianLayer.new()
	play.civilian_layer.model = old_world
	play.civilian_layer.units = [unit]
	play.civilian_layer.regions.set_region(0, [unit])
	play.civilian_layer.regions.set_region(1, [])
	assert_eq(String(MapPlayColonisationAi.run(play)[0]["kind"]), "embark")
	fleet.moved = false
	assert_eq(String(MapPlayColonisationAi.run(play)[0]["kind"]), "sail")
	fleet.moved = false
	var crossed: Array[Dictionary] = MapPlayColonisationAi.run(play)
	assert_eq(String(crossed[0]["kind"]), "cross")
	assert_true((play.ship_layer.regions.value(0, []) as Array).is_empty())
	assert_eq((play.ship_layer.regions.value(1, []) as Array).size(), 1)
	fleet.moved = false
	var landed: Array[Dictionary] = MapPlayColonisationAi.run(play)
	assert_eq(String(landed[0]["kind"]), "land")
	assert_false(unit.is_embarked())
	assert_true(unit.tile.y <= 1)
	play.ship_layer.free()
	play.civilian_layer.free()


func test_the_planner_guards_empty_inputs() -> void:
	var world: WorldMap = _world()
	var old_world: MapModel = world.region(0)
	assert_true(AiColonisationPlanner.plan(null, world, 0, old_world, [], []).is_empty())
	assert_true(AiColonisationPlanner.plan(_config(), null, 0, old_world, [], []).is_empty())
	assert_true(AiColonisationPlanner.plan(_config(), world, 0, null, [], []).is_empty())
	assert_true(
		AiColonisationPlanner.plan(
			AiConfig.build(99, 1500), world, 0, old_world, [], []
		).is_empty(),
		"an unknown court has no home region"
	)
	assert_true(
		AiColonisationPlanner.plan(
			AiConfig.build(9, 1500), world, 1, world.region(1), [], []
		).is_empty(),
		"a New World court with no Old World land has nowhere to sail"
	)


func test_a_carrying_fleet_without_its_civilian_is_ignored() -> void:
	var world: WorldMap = _world()
	var old_world: MapModel = world.region(0)
	var fleet: FleetState = FleetState.in_port(1, OWNER, 0)
	fleet.add_civilian(77)
	assert_true(
		AiColonisationPlanner.plan(_config(), world, 0, old_world, [fleet], []).is_empty()
	)


func test_a_working_builder_falls_back_to_an_idle_explorer() -> void:
	var world: WorldMap = _world()
	var old_world: MapModel = world.region(0)
	var new_world: MapModel = world.region(1)
	var tiles: Array[Vector2i] = []
	for y in 2:
		for x in 4:
			tiles.append(Vector2i(x, y))
	var colony := ProvinceState.create(0, "Colony", tiles, Vector2(1.5, 0.5), 8, OWNER, false)
	new_world.provinces = [colony]
	var builder: CivilianState = CivilianState.create(1, OWNER, "builder", Vector2i(0, 0))
	builder.start_work("build_improvement", Vector2i(0, 0), 2)
	var explorer: CivilianState = CivilianState.create(2, OWNER, "explorer", Vector2i(0, 0))
	var fleet: FleetState = FleetState.in_port(1, OWNER, 0)
	var order: Dictionary = AiColonisationPlanner.plan(
		_config(), world, 0, old_world, [fleet], [builder, explorer], {}
	)
	assert_eq(String(order.get("kind", "")), "embark")
	assert_eq(int(order.get("unit", -1)), 2)


func test_the_lowest_idle_squadron_is_chosen() -> void:
	var world: WorldMap = _world()
	var old_world: MapModel = world.region(0)
	var unit: CivilianState = CivilianState.create(1, OWNER, "explorer", Vector2i(0, 0))
	var moved: FleetState = FleetState.at_sea(1, OWNER, 0)
	moved.moved = true
	var troop_carrier: FleetState = FleetState.at_sea(2, OWNER, 0)
	troop_carrier.embarked_army = 9
	var ready: FleetState = FleetState.at_sea(3, OWNER, 0)
	var order: Dictionary = AiColonisationPlanner.plan(
		_config(), world, 0, old_world, [moved, troop_carrier, ready], [unit], {}
	)
	assert_eq(String(order.get("kind", "")), "dock")
	assert_eq(int(order.get("fleet", -1)), 3)


func test_a_moved_carrying_fleet_does_not_sail_twice() -> void:
	var world: WorldMap = _world()
	var old_world: MapModel = world.region(0)
	var first: CivilianState = CivilianState.create(1, OWNER, "explorer", Vector2i(0, 0))
	var second: CivilianState = CivilianState.create(2, OWNER, "explorer", Vector2i(0, 0))
	var moved: FleetState = FleetState.in_port(1, OWNER, 0)
	moved.add_civilian(1)
	moved.moved = true
	var ready: FleetState = FleetState.in_port(2, OWNER, 0)
	ready.add_civilian(2)
	var order: Dictionary = AiColonisationPlanner.plan(
		_config(), world, 0, old_world, [moved, ready], [first, second], {}
	)
	assert_eq(String(order.get("kind", "")), "sail")
	assert_eq(int(order.get("fleet", -1)), 2)


func test_board_refusals_without_a_reachable_port() -> void:
	var world: WorldMap = _world()
	var old_world: MapModel = world.region(0)
	var unit: CivilianState = CivilianState.create(1, OWNER, "explorer", Vector2i(0, 0))
	var elsewhere: FleetState = FleetState.in_port(1, OWNER, 1)
	assert_true(
		AiColonisationPlanner.plan(
			_config(), world, 0, old_world, [elsewhere], [unit], {}
		).is_empty(),
		"a squadron in another port cannot take this colonist"
	)
	var stray: CivilianState = CivilianState.create(9, OWNER, "explorer", Vector2i(9, 9))
	var order: Dictionary = AiColonisationPlanner.plan(
		_config(), world, 0, old_world, [FleetState.at_sea(1, OWNER, 0)], [stray], {}
	)
	assert_eq(
		String(order.get("kind", "")), "dock",
		"the squadron musters at the crown's harbour, not on the colonist's tile"
	)
	assert_eq(int(order.get("province", -1)), 0)


## A court with no harbour of its own cannot start an expedition, however many
## colonists and hulls it has (wiki: ships-and-naval § Home Fleet).
func test_no_owned_harbour_means_no_voyage() -> void:
	var world: WorldMap = _world()
	var old_world: MapModel = world.region(0)
	old_world.provinces[0].port_tile = Vector2i(-1, -1)
	var unit: CivilianState = CivilianState.create(1, OWNER, "explorer", Vector2i(0, 0))
	assert_eq(AiColonisationPlanner.harbour(old_world, OWNER), MapModel.NO_ID)
	assert_true(
		AiColonisationPlanner.plan(
			_config(), world, 0, old_world, [FleetState.at_sea(1, OWNER, 0)], [unit], {}
		).is_empty(),
		"a crown with no port has nowhere to take a colonist aboard"
	)


## The court's seat, when it has a port, is the muster harbour even if another
## owned province has a lower id.
func test_the_seat_is_the_muster_harbour() -> void:
	var world: WorldMap = _world()
	var old_world: MapModel = world.region(0)
	var seat: ProvinceState = old_world.provinces[0]
	seat.capital = false
	var coast: ProvinceState = ProvinceState.create(
		0, "Anchorage", seat.tiles.duplicate(), Vector2(2.0, 0.5), 10, OWNER, true
	)
	coast.port_tile = Vector2i(1, 0)
	old_world.provinces = [coast, seat]
	assert_eq(
		AiColonisationPlanner.harbour(old_world, OWNER), 0,
		"the seat outranks a lower-id anchorage"
	)


## An Explorer with a voyage ahead waits at its crown's harbour and marches home
## when something has carried it off, so the boarding step always finds it there
## (wiki: civilian-units § Overseas deployment; DR-20261111-05).
func test_an_explorer_musters_at_the_crowns_harbour() -> void:
	var model: MapModel = CivilianFixture.build()
	var port: Vector2i = CivilianFixture.COAST_TILE
	var here: CivilianState = CivilianState.create(1, 0, "explorer", CivilianFixture.BARE_TILE)
	var away: CivilianState = CivilianState.create(2, 0, "explorer", CivilianFixture.RIVAL_GRAIN_TILE)
	var context: Dictionary = {"muster_port": port}
	assert_true(
		AiExplorerWork.best_move(model, here, LandWorks.new(), context).is_empty(),
		"an Explorer in the harbour province waits for its voyage"
	)
	var march: Dictionary = AiExplorerWork.best_move(model, away, LandWorks.new(), context)
	assert_eq(String(march.get("kind", "")), "move")
	var before: int = absi(away.tile.x - port.x) + absi(away.tile.y - port.y)
	var step: Vector2i = march.get("tile", CivilianState.NO_TILE)
	assert_true(
		absi(step.x - port.x) + absi(step.y - port.y) < before,
		"the march closes on the harbour"
	)
	assert_true(
		AiExplorerWork.best_candidate(
			AiConfig.build(0, 1500), model, away, [away], LandWorks.new(),
			CivilianFixture.stockpile(), {}, {}, context, {}
		).is_empty(),
		"a colonist on the way to its port takes no survey work"
	)


## The muster only stands while a squadron is free to carry the colonist and the
## court has none abroad yet; otherwise the Explorer is back on survey duty.
func test_the_muster_port_needs_a_free_squadron_and_no_colonist_abroad() -> void:
	var world: WorldMap = _world()
	var old_world: MapModel = world.region(0)
	var play := PlaySession.new()
	play.player_faction = 0
	play.region_index = 0
	play.world = world
	play.model = old_world
	play.ship_layer = ShipLayer.new()
	play.ship_layer.model = old_world
	play.ship_layer.regions.set_region(0, [FleetState.at_sea(1, OWNER, 0)])
	play.ship_layer.regions.set_region(1, [])
	play.civilian_layer = CivilianLayer.new()
	play.civilian_layer.model = old_world
	play.civilian_layer.units = []
	play.civilian_layer.regions.set_region(0, [])
	play.civilian_layer.regions.set_region(1, [])
	assert_eq(
		MapPlayCivilianAi._muster_port(play, OWNER, 0, old_world), Vector2i(0, 1),
		"a court with a free squadron musters at its seat's port"
	)
	var abroad: CivilianState = CivilianState.create(7, OWNER, "explorer", Vector2i(0, 0))
	play.civilian_layer.regions.set_region(1, [abroad])
	assert_eq(
		MapPlayCivilianAi._muster_port(play, OWNER, 0, old_world), CivilianState.NO_TILE,
		"a court with a colonist already abroad sends no second expedition"
	)
	play.civilian_layer.regions.set_region(1, [])
	play.ship_layer.regions.set_region(0, [])
	assert_eq(
		MapPlayCivilianAi._muster_port(play, OWNER, 0, old_world), CivilianState.NO_TILE,
		"no squadron, no muster"
	)
	play.ship_layer.free()
	play.civilian_layer.free()


func test_region_helpers_pick_the_opposite_map() -> void:
	var world: WorldMap = _world()
	assert_eq(AiColonisationPlanner._target_region(world, WorldMap.OLD_WORLD, OWNER), WorldMap.NEW_WORLD)
	assert_eq(AiColonisationPlanner._target_region(world, WorldMap.NEW_WORLD, OWNER), WorldMap.OLD_WORLD)
	assert_false(AiColonisationPlanner._owns_land_in(world, 9, OWNER))


func test_no_passage_keeps_a_carrying_squadron_home() -> void:
	var world: WorldMap = _world()
	world.warp_links = []
	var old_world: MapModel = world.region(0)
	var fleet: FleetState = FleetState.in_port(1, OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, OWNER, "explorer", Vector2i(0, 0))
	assert_true(bool(CivilianVoyage.embark(old_world, unit, fleet)["ok"]))
	assert_true(
		AiColonisationPlanner.plan(
			_config(), world, 0, old_world, [fleet], [unit], {}
		).is_empty()
	)


func test_a_multi_zone_crossing_steps_toward_the_far_coast() -> void:
	var model := MapModel.new()
	model.setup(6, 2)
	model.region_id = WorldMap.NEW_WORLD
	for x in 6:
		var y0: int = model.index_of(x, 0)
		model.terrain[y0] = MapModel.Terrain.PLAINS if x >= 4 else MapModel.Terrain.OCEAN
		var y1: int = model.index_of(x, 1)
		model.terrain[y1] = MapModel.Terrain.OCEAN
		model.sea_zone[y1] = 0 if x < 2 else (1 if x < 4 else 2)
	var zones: Array[SeaZoneState] = []
	for zone_id in 3:
		var tiles: Array[Vector2i] = []
		for x in range(zone_id * 2, zone_id * 2 + 2):
			tiles.append(Vector2i(x, 1))
		zones.append(SeaZoneState.create(zone_id, "Z%d" % zone_id, tiles, Vector2.ZERO, 2))
	model.sea_zones = zones
	var world := WorldMap.new()
	world.add_region(_old_world())
	world.add_region(model)
	var fleet: FleetState = FleetState.at_sea(1, OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, OWNER, "explorer", Vector2i(0, 0))
	unit.embark_on(fleet.id)
	fleet.add_civilian(unit.id)
	var order: Dictionary = AiColonisationPlanner.plan(
		_config(), world, 1, model, [fleet], [unit], {}
	)
	assert_eq(String(order.get("kind", "")), "sail")
	assert_eq(int(order.get("zone", -1)), 1)
	assert_eq(AiSeaRoute.step_toward(model, 0, [0]), -1)
	assert_eq(AiColonisationPlanner._carried_id(FleetState.in_port(9, OWNER, 0)), -1)


## A court lands only on a coast it has charted (wiki: fog-and-exploration;
## DR-20261110-21).
func test_an_uncharted_coast_is_not_a_landing_ground() -> void:
	var world: WorldMap = _world()
	var new_world: MapModel = world.region(1)
	var charts := CourtCharts.new()
	charts.setup(world, 0, {})
	assert_true(
		AiColonisationPlanner._landing_zones(new_world, "explorer", OWNER, charts).is_empty(),
		"the New World water is unknown"
	)
	charts.reveal_sea_zone(OWNER, 1, 0)
	var zones: Array[int] = AiColonisationPlanner._landing_zones(
		new_world, "explorer", OWNER, charts
	)
	var expected: Array[int] = [0]
	assert_eq(zones, expected, "the charted coast opens the landing")
	assert_true(
		AiColonisationPlanner._landing_zones(new_world, "explorer", OWNER).size() == 1,
		"without a chart the fixture reading keeps every coast"
	)


## The map adapter charts the water a rival enters, so a crossing opens the far
## coast for that court alone — the player's fog stays untouched.
func test_the_adapter_charts_the_coast_its_squadron_crosses_to() -> void:
	var world: WorldMap = _world()
	var old_world: MapModel = world.region(0)
	var fleet: FleetState = FleetState.in_port(1, OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, OWNER, "explorer", Vector2i(0, 0))
	var play := PlaySession.new()
	play.player_faction = 0
	play.region_index = 0
	play.map_seed = 1500
	play.world = world
	play.model = old_world
	play.ship_layer = ShipLayer.new()
	play.ship_layer.model = old_world
	play.ship_layer.world = world
	play.ship_layer.regions.set_region(0, [fleet])
	play.ship_layer.regions.set_region(1, [])
	play.civilian_layer = CivilianLayer.new()
	play.civilian_layer.model = old_world
	play.civilian_layer.units = [unit]
	play.civilian_layer.regions.set_region(0, [unit])
	play.civilian_layer.regions.set_region(1, [])
	MapPlayCourtFog.build(play)
	assert_false(play.court_charts.knows_zone(OWNER, 1, 0), "the far water is unknown")
	assert_eq(String(MapPlayColonisationAi.run(play)[0]["kind"]), "embark")
	fleet.moved = false
	assert_eq(String(MapPlayColonisationAi.run(play)[0]["kind"]), "sail")
	fleet.moved = false
	assert_eq(String(MapPlayColonisationAi.run(play)[0]["kind"]), "cross")
	assert_true(
		play.court_charts.knows_zone(OWNER, 1, 0),
		"the entered zone is charted for the rival"
	)
	fleet.moved = false
	var landed: Array[Dictionary] = MapPlayColonisationAi.run(play)
	assert_eq(String(landed[0]["kind"]), "land", "the charted coast takes the colonist")
	assert_true(play.court_charts.regions_of(0).is_empty(), "the player charts nothing")
	play.ship_layer.free()
	play.civilian_layer.free()


func test_the_adapter_docks_and_refuses_illegal_orders() -> void:
	var world: WorldMap = _world()
	var old_world: MapModel = world.region(0)
	var fleet: FleetState = FleetState.at_sea(1, OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, OWNER, "explorer", Vector2i(0, 0))
	var play := PlaySession.new()
	play.player_faction = 0
	play.region_index = 0
	play.map_seed = 1500
	play.world = world
	play.model = old_world
	play.ship_layer = ShipLayer.new()
	play.ship_layer.model = old_world
	play.ship_layer.world = world
	play.ship_layer.regions.set_region(0, [fleet])
	play.civilian_layer = CivilianLayer.new()
	play.civilian_layer.model = old_world
	play.civilian_layer.units = [unit]
	play.civilian_layer.regions.set_region(0, [unit])
	var docked: Array[Dictionary] = MapPlayColonisationAi.run(play)
	assert_eq(String(docked[0]["kind"]), "dock")
	assert_true(fleet.is_in_port())
	assert_true(MapPlayColonisationAi.run(null).is_empty())
	assert_true(MapPlayColonisationAi._apply(
		play, 0, old_world, {"kind": "bogus", "fleet": fleet.id}
	).is_empty())
	assert_true(MapPlayColonisationAi._apply(
		play, 0, old_world, {"kind": "sail", "fleet": fleet.id, "zone": 99}
	).is_empty())
	assert_true(MapPlayColonisationAi._apply(
		play, 0, old_world, {"kind": "cross", "fleet": fleet.id}
	).is_empty())
	assert_true(MapPlayColonisationAi._apply(
		play, 0, old_world,
		{"kind": "land", "fleet": fleet.id, "unit": 999, "tile": Vector2i(0, 0)}
	).is_empty())
	play.ship_layer.free()
	play.civilian_layer.free()
