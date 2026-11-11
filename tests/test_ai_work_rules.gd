extends GdToolsTest
## Rival Builders finish province towns that pay a manufacturing bonus, priced on
## the raw the crown actually gathers (wiki: extraction-and-improvements
## § Town manufacturing bonus; civilian-work-planner § Builders).
##
## The fixture is a colony of one town tile and two rail-linked timber estates:
## the estates are already fully improved, so the only legal work left is the
## town, and the whole question is whether the planner values it.
## Consolidated rulebook: AiBuilderWork + AiEngineerWork + AiCivilianDispatch
## + AiHospitalWork + AiTownRoads + AiArmyReinforce (one Godot boot per domain).

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


# --- a capital province, where the town caps its estates ----------------------

## A Great Power seat: the town's development caps what its estates may gather,
## so a Builder that raises an estate past the cap spends lumber and cast iron
## for nothing until the town rises (wiki: capital-and-connectivity § Town rule).
const SEAT: Vector2i = Vector2i(0, 0)
const SEAT_ESTATE: Vector2i = Vector2i(1, 0)
const SEAT_ESTATE_FAR: Vector2i = Vector2i(2, 0)


func _seat_model(town_level: int, estate_level: int) -> MapModel:
	var model := MapModel.new()
	model.setup(3, 1)
	var tiles: Array[Vector2i] = []
	for tile: Vector2i in [SEAT, SEAT_ESTATE, SEAT_ESTATE_FAR]:
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.PLAINS
		model.province[model.index_of(tile.x, tile.y)] = 0
		tiles.append(tile)
	var province := ProvinceState.create(0, "Seat", tiles, Vector2.ZERO, 3, 1, true)
	province.town_tile = SEAT
	province.capital_tile = SEAT
	province.town_development = town_level
	model.provinces = [province]
	model.faction_ids.append(1)
	for tile: Vector2i in [SEAT_ESTATE, SEAT_ESTATE_FAR]:
		model.resource[model.index_of(tile.x, tile.y)] = 0
	return model


func _seat_works(model: MapModel, estate_level: int) -> LandWorks:
	var works := LandWorks.new()
	works.add_port(model, SEAT)
	for tile: Vector2i in [SEAT_ESTATE, SEAT_ESTATE_FAR]:
		if estate_level > 0:
			works.set_improvement(model, tile, estate_level)
		works.set_transport(model, tile, LandWorks.TRANSPORT_RAIL)
	return works


func _seat_plan(town_level: int, estate_level: int) -> Dictionary:
	var model: MapModel = _seat_model(town_level, estate_level)
	var builder: CivilianState = CivilianState.create(1, 1, "builder", SEAT_ESTATE)
	return AiCivilianPlanner.plan(
		AiConfig.build(1, 1500), model, [builder], _seat_works(model, estate_level),
		{"timber": 2, "lumber": 40, "castIron": 40}, {"timber": 4},
		{"national_bureaucracy": true}
	)


## Stores are short of timber, but a level-1 estate in a level-1 seat gathers
## nothing more at level 2: the town is the order that pays, so the Builder
## raises the town instead of buying a dead estate level.
func test_a_town_capping_its_estates_is_raised_before_the_estate() -> void:
	var plan: Dictionary = _seat_plan(1, 1)
	var orders: Array = plan["orders"]

	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "upgrade_town")
	assert_eq(Vector2i(orders[0]["tile"]), SEAT)


## Once the estate is fully improved the town is the only order left, and it is
## raised even though its manufactures are still short of one four-ton run: the
## estate levels it unlocks are what the Builder is buying.
func test_a_town_is_raised_for_the_estate_levels_it_unlocks() -> void:
	var plan: Dictionary = _seat_plan(1, LandWorks.MAX_IMPROVEMENT)
	var orders: Array = plan["orders"]

	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "upgrade_town")
	assert_eq(Vector2i(orders[0]["tile"]), SEAT)


## A developed town no longer caps its estates, so the Builder raises the estate
## at once — the cap read must not idle a court that can gather.
func test_a_developed_town_frees_the_estate_order() -> void:
	var plan: Dictionary = _seat_plan(CivilianWorkPlan.MAX_TOWN, 1)
	var orders: Array = plan["orders"]

	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "build_improvement")
	assert_eq(Vector2i(orders[0]["tile"]), SEAT_ESTATE)


## An estate held back by the town cap earns no shortage premium: an estate the
## crown can gather from wins the Builder even when its commodity is abundant.
func test_a_capped_estate_earns_no_shortage_premium() -> void:
	var row: Dictionary = {
		"tile": SEAT_ESTATE, "province": 0, "commodity": "timber", "level": 1,
		"tech_cap": 4, "terrain_cap": 4, "transport": 4, "town_cap": 1,
		"output": 1, "connected": true,
	}
	var open_row: Dictionary = row.duplicate()
	open_row["town_cap"] = 4
	open_row["output"] = 1

	assert_eq(AiBuilderWork.paid_gain(row), 0, "the town cap pays nothing more")
	assert_eq(AiBuilderWork.paid_gain(open_row), 1, "the next level pays")
	assert_eq(AiBuilderWork.town_unlocks([row], 0), 1, "the town unlocks one level")
	assert_eq(AiBuilderWork.town_unlocks([open_row], 0), 0, "a free estate unlocks nothing")


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
func _engineer_works(model: MapModel) -> LandWorks:
	var works := LandWorks.new()
	works.add_port(model, CivilianFixture.COAST_TILE)
	for tile: Vector2i in model.ownership.owned_tiles(model, 0):
		works.set_improvement(model, tile, LandWorks.MAX_IMPROVEMENT)
	return works


func test_a_road_still_reaches_a_resource_without_one() -> void:
	var model: MapModel = CivilianFixture.build()
	var order: Dictionary = _engineer_order(model, _engineer_works(model))
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
	var works: LandWorks = _engineer_works(model)
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


## The civilian dispatcher after the Engineer policy left it
## (wiki: civilian-work-planner). These cases pin the seam: a Rail Builder is
## routed to the Engineer module, and a rail is only offered once its crown can
## lay one, so every action the dispatcher emits is one the unit may work.

const Planner = preload("res://scripts/ai/ai_civilian_planner.gd")

const DISPATCH_BARE: Vector2i = Vector2i(0, 0)
const RAIL_TECHS: Dictionary = {"early_steam_engine": true}


func _dispatch_context(at_war: bool = false) -> Dictionary:
	return {
		"treasury": 2500,
		"paper": 8,
		"capital_province": CivilianFixture.PLAYER_PROVINCE,
		"capital_tile": DISPATCH_BARE,
		"at_war": at_war,
	}


func _dispatch_plan(model: MapModel, unit: CivilianState, works: LandWorks) -> Dictionary:
	return Planner.plan(
		AiConfig.build(0, 1500), model, [unit] as Array, works,
		CivilianFixture.stockpile(), {}, RAIL_TECHS, _dispatch_context()
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
	var plan: Dictionary = _dispatch_plan(model, unit, _roaded_works(model))
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
		CivilianFixture.stockpile(), {}, {}, _dispatch_context()
	)
	for order: Dictionary in plan["orders"]:
		assert_ne(String(order["action"]), "build_rail", "no rail without its tech")


func test_every_dispatched_order_is_a_work_the_unit_may_do() -> void:
	var model: MapModel = CivilianFixture.build()
	var works := LandWorks.new()
	works.add_port(model, CivilianFixture.COAST_TILE)
	for type_id: String in ["builder", "engineer", "explorer", "rail_builder"]:
		var unit: CivilianState = CivilianState.create(1, 0, type_id, DISPATCH_BARE)
		for order: Dictionary in _dispatch_plan(model, unit, works)["orders"]:
			assert_true(
				CivilianCatalog.works(type_id).has(String(order["action"])),
				"%s may work %s" % [type_id, order["action"]]
			)


## Rival engineers raise province hospitals (wiki: combat § Regiment condition;
## civilian-work-planner § Playable slice; DR-20261111-16). The scorer offers
## the seat first, then the best-developed town, and the planner keeps that
## build over the town sweep only while the court is at war.

const CAPITAL: Vector2i = Vector2i(0, 1)
const OUTER_TOWN: Vector2i = Vector2i(4, 1)
const CAPITAL_PROVINCE: int = 0
const OUTER_PROVINCE: int = 1

const TECH: Dictionary = {
	"organised_regiments": true,
	"modern_military_funding": true,
}


## A capital province with a seat and a second owned town province; no resource
## tiles and no coast, so an Engineer's only other work is the town sweep.
func _hospital_model() -> MapModel:
	var model := MapModel.new()
	model.setup(5, 3)
	var capital_tiles: Array[Vector2i] = []
	var outer_tiles: Array[Vector2i] = []
	for y in 3:
		for x in 5:
			var tile := Vector2i(x, y)
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			if x < 3:
				model.province[model.index_of(x, y)] = CAPITAL_PROVINCE
				capital_tiles.append(tile)
			else:
				model.province[model.index_of(x, y)] = OUTER_PROVINCE
				outer_tiles.append(tile)
	var capital := ProvinceState.create(
		CAPITAL_PROVINCE, "Cádiz", capital_tiles, Vector2(1.0, 1.0),
		capital_tiles.size(), 0, true
	)
	capital.capital_tile = CAPITAL
	capital.town_tile = CAPITAL
	var outer := ProvinceState.create(
		OUTER_PROVINCE, "Coro", outer_tiles, Vector2(4.0, 1.0),
		outer_tiles.size(), 0, false
	)
	outer.town_tile = OUTER_TOWN
	model.provinces = [capital, outer]
	return model


func _hospital_stockpile() -> Dictionary:
	return {"lumber": 20, "fabric": 20, "steel": 20, "castIron": 20}


func _hospital_context(at_war: bool = true) -> Dictionary:
	return {
		"treasury": 2500,
		"paper": 8,
		"capital_province": CAPITAL_PROVINCE,
		"capital_tile": CAPITAL,
		"at_war": at_war,
	}


func _best(
	model: MapModel, tech_unlocked: Dictionary = TECH, reserved: Dictionary = {}
) -> Dictionary:
	var unit: CivilianState = CivilianState.create(1, 0, "engineer", CAPITAL)
	return AiHospitalWork.best_candidate(
		AiConfig.build(0, 1500), model, unit, [unit], LandWorks.new(),
		_hospital_stockpile(), {}, tech_unlocked, _hospital_context(), reserved
	)


func test_the_seat_raises_the_first_hospital() -> void:
	var best: Dictionary = _best(_hospital_model())
	assert_eq(String(best.get("action", "")), "build_hospital")
	assert_eq(Vector2i(best.get("tile", Vector2i(-1, -1))), CAPITAL)
	assert_eq(int((best.get("cost", {}) as Dictionary).get("lumber", 0)), 3)
	assert_eq(int((best.get("cost", {}) as Dictionary).get("fabric", 0)), 2)
	assert_eq(int(best.get("duration", 0)), 1, "a field hospital takes one turn")


func test_the_seat_is_upgraded_before_a_new_province() -> void:
	var model: MapModel = _hospital_model()
	model.province_data(CAPITAL_PROVINCE).hospital_level = 1
	var best: Dictionary = _best(model)
	assert_eq(Vector2i(best.get("tile", Vector2i(-1, -1))), CAPITAL)
	assert_eq(int((best.get("cost", {}) as Dictionary).get("steel", 0)), 2)
	assert_eq(int(best.get("duration", 0)), 2, "a general hospital takes two turns")


func test_a_field_hospital_waits_while_its_tech_is_unknown() -> void:
	var best: Dictionary = _best(_hospital_model(), {})
	assert_true(best.is_empty(), "Organised Regiments gates the first hospital")


func test_a_general_hospital_waits_for_its_own_tech() -> void:
	var model: MapModel = _hospital_model()
	model.province_data(CAPITAL_PROVINCE).hospital_level = 1
	var best: Dictionary = _best(model, {"organised_regiments": true})
	assert_eq(String(best.get("action", "")), "build_hospital")
	assert_eq(
		Vector2i(best.get("tile", Vector2i(-1, -1))), OUTER_TOWN,
		"the gated upgrade gives way to a field hospital elsewhere"
	)


func test_a_second_province_follows_the_seat() -> void:
	var model: MapModel = _hospital_model()
	model.province_data(CAPITAL_PROVINCE).hospital_level = HospitalRules.MAX_LEVEL
	var best: Dictionary = _best(model)
	assert_eq(Vector2i(best.get("tile", Vector2i(-1, -1))), OUTER_TOWN)


func test_a_reserved_town_waits_its_turn() -> void:
	var model: MapModel = _hospital_model()
	var reserved: Dictionary = {CAPITAL: true}
	var best: Dictionary = _best(model, TECH, reserved)
	assert_eq(Vector2i(best.get("tile", Vector2i(-1, -1))), OUTER_TOWN)


func test_a_built_out_court_raises_no_more() -> void:
	var model: MapModel = _hospital_model()
	model.province_data(CAPITAL_PROVINCE).hospital_level = HospitalRules.MAX_LEVEL
	model.province_data(OUTER_PROVINCE).hospital_level = HospitalRules.MAX_LEVEL
	assert_true(_best(model).is_empty())


func test_a_townless_province_is_skipped() -> void:
	var model: MapModel = _hospital_model()
	model.province_data(CAPITAL_PROVINCE).hospital_level = HospitalRules.MAX_LEVEL
	var bare := ProvinceState.create(
		2, "Wilds", [Vector2i(2, 2)] as Array[Vector2i], Vector2(2.0, 2.0),
		1, 0, false
	)
	model.provinces.append(bare)
	var best: Dictionary = _best(model)
	assert_eq(
		Vector2i(best.get("tile", Vector2i(-1, -1))), OUTER_TOWN,
		"only the province with a town can host a hospital"
	)


func test_another_courts_province_is_never_planned() -> void:
	var model: MapModel = _hospital_model()
	model.province_data(CAPITAL_PROVINCE).hospital_level = HospitalRules.MAX_LEVEL
	model.province_data(OUTER_PROVINCE).owner = 1
	assert_true(_best(model).is_empty())


func test_the_engineer_planner_raises_a_hospital_at_war() -> void:
	var model: MapModel = _hospital_model()
	model.province_data(CAPITAL_PROVINCE).fort_level = FortRules.MAX_LEVEL
	var unit: CivilianState = CivilianState.create(1, 0, "engineer", CAPITAL)
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(0, 1500), model, [unit], LandWorks.new(), _hospital_stockpile(),
		{}, TECH, _hospital_context(true)
	)
	var orders: Array = plan["orders"]
	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "build_hospital")
	assert_eq(Vector2i(orders[0]["tile"]), CAPITAL)


func test_peace_leaves_the_town_sweep_first() -> void:
	var model: MapModel = _hospital_model()
	model.province_data(CAPITAL_PROVINCE).fort_level = FortRules.MAX_LEVEL
	var unit: CivilianState = CivilianState.create(1, 0, "engineer", CAPITAL)
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(0, 1500), model, [unit], LandWorks.new(), _hospital_stockpile(),
		{}, TECH, _hospital_context(false)
	)
	var orders: Array = plan["orders"]
	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "build_road")


func test_nothing_is_planned_without_a_world() -> void:
	var unit: CivilianState = CivilianState.create(1, 0, "engineer", CAPITAL)
	assert_true(AiHospitalWork.best_candidate(
		AiConfig.build(0, 1500), null, unit, [unit], null, _hospital_stockpile(), {},
		TECH, _hospital_context(), {}
	).is_empty())


func test_a_fort_always_holds_over_the_town_sweep() -> void:
	assert_true(AiHospitalWork.holds_over_town_link(
		{"action": "build_fort"}, _hospital_context(false)
	))
	assert_false(AiHospitalWork.holds_over_town_link(
		{"action": "build_hospital"}, _hospital_context(false)
	))
	assert_true(AiHospitalWork.holds_over_town_link(
		{"action": "build_hospital"}, _hospital_context(true)
	))
	assert_false(AiHospitalWork.holds_over_town_link({}, _hospital_context(true)))


func test_the_tie_break_is_row_major_then_action_name() -> void:
	var upper: Dictionary = {"action": "build_hospital", "tile": Vector2i(1, 2), "score": 40}
	var lower: Dictionary = {"action": "build_hospital", "tile": Vector2i(4, 3), "score": 40}
	var left: Dictionary = {"action": "build_hospital", "tile": Vector2i(2, 3), "score": 40}
	var early: Dictionary = {"action": "build_fort", "tile": Vector2i(1, 2), "score": 40}
	assert_eq(Vector2i(AiHospitalWork._better(lower, upper)["tile"]), Vector2i(1, 2))
	assert_eq(Vector2i(AiHospitalWork._better(upper, lower)["tile"]), Vector2i(1, 2))
	assert_eq(Vector2i(AiHospitalWork._better(lower, left)["tile"]), Vector2i(2, 3))
	assert_eq(Vector2i(AiHospitalWork._better(left, lower)["tile"]), Vector2i(2, 3))
	assert_eq(String(AiHospitalWork._better(upper, early)["action"]), "build_fort")
	assert_eq(String(AiHospitalWork._better(early, upper)["action"]), "build_fort")
	assert_eq(String(AiHospitalWork._better({}, upper)["action"]), "build_hospital")
	assert_eq(String(AiHospitalWork._better(upper, {})["action"]), "build_hospital")


## AI engineers connect every province town to the capital network (wiki:
## capital-and-connectivity § Town per province; civilian-work-planner).

const ROAD_CAPITAL: Vector2i = Vector2i(0, 1)
const ROAD_TOWN: Vector2i = Vector2i(4, 1)


func _road_model() -> MapModel:
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
	province.capital_tile = ROAD_CAPITAL
	province.town_tile = ROAD_TOWN
	model.provinces = [province]
	return model


func _road_stockpile() -> Dictionary:
	return {"lumber": 20, "castIron": 20}


func _connected(model: MapModel, tiles: Array[Vector2i]) -> Dictionary:
	var seen: Dictionary = {}
	for tile: Vector2i in tiles:
		seen[model.index_of(tile.x, tile.y)] = true
	return seen


func test_an_unconnected_town_targets_its_own_tile_first() -> void:
	var model: MapModel = _road_model()
	var works := LandWorks.new()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ROAD_CAPITAL)
	var best: Dictionary = AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, works, [unit], _road_stockpile(),
		{}, {}, {}, _connected(model, [ROAD_CAPITAL]), {}
	)
	assert_eq(String(best.get("action", "")), "build_road")
	assert_eq(Vector2i(best.get("tile", Vector2i(-1, -1))), ROAD_TOWN)


func test_the_next_step_follows_the_shortest_owned_path() -> void:
	var model: MapModel = _road_model()
	var works := LandWorks.new()
	works.set_transport(model, ROAD_TOWN, LandWorks.TRANSPORT_ROAD)
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ROAD_CAPITAL)
	var best: Dictionary = AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, works, [unit], _road_stockpile(),
		{}, {}, {}, _connected(model, [ROAD_CAPITAL]), {}
	)
	assert_eq(Vector2i(best.get("tile", Vector2i(-1, -1))), Vector2i(3, 1))


func test_a_connected_town_is_left_alone() -> void:
	var model: MapModel = _road_model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ROAD_CAPITAL)
	var best: Dictionary = AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, LandWorks.new(), [unit],
		_road_stockpile(), {}, {}, {},
		_connected(model, [ROAD_CAPITAL, ROAD_TOWN]), {}
	)
	assert_true(best.is_empty())


func test_the_engineer_planner_emits_the_town_road_order() -> void:
	var model: MapModel = _road_model()
	var works := LandWorks.new()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ROAD_CAPITAL)
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(1, 1500), model, [unit], works, _road_stockpile(), {}, {},
		{
			"treasury": 2500,
			"paper": 8,
			"capital_province": 0,
			"capital_tile": ROAD_CAPITAL,
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
	var model: MapModel = _road_model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ROAD_CAPITAL)
	assert_true(AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, LandWorks.new(), [unit],
		_road_stockpile(), {}, {}, {}, {}, {}
	).is_empty())


func test_a_reserved_town_is_left_for_another_crew() -> void:
	var model: MapModel = _road_model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ROAD_CAPITAL)
	assert_true(AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, LandWorks.new(), [unit],
		_road_stockpile(), {}, {}, {}, _connected(model, [ROAD_CAPITAL]), {ROAD_TOWN: true}
	).is_empty())


func test_a_foreign_town_is_ignored() -> void:
	var model: MapModel = _road_model()
	model.provinces[0].owner = 2
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ROAD_CAPITAL)
	assert_true(AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, LandWorks.new(), [unit],
		_road_stockpile(), {}, {}, {}, _connected(model, [ROAD_CAPITAL]), {}
	).is_empty())


func test_missing_inputs_are_guarded() -> void:
	var model: MapModel = _road_model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ROAD_CAPITAL)
	assert_true(AiTownRoads.best_candidate(
		null, model, unit, LandWorks.new(), [unit], _road_stockpile(), {}, {}, {},
		_connected(model, [ROAD_CAPITAL]), {}
	).is_empty())


func test_a_reserved_path_tile_is_left_alone() -> void:
	var model: MapModel = _road_model()
	var works := LandWorks.new()
	works.set_transport(model, ROAD_TOWN, LandWorks.TRANSPORT_ROAD)
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ROAD_CAPITAL)
	assert_true(AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, works, [unit], _road_stockpile(),
		{}, {}, {}, _connected(model, [ROAD_CAPITAL]), {Vector2i(3, 1): true}
	).is_empty())


func test_a_working_engineer_gets_no_second_order() -> void:
	var model: MapModel = _road_model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ROAD_CAPITAL)
	unit.start_work("build_road", ROAD_TOWN, 1)
	assert_true(AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, LandWorks.new(), [unit],
		_road_stockpile(), {}, {}, {}, _connected(model, [ROAD_CAPITAL]), {}
	).is_empty())


## Wiki: ai-architecture § Town-per-province roads — a town road outranks
## incidental works, so a resource road next to the capital never pre-empts the
## link that lets the Town rule connect the province's estates.
func test_a_town_road_outranks_an_incidental_resource_road() -> void:
	var model: MapModel = _road_model()
	var grain: Vector2i = Vector2i(1, 1)
	model.resource[model.index_of(grain.x, grain.y)] = 4
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ROAD_CAPITAL)
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(1, 1500), model, [unit], LandWorks.new(), _road_stockpile(), {}, {},
		{
			"treasury": 2500,
			"paper": 8,
			"capital_province": 0,
			"capital_tile": ROAD_CAPITAL,
		}
	)
	var orders: Array = plan["orders"]
	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "build_road")
	assert_eq(
		Vector2i(orders[0]["tile"]), ROAD_TOWN, "the town link comes before an incidental road"
	)


## Wiki: ai-architecture § Town-per-province roads — the court's own fort still
## comes first when it is invaded. The fort stands on the province's own site
## (CivilianWork sites it on the town), so this pins the choice, not the seat.
func test_an_invaded_court_raises_its_fort_before_a_town_road() -> void:
	var model: MapModel = _road_model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ROAD_CAPITAL)
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(1, 1500), model, [unit], LandWorks.new(),
		{"lumber": 20, "castIron": 20, "bronze": 20}, {}, {},
		{
			"treasury": 2500,
			"paper": 8,
			"capital_province": 0,
			"capital_tile": ROAD_CAPITAL,
			"at_war": true,
		}
	)
	var orders: Array = plan["orders"]
	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "build_fort")
	assert_eq(
		Vector2i(orders[0]["tile"]),
		FortRules.site_tile(model, 0),
		"the fort stands where the rules site it"
	)


## Rival land reinforcement (wiki: ai-architecture § Land reinforcement,
## growth-stage-planner § Recruitment modulation; DR-20261111-04). A rival court
## raises a line regiment from its own ledger through the same muster the human
## drill yard uses — one a turn, the strongest legal pattern, and only while its
## economy can carry the price (REQ-P2-03, REQ-P3-03).

const OWNER: int = 2
const HUMAN: int = 1

const AiFixture = preload("res://tests/ai_fixture.gd")


func _config() -> AiConfig:
	return AiConfig.build(OWNER, 1500)


## A court with its own ledger: treasury and the opening stock of fabric and
## cast iron the line rows need.
func _economy(treasury: int = 12000, peasants: int = 6) -> PlayerEconomy:
	var economy := PlayerEconomy.starting()
	economy.treasury = treasury
	economy.workers = WorkerPool.make(peasants)
	return economy


# --- planner ----------------------------------------------------------------


func test_a_rival_musters_the_strongest_line_it_can_pay_for() -> void:
	var plan: Dictionary = AiArmyReinforce.plan(_config(), _economy(), 5, false)

	assert_eq(String(plan["muster"]), "arquebusiers", "the strongest era-1 line")
	var candidates: Array = plan["candidates"]
	assert_true(candidates.size() > 0)
	assert_eq(String(candidates[0]["type_id"]), "arquebusiers")
	for entry: Dictionary in candidates:
		assert_true(
			RegimentCatalog.category(String(entry["type_id"]))
			in AiArmyReinforce.LINE_CATEGORIES,
			"a mustered regiment is a line regiment"
		)


func test_the_war_chest_keeps_the_court_from_overspending() -> void:
	# 4,000 ducats covers a pike, but that would empty the purse; the 2,000 levy
	# is the only line that leaves the court's thousand-ducat floor in the bank.
	var plan: Dictionary = AiArmyReinforce.plan(_config(), _economy(4000), 5, false)

	assert_eq(String(plan["muster"]), "peasant_levies")
	var priced: Dictionary = AiArmyReinforce.plan(_config(), _economy(1500), 5, false)
	assert_eq(String(priced["muster"]), "", "nothing payable leaves the floor alone")
	assert_true((priced["reasons"] as Array).has("nothing payable"))


func test_a_court_at_target_strength_waits_and_a_war_lifts_the_target() -> void:
	var peace: Dictionary = AiArmyReinforce.plan(_config(), _economy(), 8, false)
	assert_eq(String(peace["muster"]), "", "eight regiments is the peace target")
	assert_eq(int(peace["target"]), 8)

	var war: Dictionary = AiArmyReinforce.plan(_config(), _economy(), 8, true)
	assert_eq(int(war["target"]), 12, "the war footing raises the target by four")
	assert_eq(String(war["muster"]), "arquebusiers", "a court at war arms up")

	var full: Dictionary = AiArmyReinforce.plan(_config(), _economy(), 12, true)
	assert_eq(String(full["muster"]), "", "the war target is a ceiling too")


func test_a_thin_labour_pool_stops_the_muster() -> void:
	var plan: Dictionary = AiArmyReinforce.plan(_config(), _economy(12000, 3), 5, false)

	assert_eq(String(plan["muster"]), "", "the fields keep their hands")
	assert_true((plan["reasons"] as Array).has("labour floor"))


func test_a_researched_pattern_is_the_one_that_musters() -> void:
	var economy: PlayerEconomy = _economy()
	economy.tech_unlocked["weapon_craftsmanship"] = true
	var plan: Dictionary = AiArmyReinforce.plan(_config(), economy, 5, false)

	assert_eq(String(plan["muster"]), "musketeers", "the newest legal line wins")


# --- map adapter ------------------------------------------------------------


## One peace-time world: England's seat at province 0, France's at province 1,
## with a rival ledger already resolved for France.
func _play(treasury: int = 12000, with_ledger: bool = true) -> PlaySession:
	var world: WorldMap = AiFixture.land_world([HUMAN, OWNER], {0: true, 1: true})
	var model: MapModel = world.region(0)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, HUMAN, 0, true, ["peasant_levies"] as Array[String], 1),
		ArmyState.muster(
			2, OWNER, 1, true, ["peasant_levies", "peasant_levies"] as Array[String], 101
		),
	]
	var layer := ArmyLayer.new()
	layer.model = model
	layer.next_army = 100
	layer.next_regiment = 1000
	layer.regions.set_region(0, armies)
	var play := PlaySession.new()
	play.player_faction = HUMAN
	play.world = world
	play.model = model
	var court := DiplomacyState.new()
	court.reset(HUMAN)
	court.ensure_relation(HUMAN, OWNER, 1)
	play.diplomacy = court
	play.army_layer = layer
	play.map_seed = 1500
	if with_ledger:
		play.ai = AiState.new()
		play.ai.economies[OWNER] = _economy(treasury)
	return play


func test_the_map_pass_musters_a_rival_from_its_own_ledger() -> void:
	var play: PlaySession = _play(12000)
	var economy: PlayerEconomy = play.ai.economies[OWNER]
	var before: int = play.army_layer.regiment_count_all(OWNER)
	var peasants: int = economy.available_peasants()

	var trace: Array[Dictionary] = MapPlayArmies.run_ai(play)

	assert_eq(trace.size(), 1, "a muster and nothing else in peace")
	assert_eq(String(trace[0]["kind"]), MapPlayArmyAi.KIND_REINFORCE)
	assert_eq(String(trace[0]["type"]), "arquebusiers")
	assert_eq(play.army_layer.regiment_count_all(OWNER), before + 1)
	assert_eq(economy.available_peasants(), peasants - 1, "one peasant joins the colours")
	assert_true(
		economy.treasury < 12000, "the court's own purse pays, never the crown's"
	)
	var home: ArmyState = ArmyTraining.home_army(play.army_layer.armies, OWNER)
	assert_not_null(home)
	assert_true(
		home.regiments.has(String(trace[0]["regiment"])),
		"the new regiment wears France's colours in the Home Army"
	)
	play.army_layer.free()


func test_the_human_crown_is_never_mustered_for() -> void:
	var play: PlaySession = _play(12000)
	var before: int = play.army_layer.regiment_count_all(HUMAN)

	var trace: Array[Dictionary] = MapPlayArmies.run_ai(play)

	assert_eq(play.army_layer.regiment_count_all(HUMAN), before)
	for record: Dictionary in trace:
		assert_eq(int(record["faction"]), OWNER, "the crown musters its own men")
	play.army_layer.free()


func test_a_court_without_a_ledger_never_musters() -> void:
	var play: PlaySession = _play(12000, false)
	var before: int = play.army_layer.regiment_count_all(OWNER)

	var trace: Array[Dictionary] = MapPlayArmies.run_ai(play)

	assert_eq(trace.size(), 0, "no ledger, no muster")
	assert_eq(play.army_layer.regiment_count_all(OWNER), before)
	play.army_layer.free()


func test_the_observer_log_reads_the_muster() -> void:
	var play: PlaySession = _play(12000)
	var trace: Array[Dictionary] = MapPlayArmies.run_ai(play)
	var merged: Dictionary = AiTurnLog.record(play, trace, [], {})
	var record: Dictionary = merged["factions"][OWNER]
	assert_eq(int(record["actions"].get("reinforce", 0)), 1, "one regiment raised")
	var lines: Array = record["events"]
	assert_true(lines.size() > 0, "the event list names the pattern")
	play.army_layer.free()
