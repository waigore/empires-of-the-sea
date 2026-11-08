extends GdToolsTest
## General pool, tech-gated cap, pre-Combat binding and medals
## (wiki: military-generals § Generals).

const Fixture = preload("res://tests/army_fixture.gd")


func test_cap_follows_the_tech_floors_without_stacking() -> void:
	assert_eq(GeneralRoster.cap_for({}), 1)
	assert_eq(GeneralRoster.cap_for({"organised_regiments": true}), 2)
	assert_eq(
		GeneralRoster.cap_for({"organised_regiments": true, "national_bureaucracy": true}),
		3
	)
	assert_eq(
		GeneralRoster.cap_for(
			{"national_bureaucracy": true, "improved_infantry_tactics": true}
		),
		3
	)
	assert_eq(GeneralRoster.cap_for({"nationalism": true}), 4)


func test_sync_spawns_to_cap_and_never_trims() -> void:
	var roster := GeneralRoster.new()
	assert_eq(roster.sync(0, {}), 1)
	assert_eq(roster.sync(0, {"organised_regiments": true}), 2)
	assert_eq(roster.medals(0, "general_2"), 0)
	assert_eq(roster.sync(0, {}), 2, "above-cap rosters are tolerated")
	assert_eq(roster.ids(0).size(), 2)


func test_medals_gain_one_per_win_and_cap_at_four() -> void:
	var roster := GeneralRoster.new()
	roster.pool(0)
	for expected: int in [1, 2, 3, 4, 4]:
		assert_eq(roster.award(0, "general_1"), expected)
	assert_eq(roster.summary(0), "1 general · 4 medals")


func test_binding_gives_one_general_per_attacking_army() -> void:
	var model := Fixture.build()
	var world := WorldMap.new()
	world.add_region(model)
	var defender := Fixture.army(1, 1, 2, ["peasant_levies"])
	var first := Fixture.army(2, 0, 2, ["pikemen"])
	first.moved = true
	var second := Fixture.army(3, 0, 2, ["pikemen"])
	second.moved = true
	var armies: Array[ArmyState] = [defender, first, second]
	var bindings: Dictionary = GeneralBinding.bind_phase(
		world, {0: armies}, GeneralRoster.new(), 3
	)["army_general"]

	assert_eq(bindings.size(), 2)
	assert_true(bindings.has(first.id) != bindings.has(second.id))
	assert_true(bindings.has(defender.id), "the defender also gets a commander")


func test_defender_binding_stops_when_the_pool_is_spent() -> void:
	var model := Fixture.build()
	var world := WorldMap.new()
	world.add_region(model)
	var first := Fixture.army(1, 1, 2, ["peasant_levies"])
	var second := Fixture.army(2, 1, 2, ["peasant_levies"])
	var attacker := Fixture.army(3, 0, 2, ["guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [first, second, attacker]
	var bindings: Dictionary = GeneralBinding.bind_phase(
		world, {0: armies}, GeneralRoster.new(), 5
	)["army_general"]

	assert_eq(bindings.size(), 2)
	assert_true(bindings.has(attacker.id))
	assert_true(bindings.has(first.id) != bindings.has(second.id))


func test_unbound_sides_use_the_leader_fallback_medals() -> void:
	var army := Fixture.army(1, 0, 2, ["pikemen"])
	var side: Array[ArmyState] = [army]
	assert_eq(ArmyCommand.medals(side, {"leaders": {0: "napoleon"}}), 4)
	assert_eq(ArmyCommand.medals(side, {"leaders": {0: "frederick"}}), 2)
	assert_eq(ArmyCommand.medals(side, {}), 0)


func test_the_phase_medal_snapshot_beats_newly_earned_medals() -> void:
	var army := Fixture.army(1, 0, 2, ["pikemen"])
	var side: Array[ArmyState] = [army]
	var roster := GeneralRoster.new()
	roster.pool(0)
	for _index in 3:
		roster.award(0, "general_1")
	var context: Dictionary = {
		"roster": roster,
		"army_general": {army.id: "general_1"},
		"army_medals": {army.id: 1},
	}
	assert_eq(ArmyCommand.medals(side, context), 1)


func test_a_winning_general_earns_a_medal() -> void:
	var model := Fixture.build()
	var defender := Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := Fixture.army(2, 0, 2, ["guards", "guards", "guards", "guards", "guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var roster := GeneralRoster.new()
	roster.pool(0)
	var context: Dictionary = {"roster": roster, "army_general": {attacker.id: "general_1"}}

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	assert_eq(String(reports[0]["medal_gain"]), "general_1")
	assert_eq(int(reports[0]["medal_owner"]), 0)
	assert_eq(roster.medals(0, "general_1"), 1)


func test_a_four_medal_general_gains_nothing_more() -> void:
	var model := Fixture.build()
	var defender := Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := Fixture.army(2, 0, 2, ["guards", "guards", "guards", "guards", "guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var roster := GeneralRoster.new()
	roster.pool(0)
	for _index in 4:
		roster.award(0, "general_1")
	var context: Dictionary = {
		"roster": roster,
		"army_general": {attacker.id: "general_1"},
		"army_medals": {attacker.id: 4},
	}

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	assert_eq(roster.medals(0, "general_1"), 4)
	assert_eq(String(reports[0]["medal_gain"]), "")


func test_a_losing_general_keeps_his_medals() -> void:
	var model := Fixture.build()
	var defender := Fixture.army(1, 1, 2, ["guards", "guards", "guards"])
	var attacker := Fixture.army(2, 0, 2, ["peasant_levies"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var roster := GeneralRoster.new()
	roster.pool(0)
	var context: Dictionary = {"roster": roster, "army_general": {attacker.id: "general_1"}}

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.DEFENDER_VICTORY)
	assert_eq(roster.medals(0, "general_1"), 0)
	assert_eq(String(reports[0]["medal_gain"]), "")
