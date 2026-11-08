extends GdToolsTest
## Land battles and unopposed capture (wiki: combat, military-armies § Combat
## and province loss).

const Fixture = preload("res://tests/army_fixture.gd")

var _model: MapModel = null


func before_each() -> void:
	_model = Fixture.build()


func test_side_strength_aggregates_fpn_and_fpm() -> void:
	var first := Fixture.army(1, 0, 0, ["pikemen", "pikemen"])
	var second := Fixture.army(2, 0, 0, ["squires"])
	var side: Array[ArmyState] = [first, second]
	assert_almost_eq(ArmyCombat.side_strength(side), 14.0, 0.001)
	assert_eq(ArmyCombat.side_regiments(side), 3)
	assert_almost_eq(ArmyCombat.initiative(side), 50.0 / 3.0, 0.001)


func test_contested_provinces_need_a_great_power_mover() -> void:
	var attacker := Fixture.army(1, 0, 2, ["pikemen"])
	attacker.moved = true
	var minor := Fixture.army(2, 6, 2, ["pikemen"])
	minor.moved = true
	var idle := Fixture.army(3, 0, 3, ["pikemen"])
	var armies: Array[ArmyState] = [attacker, minor, idle]
	var expected: Array[int] = [2]
	assert_eq(ArmyCombat.contested_provinces(_model, armies), expected)


func test_unopposed_capture_flips_the_province() -> void:
	var attacker := Fixture.army(1, 0, 2, ["peasant_levies", "pikemen"])
	attacker.moved = true
	var armies: Array[ArmyState] = [attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_model, armies)

	assert_eq(reports.size(), 1)
	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.CAPTURE)
	assert_true(bool(reports[0]["captured"]))
	assert_eq(_model.province_owner(2), 0)
	assert_eq(attacker.count(), 2)


func test_a_third_faction_blocks_an_unopposed_capture() -> void:
	var attacker := Fixture.army(1, 0, 2, ["pikemen"])
	attacker.moved = true
	var third := Fixture.army(2, 2, 2, ["pikemen"])
	var armies: Array[ArmyState] = [attacker, third]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_model, armies)

	assert_eq(reports.size(), 0)
	assert_eq(_model.province_owner(2), 1)


func test_attacker_victory_eliminates_the_home_army_and_flips() -> void:
	var defender := Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := Fixture.army(2, 0, 2, ["guards", "guards", "guards", "guards", "guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_model, armies)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	assert_true(bool(reports[0]["captured"]))
	assert_eq(_model.province_owner(2), 0)
	assert_eq(defender.count(), 0)
	assert_true(armies.has(defender))
	assert_gt(attacker.count(), 0)


func test_defender_victory_wipes_the_attacker_without_a_flip() -> void:
	var defender := Fixture.army(1, 1, 2, ["guards", "guards", "guards", "guards", "guards"])
	var attacker := Fixture.army(2, 0, 2, ["peasant_levies"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_model, armies)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.DEFENDER_VICTORY)
	assert_eq(_model.province_owner(2), 1)
	assert_false(armies.has(attacker))
	assert_gt(defender.count(), 0)


func test_matched_large_armies_stalemate() -> void:
	var defender := Fixture.army(1, 1, 2, _repeat("peasant_levies", 10))
	var attacker := Fixture.army(2, 0, 2, _repeat("peasant_levies", 10))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_model, armies)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.STALEMATE)
	assert_eq(_model.province_owner(2), 1)
	assert_gt(defender.count(), 0)
	assert_gt(attacker.count(), 0)


func test_defending_armies_share_one_side() -> void:
	var first := Fixture.army(1, 1, 2, ["peasant_levies", "peasant_levies"])
	var second := Fixture.army(2, 1, 2, ["peasant_levies", "peasant_levies"])
	var side: Array[ArmyState] = ArmyCombat.armies_of([first, second], 2, 1)
	assert_almost_eq(ArmyCombat.side_strength(side), 12.0, 0.001)
	assert_eq(ArmyCombat.side_regiments(side), 4)


func test_cavalry_wins_the_initiative_order() -> void:
	var foot := Fixture.army(1, 1, 3, ["peasant_levies"])
	foot.moved = true
	var horse := Fixture.army(2, 2, 3, ["squires"])
	horse.moved = true
	var armies: Array[ArmyState] = [foot, horse]
	var expected: Array[int] = [2, 1]
	assert_eq(ArmyCombat.ordered_attackers(armies, 3, MapModel.NO_ID), expected)


func test_mutual_annihilation_recovers_a_garrison_for_the_next_attacker() -> void:
	var defender := Fixture.army(1, 1, 2, ["guards"], true)
	var first := Fixture.army(2, 0, 2, ["peasant_levies"])
	first.moved = true
	var second := Fixture.army(3, 2, 2, ["peasant_levies"])
	second.moved = true
	var armies: Array[ArmyState] = [defender, first, second]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_model, armies)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.MUTUAL_ANNIHILATION)
	assert_eq(int(reports[0]["garrison"]), 1)
	assert_eq(String(reports[0]["recovered_type"]), "guards")
	assert_eq(_model.province_owner(2), 1)


func test_mutual_annihilation_without_further_attackers_leaves_the_province_empty() -> void:
	var defender := Fixture.army(1, 1, 2, ["guards"], true)
	var attacker := Fixture.army(2, 0, 2, ["peasant_levies"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_model, armies)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.MUTUAL_ANNIHILATION)
	assert_eq(int(reports[0]["garrison"]), 0)
	assert_eq(_model.province_owner(2), 1)
	assert_eq(defender.count(), 0)


func test_ratio_bands_follow_the_documented_fractions() -> void:
	assert_almost_eq(float(ArmyCombat.band_for(2.0)["attacker"]), 0.15, 0.001)
	assert_almost_eq(float(ArmyCombat.band_for(2.0)["defender"]), 1.0, 0.001)
	assert_almost_eq(float(ArmyCombat.band_for(1.2)["attacker"]), 0.3, 0.001)
	assert_almost_eq(float(ArmyCombat.band_for(0.8)["attacker"]), 0.5, 0.001)
	assert_almost_eq(float(ArmyCombat.band_for(0.5)["attacker"]), 1.0, 0.001)


func test_great_powers_recover_era_four_infantry() -> void:
	assert_eq(ArmyCombat.era_for(0), ArmyCombat.GREAT_POWER_ERA)
	assert_eq(ArmyCombat.era_for(6), ArmyCombat.MINOR_ERA)
	assert_eq(ArmyCombat.era_for(9), ArmyCombat.MINOR_ERA)


func test_outcome_labels_cover_every_result() -> void:
	assert_eq(ArmyCombat.outcome_label(ArmyCombat.Outcome.ATTACKER_VICTORY), "attacker victory")
	assert_eq(ArmyCombat.outcome_label(ArmyCombat.Outcome.DEFENDER_VICTORY), "defender victory")
	assert_eq(ArmyCombat.outcome_label(ArmyCombat.Outcome.STALEMATE), "stalemate")
	assert_eq(
		ArmyCombat.outcome_label(ArmyCombat.Outcome.MUTUAL_ANNIHILATION),
		"mutual annihilation"
	)
	assert_eq(ArmyCombat.outcome_label(ArmyCombat.Outcome.CAPTURE), "province captured")


func _repeat(type_id: String, count: int) -> Array[String]:
	var types: Array[String] = []
	for _index in count:
		types.append(type_id)
	return types
