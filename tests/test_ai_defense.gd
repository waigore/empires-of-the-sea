extends GdToolsTest

const AiFixture = preload("res://tests/ai_fixture.gd")
## Minor Nation / Tribe defence (wiki: factions § Minor Nation, § Tribe;
## military-armies § Home Army). Those crowns never attack: at peace they hold,
## and at war they only send a relief column onto their own invaded soil.

const MINOR_ROSTER: Array[String] = ["peasant_levies", "peasant_levies", "bowmen"]
const TRIBE_ROSTER: Array[String] = ["peasant_levies", "peasant_levies"]


func test_a_minor_holds_its_army_at_peace() -> void:
	var world: WorldMap = AiFixture.land_world([6, 6, 0], {1: true})
	var model: MapModel = world.region(0)
	var state := _peace_state(0, 6)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 6, 1, true, MINOR_ROSTER, 101),
	]
	assert_eq(AiDefensePlanner.split_orders(state, model, armies, 6).size(), 0)
	var plan: Dictionary = AiDefensePlanner.march_orders(state, model, armies, 6)
	assert_eq((plan["orders"] as Array).size(), 0)


func test_a_minor_sends_a_relief_column_to_an_invaded_province() -> void:
	var world: WorldMap = AiFixture.land_world([6, 6, 0], {1: true})
	var model: MapModel = world.region(0)
	var state := _war_state(0, 6)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 6, 1, true, MINOR_ROSTER, 101),
		_army(2, 0, 0),
	]
	var splits: Array[Dictionary] = AiDefensePlanner.split_orders(state, model, armies, 6)
	assert_eq(splits.size(), 1)
	assert_eq((splits[0]["regiments"] as Array).size(), 2, "one regiment keeps the seat")
	var ids: Array[String] = []
	ids.assign(splits[0]["regiments"])
	var split: Dictionary = ArmyState.split(armies, armies[0], ids, 10)
	assert_true(bool(split["ok"]))
	var plan: Dictionary = AiDefensePlanner.march_orders(state, model, armies, 6)
	assert_eq((plan["orders"] as Array).size(), 1)
	assert_eq(int(plan["orders"][0]["province"]), 0, "the invaded province")
	assert_eq(String(plan["orders"][0]["kind"]), AiDefensePlanner.KIND_RELIEVE)


func test_an_invaded_capital_keeps_the_home_army_in_place() -> void:
	var world: WorldMap = AiFixture.land_world([6, 6, 0], {1: true})
	var model: MapModel = world.region(0)
	var state := _war_state(0, 6)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 6, 1, true, MINOR_ROSTER, 101),
		_army(2, 1, 0),
	]
	assert_eq(
		AiDefensePlanner.split_orders(state, model, armies, 6).size(),
		0,
		"the Home Army already holds the seat"
	)
	var plan: Dictionary = AiDefensePlanner.march_orders(state, model, armies, 6)
	assert_eq((plan["orders"] as Array).size(), 0)


func test_a_minor_never_marches_into_foreign_land() -> void:
	var world: WorldMap = AiFixture.land_world([6, 6, 0], {1: true})
	var model: MapModel = world.region(0)
	var state := _war_state(0, 6)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 6, 1, true, MINOR_ROSTER, 101),
		ArmyState.muster(2, 6, 0, false, ["peasant_levies"] as Array[String], 201),
		ArmyState.muster(3, 0, 2, false, ["pikemen"] as Array[String], 301),
	]
	armies[2].moved = true
	assert_eq(
		AiDefensePlanner.split_orders(state, model, armies, 6).size(),
		0,
		"no invader stands on home soil"
	)
	var plan: Dictionary = AiDefensePlanner.march_orders(state, model, armies, 6)
	assert_eq((plan["orders"] as Array).size(), 0, "a Minor never attacks")


func test_a_tribe_sends_the_same_relief_column() -> void:
	var world: WorldMap = AiFixture.land_world([9, 9, 0], {1: true})
	var model: MapModel = world.region(0)
	var state := _war_state(0, 9)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 9, 1, true, TRIBE_ROSTER, 101),
		_army(2, 0, 0),
	]
	var splits: Array[Dictionary] = AiDefensePlanner.split_orders(state, model, armies, 9)
	assert_eq(splits.size(), 1)
	assert_eq((splits[0]["regiments"] as Array).size(), 1)
	var ids: Array[String] = []
	ids.assign(splits[0]["regiments"])
	ArmyState.split(armies, armies[0], ids, 10)
	var plan: Dictionary = AiDefensePlanner.march_orders(state, model, armies, 9)
	assert_eq((plan["orders"] as Array).size(), 1)
	assert_eq(int(plan["orders"][0]["province"]), 0)


func test_a_field_army_already_in_the_field_blocks_a_second_detach() -> void:
	var world: WorldMap = AiFixture.land_world([6, 6, 0], {1: true})
	var model: MapModel = world.region(0)
	var state := _war_state(0, 6)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 6, 1, true, MINOR_ROSTER, 101),
		ArmyState.muster(2, 6, 0, false, ["bowmen"] as Array[String], 201),
		_army(3, 0, 0),
	]
	armies[1].moved = true
	assert_eq(
		AiDefensePlanner.split_orders(state, model, armies, 6).size(),
		0,
		"the home army is not drained twice"
	)
	var plan: Dictionary = AiDefensePlanner.march_orders(state, model, armies, 6)
	assert_eq((plan["orders"] as Array).size(), 0, "the column already holds the province")


func test_a_field_army_can_relieve_the_invaded_capital() -> void:
	var world: WorldMap = AiFixture.land_world([6, 6, 0], {1: true})
	var model: MapModel = world.region(0)
	var state := _war_state(0, 6)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 6, 1, true, MINOR_ROSTER, 101),
		ArmyState.muster(2, 6, 0, false, ["bowmen"] as Array[String], 201),
		_army(3, 1, 0),
	]
	var plan: Dictionary = AiDefensePlanner.march_orders(state, model, armies, 6)
	assert_eq((plan["orders"] as Array).size(), 1)
	assert_eq(int(plan["orders"][0]["province"]), 1, "the seat outranks other provinces")


func test_a_home_army_with_one_regiment_cannot_spare_a_column() -> void:
	var world: WorldMap = AiFixture.land_world([6, 6, 0], {1: true})
	var model: MapModel = world.region(0)
	var state := _war_state(0, 6)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 6, 1, true, ["peasant_levies"] as Array[String], 101),
		_army(2, 0, 0),
	]
	assert_eq(AiDefensePlanner.split_orders(state, model, armies, 6).size(), 0)


func test_a_great_power_keeps_its_offensive_planner() -> void:
	var world: WorldMap = AiFixture.land_world([1, 1])
	var model: MapModel = world.region(0)
	var state := _war_state(0, 1)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 1, 0, true, MINOR_ROSTER, 101),
		_army(2, 1, 0),
	]
	assert_eq(AiDefensePlanner.split_orders(state, model, armies, 1).size(), 0)
	var plan: Dictionary = AiDefensePlanner.march_orders(state, model, armies, 1)
	assert_eq((plan["orders"] as Array).size(), 0)


func test_the_relief_column_joins_the_defence() -> void:
	var world: WorldMap = AiFixture.land_world([6, 6, 0], {1: true})
	var model: MapModel = world.region(0)
	var state := _war_state(0, 6)
	var invader := ArmyState.muster(
		2, 0, 0, false, ["pikemen", "pikemen", "pikemen"] as Array[String], 201
	)
	invader.moved = true
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 6, 1, true, MINOR_ROSTER, 101),
		invader,
	]
	var splits: Array[Dictionary] = AiDefensePlanner.split_orders(state, model, armies, 6)
	var ids: Array[String] = []
	ids.assign(splits[0]["regiments"])
	var split: Dictionary = ArmyState.split(armies, armies[0], ids, 10)
	var plan: Dictionary = AiDefensePlanner.march_orders(state, model, armies, 6)
	var field: ArmyState = split["army"] as ArmyState
	ArmyMovement.apply_move(model, field, int(plan["orders"][0]["province"]), true)
	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies)
	assert_eq(reports.size(), 1)
	assert_eq(int(reports[0]["defender"]), 6)
	assert_ne(
		int(reports[0]["outcome"]),
		ArmyCombat.Outcome.CAPTURE,
		"the relief column turns an unopposed capture into a battle"
	)


func test_the_map_phase_moves_a_minor_relief_without_a_hud() -> void:
	var world: WorldMap = AiFixture.land_world([6, 6, 0], {1: true})
	var model: MapModel = world.region(0)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, 6, 1, true, MINOR_ROSTER, 101),
		_army(2, 0, 0),
	]
	var layer := ArmyLayer.new()
	layer.model = model
	layer.next_army = 100
	layer.regions.set_region(0, armies)
	var play := PlaySession.new()
	play.player_faction = 0
	play.world = world
	play.model = model
	play.diplomacy = _war_state(0, 6)
	play.army_layer = layer
	play.map_seed = 1500
	var trace: Array[Dictionary] = MapPlayArmies.run_ai(play)
	assert_eq(trace.size(), 2, "one detach and one relief march")
	assert_eq(String(trace[0]["kind"]), AiMilitaryPlanner.KIND_SPLIT)
	assert_eq(String(trace[1]["kind"]), AiDefensePlanner.KIND_RELIEVE)
	var field: ArmyState = null
	for army: ArmyState in layer.armies:
		if army.owner == 6 and not army.home:
			field = army
	assert_not_null(field)
	assert_eq(field.province, 0, "the relief column stands with the invaders")
	layer.free()


## A hostile column that has marched into home soil; the flag is the marker
## ArmyCombat uses, and the planner reads the presence itself.
func _army(id: int, province: int, owner: int) -> ArmyState:
	var army := ArmyState.muster(
		id, owner, province, false, ["pikemen"] as Array[String], id * 100
	)
	army.moved = true
	return army


func _peace_state(first: int, second: int) -> DiplomacyState:
	var state := DiplomacyState.new()
	state.reset(1)
	state.ensure_relation(first, second, 1)
	return state


func _war_state(attacker: int, target: int) -> DiplomacyState:
	var state := _peace_state(attacker, target)
	state.relation(attacker, target).at_war = true
	return state
