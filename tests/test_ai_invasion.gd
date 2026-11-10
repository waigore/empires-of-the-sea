extends GdToolsTest
## Rival overseas invasions (wiki: ai-architecture § Naval policy,
## ships-and-naval § Naval transport; DR-20261110-02): detach, board, cross a
## Passage, mark a beachhead and land, one legal step a turn.

const NavalFixture = preload("res://tests/naval_fixture.gd")

const OWNER: int = 1
## A Great Power rival in the Old World and the New World tribe whose coast needs
## no declaration (wiki: factions § Tribe).
const RIVAL: int = 2
const TRIBE: int = 9
const HULLS: Array[String] = ["h1", "h2"]
const HULL_TYPES: Dictionary = {"h1": "carrack", "h2": "carrack"}


## `enemy_border` puts a hostile province on the seat's land border, so the
## court has a land war and no reason to sail.
func _old_world(enemy_border: bool = false) -> MapModel:
	var model := MapModel.new()
	model.setup(5, 3)
	model.region_id = WorldMap.OLD_WORLD
	model.region_key = "old_world"
	var tiles: Array[Vector2i] = []
	for y in 2:
		for x in 5:
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			model.province[model.index_of(x, y)] = 0 if x < 3 or not enemy_border else 1
			if x < 3 or not enemy_border:
				tiles.append(Vector2i(x, y))
	for x in 5:
		var index: int = model.index_of(x, 2)
		model.terrain[index] = MapModel.Terrain.OCEAN
		model.sea_zone[index] = 0
	var seat := ProvinceState.create(
		0, "Seat", tiles, Vector2(2.0, 0.5), tiles.size(), OWNER, true
	)
	seat.capital_tile = Vector2i(0, 0)
	seat.port_tile = Vector2i(0, 1)
	seat.coastal = true
	model.provinces = [seat]
	if enemy_border:
		var border_tiles: Array[Vector2i] = []
		for y in 2:
			for x in range(3, 5):
				border_tiles.append(Vector2i(x, y))
		var border := ProvinceState.create(
			1, "Border", border_tiles, Vector2(4.0, 0.5), border_tiles.size(), RIVAL, false
		)
		model.provinces.append(border)
	var sea: Array[Vector2i] = []
	for x in 5:
		sea.append(Vector2i(x, 2))
	model.sea_zones = [SeaZoneState.create(0, "Home Waters", sea, Vector2(2.0, 2.0), 5)]
	return model


## New World: the enemy coast (province 0) and an own colony (province 1), both
## on the same sea zone so a landing is one step from the crossing.
func _new_world(own_colony: bool = true) -> MapModel:
	var model := MapModel.new()
	model.setup(4, 3)
	model.region_id = WorldMap.NEW_WORLD
	model.region_key = "new_world"
	for y in 2:
		for x in 4:
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
	for tile: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
		model.province[model.index_of(tile.x, tile.y)] = 0
	if own_colony:
		for tile: Vector2i in [Vector2i(3, 0), Vector2i(3, 1)]:
			model.province[model.index_of(tile.x, tile.y)] = 1
	for x in 4:
		var index: int = model.index_of(x, 2)
		model.terrain[index] = MapModel.Terrain.OCEAN
		model.sea_zone[index] = 0
	var coast_tiles: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]
	var coast := ProvinceState.create(0, "Coast", coast_tiles, Vector2(0.5, 0.5), 4, TRIBE, false)
	coast.coastal = true
	model.provinces = [coast]
	if own_colony:
		var colony_tiles: Array[Vector2i] = [Vector2i(3, 0), Vector2i(3, 1)]
		var colony := ProvinceState.create(
			1, "Colony", colony_tiles, Vector2(3.0, 0.5), 3, OWNER, false
		)
		colony.coastal = true
		model.provinces.append(colony)
	var sea: Array[Vector2i] = []
	for x in 4:
		sea.append(Vector2i(x, 2))
	model.sea_zones = [SeaZoneState.create(0, "Far Shore", sea, Vector2(1.5, 2.0), 4)]
	return model


func _world(own_colony: bool = true) -> WorldMap:
	var map := WorldMap.new()
	map.add_region(_old_world())
	map.add_region(_new_world(own_colony))
	map.warp_links = [
		{"from_region": 0, "from_zone": 0, "to_region": 1, "to_zone": 0},
		{"from_region": 1, "from_zone": 0, "to_region": 0, "to_zone": 0},
	]
	return map


func _config() -> AiConfig:
	return AiConfig.build(OWNER, 1500)


func _war(target: int = RIVAL) -> DiplomacyState:
	var state := DiplomacyState.new()
	state.reset(1)
	state.ensure_relation(OWNER, target, 1)
	state.relation(OWNER, target).at_war = true
	return state


func _peace(target: int = RIVAL) -> DiplomacyState:
	var state := DiplomacyState.new()
	state.reset(1)
	state.ensure_relation(OWNER, target, 1)
	return state


func _home_army(regiments: Array[String] = ["peasant_levies", "pikemen", "squires"]) -> ArmyState:
	return ArmyState.muster(1, OWNER, 0, true, regiments, 1)


func _field_army(
	regiments: Array[String] = ["pikemen", "squires"], province: int = 0
) -> ArmyState:
	return ArmyState.muster(2, OWNER, province, false, regiments, 10)


func _squadron(id: int = 1, owner: int = OWNER, zone: int = 0) -> FleetState:
	return FleetState.at_sea(id, owner, zone, HULLS, HULL_TYPES)


func test_a_war_across_the_water_detaches_a_crossing_army() -> void:
	var world: WorldMap = _world()
	var actions: Array[Dictionary] = AiInvasionPlanner.split_orders(
		_config(), _war(), world, world.region(0), [_squadron()], [_home_army()]
	)
	assert_eq(actions.size(), 1)
	assert_eq(String(actions[0]["kind"]), AiInvasionPlanner.KIND_SPLIT)
	assert_eq(int(actions[0]["regiments"].size()), 2, "one regiment keeps the seat")


func test_a_war_on_the_court_s_own_border_stays_a_land_war() -> void:
	var world := WorldMap.new()
	world.add_region(_old_world(true))
	world.add_region(_new_world())
	world.warp_links = [
		{"from_region": 0, "from_zone": 0, "to_region": 1, "to_zone": 0},
		{"from_region": 1, "from_zone": 0, "to_region": 0, "to_zone": 0},
	]
	assert_true(AiInvasionPlanner.split_orders(
		_config(), _war(), world, world.region(0), [_squadron()], [_home_army()]
	).is_empty(), "the field army is needed on the border")


func test_only_a_declared_enemy_or_a_tribe_may_be_invaded() -> void:
	assert_true(DiplomacyRules.invadable(_peace(), OWNER, TRIBE), "tribes need no declaration")
	assert_false(DiplomacyRules.invadable(_peace(), OWNER, RIVAL), "peace holds with a crown")
	assert_true(DiplomacyRules.invadable(_war(), OWNER, RIVAL))


func test_a_tribe_coast_is_a_lawful_target_without_a_declaration() -> void:
	var world: WorldMap = _world()
	var actions: Array[Dictionary] = AiInvasionPlanner.split_orders(
		_config(), _peace(), world, world.region(0), [_squadron()], [_home_army()]
	)
	assert_eq(actions.size(), 1, "the New World is open to a crown at peace")


func test_no_detachment_without_a_shore_across_the_water() -> void:
	# A war with a crown holding no New World coast, and no tribe, is a land war.
	var home_only := WorldMap.new()
	home_only.add_region(_old_world())
	var coastless: MapModel = _new_world(false)
	coastless.provinces[0].owner = OWNER
	home_only.add_region(coastless)
	home_only.warp_links = [{"from_region": 0, "from_zone": 0, "to_region": 1, "to_zone": 0}]
	assert_true(AiInvasionPlanner.split_orders(
		_config(), _war(), home_only, home_only.region(0), [_squadron()], [_home_army()]
	).is_empty())


func test_the_landing_targets_a_tribe_coast_without_a_war() -> void:
	var world: WorldMap = _world()
	var new_world: MapModel = world.region(1)
	var fleet: FleetState = FleetState.in_port(1, OWNER, 1, HULLS, HULL_TYPES)
	var army: ArmyState = _field_army(["pikemen", "squires"], 1)
	assert_true(bool(NavalTransport.embark(new_world, army, fleet)["ok"]))
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 0
	fleet.province = MapModel.NO_ID
	var order: Dictionary = AiInvasionPlanner.plan(
		_config(), _peace(), world, 1, new_world, [fleet], [army]
	)
	assert_eq(String(order.get("kind", "")), AiInvasionPlanner.KIND_BEACHHEAD)
	assert_eq(int(order.get("province", -1)), 0)


func test_a_field_army_already_afield_is_not_split_again() -> void:
	var world: WorldMap = _world()
	assert_true(AiInvasionPlanner.split_orders(
		_config(), _war(), world, world.region(0), [_squadron()],
		[_home_army(), _field_army()]
	).is_empty())


func test_an_idle_squadron_docks_for_the_crossing_army() -> void:
	var world: WorldMap = _world()
	var order: Dictionary = AiInvasionPlanner.plan(
		_config(), _war(), world, 0, world.region(0), [_squadron()], [_home_army(), _field_army()]
	)
	assert_eq(String(order.get("kind", "")), AiInvasionPlanner.KIND_DOCK)
	assert_eq(int(order.get("province", -1)), 0)


func test_a_docked_squadron_takes_the_army_aboard() -> void:
	var world: WorldMap = _world()
	var fleet: FleetState = FleetState.in_port(1, OWNER, 0, HULLS, HULL_TYPES)
	var order: Dictionary = AiInvasionPlanner.plan(
		_config(), _war(), world, 0, world.region(0), [fleet],
		[_home_army(), _field_army()]
	)
	assert_eq(String(order.get("kind", "")), AiInvasionPlanner.KIND_EMBARK)
	assert_eq(int(order.get("army", -1)), 2)


func test_a_squadron_with_no_room_takes_no_troops() -> void:
	var world: WorldMap = _world()
	var fleet: FleetState = FleetState.in_port(1, OWNER, 0, ["h1"] as Array[String], {"h1": "sloop"})
	var order: Dictionary = AiInvasionPlanner.plan(
		_config(), _war(), world, 0, world.region(0), [fleet],
		[_home_army(), _field_army()]
	)
	assert_true(order.is_empty(), "one hull cannot carry two regiments")


func test_an_expedition_crosses_then_marks_the_enemy_coast() -> void:
	var world: WorldMap = _world()
	var old_world: MapModel = world.region(0)
	var new_world: MapModel = world.region(1)
	var fleet: FleetState = FleetState.in_port(1, OWNER, 0, HULLS, HULL_TYPES)
	var army: ArmyState = _field_army()
	assert_true(bool(NavalTransport.embark(old_world, army, fleet)["ok"]))
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 0
	fleet.province = MapModel.NO_ID
	var cross: Dictionary = AiInvasionPlanner.plan(
		_config(), _war(), world, 0, old_world, [fleet], [army]
	)
	assert_eq(String(cross.get("kind", "")), AiInvasionPlanner.KIND_CROSS)
	var mark: Dictionary = AiInvasionPlanner.plan(
		_config(), _war(), world, 1, new_world, [fleet], [army]
	)
	assert_eq(String(mark.get("kind", "")), AiInvasionPlanner.KIND_BEACHHEAD)
	assert_eq(int(mark.get("province", -1)), 0)


func test_a_ready_beachhead_lands_the_army_the_next_turn() -> void:
	var world: WorldMap = _world()
	var new_world: MapModel = world.region(1)
	var fleet: FleetState = FleetState.in_port(1, OWNER, 1, HULLS, HULL_TYPES)
	var army: ArmyState = _field_army(["pikemen", "squires"], 1)
	assert_true(bool(NavalTransport.embark(new_world, army, fleet)["ok"]))
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 0
	fleet.province = MapModel.NO_ID
	assert_true(bool(NavalTransport.establish_beachhead(
		new_world, fleet, 0, 1, Callable()
	)["ok"]))
	var waiting: Dictionary = AiInvasionPlanner.plan(
		_config(), _war(), world, 1, new_world, [fleet], [army], 1
	)
	assert_true(waiting.is_empty(), "the landing opens the turn after the marker")
	var land: Dictionary = AiInvasionPlanner.plan(
		_config(), _war(), world, 1, new_world, [fleet], [army], 2
	)
	assert_eq(String(land.get("kind", "")), AiInvasionPlanner.KIND_LAND)
	assert_eq(int(land.get("province", -1)), 0)


func test_a_coast_the_army_cannot_storm_sends_it_home() -> void:
	var world: WorldMap = _world()
	var new_world: MapModel = world.region(1)
	var fleet: FleetState = FleetState.in_port(1, OWNER, 1, HULLS, HULL_TYPES)
	var army: ArmyState = _field_army(["peasant_levies"], 1)
	assert_true(bool(NavalTransport.embark(new_world, army, fleet)["ok"]))
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 0
	fleet.province = MapModel.NO_ID
	var guards: ArmyState = ArmyState.muster(9, TRIBE, 0, false, [
		"guards", "guards", "guards",
	], 20)
	var order: Dictionary = AiInvasionPlanner.plan(
		_config(), _war(), world, 1, new_world, [fleet], [army, guards]
	)
	assert_eq(String(order.get("kind", "")), AiInvasionPlanner.KIND_LAND)
	assert_eq(int(order.get("province", -1)), 1, "the army goes ashore on its own colony")


func test_the_observer_counts_an_expedition_and_its_landing() -> void:
	var play := PlaySession.new()
	play.turn = 3
	var trace: Array[Dictionary] = [
		{"faction": OWNER, "kind": AiInvasionPlanner.KIND_SPLIT, "province": 0},
		{"faction": OWNER, "kind": AiInvasionPlanner.KIND_EMBARK},
		{"faction": OWNER, "kind": AiInvasionPlanner.KIND_CROSS},
		{"faction": OWNER, "kind": AiInvasionPlanner.KIND_LAND, "province_name": "Coast"},
	]
	var record: Dictionary = AiTurnLog.record(play, [], [], {}, trace)
	var actions: Dictionary = record["factions"][OWNER]["actions"]
	assert_eq(int(actions.get("split", 0)), 1)
	assert_eq(int(actions.get("invade", 0)), 3)
	var court: Dictionary = record["factions"][OWNER]
	assert_true(AiTurnLog.headline(court).contains("landings"))


func test_the_naval_planner_leaves_a_troop_ship_to_its_expedition() -> void:
	var model: MapModel = NavalFixture.build()
	var config: AiConfig = AiConfig.build(2, 1500)
	var state := DiplomacyState.new()
	state.reset(1)
	state.ensure_relation(2, 1, 1)
	state.relation(2, 1).at_war = true
	var troop: FleetState = FleetState.at_sea(1, 2, 0, HULLS, HULL_TYPES)
	troop.embarked_army = 7
	var plan: Dictionary = AiNavalPlanner.orders(config, state, model, [troop])
	assert_true(plan["orders"].is_empty(), "the expedition keeps its course")


func test_the_adapter_detaches_the_crossing_army_first() -> void:
	var world: WorldMap = _world()
	var old_world: MapModel = world.region(0)
	var play := PlaySession.new()
	play.player_faction = 0
	play.region_index = 0
	play.map_seed = 1500
	play.turn = 0
	play.world = world
	play.model = old_world
	play.diplomacy = _war()
	play.ship_layer = ShipLayer.new()
	play.ship_layer.model = old_world
	play.ship_layer.world = world
	play.ship_layer.regions.set_region(0, [_squadron()])
	play.ship_layer.regions.set_region(1, [])
	play.army_layer = ArmyLayer.new()
	play.army_layer.model = old_world
	play.army_layer.armies = [_home_army()]
	play.army_layer.next_army = 2
	play.army_layer.next_regiment = 10
	play.army_layer.regions.set_region(0, play.army_layer.armies)
	play.army_layer.regions.set_region(1, [])
	var trace: Array[Dictionary] = MapPlayInvasionAi.run(play)
	assert_eq(String(trace[0]["kind"]), AiInvasionPlanner.KIND_SPLIT)
	assert_eq(String(trace[1]["kind"]), AiInvasionPlanner.KIND_DOCK)
	var roster: Array = play.army_layer.regions.value(0, [])
	assert_eq(roster.size(), 2, "a field army joins the Home Army at the seat")
	assert_eq((roster[1] as ArmyState).count(), 2)
	play.ship_layer.free()
	play.army_layer.free()


func test_the_map_adapter_runs_the_whole_expedition() -> void:
	var world: WorldMap = _world()
	var old_world: MapModel = world.region(0)
	var play := PlaySession.new()
	play.player_faction = 0
	play.region_index = 0
	play.map_seed = 1500
	play.turn = 0
	play.world = world
	play.model = old_world
	play.diplomacy = _war()
	var fleet: FleetState = _squadron()
	play.ship_layer = ShipLayer.new()
	play.ship_layer.model = old_world
	play.ship_layer.world = world
	play.ship_layer.regions.set_region(0, [fleet])
	play.ship_layer.regions.set_region(1, [])
	var army: ArmyState = _field_army()
	play.army_layer = ArmyLayer.new()
	play.army_layer.model = old_world
	play.army_layer.armies = [army]
	play.army_layer.next_army = 3
	play.army_layer.next_regiment = 30
	play.army_layer.regions.set_region(0, play.army_layer.armies)
	play.army_layer.regions.set_region(1, [])
	assert_eq(String(MapPlayInvasionAi.run(play)[0]["kind"]), AiInvasionPlanner.KIND_DOCK)
	fleet.moved = false
	assert_eq(String(MapPlayInvasionAi.run(play)[0]["kind"]), AiInvasionPlanner.KIND_EMBARK)
	assert_true(army.is_embarked())
	fleet.moved = false
	assert_eq(String(MapPlayInvasionAi.run(play)[0]["kind"]), AiInvasionPlanner.KIND_SAIL)
	fleet.moved = false
	assert_eq(String(MapPlayInvasionAi.run(play)[0]["kind"]), AiInvasionPlanner.KIND_CROSS)
	assert_true(play.ship_layer.regions.value(0, []).is_empty(), "the squadron left the Old World")
	assert_eq(play.ship_layer.regions.value(1, []).size(), 1)
	assert_eq(play.army_layer.regions.value(1, []).size(), 1, "the army crossed with it")
	fleet.moved = false
	assert_eq(String(MapPlayInvasionAi.run(play)[0]["kind"]), AiInvasionPlanner.KIND_BEACHHEAD)
	assert_eq(fleet.beachhead_province, 0)
	play.turn = 1
	fleet.moved = false
	assert_eq(String(MapPlayInvasionAi.run(play)[0]["kind"]), AiInvasionPlanner.KIND_LAND)
	assert_eq(army.province, 0)
	assert_eq(fleet.embarked_army, -1)
	play.ship_layer.free()
	play.army_layer.free()


## A court does not sail an army at a shore it has never charted: the New World
## starts unknown, so the crossing waits for a sighting (wiki: fog-and-exploration;
## DR-20261110-21).
func test_an_uncharted_coast_is_not_worth_a_crossing() -> void:
	var world: WorldMap = _world()
	var charts := CourtCharts.new()
	charts.setup(world, 0, {})
	assert_true(AiInvasionPlanner.split_orders(
		_config(), _war(), world, world.region(0), [_squadron()], [_home_army()], charts
	).is_empty(), "no hostile coast is charted across the water")
	charts.reveal_sea_zone(OWNER, 1, 0)
	assert_eq(AiInvasionPlanner.split_orders(
		_config(), _war(), world, world.region(0), [_squadron()], [_home_army()], charts
	).size(), 1, "the charted coast is a war worth a fleet")


func test_a_charted_coast_is_the_only_landing_target() -> void:
	var world: WorldMap = _world()
	var new_world: MapModel = world.region(1)
	var charts := CourtCharts.new()
	charts.setup(world, 0, {})
	var fleet: FleetState = FleetState.in_port(1, OWNER, 1, HULLS, HULL_TYPES)
	var army: ArmyState = _field_army(["pikemen", "squires"], 1)
	assert_true(bool(NavalTransport.embark(new_world, army, fleet)["ok"]))
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = 0
	fleet.province = MapModel.NO_ID
	var blind: Dictionary = AiInvasionPlanner.plan(
		_config(), _peace(), world, 1, new_world, [fleet], [army], 0, charts
	)
	assert_true(
		String(blind.get("kind", "")) != AiInvasionPlanner.KIND_BEACHHEAD,
		"an uncharted beach is no target"
	)
	charts.reveal_sea_zone(OWNER, 1, 0)
	var ready: Dictionary = AiInvasionPlanner.plan(
		_config(), _peace(), world, 1, new_world, [fleet], [army], 0, charts
	)
	assert_eq(String(ready.get("kind", "")), AiInvasionPlanner.KIND_BEACHHEAD)
	assert_eq(int(ready.get("province", -1)), 0)
