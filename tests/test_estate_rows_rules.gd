extends GdToolsTest
## [EstateRows]: the one-estate reading the management ledger groups and totals
## (wiki: extraction-and-improvements § Estates; REQ-P3-03). The ledger's own
## suites read the grouped snapshot, so this proves the row kit's statuses and
## its single-tile reading directly.

const Fixture = preload("res://tests/civilian_fixture.gd")


var _model: MapModel = null
var _works: LandWorks = null


func before_each() -> void:
	_model = Fixture.build()
	_works = LandWorks.new()


func test_priority_orders_a_building_estate_first_and_an_unknown_last() -> void:
	assert_eq(EstateRows.priority("building"), 0)
	assert_eq(EstateRows.priority("producing"), 1)
	assert_lt(EstateRows.priority("maxed"), 9, "a known status sorts before an unknown")
	assert_eq(EstateRows.priority("paved"), 9, "an unknown status sorts last")


func test_status_reads_work_before_level_and_a_mineral_before_vacancy() -> void:
	var builder := Fixture.unit("builder", Fixture.TIMBER_TILE)
	builder.start_work("build_improvement", Fixture.TIMBER_TILE, 1)
	assert_eq(
		EstateRows.status_for(0, true, builder, false, false), "building",
		"a Builder at work outranks a vacant estate"
	)
	assert_eq(
		EstateRows.status_for(0, true, null, true, false), "unprospected",
		"a known but unsurveyed mineral is never vacant"
	)
	assert_eq(EstateRows.status_for(0, true, null, true, true), "vacant")
	assert_eq(EstateRows.status_for(2, false, null, false, false), "disconnected")
	assert_eq(
		EstateRows.status_for(ImprovementCatalog.MAX_LEVEL, true, null, false, false),
		"maxed"
	)
	assert_eq(EstateRows.status_for(1, true, null, false, false), "producing")


func test_a_linked_estate_row_carries_no_road_gap_claim() -> void:
	_works.set_improvement(_model, Fixture.TIMBER_TILE, 2)
	var row: Dictionary = EstateRows.project(
		_model, _works, [], {}, 0, Fixture.TIMBER_TILE,
		_model.resource_at(Fixture.TIMBER_TILE.x, Fixture.TIMBER_TILE.y),
		Fixture.PLAYER_PROVINCE,
		{"transport": LandWorks.TRANSPORT_ROAD}, {"network": {}}, [], {"timber": 2}
	)
	assert_eq(int(row["level"]), 2)
	assert_eq(String(row["status"]), "producing")
	assert_true(bool(row["connected"]))
	assert_eq(int(row["link_distance"]), 0)
	assert_eq(int(row["builder_id"]), -1, "no idle Builder musters")
	assert_true(String(row["status_text"]).contains("Yields"))
	assert_false(
		String(row["status_text"]).contains("to the crown network"),
		"a linked estate carries no road-gap claim"
	)


func test_an_unlinked_estate_row_names_its_condition_and_refusal() -> void:
	_works.set_improvement(_model, Fixture.TIMBER_TILE, 2)
	var row: Dictionary = EstateRows.project(
		_model, _works, [], {}, 0, Fixture.TIMBER_TILE,
		_model.resource_at(Fixture.TIMBER_TILE.x, Fixture.TIMBER_TILE.y),
		Fixture.PLAYER_PROVINCE, {}, {"network": {}}, [], {}
	)
	assert_false(bool(row["connected"]))
	assert_eq(String(row["status"]), "disconnected")
	assert_false(bool(row["can_build"]))
	assert_true(
		String(row["build_reason"]).contains("tech"),
		"the refusal names the first gate that blocks the estate: %s"
		% String(row["build_reason"])
	)


func test_an_unsurveyed_mineral_reads_unprospected_until_an_explorer_reads_it() -> void:
	var row: Dictionary = EstateRows.project(
		_model, _works, [], {}, 0, Fixture.IRON_TILE,
		_model.resource_at(Fixture.IRON_TILE.x, Fixture.IRON_TILE.y),
		Fixture.PLAYER_PROVINCE,
		{"transport": LandWorks.TRANSPORT_ROAD}, {"network": {}}, [], {}
	)
	assert_eq(String(row["status"]), "unprospected")
	assert_true(bool(row["needs_prospecting"]))
	assert_false(bool(row["prospected"]))
	assert_false(bool(row["can_build"]))
	assert_true(String(row["build_reason"]).contains("prospect"))
