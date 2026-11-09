extends GdToolsTest
## Quick Battle contracts (wiki: quick-battle): three rounds, a player plan,
## deterministic casualties, the same ownership pipeline as auto-resolve, and
## virtual emplaced guns for sieges.

const Fixture = preload("res://tests/army_fixture.gd")


func test_quick_battle_is_deterministic_for_a_fixed_seed() -> void:
	var first: Dictionary = _fight("balanced", _guards(6), _pikes(4))
	var second: Dictionary = _fight("balanced", _guards(6), _pikes(4))

	assert_eq(int(first["outcome"]), int(second["outcome"]))
	assert_eq(
		(first["attacker_lost"] as Array).size(),
		(second["attacker_lost"] as Array).size()
	)
	assert_eq(
		(first["defender_lost"] as Array).size(),
		(second["defender_lost"] as Array).size()
	)
	assert_eq(_round_count(first), _round_count(second))


func test_quick_battle_runs_at_most_three_rounds() -> void:
	var battle: Dictionary = _fight("balanced", _guards(6), _pikes(6))
	var rounds: int = _round_count(battle)
	assert_true(rounds >= 1)
	assert_true(rounds <= QuickBattle.MAX_ROUNDS)


func test_the_players_plan_drives_the_action_script() -> void:
	var aggressive: Dictionary = _fight("aggressive", _guards(6), _pikes(4))
	var defensive: Dictionary = _fight("defensive", _guards(6), _pikes(4))
	assert_eq(String(aggressive["quick"]["plan"]), "aggressive")
	assert_eq(String(defensive["quick"]["plan"]), "defensive")


func test_quick_battle_removes_casualties_from_the_armies() -> void:
	var model := Fixture.build()
	var defender := Fixture.army(1, 1, 2, _pikes(6), true)
	var attacker := Fixture.army(2, 0, 2, _guards(6))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var before: int = ArmyCombat.side_regiments(armies)

	ArmyCombat.resolve_turn(model, armies, _context("balanced"))

	assert_true(ArmyCombat.side_regiments(armies) < before)


func test_a_siege_fields_virtual_guns_and_downgrades_the_fort() -> void:
	var model := Fixture.build()
	model.province_data(2).fort_level = 1
	var defender := Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := Fixture.army(2, 0, 2, _guards(20))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, _context("balanced"))
	var battle: Dictionary = reports[0]

	assert_eq(String(battle["battle_mode"]), "siege")
	assert_eq(int(battle["quick"]["guns_start"]), 1)
	assert_true(bool(battle["quick"]["fort_downgraded"]))
	assert_eq(model.province_data(2).fort_level, 0)


func test_rival_battles_keep_the_aggregate_path() -> void:
	var model := Fixture.build()
	var defender := Fixture.army(1, 1, 2, _pikes(3), true)
	var attacker := Fixture.army(2, 0, 2, _guards(5))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var context: Dictionary = _context("balanced")
	context["player_faction"] = 2

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)

	assert_false(reports[0].has("quick"), "a rival battle stays auto-resolve")


func test_a_weak_attacker_is_repulsed() -> void:
	var battle: Dictionary = _fight("balanced", _pikes(2), _guards(8))
	assert_eq(int(battle["outcome"]), ArmyCombat.Outcome.DEFENDER_VICTORY)


func test_a_quick_battle_win_awards_the_general() -> void:
	var model := Fixture.build()
	var defender := Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := Fixture.army(2, 0, 2, _guards(6))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var roster := GeneralRoster.new()
	roster.pool(0)
	var context: Dictionary = _context("balanced")
	context["roster"] = roster
	context["army_general"] = {attacker.id: "general_1"}

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	assert_eq(String(reports[0]["medal_gain"]), "general_1")
	assert_eq(int(reports[0]["medal_owner"]), 0)


func test_a_siege_battery_fires_while_guns_stand() -> void:
	var battle: Dictionary = _fight("balanced", _guards(6), _pikes(8), 3)
	assert_eq(int(battle["quick"]["guns_start"]), 3)
	assert_true(int(battle["quick"]["guns_left"]) < 3)
	var fired: bool = false
	for round: Dictionary in battle["quick"]["rounds"]:
		for action: Dictionary in round["actions"]:
			if String(action["action"]) == "battery":
				fired = true
	assert_true(fired, "the emplaced battery answers the assault")


func test_action_scripts_come_from_the_plan_catalog() -> void:
	assert_eq(QuickBattle.actions_for("aggressive"), ["maneuver", "assault"])
	assert_eq(QuickBattleActions.actions_for("defensive"), ["fall_back", "volley"])
	assert_eq(QuickBattleActions.actions_for("unknown"), ["volley", "entrench", "volley"])


func test_the_battery_module_silences_guns_and_downgrades() -> void:
	var model := Fixture.build()
	model.province_data(2).fort_level = 1
	var guns: Array[Dictionary] = QuickBattleBattery.make(1, {}, 1)
	assert_eq(guns.size(), 1)
	assert_eq(QuickBattleBattery.alive(guns), 1)
	assert_eq(QuickBattleBattery.hit(guns, 4), 1)
	assert_eq(QuickBattleBattery.alive(guns), 0)
	assert_true(QuickBattleBattery.downgrade_fort(model, 2, 1, guns))
	assert_eq(model.province_data(2).fort_level, 0)


func _fight(
	plan: String, attacker_types: Array[String], defender_types: Array[String],
	fort: int = 0
) -> Dictionary:
	var model := Fixture.build()
	model.province_data(2).fort_level = fort
	var defender := Fixture.army(1, 1, 2, defender_types, true)
	var attacker := Fixture.army(2, 0, 2, attacker_types)
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, _context(plan))
	return reports[0]


func _context(plan: String) -> Dictionary:
	return {
		"quick_battle": true,
		"player_faction": 0,
		"battle_plan": plan,
		"seed": 11,
	}


func _round_count(battle: Dictionary) -> int:
	return (battle["quick"]["rounds"] as Array).size()


func _guards(count: int) -> Array[String]:
	var types: Array[String] = []
	for _index in count:
		types.append("guards")
	return types


func _pikes(count: int) -> Array[String]:
	var types: Array[String] = []
	for _index in count:
		types.append("pikemen")
	return types