extends GdToolsTest
## Squadrons in a port that changes hands (wiki: ships-and-naval § Ports that
## change hands; DR-20261109-11, DR-20261109-12).
##
## The shared naval fixture gives two coastal provinces with one sea zone each;
## a local chart adds an inland province so the no-coast scuttle and the inland
## seat fallback stay readable.

const Fixture = preload("res://tests/naval_fixture.gd")

const SEAT: int = 0
const HARBOUR: int = 1


func test_a_squadron_in_a_captured_port_sorts_out_to_the_lowest_zone() -> void:
	var model: MapModel = Fixture.build()
	var fleet: FleetState = FleetState.in_port(1, 0, SEAT, ["ship_1"])
	model.province_data(SEAT).owner = 1

	var reports: Array[Dictionary] = NavalPortLoss.evict_stranded(model, [fleet])

	assert_eq(reports.size(), 1)
	assert_false(bool(reports[0]["scuttled"]))
	assert_eq(int(reports[0]["zone"]), 0)
	assert_true(fleet.is_at_sea())
	assert_eq(fleet.sea_zone, 0)
	assert_eq(fleet.province, MapModel.NO_ID)
	assert_true(fleet.moved, "the sortie spends the squadron's move")


func test_a_squadron_with_no_coast_is_scuttled() -> void:
	var model: MapModel = _inland_chart()
	var fleet: FleetState = FleetState.in_port(1, 1, HARBOUR, ["ship_1"])

	var reports: Array[Dictionary] = NavalPortLoss.evict_stranded(model, [fleet])

	assert_eq(reports.size(), 1)
	assert_true(bool(reports[0]["scuttled"]))
	assert_eq(int(reports[0]["zone"]), MapModel.NO_ID)
	assert_true(fleet.is_afloat(), "the report keeps the hull list for the toast")


func test_an_empty_slip_is_dropped_without_a_report() -> void:
	var model: MapModel = Fixture.build()
	var slip: FleetState = FleetState.empty_in_port(1, 0, SEAT)
	model.province_data(SEAT).owner = 1
	var roster: Array[FleetState] = [slip]

	var reports: Array[Dictionary] = NavalPortLoss.evict_stranded(model, roster)

	assert_true(reports.is_empty())
	assert_true(roster.is_empty())


func test_an_owned_port_keeps_its_squadron_moored() -> void:
	var model: MapModel = Fixture.build()
	var fleet: FleetState = FleetState.in_port(1, 0, SEAT, ["ship_1"])

	var reports: Array[Dictionary] = NavalPortLoss.evict_stranded(model, [fleet])

	assert_true(reports.is_empty())
	assert_true(fleet.is_in_port())
	assert_eq(fleet.province, SEAT)


func test_a_seaboard_seat_re_moors_the_home_squadron() -> void:
	var model: MapModel = Fixture.build()
	var fleet: FleetState = FleetState.in_port(1, 0, SEAT, ["ship_1"])
	model.province_data(HARBOUR).owner = 0

	var result: Dictionary = NavalPortLoss.relocate_home(model, [fleet], 0, SEAT, HARBOUR)

	assert_eq(int(result["merged"]), 0)
	assert_eq((result["moved"] as Array).size(), 1)
	assert_eq(fleet.province, HARBOUR)
	assert_true(fleet.is_in_port())
	assert_eq(fleet.hulls, ["ship_1"])


func test_an_inland_seat_leaves_the_home_squadron_to_sort_out() -> void:
	var model: MapModel = _inland_chart()
	var fleet: FleetState = FleetState.in_port(1, 0, SEAT, ["ship_1"])

	var result: Dictionary = NavalPortLoss.relocate_home(model, [fleet], 0, SEAT, HARBOUR)

	assert_true((result["moved"] as Array).is_empty())
	assert_eq(fleet.province, SEAT, "the eviction pass owns the inland fallback")
	model.province_data(SEAT).owner = 1
	NavalPortLoss.evict_stranded(model, [fleet])
	assert_true(fleet.is_at_sea())
	assert_eq(fleet.sea_zone, 0)


func test_a_squadron_at_the_new_seat_absorbs_the_home_squadron() -> void:
	var model: MapModel = Fixture.build()
	var home: FleetState = FleetState.in_port(1, 0, SEAT, ["ship_1"])
	var moored: FleetState = FleetState.in_port(2, 0, HARBOUR, ["ship_2"])
	model.province_data(HARBOUR).owner = 0
	var roster: Array[FleetState] = [home, moored]

	var result: Dictionary = NavalPortLoss.relocate_home(model, roster, 0, SEAT, HARBOUR)

	assert_eq(int(result["merged"]), 1)
	assert_eq(roster.size(), 1)
	assert_eq(roster[0], moored)
	assert_eq(moored.hulls, ["ship_2", "ship_1"])


## The re-mooring is administrative: the absorbed squadron keeps its colonists
## and troops, and a second army goes ashore at the new seat instead of being
## lost (wiki: ships-and-naval § Ports that change hands; DR-20261109-11).
func test_the_absorbed_squadron_keeps_its_passengers() -> void:
	var model: MapModel = Fixture.build()
	var home: FleetState = FleetState.in_port(1, 0, SEAT, ["ship_1", "ship_2"])
	var moored: FleetState = FleetState.in_port(2, 0, HARBOUR, ["ship_3", "ship_4"])
	model.province_data(HARBOUR).owner = 0
	home.add_civilian(11)
	home.embarked_army = 21
	var roster: Array[FleetState] = [home, moored]

	var result: Dictionary = NavalPortLoss.relocate_home(model, roster, 0, SEAT, HARBOUR)

	assert_eq(int(result["merged"]), 1)
	assert_true(moored.has_civilian(11), "the colonist rides the absorbed hulls")
	assert_eq(moored.embarked_army, 21, "the troops stay aboard")
	assert_true((result["ashore"] as Array).is_empty())

	# A second army cannot share the squadron: the surplus is reported for the
	# landing at the new seat, never dropped with the merged-away hulls.
	moored.embarked_army = 31
	var second: FleetState = FleetState.in_port(3, 0, SEAT, ["ship_5"])
	second.embarked_army = 32
	var other: Dictionary = NavalPortLoss.relocate_home(
		model, [second, moored], 0, SEAT, HARBOUR
	)

	assert_eq(moored.embarked_army, 31, "the moored squadron keeps its own army")
	assert_eq((other["ashore"] as Array), [32] as Array[int])


func test_an_empty_home_slip_is_dropped_on_the_move() -> void:
	var model: MapModel = Fixture.build()
	var slip: FleetState = FleetState.empty_in_port(1, 0, SEAT)
	var roster: Array[FleetState] = [slip]

	var result: Dictionary = NavalPortLoss.relocate_home(model, roster, 0, SEAT, HARBOUR)

	assert_true((result["moved"] as Array).is_empty())
	assert_true(roster.is_empty())


func test_settlement_sorts_out_and_reports_every_region() -> void:
	var model: MapModel = Fixture.build()
	var world := WorldMap.new()
	world.add_region(model)
	var regions := MapRegionTable.new()
	var fleet: FleetState = FleetState.in_port(1, 0, SEAT, ["ship_1"])
	regions.set_region(0, [fleet])
	model.province_data(SEAT).owner = 1

	var result: Dictionary = FleetPortSettlement.settle(world, regions, [])

	assert_eq((result["regions"] as Array), [0])
	assert_eq((result["reports"] as Array).size(), 1)
	assert_eq((result["sorties"] as Array).size(), 1)
	assert_true(fleet.is_at_sea())


func test_settlement_re_moors_a_reassigned_home_squadron() -> void:
	var model: MapModel = Fixture.build()
	var world := WorldMap.new()
	world.add_region(model)
	var regions := MapRegionTable.new()
	var fleet: FleetState = FleetState.in_port(1, 0, SEAT, ["ship_1"])
	regions.set_region(0, [fleet])
	model.province_data(HARBOUR).owner = 0

	var result: Dictionary = FleetPortSettlement.settle(
		world,
		regions,
		[{"faction": 0, "lost": SEAT, "province": HARBOUR, "region": 0}]
	)

	assert_eq(fleet.province, HARBOUR)
	assert_eq((result["reports"] as Array).size(), 1)
	assert_true((result["sorties"] as Array).is_empty())


## A 7x3 chart: province 0 is coastal, province 1 is ringed by neutral land so
## it has no sea zone, and the only water is the bay beside province 0.
func _inland_chart() -> MapModel:
	var model := MapModel.new()
	model.setup(7, 3)
	_land(model, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)], 0)
	_land(model, [Vector2i(3, 0), Vector2i(4, 0), Vector2i(3, 1), Vector2i(4, 1)], 1)
	for tile: Vector2i in [
		Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2),
		Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 0),
		Vector2i(5, 1), Vector2i(5, 2),
	]:
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.PLAINS
	var water: Array[Vector2i] = [
		Vector2i(0, 2), Vector2i(1, 2),
		Vector2i(6, 0), Vector2i(6, 1), Vector2i(6, 2),
	]
	for tile: Vector2i in water:
		model.sea_zone[model.index_of(tile.x, tile.y)] = 0
	var seat := ProvinceState.create(
		0, "Seat", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
		Vector2(0.5, 0.5), 4, 0, true
	)
	var inland := ProvinceState.create(
		1, "Inland", [Vector2i(3, 0), Vector2i(4, 0), Vector2i(3, 1), Vector2i(4, 1)],
		Vector2(3.5, 0.5), 4, 0, false
	)
	model.provinces = [seat, inland]
	model.sea_zones = [SeaZoneState.create(0, "Bay", water, Vector2(0.5, 2.0), 5)]
	return model


func _land(model: MapModel, tiles: Array, province_id: int) -> void:
	for tile: Vector2i in tiles:
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.PLAINS
		model.province[model.index_of(tile.x, tile.y)] = province_id
