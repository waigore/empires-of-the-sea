extends GdToolsTest
## Local slot storage: paths, metadata rows, overwrite and deletion.
## Uses a scratch directory so the player's saves are never touched.
## Consolidated rulebook: test_save_world.gd (one Godot boot per domain).

const DIR: String = "user://test_save_store"


func before_each() -> void:
	_clean_dir()


func after_each() -> void:
	_clean_dir()


func test_slots_report_existing_saves_and_empty_slots() -> void:
	var rows: Array[Dictionary] = SaveStore.slots(DIR)
	assert_eq(rows.size(), SaveStore.SLOT_COUNT)
	assert_false(bool(rows[0]["exists"]), "fresh slot is empty")

	assert_true(SaveStore.save_slot(3, _data(7), DIR), "slot 3 saves")
	assert_true(SaveStore.has_slot(3, DIR), "slot 3 exists")
	assert_false(SaveStore.has_slot(2, DIR), "slot 2 stays empty")
	rows = SaveStore.slots(DIR)
	assert_true(bool(rows[2]["exists"]), "row reports the save")
	assert_eq(int(rows[2]["turn"]), 7, "row carries the turn")
	assert_eq(String(rows[2]["nation"]), "Spain", "row carries the nation")
	assert_eq(String(rows[2]["region"]), "Old World", "row carries the region")
	assert_eq(int(rows[2]["seed"]), 4242, "row carries the seed")
	assert_false(String(rows[2]["saved_at"]).is_empty(), "row carries a timestamp")
	assert_eq(String(rows[2]["length"]), "Historical", "row names the campaign length")


## The campaign length is a rule a load cannot change, so the row that offers
## the load names it; a save without the key reads Historical, exactly as the
## loaded campaign will (wiki: campaign-persistence § Load and resume).
func test_slot_rows_name_the_campaign_length() -> void:
	assert_true(SaveStore.save_slot(1, _data(4, true), DIR), "the endless save writes")
	assert_true(SaveStore.save_slot(2, _data(5, false), DIR), "the historical save writes")
	assert_true(SaveStore.save_slot(3, _data(6), DIR), "the legacy save writes")
	var rows: Array[Dictionary] = SaveStore.slots(DIR)
	assert_eq(String(rows[0]["length"]), "Endless", "endless is named")
	assert_eq(String(rows[1]["length"]), "Historical", "historical is named")
	assert_eq(String(rows[2]["length"]), "Historical", "a save without the key is historical")
	assert_eq(SaveCodec.length_label(true), "Endless")
	assert_eq(SaveCodec.length_label(false), "Historical")


## A slot holding a file this build cannot read is not an empty slot: the row
## keeps the file's presence (so the overwrite guard still asks) and says it
## cannot be read, inventing no summary (wiki: campaign-persistence
## § Load and resume — announced, never silent).
func test_an_unreadable_slot_is_reported_not_empty() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var file := FileAccess.open(SaveStore.path_for(2, DIR), FileAccess.WRITE)
	assert_not_null(file, "the corrupt fixture opens")
	if file == null:
		return
	file.store_string("not a variant")
	file.close()
	# A save written by a newer format is a readable dictionary this build must
	# still refuse (wiki: campaign-persistence § Snapshots — version).
	assert_true(
		SaveStore.write(SaveStore.path_for(3, DIR), {"version": SaveCodec.VERSION + 1}),
		"the newer-format fixture writes"
	)

	var rows: Array[Dictionary] = SaveStore.slots(DIR)
	assert_true(bool(rows[1]["exists"]), "a file is in the slot")
	assert_false(bool(rows[1]["readable"]), "the corrupt file cannot be read")
	assert_false(rows[1].has("turn"), "no summary is invented for it")
	assert_true(bool(rows[2]["exists"]), "the newer-format slot is not empty")
	assert_false(bool(rows[2]["readable"]), "a newer format is refused")


func test_overwrite_replaces_the_slot_and_delete_clears_it() -> void:
	assert_true(SaveStore.save_slot(1, _data(2), DIR))
	assert_true(SaveStore.save_slot(1, _data(11), DIR), "slot overwrites")
	assert_eq(int(SaveStore.slots(DIR)[0]["turn"]), 11, "newer save wins")
	assert_true(SaveStore.delete_slot(1, DIR), "slot deletes")
	assert_false(SaveStore.has_slot(1, DIR), "deleted slot is gone")
	assert_false(SaveStore.delete_slot(1, DIR), "deleting twice is a no-op")


func test_slot_numbers_are_clamped_and_bad_data_is_refused() -> void:
	assert_eq(SaveStore.path_for(0, DIR), SaveStore.path_for(1, DIR))
	assert_eq(SaveStore.path_for(99, DIR), SaveStore.path_for(SaveStore.SLOT_COUNT, DIR))
	assert_false(SaveStore.save_slot(1, {}, DIR), "empty data is refused")
	assert_false(SaveStore.save_slot(1, {"version": 999}, DIR), "bad version refused")


## `infinite` is left null for a save written before the key existed.
func _data(turn: int, infinite: Variant = null) -> Dictionary:
	var session: Dictionary = {
		"map_seed": 4242,
		"map_width": 64,
		"map_height": 42,
		"player_faction": 0,
		"region_index": 0,
		"turn": turn,
	}
	if infinite != null:
		session["infinite_mode"] = infinite
	return {
		"version": SaveCodec.VERSION,
		"saved_at": "2026-11-08 12:00:00",
		"session": session,
		"regions": [{}],
	}


func _clean_dir() -> void:
	var path: String = ProjectSettings.globalize_path(DIR)
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(DIR)
	if dir != null:
		for file_name: String in dir.get_files():
			dir.remove(file_name)
	DirAccess.remove_absolute(path)


# --- from test_save_world.gd ---
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
	province["town_tile"] = [2, 1]
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
	assert_eq(model.provinces[0].town_tile, Vector2i(2, 1))
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


## A court seated by hand round-trips its tile and harbour, so a reload keeps
## the seat the player chose instead of the regenerated auto-choice one
## (wiki: capital-choice-phase § Player choice).
func test_a_chosen_seat_round_trips_its_tile_and_ports() -> void:
	var world: WorldMap = _world()
	var model: MapModel = world.region(0)
	model.provinces[0].capital_tile = Vector2i(1, 0)
	model.provinces[0].ports = {2: Vector2i(1, 0)}
	var captured: Array[Dictionary] = SaveWorld.capture(world)

	model.provinces[0].capital_tile = Vector2i(-1, -1)
	model.provinces[0].ports = {}
	assert_true(SaveWorld.apply(world, captured))
	assert_eq(model.provinces[0].capital_tile, Vector2i(1, 0))
	assert_eq(model.provinces[0].ports, {2: Vector2i(1, 0)})

	# A malformed port entry is dropped; the rest of the harbour still loads.
	var region: Dictionary = captured[0].duplicate(true)
	var row: Dictionary = region["provinces"][0].duplicate(true)
	row["ports"] = {0: "junk", 1: [0, 1]}
	region["provinces"][0] = row
	assert_true(SaveWorld.apply(world, [region]))
	assert_eq(model.provinces[0].ports, {1: Vector2i(0, 1)})


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
