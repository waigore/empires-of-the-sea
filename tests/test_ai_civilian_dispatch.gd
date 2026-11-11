extends GdToolsTest
## The civilian dispatcher after the Engineer policy left it
## (wiki: civilian-work-planner). These cases pin the seam: a Rail Builder is
## routed to the Engineer module, and a rail is only offered once its crown can
## lay one, so every action the dispatcher emits is one the unit may work.

const CivilianFixture = preload("res://tests/civilian_fixture.gd")
const Planner = preload("res://scripts/ai/ai_civilian_planner.gd")

const BARE: Vector2i = Vector2i(0, 0)
const RAIL_TECHS: Dictionary = {"early_steam_engine": true}


func _context(at_war: bool = false) -> Dictionary:
	return {
		"treasury": 2500,
		"paper": 8,
		"capital_province": CivilianFixture.PLAYER_PROVINCE,
		"capital_tile": BARE,
		"at_war": at_war,
	}


func _plan(model: MapModel, unit: CivilianState, works: LandWorks) -> Dictionary:
	return Planner.plan(
		AiConfig.build(0, 1500), model, [unit] as Array, works,
		CivilianFixture.stockpile(), {}, RAIL_TECHS, _context()
	)


func _roaded_works(model: MapModel) -> LandWorks:
	var works := LandWorks.new()
	works.add_port(model, CivilianFixture.COAST_TILE)
	for tile: Vector2i in model.ownership.owned_tiles(model, 0):
		works.set_improvement(model, tile, LandWorks.MAX_IMPROVEMENT)
	works.set_transport(model, CivilianFixture.TIMBER_TILE, LandWorks.TRANSPORT_ROAD)
	return works


func test_a_rail_builder_lays_a_rail_on_an_existing_road() -> void:
	var model: MapModel = CivilianFixture.build()
	var unit: CivilianState = CivilianState.create(
		1, 0, "rail_builder", CivilianFixture.TIMBER_TILE
	)
	var plan: Dictionary = _plan(model, unit, _roaded_works(model))
	var orders: Array = plan["orders"]
	assert_eq(orders.size(), 1, "the Engineer policy answers for a Rail Builder")
	assert_eq(String(orders[0]["action"]), "build_rail")
	assert_eq(Vector2i(orders[0]["tile"]), CivilianFixture.TIMBER_TILE)


func test_a_rival_without_steam_never_orders_a_rail() -> void:
	var model: MapModel = CivilianFixture.build()
	var unit: CivilianState = CivilianState.create(
		1, 0, "rail_builder", CivilianFixture.TIMBER_TILE
	)
	var plan: Dictionary = Planner.plan(
		AiConfig.build(0, 1500), model, [unit] as Array, _roaded_works(model),
		CivilianFixture.stockpile(), {}, {}, _context()
	)
	for order: Dictionary in plan["orders"]:
		assert_ne(String(order["action"]), "build_rail", "no rail without its tech")


func test_every_dispatched_order_is_a_work_the_unit_may_do() -> void:
	var model: MapModel = CivilianFixture.build()
	var works := LandWorks.new()
	works.add_port(model, CivilianFixture.COAST_TILE)
	for type_id: String in ["builder", "engineer", "explorer", "rail_builder"]:
		var unit: CivilianState = CivilianState.create(1, 0, type_id, BARE)
		for order: Dictionary in _plan(model, unit, works)["orders"]:
			assert_true(
				CivilianCatalog.works(type_id).has(String(order["action"])),
				"%s may work %s" % [type_id, order["action"]]
			)
