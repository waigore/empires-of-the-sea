extends GdToolsTest
## Rival colonisation voyages (wiki: civilian-units § Overseas deployment;
## DR-20261109-17): board, sail, cross a Passage and land, one legal step a turn.

const OWNER: int = 1


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
		_config(), world, 0, old_world, [fleet], [unit], 0
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
		_config(), world, 0, old_world, [fleet], [unit], 0
	)
	assert_eq(String(sail.get("kind", "")), "sail")
	assert_eq(int(sail.get("zone", -1)), 0)
	assert_true(
		bool(FleetSortie.apply(old_world, fleet, 0)["ok"]),
		"a squadron in port at its own capital sorties"
	)
	fleet.moved = false
	var cross: Dictionary = AiColonisationPlanner.plan(
		_config(), world, 0, old_world, [fleet], [unit], 0
	)
	assert_eq(String(cross.get("kind", "")), "cross")
	var crossed: Dictionary = WarpTravel.apply_crossing(world, 0, fleet)
	assert_true(bool(crossed["ok"]))
	fleet.moved = false
	var land: Dictionary = AiColonisationPlanner.plan(
		_config(), world, 1, new_world, [fleet], [unit], 0
	)
	assert_eq(String(land.get("kind", "")), "land")
	assert_eq(Vector2i(land.get("tile", Vector2i(-1, -1))), Vector2i(0, 1))


func test_no_second_expedition_when_a_colonist_is_already_abroad() -> void:
	var world: WorldMap = _world()
	var old_world: MapModel = world.region(0)
	var fleet: FleetState = FleetState.in_port(1, OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, OWNER, "explorer", Vector2i(0, 0))
	var order: Dictionary = AiColonisationPlanner.plan(
		_config(), world, 0, old_world, [fleet], [unit], 1
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
		_config(), world, 0, old_world, [fleet], [unit], 0
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
		_config(), world, 0, old_world, [fleet], [unit], 0
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
		_config(), world, 1, new_world, [fleet], [unit], 0
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
