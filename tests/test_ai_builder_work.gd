extends GdToolsTest
## Rival Builders finish province towns that pay a manufacturing bonus, priced on
## the raw the crown actually gathers (wiki: extraction-and-improvements
## § Town manufacturing bonus; civilian-work-planner § Builders).
##
## The fixture is a colony of one town tile and two rail-linked timber estates:
## the estates are already fully improved, so the only legal work left is the
## town, and the whole question is whether the planner values it.

const TOWN: Vector2i = Vector2i(0, 0)
const TIMBER: Vector2i = Vector2i(1, 0)
const TIMBER_FAR: Vector2i = Vector2i(2, 0)


func _model(level: int) -> MapModel:
	var model := MapModel.new()
	model.setup(3, 1)
	var tiles: Array[Vector2i] = []
	for tile: Vector2i in [TOWN, TIMBER, TIMBER_FAR]:
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.PLAINS
		model.province[model.index_of(tile.x, tile.y)] = 0
		tiles.append(tile)
	var province := ProvinceState.create(0, "Plantation", tiles, Vector2.ZERO, 3, 1)
	province.town_tile = TOWN
	province.town_development = level
	model.provinces = [province]
	model.faction_ids.append(1)
	for tile: Vector2i in [TIMBER, TIMBER_FAR]:
		model.resource[model.index_of(tile.x, tile.y)] = 0
	return model


func _works(model: MapModel) -> LandWorks:
	var works := LandWorks.new()
	works.add_port(model, TOWN)
	for tile: Vector2i in [TIMBER, TIMBER_FAR]:
		works.set_improvement(model, tile, LandWorks.MAX_IMPROVEMENT)
		works.set_transport(model, tile, LandWorks.TRANSPORT_RAIL)
	return works


func _stockpile() -> Dictionary:
	return {"timber": 200, "lumber": 40, "castIron": 40}


func _plan(model: MapModel, context: Dictionary = {}) -> Dictionary:
	var builder: CivilianState = CivilianState.create(1, 1, "builder", TIMBER)
	return AiCivilianPlanner.plan(
		AiConfig.build(1, 1500), model, [builder], _works(model), _stockpile(),
		{"timber": 4}, {"national_bureaucracy": true}, context
	)


## The estates are finished, so the town is the only order left; a level-1 town
## that would pay 4 lumber a turn is worth more than idling the Builder.
func test_a_developing_town_becomes_the_builders_order() -> void:
	var plan: Dictionary = _plan(_model(1))
	var orders: Array = plan["orders"]

	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "upgrade_town")
	assert_eq(Vector2i(orders[0]["tile"]), TOWN)


## An overseas province is priced on the tons the holds landed, not on the far
## shore's harvest: with nothing delivered the town pays nothing and is left.
func test_an_overseas_town_with_nothing_landed_is_left_alone() -> void:
	var plan: Dictionary = _plan(_model(1), {"delivered_raw": {}})

	assert_true((plan["orders"] as Array).is_empty())
	assert_true((plan["moves"] as Array).is_empty())


func test_an_overseas_town_is_upgraded_from_the_tons_that_landed() -> void:
	var plan: Dictionary = _plan(_model(1), {"delivered_raw": {0: {"timber": 8}}})
	var orders: Array = plan["orders"]

	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "upgrade_town")


func test_a_finished_town_is_left_alone() -> void:
	assert_true((_plan(_model(CivilianWorkPlan.MAX_TOWN))["orders"] as Array).is_empty())


func test_the_bureaucracy_gate_still_refuses_the_order() -> void:
	var model: MapModel = _model(1)
	var builder: CivilianState = CivilianState.create(1, 1, "builder", TIMBER)
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(1, 1500), model, [builder], _works(model), _stockpile(),
		{"timber": 4}, {}, {}
	)

	assert_true((plan["orders"] as Array).is_empty(), "no national_bureaucracy")
