extends GdToolsTest
## One boot for the field: forts and sieges, the hospital, army field rules and
## regiment names, military parity, difficulty and the quick battle resolver.

## Merged from test_fort_rules, test_siege_depth, test_hospital_rules,
## test_army_field_rules, test_army_regiment_names, test_military_parity,
## test_difficulty, test_quick_battle_rules, test_army_markers.
## One Godot boot (coverage instrumentation) per theme instead of one per file.
## Each test runs only its own suite's setup; teardown follows the setup.
const ArmyFixture = preload("res://tests/army_fixture.gd")
const CivilianFixture = preload("res://tests/civilian_fixture.gd")
const siege_depth_Fixture = preload("res://tests/army_fixture.gd")
const hospital_rules_Fixture = preload("res://tests/army_fixture.gd")
const hospital_rules_CivilianFixture = preload("res://tests/civilian_fixture.gd")
const army_field_rules_Fixture = preload("res://tests/army_fixture.gd")
const army_regiment_names_Fixture = preload("res://tests/army_fixture.gd")
const difficulty_Fixture = preload("res://tests/army_fixture.gd")
const quick_battle_rules_Fixture = preload("res://tests/army_fixture.gd")

var _model: MapModel = null
var _army_field_rules_model: MapModel = null

var _suite_setup: String = ""

func _setup_fort_rules() -> void:
	_suite_setup = "fort_rules"
	_model = ArmyFixture.build()

func _setup_army_field_rules() -> void:
	_suite_setup = "army_field_rules"
	_army_field_rules_model = army_field_rules_Fixture.build()

# --- test_fort_rules ---

func test_fort_tables_follow_the_wiki() -> void:
	_setup_fort_rules()
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
	_setup_fort_rules()
	assert_eq(FortRules.turns(1), 1)
	assert_eq(FortRules.turns(3), 3)
	assert_eq(FortRules.next_level(0), 1)
	assert_eq(FortRules.next_level(2), 3)
	assert_eq(FortRules.next_level(3), 3)

func test_emplaced_battery_follows_the_researched_line() -> void:
	_setup_fort_rules()
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
	_setup_fort_rules()
	assert_almost_eq(FortRules.wall_soak(30.0, 0), 30.0, 0.001)
	assert_almost_eq(FortRules.wall_soak(30.0, 2), 10.0, 0.001)
	assert_almost_eq(FortRules.wall_soak(5.0, 3), 0.0, 0.001)
	assert_almost_eq(FortRules.loss_scale(0), 1.0, 0.001)
	assert_almost_eq(FortRules.loss_scale(1), 0.75, 0.001)

func test_open_field_provinces_stay_field_battles() -> void:
	_setup_fort_rules()
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
	_setup_fort_rules()
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
	_setup_fort_rules()
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
	_setup_fort_rules()
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
	_setup_fort_rules()
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
	_setup_fort_rules()
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
	_setup_fort_rules()
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
	_setup_fort_rules()
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
	_setup_fort_rules()
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


## The order names the wall it buys. Three fort levels share one order name,
## three prices and three waits, so "Build fort" cannot be told from "Build
## fort" for a higher wall (wiki: siege-mechanics § Fort Levels), and the turn
## that finishes it says which level was raised.
func test_the_fort_order_names_its_level_and_its_raise() -> void:
	_setup_fort_rules()
	var model := CivilianFixture.build()
	var works := LandWorks.new()
	var engineer := CivilianFixture.unit("engineer", CivilianFixture.BARE_TILE)
	var units: Array[CivilianState] = [engineer]
	var stock: Dictionary = CivilianFixture.stockpile()

	var option: Dictionary = _fort_option(
		CivilianWork.options(model, engineer, works, units, stock)
	)
	assert_eq(String(option["label"]), "Build wood fort")
	assert_eq(String(option["cost_text"]), "3 lumber + 3 bronze · 1 turn")

	var result: Dictionary = CivilianWork.assign(
		model, engineer, "build_fort", works, units, stock
	)
	assert_eq(String(result["label"]), "Build wood fort", "the order names the level")
	var reports: Array[Dictionary] = CivilianWork.resolve_turn(model, units, works)
	assert_eq(int(reports[0].get("fort_level", 0)), 1, "the report carries the level raised")
	assert_eq(
		FortRules.raise_text(1), "wood fort raised · 10 wall hp · 1 emplaced gun",
		"the despatch names the wall, not just the order"
	)

	# A stone wall is a different order: its own level, its own two turns.
	model.get_province(CivilianFixture.PLAYER_PROVINCE).fort_level = 1
	var upper: Dictionary = _fort_option(
		CivilianWork.options(
			model, engineer, works, units, stock, null, {}, {"mine_engineering": true}
		)
	)
	assert_eq(String(upper["label"]), "Build stone fort")
	assert_eq(String(upper["cost_text"]), "4 lumber + 4 bronze · 2 turns")


func _fort_option(options: Array[Dictionary]) -> Dictionary:
	for option: Dictionary in options:
		if String(option["action"]) == "build_fort":
			return option
	return {}

func test_upgrades_need_their_tech_and_stop_at_the_ceiling() -> void:
	_setup_fort_rules()
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
	_setup_fort_rules()
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
	_setup_fort_rules()
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
	_setup_fort_rules()
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
	_setup_fort_rules()
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
	_setup_fort_rules()
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
	_setup_fort_rules()
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

# --- test_siege_depth ---

func test_lane_terrain_follows_the_ground() -> void:
	var model := siege_depth_Fixture.build()
	assert_eq(SiegeLanes.lane_terrain(model, 2, 0), "open", "plains without a fort")
	assert_eq(SiegeLanes.lane_terrain(model, 2, 1), "town", "a fort rings its town")
	_set_ground(model, 2, MapModel.Terrain.HILLS)
	assert_eq(SiegeLanes.lane_terrain(model, 2, 0), "hill")
	assert_eq(SiegeLanes.lane_terrain(model, 2, 2), "hill", "broken ground keeps its character")
	_set_ground(model, 2, MapModel.Terrain.HARDWOOD_FOREST)
	assert_eq(SiegeLanes.lane_terrain(model, 2, 0), "woods")
	_set_ground(model, 2, MapModel.Terrain.SWAMP)
	assert_eq(SiegeLanes.lane_terrain(model, 2, 0), "marsh")
	assert_eq(SiegeLanes.lane_terrain(model, 2, 0, "town"), "town", "a playtest may override")

## The ground is published as `marsh` (wiki: quick-battle § Terrain;
## DR-20261110-27): a swamp province fights on marsh ground and the documented
## override is the same id the record carries — not the map's terrain enum name.
func test_the_marsh_ground_speaks_the_published_id() -> void:
	var model := siege_depth_Fixture.build()
	_set_ground(model, 2, MapModel.Terrain.SWAMP)

	assert_true(SiegeLanes.TERRAIN.has("marsh"), "the published id is the table key")
	assert_eq(SiegeLanes.lane_terrain(model, 2, 0, "marsh"), "marsh",
		"the documented playtest override is honoured")
	assert_eq(SiegeLanes.lane_terrain(model, 2, 0, "swamp"), "marsh",
		"the map enum name is not a lane id; it falls back to the province ground")
	assert_almost_eq(SiegeLanes.terrain_scale("volley", "marsh"), 0.9, 0.001)
	assert_almost_eq(SiegeLanes.terrain_scale("assault", "marsh"), 0.7, 0.001)
	assert_almost_eq(SiegeLanes.entrench_scale("marsh"), 0.8, 0.001)
	assert_eq(SiegeLanes.terrain_label("marsh"), "Marsh")

	var battle: Dictionary = _siege_depth_fight(
		"balanced", _siege_depth_repeat("guards", 8), _siege_depth_repeat("musketeers", 6), 0, "marsh"
	)
	assert_eq(String(battle["quick"]["terrain"]), "marsh", "the record speaks the rule")
	assert_eq(String(battle["quick"]["terrain_label"]), "Marsh")
	assert_true(
		_assault_losses("marsh", 20) < _assault_losses("open", 20),
		"a charge into the marsh is blunted, not open ground"
	)

func test_terrain_scales_the_action_tables() -> void:
	assert_almost_eq(SiegeLanes.terrain_scale("volley", "open"), 1.0, 0.001)
	assert_almost_eq(SiegeLanes.terrain_scale("assault", "town"), 0.55, 0.001)
	assert_almost_eq(SiegeLanes.terrain_scale("assault", "woods"), 0.6, 0.001)
	assert_almost_eq(SiegeLanes.terrain_scale("volley", "woods"), 0.75, 0.001)
	assert_almost_eq(SiegeLanes.entrench_scale("town"), 1.4, 0.001)
	assert_almost_eq(SiegeLanes.entrench_scale("marsh"), 0.8, 0.001)
	assert_almost_eq(SiegeLanes.terrain_scale("entrench", "town"), 1.0, 0.001, "no damage")
	assert_eq(SiegeLanes.terrain_label("hill"), "Hillside")
	assert_eq(SiegeLanes.terrain_label("unknown"), "Open field")

func test_three_gates_open_one_at_a_time() -> void:
	var gates: Dictionary = SiegeLanes.gates_for(2)
	assert_eq(int(gates["max"]), 3)
	assert_eq(int(gates["threshold"]), 7, "20 wall HP shared by three gates")
	assert_false(SiegeLanes.breached(gates))
	assert_eq(SiegeLanes.batter(gates, 6), 0, "six casualties do not open a gate")
	assert_eq(SiegeLanes.batter(gates, 1), 1, "the seventh does")
	assert_true(SiegeLanes.breached(gates))
	assert_almost_eq(SiegeLanes.breach_share(gates), 1.0 / 3.0, 0.001)
	assert_eq(SiegeLanes.batter(gates, 20), 2, "the rest fall in one blow")
	assert_eq(int(gates["broken"]), 3, "three gates and no more")
	assert_eq(SiegeLanes.batter(gates, 20), 0)
	assert_true(SiegeLanes.gates_for(0).is_empty(), "no fort, no gates")
	assert_eq(SiegeLanes.breach_threshold(0), 0)
	assert_eq(SiegeLanes.batter({}, 4), 0, "a field battle has no gate state")

func test_a_breach_sheds_the_wall_and_opens_the_behind_lane() -> void:
	var sheltered: Dictionary = _breach_strike(0)
	assert_true((sheltered["wall"] as Array).size() > 0, "the wall takes the shot")
	assert_eq(int(sheltered["gates_broken"]), 0, "one blow is not a breach")

	var opened: Dictionary = _breach_strike(1)
	assert_true(
		(opened["wall"] as Array).size() > (sheltered["wall"] as Array).size(),
		"a gate down, the wall no longer spares the garrison"
	)
	assert_true(
		(opened["behind"] as Array).size() > (sheltered["behind"] as Array).size(),
		"the attackers pour through the gate into the behind lane"
	)

## A fresh defender each time: the same blow against a whole wall and against a
## wall already breached through one gate.
func _breach_strike(broken: int) -> Dictionary:
	var attacker: Array[ArmyState] = _side(["musketeers", "musketeers", "musketeers", "culverin"], 2)
	var types: Array[String] = _siege_depth_repeat("peasant_levies", 8)
	types.append_array(_siege_depth_repeat("squires", 2))
	types.append_array(_siege_depth_repeat("culverin", 2))
	var defender: Array[ArmyState] = _side(types, 1)
	var armies: Array[ArmyState] = _joined(attacker, defender)
	var gates: Dictionary = SiegeLanes.gates_for(2)
	gates["broken"] = broken
	return SiegeLanes.strike(armies, attacker, defender, 12, 20, 2, false, gates)

## A line with no fight left in it delivers no blow, so it has nothing to spend
## on the fort's battery — a spent besieger cannot grind a gun down (wiki:
## siege-mechanics § Quick Battle lanes — "the guns take the blow", and only
## what a blow delivers can reach them; DR-20261110-22 buys gun loss with the
## besieging train's weight, never with an empty blow).
func test_a_spent_line_cannot_grind_down_the_battery() -> void:
	var attacker: Array[ArmyState] = _side(_siege_depth_repeat("musketeers", 4), 2)
	var defender: Array[ArmyState] = _side(_siege_depth_repeat("pikemen", 4), 1)
	var state: Dictionary = _state(attacker, defender, "open")
	state["defender"]["mods"] = {"fort": 2}
	state["attacker"]["cohesion"] = 0
	var armies: Array[ArmyState] = state["armies"]
	var guns: Array[Dictionary] = QuickBattleBattery.make(2, {}, 1)

	var entry: Dictionary = QuickBattleActions.resolve(
		armies, state, "attacker", "defender", "volley", guns
	)

	assert_eq(int(entry["battery_hit"]), 0, "no blow, nothing for the guns to soak")
	assert_eq(int(entry["guns_destroyed"]), 0, "a spent line cannot silence a gun")
	assert_almost_eq(
		QuickBattleBattery.total_hp(guns), 4.0, 0.001, "the battery is untouched"
	)
	## The other side of the line: a line with fight left in it still pays the
	## guns first, so the fix does not stop a real besieger from silencing them.
	var fresh: Array[Dictionary] = QuickBattleBattery.make(2, {}, 1)
	state["attacker"]["cohesion"] = 3
	var spent: Dictionary = QuickBattleActions.resolve(
		armies, state, "attacker", "defender", "volley", fresh
	)
	assert_true(int(spent["battery_hit"]) > 0, "a real blow is spent on the battery")

func test_a_quick_battle_reports_its_ground_and_gates() -> void:
	var battle: Dictionary = _siege_depth_fight(
		"balanced", _siege_depth_repeat("guards", 20), _siege_depth_repeat("musketeers", 10), 1, "hill"
	)
	var quick: Dictionary = battle["quick"]
	assert_eq(String(quick["terrain"]), "hill")
	assert_eq(String(quick["terrain_label"]), "Hillside")
	assert_eq(int((quick["gates"] as Dictionary)["max"]), 3)
	assert_true(int((quick["gates"] as Dictionary)["damage"]) > 0, "the wall was beaten")
	assert_eq(int((quick["limits"] as Dictionary)["attacker"]), 10)
	assert_eq(String(battle["battle_mode"]), "siege")

func test_a_garrison_without_firearms_sallies_on_its_own() -> void:
	var battle: Dictionary = _siege_depth_fight(
		"balanced", _siege_depth_repeat("guards", 8), _siege_depth_repeat("pikemen", 6), 2, "town"
	)
	assert_true(int(battle["quick"]["sorties"]) > 0, "a pike garrison must sally to fight")
	assert_eq(String(battle["quick"]["defender_plan"]), "aggressive")

func test_the_sortie_is_a_dedicated_order() -> void:
	assert_eq(
		QuickBattleActions.actions_for("aggressive", true, true),
		["entrench", "sortie"], "a sally, not an assault on its own wall"
	)
	assert_eq(
		QuickBattleActions.actions_for("aggressive", true, false),
		["entrench", "volley", "volley"], "no wall, no gate to sally from"
	)
	assert_eq(QuickBattleActions.actions_for("aggressive"), ["maneuver", "assault"])
	assert_eq(int(QuickBattleActions.ACTION_CP["sortie"]), 2)
	assert_eq(String(QuickBattleActions.ACTION_LABEL["sortie"]), "Sortie")

func test_an_assault_into_town_is_weaker() -> void:
	var open_losses: int = _assault_losses("open")
	var town_losses: int = _assault_losses("town")
	assert_true(town_losses < open_losses, "streets and rooftops blunt a charge")

func test_entrenching_is_surer_in_cover() -> void:
	var open_guard: float = _entrench_guard("open")
	var town_guard: float = _entrench_guard("town")
	assert_almost_eq(open_guard, 0.45, 0.001)
	assert_almost_eq(town_guard, 0.63, 0.001)
	assert_true(town_guard > open_guard)

func test_a_sortie_in_the_open_costs_the_garrison_dear() -> void:
	## Enough pike that a quality assault leaves men to pay the sally's own cost
	## (main's FPN/FPM blow no longer treats a thin garrison as a head count).
	var battle: Dictionary = _siege_depth_fight(
		"aggressive", _siege_depth_repeat("guards", 8), _siege_depth_repeat("pikemen", 16), 1, "town"
	)
	var sortie: Dictionary = {}
	for round: Dictionary in battle["quick"]["rounds"]:
		for action: Dictionary in round["actions"]:
			if bool(action["sortie"]):
				sortie = action
	assert_true(not sortie.is_empty(), "the plate records the sally")
	assert_true(int(sortie["defender_lost"]) > 0, "the sally costs its own men")
	assert_eq(String(sortie["label"]), "Sortie")

func _siege_depth_fight(
	plan: String, attacker: Array[String], defender: Array[String], fort: int,
	terrain: String
) -> Dictionary:
	var model := siege_depth_Fixture.build()
	model.province_data(2).fort_level = fort
	_set_ground(model, 2, _ground(terrain))
	var defender_army := siege_depth_Fixture.army(1, 1, 2, defender, true)
	var attacker_army := siege_depth_Fixture.army(2, 0, 2, attacker)
	attacker_army.moved = true
	var armies: Array[ArmyState] = [defender_army, attacker_army]
	var context: Dictionary = {
		"quick_battle": true, "player_faction": 0,
		"battle_plan": plan, "seed": 11, "terrain_override": terrain,
	}
	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)
	return reports[0]

func _assault_losses(terrain: String, count: int = 6) -> int:
	## Peer-quality lines so the blow stays in the terrain band instead of
	## wiping both open and town (quality weight from main's Quick Battle).
	var attacker: Array[ArmyState] = _side(_siege_depth_repeat("pikemen", count), 2)
	var defender: Array[ArmyState] = _side(_siege_depth_repeat("pikemen", count), 1)
	var armies: Array[ArmyState] = _joined(attacker, defender)
	var state: Dictionary = _state(attacker, defender, terrain)
	var entry: Dictionary = QuickBattleActions.resolve(
		armies, state, "attacker", "defender", "assault", [] as Array[Dictionary]
	)
	return int(entry["defender_lost"])

func _entrench_guard(terrain: String) -> float:
	var attacker: Array[ArmyState] = _side(_siege_depth_repeat("guards", 4), 2)
	var defender: Array[ArmyState] = _side(_siege_depth_repeat("pikemen", 4), 1)
	var state: Dictionary = _state(attacker, defender, terrain)
	var armies: Array[ArmyState] = state["armies"]
	var entry: Dictionary = QuickBattleActions.resolve(
		armies, state, "defender", "attacker", "entrench", [] as Array[Dictionary]
	)
	return float(entry["guard"])

func _state(
	attacker: Array[ArmyState], defender: Array[ArmyState], terrain: String
) -> Dictionary:
	var state: Dictionary = {
		"attacker": {
			"side": attacker, "owner": 2, "limit": 10, "mods": {},
			"cohesion": 3, "guard": 0.0, "lost": [] as Array[String],
			"plan": "balanced", "exposed": false,
		},
		"defender": {
			"side": defender, "owner": 1, "limit": 10, "mods": {"fort": 0},
			"cohesion": 3, "guard": 0.0, "lost": [] as Array[String],
			"plan": "defensive", "exposed": false,
		},
		"terrain": terrain,
		"gates": {},
	}
	## One list so the resolver can find both sides' regiments by instance id.
	state["armies"] = _joined(attacker, defender)
	return state

func _side(types: Array[String], owner: int) -> Array[ArmyState]:
	var side: Array[ArmyState] = []
	side.append(siege_depth_Fixture.army(10 + owner, owner, 2, types, true))
	return side

func _joined(first: Array[ArmyState], second: Array[ArmyState]) -> Array[ArmyState]:
	var all: Array[ArmyState] = []
	all.append_array(first)
	all.append_array(second)
	return all

func _set_ground(model: MapModel, province: int, terrain: int) -> void:
	var data: ProvinceState = model.province_data(province)
	for tile: Vector2i in data.tiles:
		model.terrain[model.index_of(tile.x, tile.y)] = terrain

func _ground(terrain: String) -> int:
	match terrain:
		"hill":
			return MapModel.Terrain.HILLS
		"woods":
			return MapModel.Terrain.HARDWOOD_FOREST
		"marsh":
			return MapModel.Terrain.SWAMP
	return MapModel.Terrain.PLAINS

func _siege_depth_repeat(type_id: String, count: int) -> Array[String]:
	var types: Array[String] = []
	for _index in count:
		types.append(type_id)
	return types

# --- test_hospital_rules ---

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
	var model := hospital_rules_Fixture.build()
	assert_eq(HospitalRules.level_at(model, 2), 0)
	HospitalRules.apply_build(model.province_data(2), 1)
	assert_eq(HospitalRules.level_at(model, 2), 1)
	HospitalRules.apply_build(model.province_data(2), 2)
	assert_eq(HospitalRules.level_at(model, 2), 2)
	HospitalRules.apply_build(model.province_data(2), 1)
	assert_eq(HospitalRules.level_at(model, 2), 2, "a later build never lowers the level")

func test_a_hospital_speeds_the_turn_start_rest() -> void:
	var model := hospital_rules_Fixture.build()
	var army := hospital_rules_Fixture.army(1, 0, 2, ["pikemen"])
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
	var model := hospital_rules_CivilianFixture.build()
	var works := LandWorks.new()
	var engineer := hospital_rules_CivilianFixture.unit("engineer", hospital_rules_CivilianFixture.BARE_TILE)
	var units: Array[CivilianState] = [engineer]
	var stock: Dictionary = hospital_rules_CivilianFixture.stockpile()
	var province: ProvinceState = model.get_province(hospital_rules_CivilianFixture.PLAYER_PROVINCE)

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

## A hospital shares the province town tile, so one crew a player owns builds it
## (wiki: civilian-units § Per-player tile exclusivity).
func test_a_second_engineer_cannot_raise_the_same_hospital() -> void:
	var model := hospital_rules_CivilianFixture.build()
	var works := LandWorks.new()
	var province: ProvinceState = model.get_province(hospital_rules_CivilianFixture.PLAYER_PROVINCE)
	province.town_tile = hospital_rules_CivilianFixture.BARE_TILE
	var first := hospital_rules_CivilianFixture.unit("engineer", hospital_rules_CivilianFixture.BARE_TILE)
	first.id = 1
	var second := hospital_rules_CivilianFixture.unit("engineer", Vector2i(2, 2))
	second.id = 2
	var units: Array[CivilianState] = [first, second]
	var stock: Dictionary = hospital_rules_CivilianFixture.stockpile()
	var tech := {"organised_regiments": true}
	assert_true(bool(CivilianWork.assign(
		model, first, "build_hospital", works, units, stock, null,
		CivilianState.NO_TILE, {}, tech
	)["ok"]))
	var blocked: Dictionary = CivilianWork.validate(
		model, second, "build_hospital", works, units, stock, null,
		CivilianState.NO_TILE, {}, tech
	)
	assert_false(bool(blocked["ok"]))
	assert_true(String(blocked["reason"]).contains("Another crew"))

func test_the_general_hospital_needs_its_tech_and_stops_at_the_ceiling() -> void:
	var model := hospital_rules_CivilianFixture.build()
	var works := LandWorks.new()
	var engineer := hospital_rules_CivilianFixture.unit("engineer", hospital_rules_CivilianFixture.BARE_TILE)
	var units: Array[CivilianState] = [engineer]
	var stock: Dictionary = hospital_rules_CivilianFixture.stockpile()
	var province: ProvinceState = model.get_province(hospital_rules_CivilianFixture.PLAYER_PROVINCE)

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
	var model := hospital_rules_Fixture.build()
	model.province_data(2).hospital_level = 2
	var world := WorldMap.new()
	world.add_region(model)

	var captured: Array[Dictionary] = SaveWorld.capture(world)
	model.province_data(2).hospital_level = 0
	assert_true(SaveWorld.apply(world, captured))
	assert_eq(model.province_data(2).hospital_level, 2)

func test_the_army_layer_rests_each_region_by_its_own_hospital() -> void:
	var model := hospital_rules_Fixture.build()
	model.province_data(2).hospital_level = 1
	var army := hospital_rules_Fixture.army(1, 0, 2, ["pikemen"])
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
	var model := hospital_rules_Fixture.build()
	model.province_data(2).hospital_level = hospital
	var defender := hospital_rules_Fixture.army(1, 1, 2, ["guards", "guards", "guards", "guards"], true)
	var attacker := hospital_rules_Fixture.army(2, 0, 2, ["guards", "guards", "guards", "guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, {"seed": 11})
	return reports[0]

func _quick_battle(hospital: int) -> Dictionary:
	var model := hospital_rules_Fixture.build()
	model.province_data(2).hospital_level = hospital
	var defender := hospital_rules_Fixture.army(
		1, 1, 2,
		["guards", "guards", "guards", "guards", "guards", "guards",
		"guards", "guards", "guards", "guards"],
		true
	)
	var attacker := hospital_rules_Fixture.army(2, 0, 2, ["guards", "guards", "guards", "guards"])
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



# --- the wards eat (DR-20261112-04) -------------------------------------------


func test_the_rations_table_follows_the_design_record() -> void:
	assert_eq(HospitalRules.RATION_PER_LEVEL, 2)
	assert_eq(HospitalRules.food_demand(0), 0)
	assert_eq(HospitalRules.food_demand(1), 2)
	assert_eq(HospitalRules.food_demand(2), 4)
	assert_true(HospitalRules.describe(1).contains("staff 2 food"))
	assert_true(HospitalRules.describe(2).contains("staff 4 food"))
	var hungry: String = HospitalRules.describe(1, false)
	assert_true(hungry.contains("unstaffed"))
	assert_true(hungry.contains("rest 25%"), "an empty ward heals at the field's rate")
	assert_true(hungry.contains("wear 80%"), "the walls still shelter the wounded")



func test_an_unfed_ward_heals_at_the_fields_rate() -> void:
	var model := hospital_rules_Fixture.build()
	var province: ProvinceState = model.province_data(2)
	province.hospital_level = 1
	var army := hospital_rules_Fixture.army(1, 0, 2, ["pikemen"])
	var regiment: String = army.regiments[0]

	army.regiment_health[regiment] = 55
	province.hospital_staffed = false
	assert_eq(HospitalRules.effective_level(model, 2), 0)
	assert_eq(HospitalRules.level_at(model, 2), 1, "the building still stands")
	ArmyMovement.begin_turn([army], model)
	assert_eq(int(army.condition_of(regiment)["hp"]), 83, "no staff, no faster rest")

	army.regiment_health[regiment] = 55
	province.hospital_staffed = true
	ArmyMovement.begin_turn([army], model)
	assert_eq(int(army.condition_of(regiment)["hp"]), 99, "the staff returns")



func test_the_crowns_hospitals_are_counted_seat_first() -> void:
	var world := WorldMap.new()
	var model := hospital_rules_Fixture.build()
	world.add_region(model)
	# Faction 0 holds provinces 0 (seat), 1, 5 and 6.
	model.province_data(1).hospital_level = 1
	model.province_data(0).hospital_level = 2
	model.province_data(2).hospital_level = 2

	var rows: Array[Dictionary] = HospitalRules.demand_rows(world, 0)
	assert_eq(rows.size(), 2, "only this crown's wards eat from its larder")
	assert_eq(int(rows[0]["province"]), 0, "the seat is served first")
	assert_true(bool(rows[0]["seat"]))
	assert_eq(int(rows[1]["province"]), 1)
	var demands: Array[int] = HospitalRules.demand_list(world, 0)
	assert_eq(demands.size(), 2)
	assert_eq(demands[0] + demands[1], 6, "the crown's whole hospital ration")



func test_a_staff_is_fed_whole_or_not_at_all() -> void:
	var world := WorldMap.new()
	var model := hospital_rules_Fixture.build()
	world.add_region(model)
	model.province_data(0).hospital_level = 2
	model.province_data(1).hospital_level = 1

	var short: Dictionary = HospitalRules.feed(world, 0, 2)
	assert_eq(int(short["spent"]), 2, "no half-ration is spent on the seat")
	assert_eq((short["hungry"] as Array).size(), 1)
	assert_eq(int(short["hungry"][0]), 0, "the great hospital goes without")
	assert_false(model.province_data(0).hospital_staffed)
	assert_true(model.province_data(1).hospital_staffed, "the field station keeps its staff")

	var full: Dictionary = HospitalRules.feed(world, 0, 6)
	assert_eq(int(full["spent"]), 6)
	assert_eq((full["hungry"] as Array).size(), 0)
	assert_true(model.province_data(0).hospital_staffed, "a fed ward is staffed again")



func test_the_consumption_phase_feeds_the_wards_after_the_workers() -> void:
	var stock: Dictionary = {"grain": 3, "meat": 0}
	var report: Dictionary = EconomyConsumption.resolve(WorkerPool.make(1), stock, 0, 0, [2])
	assert_eq(int(report["hospital_demand"]), 2)
	assert_eq(int(report["hospital_fed"]), 2, "one peasant, then one field hospital")
	assert_false(bool(report["hospital_hungry"]))
	assert_eq(int(stock.get("grain", 0)), 0)
	assert_eq(int(report["food_eaten"]), 3)

	var larder: Dictionary = {"grain": 9, "meat": 0}
	var fed: Dictionary = EconomyConsumption.resolve(WorkerPool.make(0), larder, 0, 0, [4])
	assert_eq(int(fed["hospital_fed"]), 4)
	assert_false(bool(fed["hospital_hungry"]))
	assert_eq(int(larder.get("grain", 0)), 5)

	# A general hospital needs four rations: two left over are no half staff,
	# so the ward goes without and the larder keeps them (DR-20261112-04).
	var short: Dictionary = {"grain": 2, "meat": 0}
	var hungry: Dictionary = EconomyConsumption.resolve(WorkerPool.make(0), short, 0, 0, [4])
	assert_eq(int(hungry["hospital_fed"]), 0, "no half ration for a great ward")
	assert_true(bool(hungry["hospital_hungry"]))
	assert_eq(int(short.get("grain", 0)), 2, "the larder keeps what no staff can use")


## Playtest: a field hospital at the seat and a general hospital elsewhere, with
## four rations left after the living. The seat eats two, the great ward cannot
## be seated on the two that remain, and those two stay in the larder — a ration
## is never stranded on a ward that cannot be staffed (DR-20261112-04).



## Playtest: a field hospital at the seat and a general hospital elsewhere, with
## four rations left after the living. The seat eats two, the great ward cannot
## be seated on the two that remain, and those two stay in the larder — a ration
## is never stranded on a ward that cannot be staffed (DR-20261112-04).
func test_the_consumption_never_strands_a_ration_on_an_unstaffable_ward() -> void:
	var world := WorldMap.new()
	var model := hospital_rules_Fixture.build()
	world.add_region(model)
	model.province_data(0).hospital_level = 1
	model.province_data(1).hospital_level = 2
	var demands: Array[int] = HospitalRules.demand_list(world, 0)
	assert_eq(demands.size(), 2, "seat first, then the chart's order")
	assert_eq(demands[0], 2, "the seat's field hospital")
	assert_eq(demands[1], 4, "the great ward elsewhere")

	var stock: Dictionary = {"grain": 4, "meat": 0}
	var report: Dictionary = EconomyConsumption.resolve(
		WorkerPool.make(0), stock, 0, 0, demands
	)
	assert_eq(int(report["hospital_demand"]), 6)
	assert_eq(int(report["hospital_fed"]), 2, "only the seat's staff can be seated")
	assert_eq(int(stock.get("grain", 0)), 2, "the rest of the larder is not eaten")

	var fed: Dictionary = HospitalRules.feed(world, 0, int(report["hospital_fed"]))
	assert_eq(int(fed["spent"]), 2, "the larder paid exactly what the staffs ate")
	assert_true(model.province_data(0).hospital_staffed)
	assert_false(model.province_data(1).hospital_staffed)
	assert_eq((fed["hungry"] as Array), [1] as Array)


## The food the larder pays and the staffs it seats are one walk: for every
## larder size, the consumption pass eats exactly what [method HospitalRules.feed]
## spends (DR-20261112-04).



## The food the larder pays and the staffs it seats are one walk: for every
## larder size, the consumption pass eats exactly what [method HospitalRules.feed]
## spends (DR-20261112-04).
func test_the_ration_and_the_staffing_agree_at_every_larder_size() -> void:
	var world := WorldMap.new()
	var model := hospital_rules_Fixture.build()
	world.add_region(model)
	model.province_data(0).hospital_level = 1
	model.province_data(1).hospital_level = 2
	var demands: Array[int] = HospitalRules.demand_list(world, 0)
	for available in 9:
		var stock: Dictionary = {"grain": available, "meat": 0}
		var report: Dictionary = EconomyConsumption.resolve(
			WorkerPool.make(0), stock, 0, 0, demands
		)
		var fed: Dictionary = HospitalRules.feed(world, 0, int(report["hospital_fed"]))
		assert_eq(
			int(fed["spent"]), int(report["hospital_fed"]),
			"larder %d: the food paid is the food seated" % available
		)
		assert_eq(int(stock.get("grain", 0)), available - int(fed["spent"]))



func test_a_save_round_trip_keeps_an_unfed_ward() -> void:
	var model := hospital_rules_Fixture.build()
	model.province_data(2).hospital_level = 2
	model.province_data(2).hospital_staffed = false
	var world := WorldMap.new()
	world.add_region(model)

	var captured: Array[Dictionary] = SaveWorld.capture(world)
	model.province_data(2).hospital_staffed = true
	assert_true(SaveWorld.apply(world, captured))
	assert_false(model.province_data(2).hospital_staffed)

	# A save written before the wards ate carries no flag: its staffs are fed.
	for region: Variant in captured:
		for entry: Variant in (region as Dictionary).get("provinces", []) as Array:
			(entry as Dictionary).erase("hospital_staffed")
	assert_true(SaveWorld.apply(world, captured))
	assert_true(model.province_data(2).hospital_staffed)



func test_the_army_dossier_names_an_unstaffed_ward() -> void:
	var model := hospital_rules_Fixture.build()
	model.province_data(2).hospital_level = 1
	var army := hospital_rules_Fixture.army(1, 0, 2, ["guards"])
	var panel := ArmyPanel.new()
	add_child(panel)

	panel.refresh(model, army, true)
	assert_true(String(panel._strength.text).contains("rest 40%"), panel._strength.text)

	# A ward whose staff went unfed heals at the field's rate, and the dossier
	# says why (wiki: combat § Regiment condition; DR-20261112-04).
	model.province_data(2).hospital_staffed = false
	panel.refresh(model, army, true)
	assert_true(
		String(panel._strength.text).contains("hospital unstaffed"), panel._strength.text
	)
	assert_false(String(panel._strength.text).contains("rest 40%"))
	panel.free()


# --- the field hospital train (DR-20261112-07) --------------------------------

func test_the_train_table_follows_the_design_record() -> void:
	assert_almost_eq(HospitalTrain.REST_SHARE, 0.40, 0.001)
	assert_eq(HospitalTrain.food(), 2)
	assert_eq(HospitalTrain.tech(), "organised_regiments")
	assert_eq(HospitalTrain.cost(), {"lumber": 2, "fabric": 1})
	assert_true(HospitalTrain.describe().contains("rest 40%"))
	assert_true(HospitalTrain.describe().contains("staff 2 food"))


func test_the_better_of_the_tents_and_the_ward_sets_the_tempo() -> void:
	var model := hospital_rules_Fixture.build()
	assert_almost_eq(HospitalTrain.army_rest_share(model, 1, false), 0.25, 0.001)
	assert_almost_eq(HospitalTrain.army_rest_share(model, 1, true), 0.40, 0.001)
	model.province_data(1).hospital_level = 2
	assert_almost_eq(
		HospitalTrain.army_rest_share(model, 1, true), 0.55, 0.001,
		"the ward's nurses still beat the tents"
	)
	var no_model: MapModel = null
	assert_almost_eq(
		HospitalTrain.army_rest_share(no_model, MapModel.NO_ID, true), 0.40, 0.001,
		"a train heals with no map at all"
	)


func test_the_train_speeds_the_rest_wherever_the_army_stands() -> void:
	var model := hospital_rules_Fixture.build()
	var army := hospital_rules_Fixture.army(1, 0, 1, ["pikemen"])
	var regiment: String = army.regiments[0]
	army.regiment_health[regiment] = 55
	ArmyMovement.begin_turn([army], model)
	assert_eq(int(army.condition_of(regiment)["hp"]), 83, "a bare field restores a quarter")

	army.field_hospital = true
	army.regiment_health[regiment] = 55
	ArmyMovement.begin_turn([army], model)
	assert_eq(int(army.condition_of(regiment)["hp"]), 99, "the train restores 40%")

	# Enemy land: the tents travel with the standard, not the province.
	army.province = 2
	army.regiment_health[regiment] = 55
	ArmyMovement.begin_turn([army], model)
	assert_eq(int(army.condition_of(regiment)["hp"]), 99)


func test_the_trains_staff_eat_with_the_men() -> void:
	var plain := hospital_rules_Fixture.army(1, 0, 1, ["pikemen"])
	var train := hospital_rules_Fixture.army(2, 0, 1, ["pikemen"])
	train.field_hospital = true
	var bare: int = ArmyRoster.food_upkeep_of([plain], 0)
	assert_eq(ArmyRoster.food_upkeep_of([train], 0), bare + 2)
	assert_eq(ArmyRoster.food_upkeep_of([train], 1), 0, "another crown pays nothing")


func test_a_train_is_pitched_on_the_crowns_own_land() -> void:
	var model := hospital_rules_Fixture.build()
	var army := hospital_rules_Fixture.army(1, 0, 1, ["pikemen"])
	var tech: Dictionary = {"organised_regiments": true}
	var stock: Dictionary = {"lumber": 2, "fabric": 1}
	assert_true(bool(HospitalTrain.check(model, army, tech, stock)["ok"]))

	assert_false(bool(HospitalTrain.check(null, army, tech, stock)["ok"]))
	assert_false(bool(HospitalTrain.check(model, null, tech, stock)["ok"]))

	var foreign := hospital_rules_Fixture.army(2, 0, 2, ["pikemen"])
	var check: Dictionary = HospitalTrain.check(model, foreign, tech, stock)
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("own land"))

	var embarked := hospital_rules_Fixture.army(3, 0, 1, ["pikemen"])
	embarked.embarked_fleet = 7
	assert_false(bool(HospitalTrain.check(model, embarked, tech, stock)["ok"]))

	var carrying := hospital_rules_Fixture.army(4, 0, 1, ["pikemen"])
	carrying.field_hospital = true
	assert_false(bool(HospitalTrain.check(model, carrying, tech, stock)["ok"]))

	var empty := hospital_rules_Fixture.army(5, 0, 1, [])
	assert_false(bool(HospitalTrain.check(model, empty, tech, stock)["ok"]))

	var locked: Dictionary = HospitalTrain.check(model, army, {}, stock)
	assert_false(bool(locked["ok"]))
	assert_true(String(locked["reason"]).contains("Organised Regiments"))

	var short: Dictionary = HospitalTrain.check(model, army, tech, {"lumber": 1})
	assert_false(bool(short["ok"]))

	# Pitching changes only the standard that carries it.
	HospitalTrain.apply(army)
	assert_true(army.field_hospital)


func test_a_train_stays_with_its_standard_through_split_and_combine() -> void:
	var army := ArmyState.muster(1, 0, 1, false, ["pikemen", "pikemen"])
	army.field_hospital = true
	var armies: Array[ArmyState] = [army]
	var split: Dictionary = ArmyRoster.split(armies, army, [army.regiments[0]], 2)
	assert_true(bool(split["ok"]))
	var detached: ArmyState = split["army"]
	assert_true(army.field_hospital, "the parent standard keeps the tents")
	assert_false(detached.field_hospital)

	# A full detach drops the emptied standard, and the train marches with the men.
	var rest: Array[ArmyState] = [army]
	var all_out: Dictionary = ArmyRoster.split(
		rest, army, army.regiments.duplicate(), 3
	)
	assert_true(bool(all_out["ok"]))
	var moved: ArmyState = all_out["army"]
	assert_eq(rest.size(), 1)
	assert_true(moved.field_hospital)

	var other := ArmyState.muster(4, 0, 1, false, ["pikemen"])
	var pair: Array[ArmyState] = [moved, other]
	var combined: Dictionary = ArmyRoster.combine(pair, pair)
	assert_true(bool(combined["ok"]))
	assert_true((combined["army"] as ArmyState).field_hospital, "one train survives")
	assert_eq(pair.size(), 1)


func test_the_train_rides_in_the_save_and_an_old_save_has_none() -> void:
	var army := ArmyState.muster(1, 0, 1, false, ["pikemen"])
	HospitalTrain.apply(army)
	var restored: ArmyState = ArmyState.from_dict(army.to_dict())
	assert_true(restored.field_hospital)
	var legacy: ArmyState = ArmyState.from_dict({"id": 2, "owner": 0, "province": 1})
	assert_false(legacy.field_hospital)


func test_the_dossier_offers_the_train_and_then_names_it() -> void:
	var model := hospital_rules_Fixture.build()
	var army := hospital_rules_Fixture.army(1, 0, 1, ["guards"])
	var panel := ArmyPanel.new()
	add_child(panel)

	var order: Dictionary = {"caption": "Pitch a field hospital (2 lumber · 1 fabric)", "ok": true}
	panel.refresh(model, army, true, false, "", [], "", "balanced", order)
	assert_true(panel._hospital.visible)
	assert_false(panel._hospital.disabled)
	var bare_food: int = panel._food(army)

	# A blocked order still shows, with the rules' reason as its caption.
	panel.refresh(
		model, army, true, false, "", [], "", "balanced",
		{"caption": "Tents are pitched on your crown's own land.", "ok": false}
	)
	assert_true(panel._hospital.visible)
	assert_true(panel._hospital.disabled)

	HospitalTrain.apply(army)
	panel.refresh(model, army, true)
	assert_true(String(panel._strength.text).contains("field hospital"), panel._strength.text)
	assert_false(panel._hospital.visible, "a served order is gone, not disabled")
	# The strength line's food is the army's own upkeep line, nurses included.
	assert_eq(panel._food(army), bare_food + HospitalTrain.food())
	assert_true(
		String(panel._strength.text).contains("%d food" % (bare_food + HospitalTrain.food())),
		panel._strength.text
	)
	panel.free()

# --- test_army_field_rules ---

func test_owned_provinces_are_reachable_and_enemy_land_must_border() -> void:
	_setup_army_field_rules()
	var army := army_field_rules_Fixture.army(1, 0, 0, ["pikemen"])
	var expected: Array[int] = [1, 2, 6]
	assert_eq(ArmyMovement.destinations(_army_field_rules_model, army), expected)

func test_owned_island_across_water_is_not_a_land_destination() -> void:
	_setup_army_field_rules()
	var army := army_field_rules_Fixture.army(1, 0, 0, ["pikemen"])
	var destinations: Array[int] = ArmyMovement.destinations(_army_field_rules_model, army)
	assert_false(destinations.has(5))
	var check: Dictionary = ArmyMovement.can_move(_army_field_rules_model, army, 5)
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("water"))
	assert_false(ArmyMovement.land_reachable(_army_field_rules_model, 0, 0).has(5))
	assert_true(ArmyMovement.land_reachable(_army_field_rules_model, 0, 0).has(1))

func test_destinations_from_the_far_colony_reach_both_neighbours() -> void:
	_setup_army_field_rules()
	var army := army_field_rules_Fixture.army(1, 0, 1, ["pikemen"])
	var expected: Array[int] = [0, 3, 4, 6]
	assert_eq(ArmyMovement.destinations(_army_field_rules_model, army), expected)

func test_the_home_army_never_marches() -> void:
	_setup_army_field_rules()
	var home := army_field_rules_Fixture.army(1, 0, 0, ["pikemen"], true)
	var none: Array[int] = []
	assert_eq(ArmyMovement.destinations(_army_field_rules_model, home), none)
	var check: Dictionary = ArmyMovement.can_move(_army_field_rules_model, home, 1)
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("Home Army"))

func test_a_moved_army_has_no_march_left() -> void:
	_setup_army_field_rules()
	var army := army_field_rules_Fixture.army(1, 0, 0, ["pikemen"])
	army.moved = true
	var none: Array[int] = []
	assert_eq(ArmyMovement.destinations(_army_field_rules_model, army), none)
	assert_false(bool(ArmyMovement.can_move(_army_field_rules_model, army, 1)["ok"]))

func test_empty_armies_cannot_march() -> void:
	_setup_army_field_rules()
	var none: Array[String] = []
	var army := army_field_rules_Fixture.army(1, 0, 0, none)
	assert_false(bool(ArmyMovement.can_move(_army_field_rules_model, army, 1)["ok"]))

func test_owned_destination_anywhere_is_legal_even_without_adjacency() -> void:
	_setup_army_field_rules()
	var army := army_field_rules_Fixture.army(1, 0, 0, ["pikemen"])
	assert_true(bool(ArmyMovement.can_move(_army_field_rules_model, army, 1)["ok"]))

func test_neutral_or_enemy_land_far_away_is_refused() -> void:
	_setup_army_field_rules()
	var army := army_field_rules_Fixture.army(1, 0, 0, ["pikemen"])
	assert_false(bool(ArmyMovement.can_move(_army_field_rules_model, army, 3)["ok"]))
	assert_true(bool(ArmyMovement.can_move(_army_field_rules_model, army, 2)["ok"]))

func test_foreign_land_needs_war_but_wilderness_does_not() -> void:
	_setup_army_field_rules()
	var army := army_field_rules_Fixture.army(1, 0, 0, ["pikemen"])
	var refused: Dictionary = ArmyMovement.can_move(_army_field_rules_model, army, 2, false)
	assert_false(bool(refused["ok"]), "province 2 belongs to faction 1")
	assert_true(String(refused["reason"]).contains("declare war"))
	assert_true(bool(ArmyMovement.can_move(_army_field_rules_model, army, 2, true)["ok"]))
	var colonist := army_field_rules_Fixture.army(2, 0, 1, ["pikemen"])
	assert_true(
		bool(ArmyMovement.can_move(_army_field_rules_model, colonist, 3, false)["ok"]),
		"unowned wilderness beside the colony is not an invasion"
	)
	var march: Dictionary = ArmyMovement.apply_move(_army_field_rules_model, army, 2, false)
	assert_false(bool(march["ok"]))
	assert_eq(army.province, 0)
	assert_false(army.moved)

func test_invalid_and_current_provinces_are_refused() -> void:
	_setup_army_field_rules()
	var army := army_field_rules_Fixture.army(1, 0, 0, ["pikemen"])
	assert_false(bool(ArmyMovement.can_move(_army_field_rules_model, army, 0)["ok"]))
	assert_false(bool(ArmyMovement.can_move(_army_field_rules_model, army, 99)["ok"]))
	assert_false(bool(ArmyMovement.can_move(_army_field_rules_model, null, 1)["ok"]))

func test_apply_move_reports_an_attack_and_spends_the_turn() -> void:
	_setup_army_field_rules()
	var army := army_field_rules_Fixture.army(1, 0, 0, ["pikemen"])
	var result: Dictionary = ArmyMovement.apply_move(_army_field_rules_model, army, 2)
	assert_true(bool(result["ok"]))
	assert_true(bool(result["attacked"]))
	assert_eq(army.province, 2)
	assert_true(army.moved)

func test_apply_move_into_own_land_is_not_an_attack() -> void:
	_setup_army_field_rules()
	var army := army_field_rules_Fixture.army(1, 0, 0, ["pikemen"])
	var result: Dictionary = ArmyMovement.apply_move(_army_field_rules_model, army, 1)
	assert_true(bool(result["ok"]))
	assert_false(bool(result["attacked"]))

func test_begin_turn_restores_one_march() -> void:
	_setup_army_field_rules()
	var first := army_field_rules_Fixture.army(1, 0, 0, ["pikemen"])
	var second := army_field_rules_Fixture.army(2, 0, 1, ["pikemen"])
	first.moved = true
	second.moved = true
	var armies: Array[ArmyState] = [first, second]
	ArmyMovement.begin_turn(armies)
	assert_false(first.moved)
	assert_false(second.moved)

func test_side_strength_aggregates_fpn_and_fpm() -> void:
	_setup_army_field_rules()
	var first := army_field_rules_Fixture.army(1, 0, 0, ["pikemen", "pikemen"])
	var second := army_field_rules_Fixture.army(2, 0, 0, ["squires"])
	var side: Array[ArmyState] = [first, second]
	assert_almost_eq(ArmyForce.side_strength(side), 14.0, 0.001)
	assert_eq(ArmyForce.side_regiments(side), 3)
	assert_almost_eq(ArmyCommand.initiative(side), 50.0 / 3.0, 0.001)

func test_contested_provinces_need_a_great_power_mover() -> void:
	_setup_army_field_rules()
	var attacker := army_field_rules_Fixture.army(1, 0, 2, ["pikemen"])
	attacker.moved = true
	var minor := army_field_rules_Fixture.army(2, 6, 2, ["pikemen"])
	minor.moved = true
	var idle := army_field_rules_Fixture.army(3, 0, 3, ["pikemen"])
	var armies: Array[ArmyState] = [attacker, minor, idle]
	var expected: Array[int] = [2]
	assert_eq(ArmyCombat.contested_provinces(_army_field_rules_model, armies), expected)

func test_unopposed_capture_flips_the_province() -> void:
	_setup_army_field_rules()
	var attacker := army_field_rules_Fixture.army(1, 0, 2, ["peasant_levies", "pikemen"])
	attacker.moved = true
	var armies: Array[ArmyState] = [attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_army_field_rules_model, armies)

	assert_eq(reports.size(), 1)
	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.CAPTURE)
	assert_true(bool(reports[0]["captured"]))
	assert_eq(_army_field_rules_model.province_owner(2), 0)
	assert_eq(attacker.count(), 2)

func test_a_third_faction_blocks_an_unopposed_capture() -> void:
	_setup_army_field_rules()
	var attacker := army_field_rules_Fixture.army(1, 0, 2, ["pikemen"])
	attacker.moved = true
	var third := army_field_rules_Fixture.army(2, 2, 2, ["pikemen"])
	var armies: Array[ArmyState] = [attacker, third]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_army_field_rules_model, armies)

	assert_eq(reports.size(), 0)
	assert_eq(_army_field_rules_model.province_owner(2), 1)

func test_attacker_victory_eliminates_the_home_army_and_flips() -> void:
	_setup_army_field_rules()
	var defender := army_field_rules_Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := army_field_rules_Fixture.army(2, 0, 2, ["guards", "guards", "guards", "guards", "guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_army_field_rules_model, armies)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	assert_true(bool(reports[0]["captured"]))
	assert_eq(_army_field_rules_model.province_owner(2), 0)
	assert_eq(defender.count(), 0)
	assert_true(armies.has(defender))
	assert_gt(attacker.count(), 0)

func test_defender_victory_wipes_the_attacker_without_a_flip() -> void:
	_setup_army_field_rules()
	var defender := army_field_rules_Fixture.army(1, 1, 2, ["guards", "guards", "guards", "guards", "guards"])
	var attacker := army_field_rules_Fixture.army(2, 0, 2, ["peasant_levies"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_army_field_rules_model, armies)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.DEFENDER_VICTORY)
	assert_eq(_army_field_rules_model.province_owner(2), 1)
	assert_false(armies.has(attacker))
	assert_gt(defender.count(), 0)

func test_matched_large_armies_stalemate() -> void:
	_setup_army_field_rules()
	var defender := army_field_rules_Fixture.army(1, 1, 2, _army_field_rules_repeat("peasant_levies", 10))
	var attacker := army_field_rules_Fixture.army(2, 0, 2, _army_field_rules_repeat("peasant_levies", 10))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_army_field_rules_model, armies)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.STALEMATE)
	assert_eq(_army_field_rules_model.province_owner(2), 1)
	assert_gt(defender.count(), 0)
	assert_gt(attacker.count(), 0)

func test_defending_armies_share_one_side() -> void:
	_setup_army_field_rules()
	var first := army_field_rules_Fixture.army(1, 1, 2, ["peasant_levies", "peasant_levies"])
	var second := army_field_rules_Fixture.army(2, 1, 2, ["peasant_levies", "peasant_levies"])
	var side: Array[ArmyState] = ArmyForce.armies_of([first, second], 2, 1)
	assert_almost_eq(ArmyForce.side_strength(side), 12.0, 0.001)
	assert_eq(ArmyForce.side_regiments(side), 4)

func test_cavalry_wins_the_initiative_order() -> void:
	_setup_army_field_rules()
	var foot := army_field_rules_Fixture.army(1, 1, 3, ["peasant_levies"])
	foot.moved = true
	var horse := army_field_rules_Fixture.army(2, 2, 3, ["squires"])
	horse.moved = true
	var armies: Array[ArmyState] = [foot, horse]
	var expected: Array[int] = [2, 1]
	assert_eq(ArmyCombat.ordered_attackers(armies, 3, MapModel.NO_ID), expected)

func test_equal_initiative_is_broken_by_a_seeded_battle_roll() -> void:
	_setup_army_field_rules()
	var defender := army_field_rules_Fixture.army(1, 1, 2, ["peasant_levies"])
	var lower := army_field_rules_Fixture.army(2, 2, 2, ["pikemen"])
	lower.moved = true
	var higher := army_field_rules_Fixture.army(3, 0, 2, ["pikemen"])
	higher.moved = true
	var armies: Array[ArmyState] = [defender, lower, higher]

	# Same initiative: the wiki wants one deterministic roll per battle context,
	# not the lexical faction id (combat § Initiative, § Multi-Attacker Chain).
	var first: Array[int] = ArmyCombat.ordered_attackers(armies, 2, 1, {"seed": 0})
	var again: Array[int] = ArmyCombat.ordered_attackers(armies, 2, 1, {"seed": 0})
	var other: Array[int] = ArmyCombat.ordered_attackers(armies, 2, 1, {"seed": 1})

	assert_eq(first, again, "identical state reproduces the same chain order")
	assert_eq(first, [2, 0], "the seeded roll, not faction id, decides the tie")
	assert_eq(other, [0, 2], "a different combat seed may flip the tied order")
	assert_eq(ArmyCombat.ordered_attackers(armies, 2, 1), first, "the default seed is 0")

func test_general_medals_add_to_initiative() -> void:
	_setup_army_field_rules()
	var horse: Array[ArmyState] = [army_field_rules_Fixture.army(1, 0, 3, ["squires"])]
	assert_almost_eq(ArmyCommand.initiative(horse), 50.0, 0.001)
	assert_almost_eq(ArmyCommand.initiative(horse, 2), 70.0, 0.001)

func test_medal_aura_redistributes_casualties() -> void:
	_setup_army_field_rules()
	var defender := army_field_rules_Fixture.army(1, 1, 2, _army_field_rules_repeat("peasant_levies", 10))
	var attacker := army_field_rules_Fixture.army(2, 0, 2, _army_field_rules_repeat("peasant_levies", 10))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var roster := GeneralRoster.new()
	roster.pool(0)
	for _index in 4:
		roster.award(0, "general_1")
	var context: Dictionary = {"roster": roster, "army_general": {attacker.id: "general_1"}}

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_army_field_rules_model, armies, context)

	assert_eq(int(reports[0]["attacker_medals"]), 4)
	assert_gt(
		(reports[0]["defender_lost"] as Array).size(),
		(reports[0]["attacker_lost"] as Array).size()
	)

func test_mutual_annihilation_recovers_a_garrison_for_the_next_attacker() -> void:
	_setup_army_field_rules()
	var defender := army_field_rules_Fixture.army(1, 1, 2, ["guards"], true)
	var first := army_field_rules_Fixture.army(2, 0, 2, ["peasant_levies"])
	first.moved = true
	var second := army_field_rules_Fixture.army(3, 2, 2, ["peasant_levies"])
	second.moved = true
	var armies: Array[ArmyState] = [defender, first, second]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_army_field_rules_model, armies)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.MUTUAL_ANNIHILATION)
	assert_eq(int(reports[0]["garrison"]), 1)
	assert_eq(String(reports[0]["recovered_type"]), "guards")
	assert_eq(_army_field_rules_model.province_owner(2), 1)

func test_mutual_annihilation_without_further_attackers_leaves_the_province_empty() -> void:
	_setup_army_field_rules()
	var defender := army_field_rules_Fixture.army(1, 1, 2, ["guards"], true)
	var attacker := army_field_rules_Fixture.army(2, 0, 2, ["peasant_levies"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_army_field_rules_model, armies)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.MUTUAL_ANNIHILATION)
	assert_eq(int(reports[0]["garrison"]), 0)
	assert_eq(_army_field_rules_model.province_owner(2), 1)
	assert_eq(defender.count(), 0)

## A Minor Nation reforms its garrison at its effective military era, which the
## Minor Regiment Upgrade phase sets to the leading Great Power's level (wiki:
## combat § Garrison recovery type; factions § Minor military parity).
func test_a_minor_nations_reformed_garrison_keeps_its_parity_era() -> void:
	_setup_army_field_rules()
	_army_field_rules_model.get_province(2).owner = 6
	var defender := army_field_rules_Fixture.army(1, 6, 2, ["guards"], true)
	var first := army_field_rules_Fixture.army(2, 0, 2, ["peasant_levies"])
	first.moved = true
	var second := army_field_rules_Fixture.army(3, 2, 2, ["peasant_levies"])
	second.moved = true
	var armies: Array[ArmyState] = [defender, first, second]
	var context: Dictionary = {"parity_era": 4}

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_army_field_rules_model, armies, context)

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.MUTUAL_ANNIHILATION)
	assert_eq(int(reports[0]["garrison"]), 1)
	assert_eq(String(reports[0]["recovered_type"]), "guards")

## Tribes get no parity: their effective military era is always 1 (wiki:
## combat § Garrison recovery type; factions § Tribes).
func test_a_tribes_reformed_garrison_stays_at_era_one() -> void:
	_setup_army_field_rules()
	_army_field_rules_model.get_province(2).owner = 9
	var defender := army_field_rules_Fixture.army(1, 9, 2, ["guards"], true)
	var first := army_field_rules_Fixture.army(2, 0, 2, ["peasant_levies"])
	first.moved = true
	var second := army_field_rules_Fixture.army(3, 2, 2, ["peasant_levies"])
	second.moved = true
	var armies: Array[ArmyState] = [defender, first, second]
	var context: Dictionary = {"parity_era": 4}

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(_army_field_rules_model, armies, context)

	assert_eq(int(reports[0]["garrison"]), 1)
	assert_eq(String(reports[0]["recovered_type"]), RegimentCatalog.garrison_type_for(1))

func test_recovery_era_follows_the_faction_type() -> void:
	_setup_army_field_rules()
	assert_eq(ArmyGarrison.era_for(1, {"parity_era": 1}), ArmyGarrison.GREAT_POWER_ERA)
	assert_eq(ArmyGarrison.era_for(6, {"parity_era": 3}), 3)
	assert_eq(ArmyGarrison.era_for(6, {}), ArmyGarrison.MINOR_ERA)
	assert_eq(ArmyGarrison.era_for(9, {"parity_era": 4}), ArmyGarrison.MINOR_ERA)

func test_ratio_bands_follow_the_documented_fractions() -> void:
	_setup_army_field_rules()
	assert_almost_eq(float(ArmyBands.for_ratio(2.0)["attacker"]), 0.15, 0.001)
	assert_almost_eq(float(ArmyBands.for_ratio(2.0)["defender"]), 1.0, 0.001)
	assert_almost_eq(float(ArmyBands.for_ratio(1.2)["attacker"]), 0.3, 0.001)
	assert_almost_eq(float(ArmyBands.for_ratio(0.8)["attacker"]), 0.5, 0.001)
	assert_almost_eq(float(ArmyBands.for_ratio(0.5)["attacker"]), 1.0, 0.001)

func test_the_067_boundary_belongs_to_the_defender_victory_band() -> void:
	_setup_army_field_rules()
	# wiki: combat § Auto-resolve ratio bands — `ratio <= 0.67` loses 1.0/0.15,
	# while the `0.67 < ratio < 1.0` row starts strictly above 0.67.
	assert_almost_eq(float(ArmyBands.for_ratio(0.67)["attacker"]), 1.0, 0.001)
	assert_almost_eq(float(ArmyBands.for_ratio(0.67)["defender"]), 0.15, 0.001)
	assert_almost_eq(float(ArmyBands.for_ratio(0.68)["attacker"]), 0.5, 0.001)

func test_great_powers_recover_era_four_infantry() -> void:
	_setup_army_field_rules()
	assert_eq(ArmyGarrison.era_for(0), ArmyGarrison.GREAT_POWER_ERA)
	assert_eq(ArmyGarrison.era_for(6), ArmyGarrison.MINOR_ERA)
	assert_eq(ArmyGarrison.era_for(9), ArmyGarrison.MINOR_ERA)

func test_outcome_labels_cover_every_result() -> void:
	_setup_army_field_rules()
	assert_eq(ArmyCombat.outcome_label(ArmyCombat.Outcome.ATTACKER_VICTORY), "attacker victory")
	assert_eq(ArmyCombat.outcome_label(ArmyCombat.Outcome.DEFENDER_VICTORY), "defender victory")
	assert_eq(ArmyCombat.outcome_label(ArmyCombat.Outcome.STALEMATE), "stalemate")
	assert_eq(
		ArmyCombat.outcome_label(ArmyCombat.Outcome.MUTUAL_ANNIHILATION),
		"mutual annihilation"
	)
	assert_eq(ArmyCombat.outcome_label(ArmyCombat.Outcome.CAPTURE), "province captured")

func test_peaceful_factions_do_not_fight() -> void:
	_setup_army_field_rules()
	var defender := army_field_rules_Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := army_field_rules_Fixture.army(2, 0, 2, ["guards", "guards", "guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var at_peace := func(_a: int, _b: int) -> bool: return false

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(
		_army_field_rules_model, armies, {"hostile": at_peace}
	)

	assert_eq(reports.size(), 0, "peace holds: no battle, no capture")
	assert_eq(_army_field_rules_model.province_owner(2), 1)
	assert_eq(attacker.count(), 3)
	assert_eq(defender.count(), 1)
	var at_war := func(_a: int, _b: int) -> bool: return true
	var battles: Array[Dictionary] = ArmyCombat.resolve_turn(_army_field_rules_model, armies, {"hostile": at_war})
	assert_eq(battles.size(), 1, "declared war fights")
	assert_eq(_army_field_rules_model.province_owner(2), 0)

func _army_field_rules_repeat(type_id: String, count: int) -> Array[String]:
	var types: Array[String] = []
	for _index in count:
		types.append(type_id)
	return types

func test_each_military_tech_names_the_type_its_regiment_replaces() -> void:
	_setup_army_field_rules()
	var expected: Dictionary = {
		"organised_regiments": ["knights", "lancers"],
		"improved_iron_weapons": ["pikemen", "halberdiers"],
		"improved_infantry_tactics": ["peasant_levies", "calivermen"],
		"bayonet": ["halberdiers", "regulars"],
		"weapon_craftsmanship": ["arquebusiers", "musketeers"],
		"explosives": ["musketeers", "grenadiers"],
		"early_rifles": ["calivermen", "skirmishers"],
		"long_range_rifles": ["skirmishers", "sharpshooters"],
		"needle_guns": ["regulars", "rifle_infantry"],
		"elite_military_training": ["grenadiers", "guards"],
		"recruit_steppe_horsemen": ["squires", "cossacks"],
		"hussars": ["cossacks", "hussars"],
		"scouting": ["hussars", "scouts"],
		"improved_cavalry_weapons": ["harquebusiers", "cuirassiers"],
		"repeating_cavalry_carbine": ["cuirassiers", "carbine_cavalry"],
		"siege_engineering": ["culverin", "royal_artillery"],
		"light_artillery_tactics": ["horse_artillery", "light_artillery"],
		"heavy_artillery": ["royal_artillery", "heavy_artillery"],
		"field_artillery_tactics": ["light_artillery", "field_artillery"],
		"high_grade_steel": ["heavy_artillery", "siege_guns"],
	}
	for tech_id: Variant in expected.keys():
		var path: Dictionary = RegimentUpgrades.path_for(String(tech_id))
		var pair: Array = expected[tech_id]
		assert_eq(String(path.get("from", "")), String(pair[0]), String(tech_id))
		assert_eq(String(path.get("to", "")), String(pair[1]), String(tech_id))
		assert_eq(
			String(path.get("name", "")),
			"%s upgrade path" % RegimentCatalog.display_name(String(pair[0])),
			String(tech_id)
		)

func test_the_first_type_of_a_branch_and_its_dependants_open_no_path() -> void:
	_setup_army_field_rules()
	assert_true(RegimentUpgrades.path_for("improved_cavalry_tactics").is_empty())
	assert_true(RegimentUpgrades.path_for("horse_artillery").is_empty())
	assert_true(RegimentUpgrades.path_for("crucible_process").is_empty())
	assert_true(RegimentUpgrades.path_for("modern_forts").is_empty())
	assert_true(RegimentUpgrades.path_for("").is_empty())

func test_bowmen_knights_and_lancers_sit_at_the_top_of_their_ladders() -> void:
	_setup_army_field_rules()
	assert_eq(RegimentUpgrades.previous_type("bowmen"), "")
	assert_eq(RegimentUpgrades.previous_type("lancers"), "knights")
	assert_eq(RegimentUpgrades.previous_type("scouts"), "hussars")
	assert_eq(RegimentUpgrades.previous_type("not_a_regiment"), "")

func test_the_newest_buildable_type_in_the_category_wins() -> void:
	_setup_army_field_rules()
	assert_eq(RegimentUpgrades.target_type("pikemen", {}), "pikemen")
	assert_eq(
		RegimentUpgrades.target_type("pikemen", {"improved_iron_weapons": true}),
		"halberdiers"
	)
	assert_eq(
		RegimentUpgrades.target_type(
			"pikemen", {"improved_iron_weapons": true, "bayonet": true}
		),
		"regulars",
		"a court never stops at the first rung"
	)
	assert_eq(
		RegimentUpgrades.target_type("squires", {"bayonet": true}),
		"squires",
		"another branch's research never re-equips this one"
	)

func test_apply_re_equips_great_power_regiments_in_place() -> void:
	_setup_army_field_rules()
	var power: int = FactionCatalog.PLAYER_FACTION
	var other: int = FactionCatalog.great_power_ids()[1]
	var regions := MapRegionTable.new()
	var army: ArmyState = ArmyState.muster(1, power, 0, true, ["pikemen", "bowmen"], 1)
	var rival: ArmyState = ArmyState.muster(2, other, 0, true, ["squires"], 10)
	regions.set_region(0, [army, rival])

	var pikemen: String = army.regiments[0]
	var bowmen: String = army.regiments[1]
	var squires: String = rival.regiments[0]
	var report: Dictionary = RegimentUpgrades.apply(regions, {
		power: {"improved_iron_weapons": true},
		other: {"recruit_steppe_horsemen": true},
	})

	assert_eq(int(report["count"]), 2)
	assert_eq(int((report["by_faction"] as Dictionary).get(power, 0)), 1)
	assert_eq(army.type_of(pikemen), "halberdiers")
	assert_eq(army.type_of(bowmen), "bowmen", "bowmen have no upgrade path")
	assert_eq(rival.type_of(squires), "cossacks", "rivals re-equip off their own techs")
	assert_eq(army.regiments, [pikemen, bowmen], "instance ids never change")

func test_a_re_equipped_regiment_keeps_its_health_inside_the_new_pool() -> void:
	_setup_army_field_rules()
	var power: int = FactionCatalog.PLAYER_FACTION
	var whole: ArmyState = ArmyState.muster(1, power, 0, true, ["pikemen"], 1)
	var mauled: ArmyState = ArmyState.muster(2, power, 0, false, ["pikemen"], 10)
	var veteran: String = mauled.regiments[0]
	mauled.regiment_health[veteran] = RegimentCatalog.max_health("pikemen") / 2
	var regions := MapRegionTable.new()
	regions.set_region(0, [whole, mauled])

	RegimentUpgrades.apply(regions, {power: {"improved_iron_weapons": true}})

	for army: ArmyState in [whole, mauled]:
		var data: Dictionary = army.condition_of(army.regiments[0])
		assert_eq(String(data["type"]), "halberdiers")
		assert_eq(
			int(data["max"]), RegimentCatalog.max_health("halberdiers"),
			"the pool is the new type's, not the old one kept by a stale max"
		)
	assert_eq(
		int(whole.condition_of(whole.regiments[0])["hp"]),
		RegimentCatalog.max_health("halberdiers"),
		"an untouched regiment re-equips at full strength"
	)
	assert_true(
		float(mauled.condition_of(veteran)["fraction"]) < 1.0,
		"a mauled veteran keeps its wounds through the re-equip"
	)


func test_apply_skips_minors_tribes_and_courts_with_nothing_new() -> void:
	_setup_army_field_rules()
	var minor: int = FactionCatalog.minor_ids()[0]
	var tribe: int = FactionCatalog.tribe_ids()[0]
	var power: int = FactionCatalog.PLAYER_FACTION
	var regions := MapRegionTable.new()
	var minor_army: ArmyState = ArmyState.muster(1, minor, 0, true, ["pikemen"], 1)
	var tribe_army: ArmyState = ArmyState.muster(2, tribe, 0, true, ["pikemen"], 10)
	var power_army: ArmyState = ArmyState.muster(3, power, 0, true, ["pikemen"], 20)
	regions.set_region(0, [minor_army, tribe_army, power_army])

	var report: Dictionary = RegimentUpgrades.apply(regions, {
		power: {"bayonet": true},
		minor: {"bayonet": true},
		tribe: {"bayonet": true},
	})

	assert_eq(int(report["count"]), 1)
	assert_eq(power_army.type_of(power_army.regiments[0]), "regulars")
	assert_eq(
		minor_army.type_of(minor_army.regiments[0]), "pikemen",
		"Minors follow the parity pass"
	)
	assert_eq(tribe_army.type_of(tribe_army.regiments[0]), "pikemen")
	assert_eq(int(RegimentUpgrades.apply(null, {})["count"]), 0)

# --- test_army_regiment_names ---

func test_every_muster_names_its_regiments_from_the_crown_pool() -> void:
	var army := ArmyState.muster(1, 0, 2, false, ["pikemen", "musketeers"], 1)

	for regiment_id: String in army.regiments:
		var title: String = RegimentNames.of(army, regiment_id)
		assert_false(title.is_empty(), "a mustered regiment is never anonymous")
		assert_true(
			RegimentNames.pool_for(0).has(title),
			"Spain christens from its own pool, got '%s'" % title
		)

func test_a_reload_speaks_the_same_titles() -> void:
	var army := ArmyState.muster(1, 0, 2, false, ["pikemen", "musketeers"], 1)
	var before: Dictionary = {}
	for regiment_id: String in army.regiments:
		before[regiment_id] = RegimentNames.of(army, regiment_id)

	var restored: ArmyState = ArmyState.from_dict(army.to_dict())

	for regiment_id: String in restored.regiments:
		assert_eq(RegimentNames.of(restored, regiment_id), String(before[regiment_id]))

func test_no_army_wears_the_same_title_twice() -> void:
	var army := ArmyState.muster(1, 0, 2, false, [], 1)
	for index in range(14):
		army.add_regiment("unit_%d" % (index + 1), "pikemen")

	var titles: Array[String] = []
	var numbered: bool = false
	for regiment_id: String in army.regiments:
		var title: String = RegimentNames.of(army, regiment_id)
		assert_false(titles.has(title), "'%s' is worn twice" % title)
		if title.ends_with(" II"):
			numbered = true
		titles.append(title)
	# Past the ten-title pool the repeats are numbered, never duplicated.
	assert_true(numbered, "a repeat is numbered, not duplicated")

func test_a_crown_with_no_pool_still_names_its_regiments() -> void:
	var army := ArmyState.muster(1, 9, 2, false, ["peasant_levies"], 1)

	assert_true(RegimentNames.GENERIC.has(RegimentNames.of(army, "unit_1")))

func test_a_detached_regiment_keeps_its_title_and_record() -> void:
	var army := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen", "pikemen", "pikemen"])
	army.regiment_engagements["unit_102"] = 3
	army.regiment_wins["unit_102"] = 2
	var title: String = RegimentNames.of(army, "unit_102")
	var armies: Array[ArmyState] = [army]

	var result: Dictionary = ArmyRoster.split(armies, army, ["unit_102"], 2)

	assert_true(bool(result["ok"]), String(result["reason"]))
	var detached: ArmyState = result["army"] as ArmyState
	assert_eq(RegimentNames.of(detached, "unit_102"), title, "the veteran keeps its title")
	assert_eq(int(RegimentRecord.of(detached, "unit_102")["engagements"]), 3)
	assert_eq(int(RegimentRecord.of(detached, "unit_102")["wins"]), 2)

func test_a_combined_army_keeps_each_regiments_title_and_record() -> void:
	var first := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen"], true)
	var second := army_regiment_names_Fixture.army(2, 0, 2, ["musketeers"])
	second.regiment_engagements["unit_201"] = 1
	second.regiment_wins["unit_201"] = 1
	var title: String = RegimentNames.of(second, "unit_201")
	var armies: Array[ArmyState] = [first, second]

	var result: Dictionary = ArmyRoster.combine(armies, [first, second])

	assert_true(bool(result["ok"]), String(result["reason"]))
	var target: ArmyState = result["army"] as ArmyState
	assert_eq(RegimentNames.of(target, "unit_201"), title)
	assert_eq(int(RegimentRecord.of(target, "unit_201")["wins"]), 1)

func test_a_battle_is_written_into_every_survivors_record() -> void:
	var model := army_regiment_names_Fixture.build()
	var defender := army_regiment_names_Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := army_regiment_names_Fixture.army(2, 0, 2, ["guards", "guards", "guards", "guards", "guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, {})

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	assert_false(attacker.is_empty(), "the winner keeps its standing regiments")
	for regiment_id: String in attacker.regiments:
		var record: Dictionary = RegimentRecord.of(attacker, regiment_id)
		assert_eq(int(record["engagements"]), 1, "one engagement is written down")
		assert_eq(int(record["wins"]), 1, "the field was won")
		assert_true(
			RegimentRecord.line(attacker, regiment_id).contains("1 engagement"),
			"the dossier line reads the same tally"
		)

func test_a_standoff_counts_an_engagement_but_no_win() -> void:
	var army := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen"])
	var side: Array[ArmyState] = [army]

	RegimentRecord.note_battle(side, false)
	RegimentRecord.note_battle(side, true)

	var record: Dictionary = RegimentRecord.of(army, "unit_101")
	assert_eq(int(record["engagements"]), 2)
	assert_eq(int(record["wins"]), 1)

func test_the_dossier_line_is_empty_until_a_regiment_is_blooded() -> void:
	var army := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen"])

	assert_eq(RegimentRecord.line(army, "unit_101"), "")

	army.regiment_engagements["unit_101"] = 4
	army.regiment_wins["unit_101"] = 3

	assert_eq(RegimentRecord.line(army, "unit_101"), "4 engagements · 3 won")

func test_an_old_save_is_christened_on_load() -> void:
	var army := ArmyState.muster(1, 0, 2, false, ["pikemen", "musketeers"], 1)
	var expected: Dictionary = {}
	for regiment_id: String in army.regiments:
		expected[regiment_id] = RegimentNames.of(army, regiment_id)
	var data: Dictionary = army.to_dict()
	data.erase("regiment_names")
	data.erase("regiment_engagements")
	data.erase("regiment_wins")

	var restored: ArmyState = ArmyState.from_dict(data)

	for regiment_id: String in restored.regiments:
		assert_eq(
			RegimentNames.of(restored, regiment_id),
			String(expected[regiment_id]),
			"the same arithmetic christens the same title"
		)
		assert_eq(int(RegimentRecord.of(restored, regiment_id)["engagements"]), 0)

func test_the_aftermath_names_a_mauled_regiment() -> void:
	var army := army_regiment_names_Fixture.army(1, 0, 2, ["guards"])
	var side: Array[ArmyState] = [army]

	var entries: Array[Dictionary] = RegimentCondition.entries(side)

	assert_eq(entries.size(), 1)
	assert_eq(String(entries[0]["name"]), RegimentNames.of(army, "unit_101"))



# --- battle honours beyond the chevron (wiki: naming § Regiment records;
# DR-20261112-02) ---


func test_a_won_battle_adds_the_province_to_every_surviving_colour() -> void:
	var model := army_regiment_names_Fixture.build()
	var defender := army_regiment_names_Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := army_regiment_names_Fixture.army(2, 0, 2, ["guards", "guards", "guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, {})

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	assert_eq(int(reports[0]["attacker_honours"]), attacker.count(), "every colour takes it")
	assert_eq(int(reports[0]["defender_honours"]), 0, "a broken side takes no colour")
	assert_true(defender.is_empty(), "the beaten side had no survivor to honour")
	for regiment_id: String in attacker.regiments:
		assert_eq(RegimentRecord.colours(attacker, regiment_id), [2])



func test_a_standoff_and_a_defeat_take_no_honour() -> void:
	var attacker := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen"])
	var defender := army_regiment_names_Fixture.army(2, 1, 2, ["pikemen"], true)
	var standoff: Dictionary = {"province": 2, "outcome": ArmyCombat.Outcome.STALEMATE}
	var beaten: Dictionary = {"province": 2, "outcome": ArmyCombat.Outcome.DEFENDER_VICTORY}

	RegimentCondition.attach(standoff, [attacker], [defender], 0, 1)
	RegimentCondition.attach(beaten, [attacker], [defender], 0, 1)

	assert_eq(int(standoff["attacker_honours"]), 0, "a standoff wins no field")
	assert_eq(int(beaten["attacker_honours"]), 0, "the beaten side takes nothing")
	assert_eq(int(beaten["defender_honours"]), 1)
	assert_true(RegimentRecord.colours(attacker, "unit_101").is_empty())
	assert_eq(RegimentRecord.colours(defender, "unit_201"), [2])



func test_a_province_is_borne_once_and_the_newest_leads() -> void:
	var army := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen"])
	var side: Array[ArmyState] = [army]

	RegimentRecord.award_honours(side, 2)
	RegimentRecord.award_honours(side, 6)
	RegimentRecord.award_honours(side, 6)

	assert_eq(RegimentRecord.colours(army, "unit_101"), [6, 2])
	assert_eq(int(RegimentRecord.of(army, "unit_101")["honours"].size()), 2)



func test_the_colours_survive_a_detach_and_a_save() -> void:
	var army := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen", "pikemen"])
	var side: Array[ArmyState] = [army]
	RegimentRecord.award_honours(side, 2)
	var armies: Array[ArmyState] = [army]

	var result: Dictionary = ArmyRoster.split(armies, army, ["unit_101"], 2)

	assert_true(bool(result["ok"]), String(result["reason"]))
	var detached: ArmyState = result["army"] as ArmyState
	assert_eq(RegimentRecord.colours(detached, "unit_101"), [2], "the colour travels")
	var restored: ArmyState = ArmyState.from_dict(detached.to_dict())
	assert_eq(RegimentRecord.colours(restored, "unit_101"), [2], "the save carries it")



func test_the_dossier_line_names_the_colours() -> void:
	var model := army_regiment_names_Fixture.build()
	var army := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen"])
	var side: Array[ArmyState] = [army]
	army.regiment_engagements["unit_101"] = 5
	army.regiment_wins["unit_101"] = 4
	for province: int in [2, 6, 4, 0]:
		RegimentRecord.award_honours(side, province)

	assert_eq(
		RegimentRecord.line(army, "unit_101", model),
		"5 engagements · 4 won · Province 0 · Province 4 · +2 more",
		"the two newest colours, then the count of the rest"
	)
	assert_eq(
		RegimentRecord.line(army, "unit_101"),
		"5 engagements · 4 won",
		"without a chart the tally stands alone"
	)



func test_an_unhonoured_regiment_reads_only_its_tally() -> void:
	var model := army_regiment_names_Fixture.build()
	var army := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen"])
	army.regiment_engagements["unit_101"] = 1

	assert_eq(RegimentRecord.honour_line(army, "unit_101", model), "")
	assert_eq(RegimentRecord.line(army, "unit_101", model), "1 engagement · 0 won")


# --- citations and the despatch a regiment holds (wiki: naming § Regiment
# records; DR-20261112-10) ---


func test_a_won_field_is_written_into_every_survivors_despatch() -> void:
	var model := army_regiment_names_Fixture.build()
	var defender := army_regiment_names_Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := army_regiment_names_Fixture.army(2, 0, 2, ["guards", "guards", "guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, {})

	var report: Dictionary = reports[0]
	assert_eq(int(report["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	var bled: int = 0
	for entry: Dictionary in report["attacker_health"]:
		if float(entry["fraction"]) < 1.0:
			bled += 1
	assert_eq(int(report["attacker_citations"]), bled, "every mauled colour is cited")
	assert_eq(int(report["defender_citations"]), 0, "a broken side takes no citation")
	for regiment_id: String in attacker.regiments:
		var fields: Array = RegimentDecorations.history(attacker, regiment_id)
		assert_eq(fields.size(), 1, "the field is written once")
		assert_eq(int(fields[0]["p"]), 2, "the field's province is kept")
		assert_true(bool(fields[0]["w"]), "the side won it")


func test_a_clean_win_cites_nobody_but_still_writes_the_field() -> void:
	var attacker := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen"])
	var defender := army_regiment_names_Fixture.army(2, 1, 2, ["pikemen"], true)
	var won: Dictionary = {"province": 2, "outcome": ArmyCombat.Outcome.ATTACKER_VICTORY}

	RegimentCondition.attach(won, [attacker], [defender], 1, 0)

	assert_eq(int(won["attacker_citations"]), 0, "no colour bled, none is cited")
	assert_eq(RegimentDecorations.citations(attacker, "unit_101"), 0)
	var fields: Array = RegimentDecorations.history(attacker, "unit_101")
	assert_eq(fields.size(), 1, "the field is still on the record")
	assert_true(bool(fields[0]["w"]))
	assert_false(bool(fields[0]["c"]), "an untouched colour is not cited")


func test_a_lost_field_counts_but_cites_nothing() -> void:
	var attacker := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen"])
	var defender := army_regiment_names_Fixture.army(2, 1, 2, ["pikemen"], true)
	var beaten: Dictionary = {"province": 2, "outcome": ArmyCombat.Outcome.DEFENDER_VICTORY}

	RegimentCondition.attach(beaten, [attacker], [defender], 0, 1)

	assert_eq(int(beaten["attacker_citations"]), 0)
	assert_eq(int(beaten["defender_citations"]), 0, "a clean defence cites nobody")
	assert_false(bool(RegimentDecorations.history(attacker, "unit_101")[0]["w"]))
	assert_true(bool(RegimentDecorations.history(defender, "unit_201")[0]["w"]))


func test_the_despatch_keeps_the_newest_fields_and_the_tally_counts_all() -> void:
	var army := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen"])
	var side: Array[ArmyState] = [army]
	for province: int in 12:
		RegimentRecord.note_battle(side, true)
		RegimentDecorations.note(side, province, true)

	var fields: Array = RegimentDecorations.history(army, "unit_101")
	assert_eq(fields.size(), RegimentDecorations.KEPT, "the despatch is bounded")
	assert_eq(int(fields[0]["p"]), 11, "newest first")
	assert_eq(int(fields[fields.size() - 1]["p"]), 12 - RegimentDecorations.KEPT)
	assert_eq(int(RegimentRecord.of(army, "unit_101")["engagements"]), 12, "the tally counts all")


func test_the_ladder_names_a_cited_and_a_laurelled_regiment() -> void:
	var model := army_regiment_names_Fixture.build()
	var army := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen", "pikemen"])
	var side: Array[ArmyState] = [army]
	var top: int = int(army.condition_of("unit_101")["max"])

	RegimentRecord.note_battle(side, true)
	RegimentDecorations.note(side, 2, true)
	assert_eq(RegimentDecorations.rank(army, "unit_101"), "", "a clean win cites nobody")
	assert_eq(
		RegimentDecorations.line(army, "unit_101", model),
		"History — Province 2 won",
		"an undecorated record still names the field"
	)

	army.regiment_health["unit_101"] = top / 2
	RegimentRecord.note_battle(side, true)
	RegimentDecorations.note(side, 6, true)
	assert_eq(RegimentDecorations.citations(army, "unit_101"), 1)
	assert_eq(RegimentDecorations.rank(army, "unit_101"), "cited")
	assert_eq(
		RegimentDecorations.line(army, "unit_101", model),
		"Cited +5% — Province 6 won · Province 2 won",
		"the decoration leads the despatch and names the weight it buys"
	)

	RegimentRecord.note_battle(side, true)
	RegimentDecorations.note(side, 4, true)
	RegimentRecord.note_battle(side, true)
	RegimentDecorations.note(side, 0, true)
	assert_eq(RegimentDecorations.citations(army, "unit_101"), RegimentDecorations.LAUREL_AT)
	assert_eq(RegimentDecorations.rank(army, "unit_101"), "laurelled")
	assert_eq(
		RegimentDecorations.line(army, "unit_101", model),
		"Laurelled +10% — Province 0 won · Province 4 won · +2 earlier",
		"two newest fields, then the fields the record still counts"
	)


func test_a_green_regiment_holds_no_despatch() -> void:
	var model := army_regiment_names_Fixture.build()
	var army := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen"])

	assert_true(RegimentDecorations.history(army, "unit_101").is_empty())
	assert_eq(RegimentDecorations.rank(army, "unit_101"), "")
	assert_eq(RegimentDecorations.line(army, "unit_101", model), "", "a fresh roster stays short")


func test_a_citation_survives_a_detach_and_a_save() -> void:
	var army := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen", "pikemen"])
	var side: Array[ArmyState] = [army]
	army.regiment_health["unit_101"] = int(army.condition_of("unit_101")["max"]) / 2
	RegimentDecorations.note(side, 2, true)
	var armies: Array[ArmyState] = [army]

	var result: Dictionary = ArmyRoster.split(armies, army, ["unit_101"], 2)

	assert_true(bool(result["ok"]), String(result["reason"]))
	var detached: ArmyState = result["army"] as ArmyState
	assert_eq(RegimentDecorations.citations(detached, "unit_101"), 1, "the citation travels")
	var restored: ArmyState = ArmyState.from_dict(detached.to_dict())
	assert_eq(RegimentDecorations.citations(restored, "unit_101"), 1, "the save carries it")
	assert_eq(int(RegimentDecorations.history(restored, "unit_101")[0]["p"]), 2)
	assert_eq(RegimentDecorations.rank(army, "unit_102"), "", "the colour left behind is bare")

# --- what a citation buys: weight in the line (wiki: combat § Strength;
# DR-20261113-04) ---


func test_a_citation_weighs_half_a_chevron_and_the_laurel_a_whole_one() -> void:
	var army := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen"])
	var side: Array[ArmyState] = [army]

	assert_eq(
		RegimentDecorations.strength_multiplier(army, "unit_101"), 1.0,
		"a colours the crown never named weighs nothing extra"
	)
	var top: int = int(army.condition_of("unit_101")["max"])
	army.regiment_health["unit_101"] = top / 2
	RegimentDecorations.note(side, 2, true)
	assert_almost_eq(
		RegimentDecorations.strength_multiplier(army, "unit_101"),
		1.0 + RegimentDecorations.CITED_STEP, 0.0001,
		"one citation is half a chevron"
	)
	RegimentDecorations.note(side, 3, true)
	RegimentDecorations.note(side, 4, true)
	assert_eq(RegimentDecorations.rank(army, "unit_101"), "laurelled")
	assert_almost_eq(
		RegimentDecorations.strength_multiplier(army, "unit_101"),
		1.0 + RegimentDecorations.LAUREL_STEP, 0.0001,
		"the laurel is worth the whole chevron"
	)


func test_a_decorated_colour_weighs_its_step_in_the_side_strength() -> void:
	var army := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen", "pikemen"])
	var side: Array[ArmyState] = [army]
	_cite_and_heal(army, "unit_102")

	var plain: float = ArmyModifiers.rank_of("pikemen", 0, 1.0)

	assert_almost_eq(
		ArmyModifiers.strength(side, 10, 1.0),
		plain * 2.0 + plain * RegimentDecorations.CITED_STEP, 0.0001,
		"only the cited colour's rank carries the step"
	)
	var line: Array[Dictionary] = ArmyModifiers.deployed(side, 1)
	assert_eq(
		String(line[0]["id"]), "unit_102",
		"the cited colours holds the line over a bare twin"
	)


func test_the_cited_colour_is_the_last_to_fall() -> void:
	var army := army_regiment_names_Fixture.army(1, 0, 2, ["pikemen", "pikemen"])
	var side: Array[ArmyState] = [army]
	var armies: Array[ArmyState] = [army]
	_cite_and_heal(army, "unit_102")

	var lost: Array[String] = ArmyForce.apply_losses(armies, side, 1)

	assert_eq(lost.size(), 1)
	assert_eq(lost[0], "unit_101", "the bare colour goes first, the decorated one holds")


## A citation is won mauled, so the colours are healed back to full before the
## weight is read: only the decoration tells the twins apart.
func _cite_and_heal(army: ArmyState, regiment_id: String) -> void:
	var side: Array[ArmyState] = [army]
	var top: int = int(army.condition_of(regiment_id)["max"])
	army.regiment_health[regiment_id] = top / 2
	RegimentDecorations.note(side, 2, true)
	army.regiment_health[regiment_id] = top


# --- test_military_parity ---

func test_no_research_leaves_the_floor_at_era_one() -> void:
	assert_eq(MilitaryParity.max_great_power_era({}), 1)
	assert_eq(MilitaryParity.max_great_power_era({0: {}}), 1)

func test_the_strongest_great_power_sets_the_era() -> void:
	var tech: Dictionary = {
		0: {"bayonet": true},
		1: {},
		2: {"needle_guns": true},
	}
	assert_eq(MilitaryParity.max_great_power_era(tech), 4)

func test_a_minor_upgrades_within_its_own_category() -> void:
	assert_eq(
		MilitaryParity.upgrade_type("squires", 3), "hussars",
		"light cavalry becomes the era-3 light cavalry"
	)
	assert_eq(
		MilitaryParity.upgrade_type("pikemen", 3), "regulars",
		"regular infantry becomes the era-3 regular infantry"
	)
	assert_eq(
		MilitaryParity.upgrade_type("culverin", 2), "royal_artillery",
		"heavy artillery follows its own row"
	)

func test_no_downgrade_and_unknown_types_are_safe() -> void:
	assert_eq(MilitaryParity.upgrade_type("guards", 2), "guards")
	assert_eq(MilitaryParity.upgrade_type("not_a_regiment", 4), "not_a_regiment")

func test_tribes_keep_level_one_while_minors_follow_the_powers() -> void:
	assert_eq(MilitaryParity.effective_level(FactionCatalog.minor_ids()[0], 3), 3)
	assert_eq(MilitaryParity.effective_level(FactionCatalog.tribe_ids()[0], 3), 1)

func test_apply_upgrades_minor_regiments_in_place_and_skips_others() -> void:
	var minor: int = FactionCatalog.minor_ids()[0]
	var tribe: int = FactionCatalog.tribe_ids()[0]
	var regions := MapRegionTable.new()
	var minor_army: ArmyState = ArmyState.muster(
		1, minor, 0, true, ["squires", "pikemen"], 1
	)
	var tribe_army: ArmyState = ArmyState.muster(
		2, tribe, 0, true, ["pikemen"], 10
	)
	var power_army: ArmyState = ArmyState.muster(
		3, FactionCatalog.PLAYER_FACTION, 0, true, ["squires"], 20
	)
	regions.set_region(0, [minor_army, tribe_army, power_army])
	var report: Dictionary = MilitaryParity.apply(
		regions, {FactionCatalog.PLAYER_FACTION: {"bayonet": true}}
	)
	assert_eq(int(report["era"]), 3)
	assert_eq(int(report["count"]), 2)
	assert_eq(minor_army.type_of(minor_army.regiments[0]), "hussars")
	assert_eq(minor_army.type_of(minor_army.regiments[1]), "regulars")
	assert_eq(tribe_army.type_of(tribe_army.regiments[0]), "pikemen")
	assert_eq(power_army.type_of(power_army.regiments[0]), "squires")

func test_apply_without_a_table_is_safe() -> void:
	var report: Dictionary = MilitaryParity.apply(null, {0: {"bayonet": true}})
	assert_eq(int(report["count"]), 0)
	assert_eq(int(report["era"]), 3)

func test_no_research_keeps_every_regiment_as_it_stands() -> void:
	var minor: int = FactionCatalog.minor_ids()[0]
	var regions := MapRegionTable.new()
	var army: ArmyState = ArmyState.muster(1, minor, 0, true, ["squires"], 1)
	regions.set_region(0, [army])
	var report: Dictionary = MilitaryParity.apply(regions, {0: {}})
	assert_eq(int(report["count"]), 0)
	assert_eq(army.type_of(army.regiments[0]), "squires")

func test_a_category_with_no_higher_type_keeps_its_regiment() -> void:
	assert_eq(MilitaryParity.upgrade_type("bowmen", 4), "bowmen")

# --- test_difficulty ---

func test_ids_are_ordered_easiest_first_and_unknown_ids_fall_back() -> void:
	assert_eq(Difficulty.IDS.size(), 4)
	assert_eq(String(Difficulty.IDS[0]), "introductory")
	assert_eq(String(Difficulty.IDS[3]), "impossible")
	assert_eq(Difficulty.normalize(""), Difficulty.DEFAULT)
	assert_eq(Difficulty.normalize("Napoleon"), Difficulty.DEFAULT)
	assert_eq(Difficulty.normalize("  Hard "), "hard")
	assert_eq(Difficulty.index_of("hard"), 2)
	assert_eq(Difficulty.label("impossible"), "Impossible")

func test_percentages_rise_with_difficulty_and_normal_is_the_published_row() -> void:
	var previous_start: int = 0
	var previous_combat: int = 0
	for id: String in Difficulty.IDS:
		assert_gte(Difficulty.ai_start_percent(id), previous_start)
		assert_gte(Difficulty.ai_combat_percent(id), previous_combat)
		previous_start = Difficulty.ai_start_percent(id)
		previous_combat = Difficulty.ai_combat_percent(id)
	assert_eq(Difficulty.ai_start_percent(Difficulty.DEFAULT), 100)
	assert_eq(Difficulty.ai_combat_percent(Difficulty.DEFAULT), 100)
	assert_eq(Difficulty.ai_start_percent("introductory"), 60)
	assert_eq(Difficulty.ai_start_percent("impossible"), 180)
	assert_eq(Difficulty.ai_combat_percent("impossible"), 130)

func test_every_level_states_its_effect_in_plain_words() -> void:
	for id: String in Difficulty.IDS:
		assert_gt(Difficulty.hint(id).length(), 20, "%s needs a hint" % id)
	assert_true(Difficulty.hint("hard").contains("140%"))
	assert_true(Difficulty.hint("normal").contains("alike"))
	assert_ne(Difficulty.hint("hard"), Difficulty.hint("impossible"))

func test_start_quantities_scale_by_percent_and_floor_at_zero() -> void:
	assert_eq(Difficulty.scaled(2500, 140), 3500)
	assert_eq(Difficulty.scaled(6, 85), 5)
	assert_eq(Difficulty.scaled(0, 180), 0)
	assert_eq(Difficulty.scaled(-4, 180), 0)

func test_a_rival_ledger_is_founded_at_the_chosen_level_once() -> void:
	var play := PlaySession.new()
	play.difficulty = "hard"
	var ai: AiState = play.ensure_ai()
	assert_eq(ai.difficulty, "hard")
	var rival: PlayerEconomy = ai.economy_for(3)
	assert_eq(rival.treasury, Difficulty.scaled(PlayerEconomy.START_TREASURY, 140))
	assert_eq(rival.quantity("grain"), Difficulty.scaled(
		PlayerEconomy.START_PEASANTS * PlayerEconomy.START_GRAIN_TURNS, 140
	))
	var treasury: int = rival.treasury
	# Reading the same ledger again must not compound the scale.
	assert_eq(ai.economy_for(3).treasury, treasury)
	assert_eq(ai.economy_for(3), rival)

func test_normal_leaves_every_court_on_the_published_start_row() -> void:
	var play := PlaySession.new()
	var rival: PlayerEconomy = play.ensure_ai().economy_for(2)
	assert_eq(play.difficulty, Difficulty.DEFAULT)
	assert_eq(rival.treasury, PlayerEconomy.START_TREASURY)
	assert_eq(rival.quantity("grain"), PlayerEconomy.START_PEASANTS * PlayerEconomy.START_GRAIN_TURNS)
	assert_eq(rival.quantity("wool"), 4)

func test_the_human_crown_is_never_scaled() -> void:
	var play := PlaySession.new()
	play.player_faction = 2
	play.difficulty = "impossible"
	var multipliers: Dictionary = Difficulty.combat_multipliers(
		play.human_faction_id(), play.difficulty, FactionCatalog.great_power_ids()
	)
	assert_false(multipliers.has(2), "the human side keeps the published maths")
	assert_almost_eq(float(multipliers[1]), 1.3, 0.001)

func test_battle_context_carries_the_rival_multiplier_and_skips_the_human() -> void:
	var play := PlaySession.new()
	play.player_faction = 2
	play.difficulty = "introductory"
	var context: Dictionary = MapPlayLandTurn.battle_context(play)
	var difficulty: Dictionary = context["difficulty"] as Dictionary
	assert_false(difficulty.has(2))
	assert_almost_eq(float(difficulty[0]), 0.85, 0.001)

func test_an_introductory_rival_fails_an_assault_that_wins_at_normal() -> void:
	var normal: Dictionary = _assault({})
	var eased: Dictionary = _assault({1: 0.85})
	assert_true(bool(normal["captured"]), "six regiments carry four at the published maths")
	assert_false(bool(eased["captured"]), "the eased rival is turned back")
	assert_gt(
		int((eased["attacker_lost"] as Array).size()),
		int((normal["attacker_lost"] as Array).size())
	)
	assert_gt(
		int((normal["defender_lost"] as Array).size()),
		int((eased["defender_lost"] as Array).size())
	)

func test_a_hard_rival_holds_its_ground_where_normal_is_driven_off() -> void:
	var normal: Dictionary = _assault({})
	var hard: Dictionary = _assault({1: 1.3})
	assert_true(bool(normal["captured"]))
	assert_true(bool(hard["captured"]), "a stronger attacker still carries the province")
	assert_gte(
		int((hard["defender_lost"] as Array).size()),
		int((normal["defender_lost"] as Array).size())
	)

## Six rival regiments assault four of the human crown's in province 0.
func _assault(difficulty: Dictionary) -> Dictionary:
	var model: MapModel = difficulty_Fixture.build()
	var defending: Array[ArmyState] = [
		difficulty_Fixture.army(1, 0, 0, ["pikemen", "pikemen", "pikemen", "pikemen"], true)
	]
	var attacking: Array[ArmyState] = [
		difficulty_Fixture.army(2, 1, 0, ["pikemen", "pikemen", "pikemen", "pikemen", "pikemen", "pikemen"])
	]
	attacking[0].moved = true
	var armies: Array[ArmyState] = []
	armies.append_array(defending)
	armies.append_array(attacking)
	var context: Dictionary = {"quick_battle": false}
	if not difficulty.is_empty():
		context["difficulty"] = difficulty
	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)
	assert_eq(reports.size(), 1, "one exchange in province 0")
	return reports[0] if not reports.is_empty() else {}

func test_the_naval_layer_scales_every_rival_and_never_the_crown() -> void:
	var play := PlaySession.new()
	play.player_faction = 2
	play.difficulty = "hard"
	var factors: Dictionary = MapPlayNavalTurn.strength_multipliers(play)
	assert_false(factors.has(2), "the crown's hulls keep the published maths")
	assert_almost_eq(float(factors[1]), 1.15, 0.001)
	assert_almost_eq(float(factors[0]), float(factors[4]), 0.001,
		"every rival sails under one factor")

func test_a_dead_even_squadron_action_turns_on_the_level() -> void:
	assert_eq(_engagement({}), NavalCombat.Outcome.STALEMATE,
		"equal hulls draw on the published maths")
	assert_eq(_engagement({1: 0.85}), NavalCombat.Outcome.SIDE2_VICTORY,
		"the eased rival is repelled")
	assert_eq(_engagement({1: 1.3}), NavalCombat.Outcome.SIDE1_VICTORY,
		"the risen rival holds the water")

func test_the_resolved_despatch_carries_the_scaled_strength() -> void:
	var raw_rival: float = NavalCombat.side_strength([_rival_squadron(1)])
	assert_almost_eq(_engagement_record({1: 1.3})["attacker_strength"],
		raw_rival * 1.3, 0.001)
	assert_almost_eq(_engagement_record({1: 1.3})["defender_strength"],
		NavalCombat.side_strength([_crown_squadron()]), 0.001,
		"the human side is never scaled")

func test_the_dossier_odds_read_the_same_factor() -> void:
	var fleets: Array = [_crown_squadron(), _rival_squadron(4)]
	var published: Dictionary = NavalStrength.zone(fleets, fleets[0])
	var hard: Dictionary = NavalStrength.zone(
		fleets, fleets[0], Callable(), {4: 1.3})
	assert_almost_eq(float(hard["foe"]), float(published["foe"]) * 1.3, 0.001)
	assert_lt(float(hard["share"]), float(published["share"]),
		"a stronger rival takes more of the zone")

func test_two_rivals_share_one_factor_so_their_ratio_stays_published() -> void:
	var fleets: Array = [_rival_squadron(1), _rival_squadron(4)]
	var published: Dictionary = NavalStrength.zone(fleets, fleets[0])
	var scaled: Dictionary = NavalStrength.zone(
		fleets, fleets[0], Callable(), {1: 1.3, 4: 1.3})
	assert_almost_eq(float(scaled["share"]), float(published["share"]), 0.0001,
		"the factor cancels between two rivals")

## One squadron of the human crown and one rival frigate pair, both afloat in
## zone 0; the rival carries the lower owner id, so it takes the initiative.
func _crown_squadron() -> FleetState:
	return FleetState.at_sea(
		10, 2, 0, ["h1", "h2"], {"h1": "frigate", "h2": "frigate"}
	)

func _rival_squadron(owner: int) -> FleetState:
	return FleetState.at_sea(
		10 + owner, owner, 0, ["r1", "r2"], {"r1": "frigate", "r2": "frigate"}
	)

func _engagement(factors: Dictionary) -> int:
	return int(_engagement_record(factors).get("outcome", NavalCombat.Outcome.NONE))

func _engagement_record(factors: Dictionary) -> Dictionary:
	var context: Dictionary = {}
	if not factors.is_empty():
		context["difficulty"] = factors
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(
		[_crown_squadron(), _rival_squadron(1)], Callable(), context
	)
	assert_eq(battles.size(), 1, "one engagement in zone 0")
	return battles[0] if not battles.is_empty() else {}

## The published bar is 31, and the level's published percentage moves it by
## whole provinces: 85 / 100 / 115 / 130 % of 31 (wiki: victory § Military
## victory; ruleset-config § Difficulty; DR-20261111-28).
func test_the_crowns_bar_is_the_published_one_scaled_by_the_level() -> void:
	assert_eq(VictoryRules.crown_threshold("normal"), VictoryRules.MILITARY_THRESHOLD)
	assert_eq(VictoryRules.crown_threshold(""), 31, "a legacy campaign reads as published")
	assert_eq(VictoryRules.crown_threshold("introductory"), 26)
	assert_eq(VictoryRules.crown_threshold("hard"), 36)
	assert_eq(VictoryRules.crown_threshold("impossible"), 40)

## Every rival keeps the published bar at every level, so the layer never
## changes a rival-versus-rival ratio; the observer (no human) is published too.
func test_only_the_human_crowns_bar_moves() -> void:
	for level: String in Difficulty.IDS:
		assert_eq(VictoryRules.threshold_for(1, 2, level), VictoryRules.MILITARY_THRESHOLD)
		assert_eq(
			VictoryRules.threshold_for(2, 2, level),
			VictoryRules.crown_threshold(level),
			"%s moves the crown's own bar" % level
		)
		assert_eq(
			VictoryRules.threshold_for(2, MapModel.NO_ID, level),
			VictoryRules.MILITARY_THRESHOLD,
			"the full-AI observer stays on the published rows"
		)

## 31 provinces win the age at normal and fall short at hard, where the crown
## needs 36; the same 31 still wins for a rival on that level.
func test_the_level_decides_whether_the_crown_has_won_the_age() -> void:
	assert_not_null(VictoryRules.evaluate(_world({2: 31}), 5, 2, "normal"))
	assert_null(VictoryRules.evaluate(_world({2: 31}), 5, 2, "hard"))
	var won: VictoryState = VictoryRules.evaluate(_world({2: 36}), 5, 2, "hard")
	assert_not_null(won)
	assert_eq(won.winner_player_id, 2)
	assert_not_null(
		VictoryRules.evaluate(_world({1: 31}), 5, 2, "hard"),
		"a rival still wins at the published bar"
	)

## An eased campaign asks less of the crown: 26 provinces win at introductory
## where 25 do not.
func test_an_eased_campaign_asks_less_of_the_crown() -> void:
	assert_not_null(VictoryRules.evaluate(_world({2: 26}), 5, 2, "introductory"))
	assert_null(VictoryRules.evaluate(_world({2: 25}), 5, 2, "introductory"))

## The turn reads the session's own level and human slot; an observer passes
## NO_ID and gets the published maths for every crown.
func test_the_turn_reads_the_sessions_level_and_human_slot() -> void:
	var play := PlaySession.new()
	play.player_faction = 2
	play.difficulty = "hard"
	play.world = _world({2: 31})
	assert_null(
		VictoryRules.resolve(play.victory, play.world, 9, play.human_faction_id(), play.difficulty)
	)
	play.world = _world({2: 36})
	assert_not_null(
		VictoryRules.resolve(play.victory, play.world, 9, play.human_faction_id(), play.difficulty)
	)
	play.observer_mode = true
	play.world = _world({2: 31})
	assert_not_null(
		VictoryRules.resolve(play.victory, play.world, 9, play.human_faction_id(), play.difficulty),
		"the observer keeps the published bar for every crown"
	)

## One Old World region holding `counts` provinces per owner.
func _world(counts: Dictionary) -> WorldMap:
	var world := WorldMap.new()
	var model := MapModel.new()
	model.setup(1, 1)
	model.region_id = FactionCatalog.OLD_WORLD
	model.faction_ids = FactionCatalog.ids_in_region(FactionCatalog.OLD_WORLD)
	var next_id: int = 0
	for faction_id: int in counts.keys():
		for _index in int(counts[faction_id]):
			var tiles: Array[Vector2i] = []
			model.provinces.append(
				ProvinceState.create(
					next_id, "Province %d" % next_id, tiles, Vector2.ZERO, 1, faction_id
				)
			)
			next_id += 1
	world.add_region(model)
	return world

# --- test_quick_battle_rules ---

func test_quick_battle_is_deterministic_for_a_fixed_seed() -> void:
	var first: Dictionary = _quick_battle_rules_fight("balanced", _guards(6), _pikes(4))
	var second: Dictionary = _quick_battle_rules_fight("balanced", _guards(6), _pikes(4))

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
	var battle: Dictionary = _quick_battle_rules_fight("balanced", _guards(6), _pikes(6))
	var rounds: int = _round_count(battle)
	assert_true(rounds >= 1)
	assert_true(rounds <= QuickBattle.MAX_ROUNDS)

func test_the_players_plan_drives_the_action_script() -> void:
	var aggressive: Dictionary = _quick_battle_rules_fight("aggressive", _guards(6), _pikes(4))
	var defensive: Dictionary = _quick_battle_rules_fight("defensive", _guards(6), _pikes(4))
	assert_eq(String(aggressive["quick"]["plan"]), "aggressive")
	assert_eq(String(defensive["quick"]["plan"]), "defensive")

## The crown holds one plan and it binds the side it commands, even on the wall;
## a rival side keeps the rule-derived script instead (wiki: quick-battle § The
## crown's plan; DR-20261110-33).
func test_the_crowns_plan_holds_on_the_defending_side() -> void:
	var model := quick_battle_rules_Fixture.build()
	model.province_data(2).fort_level = 1
	var defender := quick_battle_rules_Fixture.army(1, 1, 2, _pikes(6), true)
	var attacker := quick_battle_rules_Fixture.army(2, 2, 2, _guards(8))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var context: Dictionary = _context("aggressive")
	context["player_faction"] = 1

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)
	var quick: Dictionary = reports[0]["quick"]

	assert_eq(String(quick["defender_plan"]), "aggressive", "the crown's plan holds")
	assert_eq(String(quick["plan"]), "balanced", "the rival keeps its own script")

func test_quick_battle_removes_casualties_from_the_armies() -> void:
	var model := quick_battle_rules_Fixture.build()
	var defender := quick_battle_rules_Fixture.army(1, 1, 2, _pikes(6), true)
	var attacker := quick_battle_rules_Fixture.army(2, 0, 2, _guards(6))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var before: int = ArmyForce.side_regiments(armies)

	ArmyCombat.resolve_turn(model, armies, _context("balanced"))

	assert_true(ArmyForce.side_regiments(armies) < before)

func test_a_siege_fields_virtual_guns_and_downgrades_the_fort() -> void:
	var model := quick_battle_rules_Fixture.build()
	model.province_data(2).fort_level = 1
	var defender := quick_battle_rules_Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := quick_battle_rules_Fixture.army(2, 0, 2, _guards(20))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, _context("balanced"))
	var battle: Dictionary = reports[0]

	assert_eq(String(battle["battle_mode"]), "siege")
	assert_eq(int(battle["quick"]["guns_start"]), 1)
	assert_true(bool(battle["quick"]["fort_downgraded"]))
	assert_eq(int(battle["quick"]["guns_lost"]), 1, "the battery is silenced")
	assert_eq(String(battle["quick"]["gun_type"]), "royal_artillery")
	assert_eq(int(battle["quick"]["fort_after"]), 0)
	assert_eq(model.province_data(2).fort_level, 0)

## The wall lanes are recorded for the despatch: infantry man the parapet, the
## battery and horse shelter behind it (wiki: siege-mechanics).
func test_a_siege_records_the_wall_lanes() -> void:
	var battle: Dictionary = _quick_battle_rules_fight(
		"balanced", _guards(8), ["pikemen", "musketeers", "culverin"], 2
	)
	var lanes: Dictionary = battle["quick"]["lanes"]

	assert_eq(int(lanes["wall"]), 2, "two infantry regiments hold the wall")
	assert_eq(int(lanes["behind"]), 1, "the gun waits behind the parapet")

## Melee-only regiments cannot attack a wall or anything inside it; they need
## firearms or guns (wiki: siege-mechanics § Damage Reduction).
func test_melee_only_besiegers_are_turned_away() -> void:
	var model := quick_battle_rules_Fixture.build()
	model.province_data(2).fort_level = 1
	var defender := quick_battle_rules_Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := quick_battle_rules_Fixture.army(2, 0, 2, _pikes(8))
	attacker.moved = true
	var context: Dictionary = _context("balanced")
	## A garrison that holds the wall gives the pikes nothing to hit.
	context["defender_battle_plan"] = "defensive"
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)
	var battle: Dictionary = reports[0]

	assert_eq((battle["defender_lost"] as Array).size(), 0, "the garrison is untouched")
	assert_eq(int(battle["quick"]["guns_lost"]), 0, "pikes cannot silence the battery")
	var turned: bool = false
	for round: Dictionary in battle["quick"]["rounds"]:
		for action: Dictionary in round["actions"]:
			if int(action["turned"]) > 0:
				turned = true
	assert_true(turned, "the despatch says the wall turned the blow aside")

## A garrison that leaves the wall to sortie can hit back with every regiment,
## which is how a pike garrison hurts a siege at all.
func test_a_sortie_lets_a_pike_garrison_fight() -> void:
	var model := quick_battle_rules_Fixture.build()
	model.province_data(2).fort_level = 2
	var defender := quick_battle_rules_Fixture.army(1, 1, 2, _pikes(6), true)
	var attacker := quick_battle_rules_Fixture.army(2, 0, 2, _guards(6))
	attacker.moved = true
	var context: Dictionary = _context("aggressive")
	context["player_faction"] = 1
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)

	assert_true(int(reports[0]["quick"]["sorties"]) > 0, "the defender chose to sortie")
	assert_true(
		(reports[0]["attacker_lost"] as Array).size() > 0,
		"outside the wall the pikes can reach the besiegers"
	)

## Regiment detail: the report counts the losses by regiment type, so the
## despatch can name them.
func test_the_report_tallies_losses_by_regiment_type() -> void:
	var battle: Dictionary = _quick_battle_rules_fight("balanced", _guards(10), ["peasant_levies", "pikemen"], 1)
	var detail: Dictionary = battle["defender_detail"]
	var counted: int = 0
	for type_id: Variant in detail.keys():
		counted += int(detail[type_id])
		assert_true(RegimentCatalog.has_type(String(type_id)))

	assert_eq(counted, (battle["defender_lost"] as Array).size())
	assert_false(RegimentCatalog.detail_text(detail).is_empty())

func test_rival_battles_keep_the_aggregate_path() -> void:
	var model := quick_battle_rules_Fixture.build()
	var defender := quick_battle_rules_Fixture.army(1, 1, 2, _pikes(3), true)
	var attacker := quick_battle_rules_Fixture.army(2, 0, 2, _guards(5))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var context: Dictionary = _context("balanced")
	context["player_faction"] = 2

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)

	assert_false(reports[0].has("quick"), "a rival battle stays auto-resolve")

func test_a_weak_attacker_is_repulsed() -> void:
	var battle: Dictionary = _quick_battle_rules_fight("balanced", _pikes(2), _guards(8))
	assert_eq(int(battle["outcome"]), ArmyCombat.Outcome.DEFENDER_VICTORY)

## Side strength is tactical, not a head count: four guards outweigh four
## pikes, and four pikes outweigh four levies (wiki: quick-battle § Cohesion
## and effective strength).
func test_effective_strength_aggregates_fpn_and_fpm() -> void:
	var guards: Array[ArmyState] = _lane_side(_guards(4), 2)
	var pikes: Array[ArmyState] = _lane_side(_pikes(4), 1)
	var levies: Array[ArmyState] = _lane_side(_levies(4), 1)

	var guard_weight: float = QuickBattle.effective_strength(guards, 10, 3, 1.0)
	var pike_weight: float = QuickBattle.effective_strength(pikes, 10, 3, 1.0)
	var levy_weight: float = QuickBattle.effective_strength(levies, 10, 3, 1.0)

	assert_almost_eq(guard_weight, 4.0 * 22.0, 0.01, "Σ (FPN + FPM) for the slice")
	assert_true(guard_weight > pike_weight)
	assert_true(pike_weight > levy_weight)
	assert_almost_eq(
		QuickBattle.effective_strength(guards, 10, 0, 1.0), 0.0, 0.001,
		"a broken line has no strength"
	)
	assert_almost_eq(
		QuickBattle.effective_strength(guards, 10, 3, 2.0), guard_weight * 2.0,
		0.01, "the side multiplier scales the whole slice"
	)

## Reserves behind the deployment limit never count, exactly as in
## auto-resolve (wiki: combat § Strength).
func test_only_the_deployed_slice_counts_toward_strength() -> void:
	var twelve: Array[ArmyState] = _lane_side(_guards(12), 2)

	assert_almost_eq(
		QuickBattle.effective_strength(twelve, 10, 3, 1.0), 10.0 * 22.0, 0.01
	)

## A chevroned regiment weighs more than a fresh one, and health scales it the
## same way (wiki: combat § Strength).
func test_chevrons_and_health_raise_a_regiments_weight() -> void:
	var fresh: Array[ArmyState] = _lane_side(_guards(2), 2)
	var veteran: Array[ArmyState] = _lane_side(_guards(2), 2)
	var army: ArmyState = veteran[0]
	for regiment_id: String in army.regiments:
		army.regiment_medals[regiment_id] = RegimentCatalog.MAX_MEDALS
	var fresh_weight: float = QuickBattle.effective_strength(fresh, 10, 3, 1.0)
	var veteran_weight: float = QuickBattle.effective_strength(veteran, 10, 3, 1.0)

	assert_almost_eq(veteran_weight, fresh_weight * 1.4, 0.01)
	var first: String = army.regiments[0]
	army.regiment_health[first] = RegimentCatalog.max_health("guards") / 2
	assert_true(
		QuickBattle.effective_strength(veteran, 10, 3, 1.0) < veteran_weight,
		"a mauled regiment shoulders less"
	)

## An action's blow is spent as weight, so the same volley from a guard line
## breaks more men than from a levy line (wiki: quick-battle § Cohesion and
## effective strength).
func test_a_stronger_line_breaks_more_of_the_enemy() -> void:
	var strong: Array[ArmyState] = _lane_side(_guards(4), 2)
	var levies: Array[ArmyState] = _lane_side(_levies(4), 1)
	var hard: Dictionary = QuickBattleActions.resolve(
		_lane_joined(strong, levies), _lane_state(strong, levies, 0),
		"attacker", "defender", "volley", [] as Array[Dictionary]
	)
	var levy_attackers: Array[ArmyState] = _lane_side(_levies(4), 2)
	var guard_defenders: Array[ArmyState] = _lane_side(_guards(4), 1)
	var soft: Dictionary = QuickBattleActions.resolve(
		_lane_joined(levy_attackers, guard_defenders),
		_lane_state(levy_attackers, guard_defenders, 0),
		"attacker", "defender", "volley", [] as Array[Dictionary]
	)

	assert_eq(int(hard["defender_lost"]), 4, "the guard volley breaks the levy line")
	assert_true(int(soft["defender_lost"]) < 4, "the levy volley cannot break four guards")

## The virtual battery weighs its emplaced gun type, scaled by its remaining
## HP, instead of a flat per-gun count (wiki: quick-battle § Emplaced fort
## artillery).
func test_the_battery_weighs_its_gun_type_and_remaining_health() -> void:
	var guns: Array[Dictionary] = QuickBattleBattery.make(1, {}, 1)
	var royal: float = float(RegimentCatalog.strength("royal_artillery"))

	assert_almost_eq(QuickBattleBattery.strength(guns), royal, 0.01)
	QuickBattleBattery.hit(guns, 1)
	assert_almost_eq(QuickBattleBattery.strength(guns), royal * 0.5, 0.01)
	QuickBattleBattery.hit(guns, 1)
	assert_almost_eq(QuickBattleBattery.strength(guns), 0.0, 0.01, "a silenced gun weighs nothing")

func test_a_quick_battle_win_awards_the_general() -> void:
	var model := quick_battle_rules_Fixture.build()
	var defender := quick_battle_rules_Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := quick_battle_rules_Fixture.army(2, 0, 2, _guards(6))
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
	var battle: Dictionary = _quick_battle_rules_fight("balanced", _guards(6), _guards(8), 3)
	assert_eq(int(battle["quick"]["guns_start"]), 3)
	assert_true(int(battle["quick"]["guns_left"]) < 3)
	var fired: bool = false
	for round: Dictionary in battle["quick"]["rounds"]:
		for action: Dictionary in round["actions"]:
			if String(action["action"]) == "battery":
				fired = true
	assert_true(fired, "the emplaced battery answers the assault")

## The despatch copy reads `defender_lost` on an attacker's action as losses it
## inflicted and `attacker_lost` as its own cost, so the report must add up that
## way round: every loss a side suffered is either inflicted by the enemy or paid
## by its own action.
func test_round_despatches_add_up_to_each_sides_losses() -> void:
	var battle: Dictionary = _quick_battle_rules_fight("aggressive", _guards(6), _pikes(8), 2)
	var quick: Dictionary = battle["quick"]
	var atk_inflicted: int = 0
	var atk_own: int = 0
	var def_inflicted: int = 0
	var def_own: int = 0
	for round: Dictionary in quick["rounds"]:
		for action: Dictionary in round["actions"]:
			var entry: Dictionary = action as Dictionary
			if int(entry["side"]) == int(battle["attacker"]):
				atk_inflicted += int(entry["defender_lost"])
				atk_own += int(entry["attacker_lost"])
			else:
				def_inflicted += int(entry["attacker_lost"])
				def_own += int(entry["defender_lost"])
	assert_eq(
		def_inflicted + atk_own,
		int(quick["attacker_start"]) - int(quick["attacker_left"]),
		"every attacker loss is a despatch number"
	)
	assert_eq(
		atk_inflicted + def_own,
		int(quick["defender_start"]) - int(quick["defender_left"]),
		"every defender loss is a despatch number"
	)

func _quick_battle_rules_fight(
	plan: String, attacker_types: Array[String], defender_types: Array[String],
	fort: int = 0
) -> Dictionary:
	var model := quick_battle_rules_Fixture.build()
	model.province_data(2).fort_level = fort
	var defender := quick_battle_rules_Fixture.army(1, 1, 2, defender_types, true)
	var attacker := quick_battle_rules_Fixture.army(2, 0, 2, attacker_types)
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, _context(plan))
	return reports[0]

func test_a_quick_battle_pays_the_attack_price_too() -> void:
	var model := quick_battle_rules_Fixture.build()
	var defender := quick_battle_rules_Fixture.army(1, 1, 2, _pikes(4), true)
	var attacker := quick_battle_rules_Fixture.army(2, 0, 2, _guards(6))
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var charged: Array = []
	var pay := func(owner: int, cost: int) -> int:
		charged.append([owner, cost])
		return mini(cost, 40)
	var context: Dictionary = _context("balanced")
	context["pay_attack"] = pay

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)

	assert_eq(charged, [[0, 100]], "the plate charges the same price as auto-resolve")
	assert_eq(int(reports[0]["attack_cost"]), 100)
	assert_eq(int(reports[0]["attack_paid"]), 40, "a thin purse pays what it has")
	assert_true(reports[0].has("quick"))

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

func _levies(count: int) -> Array[String]:
	var types: Array[String] = []
	for _index in count:
		types.append("peasant_levies")
	return types

func test_the_garrison_splits_into_wall_and_behind() -> void:
	var side: Array[ArmyState] = _lane_side(["pikemen", "musketeers", "squires", "culverin"], 1)

	assert_eq(SiegeLanes.wall_ids(side).size(), 2, "infantry man the wall")
	assert_eq(SiegeLanes.behind_ids(side).size(), 2, "horse and guns wait behind")
	assert_true(SiegeLanes.is_wall_type("guards"))
	assert_false(SiegeLanes.is_wall_type("squires"))
	assert_false(SiegeLanes.is_wall_type("culverin"))
	assert_eq(SiegeLanes.describe(side), "2 on the wall · 2 behind")

## A standing gun spends the besieger's blow before the lanes: the garrison is
## sheltered while the battery answers (wiki: siege-mechanics § Quick Battle
## lanes — "spends its blow on the battery before the lanes").
func test_a_standing_gun_spends_the_blow_before_the_lanes() -> void:
	var defender: Array[ArmyState] = _lane_side(
		["peasant_levies", "peasant_levies", "peasant_levies"], 1
	)
	var attacker: Array[ArmyState] = _lane_side(["musketeers", "musketeers"], 2)
	var armies: Array[ArmyState] = _lane_joined(attacker, defender)
	var guns: Array[Dictionary] = QuickBattleBattery.make(1, {}, 1)
	var state: Dictionary = _lane_state(attacker, defender, 1)

	var first: Dictionary = QuickBattleActions.resolve(
		armies, state, "attacker", "defender", "volley", guns
	)
	assert_eq(int(first["defender_lost"]), 0, "the gun drinks the volley")
	assert_eq(int(first["battery_hit"]), 1)
	assert_eq(int(first["guns_destroyed"]), 0, "one hit does not silence a gun")

	var second: Dictionary = QuickBattleActions.resolve(
		armies, state, "attacker", "defender", "volley", guns
	)
	assert_eq(int(second["guns_destroyed"]), 1, "the second volley silences it")
	assert_eq(int(second["defender_lost"]), 0, "the garrison is still under cover")

	var third: Dictionary = QuickBattleActions.resolve(
		armies, state, "attacker", "defender", "volley", guns
	)
	assert_eq(int(third["guns_destroyed"]), 0)
	assert_true(int(third["wall_lost"]) > 0, "with the battery quiet the wall takes the fire")

## One blow bleeds no more than the deployed slice: the two lanes share one
## deployment limit, so the reserves behind it still do not die in the same
## volley (wiki: combat § Auto-resolve casualty selection).
func test_a_siege_blow_bleeds_no_more_than_the_deployed_slice() -> void:
	var limit: int = ArmyModifiers.deployment_limit(0, false)
	var guns_only: Array[String] = []
	for _index in 18:
		guns_only.append("culverin")
	var thick: Array[String] = ["peasant_levies", "peasant_levies"]
	for _index in 20:
		thick.append("squires")
	var attacker: Array[ArmyState] = _lane_side(guns_only, 2)
	var defended: Array[ArmyState] = _lane_side(thick, 1)
	var armies: Array[ArmyState] = _lane_joined(attacker, defended)

	var split: Dictionary = SiegeLanes.strike(armies, attacker, defended, 60, limit, 3, false)

	assert_eq((split["wall"] as Array).size(), 0, "a gun-only besieger hits nothing on the wall")
	assert_eq(
		(split["behind"] as Array).size(), limit,
		"the behind lane takes the deployed slice and no more"
	)

func test_melee_only_besiegers_cannot_touch_a_wall() -> void:
	var attacker: Array[ArmyState] = _lane_side(["pikemen", "knights"], 2)
	var defender: Array[ArmyState] = _lane_side(["peasant_levies"], 1)
	var armies: Array[ArmyState] = _lane_joined(attacker, defender)
	var wanted: int = 3

	var split: Dictionary = SiegeLanes.strike(armies, attacker, defender, wanted, 10, 2, false)

	assert_eq(int(split["turned"]), wanted, "the wall turns the pikes aside")
	assert_eq((split["wall"] as Array).size(), 0)
	assert_eq(defender[0].count(), 1, "nobody on the wall is hurt")

func test_firearms_hit_the_wall_and_the_fort_blunts_the_blow() -> void:
	var open_field: int = _struck_lane_losses(2 - 2, 4)
	var stone: int = _struck_lane_losses(2, 4)

	assert_eq(open_field, 4, "an open field takes the whole blow")
	assert_eq(stone, ceili(4.0 * FortRules.loss_scale(2)), "the wall spares a share")
	assert_true(stone < open_field)

func test_only_artillery_reaches_behind_the_wall() -> void:
	var muskets: Array[ArmyState] = _lane_side(["musketeers", "musketeers"], 2)
	var guns: Array[ArmyState] = _lane_side(["musketeers", "musketeers", "culverin"], 2)
	var defender: Array[ArmyState] = _lane_side(["pikemen", "pikemen", "pikemen", "culverin"], 1)
	var armies: Array[ArmyState] = _lane_joined(guns, defender)

	assert_false(SiegeLanes.can_reach_behind(muskets), "small arms stay outside")
	var shot: Dictionary = SiegeLanes.strike(armies, guns, defender, 4, 10, 2, false)

	assert_true((shot["behind"] as Array).size() > 0, "guns drop shot over the parapet")
	assert_true((shot["wall"] as Array).size() > 0)

	var walls_only: Array[ArmyState] = _lane_side(["pikemen", "pikemen", "pikemen", "culverin"], 1)
	var field_only: Array[ArmyState] = _lane_joined(muskets, walls_only)
	var small: Dictionary = SiegeLanes.strike(field_only, muskets, walls_only, 4, 10, 2, false)
	assert_eq((small["behind"] as Array).size(), 0, "only artillery can hit behind")

func test_a_sortie_sheds_the_walls_protection() -> void:
	var sheltered: int = _struck_lane_losses(2, 6, false)
	var sortied: int = _struck_lane_losses(2, 6, true)

	assert_eq(sheltered, ceili(6.0 * FortRules.loss_scale(2)))
	assert_eq(sortied, 6, "outside the wall the garrison takes the whole blow")
	assert_true(sortied > sheltered)

func test_return_fire_follows_the_garrisons_range() -> void:
	var pikes: Array[ArmyState] = _lane_side(["pikemen", "pikemen"], 1)
	var muskets: Array[ArmyState] = _lane_side(["musketeers", "musketeers"], 1)
	var mixed: Array[ArmyState] = _lane_side(["pikemen", "pikemen", "musketeers", "musketeers"], 1)

	assert_almost_eq(SiegeLanes.return_fire_share(pikes), 0.0, 0.001, "pikes cannot shoot")
	assert_almost_eq(SiegeLanes.return_fire_share(muskets), 1.0, 0.001)
	assert_almost_eq(SiegeLanes.return_fire_share(mixed), 0.5, 0.001)

func test_an_empty_garrison_absorbs_nothing() -> void:
	var attacker: Array[ArmyState] = _lane_side(["musketeers"], 2)
	var defender: Array[ArmyState] = []
	var split: Dictionary = SiegeLanes.strike(
		attacker, attacker, defender, 3, 10, 2, false
	)

	assert_eq((split["wall"] as Array).size(), 0)
	assert_eq((split["behind"] as Array).size(), 0)
	assert_eq(int(split["turned"]), 0)
	assert_almost_eq(SiegeLanes.return_fire_share(defender), 0.0, 0.001)
	assert_false(SiegeLanes.can_reach_wall(defender))
	assert_eq(SiegeLanes.describe(defender), "0 on the wall · 0 behind")

## A hole in an army list (a pruned army) is skipped, never crashed on.
func test_a_null_army_is_skipped() -> void:
	var side: Array[ArmyState] = _lane_side(["pikemen"], 1)
	side.append(null)

	assert_eq(SiegeLanes.wall_ids(side).size(), 1)
	assert_false(SiegeLanes.behind_ids(side).size() > 0)
	assert_true(SiegeLanes.can_reach_wall(_lane_side(["musketeers"], 2)))
	assert_false(SiegeLanes.can_reach_behind(side))

func _struck_lane_losses(fort: int, wanted: int, exposed: bool = false) -> int:
	var attacker: Array[ArmyState] = _lane_side(["musketeers", "musketeers", "musketeers"], 2)
	var defender: Array[ArmyState] = _lane_side(
		["peasant_levies", "peasant_levies", "peasant_levies", "peasant_levies",
		"peasant_levies", "peasant_levies"], 1
	)
	var armies: Array[ArmyState] = _lane_joined(attacker, defender)
	var split: Dictionary = SiegeLanes.strike(
		armies, attacker, defender, wanted, 10, fort, exposed
	)
	return (split["wall"] as Array).size() + (split["behind"] as Array).size()

func _lane_side(types: Array[String], owner: int) -> Array[ArmyState]:
	var side: Array[ArmyState] = []
	side.append(quick_battle_rules_Fixture.army(10 + owner, owner, 2, types, true))
	return side

func _lane_joined(first: Array[ArmyState], second: Array[ArmyState]) -> Array[ArmyState]:
	var all: Array[ArmyState] = []
	all.append_array(first)
	all.append_array(second)
	return all

## Battle state for one scripted action, shaped the way [QuickBattle] builds it.
func _lane_state(attacker: Array[ArmyState], defender: Array[ArmyState], fort: int) -> Dictionary:
	return {
		"attacker": {
			"side": attacker, "owner": 2, "limit": 10, "mods": {},
			"cohesion": 3, "guard": 0.0, "lost": [] as Array[String],
			"plan": "balanced", "exposed": false,
		},
		"defender": {
			"side": defender, "owner": 1, "limit": 10, "mods": {"fort": fort},
			"cohesion": 3, "guard": 0.0, "lost": [] as Array[String],
			"plan": "defensive", "exposed": false,
		},
	}

## Every blow that breaks a regiment must show the health it took from the men
## still standing: the plate's bars and damage numbers read from these hits.
func test_every_action_shows_the_health_it_took() -> void:
	var battle: Dictionary = _quick_battle_rules_fight("balanced", _guards(6), _guards(20))
	var counted: int = 0
	for round: Dictionary in battle["quick"]["rounds"]:
		for action: Dictionary in round["actions"]:
			var losses: int = int(action["attacker_lost"]) + int(action["defender_lost"])
			var hits: Array = action["hits"] as Array
			if losses <= 0:
				continue
			counted += 1
			assert_true(not hits.is_empty(), "a blow that broke a regiment mauled the rest")
			assert_eq(int(action["mauled"]), hits.size())
			for hit: Dictionary in hits:
				assert_true(int(hit["damage"]) > 0)
				assert_true(int(hit["hp"]) < int(hit["max"]))
	assert_true(counted > 0, "the fight landed blows")

func test_round_logs_carry_a_condition_snapshot() -> void:
	var battle: Dictionary = _quick_battle_rules_fight("balanced", _guards(6), _guards(6))
	var rounds: Array = battle["quick"]["rounds"] as Array
	assert_true(not rounds.is_empty())
	for round: Dictionary in rounds:
		assert_true(round.has("attacker_health"))
		assert_true(round.has("defender_health"))
		assert_true(float(round["attacker_strength"]) <= 1.0)
		assert_true(float(round["defender_strength"]) <= 1.0)
	var last: Dictionary = rounds[rounds.size() - 1] as Dictionary
	var mauled: int = 0
	var entries: Array = (last["attacker_health"] as Array) + (last["defender_health"] as Array)
	for entry: Dictionary in entries:
		if float(entry["fraction"]) < 1.0:
			mauled += 1
	assert_true(mauled > 0, "survivors carry wounds out of the battle")

func test_the_battle_report_carries_aftermath_condition_and_chevrons() -> void:
	var battle: Dictionary = _quick_battle_rules_fight("balanced", _guards(8), _pikes(2))
	assert_eq(int(battle["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	assert_true((battle["attacker_health"] as Array).size() > 0)
	assert_true(int(battle["attacker_chevrons"]) > 0)
	assert_eq(int(battle["defender_chevrons"]), 0, "the broken side wins nothing")
	assert_true(int(battle["defender_mauled"]) >= 0)

func test_veterans_are_deployed_ahead_of_fresh_regiments() -> void:
	var army := quick_battle_rules_Fixture.army(1, 0, 2, ["guards", "guards"])
	var veteran: String = army.regiments[0]
	army.regiment_medals[veteran] = 4
	var side: Array[ArmyState] = [army]

	var deployed: Array[Dictionary] = ArmyModifiers.deployed(side, 1)

	assert_eq(String(deployed[0]["id"]), veteran, "the chevroned regiment leads")
	assert_eq(int(deployed[0]["medals"]), 4)

## The three stances and their ordered action lists are the rules: the page
## publishes them, so a replay must be able to read them here.
func test_the_published_plan_scripts_match_the_wiki() -> void:
	assert_eq(QuickBattleActions.actions_for("aggressive"), ["maneuver", "assault"])
	assert_eq(QuickBattleActions.actions_for("balanced"), ["volley", "entrench", "volley"])
	assert_eq(QuickBattleActions.actions_for("defensive"), ["fall_back", "volley"])

	assert_eq(
		QuickBattleActions.actions_for("aggressive", true, true), ["entrench", "sortie"],
		"a siege garrison with an aggressive plan entrenches then sallies"
	)
	assert_eq(
		QuickBattleActions.actions_for("aggressive", true, false),
		["entrench", "volley", "volley"],
		"a sortie with no wall is ordinary volley fire"
	)
	assert_eq(QuickBattleActions.actions_for("balanced", true, true), ["volley", "entrench"])
	assert_eq(QuickBattleActions.actions_for("balanced", true, false), ["volley", "entrench"])
	assert_eq(QuickBattleActions.actions_for("defensive", true, true), ["fall_back", "volley"])
	assert_eq(QuickBattleActions.actions_for("defensive", true, false), ["fall_back", "volley"])

## 3 CP a side each round, and no action is ever taken without its price.
func test_a_side_spends_at_most_three_cp_a_round() -> void:
	for plan: String in ["aggressive", "balanced", "defensive"]:
		var battle: Dictionary = _quick_battle_rules_fight(plan, _guards(6), _pikes(6))
		var rounds: Array = battle["quick"]["rounds"] as Array
		assert_true(not rounds.is_empty())
		for round: Dictionary in rounds:
			for side: int in [int(battle["attacker"]), int(battle["defender"])]:
				var spent: int = _cp_spent(round, side)
				assert_true(spent <= QuickBattle.CP_PER_ROUND, "%s spends %d CP" % [plan, spent])

## The side the human does not command is chosen in the published order
## (wiki: quick-battle § The opposing script): a scenario plan, the crown's own,
## the firearmless sally, a cavalry share ≥ 0.3, then the side's default.
func test_the_opposing_script_follows_the_published_order() -> void:
	var pikes: Array[ArmyState] = _rival(["pikemen", "pikemen"])
	var muskets: Array[ArmyState] = _rival(["pikemen", "musketeers"])
	assert_eq(QuickBattle.plan_for(pikes, 1, {}, true, true), "aggressive",
		"a wall with no firearm sallies")
	assert_eq(QuickBattle.plan_for(muskets, 1, {}, true, true), "defensive",
		"a wall that can shoot holds")
	assert_eq(QuickBattle.plan_for(_rival(["squires", "pikemen", "pikemen"]), 1, {}, false),
		"aggressive", "cavalry share ≥ 0.3")
	assert_eq(QuickBattle.plan_for(_rival(["squires", "pikemen", "pikemen", "pikemen"]), 1, {}, true, false),
		"defensive", "cavalry share below 0.3")
	assert_eq(QuickBattle.plan_for(_rival(["squires", "pikemen"]), 0, {}, false), "aggressive")
	assert_eq(QuickBattle.plan_for(_rival(["pikemen", "pikemen"]), 0, {}, false), "balanced")
	## An explicit scenario plan outranks the ranking, and the crown's plan
	## outranks the automatic sally.
	assert_eq(
		QuickBattle.plan_for(pikes, 1, {"defender_battle_plan": "balanced"}, true, true),
		"balanced"
	)
	assert_eq(
		QuickBattle.plan_for(pikes, 1, {"player_faction": 1, "battle_plan": "defensive"}, true, true),
		"defensive", "the crown's plan holds its own wall"
	)

## A sally is a real sortie, not a label: the firearmless garrison leaves the
## wall (wiki: siege-mechanics § Gates and Sortie).
func test_a_firearmless_garrison_sallies_when_no_one_commands_it() -> void:
	var battle: Dictionary = _quick_battle_rules_fight("balanced", _guards(8), _pikes(4), 1)
	assert_eq(String(battle["quick"]["defender_plan"]), "aggressive")
	assert_true(int(battle["quick"]["sorties"]) > 0, "the garrison left the wall")

## Any value the page does not publish is `balanced`, wherever it came from
## (wiki: quick-battle § The crown's plan).
func test_an_unknown_plan_is_balanced() -> void:
	assert_eq(QuickBattleActions.normalize_plan("hammer"), "balanced")
	assert_eq(QuickBattleActions.normalize_plan(""), "balanced")
	assert_eq(QuickBattleActions.normalize_plan("defensive"), "defensive")
	assert_eq(
		QuickBattle.plan_for(
			_rival(["pikemen"]), 0, {"player_faction": 0, "battle_plan": "hammer"}, false
		),
		"balanced", "a crown's unknown stance fights balanced"
	)

func _rival(types: Array[String]) -> Array[ArmyState]:
	var side: Array[ArmyState] = []
	side.append(quick_battle_rules_Fixture.army(7, 1, 2, types, true))
	return side

func _cp_spent(round: Dictionary, side: int) -> int:
	var spent: int = 0
	for entry: Dictionary in round["actions"] as Array:
		if int(entry["side"]) != side:
			continue
		spent += int(QuickBattleActions.ACTION_CP.get(String(entry["action"]), 0))
	return spent

# --- from test_army_markers.gd ---
## ArmyMarkers and ArmyMuster leave ArmyLayer.
## ArmyMarkers and ArmyMuster leave ArmyLayer: marker mint/clear/place and
## opening Home Army rosters stay testable without the map screen (REQ-P3-01,
## REQ-P3-04).


func test_muster_builds_a_home_army_per_capital() -> void:
	var model := MapModel.new()
	model.region_id = 0
	model.faction_ids = [0, 1]
	var seat_a := ProvinceState.new()
	seat_a.id = 0
	seat_a.owner = 0
	seat_a.capital = true
	seat_a.center = Vector2(1, 1)
	var seat_b := ProvinceState.new()
	seat_b.id = 1
	seat_b.owner = 1
	seat_b.capital = true
	seat_b.center = Vector2(2, 2)
	model.provinces = [seat_a, seat_b]
	var muster := ArmyMuster.new()
	var armies: Array[ArmyState] = muster.build(model)
	assert_eq(armies.size(), 2)
	assert_true(armies[0].is_home_army())
	assert_true(armies[1].is_home_army())
	assert_eq(armies[0].count(), ArmyMuster.GREAT_POWER_ROSTER.size())
	assert_eq(muster.next_army, 3)


func test_markers_mint_place_and_drop() -> void:
	var model := MapModel.new()
	model.region_id = 0
	var province := ProvinceState.new()
	province.id = 0
	province.owner = 0
	province.capital = true
	province.center = Vector2(3, 4)
	model.provinces = [province]
	var army := ArmyState.muster(1, 0, 0, true, ["peasant_levies", "pikemen"], 10)
	var helpers := ArmyMarkers.new()
	helpers.model = model
	var marker: ArmyMarker = helpers.make(army)
	assert_not_null(marker)
	assert_eq(helpers.markers.size(), 1)
	helpers.place_all([army])
	assert_eq(marker.position, province.center * ArmyMarkers.TILE_SIZE)
	helpers.refresh(army)
	assert_eq(helpers.find_army(army), marker)
	helpers.remove(marker)
	assert_eq(helpers.markers.size(), 0)
	assert_null(helpers.find(1))


func test_roster_counts_every_region() -> void:
	var regions := MapRegionTable.new()
	var home := ArmyState.muster(1, 0, 0, true, ["peasant_levies", "pikemen"], 10)
	var field := ArmyState.muster(2, 0, 1, false, ["bowmen"], 20)
	regions.set_region(0, [home])
	regions.set_region(1, [field])
	assert_eq(ArmyRoster.count_all(regions, 0), 3)
	assert_eq(ArmyRoster.count_all(regions, 1), 0)
	assert_true(ArmyRoster.food_upkeep_all(regions, 0) > 0)
