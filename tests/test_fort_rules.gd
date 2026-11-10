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
	assert_false(reports[0].has("siege"), "no walls means no battery block")


## Auto-resolve gun-loss (DR-20261110-22): the besieging train silences whole
## pieces and a silent battery drops the fort, even when the attack is repelled
## (wiki: siege-mechanics § Emplaced Artillery).
func test_auto_resolve_artillery_silences_the_battery_and_drops_the_fort() -> void:
	var defender := ArmyFixture.army(1, 1, 2, _repeat("peasant_levies", 10))
	var attacker := ArmyFixture.army(2, 0, 2, ["royal_artillery"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	_model.get_province(2).fort_level = 1

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_model, armies)
	var siege: Dictionary = reports[0]["siege"]

	assert_eq(int(siege["guns_start"]), 1)
	assert_eq(int(siege["guns_lost"]), 1, "one train of guns silences a Wood fort's one gun")
	assert_eq(String(siege["gun_type"]), "royal_artillery")
	assert_true(bool(siege["fort_downgraded"]))
	assert_eq(int(siege["fort_after"]), 0)
	assert_eq(_model.get_province(2).fort_level, 0, "the silent battery leaves open field")


func test_a_besieger_without_artillery_leaves_the_battery_standing() -> void:
	var defender := ArmyFixture.army(1, 1, 2, _repeat("peasant_levies", 10))
	var attacker := ArmyFixture.army(2, 0, 2, _repeat("guards", 5))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	_model.get_province(2).fort_level = 1

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_model, armies)
	var siege: Dictionary = reports[0]["siege"]

	assert_eq(int(siege["guns_lost"]), 0, "infantry cannot answer the battery")
	assert_false(bool(siege["fort_downgraded"]))
	assert_eq(_model.get_province(2).fort_level, 1)


func test_a_train_short_of_the_battery_silences_only_its_weight() -> void:
	var defender := ArmyFixture.army(1, 1, 2, _repeat("peasant_levies", 10))
	var attacker := ArmyFixture.army(2, 0, 2, ["royal_artillery"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	_model.get_province(2).fort_level = 3

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_model, armies)
	var siege: Dictionary = reports[0]["siege"]

	assert_eq(int(siege["guns_start"]), 3)
	assert_eq(int(siege["guns_lost"]), 1, "one gun's weight silences one of three")
	assert_false(bool(siege["fort_downgraded"]))
	assert_eq(_model.get_province(2).fort_level, 3)


func test_a_silenced_battery_downgrades_even_when_the_attack_is_repelled() -> void:
	var defender := ArmyFixture.army(1, 1, 2, _repeat("guards", 10))
	var attacker := ArmyFixture.army(2, 0, 2, ["royal_artillery"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	_model.get_province(2).fort_level = 1

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_model, armies)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.DEFENDER_VICTORY)
	assert_true(bool((reports[0]["siege"] as Dictionary)["fort_downgraded"]))
	assert_eq(_model.get_province(2).fort_level, 0, "guns are lost whatever the banner")


func test_a_better_emplaced_line_needs_a_heavier_train() -> void:
	var royal := ArmyFixture.army(2, 0, 2, _repeat("royal_artillery", 2))
	var heavy: Dictionary = {"heavy_emplaced_artillery": true}

	assert_eq(
		AutoSiege.guns_silenced(2, {}, [royal], 10), 2,
		"two royal trains silence two royal pieces"
	)
	assert_eq(
		AutoSiege.guns_silenced(2, heavy, [royal], 10), 1,
		"heavy pieces need more than one train for each"
	)
	assert_eq(AutoSiege.artillery_weight([royal], 10), 22.0)
	assert_eq(AutoSiege.gun_weight(heavy), 15.0)
	assert_eq(AutoSiege.guns_silenced(0, {}, [royal], 10), 0, "no fort, no battery")
	assert_eq(AutoSiege.artillery_weight([], 10), 0.0)


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


func test_a_second_project_cannot_leap_a_fort_level() -> void:
	# wiki: siege-mechanics § Fort Levels — Stone costs 4 lumber + 4 bronze and
	# needs Mine Engineering; civilian-units § Work Order Summary — one turn per
	# level. Tile exclusivity does not stop a second engineer in the same
	# province, but the completed projects must still leave one Wood fort.
	var model := CivilianFixture.build()
	var works := LandWorks.new()
	var first := CivilianFixture.unit("engineer", CivilianFixture.BARE_TILE)
	var second := CivilianFixture.unit("engineer", Vector2i(2, 1))
	second.id = 2
	var units: Array[CivilianState] = [first, second]
	var stock: Dictionary = CivilianFixture.stockpile()
	var a: Dictionary = CivilianWork.assign(model, first, "build_fort", works, units, stock)
	var b: Dictionary = CivilianWork.assign(model, second, "build_fort", works, units, stock)
	assert_true(bool(a["ok"]), String(a.get("reason", "")))
	assert_true(bool(b["ok"]), String(b.get("reason", "")))
	assert_eq(int(stock["bronze"]), 4, "both projects pay their level-1 materials")

	CivilianWork.resolve_turn(model, units, works)

	assert_eq(
		model.get_province(CivilianFixture.PLAYER_PROVINCE).fort_level, 1,
		"one turn of level-1 materials buys a Wood fort, not a free Stone one"
	)


func test_a_duplicate_upgrade_cannot_leap_the_modern_forts_gate() -> void:
	var model := CivilianFixture.build()
	var works := LandWorks.new()
	var first := CivilianFixture.unit("engineer", CivilianFixture.BARE_TILE)
	var second := CivilianFixture.unit("engineer", Vector2i(2, 2))
	second.id = 2
	var units: Array[CivilianState] = [first, second]
	var stock: Dictionary = CivilianFixture.stockpile()
	var province: ProvinceState = model.get_province(CivilianFixture.PLAYER_PROVINCE)
	province.fort_level = 1
	var tech: Dictionary = {"mine_engineering": true}

	var upgrade: Dictionary = CivilianWork.assign(
		model, first, "build_fort", works, units, stock, null,
		CivilianState.NO_TILE, {}, tech
	)
	assert_eq(int(upgrade["duration"]), 2, "a Stone upgrade is a two-turn project")
	CivilianWork.resolve_turn(model, units, works)
	assert_eq(province.fort_level, 1, "the Stone upgrade is still in progress")
	var duplicate: Dictionary = CivilianWork.assign(
		model, second, "build_fort", works, units, stock, null,
		CivilianState.NO_TILE, {}, tech
	)
	assert_true(bool(duplicate["ok"]), String(duplicate.get("reason", "")))
	CivilianWork.resolve_turn(model, units, works)
	CivilianWork.resolve_turn(model, units, works)

	assert_eq(
		province.fort_level, 2,
		"a finished duplicate leaves the Stone fort alone — Modern Forts is unowned"
	)


func test_a_queued_fort_keeps_its_ordered_level_across_a_save() -> void:
	var model := CivilianFixture.build()
	var works := LandWorks.new()
	var engineer := CivilianFixture.unit("engineer", CivilianFixture.BARE_TILE)
	var units: Array[CivilianState] = [engineer]
	var stock: Dictionary = CivilianFixture.stockpile()
	CivilianWork.assign(model, engineer, "build_fort", works, units, stock)

	var restored: CivilianState = CivilianState.from_dict(engineer.to_dict())
	assert_eq(restored.work_detail("fort_level"), 1, "the ordered level rides in work")
	var reloaded: Array[CivilianState] = [restored]
	CivilianWork.resolve_turn(model, reloaded, works)

	assert_eq(model.get_province(CivilianFixture.PLAYER_PROVINCE).fort_level, 1)


func test_a_fort_rises_on_the_provinces_town_tile() -> void:
	# wiki: siege-mechanics § Fort Levels — engineers build on the town tile;
	# DR-20261110-24 brings the province-scoped fort onto it.
	var model := CivilianFixture.build()
	var works := LandWorks.new()
	var engineer := CivilianFixture.unit("engineer", CivilianFixture.TIMBER_TILE)
	var units: Array[CivilianState] = [engineer]
	var stock: Dictionary = CivilianFixture.stockpile()
	var province: ProvinceState = model.get_province(CivilianFixture.PLAYER_PROVINCE)
	province.town_tile = Vector2i(2, 0)

	assert_eq(FortRules.site_tile(model, province.id), Vector2i(2, 0))
	var check: Dictionary = CivilianWork.validate(
		model, engineer, "build_fort", works, units, stock
	)
	assert_true(bool(check["ok"]), String(check.get("reason", "")))
	assert_eq(Vector2i(check["tile"]), Vector2i(2, 0), "the work targets the town")

	CivilianWork.assign(model, engineer, "build_fort", works, units, stock)
	assert_eq(engineer.work_tile(), Vector2i(2, 0))
	CivilianWork.resolve_turn(model, units, works)
	assert_eq(province.fort_level, 1)
	assert_eq(engineer.tile, Vector2i(2, 0), "the crew works the town it walled")


func test_the_fort_site_falls_back_to_the_capital_then_the_ordered_tile() -> void:
	var model := CivilianFixture.build()
	var province: ProvinceState = model.get_province(CivilianFixture.PLAYER_PROVINCE)
	assert_eq(FortRules.site_tile(model, province.id), CivilianFixture.BARE_TILE)

	province.town_tile = Vector2i(2, 0)
	assert_eq(FortRules.site_tile(model, province.id), Vector2i(2, 0), "the town wins")
	province.town_tile = Vector2i(-1, -1)
	province.capital_tile = Vector2i(-1, -1)
	assert_eq(FortRules.site_tile(model, province.id), Vector2i(-1, -1), "legacy map")


func _repeat(type_id: String, count: int) -> Array[String]:
	var types: Array[String] = []
	for _index in count:
		types.append(type_id)
	return types
