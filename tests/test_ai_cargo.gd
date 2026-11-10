extends GdToolsTest
## Rival cargo routes (wiki: economy-planner § Cargo; DR-20261110-26): idle
## merchant squadrons sail home so their holds count at the seat, and a court
## whose colonial tonnage and trade holds outrun the berths lays down one more
## hull through the same yard and movement gates the human uses.

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
			model.province[model.index_of(x, y)] = 0 if x < 4 else 1
			if x < 4:
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
	var harbour: Array[Vector2i] = [Vector2i(4, 0), Vector2i(4, 1)]
	var outport := ProvinceState.create(
		1, "Outport", harbour, Vector2(4.0, 0.5), harbour.size(), OWNER, false
	)
	outport.port_tile = Vector2i(4, 1)
	outport.coastal = true
	model.provinces = [province, outport]
	var sea: Array[Vector2i] = []
	for x in 5:
		sea.append(Vector2i(x, 2))
	model.sea_zones = [SeaZoneState.create(0, "Home Waters", sea, Vector2(2.0, 2.0), 5)]
	return model


func _config() -> AiConfig:
	return AiConfig.build(OWNER, 1500)


func _economy(treasury: int = 2500) -> PlayerEconomy:
	var economy := PlayerEconomy.starting()
	economy.treasury = treasury
	return economy


func _merchant(fleet_id: int, type_id: String = "carrack") -> FleetState:
	var hull_id: String = "hull_%d" % fleet_id
	return FleetState.at_sea(fleet_id, OWNER, 0, [hull_id], {hull_id: type_id})


func test_an_idle_merchant_squadron_is_walked_home_and_docks() -> void:
	var model: MapModel = _old_world()
	var fleet: FleetState = _merchant(1)
	var plan: Dictionary = AiCargoPlanner.plan(
		_config(), _economy(), model, [fleet], 0, 5
	)
	var routes: Array = plan["routes"]
	assert_eq(routes.size(), 1, "one idle merchant squadron is ordered home")
	assert_true(bool(routes[0]["dock"]), "the seat's harbour borders the zone")
	var moved: Dictionary = AiCargoPlanner.apply_route(model, fleet, routes[0])
	assert_true(bool(moved["ok"]))
	assert_true(fleet.is_in_port())
	assert_eq(fleet.province, 0, "it berths at the crown's seat")
	assert_eq(int(plan["holds"]), 0, "the holds did not count afloat")
	assert_eq(int(plan["projected"]), 3, "the projected berths count its cargo")


func test_a_warship_is_never_a_cargo_route() -> void:
	var model: MapModel = _old_world()
	var sloop := FleetState.at_sea(2, OWNER, 0, ["hull_2"], {"hull_2": "sloop"})
	var plan: Dictionary = AiCargoPlanner.plan(
		_config(), _economy(), model, [sloop], 0, 5
	)
	assert_true((plan["routes"] as Array).is_empty())
	assert_true((plan["launch"] as Dictionary).is_empty(), "no purse for a hull yet")


func test_a_merchant_in_another_port_puts_to_sea_toward_the_seat() -> void:
	var model: MapModel = _old_world()
	var fleet := FleetState.in_port(5, OWNER, 1, ["hull_5"], {"hull_5": "carrack"})
	var plan: Dictionary = AiCargoPlanner.plan(
		_config(), _economy(), model, [fleet], 0, 5
	)
	var routes: Array = plan["routes"]
	assert_eq(routes.size(), 1)
	assert_true(not bool(routes[0]["dock"]), "the outport is not the seat")
	assert_eq(int(routes[0]["zone"]), 0, "it puts to sea into the seat's water")


func test_hostile_water_holds_a_merchant_in_port() -> void:
	var model: MapModel = _old_world()
	var fleet := FleetState.in_port(5, OWNER, 1, ["hull_5"], {"hull_5": "carrack"})
	var plan: Dictionary = AiCargoPlanner.plan(
		_config(), _economy(), model, [fleet], 0, 5, {0: true}
	)
	assert_true((plan["routes"] as Array).is_empty(), "it waits for safer water")


func test_berths_at_the_seat_already_cover_the_need() -> void:
	var model: MapModel = _old_world()
	var fluyte := FleetState.in_port(3, OWNER, 0, ["hull_3"], {"hull_3": "fluyte"})
	var plan: Dictionary = AiCargoPlanner.plan(
		_config(), _economy(20000), model, [fluyte], 0, 4
	)
	assert_eq(int(plan["holds"]), 4, "a fluyte's four holds are home cargo")
	assert_true((plan["routes"] as Array).is_empty())
	assert_true((plan["launch"] as Dictionary).is_empty())


func test_a_shortfall_that_pays_lays_down_a_merchant_hull() -> void:
	var model: MapModel = _old_world()
	var plan: Dictionary = AiCargoPlanner.plan(
		_config(), _economy(20000), model, [], 0, 10
	)
	var launch: Dictionary = plan["launch"]
	assert_eq(String(launch.get("kind", "")), "launch")
	assert_eq(String(launch.get("type_id", "")), "carrack", "the only buildable hull")
	assert_eq(int(launch.get("cargo", 0)), 3)


func test_the_better_merchant_wins_on_cargo_then_price() -> void:
	var model: MapModel = _old_world()
	var economy: PlayerEconomy = _economy(20000)
	economy.tech_unlocked["superior_hull_design"] = true
	var plan: Dictionary = AiCargoPlanner.plan(_config(), economy, model, [], 0, 10)
	assert_eq(
		String(plan["launch"].get("type_id", "")), "fluyte",
		"four holds for less money beats three"
	)


func test_the_purse_floor_keeps_the_yard_shut() -> void:
	var model: MapModel = _old_world()
	var plan: Dictionary = AiCargoPlanner.plan(
		_config(), _economy(9000), model, [], 0, 10
	)
	assert_true((plan["launch"] as Dictionary).is_empty(), "£1,000 left is not enough")


func test_a_squadron_carrying_an_expedition_keeps_its_course() -> void:
	var model: MapModel = _old_world()
	var fleet: FleetState = _merchant(4)
	fleet.embarked_army = 7
	var plan: Dictionary = AiCargoPlanner.plan(
		_config(), _economy(), model, [fleet], 0, 5
	)
	assert_true((plan["routes"] as Array).is_empty())


func test_missing_inputs_make_the_plan_empty() -> void:
	var model: MapModel = _old_world()
	assert_true((AiCargoPlanner.plan(null, _economy(), model, [], 0, 5)["routes"] as Array).is_empty())
	assert_true((AiCargoPlanner.plan(_config(), null, model, [], 0, 5)["routes"] as Array).is_empty())
	assert_true((AiCargoPlanner.plan(_config(), _economy(), null, [], 0, 5)["routes"] as Array).is_empty())
	assert_true(not bool(AiCargoPlanner.apply_route(model, null, {})["ok"]))


# --- applied orders (MapPlayCargoAi) ----------------------------------------


func _session(model: MapModel, fleets: Array[FleetState]) -> Dictionary:
	var play := PlaySession.new()
	play.map_seed = 1
	play.player_faction = 0
	var world := WorldMap.new()
	world.add_region(model)
	play.world = world
	var ships := ShipLayer.new()
	ships.player_faction = 0
	ships.regions.set_region(model.region_id, fleets)
	play.ship_layer = ships
	return {"play": play, "ships": ships, "model": model}


func test_the_adapter_docks_a_rival_squadron_and_its_holds_count() -> void:
	var model: MapModel = _old_world()
	var fleet: FleetState = _merchant(1)
	var built: Dictionary = _session(model, [fleet])
	var play: PlaySession = built["play"]
	var economy: PlayerEconomy = _economy()
	var report: Dictionary = MapPlayCargoAi.run(
		play, OWNER, economy, {"used": 0, "left_total": 2}
	)
	assert_eq((report["routes"] as Array).size(), 1)
	assert_true(fleet.is_in_port())
	assert_eq(
		TradeCargo.capacity(play.world, play.ship_layer.regions.snapshot(), OWNER),
		3, "the docked hull's three holds now count"
	)
	(built["ships"] as Node).free()


func test_the_adapter_puts_a_merchant_to_sea_for_the_crossing() -> void:
	var model: MapModel = _old_world()
	var fleet := FleetState.in_port(5, OWNER, 1, ["hull_5"], {"hull_5": "carrack"})
	var built: Dictionary = _session(model, [fleet])
	var play: PlaySession = built["play"]
	var report: Dictionary = MapPlayCargoAi.run(
		play, OWNER, _economy(), {"used": 0, "left_total": 2}
	)
	assert_eq((report["routes"] as Array).size(), 1)
	assert_true(fleet.is_at_sea(), "the outport merchant puts to sea")
	assert_eq(fleet.sea_zone, 0)
	(built["ships"] as Node).free()


func test_the_adapter_keeps_a_merchant_out_of_hostile_water() -> void:
	var model: MapModel = _old_world()
	var fleet := FleetState.in_port(5, OWNER, 1, ["hull_5"], {"hull_5": "carrack"})
	var player := FleetState.at_sea(9, 0, 0, ["hull_9"], {"hull_9": "carrack"})
	var built: Dictionary = _session(model, [fleet, player])
	var play: PlaySession = built["play"]
	var state := DiplomacyState.new()
	state.initialize(1)
	state.ensure_relation(OWNER, 0, 1)
	assert_true(bool(DiplomacyRules.declare_war(state, OWNER, 0)["ok"]))
	play.diplomacy = state
	var report: Dictionary = MapPlayCargoAi.run(
		play, OWNER, _economy(), {"used": 0, "left_total": 2}
	)
	assert_true((report["routes"] as Array).is_empty())
	assert_true(fleet.is_in_port(), "the merchant never enters the hostile zone")
	(built["ships"] as Node).free()


func test_the_adapter_founds_a_slip_when_no_squadron_is_in_port() -> void:
	var model: MapModel = _old_world()
	var built: Dictionary = _session(model, [])
	var play: PlaySession = built["play"]
	var economy: PlayerEconomy = _economy(20000)
	var report: Dictionary = MapPlayCargoAi.run(
		play, OWNER, economy, {"used": 0, "left_total": 8}
	)
	var launch: Dictionary = report["launch"]
	assert_eq(String(launch.get("type_id", "")), "carrack")
	assert_true(bool(launch.get("founded", false)), "the yard founds the home squadron")
	var roster: Array = play.ship_layer.regions.value(model.region_id, [])
	assert_eq(roster.size(), 1)
	var fleet: FleetState = roster[0]
	assert_true(fleet.is_in_port() and fleet.province == 0)
	assert_eq(economy.treasury, 12000, "the yard took its published price")
	(built["ships"] as Node).free()
