extends GdToolsTest
## Rival Engineer policy after it left the civilian dispatcher
## (wiki: civilian-work-planner § Engineer; capital-and-connectivity;
## civilian-units § Engineer, § Rail Builder). These cases pin the split: the
## Engineer module owns the roads, the harbour and the wartime fort, while a
## rail is the Rail Builder's own work.

const CivilianFixture = preload("res://tests/civilian_fixture.gd")
const Engineer = preload("res://scripts/ai/ai_engineer_work.gd")

const BARE: Vector2i = Vector2i(0, 0)


func _context(at_war: bool = false) -> Dictionary:
	return {
		"treasury": 2500,
		"paper": 8,
		"capital_province": CivilianFixture.PLAYER_PROVINCE,
		"capital_tile": BARE,
		"at_war": at_war,
	}


func _engineer_order(model: MapModel, works: LandWorks, at_war: bool = false) -> Dictionary:
	var unit: CivilianState = CivilianState.create(1, 0, "engineer", BARE)
	return Engineer.best_candidate(
		AiConfig.build(0, 1500), model, unit, [unit] as Array, works,
		CivilianFixture.stockpile(), {}, {}, _context(at_war), {}
	)


## Every owned tile improved and ported, so the only work left is transport.
func _works(model: MapModel) -> LandWorks:
	var works := LandWorks.new()
	works.add_port(model, CivilianFixture.COAST_TILE)
	for tile: Vector2i in model.ownership.owned_tiles(model, 0):
		works.set_improvement(model, tile, LandWorks.MAX_IMPROVEMENT)
	return works


func test_a_road_still_reaches_a_resource_without_one() -> void:
	var model: MapModel = CivilianFixture.build()
	var order: Dictionary = _engineer_order(model, _works(model))
	assert_eq(String(order.get("action", "")), "build_road")
	var tile: Vector2i = order.get("tile", CivilianState.NO_TILE)
	assert_ne(model.resource_at(tile.x, tile.y), MapModel.NO_ID, "the road reaches a resource")


func test_a_coastal_province_without_a_port_gets_one() -> void:
	var model: MapModel = CivilianFixture.build()
	for tile: Vector2i in model.provinces[0].tiles:
		model.resource[model.index_of(tile.x, tile.y)] = MapModel.NO_ID
	var order: Dictionary = _engineer_order(model, LandWorks.new())
	var tile: Vector2i = order.get("tile", CivilianState.NO_TILE)
	assert_eq(String(order.get("action", "")), "build_port")
	assert_true(MapGeo.is_coastal_tile(model, tile.x, tile.y), "a port only rises on the coast")


func test_an_invaded_court_prices_its_fort_with_wartime_urgency() -> void:
	var model: MapModel = CivilianFixture.build()
	var works := LandWorks.new()
	works.add_port(model, CivilianFixture.COAST_TILE)
	var unit: CivilianState = CivilianState.create(1, 0, "engineer", BARE)
	var fort: Dictionary = Engineer.fort_candidate(
		AiConfig.build(0, 1500), model, unit, [unit] as Array, works,
		CivilianFixture.stockpile(), {}, {}, _context(true)
	)
	var road: Dictionary = _engineer_order(model, works)
	assert_eq(String(fort.get("action", "")), "build_fort")
	assert_eq(Vector2i(fort["tile"]), FortRules.site_tile(model, CivilianFixture.PLAYER_PROVINCE))
	# An invaded court prices its fort above its other works as a floor: the fort
	# weight plus the wartime urgency, whatever the hinterland still owes.
	var weight: int = AiConfig.build(0, 1500).parameter("civilian.fort_weight")
	assert_true(int(fort["score"]) >= weight + 50, "the fort carries its wartime urgency")
	assert_eq(String(road.get("action", "")), "build_road")


func test_the_engineer_never_offers_a_rail() -> void:
	var model: MapModel = CivilianFixture.build()
	var works: LandWorks = _works(model)
	works.set_transport(model, CivilianFixture.TIMBER_TILE, LandWorks.TRANSPORT_ROAD)
	for at_war: bool in [false, true]:
		var order: Dictionary = _engineer_order(model, works, at_war)
		assert_ne(String(order.get("action", "")), "build_rail", "a rail is the Rail Builder's work")


func test_no_engineer_work_without_a_config() -> void:
	var model: MapModel = CivilianFixture.build()
	var unit: CivilianState = CivilianState.create(1, 0, "engineer", BARE)
	assert_true(Engineer.best_candidate(
		null, model, unit, [unit] as Array, LandWorks.new(),
		CivilianFixture.stockpile(), {}, {}, _context(), {}
	).is_empty())
