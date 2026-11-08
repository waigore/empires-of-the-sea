extends GdToolsTest
## Small pure contracts: build version, calendar, audio cues, ink paths,
## borders, camera math and victory rules.
## Merged into one suite so coverage pays a single Godot boot per theme
## (docs/testing.md speed rules).

const WIDTH: int = 6
const HEIGHT: int = 3
const VIEWPORT := Vector2(1280.0, 720.0)
const MAP := Vector2(2816.0, 1848.0)

# --- from test_game_version.gd ---
## Smoke tests for GameVersion helpers.


func test_as_string_matches_semver_parts() -> void:
	assert_eq(GameVersion.as_string(), "0.1.0")


func test_is_compatible_with_matching_major() -> void:
	assert_true(GameVersion.is_compatible_with(GameVersion.MAJOR))


func test_is_compatible_with_rejects_other_major() -> void:
	assert_false(GameVersion.is_compatible_with(GameVersion.MAJOR + 1))

# --- from test_turn_time.gd ---
## Turn-to-calendar mapping (wiki: turn-time-mapping).


func test_turn_one_is_start_year() -> void:
	assert_eq(TurnTime.year_for_turn(1), 1500)


func test_two_years_per_turn_before_cutoff() -> void:
	assert_eq(TurnTime.year_for_turn(2), 1502)
	assert_eq(TurnTime.year_for_turn(51), 1600)


func test_cutoff_turn_is_1700() -> void:
	assert_eq(TurnTime.TURNS_BEFORE_CUTOFF, 100)
	assert_eq(TurnTime.year_for_turn(101), 1700)


func test_one_year_per_turn_after_cutoff() -> void:
	assert_eq(TurnTime.year_for_turn(102), 1701)
	assert_eq(TurnTime.year_for_turn(201), 1800)


func test_turn_zero_clamps_to_start_year() -> void:
	assert_eq(TurnTime.year_for_turn(0), 1500)
	assert_eq(TurnTime.year_for_turn(-4), 1500)


func test_label_formats_turn_and_year() -> void:
	assert_eq(TurnTime.label_for_turn(1), "Turn 1  ·  1500")
	assert_eq(TurnTime.label_for_turn(201), "Turn 201  ·  1800")

# --- from test_audio_events.gd ---
## Cue table contract: every gameplay cue resolves to a shipped file and keeps a
## sane trim so the mix never clips (REQ-P1-06).


func test_every_cue_points_at_a_shipped_file() -> void:
	var names: Array[String] = AudioEvents.names()
	assert_gt(names.size(), 8)
	for event_name: String in names:
		var path: String = AudioEvents.path_for(event_name)
		assert_true(path.begins_with(AudioEvents.ROOT), event_name)
		assert_true(FileAccess.file_exists(path), path)


func test_unknown_events_have_no_cue() -> void:
	assert_false(AudioEvents.has("cannon_fire_9000"))
	assert_true(AudioEvents.cue("cannon_fire_9000").is_empty())
	assert_eq(AudioEvents.path_for("cannon_fire_9000"), "")


func test_trims_stay_inside_a_safe_mix_window() -> void:
	for event_name: String in AudioEvents.names():
		var cue: Dictionary = AudioEvents.cue(event_name)
		assert_between(float(cue.get("volume_db", 0.0)), -26.0, 0.0, event_name)
		assert_between(float(cue.get("pitch", 0.0)), 0.0, 0.1, event_name)


func test_names_are_sorted_and_unique() -> void:
	var names: Array[String] = AudioEvents.names()
	var sorted_copy: Array[String] = names.duplicate()
	sorted_copy.sort()
	assert_eq(names, sorted_copy)
	for event_name: String in names:
		assert_eq(names.count(event_name), 1, event_name)

# --- from test_ink_paths.gd ---
## Segment tracing and Chaikin smoothing used by coastlines and borders.


func _seg(a: Vector2, b: Vector2) -> PackedVector2Array:
	return PackedVector2Array([a, b])


func test_trace_joins_connected_segments() -> void:
	var segments: Array[PackedVector2Array] = [
		_seg(Vector2(0, 0), Vector2(10, 0)),
		_seg(Vector2(10, 0), Vector2(10, 10)),
		_seg(Vector2(10, 10), Vector2(0, 10)),
	]
	var paths: Array[PackedVector2Array] = InkPaths.trace(segments)
	assert_eq(paths.size(), 1)
	assert_eq(paths[0].size(), 4)
	assert_eq(paths[0][0], Vector2(0, 0))
	assert_eq(paths[0][3], Vector2(0, 10))


func test_trace_keeps_disconnected_segments_apart() -> void:
	var segments: Array[PackedVector2Array] = [
		_seg(Vector2(0, 0), Vector2(10, 0)),
		_seg(Vector2(50, 50), Vector2(60, 50)),
	]
	assert_eq(InkPaths.trace(segments).size(), 2)


func test_chaikin_keeps_open_endpoints() -> void:
	var points := PackedVector2Array([
		Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)
	])
	var smoothed: PackedVector2Array = InkPaths.chaikin(points, 2, false)
	assert_eq(smoothed[0], Vector2(0, 0))
	assert_eq(smoothed[smoothed.size() - 1], Vector2(10, 10))
	assert_gt(smoothed.size(), points.size())


func test_chaikin_short_input_is_unchanged() -> void:
	var points := PackedVector2Array([Vector2(0, 0), Vector2(1, 1)])
	assert_eq(InkPaths.chaikin(points, 2, false), points)


func test_smooth_segments_closes_a_loop() -> void:
	var segments: Array[PackedVector2Array] = [
		_seg(Vector2(0, 0), Vector2(10, 0)),
		_seg(Vector2(10, 0), Vector2(10, 10)),
		_seg(Vector2(10, 10), Vector2(0, 10)),
		_seg(Vector2(0, 10), Vector2(0, 0)),
	]
	var paths: Array[PackedVector2Array] = InkPaths.smooth_segments(segments, 1)
	assert_eq(paths.size(), 1)
	var path: PackedVector2Array = paths[0]
	assert_eq(path[0], path[path.size() - 1])
	assert_gt(path.size(), 8)


func test_smooth_segments_skips_single_points() -> void:
	var segments: Array[PackedVector2Array] = []
	assert_eq(InkPaths.smooth_segments(segments, 2).size(), 0)

# --- from test_country_borders.gd ---
## Country borders (view support for wiki: factions / map ownership).
## Ownership changes must produce an explicit line between different nations.


func _model_with_owners(owners: Array[int]) -> MapModel:
	var model := MapModel.new()
	model.setup(WIDTH, HEIGHT)
	var province_count: int = 3
	for province_id in province_count:
		var tiles: Array[Vector2i] = [
			Vector2i(province_id * 2, 1), Vector2i(province_id * 2 + 1, 1)
		]
		for tile: Vector2i in tiles:
			model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.PLAINS
			model.province[model.index_of(tile.x, tile.y)] = province_id
		model.provinces.append(
			ProvinceState.create(
				province_id,
				"P%d" % province_id,
				tiles,
				Vector2(float(province_id) * 2.0 + 0.5, 1.5),
				tiles.size(),
				owners[province_id]
			)
		)
	return model


func test_borders_split_different_owners() -> void:
	var model: MapModel = _model_with_owners([0, 1, 0])
	var borders: Dictionary = CountryBorders.build(model, 1.0)
	assert_true(borders.has(0))
	assert_true(borders.has(1))
	assert_true(_has_edge(borders[0], Vector2(2, 1), Vector2(2, 2)), "missing 0|1 border")
	assert_true(_has_edge(borders[1], Vector2(4, 1), Vector2(4, 2)), "missing 1|0 border")


func test_no_border_inside_one_nation() -> void:
	var model: MapModel = _model_with_owners([0, 0, 0])
	var borders: Dictionary = CountryBorders.build(model, 1.0)
	assert_true(borders.is_empty(), "same owner should draw no border")


func test_coastline_keeps_its_ink_and_no_country_line() -> void:
	var model: MapModel = _model_with_owners([0, 1, 0])
	var borders: Dictionary = CountryBorders.build(model, 1.0)
	assert_false(_has_edge(borders[0], Vector2(0, 1), Vector2(0, 2)), "west coast got a country line")
	assert_false(_has_edge(borders[0], Vector2(0, 1), Vector2(1, 1)), "north coast got a country line")


func test_unclaimed_land_gets_no_border() -> void:
	var model: MapModel = _model_with_owners([MapModel.NO_ID, 0, 0])
	var borders: Dictionary = CountryBorders.build(model, 1.0)
	assert_true(borders.is_empty(), "unclaimed land has no country border")


func test_missing_model_is_safe() -> void:
	assert_true(CountryBorders.build(null, 1.0).is_empty())


func _has_edge(segments: Array, a: Vector2, b: Vector2) -> bool:
	for segment: PackedVector2Array in segments:
		if segment.size() != 2:
			continue
		if segment[0] == a and segment[1] == b:
			return true
		if segment[0] == b and segment[1] == a:
			return true
	return false

# --- from test_camera_math.gd ---
## Camera clamping and anchoring maths.


func test_clamp_center_keeps_view_inside_map() -> void:
	var clamped: Vector2 = CameraMath.clamp_center(Vector2(-500, -500), 1.0, VIEWPORT, MAP)
	assert_almost_eq(clamped.x, VIEWPORT.x * 0.5, 0.01)
	assert_almost_eq(clamped.y, VIEWPORT.y * 0.5, 0.01)

	clamped = CameraMath.clamp_center(Vector2(99999, 99999), 1.0, VIEWPORT, MAP)
	assert_almost_eq(clamped.x, MAP.x - VIEWPORT.x * 0.5, 0.01)
	assert_almost_eq(clamped.y, MAP.y - VIEWPORT.y * 0.5, 0.01)


func test_clamp_center_allows_interior_positions() -> void:
	var target := Vector2(1400.0, 900.0)
	assert_eq(CameraMath.clamp_center(target, 1.0, VIEWPORT, MAP), target)


func test_clamp_center_centres_small_map() -> void:
	var small := Vector2(400.0, 200.0)
	var clamped: Vector2 = CameraMath.clamp_center(Vector2(0, 0), 1.0, VIEWPORT, small)
	assert_almost_eq(clamped.x, 200.0, 0.01)
	assert_almost_eq(clamped.y, 100.0, 0.01)


func test_zoom_anchor_keeps_world_point_under_cursor() -> void:
	var center := Vector2(1400.0, 900.0)
	var anchor := Vector2(1000.0, 200.0)
	var before: Vector2 = CameraMath.screen_to_world(center, 0.6, anchor, VIEWPORT)
	var moved: Vector2 = CameraMath.zoom_anchor(center, 0.6, 1.2, anchor, VIEWPORT)
	var after: Vector2 = CameraMath.screen_to_world(moved, 1.2, anchor, VIEWPORT)
	assert_almost_eq(after.x, before.x, 0.01)
	assert_almost_eq(after.y, before.y, 0.01)


func test_fit_zoom_fits_whole_map() -> void:
	var zoom: float = CameraMath.fit_zoom(VIEWPORT, MAP)
	var expected: float = minf(VIEWPORT.x / MAP.x, VIEWPORT.y / MAP.y)
	assert_almost_eq(zoom, expected, 0.0001)


func test_fit_cover_covers_the_viewport() -> void:
	var zoom: float = CameraMath.fit_cover(VIEWPORT, MAP)
	assert_almost_eq(zoom, maxf(VIEWPORT.x / MAP.x, VIEWPORT.y / MAP.y), 0.0001)
	var tall := Vector2(720.0, 1600.0)
	assert_almost_eq(CameraMath.fit_cover(tall, MAP), 1600.0 / MAP.y, 0.0001)


func test_fit_cover_handles_zero_map() -> void:
	assert_eq(CameraMath.fit_cover(VIEWPORT, Vector2.ZERO), 1.0)


func test_fit_zoom_handles_zero_map() -> void:
	assert_eq(CameraMath.fit_zoom(VIEWPORT, Vector2.ZERO), 1.0)


func test_screen_world_round_trip() -> void:
	var world := Vector2(1234.0, 567.0)
	var screen: Vector2 = CameraMath.world_to_screen(Vector2(1000, 800), 1.7, world, VIEWPORT)
	var back: Vector2 = CameraMath.screen_to_world(Vector2(1000, 800), 1.7, screen, VIEWPORT)
	assert_almost_eq(back.x, world.x, 0.01)
	assert_almost_eq(back.y, world.y, 0.01)

# --- from test_victory_rules.gd ---
## Military victory (wiki: victory § Current scope: military victory only).
## Pure rules: synthetic worlds only, so the threshold and tie-break are pinned
## without a generated map (REQ-P2-04).


func test_thirty_old_world_provinces_are_not_enough() -> void:
	var world: WorldMap = _world({FactionCatalog.PLAYER_FACTION: 30})
	assert_null(VictoryRules.evaluate(world, 4))


func test_thirty_one_old_world_provinces_win() -> void:
	var world: WorldMap = _world({FactionCatalog.PLAYER_FACTION: 31})
	var victory: VictoryState = VictoryRules.evaluate(world, 7)
	assert_not_null(victory)
	assert_eq(victory.winner_player_id, FactionCatalog.PLAYER_FACTION)
	assert_eq(victory.type, VictoryState.Type.MILITARY)
	assert_eq(victory.turn_number, 7)
	assert_eq(victory.type_label(), "Military victory")
	assert_true(victory.won_by(FactionCatalog.PLAYER_FACTION))
	assert_eq(
		victory.summary(),
		"Spain — Military victory, turn 7",
		"the record names winner, type and turn"
	)


func test_only_great_powers_are_eligible() -> void:
	var world: WorldMap = _world({6: 40})
	assert_null(VictoryRules.evaluate(world, 3), "a Minor Nation never wins")


func test_shared_threshold_resolves_by_the_smallest_player_id() -> void:
	# Two qualified crowns: the smallest player id wins even though the other
	# holds more provinces (wiki: victory § Tie-breaking).
	var world: WorldMap = _world({4: 40, 2: 31})
	var victory: VictoryState = VictoryRules.evaluate(world, 3)
	assert_not_null(victory)
	assert_eq(victory.winner_player_id, 2)


func test_new_world_provinces_do_not_count() -> void:
	var world: WorldMap = _old_and_new(
		{FactionCatalog.PLAYER_FACTION: 10}, {FactionCatalog.PLAYER_FACTION: 30}
	)
	assert_null(VictoryRules.evaluate(world, 3))


func test_an_existing_victory_is_never_overwritten() -> void:
	var first: VictoryState = VictoryRules.evaluate(_world({1: 31}), 3)
	var later: WorldMap = _world({2: 40})
	assert_eq(VictoryRules.resolve(first, later, 9), first)


func test_qualified_crowns_are_ordered_and_filtered() -> void:
	var world: WorldMap = _world({4: 31, 1: 31, 3: 30})
	var ids: Array[int] = VictoryRules.qualified(world)
	assert_eq(ids.size(), 2)
	assert_eq(ids[0], 1)
	assert_eq(ids[1], 4)


func _world(counts: Dictionary) -> WorldMap:
	return _old_and_new(counts, {})


func _old_and_new(old_world: Dictionary, new_world: Dictionary) -> WorldMap:
	var world := WorldMap.new()
	world.add_region(_model(old_world, FactionCatalog.OLD_WORLD))
	world.add_region(_model(new_world, FactionCatalog.NEW_WORLD))
	return world


func _model(counts: Dictionary, region_id: int) -> MapModel:
	var model := MapModel.new()
	model.setup(1, 1)
	model.region_id = region_id
	model.faction_ids = FactionCatalog.ids_in_region(region_id)
	var next_id: int = 0
	for faction_id: int in counts.keys():
		for _index in int(counts[faction_id]):
			var tiles: Array[Vector2i] = []
			model.provinces.append(
				ProvinceState.create(
					next_id, "Province %d" % next_id, tiles, Vector2.ZERO, 1, faction_id
				)
			)
			next_id += 1
	return model
