extends GdToolsTest
## The sea's node-free passes (REQ-P3-03): a turn's battles resolve in every
## region and the drowned leave their roster, while the roster surgery a
## hand-over, a passage and a battle need lives in FleetRosters, where the layer,
## the save and the AI read the same list (wiki: map-topology § two regions;
## ships-and-naval § Naval Combat, § Ports that change hands).

const NavalFixture = preload("res://tests/naval_fixture.gd")

const OWNER: int = 0
const RIVAL: int = 1
const CARIBBEAN: int = 0


## --- the battle pass --------------------------------------------------------


func test_every_region_fights_and_names_its_battle() -> void:
	var world: WorldMap = _world()
	var regions: MapRegionTable = _regions()

	var battles: Array[Dictionary] = NavalBattles.resolve_region_turn(
		world, regions, _war, {"seed": 7, "turn": 3}
	)

	assert_true(battles.size() >= 1, "two crowns at war in one zone fight")
	for battle: Dictionary in battles:
		assert_eq(int(battle["region"]), 0, "only the Old World's zone is contested")
	assert_eq(
		(regions.value(1, []) as Array).size(), 2,
		"a region with no battle keeps the roster it had"
	)


func test_a_beaten_squadron_leaves_its_region() -> void:
	var world: WorldMap = _world()
	var regions: MapRegionTable = _regions()

	NavalBattles.resolve_region_turn(world, regions, _war, {"seed": 7, "turn": 3})

	var old_world: Array[FleetState] = []
	old_world.assign(regions.value(0, []))
	assert_eq(old_world.size(), 1, "the lone hull goes down and its squadron leaves the roster")
	assert_eq(old_world[0].owner, OWNER, "the victor keeps the sea")
	assert_true(old_world[0].is_afloat())


func test_no_hostility_leaves_the_sea_alone() -> void:
	var world: WorldMap = _world()
	var regions: MapRegionTable = _regions()

	var battles: Array[Dictionary] = NavalBattles.resolve_region_turn(
		world, regions, _peace, {"seed": 7, "turn": 3}
	)

	assert_true(battles.is_empty(), "peace spills no blood")
	assert_eq((regions.value(0, []) as Array).size(), 2, "both squadrons keep the sea")


## --- roster surgery ---------------------------------------------------------


func test_prune_drops_a_squadron_with_no_hulls() -> void:
	var live: FleetState = FleetState.at_sea(1, OWNER, CARIBBEAN, ["ship_1"])
	var sunk: FleetState = FleetState.at_sea(2, RIVAL, CARIBBEAN, ["ship_2"])
	sunk.hulls.clear()
	var roster: Array[FleetState] = [live, sunk, null]

	FleetRosters.prune(roster)

	assert_eq(roster.size(), 2, "a hauled-out squadron leaves")
	assert_eq(roster[0], live, "the live command keeps its berth")
	assert_null(roster[1], "a null slot is not the same as a sunk one: only hulls decide")


func test_hand_over_recolours_or_retires_a_crowns_squadrons() -> void:
	var roster: Array[FleetState] = [
		FleetState.at_sea(1, RIVAL, CARIBBEAN, ["ship_1"]),
		FleetState.at_sea(2, OWNER, CARIBBEAN, ["ship_2"]),
	]

	FleetRosters.hand_over(roster, RIVAL, OWNER)

	assert_eq(roster.size(), 2, "an absorption keeps every hull")
	assert_eq(roster[0].owner, OWNER, "the loser's colours change")

	FleetRosters.hand_over(roster, OWNER, MapModel.NO_ID)

	assert_true(roster.is_empty(), "a terminal fall retires every squadron it owned")


func test_a_passage_renumbers_the_crossing_squadron() -> void:
	var regions: MapRegionTable = _regions()
	var from: Array[FleetState] = []
	from.assign(regions.value(0, []))
	var crossing: FleetState = from[0]

	var destination: Array[FleetState] = FleetRosters.hand_to_region(
		regions, 0, crossing, 1, from
	)

	assert_eq(destination.size(), 3, "the squadron lands in the other roster")
	assert_eq(int((regions.value(0, []) as Array).size()), 1, "and leaves the one it sailed from")
	assert_eq(crossing.id, 5, "it takes the next free id across every region")
	var ids: Array[int] = []
	for region: Array in FleetRosters.all(regions):
		for fleet: FleetState in region:
			ids.append(fleet.id)
	ids.sort()
	assert_eq(ids, [2, 3, 4, 5] as Array[int], "both rosters list every hull and no id twice")


func test_zones_at_sea_lists_each_zone_once() -> void:
	var roster: Array[FleetState] = [
		FleetState.at_sea(1, OWNER, CARIBBEAN, ["ship_1"]),
		FleetState.at_sea(2, OWNER, CARIBBEAN, ["ship_2"]),
		FleetState.at_sea(3, OWNER, 1, ["ship_3"]),
		FleetState.at_sea(4, RIVAL, 1, ["ship_4"]),
		FleetState.in_port(5, OWNER, 0, ["ship_5"]),
	]

	assert_eq(
		FleetRosters.zones_at_sea(roster, OWNER), [CARIBBEAN, 1] as Array[int],
		"one entry per zone the crown holds, and no port"
	)
	assert_true(FleetRosters.zones_at_sea(roster, 9).is_empty(), "a crown at no sea holds no zone")


func test_each_visits_every_region_roster() -> void:
	var regions: MapRegionTable = _regions()
	var seen: Array[int] = []

	FleetRosters.each(
		regions, func(roster: Array[FleetState]) -> void: seen.append(roster.size())
	)

	seen.sort()
	assert_eq(seen, [2, 2] as Array[int], "every stored roster is visited once")


## --- berths -----------------------------------------------------------------


func test_prune_drops_the_marker_of_a_sunk_squadron() -> void:
	var markers := ShipMarkers.new()
	markers.model = NavalFixture.build()
	var kept: FleetState = FleetState.at_sea(1, OWNER, CARIBBEAN, ["ship_1"])
	var sunk: FleetState = FleetState.at_sea(2, RIVAL, CARIBBEAN, ["ship_2"])
	var kept_marker: Ship = markers.make(kept)
	var sunk_marker: Ship = markers.make(sunk)
	markers.selected_ship = sunk_marker

	markers.prune([kept] as Array[FleetState])

	assert_eq(markers.ships.size(), 1, "only the squadron still on the roster keeps a marker")
	assert_eq(markers.ships[0], kept_marker)
	assert_null(markers.selected_ship, "a selection cannot outlive the hull that wore it")
	markers.remove(kept_marker)


func test_a_port_berth_prefers_the_registered_tile() -> void:
	var model: MapModel = NavalFixture.build()

	assert_eq(
		ShipMarkers.port_position(model, 0),
		MapGeo.tile_center(1, 0, ShipMarkers.TILE_SIZE),
		"the harbour tile is the berth"
	)
	model.provinces[0].port_tile = Vector2i(-1, -1)
	assert_eq(
		ShipMarkers.port_position(model, 0),
		model.province_center(0) * ShipMarkers.TILE_SIZE,
		"a province with no harbour tile berths at its centre"
	)


## --- fixtures ---------------------------------------------------------------


## Two Old-World charts: region 0 is at war over the Caribbean with four carracks
## against one sloop, region 1 keeps two squadrons of one crown in company.
func _world() -> WorldMap:
	var world := WorldMap.new()
	for index in 2:
		var model: MapModel = NavalFixture.build()
		model.region_id = index
		world.add_region(model)
	return world


func _regions() -> MapRegionTable:
	var regions := MapRegionTable.new()
	var strong: Array[FleetState] = [
		FleetState.at_sea(
			1, OWNER, CARIBBEAN, ["ship_1", "ship_2", "ship_3", "ship_4"],
			{"ship_1": "carrack", "ship_2": "carrack", "ship_3": "carrack", "ship_4": "carrack"}
		),
	]
	var weak: Array[FleetState] = [
		FleetState.at_sea(2, RIVAL, CARIBBEAN, ["ship_5"], {"ship_5": "sloop"}),
	]
	var company: Array[FleetState] = [
		FleetState.at_sea(3, RIVAL, CARIBBEAN, ["ship_6"], {"ship_6": "carrack"}),
		FleetState.at_sea(4, RIVAL, CARIBBEAN, ["ship_7"], {"ship_7": "carrack"}),
	]
	var old_world: Array[FleetState] = []
	old_world.append_array(strong)
	old_world.append_array(weak)
	regions.set_region(0, old_world)
	regions.set_region(1, company)
	return regions


## The court's war query: the two crowns of the Old World are at war.
func _war(a: int, b: int) -> bool:
	return (a == OWNER and b == RIVAL) or (a == RIVAL and b == OWNER)


## The same query in peacetime: no pair is hostile.
func _peace(_a: int, _b: int) -> bool:
	return false
