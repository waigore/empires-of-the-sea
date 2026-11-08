extends GdToolsTest
## Improvement catalog, connectivity, extraction and the estates ledger
## (wiki: extraction-and-improvements, capital-and-connectivity).

const Fixture = preload("res://tests/civilian_fixture.gd")

var _model: MapModel = null
var _works: LandWorks = null
var _units: Array[CivilianState] = []
var _stock: Dictionary = {}


func before_each() -> void:
	_model = Fixture.build()
	_works = LandWorks.new()
	_units = []
	_stock = Fixture.stockpile()


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
