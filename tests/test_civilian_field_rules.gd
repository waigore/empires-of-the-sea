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


## Order visibility gate (wiki: fog-and-exploration § Order Visibility
## Requirements): a march into a province the crown has never charted is
## refused, even though an Explorer may roam any land.
func test_a_march_into_an_uncharted_province_is_refused() -> void:
	var explorer := Fixture.unit("explorer", Vector2i(2, 0))
	for tile: Vector2i in _model.province_tiles(Fixture.RIVAL_PROVINCE):
		_view.lower_to(_model.index_of(tile.x, tile.y), VisibilityModel.Level.UNKNOWN)
	assert_false(
		CivilianMovement.valid_tiles(_model, explorer, _view).has(Vector2i(3, 0)),
		"the uncharted province is not a march option"
	)
	var result: Dictionary = CivilianMovement.apply_move(
		_model, explorer, Vector2i(3, 0), _view
	)
	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("charted"))
	assert_eq(explorer.tile, Vector2i(2, 0))


## One charted tile anywhere in the province is enough: a coast glimpsed from
## the sea opens the whole province to land orders.
func test_a_glimpsed_province_accepts_the_march() -> void:
	var explorer := Fixture.unit("explorer", Vector2i(2, 0))
	var tiles: Array[Vector2i] = _model.province_tiles(Fixture.RIVAL_PROVINCE)
	for tile: Vector2i in tiles:
		_view.lower_to(_model.index_of(tile.x, tile.y), VisibilityModel.Level.UNKNOWN)
	_view.raise_to(_model.index_of(tiles[0].x, tiles[0].y), VisibilityModel.Level.FOGGED)
	assert_true(
		CivilianMovement.valid_tiles(_model, explorer, _view).has(Vector2i(3, 0))
	)
	assert_true(bool(CivilianMovement.apply_move(
		_model, explorer, Vector2i(3, 0), _view
	)["ok"]))

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
	assert_true(String(check["reason"]).contains("iron, coal, gold and tin"))


func test_tin_tiles_can_be_prospected() -> void:
	# Wiki: fog-and-exploration § Prospect-Required Resources lists tin with the
	# other prospected minerals; refusals left it unopenable and unminable.
	var tile := Vector2i(2, 2)
	_model.resource[_model.index_of(tile.x, tile.y)] = 8
	var explorer := _add("explorer", tile)
	var check: Dictionary = _validate(explorer, "prospect")
	assert_true(bool(check["ok"]), String(check.get("reason", "")))
	CivilianWork.assign(_model, explorer, "prospect", _works, _units, _stock, _view)
	CivilianWork.resolve_turn(_model, _units, _works, _view)
	assert_true(_works.is_prospected(0, _model, tile))


func test_exploring_a_minor_province_needs_a_consulate() -> void:
	var model: MapModel = Fixture.build_minor()
	var works := LandWorks.new()
	var explorer := Fixture.unit("explorer", Vector2i(2, 1))
	var units: Array[CivilianState] = [explorer]
	var view := Fixture.visibility(model)
	var no_court := DiplomacyState.new()
	no_court.initialize(1)
	no_court.ensure_relation(0, 6, 50)
	for action: String in ["explore", "prospect"]:
		var blocked: Dictionary = CivilianWork.validate(
			model, explorer, action, works, units, Fixture.stockpile(), view,
			CivilianState.NO_TILE, {}, {}, {"diplomacy": no_court}
		)
		assert_false(bool(blocked["ok"]), action)
		assert_true(String(blocked["reason"]).contains("consulate"), action)
	var court := Fixture.merchant_court()
	var allowed: Dictionary = CivilianWork.validate(
		model, explorer, "prospect", works, units, Fixture.stockpile(), view,
		CivilianState.NO_TILE, {}, {}, {"diplomacy": court}
	)
	assert_true(bool(allowed["ok"]), String(allowed.get("reason", "")))


func test_a_prospected_tile_cannot_be_prospected_again() -> void:
	var explorer := _add("explorer", Fixture.IRON_TILE)
	_works.set_prospected(0, _model, Fixture.IRON_TILE)
	var check: Dictionary = _validate(explorer, "prospect")
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("already been prospected"))


func test_only_charted_land_can_be_prospected() -> void:
	var explorer := _add("explorer", Fixture.IRON_TILE)
	var index: int = _model.index_of(Fixture.IRON_TILE.x, Fixture.IRON_TILE.y)
	_view.lower_to(index, VisibilityModel.Level.UNKNOWN)
	var check: Dictionary = _validate(explorer, "prospect")
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("charted"))
	_view.raise_to(index, VisibilityModel.Level.FOGGED)
	var allowed: Dictionary = _validate(explorer, "prospect")
	assert_true(bool(allowed["ok"]), String(allowed.get("reason", "")))


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


func test_builder_upgrades_the_town_with_national_bureaucracy() -> void:
	var builder := _add("builder", Fixture.BARE_TILE)
	var blocked: Dictionary = _validate(builder, "upgrade_town")
	assert_false(bool(blocked["ok"]))
	assert_true(String(blocked["reason"]).contains("National Bureaucracy"))
	var tech := {"national_bureaucracy": true}
	var check: Dictionary = _validate(builder, "upgrade_town", tech)
	assert_true(bool(check["ok"]), String(check.get("reason", "")))
	assert_eq(check["cost"], {"lumber": 4, "castIron": 4})
	assert_eq(int(check["duration"]), 2)
	CivilianWork.assign(
		_model, builder, "upgrade_town", _works, _units, _stock, _view,
		CivilianState.NO_TILE, {}, tech
	)
	assert_eq(int(_stock["lumber"]), 36)
	CivilianWork.resolve_turn(_model, _units, _works, _view)
	CivilianWork.resolve_turn(_model, _units, _works, _view)
	assert_eq(_model.provinces[0].town_development, 2)


func test_town_upgrades_only_on_the_town_tile_and_stop_at_four() -> void:
	var builder := _add("builder", Fixture.TIMBER_TILE)
	var tech := {"national_bureaucracy": true}
	var wrong: Dictionary = _validate(builder, "upgrade_town", tech)
	assert_false(bool(wrong["ok"]))
	assert_true(String(wrong["reason"]).contains("town tile"))
	_model.provinces[0].town_development = 4
	var capped: Dictionary = CivilianWork.validate(
		_model, Fixture.unit("builder", Fixture.BARE_TILE), "upgrade_town",
		_works, _units, _stock, _view, CivilianState.NO_TILE, {}, tech
	)
	assert_false(bool(capped["ok"]))
	assert_true(String(capped["reason"]).contains("fully developed"))


func test_town_order_dispatches_the_nearest_builder() -> void:
	_model.provinces[0].town_tile = Fixture.BARE_TILE
	var builder := _add("builder", Fixture.TIMBER_TILE)
	var tech := {"national_bureaucracy": true}
	var result: Dictionary = ImprovementOrders.upgrade_town(
		_model, _units, _works, _stock, _view, 0, Fixture.BARE_TILE, tech
	)
	assert_true(bool(result["ok"]), String(result.get("message", "")))
	assert_true(builder.is_working())
	assert_eq(builder.work_tile(), Fixture.BARE_TILE)
	assert_eq(builder.work_action(), "upgrade_town")


func test_town_order_reports_a_missing_builder() -> void:
	_model.provinces[0].town_tile = Fixture.BARE_TILE
	var result: Dictionary = ImprovementOrders.upgrade_town(
		_model, _units, _works, _stock, _view, 0, Fixture.BARE_TILE,
		{"national_bureaucracy": true}
	)
	assert_false(bool(result["ok"]))
	assert_true(String(result["message"]).contains("No idle Builder"))


func test_scrub_forest_caps_timber_improvements() -> void:
	var builder := _add("builder", Fixture.TIMBER_TILE)
	var index: int = _model.index_of(Fixture.TIMBER_TILE.x, Fixture.TIMBER_TILE.y)
	_model.terrain[index] = MapModel.Terrain.SCRUB_FOREST
	_works.set_improvement(_model, Fixture.TIMBER_TILE, 1)
	var check: Dictionary = CivilianWork.validate(
		_model, builder, "build_improvement", _works, _units, _stock, _view,
		CivilianState.NO_TILE, {"timber": 4}, {"circular_saw": true}
	)
	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("Terrain caps"))


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
	assert_true(String(check["reason"]).contains("Stores are short of"))
	assert_true(String(check["reason"]).contains("lumber"))


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


func test_rail_terrain_techs_gate_hills_swamps_and_mountains() -> void:
	var tile := Vector2i(0, 1)
	var index: int = _model.index_of(tile.x, tile.y)
	_works.set_transport(_model, tile, LandWorks.TRANSPORT_ROAD)
	var rail := _add("rail_builder", tile)
	var early := {"early_steam_engine": true}
	var later := {"early_steam_engine": true, "later_steam_engine": true}
	var powder := {"early_steam_engine": true, "later_steam_engine": true, "dynamite": true}
	_model.terrain[index] = MapModel.Terrain.HILLS
	var hills_locked: Dictionary = _validate(rail, "build_rail", early)
	assert_false(bool(hills_locked["ok"]))
	assert_true(String(hills_locked["reason"]).contains("Later Steam Engine"))
	assert_true(bool(_validate(rail, "build_rail", later)["ok"]))
	_model.terrain[index] = MapModel.Terrain.SWAMP
	assert_true(bool(_validate(rail, "build_rail", later)["ok"]))
	_model.terrain[index] = MapModel.Terrain.MOUNTAINS
	var mountains_locked: Dictionary = _validate(rail, "build_rail", later)
	assert_false(bool(mountains_locked["ok"]))
	assert_true(String(mountains_locked["reason"]).contains("Dynamite"))
	assert_true(bool(_validate(rail, "build_rail", powder)["ok"]))
	_model.terrain[index] = MapModel.Terrain.HARDWOOD_FOREST
	assert_true(bool(_validate(rail, "build_rail", early)["ok"]), "forest is flat ground")


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
			assert_true(String(option["reason"]).contains("iron, coal, gold and tin"))
		else:
			assert_eq(String(option["label"]), "Explore province")
			assert_eq(String(option["cost_text"]), "Free")


func test_idle_units_produce_no_reports() -> void:
	_add("builder", Fixture.IRON_TILE)
	assert_eq(CivilianWork.resolve_turn(_model, _units, _works, _view), [])


# --- merchant land purchase and tile deeds ----------------------------------
## Wiki: civilian-units § Merchant. A Merchant buys a resource tile in a Minor
## Nation or Tribe province, with an embassy, no war and a prospected mineral.


func test_a_spy_walks_into_a_rival_great_powers_land_unchallenged() -> void:
	# Stealth: no war, no declaration, and no order needed to earn its keep
	# (wiki: civilian-units § Spy; DR-20261110-03).
	var spy := Fixture.unit("spy", Vector2i(2, 1))
	var moved: Dictionary = CivilianMovement.apply_move(
		_model, spy, Vector2i(3, 1), _view
	)
	assert_true(bool(moved["ok"]), String(moved.get("reason", "")))
	assert_eq(spy.tile, Vector2i(3, 1))
	assert_false(
		CivilianMovement.may_enter(_model, "builder", 0, Vector2i(3, 1)),
		"a builder needs crown land"
	)


func test_merchant_may_enter_foreign_land_but_a_builder_may_not() -> void:
	var model: MapModel = Fixture.build_minor()
	var merchant := Fixture.unit("merchant", Vector2i(1, 1))
	assert_true(bool(CivilianMovement.apply_move(
		model, merchant, Vector2i(2, 1)
	)["ok"]))
	var builder := Fixture.unit("builder", Vector2i(1, 1))
	assert_false(CivilianMovement.may_enter(model, "builder", 0, Vector2i(2, 1)))


func test_purchase_land_prices_at_fifteen_times_the_base_price() -> void:
	var model: MapModel = Fixture.build_minor()
	assert_eq(LandPurchase.cost(model, Vector2i(3, 1)), 750, "grain")
	assert_eq(LandPurchase.cost(model, Vector2i(2, 1)), 1200, "iron")
	assert_eq(LandPurchase.cost_text(model, Vector2i(3, 1)), "£750")


func test_merchant_purchase_needs_embassy_and_a_clear_sale() -> void:
	var model: MapModel = Fixture.build_minor()
	var works := LandWorks.new()
	var merchant := Fixture.unit("merchant", Vector2i(1, 1))
	var units: Array[CivilianState] = [merchant]
	var stock := Fixture.stockpile()
	var tile := Vector2i(3, 1)
	var no_court := DiplomacyState.new()
	no_court.initialize(1)
	no_court.ensure_relation(0, 6, 1)
	var refused: Dictionary = CivilianWork.validate(
		model, merchant, "purchase_land", works, units, stock, null, tile,
		{}, {}, {"treasury": 5000, "diplomacy": no_court}
	)
	assert_false(bool(refused["ok"]))
	assert_true(String(refused["reason"]).contains("embassy"))
	var court := Fixture.merchant_court()
	DiplomacyRules.declare_war(court, 0, 6)
	var war: Dictionary = CivilianWork.validate(
		model, merchant, "purchase_land", works, units, stock, null, tile,
		{}, {}, {"treasury": 5000, "diplomacy": court}
	)
	assert_false(bool(war["ok"]))
	assert_true(String(war["reason"]).contains("war"))
	var poor := Fixture.merchant_court()
	var cheap: Dictionary = CivilianWork.validate(
		model, merchant, "purchase_land", works, units, stock, null, tile,
		{}, {}, {"treasury": 749, "diplomacy": poor}
	)
	assert_false(bool(cheap["ok"]))
	assert_true(String(cheap["reason"]).contains("treasury"))


func test_minerals_must_be_prospected_before_purchase() -> void:
	var model: MapModel = Fixture.build_minor()
	var works := LandWorks.new()
	var merchant := Fixture.unit("merchant", Vector2i(1, 1))
	var units: Array[CivilianState] = [merchant]
	var iron := Vector2i(2, 1)
	var context: Dictionary = {"treasury": 5000, "diplomacy": Fixture.merchant_court()}
	var blocked: Dictionary = CivilianWork.validate(
		model, merchant, "purchase_land", works, units, Fixture.stockpile(), null,
		iron, {}, {}, context
	)
	assert_false(bool(blocked["ok"]))
	assert_true(String(blocked["reason"]).contains("prospect"))
	works.set_prospected(0, model, iron)
	var allowed: Dictionary = CivilianWork.validate(
		model, merchant, "purchase_land", works, units, Fixture.stockpile(), null,
		iron, {}, {}, context
	)
	assert_true(bool(allowed["ok"]), String(allowed.get("reason", "")))


func test_purchase_completes_one_turn_later_and_debits_the_purse() -> void:
	var model: MapModel = Fixture.build_minor()
	var works := LandWorks.new()
	var merchant := Fixture.unit("merchant", Vector2i(1, 1))
	var units: Array[CivilianState] = [merchant]
	var tile := Vector2i(3, 1)
	var context: Dictionary = {"treasury": 5000, "diplomacy": Fixture.merchant_court()}
	var check: Dictionary = CivilianWork.assign(
		model, merchant, "purchase_land", works, units, Fixture.stockpile(), null,
		tile, {}, {}, context
	)
	assert_true(bool(check["ok"]), String(check.get("reason", "")))
	assert_eq(int(context["treasury"]), 5000, "assign does not debit")
	var economy := PlayerEconomy.starting()
	economy.treasury = 5000
	var reports: Array[Dictionary] = CivilianWork.resolve_turn(
		model, units, works, null, economy
	)
	assert_true(bool(reports[0]["completed"]))
	assert_eq(economy.treasury, 4250, "price is debited at completion")
	assert_true(model.is_purchased_tile(tile))
	assert_eq(model.owner_at(tile.x, tile.y), 0, "tile changes hands")
	assert_eq(model.province_owner(1), 6, "the province stays Genoese")
	assert_false(model.purchase_tile(tile, 7), "one deed per tile")


func test_a_purchased_tile_becomes_an_owned_estate() -> void:
	var model: MapModel = Fixture.build()
	var works := LandWorks.new()
	var tile := Fixture.RIVAL_GRAIN_TILE
	assert_true(model.purchase_tile(tile, 0))
	assert_eq(model.owner_at(tile.x, tile.y), 0)
	assert_false(model.purchase_tile(tile, 1), "no second buyer")
	works.set_improvement(model, tile, 1)
	for step: Vector2i in [Vector2i(1, 0), Vector2i(2, 0), tile]:
		works.set_transport(model, step, LandWorks.TRANSPORT_ROAD)
	var totals: Dictionary = Extraction.yields(
		model, 0, -1, {}, works, Fixture.BARE_TILE
	)
	assert_eq(totals, {"grain": 1}, "the deed yields for its buyer")
	var seller: Dictionary = Extraction.yields(
		model, 1, -1, {}, works, Fixture.BARE_TILE
	)
	assert_eq(seller, {}, "the old owner no longer extracts it")
	var snap: Dictionary = ImprovementLedger.snapshot(
		model, works, [], {}, 0, Fixture.BARE_TILE
	)
	assert_eq(
		int(snap["counts"]["estates"]), 3, "the enclave joins the realm's two estates"
	)
	assert_eq(String(_row_at(snap, tile)["province_name"]), "Coro")


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


## A colony's estates beside its port town are Town-rule connected, so the town's
## own development level caps their yield (wiki: extraction-and-improvements
## § Extraction formula and town development cap).
func test_a_port_town_caps_the_estates_beside_it() -> void:
	var offshoot: Array = _overseas_estate(2, true)
	var model: MapModel = offshoot[0]
	var works: LandWorks = offshoot[1]
	var totals: Dictionary = Extraction.yields(
		model, 0, -1, {"grain": 4}, works, Vector2i(-1, -1)
	)
	assert_eq(totals, {"grain": 2})


## A rail from the landfall lifts the cap: the estate then reaches the crown by
## road, so town development does not limit it.
func test_a_colony_road_lifts_the_town_cap() -> void:
	var offshoot: Array = _overseas_estate(2, true)
	var model: MapModel = offshoot[0]
	var works: LandWorks = offshoot[1]
	works.set_transport(model, Vector2i(0, 1), LandWorks.TRANSPORT_RAIL)
	var totals: Dictionary = Extraction.yields(
		model, 0, -1, {"grain": 4}, works, Vector2i(-1, -1)
	)
	assert_eq(totals, {"grain": 4})


## An inland town caps nothing: only a port town beside the crown's sea path
## limits its neighbours.
func test_an_inland_town_does_not_cap_the_yield() -> void:
	var offshoot: Array = _overseas_estate(2, false)
	var model: MapModel = offshoot[0]
	var works: LandWorks = offshoot[1]
	var resolved: Dictionary = LandConnectivity.resolve(model, works, 0, Vector2i(-1, -1))
	assert_eq(
		LandConnectivity.town_cap_for(model, resolved, 0, model.index_of(0, 1)),
		LandWorks.MAX_IMPROVEMENT
	)


## One colony province: a town at (0,0) and a level-4 grain estate beside it.
## `port` builds the town's harbour; `development` is the town's level.
func _overseas_estate(development: int, port: bool) -> Array:
	var model := MapModel.new()
	model.setup(2, 2)
	var tiles: Array[Vector2i] = []
	for y in 2:
		for x in 2:
			var tile := Vector2i(x, y)
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			model.province[model.index_of(x, y)] = 0
			tiles.append(tile)
			if tile != Vector2i(0, 0):
				model.resource[model.index_of(x, y)] = 4
	var province := ProvinceState.create(0, "Colonia", tiles, Vector2(0.5, 0.5), 4, 0, false)
	province.town_tile = Vector2i(0, 0)
	province.town_development = development
	model.provinces = [province]
	var works := LandWorks.new()
	if port:
		works.add_port(model, Vector2i(0, 0))
	works.set_improvement(model, Vector2i(0, 1), 4)
	return [model, works]


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
	assert_eq(snap["totals"], {"timber": 1})
	var timber: Dictionary = _row_at(snap, Fixture.TIMBER_TILE)
	assert_eq(String(timber["name"]), "Lumber camp (L2)")
	assert_eq(String(timber["status"]), "producing")
	assert_true(bool(timber["can_build"]))
	assert_eq(int(timber["output"]), 1)
	assert_true(String(timber["status_text"]).contains("transport cap 1"))
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

# --- from test_civilian_roster.gd ---------------------------------------------
## Whole-empire roster view-model: region/province grouping, filters and status.
## Kept in this suite so the civilian domain pays one Godot boot (docs/testing.md).

func test_roster_snapshot_spans_both_regions_and_ignores_rivals() -> void:
	var snapshot: Dictionary = CivilianRoster.snapshot(
		_roster_world(), _roster_regions(), 0
	)
	assert_eq(int(snapshot["total"]), 5)
	assert_eq(int(snapshot["by_region"][FactionCatalog.OLD_WORLD]), 3)
	assert_eq(int(snapshot["by_region"][FactionCatalog.NEW_WORLD]), 2)
	assert_eq(int(snapshot["idle"]), 4)
	assert_eq(int(snapshot["working"]), 1)
	assert_eq(int(snapshot["by_type"]["merchant"]), 1)
	assert_eq((snapshot["groups"] as Array).size(), 2, "one posting per region")


func test_roster_region_filter_narrows_to_one_world() -> void:
	var snapshot: Dictionary = CivilianRoster.snapshot(
		_roster_world(), _roster_regions(), 0
	)
	assert_eq(CivilianRoster.count(snapshot, CivilianRoster.REGION_ALL), 5)
	assert_eq(CivilianRoster.count(snapshot, CivilianRoster.REGION_OLD), 3)
	assert_eq(CivilianRoster.count(snapshot, CivilianRoster.REGION_NEW), 2)
	for group: Dictionary in CivilianRoster.groups(snapshot, CivilianRoster.REGION_NEW):
		assert_eq(int(group["region"]), FactionCatalog.NEW_WORLD)


func test_roster_craft_filter_and_chip_counts() -> void:
	var snapshot: Dictionary = CivilianRoster.snapshot(
		_roster_world(), _roster_regions(), 0
	)
	assert_eq(CivilianRoster.count(snapshot, CivilianRoster.REGION_ALL, "merchant"), 1)
	assert_eq(CivilianRoster.count(snapshot, CivilianRoster.REGION_OLD, "merchant"), 0)
	var counts: Dictionary = CivilianRoster.type_counts(snapshot, CivilianRoster.REGION_OLD)
	assert_eq(int(counts["explorer"]), 1)
	assert_eq(int(counts["builder"]), 1)
	assert_eq(int(counts["merchant"]), 0)


func test_roster_rows_carry_posting_and_work_status() -> void:
	var snapshot: Dictionary = CivilianRoster.snapshot(
		_roster_world(), _roster_regions(), 0
	)
	var merchant: Dictionary = _row_of_type(snapshot, "merchant")
	assert_eq(String(merchant["province_name"]), "Veracruz")
	assert_eq(int(merchant["region"]), FactionCatalog.NEW_WORLD)
	assert_true(String(merchant["status_text"]).contains("Build improvement"))
	assert_true(String(merchant["status_text"]).contains("2 turns to go"))
	assert_almost_eq(float(merchant["progress"]), 0.0, 0.001)
	var explorer: Dictionary = _row_of_type(snapshot, "explorer")
	assert_eq(String(explorer["status_text"]), "Idle — ready for orders")


func test_roster_empty_inputs_make_an_empty_roster() -> void:
	var snapshot: Dictionary = CivilianRoster.snapshot(null, null, 0)
	assert_eq(int(snapshot["total"]), 0)
	assert_true((snapshot["groups"] as Array).is_empty())
	for type_id: String in CivilianCatalog.ORDER:
		assert_eq(int(snapshot["by_type"][type_id]), 0)


func _roster_regions() -> MapRegionTable:
	var table := MapRegionTable.new()
	var old_units: Array[CivilianState] = []
	old_units.append(_roster_unit(1, 0, "explorer", Vector2i(0, 0)))
	old_units.append(_roster_unit(2, 0, "builder", Vector2i(0, 2)))
	old_units.append(_roster_unit(3, 0, "spy", Vector2i(1, 1)))
	old_units.append(_roster_unit(4, 1, "spy", Vector2i(2, 0)))
	table.set_region(FactionCatalog.OLD_WORLD, old_units)

	var new_units: Array[CivilianState] = []
	var merchant: CivilianState = _roster_unit(5, 0, "merchant", Vector2i(0, 0))
	merchant.start_work("build_improvement", Vector2i(0, 1), 2, Vector2i(0, 0))
	new_units.append(merchant)
	new_units.append(_roster_unit(6, 0, "rail_builder", Vector2i(0, 2)))
	table.set_region(FactionCatalog.NEW_WORLD, new_units)
	return table


func _roster_world() -> WorldMap:
	var old: MapModel = Fixture.build()
	var new: MapModel = Fixture.build()
	new.region_id = FactionCatalog.NEW_WORLD
	new.provinces[0].name = "Veracruz"
	var world := WorldMap.new()
	world.add_region(old)
	world.add_region(new)
	return world


func _roster_unit(
	id: int, owner: int, type_id: String, tile: Vector2i
) -> CivilianState:
	return CivilianState.create(id, owner, type_id, tile)


func _row_of_type(snapshot: Dictionary, type_id: String) -> Dictionary:
	for raw: Variant in snapshot["rows"]:
		var row: Dictionary = raw
		if String(row["type_id"]) == type_id:
			return row
	return {}
