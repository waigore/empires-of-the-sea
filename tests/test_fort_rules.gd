extends GdToolsTest
## Forts: wiki tables, emplaced batteries, engineer builds and siege
## auto-resolve (wiki: siege-mechanics, combat § Battle Mode).

const ArmyFixture = preload("res://tests/army_fixture.gd")
const CivilianFixture = preload("res://tests/civilian_fixture.gd")

var _model: MapModel = null


func before_each() -> void:
	_model = ArmyFixture.build()


func test_fort_tables_follow_the_wiki() -> void:
	assert_eq(FortRules.MAX_LEVEL, 3)
	assert_eq(FortRules.guns(1), 1)
	assert_eq(FortRules.guns(2), 2)
	assert_eq(FortRules.guns(3), 3)
	assert_almost_eq(FortRules.wall_hp(1), 10.0, 0.001)
	assert_almost_eq(FortRules.wall_hp(3), 30.0, 0.001)
	assert_almost_eq(FortRules.damage_reduction(3), 0.6, 0.001)
	assert_eq(FortRules.cost(1), {"lumber": 3, "bronze": 3})
	assert_eq(FortRules.cost(3), {"steel": 5, "lumber": 5})
	assert_eq(FortRules.tech_gate(1), "")
	assert_eq(FortRules.tech_gate(2), "mine_engineering")
	assert_eq(FortRules.tech_gate(3), "modern_forts")


func test_fort_levels_are_multi_turn_and_capped() -> void:
	assert_eq(FortRules.turns(1), 1)
	assert_eq(FortRules.turns(3), 3)
	assert_eq(FortRules.next_level(0), 1)
	assert_eq(FortRules.next_level(2), 3)
	assert_eq(FortRules.next_level(3), 3)


func test_emplaced_battery_follows_the_researched_line() -> void:
	assert_eq(FortRules.emplaced_type({}), "royal_artillery")
	assert_eq(
		FortRules.emplaced_type({"heavy_emplaced_artillery": true}),
		"heavy_artillery"
	)
	assert_eq(
		FortRules.emplaced_type({"heavy_emplaced_artillery": true, "emplaced_siege_guns": true}),
		"siege_guns"
	)
	assert_almost_eq(
		FortRules.emplaced_strength(2, {}),
		2.0 * float(RegimentCatalog.strength("royal_artillery")),
		0.001
	)
	assert_almost_eq(FortRules.emplaced_strength(0, {}), 0.0, 0.001)


func test_walls_soak_strength_and_spare_the_defenders() -> void:
	assert_almost_eq(FortRules.wall_soak(30.0, 0), 30.0, 0.001)
	assert_almost_eq(FortRules.wall_soak(30.0, 2), 10.0, 0.001)
	assert_almost_eq(FortRules.wall_soak(5.0, 3), 0.0, 0.001)
	assert_almost_eq(FortRules.loss_scale(0), 1.0, 0.001)
	assert_almost_eq(FortRules.loss_scale(1), 0.75, 0.001)


func test_open_field_provinces_stay_field_battles() -> void:
	var defender := ArmyFixture.army(1, 1, 2, _repeat("peasant_levies", 10))
	var attacker := ArmyFixture.army(2, 0, 2, _repeat("peasant_levies", 10))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_model, armies)

	assert_eq(String(reports[0]["battle_mode"]), "field")
	assert_eq(int(reports[0]["fort_level"]), 0)
	assert_eq((reports[0]["defender_lost"] as Array).size(), 6)


func test_walls_blunt_the_assault_and_shrink_defender_losses() -> void:
	var defender := ArmyFixture.army(1, 1, 2, _repeat("peasant_levies", 10))
	var attacker := ArmyFixture.army(2, 0, 2, _repeat("peasant_levies", 10))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	_model.get_province(2).fort_level = 1

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_model, armies)

	assert_eq(String(reports[0]["battle_mode"]), "siege")
	assert_eq(int(reports[0]["fort_level"]), 1)
	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.DEFENDER_VICTORY)
	assert_eq((reports[0]["defender_lost"] as Array).size(), 2)
	assert_eq(_model.province_owner(2), 1)


func test_a_captured_province_keeps_its_walls() -> void:
	var defender := ArmyFixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := ArmyFixture.army(2, 0, 2, _repeat("guards", 5))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	_model.get_province(2).fort_level = 2

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_model, armies)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	assert_eq(_model.province_owner(2), 0)
	assert_eq(_model.get_province(2).fort_level, 2)


func test_engineer_raises_a_fort_and_lays_materials_down() -> void:
	var model := CivilianFixture.build()
	var works := LandWorks.new()
	var engineer := CivilianFixture.unit("engineer", CivilianFixture.BARE_TILE)
	var units: Array[CivilianState] = [engineer]
	var stock: Dictionary = CivilianFixture.stockpile()
	var check: Dictionary = CivilianWork.validate(
		model, engineer, "build_fort", works, units, stock
	)
	assert_true(bool(check["ok"]), String(check.get("reason", "")))
	assert_eq(int(check["duration"]), 1)
	assert_eq(check["cost"], {"lumber": 3, "bronze": 3})

	var result: Dictionary = CivilianWork.assign(
		model, engineer, "build_fort", works, units, stock
	)
	assert_true(bool(result["ok"]))
	assert_eq(int(stock["lumber"]), 37)
	assert_eq(int(stock["bronze"]), 7)
	assert_eq(model.get_province(CivilianFixture.PLAYER_PROVINCE).fort_level, 0)

	CivilianWork.resolve_turn(model, units, works)
	assert_eq(model.get_province(CivilianFixture.PLAYER_PROVINCE).fort_level, 1)
	assert_true(engineer.is_idle())


func test_upgrades_need_their_tech_and_stop_at_the_ceiling() -> void:
	var model := CivilianFixture.build()
	var works := LandWorks.new()
	var engineer := CivilianFixture.unit("engineer", CivilianFixture.BARE_TILE)
	var units: Array[CivilianState] = [engineer]
	var stock: Dictionary = CivilianFixture.stockpile()
	var province: ProvinceState = model.get_province(CivilianFixture.PLAYER_PROVINCE)

	province.fort_level = 1
	var gated: Dictionary = CivilianWork.validate(
		model, engineer, "build_fort", works, units, stock
	)
	assert_false(bool(gated["ok"]))
	assert_true(String(gated["reason"]).contains("Mine Engineering"))

	var allowed: Dictionary = CivilianWork.validate(
		model, engineer, "build_fort", works, units, stock, null,
		CivilianState.NO_TILE, {}, {"mine_engineering": true}
	)
	assert_true(bool(allowed["ok"]), String(allowed.get("reason", "")))
	assert_eq(int(allowed["duration"]), 2)

	province.fort_level = 3
	var ceiling: Dictionary = CivilianWork.validate(
		model, engineer, "build_fort", works, units, stock
	)
	assert_false(bool(ceiling["ok"]))
	assert_true(String(ceiling["reason"]).contains("modern fort"))


func test_only_owned_land_can_be_fortified() -> void:
	var model := CivilianFixture.build()
	var works := LandWorks.new()
	var engineer := CivilianFixture.unit(
		"engineer", CivilianFixture.RIVAL_GRAIN_TILE, 0
	)
	var units: Array[CivilianState] = [engineer]

	var check: Dictionary = CivilianWork.validate(
		model, engineer, "build_fort", works, units, CivilianFixture.stockpile()
	)

	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("not held"))


func _repeat(type_id: String, count: int) -> Array[String]:
	var types: Array[String] = []
	for _index in count:
		types.append(type_id)
	return types
