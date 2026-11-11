extends GdToolsTest
## Crown-road projection for the connectivity lens: own land reads road, town or
## cut; a cut province carries the shortest road still to lay, and laying that
## road links it. Foreign and uncharted ground is never painted.

const WIDTH: int = 9
const HEIGHT: int = 4
const CAPITAL: Vector2i = Vector2i(0, 1)
const TOWN_CUT: Vector2i = Vector2i(4, 1)
const TOWN_PORT: Vector2i = Vector2i(7, 2)
const PLAYER: int = FactionCatalog.PLAYER_FACTION
const RIVAL: int = 3

var _model: MapModel = null
var _works: LandWorks = null


func before_each() -> void:
	_model = _build()
	_works = LandWorks.new()


## Three crowns' worth of ground, all held by the player: a capital province in
## the west, a province whose town stands four tiles from the capital, and a
## province whose town is a landfall port (Town rule, so town development caps
## the yield of its neighbours).
func _build() -> MapModel:
	var model := MapModel.new()
	model.setup(WIDTH, HEIGHT)
	var groups: Dictionary = {0: [], 1: [], 2: []}
	for y in HEIGHT - 1:
		for x in WIDTH:
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			var province_id: int = 0 if x < 3 else (1 if x < 6 else 2)
			model.province[model.index_of(x, y)] = province_id
			(groups[province_id] as Array).append(Vector2i(x, y))
	for x in WIDTH:
		model.terrain[model.index_of(x, HEIGHT - 1)] = MapModel.Terrain.OCEAN
		model.sea_zone[model.index_of(x, HEIGHT - 1)] = 0
	var names: Array[String] = ["Sevilla", "Córdoba", "Granada"]
	var provinces: Array[ProvinceState] = []
	for province_id in 3:
		var tiles: Array[Vector2i] = []
		for raw: Variant in groups[province_id]:
			tiles.append(raw as Vector2i)
		var province := ProvinceState.create(
			province_id, names[province_id], tiles, Vector2(1.0, 1.0),
			tiles.size(), PLAYER, province_id == 0
		)
		provinces.append(province)
	provinces[0].capital_tile = CAPITAL
	provinces[0].town_tile = CAPITAL
	provinces[1].town_tile = TOWN_CUT
	provinces[2].town_tile = TOWN_PORT
	provinces[2].town_development = 2
	model.provinces = provinces
	return model


func _snapshot() -> Dictionary:
	return CrownRoadSurvey.snapshot(_model, _works, PLAYER, CAPITAL)


func _entry(survey: Dictionary, province_id: int) -> Dictionary:
	for raw: Variant in survey.get("provinces", []):
		var entry: Dictionary = raw
		if int(entry["id"]) == province_id:
			return entry
	return {}


func _route(survey: Dictionary, province_id: int) -> Array:
	for raw: Variant in survey.get("routes", []):
		var route: Dictionary = raw
		if int(route["province"]) == province_id:
			return route.get("tiles", [])
	return []


func test_capital_network_reads_as_road() -> void:
	var survey: Dictionary = _snapshot()
	var states: Dictionary = _states(survey)
	assert_eq(String(states.get(_model.index_of(0, 1), "")), CrownRoadSurvey.STATE_ROAD)
	# A tile beside the capital network extracts at its cap, so it reads road too.
	assert_eq(String(states.get(_model.index_of(1, 1), "")), CrownRoadSurvey.STATE_ROAD)
	assert_gt(int(survey["tiles"][CrownRoadSurvey.STATE_ROAD]), 0)


func test_cut_province_reports_the_road_still_to_lay() -> void:
	var survey: Dictionary = _snapshot()
	var entry: Dictionary = _entry(survey, 1)
	assert_eq(String(entry["state"]), CrownRoadSurvey.STATE_CUT)
	assert_false(bool(entry["linked"]))
	# The town stands four tiles from the capital: three road tiles short.
	assert_eq(int(entry["gap"]), 3)
	# The port province is cut too, seven tiles out: the summary counts both.
	assert_eq(int(survey["counts"]["gap"]), 10)
	assert_eq(int(survey["counts"]["cut"]), 2)
	var route: Array = _route(survey, 1)
	assert_eq(route.size(), 3, "the route is one tile per road still to lay")
	assert_eq(route[0], Vector2i(1, 1))
	assert_eq(route[2], Vector2i(3, 1))
	# The town itself is never laid: it extracts once it stands beside the road.
	assert_false(route.has(TOWN_CUT))


func test_laying_the_shown_route_links_the_province() -> void:
	var survey: Dictionary = _snapshot()
	var route: Array = _route(survey, 1)
	assert_false(route.is_empty())
	for raw: Variant in route:
		var tile: Vector2i = raw
		_works.set_transport(_model, tile, LandWorks.TRANSPORT_ROAD)
	var linked: Dictionary = _snapshot()
	var entry: Dictionary = _entry(linked, 1)
	assert_true(bool(entry["linked"]))
	assert_eq(String(entry["state"]), CrownRoadSurvey.STATE_ROAD)
	assert_eq(int(entry["gap"]), 0)
	assert_true(_route(linked, 1).is_empty(), "a linked province needs no route")
	# The port province is still cut, but the new road shortens its gap to four.
	assert_eq(int(linked["counts"]["cut"]), 1)
	assert_eq(int(linked["counts"]["gap"]), 4)


func test_a_port_town_links_and_caps_its_neighbours() -> void:
	_works.add_port(_model, TOWN_PORT)
	var survey: Dictionary = _snapshot()
	var entry: Dictionary = _entry(survey, 2)
	assert_true(bool(entry["linked"]))
	# The port seeds the province's own network, but it is not a road to the
	# crown: its neighbours read town, so town development caps their yield.
	assert_eq(
		String(_states(survey).get(_model.index_of(6, 2), "")),
		CrownRoadSurvey.STATE_TOWN
	)
	var neighbour: Dictionary = {"state": CrownRoadSurvey.STATE_TOWN, "town_level": 2}
	assert_eq(
		CrownRoadSurvey.summary_text(neighbour),
		"Crown road: town only — town level 2 caps its yield"
	)


func test_foreign_land_is_never_painted() -> void:
	var survey: Dictionary = _snapshot()
	var painted: int = _painted_tiles(survey)
	_model.provinces[1].owner = RIVAL
	var foreign: Dictionary = _snapshot()
	assert_eq(_entry(foreign, 1), {}, "a rival province has no crown reading")
	assert_eq(_painted_tiles(foreign), painted - 9)
	assert_eq(int(foreign["counts"]["cut"]), 1, "only the port province is left cut")


func test_uncharted_ground_is_dropped() -> void:
	var visibility := VisibilityModel.new()
	visibility.setup(_model, PLAYER)
	for y in HEIGHT - 1:
		for x in WIDTH:
			visibility.lower_to(
				_model.index_of(x, y), VisibilityModel.Level.UNKNOWN
			)
	visibility.raise_to(_model.index_of(0, 1), VisibilityModel.Level.FULLY_VISIBLE)
	var survey: Dictionary = CrownRoadSurvey.snapshot(
		_model, _works, PLAYER, CAPITAL, visibility
	)
	assert_eq(_entry(survey, 1), {}, "a province the crown has not charted is skipped")
	assert_eq(_painted_tiles(survey), 1, "only the charted capital tile is painted")


func test_runs_cover_every_painted_tile_once() -> void:
	var survey: Dictionary = _snapshot()
	var from_runs: int = 0
	for state: String in CrownRoadSurvey.STATES:
		for raw: Variant in survey["runs"][state]:
			var run: Rect2 = raw
			from_runs += int(run.size.x) * int(run.size.y)
	assert_eq(from_runs, _painted_tiles(survey))


func test_summary_names_the_gap() -> void:
	var survey: Dictionary = _snapshot()
	assert_eq(
		CrownRoadSurvey.summary_text(_entry(survey, 1)),
		"Crown road: 3 road tiles from the crown"
	)
	assert_eq(
		CrownRoadSurvey.summary_text({"state": CrownRoadSurvey.STATE_ROAD}),
		"Crown road: linked by road"
	)
	assert_eq(
		CrownRoadSurvey.summary_text(
			{"state": CrownRoadSurvey.STATE_CUT, "gap": -1}
		),
		"Crown road: no owned-land route to the crown"
	)


# --- helpers -----------------------------------------------------------------


## Tile index -> state, rebuilt from the merged runs the view draws.
func _states(survey: Dictionary) -> Dictionary:
	var states: Dictionary = {}
	for state: String in CrownRoadSurvey.STATES:
		for raw: Variant in survey["runs"][state]:
			var run: Rect2 = raw
			for x in int(run.size.x):
				var tile := Vector2i(int(run.position.x) + x, int(run.position.y))
				states[_model.index_of(tile.x, tile.y)] = state
	return states


func _painted_tiles(survey: Dictionary) -> int:
	var total: int = 0
	for state: String in CrownRoadSurvey.STATES:
		total += int(survey["tiles"][state])
	return total
