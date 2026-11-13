extends GdToolsTest
## ArmyMarkers and ArmyMuster leave ArmyLayer: marker mint/clear/place and
## opening Home Army rosters stay testable without the map screen (REQ-P3-01,
## REQ-P3-04).


func test_muster_builds_a_home_army_per_capital() -> void:
	var model := MapModel.new()
	model.region_id = 0
	model.faction_ids = [0, 1]
	var seat_a := ProvinceState.new()
	seat_a.id = 0
	seat_a.owner = 0
	seat_a.capital = true
	seat_a.center = Vector2(1, 1)
	var seat_b := ProvinceState.new()
	seat_b.id = 1
	seat_b.owner = 1
	seat_b.capital = true
	seat_b.center = Vector2(2, 2)
	model.provinces = [seat_a, seat_b]
	var muster := ArmyMuster.new()
	var armies: Array[ArmyState] = muster.build(model)
	assert_eq(armies.size(), 2)
	assert_true(armies[0].is_home_army())
	assert_true(armies[1].is_home_army())
	assert_eq(armies[0].count(), ArmyMuster.GREAT_POWER_ROSTER.size())
	assert_eq(muster.next_army, 3)


func test_markers_mint_place_and_drop() -> void:
	var model := MapModel.new()
	model.region_id = 0
	var province := ProvinceState.new()
	province.id = 0
	province.owner = 0
	province.capital = true
	province.center = Vector2(3, 4)
	model.provinces = [province]
	var army := ArmyState.muster(1, 0, 0, true, ["peasant_levies", "pikemen"], 10)
	var helpers := ArmyMarkers.new()
	helpers.model = model
	var marker: ArmyMarker = helpers.make(army)
	assert_not_null(marker)
	assert_eq(helpers.markers.size(), 1)
	helpers.place_all([army])
	assert_eq(marker.position, province.center * ArmyMarkers.TILE_SIZE)
	helpers.refresh(army)
	assert_eq(helpers.find_army(army), marker)
	helpers.remove(marker)
	assert_eq(helpers.markers.size(), 0)
	assert_null(helpers.find(1))


func test_roster_counts_every_region() -> void:
	var regions := MapRegionTable.new()
	var home := ArmyState.muster(1, 0, 0, true, ["peasant_levies", "pikemen"], 10)
	var field := ArmyState.muster(2, 0, 1, false, ["bowmen"], 20)
	regions.set_region(0, [home])
	regions.set_region(1, [field])
	assert_eq(ArmyRoster.count_all(regions, 0), 3)
	assert_eq(ArmyRoster.count_all(regions, 1), 0)
	assert_true(ArmyRoster.food_upkeep_all(regions, 0) > 0)
