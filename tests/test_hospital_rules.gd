extends GdToolsTest
## Hospitals: the province building that sets an army's recovery tempo and
## blunts battle wear (wiki: combat § Regiment condition; DR-20261111-12).

const Fixture = preload("res://tests/army_fixture.gd")
const CivilianFixture = preload("res://tests/civilian_fixture.gd")


func test_hospital_tables_follow_the_design_record() -> void:
	assert_eq(HospitalRules.MAX_LEVEL, 2)
	assert_almost_eq(HospitalRules.rest_share(0), 0.25, 0.001)
	assert_almost_eq(HospitalRules.rest_share(1), 0.40, 0.001)
	assert_almost_eq(HospitalRules.rest_share(2), 0.55, 0.001)
	assert_almost_eq(HospitalRules.triage_scale(0), 1.0, 0.001)
	assert_almost_eq(HospitalRules.triage_scale(1), 0.80, 0.001)
	assert_almost_eq(HospitalRules.triage_scale(2), 0.65, 0.001)
	assert_eq(HospitalRules.cost(1), {"lumber": 3, "fabric": 2})
	assert_eq(HospitalRules.cost(2), {"lumber": 4, "fabric": 3, "steel": 2})
	assert_eq(HospitalRules.tech_gate(1), "organised_regiments")
	assert_eq(HospitalRules.tech_gate(2), "modern_military_funding")
	assert_eq(HospitalRules.turns(1), 1)
	assert_eq(HospitalRules.turns(2), 2)
	assert_eq(HospitalRules.next_level(0), 1)
	assert_eq(HospitalRules.next_level(2), 2)
	assert_true(HospitalRules.describe(1).contains("rest 40%"))
	assert_true(HospitalRules.describe(2).contains("wear 65%"))
	assert_eq(HospitalRules.describe(0), "No hospital")


func test_a_province_stores_its_hospital_level() -> void:
	var model := Fixture.build()
	assert_eq(HospitalRules.level_at(model, 2), 0)
	HospitalRules.apply_build(model.province_data(2), 1)
	assert_eq(HospitalRules.level_at(model, 2), 1)
	HospitalRules.apply_build(model.province_data(2), 2)
	assert_eq(HospitalRules.level_at(model, 2), 2)
	HospitalRules.apply_build(model.province_data(2), 1)
	assert_eq(HospitalRules.level_at(model, 2), 2, "a later build never lowers the level")


func test_a_hospital_speeds_the_turn_start_rest() -> void:
	var model := Fixture.build()
	var army := Fixture.army(1, 0, 2, ["pikemen"])
	var regiment: String = army.regiments[0]
	army.regiment_health[regiment] = 55

	ArmyMovement.begin_turn([army], model)
	assert_eq(int(army.condition_of(regiment)["hp"]), 83, "a bare field restores a quarter")

	army.regiment_health[regiment] = 55
	model.province_data(2).hospital_level = 1
	ArmyMovement.begin_turn([army], model)
	assert_eq(int(army.condition_of(regiment)["hp"]), 99, "a field hospital restores 40%")

	army.regiment_health[regiment] = 55
	model.province_data(2).hospital_level = 2
	ArmyMovement.begin_turn([army], model)
	assert_eq(int(army.condition_of(regiment)["hp"]), 110, "a general hospital restores 55%")


func test_a_hospital_triages_the_defenders_battle_wear() -> void:
	var bare: Dictionary = _auto_battle(0)
	var field: Dictionary = _auto_battle(1)
	var general: Dictionary = _auto_battle(2)

	var bare_hp: int = _health_total(bare, "defender_health")
	var field_hp: int = _health_total(field, "defender_health")
	var general_hp: int = _health_total(general, "defender_health")

	assert_true(bare_hp > 0, "the defender survives the exchange")
	assert_true(field_hp > bare_hp, "a field hospital leaves fewer wounds")
	assert_true(general_hp > field_hp, "a general hospital leaves fewer still")
	assert_eq(int(field["hospital_level"]), 1)
	assert_eq(int(general["hospital_level"]), 2)


func test_a_hospital_triages_quick_battle_wear_too() -> void:
	var bare: Dictionary = _quick_battle(0)
	var field: Dictionary = _quick_battle(1)
	assert_true(_health_total(bare, "defender_health") > 0)
	assert_true(
		_health_total(field, "defender_health") > _health_total(bare, "defender_health"),
		"the quick plate reads the same triage"
	)


func test_an_engineer_raises_a_hospital_on_the_town_tile() -> void:
	var model := CivilianFixture.build()
	var works := LandWorks.new()
	var engineer := CivilianFixture.unit("engineer", CivilianFixture.BARE_TILE)
	var units: Array[CivilianState] = [engineer]
	var stock: Dictionary = CivilianFixture.stockpile()
	var province: ProvinceState = model.get_province(CivilianFixture.PLAYER_PROVINCE)

	var check: Dictionary = CivilianWork.validate(
		model, engineer, "build_hospital", works, units, stock, null,
		CivilianState.NO_TILE, {}, {"organised_regiments": true}
	)
	assert_true(bool(check["ok"]), String(check.get("reason", "")))
	assert_eq(int(check["duration"]), 1)
	assert_eq(check["cost"], {"lumber": 3, "fabric": 2})

	var result: Dictionary = CivilianWork.assign(
		model, engineer, "build_hospital", works, units, stock, null,
		CivilianState.NO_TILE, {}, {"organised_regiments": true}
	)
	assert_true(bool(result["ok"]))
	assert_eq(int(stock["lumber"]), 37)
	assert_eq(int(stock["fabric"]), 18)
	assert_eq(province.hospital_level, 0)

	CivilianWork.resolve_turn(model, units, works)
	assert_eq(province.hospital_level, 1)
	assert_true(engineer.is_idle())


func test_the_general_hospital_needs_its_tech_and_stops_at_the_ceiling() -> void:
	var model := CivilianFixture.build()
	var works := LandWorks.new()
	var engineer := CivilianFixture.unit("engineer", CivilianFixture.BARE_TILE)
	var units: Array[CivilianState] = [engineer]
	var stock: Dictionary = CivilianFixture.stockpile()
	var province: ProvinceState = model.get_province(CivilianFixture.PLAYER_PROVINCE)

	province.hospital_level = 1
	var gated: Dictionary = CivilianWork.validate(
		model, engineer, "build_hospital", works, units, stock
	)
	assert_false(bool(gated["ok"]))
	assert_true(String(gated["reason"]).contains("Modern Military Funding"))

	var allowed: Dictionary = CivilianWork.validate(
		model, engineer, "build_hospital", works, units, stock, null,
		CivilianState.NO_TILE, {}, {"modern_military_funding": true}
	)
	assert_true(bool(allowed["ok"]), String(allowed.get("reason", "")))
	assert_eq(int(allowed["duration"]), 2)

	province.hospital_level = 2
	var ceiling: Dictionary = CivilianWork.validate(
		model, engineer, "build_hospital", works, units, stock
	)
	assert_false(bool(ceiling["ok"]))
	assert_true(String(ceiling["reason"]).contains("general hospital"))


func test_a_save_round_trip_keeps_the_hospital() -> void:
	var model := Fixture.build()
	model.province_data(2).hospital_level = 2
	var world := WorldMap.new()
	world.add_region(model)

	var captured: Array[Dictionary] = SaveWorld.capture(world)
	model.province_data(2).hospital_level = 0
	assert_true(SaveWorld.apply(world, captured))
	assert_eq(model.province_data(2).hospital_level, 2)


func test_the_army_layer_rests_each_region_by_its_own_hospital() -> void:
	var model := Fixture.build()
	model.province_data(2).hospital_level = 1
	var army := Fixture.army(1, 0, 2, ["pikemen"])
	var regiment: String = army.regiments[0]
	army.regiment_health[regiment] = 55
	var world := WorldMap.new()
	world.add_region(model)
	var layer := ArmyLayer.new()
	layer.regions.set_region(model.region_id, [army] as Array[ArmyState])

	layer.begin_turn(world)

	assert_eq(int(army.condition_of(regiment)["hp"]), 99, "the region's hospital applies")
	layer.free()


func _auto_battle(hospital: int) -> Dictionary:
	var model := Fixture.build()
	model.province_data(2).hospital_level = hospital
	var defender := Fixture.army(1, 1, 2, ["guards", "guards", "guards", "guards"], true)
	var attacker := Fixture.army(2, 0, 2, ["guards", "guards", "guards", "guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, {"seed": 11})
	return reports[0]


func _quick_battle(hospital: int) -> Dictionary:
	var model := Fixture.build()
	model.province_data(2).hospital_level = hospital
	var defender := Fixture.army(
		1, 1, 2,
		["guards", "guards", "guards", "guards", "guards", "guards",
		"guards", "guards", "guards", "guards"],
		true
	)
	var attacker := Fixture.army(2, 0, 2, ["guards", "guards", "guards", "guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var context: Dictionary = {
		"quick_battle": true,
		"player_faction": 0,
		"battle_plan": "balanced",
		"seed": 11,
	}
	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)
	return reports[0]


func _health_total(battle: Dictionary, key: String) -> int:
	var total: int = 0
	for entry: Dictionary in battle.get(key, []) as Array:
		total += int(entry["hp"])
	return total