extends GdToolsTest
## The one settlement pipeline auto-resolve and Quick Battle share: the report
## fields, the province, the medal and the aftermath (wiki: combat § Outcomes;
## quick-battle § Outcome and integration; REQ-P2-03, REQ-P3-01, REQ-P3-04).

const Fixture = preload("res://tests/army_fixture.gd")


func _mods(medals: int = 0, fort: int = 0) -> Dictionary:
	return {"medals": medals, "fort": fort}


func _report(
	model: MapModel, outcome: int, attacker_medals: int = 0, defender_medals: int = 0
) -> Dictionary:
	return BattleSettlement.report_skeleton(
		model, 2, 0, 1, outcome,
		[] as Array[String], [] as Array[String],
		_mods(attacker_medals), _mods(defender_medals)
	)


func test_the_skeleton_carries_the_fields_every_battle_prints() -> void:
	var model := Fixture.build()
	var province: ProvinceState = model.get_province(2)
	province.fort_level = 2
	province.hospital_level = 1
	var atk_lost: Array[String] = ["a1"]
	var def_lost: Array[String] = []
	var report: Dictionary = BattleSettlement.report_skeleton(
		model, 2, 0, 1, ArmyCombat.Outcome.STALEMATE, atk_lost, def_lost,
		_mods(2), _mods(1, 2)
	)
	assert_eq(int(report["province"]), 2)
	assert_eq(int(report["attacker"]), 0)
	assert_eq(int(report["defender"]), 1)
	assert_eq(int(report["outcome"]), ArmyCombat.Outcome.STALEMATE)
	assert_eq(report["attacker_lost"], atk_lost)
	assert_eq(report["defender_lost"], def_lost)
	assert_false(bool(report["captured"]))
	assert_eq(int(report["garrison"]), 0)
	assert_eq(String(report["recovered_type"]), "")
	assert_eq(int(report["attacker_medals"]), 2)
	assert_eq(int(report["defender_medals"]), 1)
	assert_eq(String(report["battle_mode"]), "siege")
	assert_eq(int(report["fort_level"]), 2)
	assert_eq(int(report["hospital_level"]), 1)
	assert_eq(String(report["medal_gain"]), "")
	assert_eq(int(report["medal_owner"]), -1)


func test_a_victory_flips_the_province_and_decorates_the_attacker() -> void:
	var model := Fixture.build()
	var defending := Fixture.army(1, 1, 2, ["peasant_levies"])
	var attacking := Fixture.army(2, 0, 2, ["guards"])
	var armies: Array[ArmyState] = [defending, attacking]
	var report: Dictionary = _report(model, ArmyCombat.Outcome.ATTACKER_VICTORY)

	BattleSettlement.settle(
		model, armies, report, [attacking], [defending], attacking, defending,
		{}, false, 1
	)

	assert_eq(model.province_owner(2), 0, "the victor holds the province")
	assert_true(bool(report["captured"]))
	assert_eq(int(report["attacker_chevrons"]), 1)
	assert_eq(int(report["defender_chevrons"]), 0)
	assert_eq(int(report["attacker_mauled"]), 0)


func test_a_defeat_keeps_the_province_and_decorates_the_defender() -> void:
	var model := Fixture.build()
	var defending := Fixture.army(1, 1, 2, ["guards"])
	var attacking := Fixture.army(2, 0, 2, ["peasant_levies"])
	var armies: Array[ArmyState] = [defending, attacking]
	var report: Dictionary = _report(model, ArmyCombat.Outcome.DEFENDER_VICTORY)

	BattleSettlement.settle(
		model, armies, report, [attacking], [defending], attacking, defending,
		{}, false, 1
	)

	assert_eq(model.province_owner(2), 1)
	assert_false(bool(report["captured"]))
	assert_eq(int(report["attacker_chevrons"]), 0)
	assert_eq(int(report["defender_chevrons"]), 1)


## An advantage holds the field but never hands over the province
## (wiki: quick-battle § Outcome and integration).
func test_an_advantage_advances_the_attacker_without_the_province() -> void:
	var model := Fixture.build()
	var defending := Fixture.army(1, 1, 2, ["peasant_levies"])
	var attacking := Fixture.army(2, 0, 2, ["guards"])
	var armies: Array[ArmyState] = [defending, attacking]
	var report: Dictionary = _report(model, ArmyCombat.Outcome.ATTACKER_ADVANTAGE)

	BattleSettlement.settle(
		model, armies, report, [attacking], [defending], attacking, defending,
		{}, false, 1
	)

	assert_eq(model.province_owner(2), 1)
	assert_false(bool(report["captured"]))
	assert_eq(int(report["attacker_chevrons"]), 1)
	assert_eq(int(report["defender_chevrons"]), 0)


func test_a_mutual_annihilation_raises_a_garrison_when_a_second_attacker_waits() -> void:
	var model := Fixture.build()
	var defending := Fixture.army(1, 1, 2, ["peasant_levies"])
	var attacking := Fixture.army(2, 0, 2, ["guards"])
	var armies: Array[ArmyState] = [defending, attacking]
	var report: Dictionary = _report(model, ArmyCombat.Outcome.MUTUAL_ANNIHILATION)

	BattleSettlement.settle(
		model, armies, report, [attacking], [defending], attacking, defending,
		{}, true, defending.count()
	)

	assert_eq(int(report["garrison"]), 1)
	assert_eq(
		String(report["recovered_type"]),
		RegimentCatalog.garrison_type_for(ArmyGarrison.GREAT_POWER_ERA)
	)
	assert_eq(armies.size(), 3, "the reformed garrison joins the field")


func test_a_mutual_annihilation_with_no_second_attacker_leaves_no_garrison() -> void:
	var model := Fixture.build()
	var defending := Fixture.army(1, 1, 2, ["peasant_levies"])
	var attacking := Fixture.army(2, 0, 2, ["guards"])
	var armies: Array[ArmyState] = [defending, attacking]
	var report: Dictionary = _report(model, ArmyCombat.Outcome.MUTUAL_ANNIHILATION)

	BattleSettlement.settle(
		model, armies, report, [attacking], [defending], attacking, defending,
		{}, false, defending.count()
	)

	assert_eq(int(report["garrison"]), 0)
	assert_eq(String(report["recovered_type"]), "")
	assert_eq(armies.size(), 2)


func test_a_stalemate_settles_no_holder_and_no_chevrons() -> void:
	var model := Fixture.build()
	var defending := Fixture.army(1, 1, 2, ["peasant_levies"])
	var attacking := Fixture.army(2, 0, 2, ["guards"])
	var armies: Array[ArmyState] = [defending, attacking]
	var report: Dictionary = _report(model, ArmyCombat.Outcome.STALEMATE)

	BattleSettlement.settle(
		model, armies, report, [attacking], [defending], attacking, defending,
		{}, false, 1
	)

	assert_eq(model.province_owner(2), 1)
	assert_false(bool(report["captured"]))
	assert_eq(int(report["attacker_chevrons"]), 0)
	assert_eq(int(report["defender_chevrons"]), 0)
	assert_eq(int(report["garrison"]), 0)


## A medal is the commander's, not the side's: the settlement asks
## [ArmyCommand] exactly as auto-resolve did before the split.
func test_a_winning_commander_takes_the_medal() -> void:
	var model := Fixture.build()
	var defending := Fixture.army(1, 1, 2, ["peasant_levies"])
	var attacking := Fixture.army(2, 0, 2, ["guards"])
	var armies: Array[ArmyState] = [defending, attacking]
	var roster := GeneralRoster.new()
	roster.pool(0)
	var context: Dictionary = {
		"roster": roster,
		"army_general": {attacking.id: "general_1"},
	}
	var report: Dictionary = _report(model, ArmyCombat.Outcome.ATTACKER_VICTORY)

	BattleSettlement.settle(
		model, armies, report, [attacking], [defending], attacking, defending,
		context, false, 1
	)

	assert_eq(String(report["medal_gain"]), "general_1")
	assert_eq(int(report["medal_owner"]), 0)
	assert_eq(roster.medals(0, "general_1"), 1)
