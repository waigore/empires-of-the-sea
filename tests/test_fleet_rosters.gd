extends GdToolsTest
## Fleet roster arithmetic shared by ShipLayer, the turn tick and the save
## module: every region counts, fleet ids never collide across maps, and the
## marker helper frees nodes it drops.

const Fixture = preload("res://tests/map_fixture.gd")

var _markers: ShipMarkers = null


func before_each() -> void:
	_markers = ShipMarkers.new()
	_markers.model = Fixture.region()


func after_each() -> void:
	_markers.clear()
	_markers = null


func _regions() -> MapRegionTable:
	var regions := MapRegionTable.new()
	regions.set_region(0, [
		FleetState.at_sea(0, 1, 0, ["a", "b"]), FleetState.in_port(1, 1, 2, ["c"])
	])
	regions.set_region(1, [FleetState.at_sea(4, 2, 5, ["d"])])
	return regions


func test_every_region_contributes_to_the_hull_count() -> void:
	var regions := _regions()
	assert_eq(FleetRosters.hulls_afloat(regions, 1), 3)
	assert_eq(FleetRosters.hulls_afloat(regions, 2), 1)
	assert_eq(FleetRosters.hulls_afloat(MapRegionTable.new(), 1), 0)


func test_next_id_avoids_ids_used_in_any_region() -> void:
	var regions := _regions()
	assert_eq(FleetRosters.next_id_all(regions), 5)
	assert_eq(FleetRosters.next_id_all(MapRegionTable.new()), 0)


func test_all_returns_one_typed_roster_per_region() -> void:
	var regions := _regions()
	var rosters: Array[Array] = FleetRosters.all(regions)
	assert_eq(rosters.size(), 2)
	assert_eq(rosters[1].size(), 1)


func test_removing_the_selected_marker_clears_the_selection() -> void:
	var fleet := FleetState.at_sea(3, 1, 0)
	var ship: Ship = _markers.make(fleet)
	_markers.selected_ship = ship
	_markers.remove(ship)
	assert_eq(_markers.ships.size(), 0)
	assert_null(_markers.selected_ship)
	assert_eq(_markers.find(3), null)


func test_clear_frees_every_marker() -> void:
	_markers.make(FleetState.at_sea(0, 1, 0))
	_markers.make(FleetState.in_port(1, 2, 2))
	_markers.selected_ship = _markers.ships[0]
	_markers.clear()
	assert_eq(_markers.ships.size(), 0)
	assert_null(_markers.selected_ship)
