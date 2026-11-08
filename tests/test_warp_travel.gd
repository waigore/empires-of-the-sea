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
