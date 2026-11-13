extends GdToolsTest
## One boot for the rival campaign plans: invasion, colonisation, court offers and
## the planner that orders them (docs/ai.md).

## Merged from test_ai_invasion, test_ai_colonisation, test_ai_diplomacy_offers,
## test_ai_planner.
## One Godot boot (coverage instrumentation) per theme instead of one per file.
## Each test runs only its own suite's setup; teardown follows the setup.
const NavalFixture = preload("res://tests/naval_fixture.gd")
const CivilianFixture = preload("res://tests/civilian_fixture.gd")
const ai_diplomacy_offers_AiFixture = preload("res://tests/ai_fixture.gd")
const ai_planner_AiFixture = preload("res://tests/ai_fixture.gd")

const OWNER: int = 1
const RIVAL: int = 2
const TRIBE: int = 9
const HULLS: Array[String] = ["h1", "h2"]
const HULL_TYPES: Dictionary = {"h1": "carrack", "h2": "carrack"}
const ai_colonisation_OWNER: int = 1

var ai_diplomacy_offers_state: DiplomacyState
var ai_diplomacy_offers_config: AiConfig
var ai_diplomacy_offers_ai_state: AiState
var ai_planner_state: DiplomacyState
var ai_planner_config: AiConfig
var ai_planner_ai_state: AiState

var _suite_setup: String = ""

func _setup_ai_diplomacy_offers() -> void:
	_suite_setup = "ai_diplomacy_offers"
	ai_diplomacy_offers_state = DiplomacyState.new()
	ai_diplomacy_offers_state.reset(1)
	ai_diplomacy_offers_state.human_faction = 0
	ai_diplomacy_offers_config = AiConfig.build(2, 1500, AiProfile.NORMAL, AiAgenda.TECH_THIEF)
	ai_diplomacy_offers_config.personality = AiPersonality.NEUTRAL
	ai_diplomacy_offers_config.agenda_traits = AiAgenda.NEUTRAL
	ai_diplomacy_offers_ai_state = AiState.new()

func _setup_ai_planner() -> void:
	_suite_setup = "ai_planner"
	ai_planner_state = DiplomacyState.new()
	ai_planner_state.reset(1)
	ai_planner_config = AiConfig.build(FactionCatalog.PLAYER_FACTION, 1500, AiProfile.NORMAL, AiAgenda.TECH_THIEF)
	ai_planner_ai_state = AiState.new()

# --- test_ai_invasion ---

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
	var world: WorldMap = _border_world()
	assert_true(AiInvasionPlanner.split_orders(
		_config(), _war(), world, world.region(0), [_squadron()], [_home_army()]
	).is_empty(), "the field army is needed on the border")

## The Passage map with a hostile province on the seat's land border.
func _border_world() -> WorldMap:
	var world := WorldMap.new()
	world.add_region(_old_world(true))
	world.add_region(_new_world())
	world.warp_links = [
		{"from_region": 0, "from_zone": 0, "to_region": 1, "to_zone": 0},
		{"from_region": 1, "from_zone": 0, "to_region": 0, "to_zone": 0},
	]
	return world

## The money goal lifts the frontier guard: a court on **earn** sends its spare
## regiments across the Passage even while a war sits on its border, because the
## gold that ends the impasse is overseas (DR-20261113-19).
func test_an_earning_court_sails_into_a_border_war() -> void:
	var world: WorldMap = _border_world()
	var armies: Array = [_home_army()]
	assert_true(AiInvasionPlanner.split_orders(
		_config(), _war(), world, world.region(0), [_squadron()], armies
	).is_empty(), "the published rule keeps the army home")
	var earning: Array[Dictionary] = AiInvasionPlanner.split_orders(
		_config(), _war(), world, world.region(0), [_squadron()], armies, null, true
	)
	assert_eq(earning.size(), 1, "a court on earn sails for the far coast")
	assert_eq(
		int(earning[0]["regiments"].size()), 2,
		"one regiment always keeps the seat"
	)

## The defence guard survives the goal: a hostile host already standing on the
## court's own soil is never left behind (DR-20261113-19).
func test_a_hostile_host_on_the_court_s_soil_keeps_the_army_home() -> void:
	var world: WorldMap = _border_world()
	var invader: ArmyState = ArmyState.muster(9, RIVAL, 0, false, ["pikemen"], 5)
	assert_true(AiInvasionPlanner.split_orders(
		_config(), _war(), world, world.region(0), [_squadron()],
		[_home_army(), invader], null, true
	).is_empty(), "a war on its own soil comes before a voyage")

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

# --- test_ai_colonisation ---

func _ai_colonisation_old_world() -> MapModel:
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
		0, "Seat", tiles, Vector2(2.0, 0.5), tiles.size(), ai_colonisation_OWNER, true
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

func _ai_colonisation_new_world() -> MapModel:
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

func _ai_colonisation_world() -> WorldMap:
	var map := WorldMap.new()
	map.add_region(_ai_colonisation_old_world())
	map.add_region(_ai_colonisation_new_world())
	map.warp_links = [
		{"from_region": 0, "from_zone": 0, "to_region": 1, "to_zone": 0},
		{"from_region": 1, "from_zone": 0, "to_region": 0, "to_zone": 0},
	]
	return map

func _ai_colonisation_config() -> AiConfig:
	return AiConfig.build(ai_colonisation_OWNER, 1500)

func test_an_idle_explorer_boards_a_squadron_in_port() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var fleet: FleetState = FleetState.in_port(1, ai_colonisation_OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
	var order: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 0, old_world, [fleet], [unit], {}
	)
	assert_eq(String(order.get("kind", "")), "embark")
	assert_eq(int(order.get("unit", -1)), 1)

func test_a_passenger_sails_crosses_and_lands() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var new_world: MapModel = world.region(1)
	var fleet: FleetState = FleetState.in_port(1, ai_colonisation_OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
	assert_true(bool(CivilianVoyage.embark(old_world, unit, fleet)["ok"]))
	var sail: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 0, old_world, [fleet], [unit], {}
	)
	assert_eq(String(sail.get("kind", "")), "sail")
	assert_eq(int(sail.get("zone", -1)), 0)
	assert_true(
		bool(FleetSortie.apply(old_world, fleet, 0)["ok"]),
		"a squadron in port at its own capital sorties"
	)
	fleet.moved = false
	var cross: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 0, old_world, [fleet], [unit], {}
	)
	assert_eq(String(cross.get("kind", "")), "cross")
	var crossed: Dictionary = WarpTravel.apply_crossing(world, 0, fleet)
	assert_true(bool(crossed["ok"]))
	fleet.moved = false
	var land: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 1, new_world, [fleet], [unit], {}
	)
	assert_eq(String(land.get("kind", "")), "land")
	assert_eq(Vector2i(land.get("tile", Vector2i(-1, -1))), Vector2i(0, 1))

func test_no_second_expedition_when_a_colonist_is_already_abroad() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var fleet: FleetState = FleetState.in_port(1, ai_colonisation_OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
	var order: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 0, old_world, [fleet], [unit], {"explorer": 1}
	)
	assert_true(order.is_empty())

func test_the_map_adapter_embarks_and_sails_the_rival() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var fleet: FleetState = FleetState.in_port(1, ai_colonisation_OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
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
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var fleet: FleetState = FleetState.at_sea(1, ai_colonisation_OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
	var order: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 0, old_world, [fleet], [unit], {}
	)
	assert_eq(String(order.get("kind", "")), "dock")
	assert_eq(int(order.get("province", -1)), 0)

func test_a_builder_boards_when_the_crown_owns_overseas_land() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var new_world: MapModel = world.region(1)
	var tiles: Array[Vector2i] = []
	for y in 2:
		for x in 4:
			tiles.append(Vector2i(x, y))
	var colony := ProvinceState.create(0, "Colony", tiles, Vector2(1.5, 0.5), 8, ai_colonisation_OWNER, false)
	colony.town_tile = Vector2i(0, 0)
	new_world.provinces = [colony]
	var fleet: FleetState = FleetState.in_port(1, ai_colonisation_OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "builder", Vector2i(0, 0))
	var order: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 0, old_world, [fleet], [unit], {}
	)
	assert_eq(String(order.get("kind", "")), "embark")
	assert_eq(int(order.get("unit", -1)), 1)

func test_a_docked_passenger_lands_without_sailing_first() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var new_world: MapModel = world.region(1)
	var tiles: Array[Vector2i] = []
	for y in 2:
		for x in 4:
			var tile := Vector2i(x, y)
			tiles.append(tile)
			new_world.province[new_world.index_of(x, y)] = 0
	var colony := ProvinceState.create(0, "Colony", tiles, Vector2(1.5, 0.5), 8, ai_colonisation_OWNER, false)
	colony.port_tile = Vector2i(0, 1)
	colony.coastal = true
	new_world.provinces = [colony]
	var fleet: FleetState = FleetState.in_port(1, ai_colonisation_OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "builder", Vector2i(0, 0))
	assert_true(bool(CivilianVoyage.embark(new_world, unit, fleet)["ok"]))
	var order: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 1, new_world, [fleet], [unit], {}
	)
	assert_eq(String(order.get("kind", "")), "land")

func test_the_map_adapter_crosses_and_lands() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var fleet: FleetState = FleetState.in_port(1, ai_colonisation_OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
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
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	assert_true(AiColonisationPlanner.plan(null, world, 0, old_world, [], []).is_empty())
	assert_true(AiColonisationPlanner.plan(_ai_colonisation_config(), null, 0, old_world, [], []).is_empty())
	assert_true(AiColonisationPlanner.plan(_ai_colonisation_config(), world, 0, null, [], []).is_empty())
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
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var fleet: FleetState = FleetState.in_port(1, ai_colonisation_OWNER, 0)
	fleet.add_civilian(77)
	assert_true(
		AiColonisationPlanner.plan(_ai_colonisation_config(), world, 0, old_world, [fleet], []).is_empty()
	)

func test_a_working_builder_falls_back_to_an_idle_explorer() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var new_world: MapModel = world.region(1)
	var tiles: Array[Vector2i] = []
	for y in 2:
		for x in 4:
			tiles.append(Vector2i(x, y))
	var colony := ProvinceState.create(0, "Colony", tiles, Vector2(1.5, 0.5), 8, ai_colonisation_OWNER, false)
	new_world.provinces = [colony]
	var builder: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "builder", Vector2i(0, 0))
	builder.start_work("build_improvement", Vector2i(0, 0), 2)
	var explorer: CivilianState = CivilianState.create(2, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
	var fleet: FleetState = FleetState.in_port(1, ai_colonisation_OWNER, 0)
	var order: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 0, old_world, [fleet], [builder, explorer], {}
	)
	assert_eq(String(order.get("kind", "")), "embark")
	assert_eq(int(order.get("unit", -1)), 2)

func test_the_lowest_idle_squadron_is_chosen() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var unit: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
	var moved: FleetState = FleetState.at_sea(1, ai_colonisation_OWNER, 0)
	moved.moved = true
	var troop_carrier: FleetState = FleetState.at_sea(2, ai_colonisation_OWNER, 0)
	troop_carrier.embarked_army = 9
	var ready: FleetState = FleetState.at_sea(3, ai_colonisation_OWNER, 0)
	var order: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 0, old_world, [moved, troop_carrier, ready], [unit], {}
	)
	assert_eq(String(order.get("kind", "")), "dock")
	assert_eq(int(order.get("fleet", -1)), 3)

func test_a_moved_carrying_fleet_does_not_sail_twice() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var first: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
	var second: CivilianState = CivilianState.create(2, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
	var moved: FleetState = FleetState.in_port(1, ai_colonisation_OWNER, 0)
	moved.add_civilian(1)
	moved.moved = true
	var ready: FleetState = FleetState.in_port(2, ai_colonisation_OWNER, 0)
	ready.add_civilian(2)
	var order: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 0, old_world, [moved, ready], [first, second], {}
	)
	assert_eq(String(order.get("kind", "")), "sail")
	assert_eq(int(order.get("fleet", -1)), 2)

func test_board_refusals_without_a_reachable_port() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var unit: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
	var elsewhere: FleetState = FleetState.in_port(1, ai_colonisation_OWNER, 1)
	assert_true(
		AiColonisationPlanner.plan(
			_ai_colonisation_config(), world, 0, old_world, [elsewhere], [unit], {}
		).is_empty(),
		"a squadron in another port cannot take this colonist"
	)
	var stray: CivilianState = CivilianState.create(9, ai_colonisation_OWNER, "explorer", Vector2i(9, 9))
	var order: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 0, old_world, [FleetState.at_sea(1, ai_colonisation_OWNER, 0)], [stray], {}
	)
	assert_eq(
		String(order.get("kind", "")), "dock",
		"the squadron musters at the crown's harbour, not on the colonist's tile"
	)
	assert_eq(int(order.get("province", -1)), 0)

## A court with no harbour of its own cannot start an expedition, however many
## colonists and hulls it has (wiki: ships-and-naval § Home Fleet).
func test_no_owned_harbour_means_no_voyage() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	old_world.provinces[0].port_tile = Vector2i(-1, -1)
	var unit: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
	assert_eq(AiColonisationPlanner.harbour(old_world, ai_colonisation_OWNER), MapModel.NO_ID)
	assert_true(
		AiColonisationPlanner.plan(
			_ai_colonisation_config(), world, 0, old_world, [FleetState.at_sea(1, ai_colonisation_OWNER, 0)], [unit], {}
		).is_empty(),
		"a crown with no port has nowhere to take a colonist aboard"
	)

## The court's seat, when it has a port, is the muster harbour even if another
## owned province has a lower id.
func test_the_seat_is_the_muster_harbour() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var seat: ProvinceState = old_world.provinces[0]
	seat.capital = false
	var coast: ProvinceState = ProvinceState.create(
		0, "Anchorage", seat.tiles.duplicate(), Vector2(2.0, 0.5), 10, ai_colonisation_OWNER, true
	)
	coast.port_tile = Vector2i(1, 0)
	old_world.provinces = [coast, seat]
	assert_eq(
		AiColonisationPlanner.harbour(old_world, ai_colonisation_OWNER), 0,
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
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var play := PlaySession.new()
	play.player_faction = 0
	play.region_index = 0
	play.world = world
	play.model = old_world
	play.ship_layer = ShipLayer.new()
	play.ship_layer.model = old_world
	play.ship_layer.regions.set_region(0, [FleetState.at_sea(1, ai_colonisation_OWNER, 0)])
	play.ship_layer.regions.set_region(1, [])
	play.civilian_layer = CivilianLayer.new()
	play.civilian_layer.model = old_world
	play.civilian_layer.units = []
	play.civilian_layer.regions.set_region(0, [])
	play.civilian_layer.regions.set_region(1, [])
	assert_eq(
		MapPlayCivilianAi._muster_port(play, ai_colonisation_OWNER, 0, old_world), Vector2i(0, 1),
		"a court with a free squadron musters at its seat's port"
	)
	var abroad: CivilianState = CivilianState.create(7, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
	play.civilian_layer.regions.set_region(1, [abroad])
	assert_eq(
		MapPlayCivilianAi._muster_port(play, ai_colonisation_OWNER, 0, old_world), CivilianState.NO_TILE,
		"a court with a colonist already abroad sends no second expedition"
	)
	play.civilian_layer.regions.set_region(1, [])
	play.ship_layer.regions.set_region(0, [])
	assert_eq(
		MapPlayCivilianAi._muster_port(play, ai_colonisation_OWNER, 0, old_world), CivilianState.NO_TILE,
		"no squadron, no muster"
	)
	play.ship_layer.free()
	play.civilian_layer.free()

func test_region_helpers_pick_the_opposite_map() -> void:
	var world: WorldMap = _ai_colonisation_world()
	assert_eq(AiColonisationPlanner._target_region(world, WorldMap.OLD_WORLD, ai_colonisation_OWNER), WorldMap.NEW_WORLD)
	assert_eq(AiColonisationPlanner._target_region(world, WorldMap.NEW_WORLD, ai_colonisation_OWNER), WorldMap.OLD_WORLD)
	assert_false(AiColonisationPlanner._owns_land_in(world, 9, ai_colonisation_OWNER))

func test_no_passage_keeps_a_carrying_squadron_home() -> void:
	var world: WorldMap = _ai_colonisation_world()
	world.warp_links = []
	var old_world: MapModel = world.region(0)
	var fleet: FleetState = FleetState.in_port(1, ai_colonisation_OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
	assert_true(bool(CivilianVoyage.embark(old_world, unit, fleet)["ok"]))
	assert_true(
		AiColonisationPlanner.plan(
			_ai_colonisation_config(), world, 0, old_world, [fleet], [unit], {}
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
	world.add_region(_ai_colonisation_old_world())
	world.add_region(model)
	var fleet: FleetState = FleetState.at_sea(1, ai_colonisation_OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
	unit.embark_on(fleet.id)
	fleet.add_civilian(unit.id)
	var order: Dictionary = AiColonisationPlanner.plan(
		_ai_colonisation_config(), world, 1, model, [fleet], [unit], {}
	)
	assert_eq(String(order.get("kind", "")), "sail")
	assert_eq(int(order.get("zone", -1)), 1)
	assert_eq(AiSeaRoute.step_toward(model, 0, [0]), -1)
	assert_eq(AiColonisationPlanner._carried_id(FleetState.in_port(9, ai_colonisation_OWNER, 0)), -1)

## A court lands only on a coast it has charted (wiki: fog-and-exploration;
## DR-20261110-21).
func test_an_uncharted_coast_is_not_a_landing_ground() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var new_world: MapModel = world.region(1)
	var charts := CourtCharts.new()
	charts.setup(world, 0, {})
	assert_true(
		AiColonisationPlanner._landing_zones(new_world, "explorer", ai_colonisation_OWNER, charts).is_empty(),
		"the New World water is unknown"
	)
	charts.reveal_sea_zone(ai_colonisation_OWNER, 1, 0)
	var zones: Array[int] = AiColonisationPlanner._landing_zones(
		new_world, "explorer", ai_colonisation_OWNER, charts
	)
	var expected: Array[int] = [0]
	assert_eq(zones, expected, "the charted coast opens the landing")
	assert_true(
		AiColonisationPlanner._landing_zones(new_world, "explorer", ai_colonisation_OWNER).size() == 1,
		"without a chart the fixture reading keeps every coast"
	)

## The map adapter charts the water a rival enters, so a crossing opens the far
## coast for that court alone — the player's fog stays untouched.
func test_the_adapter_charts_the_coast_its_squadron_crosses_to() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var fleet: FleetState = FleetState.in_port(1, ai_colonisation_OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
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
	assert_false(play.court_charts.knows_zone(ai_colonisation_OWNER, 1, 0), "the far water is unknown")
	assert_eq(String(MapPlayColonisationAi.run(play)[0]["kind"]), "embark")
	fleet.moved = false
	assert_eq(String(MapPlayColonisationAi.run(play)[0]["kind"]), "sail")
	fleet.moved = false
	assert_eq(String(MapPlayColonisationAi.run(play)[0]["kind"]), "cross")
	assert_true(
		play.court_charts.knows_zone(ai_colonisation_OWNER, 1, 0),
		"the entered zone is charted for the rival"
	)
	fleet.moved = false
	var landed: Array[Dictionary] = MapPlayColonisationAi.run(play)
	assert_eq(String(landed[0]["kind"]), "land", "the charted coast takes the colonist")
	assert_true(play.court_charts.regions_of(0).is_empty(), "the player charts nothing")
	play.ship_layer.free()
	play.civilian_layer.free()

func test_the_adapter_docks_and_refuses_illegal_orders() -> void:
	var world: WorldMap = _ai_colonisation_world()
	var old_world: MapModel = world.region(0)
	var fleet: FleetState = FleetState.at_sea(1, ai_colonisation_OWNER, 0)
	var unit: CivilianState = CivilianState.create(1, ai_colonisation_OWNER, "explorer", Vector2i(0, 0))
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

# --- test_ai_diplomacy_offers ---

func test_every_court_menu_order_has_a_rival_policy() -> void:
	_setup_ai_diplomacy_offers()
	var menu: Array[String] = [
		DiplomacyOrders.KIND_WAR,
		DiplomacyOrders.KIND_PEACE,
		DiplomacyOrders.KIND_ALLIANCE,
		DiplomacyOrders.KIND_BREAK,
		DiplomacyOrders.KIND_OVERTURE,
		DiplomacyOrders.KIND_AID,
		DiplomacyOrders.KIND_SUBSIDY,
		DiplomacyOrders.KIND_CANCEL_SUBSIDY,
		DiplomacyOrders.KIND_FTP,
		DiplomacyOrders.KIND_REVOKE_FTP,
		DiplomacyOrders.KIND_BOYCOTT,
		DiplomacyOrders.KIND_REVOKE_BOYCOTT,
	]
	var planned: Array[String] = AiDiplomacyPlanner.kinds()
	assert_eq(planned.size(), menu.size(), "no order kind is left out of the rival menu")
	for kind: String in menu:
		assert_true(planned.has(kind), "%s has a rival policy" % kind)

func test_a_warm_rival_signs_a_trade_pact_with_a_fellow_court() -> void:
	_setup_ai_diplomacy_offers()
	# Turn one takes the free Non-Aggression Pact; Join Empire stays closed to a
	# Great Power still holding four provinces, so the next turn spends its one
	# order on the favoured trading pact (wiki: world-market § FTP).
	ai_diplomacy_offers_state.ensure_relation(2, 3, 1)
	ai_diplomacy_offers_state.relation(2, 3).score = 70.0
	_stage(2, 3, DiplomacyCatalog.STAGE_EMBASSY)
	var world: Array[int] = [0, 2, 3, 3, 3, 3]
	var first: Dictionary = _run(world, [[2, 3, 70.0]], 1)
	assert_eq(String(_action(first, 2)["kind"]), AiDiplomacyPlanner.KIND_OVERTURE)
	assert_eq(String(_action(first, 2)["stage"]), DiplomacyCatalog.STAGE_NAP)
	assert_eq(ai_diplomacy_offers_state.overture(2, 3), DiplomacyCatalog.STAGE_NAP, "a fellow court answers")
	# The warmer court, acting later in the same pass, spends its one order on
	# the trade pact the treaty just unlocked.
	assert_eq(String(_action(first, 3)["kind"]), AiDiplomacyOffers.KIND_FTP)
	assert_true(DiplomacyTrade.is_ftp(ai_diplomacy_offers_state, 2, 3), "the pact is signed at once")
	assert_true(String(_record(first, 3)["message"]).contains("favoured trading pact"))

func test_a_warm_rival_sends_aid_and_pays_from_its_own_purse() -> void:
	_setup_ai_diplomacy_offers()
	ai_diplomacy_offers_state.ensure_relation(2, 3, 1)
	ai_diplomacy_offers_state.relation(2, 3).score = 60.0
	_stage(2, 3, DiplomacyCatalog.STAGE_NAP)
	ai_diplomacy_offers_ai_state.note_war(2, 3, 1)
	var result: Dictionary = _run([0, 2, 3, 3, 3, 3], [], 1)
	var action: Dictionary = _action(result, 2)
	assert_eq(String(action["kind"]), AiDiplomacyOffers.KIND_AID)
	assert_eq(int(action["amount"]), DiplomacyCatalog.GRANT_AID_STEP)
	assert_eq(int(action["target"]), 3)
	assert_true(ai_diplomacy_offers_state.relation(2, 3).score > 60.0, "the court remembers the gift")
	assert_true(_event("grantAid"), "the shared aid rules made the transfer")

func test_aid_stops_when_the_purse_cannot_cover_it() -> void:
	_setup_ai_diplomacy_offers()
	ai_diplomacy_offers_state.ensure_relation(2, 3, 1)
	ai_diplomacy_offers_state.relation(2, 3).score = 60.0
	_stage(2, 3, DiplomacyCatalog.STAGE_NAP)
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		ai_diplomacy_offers_config, ai_diplomacy_offers_state, ai_diplomacy_offers_ai_state, ai_diplomacy_offers_AiFixture.world([0, 2, 3, 3, 3, 3]), 1,
		_context({2: 10, 3: 40})
	)
	assert_true((plan["action"] as Dictionary).is_empty())
	assert_eq(_offer_blocked(plan, AiDiplomacyOffers.KIND_AID), "The treasury cannot cover that aid.")

func test_a_rival_subsidises_a_minor_it_wants_close() -> void:
	_setup_ai_diplomacy_offers()
	ai_diplomacy_offers_state.ensure_relation(2, 6, 1)
	ai_diplomacy_offers_state.relation(2, 6).score = 70.0
	_stage(2, 6, DiplomacyCatalog.STAGE_NAP)
	var result: Dictionary = _run([0, 0, 0, 2, 6], [], 1)
	var action: Dictionary = _action(result, 2)
	assert_eq(String(action["kind"]), AiDiplomacyOffers.KIND_SUBSIDY)
	assert_eq(int(ai_diplomacy_offers_state.subsidy(2, 6)), int(action["amount"]))
	assert_eq(int(ai_diplomacy_offers_state.subsidy(2, 6)), DiplomacyCatalog.SUBSIDY_MIN)

func test_a_rival_ends_a_subsidy_once_the_friendship_cools() -> void:
	_setup_ai_diplomacy_offers()
	ai_diplomacy_offers_state.ensure_relation(2, 6, 1)
	ai_diplomacy_offers_state.relation(2, 6).score = 40.0
	_stage(2, 6, DiplomacyCatalog.STAGE_NAP)
	ai_diplomacy_offers_state.set_subsidy(2, 6, 10)
	ai_diplomacy_offers_ai_state.note_war(2, 6, 1)
	var result: Dictionary = _run([0, 0, 0, 2, 6], [], 2, {2: 3})
	assert_eq(String(_action(result, 2)["kind"]), AiDiplomacyOffers.KIND_CANCEL_SUBSIDY)
	assert_eq(ai_diplomacy_offers_state.subsidy(2, 6), 0, "the shared rules end the subsidy")

func test_a_rival_too_weak_to_fight_boycotts_a_rival_it_has_fallen_out_with() -> void:
	_setup_ai_diplomacy_offers()
	ai_diplomacy_offers_state.ensure_relation(2, 3, 1)
	ai_diplomacy_offers_state.relation(2, 3).score = 30.0
	ai_diplomacy_offers_state.set_colony(9, 2)
	_stage(2, 3, DiplomacyCatalog.STAGE_NAP)
	ai_diplomacy_offers_ai_state.economy_for(2).treasury = 0
	ai_diplomacy_offers_ai_state.note_war(2, 3, 1)
	var result: Dictionary = _run([0, 2, 3, 3, 3, 3], [], 1)
	assert_eq(String(_action(result, 2)["kind"]), AiDiplomacyOffers.KIND_BOYCOTT)
	assert_true(DiplomacyTrade.is_boycotting(ai_diplomacy_offers_state, 2, 3), "the colonies close at once")
	assert_true(String(_record(result, 2)["message"]).contains("closes its colonies"))

func test_a_recovered_standing_lifts_the_boycott() -> void:
	_setup_ai_diplomacy_offers()
	ai_diplomacy_offers_state.ensure_relation(2, 3, 1)
	ai_diplomacy_offers_state.relation(2, 3).score = 65.0
	ai_diplomacy_offers_state.set_colony(9, 2)
	ai_diplomacy_offers_state.boycotts["2>3"] = 1
	ai_diplomacy_offers_state.ftps[ai_diplomacy_offers_state.pair_key(2, 3)] = 1
	_stage(2, 3, DiplomacyCatalog.STAGE_NAP)
	ai_diplomacy_offers_ai_state.economy_for(2).treasury = 0
	ai_diplomacy_offers_ai_state.note_war(2, 3, 1)
	var result: Dictionary = _run([0, 2, 3, 3, 3, 3], [], 1)
	assert_eq(String(_action(result, 2)["kind"]), AiDiplomacyOffers.KIND_REVOKE_BOYCOTT)
	assert_false(DiplomacyTrade.is_boycotting(ai_diplomacy_offers_state, 2, 3))

func test_a_pact_that_no_longer_matches_the_standing_is_revoked() -> void:
	_setup_ai_diplomacy_offers()
	ai_diplomacy_offers_state.ensure_relation(2, 3, 1)
	ai_diplomacy_offers_state.relation(2, 3).score = 30.0
	ai_diplomacy_offers_state.ftps[ai_diplomacy_offers_state.pair_key(2, 3)] = 1
	_stage(2, 3, DiplomacyCatalog.STAGE_NAP)
	ai_diplomacy_offers_ai_state.economy_for(2).treasury = 0
	ai_diplomacy_offers_ai_state.note_war(2, 3, 1)
	var result: Dictionary = _run([0, 2, 3, 3, 3, 3], [], 2)
	assert_eq(String(_action(result, 2)["kind"]), AiDiplomacyOffers.KIND_REVOKE_FTP)
	assert_false(DiplomacyTrade.is_ftp(ai_diplomacy_offers_state, 2, 3))

func test_an_alliance_the_court_no_longer_means_is_broken() -> void:
	_setup_ai_diplomacy_offers()
	ai_diplomacy_offers_state.ensure_relation(2, 3, 1)
	ai_diplomacy_offers_state.relation(2, 3).score = 60.0
	ai_diplomacy_offers_state.relation(2, 3).formal_alliance = true
	ai_diplomacy_offers_ai_state.note_war(2, 3, 1)
	var result: Dictionary = _run([0, 2, 2, 2, 2, 3], [], 1)
	assert_eq(String(_action(result, 2)["kind"]), AiDiplomacyOffers.KIND_BREAK)
	assert_false(ai_diplomacy_offers_state.relation(2, 3).formal_alliance, "the treaty is dissolved")
	assert_true(String(_record(result, 2)["message"]).contains("breaks its alliance"))

func test_a_trade_pact_offer_to_the_human_court_waits_for_the_answer() -> void:
	_setup_ai_diplomacy_offers()
	ai_diplomacy_offers_state.ensure_relation(0, 2, 1)
	ai_diplomacy_offers_state.relation(0, 2).score = 70.0
	_stage(0, 2, DiplomacyCatalog.STAGE_NAP)
	var result: Dictionary = _run([0, 0, 0, 0, 2, 3], [], 1)
	assert_eq(String(_action(result, 2)["kind"]), AiDiplomacyOffers.KIND_FTP)
	assert_true(bool(_action(result, 2)["propose"]), "the human keeps consent")
	assert_false(DiplomacyTrade.is_ftp(ai_diplomacy_offers_state, 0, 2), "nothing is signed yet")
	assert_eq(ai_diplomacy_offers_state.pending_offers.size(), 1)
	assert_eq(String(ai_diplomacy_offers_state.pending_offers[0]["kind"]), DiplomacyProposals.KIND_FTP)
	assert_true(String(_record(result, 2)["message"]).contains("favoured trading pact"))
	var answer: Dictionary = DiplomacyProposals.resolve_human(ai_diplomacy_offers_state, null, true)
	assert_true(bool(answer.get("accepted", false)), answer.get("reason", ""))
	assert_true(DiplomacyTrade.is_ftp(ai_diplomacy_offers_state, 0, 2), "the court's answer signs the pact")

func test_one_sided_acts_and_consent_offers_are_told_apart() -> void:
	_setup_ai_diplomacy_offers()
	# A new order kind must reach the rival courts the turn it reaches the panel:
	# either through the court queue or as a one-sided act.
	var one_sided: Array[String] = [
		DiplomacyOrders.KIND_AID,
		DiplomacyOrders.KIND_BOYCOTT,
		DiplomacyOrders.KIND_REVOKE_BOYCOTT,
		DiplomacyOrders.KIND_SUBSIDY,
		DiplomacyOrders.KIND_CANCEL_SUBSIDY,
		DiplomacyOrders.KIND_REVOKE_FTP,
		DiplomacyOrders.KIND_BREAK,
	]
	for kind: String in AiDiplomacyOffers.KINDS:
		var queued: bool = DiplomacyProposals.knows(kind)
		assert_true(queued or one_sided.has(kind), "%s has a path to the human court" % kind)
	for kind: String in one_sided:
		assert_false(
			DiplomacyProposals.knows(kind),
			"%s needs no consent, so it never blocks the court" % kind
		)

func test_an_isolationist_values_a_trade_pact_less() -> void:
	_setup_ai_diplomacy_offers()
	# Same warm standing, same one order: the isolationist prices the pact 20
	# lower, so it keeps to the overture chain where a plain court would trade
	# (wiki: hidden-agendas — minimal trade; DR-20261111-27).
	ai_diplomacy_offers_state.ensure_relation(2, 3, 1)
	ai_diplomacy_offers_state.relation(2, 3).score = 75.0
	_stage(2, 3, DiplomacyCatalog.STAGE_EMBASSY)
	var context: Dictionary = _context({2: 100, 3: 100})
	var world: WorldMap = ai_diplomacy_offers_AiFixture.world([0, 2, 3, 3, 3, 3])
	var plain_entries: Array[Dictionary] = AiDiplomacyOffers.candidates(
		ai_diplomacy_offers_config, ai_diplomacy_offers_state, ai_diplomacy_offers_ai_state, world, 1, 3, 20, context
	)
	var loner: AiConfig = AiConfig.build(2, 1500, AiProfile.NORMAL, AiAgenda.ISOLATIONIST)
	loner.personality = AiPersonality.NEUTRAL
	var loner_entries: Array[Dictionary] = AiDiplomacyOffers.candidates(
		loner, ai_diplomacy_offers_state, ai_diplomacy_offers_ai_state, world, 1, 3, 20, context
	)
	var plain_pact: int = _utility_of(plain_entries, AiDiplomacyOffers.KIND_FTP)
	assert_true(plain_pact > 0, "the pact is legal at a warm standing")
	assert_eq(plain_pact, _utility_of(loner_entries, AiDiplomacyOffers.KIND_FTP) + 20)
	assert_eq(
		_utility_of(plain_entries, AiDiplomacyOffers.KIND_OVERTURE),
		_utility_of(loner_entries, AiDiplomacyOffers.KIND_OVERTURE),
		"the envoy chain is untouched"
	)

## A rival opens an envoy chain to a Minor or Tribe because it has seen land worth
## buying there; a province it has never charted buys no nudge at all, so the
## overture stays closed while the court is in no mood to improve relations
## (wiki: civilian-units § Merchant, fog-and-exploration § Visibility Levels;
## DR-20261113-03).
func test_the_land_envoy_nudge_reads_only_charted_land() -> void:
	_setup_ai_diplomacy_offers()
	ai_diplomacy_offers_state.ensure_relation(2, TRIBE, 1)
	ai_diplomacy_offers_state.relation(2, TRIBE).score = 50.0
	var world: WorldMap = _uncharted_tribe_world()
	var context: Dictionary = _context({2: 100, TRIBE: 100})
	context["treasury"] = {2: 2000}
	context["tech"] = {2: {"merchant_companies": true}}
	var published: Array[Dictionary] = AiDiplomacyOffers.candidates(
		ai_diplomacy_offers_config, ai_diplomacy_offers_state,
		ai_diplomacy_offers_ai_state, world, 1, TRIBE, 60, context
	)
	assert_eq(
		_utility_of(published, AiDiplomacyOffers.KIND_OVERTURE), 52,
		"no chart at all still prices the published map"
	)
	var charts: CourtCharts = _charts(world)
	context["charts"] = charts
	var blind: Array[Dictionary] = AiDiplomacyOffers.candidates(
		ai_diplomacy_offers_config, ai_diplomacy_offers_state,
		ai_diplomacy_offers_ai_state, world, 1, TRIBE, 60, context
	)
	assert_eq(
		_offer_blocked_kind(blind, AiDiplomacyOffers.KIND_OVERTURE),
		"improve-relations desire too low",
		"a chart that never reached the province buys no nudge"
	)
	charts.reveal_province(2, 0, 0)
	var seen: Array[Dictionary] = AiDiplomacyOffers.candidates(
		ai_diplomacy_offers_config, ai_diplomacy_offers_state,
		ai_diplomacy_offers_ai_state, world, 1, TRIBE, 60, context
	)
	assert_eq(
		_utility_of(seen, AiDiplomacyOffers.KIND_OVERTURE), 52,
		"charted land lifts the overture by the deed nudge"
	)


## The refusal an offers candidate list recorded for one order kind ("" when the
## candidate was legal).
func _offer_blocked_kind(entries: Array[Dictionary], kind: String) -> String:
	for entry: Dictionary in entries:
		if String(entry.get("kind", "")) == kind and not bool(entry.get("ok", false)):
			return String(entry.get("blocked", ""))
	return ""


## The legal candidate's utility for one kind, or -1 when it was refused.
func _utility_of(entries: Array[Dictionary], kind: String) -> int:
	for entry: Dictionary in entries:
		if String(entry.get("kind", "")) != kind:
			continue
		assert_true(
			bool(entry.get("ok", false)),
			"%s is legal: %s" % [kind, String(entry.get("blocked", ""))]
		)
		return int(entry.get("utility", -1))
	return -1

## Opens the turn pass with the given relation scores applied (default 50).
func _run(world: Array[int], scores: Array, turn: int, regiments: Dictionary = {}) -> Dictionary:
	for entry: Array in scores:
		ai_diplomacy_offers_state.ensure_relation(int(entry[0]), int(entry[1]), turn)
		ai_diplomacy_offers_state.relation(int(entry[0]), int(entry[1])).score = float(entry[2])
	return AiTurn.run(
		ai_diplomacy_offers_state, ai_diplomacy_offers_AiFixture.world(world), ai_diplomacy_offers_ai_state, turn, 0, 1500,
		{"regiments": regiments, "ships": {}}
	)

## A New World region (every tile unknown at setup) holding one Tribe province
## with a timber tile, so only a court that charts it can price the land or the
## commodity (wiki: fog-and-exploration § Visibility Levels; DR-20261113-03).
func _uncharted_tribe_world() -> WorldMap:
	var model := MapModel.new()
	model.setup(3, 2)
	model.region_id = FactionCatalog.NEW_WORLD
	model.region_key = "new_world"
	model.faction_ids = [TRIBE]
	var tiles: Array[Vector2i] = []
	for x in 3:
		model.terrain[model.index_of(x, 0)] = MapModel.Terrain.PLAINS
		model.province[model.index_of(x, 0)] = 0
		tiles.append(Vector2i(x, 0))
	model.resource[model.index_of(0, 0)] = 0
	var province := ProvinceState.create(
		0, "P0", tiles, Vector2(0.0, 0.0), 3, TRIBE, false
	)
	province.resource = 0
	province.resource_tile = Vector2i(0, 0)
	model.provinces.append(province)
	var world := WorldMap.new()
	world.add_region(model)
	return world


## Charts cut from `world`. `human` is a court the tests never read as, so every
## reader gets its own rival grid (the human's table stays empty).
func _charts(world: WorldMap, human: int = 7) -> CourtCharts:
	var charts := CourtCharts.new()
	charts.setup(world, human, {})
	return charts


func _context(power: Dictionary) -> Dictionary:
	var context: Dictionary = ai_diplomacy_offers_AiFixture.context(power)
	context["treasury"] = {}
	context["tech"] = {}
	context["player"] = 0
	return context

## Both directions at one stage, as a signed overture lands.
func _stage(a: int, b: int, stage: String) -> void:
	ai_diplomacy_offers_state.set_overture(a, b, stage)
	ai_diplomacy_offers_state.set_overture(b, a, stage)

## The refusal the offers module recorded for one order kind.
func _offer_blocked(plan: Dictionary, kind: String) -> String:
	var offer: Dictionary = plan["candidates"][0].get("offer", {})
	for entry: Dictionary in offer.get("candidates", []):
		if String(entry.get("kind", "")) == kind:
			return String(entry.get("blocked", ""))
	return ""

func _action(run: Dictionary, faction: int) -> Dictionary:
	return _record(run, faction).get("action", {})

func _record(run: Dictionary, faction: int) -> Dictionary:
	for record: Dictionary in run["trace"]:
		if int(record["faction"]) == faction:
			return record
	return {}

func _event(kind: String) -> bool:
	for entry: Dictionary in ai_diplomacy_offers_state.events:
		if String(entry.get("kind", "")) == kind:
			return true
	return false

# --- test_ai_planner ---

func test_desire_starts_at_the_base_and_adds_power_and_relation() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 1, 1)
	var desire: Dictionary = AiDiplomacyPlanner.war_desire(
		ai_planner_config, ai_planner_state, ai_planner_AiFixture.world([0, 1]), 0, 1,
		ai_planner_AiFixture.context({0: 100, 1: 100})
	)
	assert_eq(int(desire["score"]), 35, "50 base + 5 even power - 20 neutral relations")
	var factors: Dictionary = desire["factors"]
	assert_eq(int(factors["base"]), 50)
	assert_eq(int(factors["relative_power"]), 5)
	assert_eq(int(factors["relation"]), -20)
	assert_eq(int(factors["personality"]), 0)

func test_relative_power_dominates_the_score() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 1, 1)
	var world: WorldMap = ai_planner_AiFixture.world([0, 1])
	var strong: Dictionary = AiDiplomacyPlanner.war_desire(
		ai_planner_config, ai_planner_state, world, 0, 1, ai_planner_AiFixture.context({0: 135, 1: 100})
	)
	assert_eq(int(strong["score"]), 60, "50 + 30 strong - 20 neutral")
	var weak: Dictionary = AiDiplomacyPlanner.war_desire(
		ai_planner_config, ai_planner_state, world, 0, 1, ai_planner_AiFixture.context({0: 84, 1: 100})
	)
	assert_eq(int(weak["score"]), 5, "50 - 25 weak - 20 neutral")

func test_relation_pressure_bands() -> void:
	_setup_ai_planner()
	var world: WorldMap = ai_planner_AiFixture.world([0, 1])
	var context: Dictionary = ai_planner_AiFixture.context({0: 100, 1: 100})
	ai_planner_state.ensure_relation(0, 1, 1)
	ai_planner_state.relation(0, 1).score = 25.0
	assert_eq(int(AiDiplomacyPlanner.war_desire(ai_planner_config, ai_planner_state, world, 0, 1, context)["score"]), 65)
	ai_planner_state.relation(0, 1).score = 40.0
	assert_eq(int(AiDiplomacyPlanner.war_desire(ai_planner_config, ai_planner_state, world, 0, 1, context)["score"]), 55)
	ai_planner_state.relation(0, 1).score = 75.0
	assert_eq(int(AiDiplomacyPlanner.war_desire(ai_planner_config, ai_planner_state, world, 0, 1, context)["score"]), 15)

func test_minor_targets_pay_the_invasion_capacity_cost() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 6, 1)
	var world: WorldMap = ai_planner_AiFixture.world([0, 6])
	var weak: Dictionary = AiDiplomacyPlanner.war_desire(
		ai_planner_config, ai_planner_state, world, 0, 6, ai_planner_AiFixture.context({0: 100, 6: 100})
	)
	assert_eq(int(weak["score"]), 15, "no regiments is -20")
	var ready: Dictionary = AiDiplomacyPlanner.war_desire(
		ai_planner_config, ai_planner_state, world, 0, 6, ai_planner_AiFixture.context({0: 100, 6: 100}, {0: 3, 6: 0})
	)
	assert_eq(int(ready["score"]), 45, "superior regiments is +10")

func test_two_active_wars_add_the_multi_war_penalty() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 6, 1)
	ai_planner_state.ensure_relation(0, 7, 1)
	ai_planner_state.ensure_relation(0, 8, 1)
	DiplomacyRules.declare_war(ai_planner_state, 0, 7)
	DiplomacyRules.declare_war(ai_planner_state, 0, 8)
	var desire: Dictionary = AiDiplomacyPlanner.war_desire(
		ai_planner_config, ai_planner_state, ai_planner_AiFixture.world([0, 6]), 0, 6,
		ai_planner_AiFixture.context({0: 100, 6: 100}, {0: 3, 6: 0})
	)
	assert_eq(int(desire["factors"]["wars"]), -15)
	assert_eq(int(desire["score"]), 30)

func test_missing_stockpiles_are_scored_against_the_target() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 6, 1)
	var world: WorldMap = ai_planner_AiFixture.world([0, 6, 6, 6, 6], {1: 0, 2: 1, 3: 2, 4: 3})
	var context: Dictionary = ai_planner_AiFixture.context({0: 100, 6: 100})
	context["stockpiles"] = {0: {}}
	var need: Dictionary = AiDiplomacyPlanner.war_desire(ai_planner_config, ai_planner_state, world, 0, 6, context)
	assert_eq(int(need["factors"]["resource_need"]), 15, "four missing resources cap at +15")
	context["stockpiles"] = {0: {"timber": 4, "iron": 4, "coal": 4}}
	var partly: Dictionary = AiDiplomacyPlanner.war_desire(ai_planner_config, ai_planner_state, world, 0, 6, context)
	assert_eq(int(partly["factors"]["resource_need"]), 5)

## The commodity term reads only land the court has charted: a province it has
## never sailed past adds nothing to its war desire, and charting it restores the
## bonus (wiki: fog-and-exploration § Visibility Levels; DR-20261113-03).
func test_the_resource_need_counts_only_charted_land() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, TRIBE, 1)
	var world: WorldMap = _uncharted_tribe_world()
	var context: Dictionary = ai_planner_AiFixture.context({0: 100, TRIBE: 100})
	context["stockpiles"] = {0: {}}
	var published: Dictionary = AiDiplomacyPlanner.war_desire(
		ai_planner_config, ai_planner_state, world, 0, TRIBE, context
	)
	assert_eq(
		int(published["factors"]["resource_need"]), 5, "no chart still reads the published map"
	)
	var charts: CourtCharts = _charts(world)
	context["charts"] = charts
	var blind: Dictionary = AiDiplomacyPlanner.war_desire(
		ai_planner_config, ai_planner_state, world, 0, TRIBE, context
	)
	assert_eq(int(blind["factors"]["resource_need"]), 0, "unseen land offers no commodity")
	charts.reveal_province(0, 0, 0)
	var seen: Dictionary = AiDiplomacyPlanner.war_desire(
		ai_planner_config, ai_planner_state, world, 0, TRIBE, context
	)
	assert_eq(int(seen["factors"]["resource_need"]), 5, "charted ground prices the commodity")
	assert_eq(
		int(seen["score"]),
		int(blind["score"]),
		"the chart moved the one term the fog reaches, not the whole formula"
	)

func test_rival_embassies_add_the_intervention_risk_penalty() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 6, 1)
	ai_planner_state.set_overture(1, 6, DiplomacyCatalog.STAGE_EMBASSY)
	ai_planner_state.set_overture(2, 6, DiplomacyCatalog.STAGE_EMBASSY)
	ai_planner_state.set_overture(3, 6, DiplomacyCatalog.STAGE_EMBASSY)
	var desire: Dictionary = AiDiplomacyPlanner.war_desire(
		ai_planner_config, ai_planner_state, ai_planner_AiFixture.world([0, 6]), 0, 6,
		ai_planner_AiFixture.context({0: 100, 6: 100})
	)
	assert_eq(int(desire["factors"]["intervention"]), -24, "three embassies cap at -24")
	ai_planner_state.set_overture(2, 6, DiplomacyCatalog.STAGE_NONE)
	ai_planner_state.set_overture(3, 6, DiplomacyCatalog.STAGE_NONE)
	var single: Dictionary = AiDiplomacyPlanner.war_desire(
		ai_planner_config, ai_planner_state, ai_planner_AiFixture.world([0, 6]), 0, 6,
		ai_planner_AiFixture.context({0: 100, 6: 100})
	)
	assert_eq(int(single["factors"]["intervention"]), -8)

## A deed is protection in the attacker's eyes too: a rival's purchased land in
## the minor's provinces is a Great Power the declaration would call to the
## victim's aid, so it costs the same -8 as an embassy (wiki: diplomacy
## § Intervention "investment protection"; DR-20261110-20).
func test_a_rival_deed_in_the_minors_land_adds_the_intervention_risk_penalty() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 6, 1)
	var world: WorldMap = ai_planner_AiFixture.world([0, 6])
	var context: Dictionary = ai_planner_AiFixture.context({0: 100, 6: 100}, {0: 3, 6: 0})
	var bare: Dictionary = AiDiplomacyPlanner.war_desire(ai_planner_config, ai_planner_state, world, 0, 6, context)
	assert_eq(int(bare["factors"]["intervention"]), 0, "no one would answer")
	var model: MapModel = world.region(0)
	assert_true(model.ownership.purchase(model.index_of(1, 0), 1), "a rival buys land")
	var bought: Dictionary = AiDiplomacyPlanner.war_desire(ai_planner_config, ai_planner_state, world, 0, 6, context)
	assert_eq(int(bought["factors"]["intervention"]), -8, "the deed holder answers")
	assert_true(
		int(bought["score"]) < int(bare["score"]),
		"the protected minor is the harder war"
	)

func test_declares_war_when_strong_and_relations_are_cool() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 1, 1)
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		ai_planner_config, ai_planner_state, ai_planner_ai_state, ai_planner_AiFixture.world([0, 1, 1]), 1,
		ai_planner_AiFixture.context({0: 200, 1: 100})
	)
	var action: Dictionary = plan["action"]
	assert_eq(String(action["kind"]), AiDiplomacyPlanner.KIND_DECLARE_WAR)
	assert_eq(int(action["target"]), 1)
	assert_eq(int(action["desired_territory"]), 2, "clamp(round(75/25), 1, 2)")

func test_friendly_relations_block_war_even_when_desire_is_high() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 1, 1)
	ai_planner_state.relation(0, 1).score = 80.0
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		ai_planner_config, ai_planner_state, ai_planner_ai_state, ai_planner_AiFixture.world([0, 1]), 1,
		ai_planner_AiFixture.context({0: 400, 1: 100})
	)
	assert_eq(String(plan["candidates"][0]["blocked"]), "relations too warm")
	assert_eq(
		String((plan["action"] as Dictionary).get("kind", "")),
		AiDiplomacyOffers.KIND_ALLIANCE,
		"the court works for the treaty the standing already earns"
	)

func test_war_cooldown_blocks_the_pair_for_four_turns() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 1, 1)
	ai_planner_ai_state.note_war(0, 1, 1)
	var context: Dictionary = ai_planner_AiFixture.context({0: 200, 1: 100})
	var world: WorldMap = ai_planner_AiFixture.world([0, 1])
	var cooling: Dictionary = AiDiplomacyPlanner.decide(ai_planner_config, ai_planner_state, ai_planner_ai_state, world, 2, context)
	assert_true((cooling["action"] as Dictionary).is_empty())
	assert_eq(String(cooling["candidates"][0]["blocked"]), "war cooldown")
	var ready: Dictionary = AiDiplomacyPlanner.decide(ai_planner_config, ai_planner_state, ai_planner_ai_state, world, 5, context)
	assert_eq(String(ready["action"]["kind"]), AiDiplomacyPlanner.KIND_DECLARE_WAR)

## A peace cools the pair: the war the courts just signed away is not declared
## again at the 4-turn cooldown, and the trace says why (wiki: diplomacy
## § Planner selection; DR-20261113-25). The observer run showed England-France
## and France-Maya each declared and undone 46 times in 200 turns.
func test_a_peace_cools_the_pair_off_the_declaration_bar() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 1, 1)
	var world: WorldMap = ai_planner_AiFixture.world([0, 1])
	var context: Dictionary = ai_planner_AiFixture.context({0: 200, 1: 100})
	var hot: Dictionary = AiDiplomacyPlanner.decide(
		ai_planner_config, ai_planner_state, ai_planner_ai_state, world, 5, context
	)
	assert_eq(String(hot["action"]["kind"]), AiDiplomacyPlanner.KIND_DECLARE_WAR)
	assert_false(
		(hot["candidates"][0]["factors"] as Dictionary).has("truce"),
		"a pair that never made peace carries no cooling term"
	)
	ai_planner_ai_state.note_peace(0, 1, 5)
	var cooling: Dictionary = AiDiplomacyPlanner.decide(
		ai_planner_config, ai_planner_state, ai_planner_ai_state, world, 6, context
	)
	assert_true(
		(cooling["action"] as Dictionary).is_empty(),
		"the peace is not undone on the next turn"
	)
	assert_eq(String(cooling["candidates"][0]["blocked"]), "war desire too low")
	assert_eq(
		int(cooling["candidates"][0]["factors"]["truce"]),
		-AiPeaceStance.TRUCE_DESIRE_PENALTY,
		"the trace names the cooling term"
	)
	var restored: AiState = AiState.from_dict(ai_planner_ai_state.to_dict())
	assert_true(
		restored.peace_on_cooldown(0, 1, 6, AiPeaceStance.TRUCE_TURNS),
		"a save keeps the truce"
	)
	var expiring: Dictionary = AiDiplomacyPlanner.decide(
		ai_planner_config, ai_planner_state, ai_planner_ai_state, world,
		5 + AiPeaceStance.TRUCE_TURNS, context
	)
	assert_eq(
		String(expiring["action"]["kind"]), AiDiplomacyPlanner.KIND_DECLARE_WAR,
		"the pair may go back to war once the truce has run"
	)

## The truce prices a new declaration only: a war in progress still reads its
## full desire, so the defender's white peace is answered as before.
func test_a_truce_does_not_price_the_war_in_progress() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 1, 1)
	ai_planner_ai_state.note_peace(0, 1, 5)
	DiplomacyRules.declare_war(ai_planner_state, 0, 1)
	assert_eq(
		AiPeaceStance.truce_penalty(
			ai_planner_ai_state, 6, 0, 1, ai_planner_state.relation(0, 1)
		),
		0, "a war already on carries no cooling term"
	)
	var unread: DiplomacyRelation = null
	assert_eq(
		AiPeaceStance.truce_penalty(ai_planner_ai_state, 6, 0, 99, unread), 0,
		"a pair with no relation carries no cooling term"
	)
	assert_eq(
		AiPeaceStance.truce_penalty(
			null, 6, 0, 1, ai_planner_state.relation(0, 1)
		),
		0, "a run with no AI bookkeeping keeps the published score"
	)

func test_war_desire_below_the_minimum_blocks_war() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 1, 1)
	ai_planner_state.relation(0, 1).score = 45.0
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		ai_planner_config, ai_planner_state, ai_planner_ai_state, ai_planner_AiFixture.world([0, 1]), 1,
		ai_planner_AiFixture.context({0: 84, 1: 100})
	)
	assert_true((plan["action"] as Dictionary).is_empty())
	assert_eq(String(plan["candidates"][0]["blocked"]), "war desire too low")

func test_peace_is_offered_when_the_war_stops_being_worth_it() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 1, 1)
	DiplomacyRules.declare_war(ai_planner_state, 0, 1)
	var context: Dictionary = ai_planner_AiFixture.context({0: 100, 1: 100})
	context["player"] = 5
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		ai_planner_config, ai_planner_state, ai_planner_ai_state, ai_planner_AiFixture.world([0, 1]), 2, context
	)
	assert_eq(String(plan["action"]["kind"]), AiDiplomacyPlanner.KIND_OFFER_PEACE)
	assert_eq(int(plan["action"]["target"]), 1)

## The other half of the exchange: a court still wants the war it declared, so
## the defender's white peace is refused and the war reaches Movement (wiki:
## diplomacy § Planner selection; hidden-agendas — a warmonger keeps the war
## alive; DR-20261111-27). The observer run showed the opposite: every rival war
## was dissolved in the phase it was declared.
func test_a_warmonger_refuses_the_peace_offered_in_the_phase_it_declared() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(1, 2, 1)
	ai_planner_state.relation(1, 2).score = 35.0
	var war: Dictionary = DiplomacyRules.declare_war(ai_planner_state, 1, 2)
	assert_true(bool(war["ok"]), "the declaration stands")
	ai_planner_ai_state.agendas[1] = AiAgenda.WARMONGER
	ai_planner_ai_state.agendas[2] = AiAgenda.ISOLATIONIST
	var result: Dictionary = AiTurn.run(
		ai_planner_state,
		ai_planner_AiFixture.world([1, 1, 1, 1, 2]),
		ai_planner_ai_state,
		1,
		0,
		1500,
		{"regiments": {}, "ships": {}}
	)
	var record: Dictionary = _campaign_record_for(result["trace"], 2)
	assert_eq(String(record["action"]["kind"]), AiDiplomacyPlanner.KIND_OFFER_PEACE)
	assert_true(
		ai_planner_state.relation(1, 2).at_war,
		"the war it declared still stands after the defender's offer"
	)
	assert_true(String(record["message"]).contains("refuses a white peace"))
	assert_true(
		ai_planner_ai_state.peace_on_cooldown(2, 1, 2, 3),
		"the refusal starts the pair's peace-offer cooldown"
	)

## A refused white peace is not put again the next turn: the pair waits out the
## cooldown (wiki: diplomacy § Planner selection — either answer starts it, so a
## court does not ask again every turn; DR-20261109-07).
func test_a_refused_peace_waits_out_the_pair_cooldown() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(1, 2, 1)
	ai_planner_state.relation(1, 2).score = 35.0
	DiplomacyRules.declare_war(ai_planner_state, 1, 2)
	ai_planner_ai_state.agendas[1] = AiAgenda.WARMONGER
	ai_planner_ai_state.agendas[2] = AiAgenda.ISOLATIONIST
	var world: WorldMap = ai_planner_AiFixture.world([1, 1, 1, 1, 2])
	AiTurn.run(
		ai_planner_state, world, ai_planner_ai_state, 1, 0, 1500,
		{"regiments": {}, "ships": {}}
	)
	var cooling: Dictionary = AiTurn.run(
		ai_planner_state, world, ai_planner_ai_state, 2, 0, 1500,
		{"regiments": {}, "ships": {}}
	)
	var cooling_record: Dictionary = _campaign_record_for(cooling["trace"], 2)
	assert_true(
		cooling_record["action"].is_empty(),
		"a refused peace is not offered again the next turn"
	)
	assert_eq(
		_campaign_blocked(cooling_record, 1), "peace cooldown",
		"the trace explains the wait"
	)
	var ready: Dictionary = AiTurn.run(
		ai_planner_state, world, ai_planner_ai_state, 4, 0, 1500,
		{"regiments": {}, "ships": {}}
	)
	var ready_record: Dictionary = _campaign_record_for(ready["trace"], 2)
	assert_eq(String(ready_record["action"]["kind"]), AiDiplomacyPlanner.KIND_OFFER_PEACE)
	assert_true(ai_planner_state.relation(1, 2).at_war, "the warmonger still refuses")

## The trace row one court recorded for its target ("{}" when it did nothing).
func _campaign_record_for(trace: Array, faction: int) -> Dictionary:
	for record: Dictionary in trace:
		if int(record["faction"]) == faction:
			return record
	return {}

## The reason the planner recorded against one target ("" when it was legal).
func _campaign_blocked(record: Dictionary, target: int) -> String:
	for row: Dictionary in record.get("candidates", []):
		if int(row.get("target", -1)) == target:
			return String(row.get("blocked", ""))
	return ""

func test_peace_with_the_human_is_proposed_and_waits_for_the_player() -> void:
	_setup_ai_planner()
	var france: AiConfig = AiConfig.build(2, 1500, AiProfile.NORMAL, AiAgenda.TECH_THIEF)
	ai_planner_state.ensure_relation(2, 0, 1)
	DiplomacyRules.declare_war(ai_planner_state, 2, 0)
	var context: Dictionary = ai_planner_AiFixture.context({2: 84, 0: 100})
	context["player"] = 0
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		france, ai_planner_state, ai_planner_ai_state, ai_planner_AiFixture.world([0, 2]), 2, context
	)
	var action: Dictionary = plan["action"]
	assert_eq(String(action["kind"]), AiDiplomacyPlanner.KIND_OFFER_PEACE)
	assert_eq(int(action["target"]), 0)
	assert_true(bool(action.get("propose", false)), "the human court answers the offer")
	assert_true(ai_planner_state.relation(0, 2).at_war, "nothing is signed before the answer")

func test_a_refused_peace_waits_the_peace_cooldown() -> void:
	_setup_ai_planner()
	var france: AiConfig = AiConfig.build(2, 1500, AiProfile.NORMAL, AiAgenda.TECH_THIEF)
	ai_planner_state.ensure_relation(2, 0, 1)
	DiplomacyRules.declare_war(ai_planner_state, 2, 0)
	ai_planner_ai_state.note_peace(2, 0, 2)
	var context: Dictionary = ai_planner_AiFixture.context({2: 84, 0: 100})
	context["player"] = 0
	var cooling: Dictionary = AiDiplomacyPlanner.decide(
		france, ai_planner_state, ai_planner_ai_state, ai_planner_AiFixture.world([0, 2]), 3, context
	)
	assert_true((cooling["action"] as Dictionary).is_empty())
	assert_eq(String(cooling["candidates"][0]["blocked"]), "peace cooldown")
	var ready: Dictionary = AiDiplomacyPlanner.decide(
		france, ai_planner_state, ai_planner_ai_state, ai_planner_AiFixture.world([0, 2]), 5, context
	)
	assert_eq(String(ready["action"]["kind"]), AiDiplomacyPlanner.KIND_OFFER_PEACE)

func test_a_recent_war_declaration_does_not_silence_a_peace_offer() -> void:
	_setup_ai_planner()
	# The 4-turn war cooldown gates another Declare War on that pair, never the
	# peace leg of the same pair (wiki: diplomacy § Configurable Values —
	# "Applies to AI-initiated Declare War re-attempts"; DR-20261108-01).
	ai_planner_state.ensure_relation(0, 1, 1)
	DiplomacyRules.declare_war(ai_planner_state, 0, 1)
	ai_planner_ai_state.note_war(0, 1, 1)
	var context: Dictionary = ai_planner_AiFixture.context({0: 100, 1: 100})
	context["player"] = 5
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		ai_planner_config, ai_planner_state, ai_planner_ai_state, ai_planner_AiFixture.world([0, 1]), 2, context
	)
	assert_eq(
		String((plan["action"] as Dictionary).get("kind", "")),
		AiDiplomacyPlanner.KIND_OFFER_PEACE,
		"a war that stopped being worth waging still offers peace after declaring"
	)
	assert_eq(int((plan["action"] as Dictionary).get("target", -1)), 1)

func test_war_goal_clamps_to_the_target_province_count() -> void:
	_setup_ai_planner()
	assert_eq(AiDiplomacyPlanner.desired_territory(75, 5), 3)
	assert_eq(AiDiplomacyPlanner.desired_territory(75, 2), 2)
	assert_eq(AiDiplomacyPlanner.desired_territory(12, 3), 1)
	assert_eq(AiDiplomacyPlanner.desired_territory(100, 0), 1)

func test_a_peacemaker_offers_peace_where_a_plain_court_fights_on() -> void:
	_setup_ai_planner()
	# Same war, same standing: the dove's peace bar sits 15 higher, so a war it
	# no longer means is put to its enemy a turn earlier (wiki: hidden-agendas —
	# peacemaker early peace).
	ai_planner_state.ensure_relation(0, 1, 1)
	DiplomacyRules.declare_war(ai_planner_state, 0, 1)
	ai_planner_state.relation(0, 1).score = 40.0
	var context: Dictionary = ai_planner_AiFixture.context({0: 100, 1: 100})
	context["player"] = 5
	var world: WorldMap = ai_planner_AiFixture.world([0, 1])
	var plain: Dictionary = AiDiplomacyPlanner.decide(ai_planner_config, ai_planner_state, ai_planner_ai_state, world, 2, context)
	assert_eq(String(plain["candidates"][0]["blocked"]), "war still worth waging")
	var dove: AiConfig = AiConfig.build(0, 1500, AiProfile.NORMAL, AiAgenda.PEACEMAKER)
	var peace: Dictionary = AiDiplomacyPlanner.decide(dove, ai_planner_state, ai_planner_ai_state, world, 2, context)
	assert_eq(String(peace["action"]["kind"]), AiDiplomacyPlanner.KIND_OFFER_PEACE)
	assert_eq(int(peace["action"]["target"]), 1)

func test_a_warmonger_keeps_a_war_a_plain_court_would_end() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 1, 1)
	DiplomacyRules.declare_war(ai_planner_state, 0, 1)
	ai_planner_state.relation(0, 1).score = 60.0
	var context: Dictionary = ai_planner_AiFixture.context({0: 100, 1: 100})
	context["player"] = 5
	var world: WorldMap = ai_planner_AiFixture.world([0, 1])
	var plain: Dictionary = AiDiplomacyPlanner.decide(ai_planner_config, ai_planner_state, ai_planner_ai_state, world, 2, context)
	assert_eq(String(plain["action"]["kind"]), AiDiplomacyPlanner.KIND_OFFER_PEACE)
	var hawk: AiConfig = AiConfig.build(0, 1500, AiProfile.NORMAL, AiAgenda.WARMONGER)
	var keep: Dictionary = AiDiplomacyPlanner.decide(hawk, ai_planner_state, ai_planner_ai_state, world, 2, context)
	assert_true((keep["action"] as Dictionary).is_empty(), "the war is still worth waging")
	assert_eq(String(keep["candidates"][0]["blocked"]), "war still worth waging")

func test_a_backstabber_breaks_an_alliance_it_would_otherwise_keep() -> void:
	_setup_ai_planner()
	# A formal ally that is weaker than the court: the treaty still serves an
	# honest court, but the backstabber's desire against its own ally clears the
	# break bar (wiki: hidden-agendas — hits allies when weak).
	ai_planner_state.ensure_relation(0, 1, 1)
	ai_planner_state.relation(0, 1).score = 70.0
	ai_planner_state.relation(0, 1).formal_alliance = true
	var context: Dictionary = ai_planner_AiFixture.context({0: 135, 1: 100})
	context["player"] = 5
	var world: WorldMap = ai_planner_AiFixture.world([0, 1])
	var honest: Dictionary = AiDiplomacyPlanner.war_desire(ai_planner_config, ai_planner_state, world, 0, 1, context)
	assert_false((honest["factors"] as Dictionary).has("betrayal"))
	assert_eq(int(honest["score"]), 40, "50 + 30 strong - 40 allied")
	var snake: AiConfig = AiConfig.build(0, 1500, AiProfile.NORMAL, AiAgenda.BACKSTABBER)
	var snake_desire: Dictionary = AiDiplomacyPlanner.war_desire(snake, ai_planner_state, world, 0, 1, context)
	assert_eq(int(snake_desire["factors"]["betrayal"]), 25)
	var keep: Dictionary = AiDiplomacyPlanner.decide(ai_planner_config, ai_planner_state, ai_planner_ai_state, world, 1, context)
	assert_true(
		String((keep["action"] as Dictionary).get("kind", "")) != AiDiplomacyOffers.KIND_BREAK,
		"an honest court keeps the treaty its standing earned"
	)
	var betray: Dictionary = AiDiplomacyPlanner.decide(snake, ai_planner_state, ai_planner_ai_state, world, 1, context)
	assert_eq(String(betray["action"]["kind"]), AiDiplomacyOffers.KIND_BREAK)
	assert_true(ai_planner_state.relation(0, 1).formal_alliance, "the planner only plans the break")

func test_an_envious_court_resents_a_human_crown_that_pulled_ahead() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 2, 1)
	var context: Dictionary = ai_planner_AiFixture.context({0: 135, 2: 100})
	context["player"] = 0
	var world: WorldMap = ai_planner_AiFixture.world([0, 2, 2])
	var plain_config: AiConfig = AiConfig.build(2, 1500, AiProfile.NORMAL, AiAgenda.TECH_THIEF)
	var plain: Dictionary = AiDiplomacyPlanner.war_desire(plain_config, ai_planner_state, world, 2, 0, context)
	assert_false((plain["factors"] as Dictionary).has("rival"))
	var jealous: AiConfig = AiConfig.build(2, 1500, AiProfile.NORMAL, AiAgenda.ENVY)
	var envy: Dictionary = AiDiplomacyPlanner.war_desire(jealous, ai_planner_state, world, 2, 0, context)
	assert_eq(int(envy["factors"]["rival"]), 20)
	assert_eq(
		int(envy["score"]) - int(plain["score"]), 25,
		"20 rival_bias + 5 war_bias"
	)
	assert_true(int(envy["score"]) > int(plain["score"]), "the lead is felt")

func test_an_envious_court_does_not_resent_a_crown_that_trails_it() -> void:
	_setup_ai_planner()
	ai_planner_state.ensure_relation(0, 2, 1)
	var context: Dictionary = ai_planner_AiFixture.context({0: 100, 2: 135})
	context["player"] = 0
	var jealous: AiConfig = AiConfig.build(2, 1500, AiProfile.NORMAL, AiAgenda.ENVY)
	var desire: Dictionary = AiDiplomacyPlanner.war_desire(
		jealous, ai_planner_state, ai_planner_AiFixture.world([0, 2, 2]), 2, 0, context
	)
	assert_false((desire["factors"] as Dictionary).has("rival"), "envy is not a grudge")
	# Nor is it a grudge against another rival: the pull is for the human crown.
	var other: Dictionary = AiDiplomacyPlanner.war_desire(
		jealous, ai_planner_state, ai_planner_AiFixture.world([0, 1, 2]), 2, 1, context
	)
	assert_false((other["factors"] as Dictionary).has("rival"))
