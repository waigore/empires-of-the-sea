extends GdToolsTest
## SaveWorld capture/apply edge cases: a reused world must match the save's
## region count and sizes, and corrupt province/resource payloads are refused
## so the caller regenerates instead of applying a wrong map (REQ-P3-03).


func test_round_trip_applies_owners_resources_and_array_tiles() -> void:
	var world: WorldMap = _world()
	var captured: Array[Dictionary] = SaveWorld.capture(world)
	var region: Dictionary = captured[0]
	var province: Dictionary = region["provinces"][0]
	province["owner"] = 3
	province["capital"] = true
	province["town_development"] = 2
	province["fort_level"] = FortRules.MAX_LEVEL + 4
	province["resource"] = 7
	province["resource_tile"] = [1, 0]
	province["population"] = 42
	province["road_paths"] = [[Vector2i(0, 0), Vector2i(1, 0)]]
	region["provinces"][0] = province
	# JSON-shaped resources arrive as Array; PackedInt32Array is the capture path.
	var resources: Array = []
	for index in world.region(0).resource.size():
		resources.append(9 if index == 0 else -1)
	region["resources"] = resources
	region["tile_deeds"] = {"owners": {0: 3}, "purchased": {0: 3}}
	captured[0] = region

	assert_true(SaveWorld.apply(world, captured), "matching save applies")
	var model: MapModel = world.region(0)
	assert_eq(model.provinces[0].owner, 3)
	assert_true(model.provinces[0].capital)
	assert_eq(model.provinces[0].town_development, 2)
	assert_eq(model.provinces[0].fort_level, FortRules.MAX_LEVEL)
	assert_eq(model.provinces[0].resource, 7)
	assert_eq(model.provinces[0].resource_tile, Vector2i(1, 0))
	assert_eq(model.provinces[0].population, 42)
	assert_eq(model.provinces[0].road_paths, [[Vector2i(0, 0), Vector2i(1, 0)]])
	assert_eq(model.resource[0], 9)
	assert_eq(model.owner_at(0, 0), 3)


func test_apply_refuses_shape_mismatches_and_corrupt_entries() -> void:
	var world: WorldMap = _world()
	var good: Array[Dictionary] = SaveWorld.capture(world)

	assert_false(SaveWorld.apply(world, {}), "non-array regions refuse")
	assert_false(SaveWorld.apply(world, []), "wrong region count refuses")
	assert_false(SaveWorld.apply(world, [good[0], "x"]), "non-dict region refuses")

	var wide: Dictionary = good[0].duplicate(true)
	wide["width"] = world.region(0).width + 1
	assert_false(SaveWorld.apply(world, [wide]), "size mismatch refuses")

	var short_provinces: Dictionary = good[0].duplicate(true)
	short_provinces["provinces"] = []
	assert_false(SaveWorld.apply(world, [short_provinces]), "province count refuses")

	var bad_province: Dictionary = good[0].duplicate(true)
	bad_province["provinces"] = ["x"]
	assert_false(SaveWorld.apply(world, [bad_province]), "non-dict province refuses")

	var missing_id: Dictionary = good[0].duplicate(true)
	var row: Dictionary = missing_id["provinces"][0].duplicate(true)
	row["id"] = 99
	missing_id["provinces"][0] = row
	assert_false(SaveWorld.apply(world, [missing_id]), "unknown province refuses")

	var bad_roads: Dictionary = good[0].duplicate(true)
	row = bad_roads["provinces"][0].duplicate(true)
	row["road_paths"] = "not-an-array"
	bad_roads["provinces"][0] = row
	assert_false(SaveWorld.apply(world, [bad_roads]), "bad road_paths refuse")

	var bad_resources: Dictionary = good[0].duplicate(true)
	bad_resources["resources"] = PackedInt32Array([1])
	assert_false(SaveWorld.apply(world, [bad_resources]), "wrong packed size refuses")
	bad_resources["resources"] = [1]
	assert_false(SaveWorld.apply(world, [bad_resources]), "wrong array size refuses")


func test_reusable_requires_matching_region_sizes() -> void:
	var world: WorldMap = _world()
	var width: int = world.region(0).width
	var height: int = world.region(0).height

	assert_null(SaveWorld.reusable(null, width, height))
	assert_null(SaveWorld.reusable(WorldMap.new(), width, height))
	assert_eq(SaveWorld.reusable(world, width, height), world)

	var other: WorldMap = WorldMap.new()
	var model: MapModel = MapModel.new()
	model.setup(width + 1, height)
	other.add_region(model)
	assert_null(SaveWorld.reusable(other, width, height), "wrong size is not reused")


func test_resource_tile_accepts_vector2i_and_falls_back() -> void:
	var world: WorldMap = _world()
	var captured: Array[Dictionary] = SaveWorld.capture(world)
	var region: Dictionary = captured[0]
	var row: Dictionary = region["provinces"][0].duplicate(true)
	row["resource_tile"] = Vector2i(0, 0)
	region["provinces"][0] = row
	assert_true(SaveWorld.apply(world, [region]))
	assert_eq(world.region(0).provinces[0].resource_tile, Vector2i(0, 0))

	row = region["provinces"][0].duplicate(true)
	row["resource_tile"] = "junk"
	region["provinces"][0] = row
	assert_true(SaveWorld.apply(world, [region]))
	assert_eq(world.region(0).provinces[0].resource_tile, Vector2i(-1, -1))

	row = region["provinces"][0].duplicate(true)
	row["resource_tile"] = [1]
	region["provinces"][0] = row
	assert_true(SaveWorld.apply(world, [region]))
	assert_eq(world.region(0).provinces[0].resource_tile, Vector2i(-1, -1))


func test_visibility_round_trips_and_skips_unknown_regions() -> void:
	var play := PlaySession.new()
	play.world = _world()
	play.player_faction = 0
	var visibility := VisibilityModel.new()
	visibility.setup(play.world.region(0), play.player_faction)
	visibility.raise_to(0, VisibilityModel.Level.FULLY_VISIBLE)
	play.visibility_by_region[0] = visibility

	var captured: Dictionary = SaveWorld.capture_visibility(play)
	assert_true(captured["by_region"].has(0), "every charted region is captured")

	var restored := PlaySession.new()
	restored.world = _world()
	restored.player_faction = 0
	SaveWorld.restore_visibility(restored, captured)
	assert_true(restored.visibility_by_region.has(0), "the charted region comes back")
	assert_eq(
		restored.visibility_by_region[0].level_at(0, 0),
		VisibilityModel.Level.FULLY_VISIBLE,
		"seen tiles stay seen"
	)


func test_visibility_restore_tolerates_junk_and_unknown_regions() -> void:
	var play := PlaySession.new()
	play.world = _world()
	play.player_faction = 0
	SaveWorld.restore_visibility(play, "not-a-dict")
	assert_true(play.visibility_by_region.is_empty(), "junk clears to no fog model")
	SaveWorld.restore_visibility(play, {"by_region": {7: {"seen": []}, 0: "junk"}})
	assert_true(
		play.visibility_by_region.is_empty(),
		"an unknown region and a malformed entry are both skipped"
	)


func _world() -> WorldMap:
	var model := MapModel.new()
	model.setup(2, 1)
	model.terrain[0] = MapModel.Terrain.PLAINS
	model.terrain[1] = MapModel.Terrain.PLAINS
	model.province[0] = 0
	model.province[1] = 0
	model.provinces = [
		ProvinceState.create(0, "A", [Vector2i(0, 0), Vector2i(1, 0)], Vector2(0.5, 0.5), 2, 0, true),
	]
	var world := WorldMap.new()
	world.add_region(model)
	return world
