extends GdToolsTest
## Civilian movement, work, improvement and estates rules on the shared
## civilian fixture.
## Merged into one suite so coverage pays a single Godot boot per theme
## (docs/testing.md speed rules).

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

# --- from test_civilian_movement.gd ---
## Civilian land movement (wiki: civilian-units § Relations).

func test_explorer_walks_one_orthogonal_land_tile() -> void:
	var explorer := Fixture.unit("explorer", Vector2i(1, 1))
	var tiles: Array[Vector2i] = CivilianMovement.valid_tiles(_model, explorer)
	assert_eq(tiles.size(), 4)
	for tile: Vector2i in [
		Vector2i(0, 1), Vector2i(2, 1), Vector2i(1, 0), Vector2i(1, 2)
	]:
		assert_true(tiles.has(tile), str(tile))


func test_sea_and_diagonals_are_out_of_reach() -> void:
	var explorer := Fixture.unit("explorer", Fixture.COAST_TILE)
	var tiles: Array[Vector2i] = CivilianMovement.valid_tiles(_model, explorer)
	assert_false(tiles.has(Vector2i(1, 4)), "sea row")
	assert_eq(CivilianMovement.apply_move(
		_model, explorer, Vector2i(1, 4)
	)["ok"], false)


func test_builder_keeps_to_its_crowns_land() -> void:
	var builder := Fixture.unit("builder", Vector2i(2, 1))
	var tiles: Array[Vector2i] = CivilianMovement.valid_tiles(_model, builder)
	assert_false(tiles.has(Vector2i(3, 1)))
	assert_true(tiles.has(Vector2i(2, 0)))
	var refused: Dictionary = CivilianMovement.apply_move(
		_model, builder, Vector2i(3, 1)
	)
	assert_false(bool(refused["ok"]))
	assert_true(String(refused["reason"]).contains("without a war"))
	assert_eq(builder.tile, Vector2i(2, 1))


func test_explorer_may_cross_into_a_rival_province() -> void:
	var explorer := Fixture.unit("explorer", Vector2i(2, 1))
	var result: Dictionary = CivilianMovement.apply_move(
		_model, explorer, Vector2i(3, 1)
	)
	assert_true(bool(result["ok"]))
	assert_eq(explorer.tile, Vector2i(3, 1))


func test_one_move_per_turn() -> void:
	var explorer := Fixture.unit("explorer", Vector2i(1, 1))
	assert_true(bool(CivilianMovement.apply_move(
		_model, explorer, Vector2i(2, 1)
	)["ok"]))
	var second: Dictionary = CivilianMovement.apply_move(
		_model, explorer, Vector2i(2, 2)
	)
	assert_false(bool(second["ok"]))
	assert_true(String(second["reason"]).contains("already moved"))
	assert_eq(explorer.tile, Vector2i(2, 1))


func test_begin_turn_restores_the_move() -> void:
	var explorer := Fixture.unit("explorer", Vector2i(1, 1))
	CivilianMovement.apply_move(_model, explorer, Vector2i(2, 1))
	var units: Array[CivilianState] = [explorer]
	CivilianMovement.begin_turn(units)
	assert_false(explorer.moved)
	assert_true(bool(CivilianMovement.apply_move(
		_model, explorer, Vector2i(2, 2)
	)["ok"]))


func test_working_civilians_stay_on_their_tile() -> void:
	var builder := Fixture.unit("builder", Fixture.IRON_TILE)
	builder.start_work("build_improvement", Fixture.IRON_TILE, 1)
	var result: Dictionary = CivilianMovement.apply_move(
		_model, builder, Vector2i(0, 1)
	)
	assert_false(bool(result["ok"]))
	assert_eq(CivilianMovement.valid_tiles(_model, builder), [])


func test_non_adjacent_tiles_are_refused() -> void:
	var explorer := Fixture.unit("explorer", Vector2i(0, 0))
	var result: Dictionary = CivilianMovement.apply_move(
		_model, explorer, Vector2i(2, 2)
	)
	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("one tile"))
	assert_eq(explorer.tile, Vector2i(0, 0))


func test_out_of_bounds_land_is_refused() -> void:
	assert_false(CivilianMovement.may_enter(_model, "explorer", 0, Vector2i(-1, 0)))
	assert_false(CivilianMovement.may_enter(_model, "explorer", 0, Vector2i(9, 9)))
	assert_true(CivilianMovement.may_enter(_model, "explorer", 0, Vector2i(0, 0)))

# --- from test_civilian_work.gd ---
## Civilian work orders: gates, costs, multi-turn progress and tile effects
## (wiki: civilian-units § Work Types, extraction-and-improvements costs).

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


func test_road_construction_raises_a_road_to_level_two() -> void:
	var tile := Vector2i(0, 1)
	_works.set_transport(_model, tile, LandWorks.TRANSPORT_ROAD)
	var engineer := _add("engineer", tile)
	var locked: Dictionary = _validate(engineer, "build_road")
	assert_false(bool(locked["ok"]))
	assert_true(String(locked["reason"]).contains("already has a road"))
	var tech := {"road_construction": true}
	var check: Dictionary = _validate(engineer, "build_road", tech)
	assert_true(bool(check["ok"]), String(check.get("reason", "")))
	assert_eq(int(check["duration"]), CivilianTransport.ROAD_TURNS)
	assert_true(bool(CivilianWork.assign(
		_model, engineer, "build_road", _works, _units, _stock, _view,
		CivilianState.NO_TILE, {}, tech
	)["ok"]))
	CivilianWork.resolve_turn(_model, _units, _works, _view)
	assert_eq(_works.transport_at(_model, tile), LandWorks.TRANSPORT_IMPROVED_ROAD)
	var capped: Dictionary = _validate(engineer, "build_road", tech)
	assert_false(bool(capped["ok"]))
	assert_true(String(capped["reason"]).contains("improved road"))


func test_rail_builder_lays_rail_on_a_road() -> void:
	var tile := Vector2i(0, 1)
	_works.set_transport(_model, tile, LandWorks.TRANSPORT_ROAD)
	var rail := _add("rail_builder", tile)
	var locked: Dictionary = _validate(rail, "build_rail")
	assert_false(bool(locked["ok"]))
	assert_true(String(locked["reason"]).contains("Early Steam Engine"))
	var tech := {"early_steam_engine": true}
	var check: Dictionary = _validate(rail, "build_rail", tech)
	assert_true(bool(check["ok"]), String(check.get("reason", "")))
	assert_eq(check["cost"], {"lumber": 2, "steel": 2})
	assert_eq(int(check["duration"]), CivilianTransport.RAIL_TURNS)
	assert_true(bool(CivilianWork.assign(
		_model, rail, "build_rail", _works, _units, _stock, _view,
		CivilianState.NO_TILE, {}, tech
	)["ok"]))
	assert_eq(int(_stock["steel"]), 6)
	var first: Array[Dictionary] = CivilianWork.resolve_turn(_model, _units, _works, _view)
	assert_false(bool(first[0]["completed"]))
	assert_eq(_works.transport_at(_model, tile), LandWorks.TRANSPORT_ROAD)
	var second: Array[Dictionary] = CivilianWork.resolve_turn(_model, _units, _works, _view)
	assert_true(bool(second[0]["completed"]))
	assert_eq(_works.transport_at(_model, tile), LandWorks.TRANSPORT_RAIL)


func test_rail_needs_an_existing_road_and_an_unrailed_tile() -> void:
	var tile := Vector2i(0, 1)
	var rail := _add("rail_builder", tile)
	var tech := {"early_steam_engine": true}
	var no_road: Dictionary = _validate(rail, "build_rail", tech)
	assert_false(bool(no_road["ok"]))
	assert_true(String(no_road["reason"]).contains("existing road"))
	_works.set_transport(_model, tile, LandWorks.TRANSPORT_RAIL)
	var railed: Dictionary = _validate(rail, "build_rail", tech)
	assert_false(bool(railed["ok"]))
	assert_true(String(railed["reason"]).contains("already carries a railroad"))


func test_rail_builders_are_exempt_from_tile_exclusivity() -> void:
	var tile := Vector2i(0, 1)
	_works.set_transport(_model, tile, LandWorks.TRANSPORT_ROAD)
	var first := _add("rail_builder", tile)
	var second := _add("rail_builder", tile)
	var tech := {"early_steam_engine": true}
	assert_true(bool(CivilianWork.assign(
		_model, first, "build_rail", _works, _units, _stock, _view,
		CivilianState.NO_TILE, {}, tech
	)["ok"]))
	assert_true(bool(_validate(second, "build_rail", tech)["ok"]))


func test_engineer_builds_a_port_only_on_the_coast() -> void:
	var engineer := _add("engineer", Fixture.IRON_TILE)
	var inland: Dictionary = _validate(engineer, "build_port")
	assert_false(bool(inland["ok"]))
	assert_true(String(inland["reason"]).contains("coastal"))

	engineer.tile = Fixture.COAST_TILE
	var coastal: Dictionary = _validate(engineer, "build_port")
	assert_true(bool(coastal["ok"]), String(coastal.get("reason", "")))
	assert_eq(int(coastal["duration"]), CivilianTransport.PORT_TURNS)
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


func _validate(
	unit: CivilianState, action: String, tech_unlocked: Dictionary = {}
) -> Dictionary:
	return CivilianWork.validate(
		_model, unit, action, _works, _units, _stock, _view,
		CivilianState.NO_TILE, {}, tech_unlocked
	)


func _cost_text(cost: Dictionary) -> String:
	return CivilianWork.cost_text(cost)

# --- from test_improvement_system.gd ---
## Improvement catalog, connectivity, extraction and the estates ledger
## (wiki: extraction-and-improvements, capital-and-connectivity).

func test_catalog_names_follow_the_resource_not_the_level() -> void:
	assert_eq(ImprovementCatalog.base_name(0), "Lumber camp")
	assert_eq(ImprovementCatalog.base_name(1), "Mine")
	assert_eq(ImprovementCatalog.base_name(4), "Farm")
	assert_eq(ImprovementCatalog.base_name(5), "Pasture")
	assert_eq(ImprovementCatalog.base_name(6), "Ranch")
	assert_eq(ImprovementCatalog.display_name(4, 0), "Farm")
	assert_eq(ImprovementCatalog.display_name(4, 3), "Farm (L3)")
	assert_eq(ImprovementCatalog.display_name(-1, 2), "Improvement (L2)")


func test_catalog_maps_resources_to_commodities_and_yield() -> void:
	assert_eq(ImprovementCatalog.commodity(0), "timber")
	assert_eq(ImprovementCatalog.commodity(1), "iron")
	assert_eq(ImprovementCatalog.commodity(4), "grain")
	assert_eq(ImprovementCatalog.yield_for(0, 3), {"timber": 3})
	assert_eq(ImprovementCatalog.yield_for(0, 0), {})
	assert_eq(ImprovementCatalog.production(9), ImprovementCatalog.MAX_LEVEL)
	assert_true(ImprovementCatalog.needs_prospecting(1))
	assert_false(ImprovementCatalog.needs_prospecting(0))


func test_capital_tile_and_its_neighbours_are_connected() -> void:
	var connected: Dictionary = ImprovementSystem.connected_tiles(
		_model, _works, 0, Fixture.BARE_TILE
	)
	assert_true(connected.has(_model.index_of(0, 0)))
	assert_true(connected.has(_model.index_of(0, 1)))
	assert_true(connected.has(_model.index_of(1, 0)))
	assert_false(connected.has(_model.index_of(2, 2)))


func test_roads_extend_connectivity_beyond_the_capital() -> void:
	_works.set_transport(_model, Vector2i(1, 0), LandWorks.TRANSPORT_ROAD)
	_works.set_transport(_model, Vector2i(2, 0), LandWorks.TRANSPORT_ROAD)
	_works.set_transport(_model, Vector2i(2, 1), LandWorks.TRANSPORT_ROAD)
	var connected: Dictionary = ImprovementSystem.connected_tiles(
		_model, _works, 0, Fixture.BARE_TILE
	)
	assert_true(connected.has(_model.index_of(2, 1)))
	assert_true(connected.has(_model.index_of(2, 2)))
	assert_false(connected.has(_model.index_of(3, 1)))


func test_a_built_port_seeds_its_province() -> void:
	_works.add_port(_model, Fixture.COAST_TILE)
	var connected: Dictionary = ImprovementSystem.connected_tiles(
		_model, _works, 0, Fixture.BARE_TILE
	)
	assert_true(connected.has(_model.index_of(1, 3)))
	assert_true(connected.has(_model.index_of(1, 2)))
	assert_eq(ImprovementSystem.town_tile(_model, _works, 0, Fixture.BARE_TILE), Fixture.BARE_TILE)
	assert_eq(ImprovementSystem.town_tile(_model, _works, 1, Fixture.BARE_TILE), Vector2i(-1, -1))


func test_disconnected_improvements_do_not_yield() -> void:
	_works.set_improvement(_model, Fixture.TIMBER_TILE, 1)
	var totals: Dictionary = Extraction.yields(
		_model, 0, -1, {}, _works, Fixture.BARE_TILE
	)
	assert_eq(totals, {})
	assert_eq(int(_stock["lumber"]), 40)


func test_connected_improvements_yield_their_commodity() -> void:
	_works.set_transport(_model, Vector2i(0, 1), LandWorks.TRANSPORT_ROAD)
	_works.set_improvement(_model, Fixture.TIMBER_TILE, 1)
	var totals: Dictionary = Extraction.yields(
		_model, 0, -1, {}, _works, Fixture.BARE_TILE
	)
	assert_eq(totals, {"timber": 1})
	assert_eq(int(_stock["lumber"]), 40)
	assert_eq(ImprovementSystem.output_text({"timber": 2, "grain": 1}), "1 grain · 2 timber")


func test_tech_and_transport_caps_limit_the_yield() -> void:
	assert_eq(ImprovementCatalog.effective_yield(0, 1, {}, 1, 4), 1)
	assert_eq(ImprovementCatalog.effective_yield(0, 4, {"timber": 4}, 1, 4), 1)
	assert_eq(ImprovementCatalog.effective_yield(0, 4, {"timber": 4}, 4, 4), 4)
	assert_eq(ImprovementCatalog.effective_yield(0, 0, {}, 4, 4), 0)


func test_minerals_must_be_prospected_to_yield() -> void:
	_works.set_transport(_model, Vector2i(1, 0), LandWorks.TRANSPORT_ROAD)
	_works.set_improvement(_model, Fixture.IRON_TILE, 1)
	var blocked: Dictionary = Extraction.yields(
		_model, 0, -1, {}, _works, Fixture.BARE_TILE
	)
	assert_eq(blocked, {})
	_works.set_prospected(0, _model, Fixture.IRON_TILE)
	var totals: Dictionary = Extraction.yields(
		_model, 0, -1, {}, _works, Fixture.BARE_TILE
	)
	assert_eq(totals, {"iron": 1})


func test_foreign_estates_never_pay_the_player() -> void:
	_works.set_improvement(_model, Fixture.RIVAL_GRAIN_TILE, 3)
	var totals: Dictionary = Extraction.yields(
		_model, 0, -1, {}, _works, Fixture.BARE_TILE
	)
	assert_eq(totals, {})


func test_ledger_snapshot_exposes_status_and_actions() -> void:
	_works.set_transport(_model, Vector2i(0, 1), LandWorks.TRANSPORT_ROAD)
	_works.set_transport(_model, Fixture.TIMBER_TILE, LandWorks.TRANSPORT_RAIL)
	_works.set_improvement(_model, Fixture.TIMBER_TILE, 2)
	_works.set_improvement(_model, Fixture.IRON_TILE, 1)
	var builder := Fixture.unit("builder", Fixture.BARE_TILE)
	builder.id = 1
	_units.append(builder)
	var snap: Dictionary = ImprovementLedger.snapshot(
		_model, _works, _units, _stock, 0, Fixture.BARE_TILE, {"timber": 4}
	)
	var counts: Dictionary = snap["counts"]
	assert_eq(int(counts["estates"]), 2)
	assert_eq(int(counts["improved"]), 2)
	assert_eq(int(counts["producing"]), 1)
	assert_eq(int(counts["idle_builders"]), 1)
	assert_eq(snap["totals"], {"timber": 2})
	var timber: Dictionary = _row_at(snap, Fixture.TIMBER_TILE)
	assert_eq(String(timber["name"]), "Lumber camp (L2)")
	assert_eq(String(timber["status"]), "producing")
	assert_true(bool(timber["can_build"]))
	assert_eq(int(timber["output"]), 2)
	var iron: Dictionary = _row_at(snap, Fixture.IRON_TILE)
	assert_eq(String(iron["status"]), "unprospected")
	assert_false(bool(iron["can_build"]))
	assert_true(String(iron["build_reason"]).contains("prospect"))


func test_upgrades_above_the_tech_cap_are_refused() -> void:
	_works.set_transport(_model, Vector2i(0, 1), LandWorks.TRANSPORT_ROAD)
	_works.set_improvement(_model, Fixture.TIMBER_TILE, 1)
	var builder := Fixture.unit("builder", Fixture.BARE_TILE)
	builder.id = 1
	_units.append(builder)
	var snap: Dictionary = ImprovementLedger.snapshot(
		_model, _works, _units, _stock, 0, Fixture.BARE_TILE
	)
	var row: Dictionary = _row_at(snap, Fixture.TIMBER_TILE)
	assert_true(bool(row["tech_limited"]))
	assert_eq(int(row["tech_cap"]), 1)
	assert_false(bool(row["can_build"]))
	assert_true(String(row["build_reason"]).contains("tech"))
	assert_eq(int(row["output"]), 1)


func test_researched_techs_let_build_orders_pass_the_cap() -> void:
	_works.set_transport(_model, Vector2i(0, 1), LandWorks.TRANSPORT_ROAD)
	_works.set_improvement(_model, Fixture.TIMBER_TILE, 1)
	var builder := Fixture.unit("builder", Fixture.BARE_TILE)
	builder.id = 1
	_units.append(builder)
	var refused: Dictionary = ImprovementOrders.build(
		_model, _units, _works, _stock, null, 0, Fixture.TIMBER_TILE
	)
	assert_false(bool(refused["ok"]))
	assert_true(String(refused["message"]).contains("tech"))
	var caps: Dictionary = TechCatalog.extraction_caps({"saw_mill": true})
	assert_eq(int(caps["timber"]), 2)
	var allowed: Dictionary = ImprovementOrders.build(
		_model, _units, _works, _stock, null, 0, Fixture.TIMBER_TILE, caps
	)
	assert_true(bool(allowed["ok"]), String(allowed.get("message", "")))
	assert_true(builder.is_working())


func test_ledger_surfaces_an_active_build_and_cancel() -> void:
	var builder := Fixture.unit("builder", Fixture.TIMBER_TILE)
	builder.id = 1
	_units.append(builder)
	assert_true(bool(CivilianWork.assign(
		_model, builder, "build_improvement", _works, _units, _stock, null,
		Fixture.TIMBER_TILE
	)["ok"]))
	var snap: Dictionary = ImprovementLedger.snapshot(
		_model, _works, _units, _stock, 0, Fixture.BARE_TILE
	)
	var row: Dictionary = _row_at(snap, Fixture.TIMBER_TILE)
	assert_eq(String(row["status"]), "building")
	assert_true(bool(row["working"]))
	assert_false(bool(row["can_build"]))
	assert_true(String(row["status_text"]).contains("1 turn"))
	var cancelled: Dictionary = ImprovementOrders.cancel(_model, _units, 0, Fixture.TIMBER_TILE)
	assert_true(bool(cancelled["ok"]))
	assert_true(builder.is_idle())


func test_build_orders_pick_the_nearest_builder() -> void:
	var far := Fixture.unit("builder", Vector2i(2, 2))
	far.id = 9
	var near := Fixture.unit("builder", Vector2i(1, 1))
	near.id = 3
	_units = [far, near]
	assert_eq(ImprovementOrders.nearest_builder(_units, 0, Fixture.TIMBER_TILE), near)
	var result: Dictionary = ImprovementOrders.build(
		_model, _units, _works, _stock, null, 0, Fixture.TIMBER_TILE
	)
	assert_true(bool(result["ok"]), String(result.get("message", "")))
	assert_eq(near.tile, Fixture.TIMBER_TILE)
	assert_true(near.is_working())
	assert_eq(int(_stock["lumber"]), 39)


func test_build_orders_report_when_no_builder_is_free() -> void:
	var result: Dictionary = ImprovementOrders.build(
		_model, _units, _works, _stock, null, 0, Fixture.TIMBER_TILE
	)
	assert_false(bool(result["ok"]))
	assert_true(String(result["message"]).contains("No idle Builder"))


func test_short_inputs_explain_missing_materials() -> void:
	var short: Dictionary = ImprovementSystem.short_inputs(
		{"lumber": 4, "castIron": 4}, {"lumber": 1, "castIron": 9}
	)
	assert_eq(short, {"lumber": 4})


func _row_at(snap: Dictionary, tile: Vector2i) -> Dictionary:
	for row: Dictionary in snap["estates"]:
		if Vector2i(row["tile"]) == tile:
			return row
	return {}
