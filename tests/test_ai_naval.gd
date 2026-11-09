extends GdToolsTest
## Rival naval pass: squadrons engage, threaten, hold or cruise home through
## the shared NavalMovement rules (docs/ai.md). The fixture has two adjacent
## zones: zone 0 off the human coast, zone 1 off the rival's.

const NavalFixture = preload("res://tests/naval_fixture.gd")


func test_ai_navy_holds_its_own_waters_at_peace() -> void:
	var model: MapModel = NavalFixture.build()
	var fleets: Array[FleetState] = [_fleet(1, 1, 1, ["carrack"])]
	var plan: Dictionary = AiNavalPlanner.orders(
		AiConfig.build(1, 1500), _peace_state(1, 0), model, fleets
	)
	assert_eq((plan["orders"] as Array).size(), 0, "already off its own coast")


func test_ai_navy_sails_home_from_far_waters_at_peace() -> void:
	var model: MapModel = NavalFixture.build()
	var fleets: Array[FleetState] = [_fleet(1, 1, 0, ["carrack"])]
	var plan: Dictionary = AiNavalPlanner.orders(
		AiConfig.build(1, 1500), _peace_state(1, 0), model, fleets
	)
	assert_eq((plan["orders"] as Array).size(), 1)
	assert_eq(int(plan["orders"][0]["zone"]), 1, "the zone off its own coast")
	assert_eq(String(plan["orders"][0]["kind"]), AiNavalPlanner.KIND_STAGE)


func test_ai_navy_threatens_a_hostile_coast_at_war() -> void:
	var model: MapModel = NavalFixture.build()
	var fleets: Array[FleetState] = [_fleet(1, 1, 1, ["carrack"])]
	var plan: Dictionary = AiNavalPlanner.orders(
		AiConfig.build(1, 1500), _war_state(1, 0), model, fleets
	)
	assert_eq((plan["orders"] as Array).size(), 1)
	assert_eq(int(plan["orders"][0]["zone"]), 0)
	assert_eq(String(plan["orders"][0]["kind"]), AiNavalPlanner.KIND_THREATEN)


func test_ai_navy_engages_a_weaker_fleet() -> void:
	var model: MapModel = NavalFixture.build()
	var fleets: Array[FleetState] = [
		_fleet(1, 1, 1, ["carrack", "carrack"]),
		_fleet(2, 0, 0, ["fluyte"]),
	]
	var plan: Dictionary = AiNavalPlanner.orders(
		AiConfig.build(1, 1500), _war_state(1, 0), model, fleets
	)
	assert_eq((plan["orders"] as Array).size(), 1)
	assert_eq(String(plan["orders"][0]["kind"]), AiNavalPlanner.KIND_ENGAGE)
	assert_eq(int(plan["orders"][0]["zone"]), 0)


func test_ai_navy_avoids_a_stronger_fleet() -> void:
	var model: MapModel = NavalFixture.build()
	var fleets: Array[FleetState] = [
		_fleet(1, 1, 1, ["sloop"]),
		_fleet(2, 0, 0, ["carrack", "carrack", "carrack"]),
	]
	var plan: Dictionary = AiNavalPlanner.orders(
		AiConfig.build(1, 1500), _war_state(1, 0), model, fleets
	)
	assert_eq((plan["orders"] as Array).size(), 0, "one sloop never sails into three carracks")


func test_ai_navy_holds_a_zone_where_it_is_outmatched() -> void:
	var model: MapModel = NavalFixture.build()
	var fleets: Array[FleetState] = [
		_fleet(1, 1, 1, ["sloop"]),
		_fleet(2, 0, 1, ["carrack", "carrack", "carrack"]),
	]
	var plan: Dictionary = AiNavalPlanner.orders(
		AiConfig.build(1, 1500), _war_state(1, 0), model, fleets
	)
	assert_eq((plan["orders"] as Array).size(), 0, "the battle resolves at turn end")


func test_ai_navy_leaves_the_home_fleet_in_port() -> void:
	var model: MapModel = NavalFixture.build()
	model.province_data(1).capital = true
	var fleets: Array[FleetState] = [_port_fleet(1, 1, 1, ["carrack"])]
	var plan: Dictionary = AiNavalPlanner.orders(
		AiConfig.build(1, 1500), _war_state(1, 0), model, fleets
	)
	assert_eq((plan["orders"] as Array).size(), 0, "the home fleet cannot sail")


func test_ai_navy_skips_a_squadron_that_already_sailed() -> void:
	var model: MapModel = NavalFixture.build()
	var fleets: Array[FleetState] = [_fleet(1, 1, 0, ["carrack"])]
	fleets[0].moved = true
	var plan: Dictionary = AiNavalPlanner.orders(
		AiConfig.build(1, 1500), _war_state(1, 0), model, fleets
	)
	assert_eq((plan["orders"] as Array).size(), 0)


func test_ai_navy_holds_a_zone_it_already_dominates() -> void:
	var model: MapModel = NavalFixture.build()
	var fleets: Array[FleetState] = [
		_fleet(1, 1, 0, ["carrack", "carrack", "carrack"]),
		_fleet(2, 0, 0, ["fluyte"]),
	]
	var plan: Dictionary = AiNavalPlanner.orders(
		AiConfig.build(1, 1500), _war_state(1, 0), model, fleets
	)
	assert_eq((plan["orders"] as Array).size(), 0, "the battle comes to it at turn end")


func test_map_phase_moves_rival_squadrons_without_a_hud() -> void:
	var model: MapModel = NavalFixture.build()
	var world := WorldMap.new()
	world.add_region(model)
	var fleets: Array[FleetState] = [
		_fleet(1, 1, 1, ["carrack", "carrack"]),
		_fleet(2, 0, 0, ["fluyte"]),
	]
	var layer := ShipLayer.new()
	layer.model = model
	layer.world = world
	layer.regions.set_region(0, fleets)
	var play := PlaySession.new()
	play.player_faction = 0
	play.world = world
	play.model = model
	play.diplomacy = _war_state(1, 0)
	play.ship_layer = layer
	play.map_seed = 1500
	var trace: Array[Dictionary] = MapPlayFleets.run_ai(play)
	assert_eq(trace.size(), 1)
	assert_eq(int(trace[0]["fleet"]), 1)
	assert_eq(fleets[0].sea_zone, 0, "the rival squadron now holds human waters")
	assert_true(fleets[0].moved)
	layer.free()


func _fleet(
	fleet_id: int, owner: int, zone: int, types: Array[String]
) -> FleetState:
	var hulls: Array[String] = []
	var typed: Dictionary = {}
	for index in types.size():
		var hull_id: String = "h%d_%d" % [fleet_id, index]
		hulls.append(hull_id)
		typed[hull_id] = types[index]
	return FleetState.at_sea(fleet_id, owner, zone, hulls, typed)


func _port_fleet(
	fleet_id: int, owner: int, province: int, types: Array[String]
) -> FleetState:
	var fleet: FleetState = _fleet(fleet_id, owner, MapModel.NO_ID, types)
	fleet.location = FleetState.Location.IN_PORT
	fleet.province = province
	return fleet


func _peace_state(first: int, second: int) -> DiplomacyState:
	var state := DiplomacyState.new()
	state.reset(1)
	state.ensure_relation(first, second, 1)
	return state


func _war_state(attacker: int, target: int) -> DiplomacyState:
	var state := _peace_state(attacker, target)
	state.relation(attacker, target).at_war = true
	return state
