extends GdToolsTest
## The crown's road works (wiki: capital-and-connectivity § Connectivity,
## civilian-units § Work Order Summary): the route that links a cut-off estate
## and the Engineer dispatch the province dossier's Build road control makes
## (issue #671). One boot for the route, the plan and the order.

const Fixture = preload("res://tests/civilian_fixture.gd")

## The fixture's developed estate off the crown road: (1,1) is diagonal to the
## capital at (0,0), so it yields nothing until a road reaches it.
const CUT_ESTATE: Vector2i = Vector2i(1, 1)
## Beside the capital's own network, so it already extracts.
const LINKED_ESTATE: Vector2i = Vector2i(1, 0)
const CAPITAL: Vector2i = Vector2i(0, 0)

var _model: MapModel = null
var _works: LandWorks = null
var _units: Array[CivilianState] = []
var _stock: Dictionary = {}
var _view: VisibilityModel = null


func before_each() -> void:
	_model = Fixture.build()
	_works = LandWorks.new()
	_works.set_improvement(_model, CUT_ESTATE, 1)
	_works.set_improvement(_model, LINKED_ESTATE, 2)
	_units = []
	_stock = Fixture.stockpile()
	_view = Fixture.visibility(_model)


func _resolved() -> Dictionary:
	return LandConnectivity.resolve(_model, _works, 0, CAPITAL)


func _engineer(tile: Vector2i = Vector2i(0, 2)) -> CivilianState:
	var unit: CivilianState = Fixture.unit("engineer", tile)
	_units.append(unit)
	return unit


# --- the route ---------------------------------------------------------------


## The route is the tiles between the crown network and the estate: the network
## tile is already roaded and the estate extracts as soon as it stands beside
## the road, so neither is laid.
func test_the_route_lays_only_the_tiles_between_the_network_and_the_estate() -> void:
	var route: Array[Vector2i] = RoadWorks.route(
		_model, 0, _resolved()["network"], CUT_ESTATE
	)
	assert_eq(route.size(), 1, "one road tile links the cut-off estate")
	var step: Vector2i = route[0]
	assert_true(
		absi(step.x - CAPITAL.x) + absi(step.y - CAPITAL.y) == 1,
		"the first tile is the one beside the crown network"
	)
	assert_false(route.has(CUT_ESTATE), "the estate tile itself is never laid")


## A tile the crown does not hold has no owned-land route at all.
func test_a_foreign_tile_has_no_route() -> void:
	var route: Array[Vector2i] = RoadWorks.route(
		_model, 0, _resolved()["network"], Fixture.RIVAL_GRAIN_TILE
	)
	assert_true(route.is_empty(), "the route never crosses another crown's land")


func test_an_empty_network_has_no_route() -> void:
	var route: Array[Vector2i] = RoadWorks.route(_model, 0, {}, CUT_ESTATE)
	assert_true(route.is_empty(), "no crown network, nothing to extend")


func test_a_missing_map_reads_no_plan() -> void:
	var plan: Dictionary = RoadWorks.plan(null, _works, _units, 0, CAPITAL, CUT_ESTATE)
	assert_false(bool(plan["needed"]), "nothing to read without a chart")
	plan = RoadWorks.plan(_model, _works, _units, -1, CAPITAL, CUT_ESTATE)
	assert_false(bool(plan["needed"]), "no crown, no estate of ours")


# --- the plan the dossier reads ----------------------------------------------


func test_a_cut_off_estate_needs_a_road() -> void:
	var plan: Dictionary = RoadWorks.plan(
		_model, _works, _units, 0, CAPITAL, CUT_ESTATE, _resolved()
	)
	assert_true(bool(plan["needed"]), "the estate is developed and cut off")
	assert_eq(int(plan["gap"]), 1, "one road tile still to lay")
	assert_false(bool(plan["engineer"]), "no crew musters yet")
	assert_true(
		String(plan["reason"]).contains("Engineer"),
		"the reason names the missing crew: %s" % plan["reason"]
	)


func test_a_linked_estate_needs_no_road() -> void:
	var plan: Dictionary = RoadWorks.plan(
		_model, _works, _units, 0, CAPITAL, LINKED_ESTATE, _resolved()
	)
	assert_false(bool(plan["needed"]), "an estate beside the road already extracts")


## A bare tile is the Build control's business: a road under it would still
## yield nothing (wiki: extraction-and-improvements).
func test_a_bare_estate_needs_no_road() -> void:
	var plan: Dictionary = RoadWorks.plan(
		_model, _works, _units, 0, CAPITAL, Fixture.BARE_TILE, _resolved()
	)
	assert_false(bool(plan["needed"]), "an unimproved tile has no yield to link")


func test_a_foreign_estate_needs_no_road() -> void:
	var plan: Dictionary = RoadWorks.plan(
		_model, _works, _units, 0, CAPITAL, Fixture.RIVAL_GRAIN_TILE, _resolved()
	)
	assert_false(bool(plan["needed"]), "another crown's estate is not ours to road")


## The dossier resolves the crown network once and hands it in, so a province of
## many estates costs one BFS (REQ-P4-01). The reading must not change.
func test_the_plan_reads_the_network_the_dossier_handed_in() -> void:
	var handed: Dictionary = RoadWorks.plan(
		_model, _works, _units, 0, CAPITAL, CUT_ESTATE, _resolved()
	)
	var fresh: Dictionary = RoadWorks.plan(
		_model, _works, _units, 0, CAPITAL, CUT_ESTATE
	)
	assert_eq(int(handed["gap"]), int(fresh["gap"]), "same gap either way")
	assert_eq(
		(handed["route"] as Array).size(), (fresh["route"] as Array).size(),
		"same route either way"
	)


# --- the dispatch ------------------------------------------------------------


func test_dispatch_refuses_without_an_engineer() -> void:
	var result: Dictionary = RoadWorks.dispatch(
		_model, _units, _works, _stock, _view, 0, CAPITAL, CUT_ESTATE
	)
	assert_false(bool(result["ok"]), "no crew, no order")
	assert_true(
		String(result["message"]).contains("Engineer"),
		"the refusal names the crew: %s" % result["message"]
	)


func test_dispatch_puts_the_engineer_on_the_first_road_tile() -> void:
	var engineer: CivilianState = _engineer()
	var result: Dictionary = RoadWorks.dispatch(
		_model, _units, _works, _stock, _view, 0, CAPITAL, CUT_ESTATE
	)
	assert_true(bool(result["ok"]), String(result["message"]))
	assert_true(engineer.is_working(), "the Engineer takes the order")
	assert_eq(engineer.work_action(), "build_road")
	assert_true(
		engineer.work_tile() != CUT_ESTATE,
		"the crew roads the tile beside the estate, not the estate itself"
	)
	assert_true(
		String(result["message"]).contains("last road tile"),
		"a one-tile gap reads as the last tile: %s" % result["message"]
	)


## The order is the rules' own: the road lands on completion and the estate
## starts reaching the crown (wiki: civilian-units § Work Types).
func test_the_road_links_the_estate_when_the_work_completes() -> void:
	_engineer()
	RoadWorks.dispatch(_model, _units, _works, _stock, _view, 0, CAPITAL, CUT_ESTATE)
	CivilianWork.resolve_turn(_model, _units, _works, _view)
	var plan: Dictionary = RoadWorks.plan(
		_model, _works, _units, 0, CAPITAL, CUT_ESTATE
	)
	assert_false(bool(plan["needed"]), "the estate reaches the crown now")
	var tiles: Dictionary = _resolved()["tiles"]
	assert_true(
		tiles.has(_model.index_of(CUT_ESTATE.x, CUT_ESTATE.y)),
		"the estate is on the crown's network"
	)


## A second press on a linked estate is refused, never a silent no-op.
func test_dispatch_refuses_an_estate_that_already_reaches_the_crown() -> void:
	_engineer()
	var result: Dictionary = RoadWorks.dispatch(
		_model, _units, _works, _stock, _view, 0, CAPITAL, LINKED_ESTATE
	)
	assert_false(bool(result["ok"]))
	assert_true(
		String(result["message"]).contains("already reaches"),
		String(result["message"])
	)


## A gap of several tiles reads as the first of them, so the court knows the
## link is a road works, not one order (issue #671).
func test_a_multi_tile_gap_reads_as_the_first_of_many() -> void:
	var far: Vector2i = Vector2i(2, 3)
	_works.set_improvement(_model, far, 1)
	var plan: Dictionary = RoadWorks.plan(
		_model, _works, _units, 0, CAPITAL, far, _resolved()
	)
	assert_true(bool(plan["needed"]), "the far estate is cut off")
	assert_gt(int(plan["gap"]), 1, "more than one road tile to lay")
	_engineer()
	var result: Dictionary = RoadWorks.dispatch(
		_model, _units, _works, _stock, _view, 0, CAPITAL, far
	)
	assert_true(bool(result["ok"]), String(result["message"]))
	assert_true(
		String(result["message"]).contains("first of"),
		String(result["message"])
	)
