extends GdToolsTest
## Civilian work orders: gates, costs, multi-turn progress and tile effects
## (wiki: civilian-units § Work Types, extraction-and-improvements costs).

const Fixture = preload("res://tests/civilian_fixture.gd")

var _model: MapModel = null
var _works: LandWorks = null
var _units: Array[CivilianState] = []
var _stock: Dictionary = {}
var _view: VisibilityModel = null


func before_each() -> void:
	_model = Fixture.build()
	_works = LandWorks.new()
	_units = []
	_stock = Fixture.stockpile()
	_view = Fixture.visibility(_model)


func test_exploration_time_follows_the_wiki_formula() -> void:
	# ceil(3 × province tiles / largest province), capped at three turns.
	assert_eq(CivilianWork.explore_turns(_model, Fixture.PLAYER_PROVINCE), 3)
	assert_eq(CivilianWork.explore_turns(_model, Fixture.RIVAL_PROVINCE), 2)


func test_explorer_charts_a_rival_province_over_several_turns() -> void:
	var explorer := _add("explorer", Vector2i(3, 1))
	var check: Dictionary = _validate(explorer, "explore")
	assert_true(bool(check["ok"]), String(check.get("reason", "")))
	assert_eq(int(check["duration"]), 2)
	assert_true(bool(CivilianWork.assign(
		_model, explorer, "explore", _works, _units, _stock, _view
	)["ok"]))
	assert_true(explorer.is_working())

	var first: Array[Dictionary] = CivilianWork.resolve_turn(_model, _units, _works, _view)
	assert_false(bool(first[0]["completed"]))
	assert_true(explorer.is_working())

	var second: Array[Dictionary] = CivilianWork.resolve_turn(_model, _units, _works, _view)
	assert_true(bool(second[0]["completed"]))
	assert_true(explorer.is_idle())
	var tile: Vector2i = _model.province_tiles(Fixture.RIVAL_PROVINCE)[0]
	assert_eq(_view.level_at(tile.x, tile.y), VisibilityModel.Level.FULLY_VISIBLE)
	assert_true(_view.is_province_fully_visible(Fixture.RIVAL_PROVINCE))


func test_explorer_cannot_chart_land_already_seen() -> void:
	var explorer := _add("explorer", Fixture.IRON_TILE)
	var check: Dictionary = _validate(explorer, "explore")
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("already charted"))


func test_prospecting_takes_one_turn_and_records_the_tile() -> void:
	var explorer := _add("explorer", Fixture.IRON_TILE)
	var check: Dictionary = _validate(explorer, "prospect")
	assert_true(bool(check["ok"]), String(check.get("reason", "")))
	assert_eq(int(check["duration"]), 1)
	CivilianWork.assign(_model, explorer, "prospect", _works, _units, _stock, _view)
	var reports: Array[Dictionary] = CivilianWork.resolve_turn(_model, _units, _works, _view)
	assert_true(bool(reports[0]["completed"]))
	assert_true(_works.is_prospected(0, _model, Fixture.IRON_TILE))
	assert_false(_works.is_prospected(1, _model, Fixture.IRON_TILE))


func test_only_mineral_tiles_can_be_prospected() -> void:
	var explorer := _add("explorer", Fixture.TIMBER_TILE)
	var check: Dictionary = _validate(explorer, "prospect")
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("iron, coal and gold"))


func test_a_prospected_tile_cannot_be_prospected_again() -> void:
	var explorer := _add("explorer", Fixture.IRON_TILE)
	_works.set_prospected(0, _model, Fixture.IRON_TILE)
	var check: Dictionary = _validate(explorer, "prospect")
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("already been prospected"))


func test_builder_pays_materials_and_raises_the_improvement_level() -> void:
	var builder := _add("builder", Fixture.IRON_TILE)
	_works.set_prospected(0, _model, Fixture.IRON_TILE)
	var check: Dictionary = _validate(builder, "build_improvement")
	assert_true(bool(check["ok"]), String(check.get("reason", "")))
	assert_eq(check["cost"], {"lumber": 1, "castIron": 1})
	assert_eq(int(check["duration"]), 1)
	CivilianWork.assign(_model, builder, "build_improvement", _works, _units, _stock, _view)
	assert_eq(int(_stock["lumber"]), 39)
	assert_eq(int(_stock["castIron"]), 39)
	CivilianWork.resolve_turn(_model, _units, _works, _view)
	assert_eq(_works.improvement_at(_model, Fixture.IRON_TILE), 1)

	var second: Dictionary = _validate(builder, "build_improvement")
	assert_false(bool(second["ok"]))
	assert_true(String(second["reason"]).contains("tech"))


func test_improvements_need_a_resource_tile() -> void:
	var builder := _add("builder", Fixture.BARE_TILE)
	var check: Dictionary = _validate(builder, "build_improvement")
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("with a resource"))


func test_builder_cannot_improve_foreign_land() -> void:
	var builder := _add("builder", Fixture.RIVAL_GRAIN_TILE)
	var check: Dictionary = _validate(builder, "build_improvement")
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("not held by your crown"))


func test_improvements_stop_at_level_four() -> void:
	var builder := _add("builder", Fixture.IRON_TILE)
	_works.set_improvement(_model, Fixture.IRON_TILE, LandWorks.MAX_IMPROVEMENT)
	var check: Dictionary = _validate(builder, "build_improvement")
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("fully improved"))


func test_one_crew_per_tile() -> void:
	var first := _add("builder", Fixture.TIMBER_TILE)
	var second := _add("builder", Fixture.TIMBER_TILE)
	assert_true(bool(CivilianWork.assign(
		_model, first, "build_improvement", _works, _units, _stock, _view
	)["ok"]))
	var check: Dictionary = CivilianWork.validate(
		_model, second, "build_improvement", _works, _units, _stock, _view
	)
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("already working this tile"))


func test_work_needs_materials_in_the_stockpile() -> void:
	var builder := _add("builder", Fixture.IRON_TILE)
	_works.set_prospected(0, _model, Fixture.IRON_TILE)
	_stock = {"lumber": 0, "castIron": 0}
	var check: Dictionary = _validate(builder, "build_improvement")
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("Not enough lumber, cast iron"))


func test_engineer_builds_one_road_per_tile() -> void:
	var engineer := _add("engineer", Vector2i(0, 1))
	var check: Dictionary = _validate(engineer, "build_road")
	assert_true(bool(check["ok"]), String(check.get("reason", "")))
	assert_eq(check["cost"], {"lumber": 1, "castIron": 1})
	CivilianWork.assign(_model, engineer, "build_road", _works, _units, _stock, _view)
	CivilianWork.resolve_turn(_model, _units, _works, _view)
	assert_eq(_works.transport_at(_model, Vector2i(0, 1)), LandWorks.TRANSPORT_ROAD)
	var again: Dictionary = _validate(engineer, "build_road")
	assert_false(bool(again["ok"]))
	assert_true(String(again["reason"]).contains("already has a road"))


func test_engineer_builds_a_port_only_on_the_coast() -> void:
	var engineer := _add("engineer", Fixture.IRON_TILE)
	var inland: Dictionary = _validate(engineer, "build_port")
	assert_false(bool(inland["ok"]))
	assert_true(String(inland["reason"]).contains("coastal"))

	engineer.tile = Fixture.COAST_TILE
	var coastal: Dictionary = _validate(engineer, "build_port")
	assert_true(bool(coastal["ok"]), String(coastal.get("reason", "")))
	assert_eq(int(coastal["duration"]), CivilianWork.PORT_TURNS)
	assert_eq(_cost_text(coastal["cost"]), "5 lumber + 5 cast iron")


func test_a_province_holds_one_port() -> void:
	var engineer := _add("engineer", Fixture.COAST_TILE)
	CivilianWork.assign(_model, engineer, "build_port", _works, _units, _stock, _view)
	CivilianWork.resolve_turn(_model, _units, _works, _view)
	CivilianWork.resolve_turn(_model, _units, _works, _view)
	assert_true(_works.has_port(_model, Fixture.COAST_TILE))
	var second: Dictionary = _validate(engineer, "build_port")
	assert_false(bool(second["ok"]))
	assert_true(String(second["reason"]).contains("already has a port"))


func test_port_builds_take_two_turns() -> void:
	var engineer := _add("engineer", Fixture.COAST_TILE)
	CivilianWork.assign(_model, engineer, "build_port", _works, _units, _stock, _view)
	var first: Array[Dictionary] = CivilianWork.resolve_turn(_model, _units, _works, _view)
	assert_false(bool(first[0]["completed"]))
	assert_false(_works.has_port(_model, Fixture.COAST_TILE))
	var second: Array[Dictionary] = CivilianWork.resolve_turn(_model, _units, _works, _view)
	assert_true(bool(second[0]["completed"]))
	assert_true(_works.has_port(_model, Fixture.COAST_TILE))


func test_cancelling_work_returns_the_unit_to_idle() -> void:
	var builder := _add("builder", Fixture.IRON_TILE)
	CivilianWork.assign(_model, builder, "build_improvement", _works, _units, _stock, _view)
	var spent: int = 40 - int(_stock["lumber"])
	builder.cancel_work()
	assert_true(builder.is_idle())
	assert_eq(builder.work, {})
	assert_eq(40 - int(_stock["lumber"]), spent)
	assert_eq(_works.improvement_at(_model, Fixture.IRON_TILE), 0)


func test_a_type_cannot_take_another_types_work() -> void:
	var builder := _add("builder", Fixture.IRON_TILE)
	var check: Dictionary = _validate(builder, "explore")
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("cannot explore province"))


func test_a_mine_needs_prospecting_first() -> void:
	var builder := _add("builder", Fixture.IRON_TILE)
	var check: Dictionary = _validate(builder, "build_improvement")
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("prospect"))


func test_builder_can_take_an_estate_away_from_its_tile() -> void:
	var builder := _add("builder", Fixture.BARE_TILE)
	var check: Dictionary = CivilianWork.validate(
		_model, builder, "build_improvement", _works, _units, _stock, _view,
		Fixture.TIMBER_TILE
	)
	assert_true(bool(check["ok"]), String(check.get("reason", "")))
	CivilianWork.assign(
		_model, builder, "build_improvement", _works, _units, _stock, _view,
		Fixture.TIMBER_TILE
	)
	assert_eq(builder.tile, Fixture.TIMBER_TILE)
	assert_eq(builder.origin_tile, Fixture.BARE_TILE)
	assert_eq(builder.assigned_tile, Fixture.TIMBER_TILE)
	CivilianWork.resolve_turn(_model, _units, _works, _view)
	assert_eq(_works.improvement_at(_model, Fixture.TIMBER_TILE), 1)
	assert_eq(builder.origin_tile, CivilianState.NO_TILE)


func test_cancelling_a_relocated_order_returns_the_builder() -> void:
	var builder := _add("builder", Fixture.BARE_TILE)
	_works.set_prospected(0, _model, Fixture.IRON_TILE)
	CivilianWork.assign(
		_model, builder, "build_improvement", _works, _units, _stock, _view,
		Fixture.IRON_TILE
	)
	assert_eq(builder.tile, Fixture.IRON_TILE)
	builder.cancel_work()
	assert_eq(builder.tile, Fixture.BARE_TILE)
	assert_eq(builder.origin_tile, CivilianState.NO_TILE)
	assert_eq(_works.improvement_at(_model, Fixture.IRON_TILE), 0)


func test_busy_civilians_refuse_new_orders() -> void:
	var builder := _add("builder", Fixture.IRON_TILE)
	_works.set_prospected(0, _model, Fixture.IRON_TILE)
	CivilianWork.assign(_model, builder, "build_improvement", _works, _units, _stock, _view)
	var check: Dictionary = _validate(builder, "build_improvement")
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("already working"))


func test_status_stays_idle_or_working_across_the_work_pass() -> void:
	var builder := _add("builder", Fixture.IRON_TILE)
	CivilianWork.assign(_model, builder, "build_improvement", _works, _units, _stock, _view)
	for _turn in 3:
		CivilianWork.resolve_turn(_model, _units, _works, _view)
		assert_true(
			builder.status == CivilianState.Status.IDLE
			or builder.status == CivilianState.Status.WORKING
		)
	assert_true(builder.is_idle())


func test_options_explain_each_work_order() -> void:
	var explorer := _add("explorer", Fixture.TIMBER_TILE)
	var options: Array[Dictionary] = CivilianWork.options(
		_model, explorer, _works, _units, _stock, _view
	)
	assert_eq(options.size(), 2)
	for option: Dictionary in options:
		if String(option["action"]) == "prospect":
			assert_false(bool(option["ok"]))
			assert_true(String(option["reason"]).contains("iron, coal and gold"))
		else:
			assert_eq(String(option["label"]), "Explore province")
			assert_eq(String(option["cost_text"]), "Free")


func test_idle_units_produce_no_reports() -> void:
	_add("builder", Fixture.IRON_TILE)
	assert_eq(CivilianWork.resolve_turn(_model, _units, _works, _view), [])


func _add(type_id: String, tile: Vector2i) -> CivilianState:
	var unit := Fixture.unit(type_id, tile)
	unit.id = _units.size() + 1
	_units.append(unit)
	return unit


func _validate(unit: CivilianState, action: String) -> Dictionary:
	return CivilianWork.validate(_model, unit, action, _works, _units, _stock, _view)


func _cost_text(cost: Dictionary) -> String:
	return CivilianWork.cost_text(cost)
