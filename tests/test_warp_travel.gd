extends GdToolsTest
## Warp-zone crossings between the Old and New World (wiki: map-topology).

const Fixture = preload("res://tests/map_fixture.gd")

var world_map: WorldMap = null


func before_all() -> void:
	world_map = Fixture.world()


func test_a_warp_zone_links_to_one_zone_on_the_other_map() -> void:
	var zone: int = world_map.warp_zones(FactionCatalog.OLD_WORLD)[0]
	var fleet := FleetState.at_sea(1, 0, zone)

	var check: Dictionary = WarpTravel.can_cross(
		world_map, FactionCatalog.OLD_WORLD, fleet
	)

	assert_true(bool(check["ok"]))
	assert_eq(int(check["to_region"]), FactionCatalog.NEW_WORLD)
	assert_eq(
		int(check["to_zone"]),
		int(world_map.warp_partner(FactionCatalog.OLD_WORLD, zone)["to_zone"])
	)
	assert_true(world_map.is_warp_zone(int(check["to_region"]), int(check["to_zone"])))


func test_crossing_moves_the_fleet_into_the_paired_zone() -> void:
	var zone: int = world_map.warp_zones(FactionCatalog.OLD_WORLD)[0]
	var fleet := FleetState.at_sea(2, 0, zone, ["ship_2"], {"ship_2": "sloop"})

	var result: Dictionary = WarpTravel.apply_crossing(
		world_map, FactionCatalog.OLD_WORLD, fleet
	)

	assert_true(bool(result["ok"]))
	assert_eq(int(result["from_zone"]), zone)
	assert_eq(int(result["from_region"]), FactionCatalog.OLD_WORLD)
	assert_eq(int(result["to_region"]), FactionCatalog.NEW_WORLD)
	assert_eq(fleet.sea_zone, int(result["to_zone"]))
	assert_eq(fleet.location, FleetState.Location.AT_SEA)
	assert_eq(fleet.province, MapModel.NO_ID)
	assert_true(fleet.moved)
	# Hulls cross intact, instance ids and types unchanged.
	assert_eq(fleet.ship_count(), 1)
	assert_eq(fleet.type_of("ship_2"), "sloop")


func test_a_crossing_can_be_made_back_the_other_way() -> void:
	var zone: int = world_map.warp_zones(FactionCatalog.OLD_WORLD)[0]
	var fleet := FleetState.at_sea(3, 0, zone)
	var there: Dictionary = WarpTravel.apply_crossing(
		world_map, FactionCatalog.OLD_WORLD, fleet
	)
	assert_true(bool(there["ok"]))
	fleet.moved = false

	var back: Dictionary = WarpTravel.apply_crossing(
		world_map, int(there["to_region"]), fleet
	)

	assert_true(bool(back["ok"]))
	assert_eq(int(back["to_region"]), FactionCatalog.OLD_WORLD)
	assert_true(world_map.is_warp_zone(FactionCatalog.OLD_WORLD, fleet.sea_zone))


## A crossing is the squadron's sail, so the station and the landing site are
## given up; province ids are region-local, so a marker carried across would
## name an unrelated coast on the other map (wiki: ships-and-naval § Missions
## and Movement — a mission persists until the squadron sails; § Naval transport
## — the beachhead marker is lost if the squadron sails).
func test_a_crossing_gives_up_the_station_and_the_landing_site() -> void:
	var zone: int = world_map.warp_zones(FactionCatalog.OLD_WORLD)[0]
	var blockading := FleetState.at_sea(7, 0, zone)
	blockading.mission = FleetState.Mission.BLOCKADE
	blockading.blockade_province = 4
	blockading.beachhead_province = 4
	blockading.beachhead_turn = 3
	var landing := FleetState.at_sea(8, 0, zone)
	landing.mission = FleetState.Mission.BEACHHEAD
	landing.beachhead_province = 5
	landing.beachhead_turn = 3

	assert_true(bool(WarpTravel.apply_crossing(world_map, FactionCatalog.OLD_WORLD, blockading)["ok"]))
	assert_true(bool(WarpTravel.apply_crossing(world_map, FactionCatalog.OLD_WORLD, landing)["ok"]))

	assert_eq(blockading.mission, FleetState.Mission.NONE)
	assert_eq(blockading.blockade_province, MapModel.NO_ID, "the blockade coast does not cross")
	assert_false(blockading.has_beachhead(), "the landing site does not cross")
	assert_eq(blockading.beachhead_turn, -1)
	assert_eq(landing.mission, FleetState.Mission.NONE, "the beachhead mission is given up")
	assert_false(landing.has_beachhead())


func test_a_moved_fleet_cannot_cross() -> void:
	var zone: int = world_map.warp_zones(FactionCatalog.OLD_WORLD)[0]
	var fleet := FleetState.at_sea(4, 0, zone)
	fleet.moved = true

	var result: Dictionary = WarpTravel.apply_crossing(
		world_map, FactionCatalog.OLD_WORLD, fleet
	)

	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("already moved"))
	assert_eq(fleet.sea_zone, zone)


func test_a_fleet_in_port_cannot_cross() -> void:
	var province: int = int(world_map.region(FactionCatalog.OLD_WORLD).provinces[0].id)
	var fleet := FleetState.in_port(5, 0, province)

	var result: Dictionary = WarpTravel.apply_crossing(
		world_map, FactionCatalog.OLD_WORLD, fleet
	)

	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("at sea"))
	assert_eq(fleet.location, FleetState.Location.IN_PORT)


func test_open_water_has_no_passage() -> void:
	var model: MapModel = world_map.region(FactionCatalog.OLD_WORLD)
	var zone: int = -1
	for data: SeaZoneState in model.sea_zones:
		if not world_map.is_warp_zone(FactionCatalog.OLD_WORLD, int(data.id)):
			zone = int(data.id)
			break
	assert_gt(zone, -1, "the Old World has ordinary water")
	var fleet := FleetState.at_sea(6, 0, zone)

	var check: Dictionary = WarpTravel.can_cross(
		world_map, FactionCatalog.OLD_WORLD, fleet
	)

	assert_false(bool(check["ok"]))
	assert_true(String(check["reason"]).contains("passage"))
	assert_false(fleet.moved)
