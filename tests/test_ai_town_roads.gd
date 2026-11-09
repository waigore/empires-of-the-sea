extends GdToolsTest
## AI engineers connect every province town to the capital network (wiki:
## capital-and-connectivity § Town per province; civilian-work-planner).

const CAPITAL: Vector2i = Vector2i(0, 1)
const TOWN: Vector2i = Vector2i(4, 1)


func _model() -> MapModel:
	var model := MapModel.new()
	model.setup(5, 3)
	var tiles: Array[Vector2i] = []
	for y in 3:
		for x in 5:
			var tile := Vector2i(x, y)
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			model.province[model.index_of(x, y)] = 0
			tiles.append(tile)
	var province := ProvinceState.create(
		0, "Townshire", tiles, Vector2(2.0, 1.0), tiles.size(), 1, true
	)
	province.capital_tile = CAPITAL
	province.town_tile = TOWN
	model.provinces = [province]
	return model


func _stockpile() -> Dictionary:
	return {"lumber": 20, "castIron": 20}


func _connected(model: MapModel, tiles: Array[Vector2i]) -> Dictionary:
	var seen: Dictionary = {}
	for tile: Vector2i in tiles:
		seen[model.index_of(tile.x, tile.y)] = true
	return seen


func test_an_unconnected_town_targets_its_own_tile_first() -> void:
	var model: MapModel = _model()
	var works := LandWorks.new()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", CAPITAL)
	var best: Dictionary = AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, works, [unit], _stockpile(),
		{}, {}, {}, _connected(model, [CAPITAL]), {}
	)
	assert_eq(String(best.get("action", "")), "build_road")
	assert_eq(Vector2i(best.get("tile", Vector2i(-1, -1))), TOWN)


func test_the_next_step_follows_the_shortest_owned_path() -> void:
	var model: MapModel = _model()
	var works := LandWorks.new()
	works.set_transport(model, TOWN, LandWorks.TRANSPORT_ROAD)
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", CAPITAL)
	var best: Dictionary = AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, works, [unit], _stockpile(),
		{}, {}, {}, _connected(model, [CAPITAL]), {}
	)
	assert_eq(Vector2i(best.get("tile", Vector2i(-1, -1))), Vector2i(3, 1))


func test_a_connected_town_is_left_alone() -> void:
	var model: MapModel = _model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", CAPITAL)
	var best: Dictionary = AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, LandWorks.new(), [unit],
		_stockpile(), {}, {}, {},
		_connected(model, [CAPITAL, TOWN]), {}
	)
	assert_true(best.is_empty())


func test_the_engineer_planner_emits_the_town_road_order() -> void:
	var model: MapModel = _model()
	var works := LandWorks.new()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", CAPITAL)
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(1, 1500), model, [unit], works, _stockpile(), {}, {},
		{
			"treasury": 2500,
			"paper": 8,
			"capital_province": 0,
			"capital_tile": CAPITAL,
		}
	)
	var orders: Array = plan["orders"]
	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "build_road")
	assert_eq(
		model.resource_at(Vector2i(orders[0]["tile"]).x, Vector2i(orders[0]["tile"]).y),
		MapModel.NO_ID
	)


func test_without_a_capital_network_no_order_is_offered() -> void:
	var model: MapModel = _model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", CAPITAL)
	assert_true(AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, LandWorks.new(), [unit],
		_stockpile(), {}, {}, {}, {}, {}
	).is_empty())


func test_a_reserved_town_is_left_for_another_crew() -> void:
	var model: MapModel = _model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", CAPITAL)
	assert_true(AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, LandWorks.new(), [unit],
		_stockpile(), {}, {}, {}, _connected(model, [CAPITAL]), {TOWN: true}
	).is_empty())


func test_a_foreign_town_is_ignored() -> void:
	var model: MapModel = _model()
	model.provinces[0].owner = 2
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", CAPITAL)
	assert_true(AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, LandWorks.new(), [unit],
		_stockpile(), {}, {}, {}, _connected(model, [CAPITAL]), {}
	).is_empty())


func test_missing_inputs_are_guarded() -> void:
	var model: MapModel = _model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", CAPITAL)
	assert_true(AiTownRoads.best_candidate(
		null, model, unit, LandWorks.new(), [unit], _stockpile(), {}, {}, {},
		_connected(model, [CAPITAL]), {}
	).is_empty())


func test_a_reserved_path_tile_is_left_alone() -> void:
	var model: MapModel = _model()
	var works := LandWorks.new()
	works.set_transport(model, TOWN, LandWorks.TRANSPORT_ROAD)
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", CAPITAL)
	assert_true(AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, works, [unit], _stockpile(),
		{}, {}, {}, _connected(model, [CAPITAL]), {Vector2i(3, 1): true}
	).is_empty())


func test_a_working_engineer_gets_no_second_order() -> void:
	var model: MapModel = _model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", CAPITAL)
	unit.start_work("build_road", TOWN, 1)
	assert_true(AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, LandWorks.new(), [unit],
		_stockpile(), {}, {}, {}, _connected(model, [CAPITAL]), {}
	).is_empty())
