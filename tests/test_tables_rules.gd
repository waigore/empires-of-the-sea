extends GdToolsTest
## One boot for the published tables: misc rules and the catalog rows.

## Merged from test_misc_rules, test_catalogs.
## One Godot boot (coverage instrumentation) per theme instead of one per file.
## Each test runs only its own suite's setup; teardown follows the setup.

const WIDTH: int = 6
const HEIGHT: int = 3
const VIEWPORT := Vector2(1280.0, 720.0)
const MAP := Vector2(2816.0, 1848.0)
const ROLE_NAMES: Dictionary = {
	"explorer": "Explorer",
	"engineer": "Engineer",
	"builder": "Builder",
	"spy": "Spy",
	"merchant": "Merchant",
	"rail_builder": "Rail Builder",
}
const MANUFACTURED_ROWS: Dictionary = {
	"lumber": 60,
	"fabric": 80,
	"castIron": 160,
	"refinedSugar": 70,
	"cigars": 80,
	"furHats": 110,
	"steel": 170,
	"paper": 60,
	"bronze": 145,
}
const ROSTER: Array[String] = [
	"carrack",
	"fluyte",
	"sloop",
	"trader",
	"galleon",
	"indiaman",
	"frigate",
	"raider",
	"ship_of_the_line",
	"clipper",
	"merchant_steamship",
	"ironclad",
]

# --- test_misc_rules ---

func test_as_string_matches_semver_parts() -> void:
	assert_eq(GameVersion.as_string(), "0.1.0")

func test_is_compatible_with_matching_major() -> void:
	assert_true(GameVersion.is_compatible_with(GameVersion.MAJOR))

func test_is_compatible_with_rejects_other_major() -> void:
	assert_false(GameVersion.is_compatible_with(GameVersion.MAJOR + 1))

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

## A grid boundary is traced dead straight; the hand pass is what makes it read
## as ink. It must move points, never run away, and stay deterministic.
func test_hand_wobbles_a_straight_run_within_bounds() -> void:
	var points := PackedVector2Array()
	for i in 40:
		points.append(Vector2(float(i) * 8.0, 0.0))
	var inked: PackedVector2Array = InkPaths.hand(points, 2.0, 1.4)
	assert_eq(inked.size(), points.size())
	var moved: int = 0
	for i in inked.size():
		var offset: float = absf(inked[i].y - points[i].y)
		assert_true(offset <= 2.0001, "the wobble stays inside its amplitude")
		if offset > 0.05:
			moved += 1
	assert_gt(moved, points.size() / 2, "most of a long straight run is displaced")
	assert_eq(InkPaths.hand(points, 2.0, 1.4), inked)

func test_hand_keeps_a_closed_loop_closed() -> void:
	var loop := PackedVector2Array([
		Vector2(0, 0), Vector2(40, 0), Vector2(40, 40), Vector2(0, 40), Vector2(0, 0),
	])
	var inked: PackedVector2Array = InkPaths.hand(loop, 3.0, 0.7)
	assert_eq(inked.size(), loop.size())
	assert_eq(inked[0], inked[inked.size() - 1])

func test_hand_leaves_short_or_flat_paths_alone() -> void:
	var short := PackedVector2Array([Vector2(0, 0), Vector2(1, 0)])
	assert_eq(InkPaths.hand(short, 2.0), short)
	var straight := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(20, 0)])
	assert_eq(InkPaths.hand(straight, 0.0), straight)

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

func test_a_purchased_tile_draws_its_own_border() -> void:
	var model: MapModel = _model_with_owners([0, 0, 0])
	assert_true(model.purchase_tile(Vector2i(2, 1), 1))
	var borders: Dictionary = CountryBorders.build(model, 1.0)
	assert_true(borders.has(0), "the seller keeps a border")
	assert_true(borders.has(1), "the buyer gets a border")
	assert_true(_has_edge(borders[1], Vector2(3, 1), Vector2(3, 2)), "missing deed edge")

func test_unclaimed_land_gets_no_border() -> void:
	var model: MapModel = _model_with_owners([MapModel.NO_ID, 0, 0])
	var borders: Dictionary = CountryBorders.build(model, 1.0)
	assert_true(borders.is_empty(), "unclaimed land has no country border")

func test_missing_model_is_safe() -> void:
	assert_true(CountryBorders.build(null, 1.0).is_empty())

func test_unknown_land_draws_no_country_border() -> void:
	var model: MapModel = _model_with_owners([0, 1, 0])
	var view := VisibilityModel.new()
	view.setup(model, 0)
	var charted: Dictionary = CountryBorders.build(model, 1.0, view)
	assert_true(charted.has(0), "fogged land still carries its political border")
	view.levels.fill(VisibilityModel.Level.UNKNOWN)
	var uncharted: Dictionary = CountryBorders.build(model, 1.0, view)
	assert_true(uncharted.is_empty(), "unknown land stays off the political map")

func _has_edge(segments: Array, a: Vector2, b: Vector2) -> bool:
	for segment: PackedVector2Array in segments:
		if segment.size() != 2:
			continue
		if segment[0] == a and segment[1] == b:
			return true
		if segment[0] == b and segment[1] == a:
			return true
	return false

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

# --- test_catalogs ---

func test_every_great_power_fields_exactly_one_default_leader() -> void:
	var seen: Dictionary = {}
	for faction: int in FactionCatalog.great_power_ids():
		var keys: Array[String] = LeaderCatalog.keys_for(faction)
		assert_eq(keys.size(), 1, "crown %d fields one leader variant" % faction)
		assert_eq(LeaderCatalog.default_key(faction), keys[0], "first variant is the default")
		var key: String = keys[0]
		assert_false(seen.has(key), "leader key %s is not shared" % key)
		seen[key] = true
		assert_true(LeaderCatalog.label(key) != "")

func test_minors_tribes_and_unknown_factions_reserve_the_neutral_leader() -> void:
	for faction: int in FactionCatalog.minor_ids() + FactionCatalog.tribe_ids():
		assert_eq(LeaderCatalog.default_key(faction), LeaderCatalog.DEFAULT_KEY)
		assert_true(LeaderCatalog.keys_for(faction).is_empty())
	assert_eq(LeaderCatalog.default_key(-1), LeaderCatalog.DEFAULT_KEY)

func test_bonus_table_matches_the_documented_multipliers() -> void:
	# Land is published per side: Napoleon both, Gustavus attacking, Frederick
	# defending (wiki: leader-bonuses § Bonus Table).
	assert_almost_eq(LeaderCatalog.land_multiplier("napoleon", false), 1.25, 0.001)
	assert_almost_eq(LeaderCatalog.land_multiplier("napoleon", true), 1.25, 0.001)
	assert_almost_eq(LeaderCatalog.land_multiplier("gustavus", false), 1.15, 0.001)
	assert_almost_eq(LeaderCatalog.land_multiplier("gustavus", true), 1.0, 0.001)
	assert_almost_eq(LeaderCatalog.land_multiplier("frederick", true), 1.15, 0.001)
	assert_almost_eq(LeaderCatalog.land_multiplier("frederick", false), 1.0, 0.001)
	assert_almost_eq(LeaderCatalog.land_multiplier("reserve", true), 1.0, 0.001)
	assert_almost_eq(LeaderCatalog.land_multiplier("", false), 1.0, 0.001)
	assert_almost_eq(LeaderCatalog.land_multiplier("isabella", false), 1.0, 0.001)
	assert_eq(LeaderCatalog.land_percent("napoleon"), 25)
	assert_eq(LeaderCatalog.land_percent("isabella"), 0)


## One primary bonus per key: each non-land key publishes exactly its own domain
## and nothing else (wiki: leader-bonuses § Design notes).
func test_each_non_land_key_publishes_exactly_its_own_domain() -> void:
	assert_almost_eq(LeaderCatalog.naval_multiplier("de_ruyter"), 1.15, 0.001)
	for key: String in [
		"napoleon", "gustavus", "frederick", "isabella", "henry", "victoria", "reserve"
	]:
		assert_almost_eq(
			LeaderCatalog.naval_multiplier(key), 1.0, 0.001, "%s has no naval row" % key
		)
	assert_almost_eq(LeaderCatalog.first_contact_score("isabella"), 60.0, 0.001)
	assert_almost_eq(
		LeaderCatalog.first_contact_score("henry"), DiplomacyCatalog.INITIAL_SCORE, 0.001
	)
	assert_eq(LeaderCatalog.coastal_rings("henry"), 1)
	assert_eq(LeaderCatalog.coastal_rings("isabella"), 0)
	assert_almost_eq(LeaderCatalog.funding_multiplier("victoria"), 1.15, 0.001)
	assert_almost_eq(LeaderCatalog.funding_multiplier("henry"), 1.0, 0.001)


func test_bonus_labels_name_the_real_effect() -> void:
	assert_true(LeaderCatalog.bonus_label("isabella").contains("first contact"))
	assert_true(LeaderCatalog.bonus_label("henry").contains("coastal"))
	assert_true(LeaderCatalog.bonus_label("de_ruyter").contains("naval"))
	assert_true(LeaderCatalog.bonus_label("victoria").contains("research"))
	assert_true(LeaderCatalog.bonus_label("gustavus").contains("attacking"))
	assert_true(LeaderCatalog.bonus_label("frederick").contains("defending"))
	assert_eq(LeaderCatalog.bonus_label("reserve"), "no bonus",
		"a key with no row never reads as a missing land bonus")

func test_variant_ids_match_exactly_first_then_by_substring() -> void:
	assert_almost_eq(LeaderCatalog.land_multiplier("france_napoleon_leader", false), 1.25, 0.001)
	assert_almost_eq(LeaderCatalog.land_multiplier("Prussia_Frederick_Leader", true), 1.15, 0.001)
	assert_almost_eq(LeaderCatalog.land_multiplier("unknown_court", false), 1.0, 0.001)
	assert_almost_eq(LeaderCatalog.naval_multiplier("dutch_michiel_de_ruyter_leader"), 1.15, 0.001)
	assert_almost_eq(LeaderCatalog.funding_multiplier("ENG_victoria_leader"), 1.15, 0.001)
	assert_eq(LeaderCatalog.coastal_rings("POR_henry_leader"), 1)

func test_roster_assigns_the_choice_to_the_human_crown_only() -> void:
	var roster: Dictionary = LeaderCatalog.roster(2, "napoleon")
	for faction: int in FactionCatalog.great_power_ids():
		assert_true(roster.has(faction), "crown %d has a leader" % faction)
	assert_eq(roster[2], "napoleon")
	assert_eq(roster[0], LeaderCatalog.default_key(0), "rivals keep their config leader")
	var refused: Dictionary = LeaderCatalog.roster(2, "isabella")
	assert_eq(refused[2], "napoleon", "a crown cannot field another crown's leader")

func test_saved_map_keeps_known_keys_and_backfills_missing_crowns() -> void:
	var saved: Dictionary = {0: "isabella", 2: "napoleon", 3: "invented_leader", 99: "napoleon"}
	var restored: Dictionary = LeaderCatalog.from_saved(saved)
	assert_eq(restored[0], "isabella")
	assert_eq(restored[2], "napoleon")
	assert_eq(restored[3], LeaderCatalog.default_key(3), "unknown keys are dropped")
	assert_false(restored.has(99), "non-Great-Power rows are ignored")
	for faction: int in FactionCatalog.great_power_ids():
		assert_true(restored.has(faction), "crown %d backfilled" % faction)

func test_ai_personality_reads_the_same_default_leader() -> void:
	for faction: int in FactionCatalog.great_power_ids():
		assert_eq(AiPersonality.leader_for(faction), LeaderCatalog.default_key(faction))

func test_default_roster_matches_the_configured_counts() -> void:
	assert_eq(FactionCatalog.great_power_ids().size(), 6)
	assert_eq(FactionCatalog.minor_ids().size(), 6)
	assert_eq(FactionCatalog.tribe_ids().size(), 10)
	assert_eq(FactionCatalog.count(), 22)

func test_great_power_colours_follow_gdd_09() -> void:
	## wiki: naming § Default map colour id — GDD 09 RGB per semantic id.
	assert_eq(FactionCatalog.color_of(0), Color8(220, 180, 60), "Spain is yellow")
	assert_eq(FactionCatalog.color_of(1), Color8(180, 80, 80), "England is red")
	assert_eq(FactionCatalog.color_of(2), Color8(80, 140, 200), "France is dark blue")
	assert_eq(FactionCatalog.color_of(3), Color8(90, 160, 90), "Portugal is green")
	assert_eq(
		FactionCatalog.color_of(4),
		Color8(220, 140, 100),
		"United Provinces uses the netherlands orange"
	)
	assert_eq(FactionCatalog.color_of(5), Color8(100, 120, 200), "Sweden is light blue")

func test_ids_are_unique_and_resolvable() -> void:
	var seen: Dictionary = {}
	for faction: Dictionary in FactionCatalog.all():
		var id: int = int(faction["id"])
		assert_false(seen.has(id), "duplicate faction id %d" % id)
		seen[id] = true
		assert_eq(int(FactionCatalog.get_faction(id)["id"]), id)
		assert_true(FactionCatalog.name_of(id) != "")

func test_only_great_powers_win_and_submit_orders() -> void:
	for id: int in FactionCatalog.great_power_ids():
		assert_true(FactionCatalog.can_win(id))
		assert_true(FactionCatalog.submits_orders(id))
		assert_true(FactionCatalog.has_navy(id))
	for id: int in FactionCatalog.minor_ids() + FactionCatalog.tribe_ids():
		assert_false(FactionCatalog.can_win(id))
		assert_false(FactionCatalog.submits_orders(id))
		assert_false(FactionCatalog.has_navy(id))

func test_region_ownership_matches_faction_type() -> void:
	for id: int in FactionCatalog.great_power_ids():
		assert_true(FactionCatalog.can_own_region(id, FactionCatalog.OLD_WORLD))
		assert_true(FactionCatalog.can_own_region(id, FactionCatalog.NEW_WORLD))
	for id: int in FactionCatalog.minor_ids():
		assert_true(FactionCatalog.can_own_region(id, FactionCatalog.OLD_WORLD))
		assert_false(FactionCatalog.can_own_region(id, FactionCatalog.NEW_WORLD))
	for id: int in FactionCatalog.tribe_ids():
		assert_false(FactionCatalog.can_own_region(id, FactionCatalog.OLD_WORLD))
		assert_true(FactionCatalog.can_own_region(id, FactionCatalog.NEW_WORLD))

func test_minors_have_military_parity_but_tribes_do_not() -> void:
	for id: int in FactionCatalog.minor_ids():
		assert_true(FactionCatalog.has_military_parity(id))
	for id: int in FactionCatalog.tribe_ids():
		assert_false(FactionCatalog.has_military_parity(id))

func test_unknown_ids_fall_back_to_unclaimed() -> void:
	assert_eq(FactionCatalog.name_of(-1), "Unclaimed")
	assert_eq(FactionCatalog.type_of(-1), -1)
	assert_false(FactionCatalog.can_own_region(-1, FactionCatalog.OLD_WORLD))
	assert_false(FactionCatalog.has_faction(999))

func test_region_labels_and_keys_are_defined() -> void:
	assert_eq(FactionCatalog.region_label(FactionCatalog.OLD_WORLD), "Old World")
	assert_eq(FactionCatalog.region_label(FactionCatalog.NEW_WORLD), "New World")
	assert_eq(FactionCatalog.region_key(FactionCatalog.NEW_WORLD), "new_world")
	assert_eq(FactionCatalog.ids_in_region(FactionCatalog.NEW_WORLD), FactionCatalog.tribe_ids())

func test_names_are_indexed_by_faction_id() -> void:
	var names: Array[String] = FactionCatalog.names()
	assert_eq(names.size(), FactionCatalog.count())
	for faction: Dictionary in FactionCatalog.all():
		var id: int = int(faction["id"])
		assert_eq(names[id], FactionCatalog.name_of(id))

func test_catalog_lists_every_regiment_once() -> void:
	var ids: Array[String] = RegimentCatalog.ids()
	assert_eq(ids.size(), 29)
	var seen: Dictionary = {}
	for type_id: String in ids:
		assert_false(seen.has(type_id), "duplicate regiment %s" % type_id)
		seen[type_id] = true
		assert_eq(RegimentCatalog.display_name(type_id), String(RegimentCatalog.row(type_id)["name"]))

func test_tactical_stats_match_the_wiki_table() -> void:
	assert_eq(RegimentCatalog.stat("peasant_levies", "fpn"), 0)
	assert_eq(RegimentCatalog.stat("peasant_levies", "fpm"), 3)
	assert_eq(RegimentCatalog.stat("guards", "fpn"), 12)
	assert_eq(RegimentCatalog.stat("guards", "fpm"), 10)
	assert_eq(RegimentCatalog.stat("siege_guns", "rng"), 12)
	assert_eq(RegimentCatalog.stat("carbine_cavalry", "mvr"), 9)
	assert_eq(RegimentCatalog.era("guards"), 4)
	assert_eq(RegimentCatalog.era("culverin"), 1)

func test_categories_drive_cavalry_and_infantry_rules() -> void:
	assert_true(RegimentCatalog.is_cavalry("squires"))
	assert_true(RegimentCatalog.is_cavalry("cuirassiers"))
	assert_false(RegimentCatalog.is_cavalry("guards"))
	assert_true(RegimentCatalog.is_artillery("royal_artillery"))
	assert_false(RegimentCatalog.is_infantry("field_artillery"))
	assert_true(RegimentCatalog.is_infantry("bowmen"))
	assert_true(RegimentCatalog.is_infantry("peasant_levies"))

## Regiment detail: the dossier line names the category, the tactical stats and
## the food bill; the despatch text groups losses by type, name-ordered.
func test_regiment_detail_lines_carry_stats_and_tally_losses() -> void:
	assert_eq(RegimentCatalog.category_name("guards"), "Heavy infantry")
	assert_eq(RegimentCatalog.category_name("culverin"), "Heavy artillery")
	assert_eq(RegimentCatalog.category_name("peasant_levies"), "Light infantry")
	assert_eq(RegimentCatalog.category_name("pikemen"), "Regular infantry")
	assert_eq(RegimentCatalog.category_name("bowmen"), "Bowmen")
	assert_eq(RegimentCatalog.category_name("squires"), "Light cavalry")
	assert_eq(RegimentCatalog.category_name("knights"), "Spear cavalry")
	assert_eq(RegimentCatalog.category_name("harquebusiers"), "Heavy cavalry")
	assert_eq(RegimentCatalog.category_name("horse_artillery"), "Light artillery")
	assert_eq(
		RegimentCatalog.detail_line("guards"),
		"Heavy infantry · FPN 12 · FPM 10 · RNG 6 · DEF 6 · MVR 4 · 3 food"
	)
	assert_eq(RegimentCatalog.detail_text({"guards": 3}), "3 Guards")
	assert_eq(RegimentCatalog.detail_text({"guards": 1}), "Guards")
	assert_eq(
		RegimentCatalog.detail_text({"pikemen": 3, "culverin": 1}),
		"Culverin · 3 Pikemen"
	)
	assert_eq(RegimentCatalog.detail_text({}), "")

func test_treasury_costs_follow_the_canonical_scale() -> void:
	assert_eq(RegimentCatalog.treasury_cost("peasant_levies"), 2000)
	assert_eq(RegimentCatalog.treasury_cost("arquebusiers"), 5000)
	assert_eq(RegimentCatalog.treasury_cost("siege_guns"), 22000)

func test_food_upkeep_keeps_cavalry_and_artillery_highest() -> void:
	assert_eq(RegimentCatalog.food_upkeep("peasant_levies"), 1)
	assert_eq(RegimentCatalog.food_upkeep("pikemen"), 2)
	assert_eq(RegimentCatalog.food_upkeep("guards"), 3)
	assert_eq(RegimentCatalog.food_upkeep("squires"), 3)
	assert_eq(RegimentCatalog.food_upkeep("culverin"), 3)

func test_unknown_types_fall_back_to_peasant_levies() -> void:
	assert_eq(RegimentCatalog.normalize("dragoons"), RegimentCatalog.DEFAULT_TYPE)
	assert_eq(RegimentCatalog.display_name("dragoons"), "Regiment")
	assert_false(RegimentCatalog.has_type("dragoons"))

func test_garrison_recovery_uses_the_most_advanced_infantry_for_the_era() -> void:
	assert_eq(RegimentCatalog.garrison_type_for(4), "guards")
	assert_eq(RegimentCatalog.garrison_type_for(1), "arquebusiers")
	assert_eq(RegimentCatalog.garrison_type_for(9), RegimentCatalog.DEFAULT_TYPE)

func test_catalog_holds_the_full_wiki_tree() -> void:
	assert_eq(TechCatalog.TECHS.size(), TechAudit.EXPECTED_COUNT)
	assert_eq(TechCatalog.ids().size(), TechCatalog.TECHS.size())
	assert_eq(TechAudit.validate(), [] as Array[String])
	assert_true(TechCatalog.roots().size() >= 7, "several starting techs")

func test_costs_follow_the_era_formula() -> void:
	var costs: Dictionary = {}
	for tech_id: String in TechCatalog.ids():
		costs[TechCatalog.cost(tech_id)] = true
	assert_eq(costs.size(), 4)
	assert_true(costs.has(1800))
	assert_true(costs.has(2400))
	assert_true(costs.has(3000))
	assert_true(costs.has(3600))
	assert_eq(TechCatalog.cost("crop_rotation"), 1800)
	assert_eq(TechCatalog.cost("saw_mill"), 1800)
	assert_eq(TechCatalog.cost("wind_saw_mill"), 2400)
	assert_eq(TechCatalog.cost("circular_saw"), 3000)
	assert_eq(TechCatalog.cost("safety_lamp"), 3600)

func test_prerequisites_cross_categories() -> void:
	assert_has(TechCatalog.prerequisites("circular_saw"), "university")
	assert_has(TechCatalog.prerequisites("dynamite"), "banking")
	assert_has(TechCatalog.prerequisites("dynamite"), "explosives")
	assert_has(TechCatalog.prerequisites("large_tobacco_plantations"), "seed_drill")
	assert_has(TechCatalog.dependents("university"), "advanced_hull_design")
	assert_eq(TechCatalog.prerequisites("crop_rotation"), [] as Array[String])

func test_extraction_caps_default_to_one() -> void:
	assert_eq(TechCatalog.extraction_caps({}), {})
	assert_eq(TechCatalog.cap_for("grain", {}), 1)
	assert_eq(TechCatalog.cap_for("timber", {"land_enclosure": true}), 1)
	assert_eq(TechCatalog.cap_for("horses", {"crop_rotation": true}), 1)

func test_gathering_techs_lift_the_cap_per_resource() -> void:
	var unlocked: Dictionary = {"land_enclosure": true}
	assert_eq(TechCatalog.cap_for("grain", unlocked), 2)
	unlocked["seed_drill"] = true
	assert_eq(TechCatalog.cap_for("grain", unlocked), 3)
	unlocked["moldboard_plow"] = true
	assert_eq(TechCatalog.cap_for("grain", unlocked), 4)
	assert_eq(TechCatalog.extraction_caps(unlocked), {"grain": 4})

func test_cap_chains_stop_at_the_wiki_exceptions() -> void:
	var wool: Dictionary = {"sheep_ranching": true, "scientific_sheep_breeding": true}
	assert_eq(TechCatalog.cap_for("wool", wool), TechCatalog.CAP_EXCEPTIONS["wool"])
	assert_eq(TechCatalog.CAP_EXCEPTIONS["horses"], 1)
	var iron: Dictionary = {
		"iron_mining": true, "steam_in_mining": true, "industrial_iron_mining": true,
	}
	assert_eq(TechCatalog.cap_for("iron", iron), 4)
	var copper: Dictionary = {
		"copper_and_tin_mining": true, "large_copper_and_tin_mines": true,
		"efficient_extraction_of_copper_and_tin": true,
	}
	assert_eq(TechCatalog.cap_for("copper", copper), 4)
	assert_eq(TechCatalog.cap_for("tin", copper), 4)

func test_discovery_techs_name_their_resources() -> void:
	assert_eq(TechCatalog.discovery_resources("discovery_of_sugar"), ["sugarCane"])
	assert_eq(
		TechCatalog.discovery_resources("discovery_of_gold_or_silver"),
		["gold", "silver"]
	)
	assert_eq(TechCatalog.discovery_resources("saw_mill"), [] as Array[String])
	assert_eq(TechCatalog.display_name("discovery_of_sugar"), "Discovery of Sugar")

## Every resource the map can place carries its published base name (wiki:
## extraction-and-improvements § Improvement Naming): minerals read Mine, the
## crops their own work, and no index falls back to the generic "Improvement".
func test_every_placeable_resource_has_its_published_improvement() -> void:
	var names: Dictionary = {
		"timber": "Lumber camp", "iron": "Mine", "coal": "Mine", "gold": "Mine",
		"grain": "Farm", "wool": "Pasture", "horses": "Ranch", "meat": "Ranch",
		"tin": "Mine", "copper": "Mine", "silver": "Mine", "gems": "Mine",
		"diamonds": "Mine", "sugarCane": "Plantation", "tobacco": "Plantation",
		"cotton": "Plantation", "furs": "Fur post", "spices": "Plantation",
	}
	var table: Array[Dictionary] = MapGenerator.resource_table()
	assert_eq(table.size(), names.size())
	for index in table.size():
		var commodity: String = String(table[index]["commodity"])
		assert_true(names.has(commodity), "unpublished resource %s" % commodity)
		assert_eq(ImprovementCatalog.base_name(index), String(names[commodity]), commodity)
		assert_eq(
			ImprovementCatalog.display_name(index, 2),
			"%s (L2)" % String(names[commodity]),
			commodity
		)

func test_effect_text_uses_the_fixed_phrases() -> void:
	assert_true(TechCatalog.effect_text("saw_mill").contains("Improves:"))
	assert_true(TechCatalog.effect_text("saw_mill").to_lower().contains("timber"))
	assert_true(TechCatalog.effect_text("land_enclosure").contains("Unlocks:"))
	assert_true(TechCatalog.effect_text("discovery_of_sugar").contains("Enables:"))
	assert_true(TechCatalog.effect_text("clipper_ships").contains("Unlocks:"))
	assert_true(TechCatalog.effect_text("crop_rotation").contains("Unlocks:"))

func test_catalog_covers_all_six_wiki_types() -> void:
	assert_eq(CivilianCatalog.TYPES.size(), 6)
	assert_eq(CivilianCatalog.ORDER.size(), 6)
	for type_id: String in CivilianCatalog.ORDER:
		assert_true(CivilianCatalog.known(type_id), type_id)
		assert_eq(CivilianCatalog.display_name(type_id), String(ROLE_NAMES[type_id]))

func test_training_costs_match_the_wiki() -> void:
	for type_id: String in ["explorer", "engineer", "builder"]:
		assert_eq(CivilianCatalog.treasury_cost(type_id), 1000, type_id)
		assert_eq(CivilianCatalog.paper_cost(type_id), 2, type_id)
	for type_id: String in ["spy", "merchant", "rail_builder"]:
		assert_eq(CivilianCatalog.treasury_cost(type_id), 2000, type_id)
		assert_eq(CivilianCatalog.paper_cost(type_id), 4, type_id)

func test_the_playable_roster_includes_the_spy_merchant_and_rail_builder() -> void:
	assert_eq(
		CivilianCatalog.playable_types(),
		["explorer", "engineer", "builder", "spy", "merchant", "rail_builder"]
	)
	assert_true(CivilianCatalog.is_implemented("spy"), "Spy")
	for type_id: String in CivilianCatalog.playable_types():
		assert_true(CivilianCatalog.is_implemented(type_id), type_id)
		assert_eq(CivilianCatalog.deferred_reason(type_id), "")

func test_tech_gated_types_unlock_on_research() -> void:
	assert_eq(CivilianCatalog.unlock_tech("explorer"), "")
	assert_eq(CivilianCatalog.unlock_tech("rail_builder"), "early_steam_engine")
	assert_eq(CivilianCatalog.unlock_tech("merchant"), "merchant_companies")
	assert_true(CivilianCatalog.is_unlocked("explorer"))
	assert_false(CivilianCatalog.is_unlocked("rail_builder"))
	assert_true(CivilianCatalog.is_unlocked("rail_builder", {"early_steam_engine": true}))

func test_work_lists_match_the_wiki_table() -> void:
	assert_eq(CivilianCatalog.works("explorer"), ["explore", "prospect"])
	assert_eq(CivilianCatalog.works("builder"), ["build_improvement", "upgrade_town"])
	assert_eq(
		CivilianCatalog.works("engineer"),
		["build_road", "build_port", "build_fort", "build_hospital"],
		"a fort and a hospital are the engineer's province works"
	)
	assert_eq(CivilianCatalog.works("spy"), ["counter_spy"], "screen plus passive tradecraft")
	assert_eq(CivilianCatalog.works("merchant"), ["purchase_land"])
	assert_eq(CivilianCatalog.works("rail_builder"), ["build_rail"])

func test_affordability_needs_cash_and_paper() -> void:
	assert_true(CivilianCatalog.can_afford("explorer", 1000, 2))
	assert_false(CivilianCatalog.can_afford("explorer", 999, 2))
	assert_false(CivilianCatalog.can_afford("explorer", 1000, 1))
	assert_false(CivilianCatalog.can_afford("merchant", 1999, 4))

func test_training_cost_text_reads_as_a_purse_line() -> void:
	assert_eq(CivilianCatalog.training_cost_text("explorer"), "1,000 cash + 2 paper")
	assert_eq(CivilianCatalog.training_cost_text("merchant"), "2,000 cash + 4 paper")

func test_unknown_types_fall_back_to_a_known_row() -> void:
	assert_false(CivilianCatalog.known("privateer"))
	assert_true(CivilianCatalog.known(CivilianCatalog.normalize("privateer")))
	assert_eq(CivilianCatalog.normalize("privateer"), CivilianCatalog.DEFAULT_TYPE)

func test_catalog_covers_the_wiki_lists() -> void:
	assert_eq(CommodityCatalog.FOOD, ["grain", "meat"] as Array[String])
	assert_eq(CommodityCatalog.RAW.size(), 11)
	assert_eq(CommodityCatalog.MANUFACTURED.size(), 9)
	assert_eq(CommodityCatalog.LUXURY.size(), 0)
	assert_eq(
		CommodityCatalog.RICHES,
		["gold", "silver", "gems", "diamonds", "spices"] as Array[String]
	)
	assert_eq(CommodityCatalog.ADVANCED, [] as Array[String])
	assert_eq(CommodityCatalog.all_ids().size(), 27)

func test_categories_match_the_table() -> void:
	assert_eq(CommodityCatalog.category_of("grain"), CommodityCatalog.Category.FOOD)
	assert_eq(CommodityCatalog.category_of("timber"), CommodityCatalog.Category.RAW)
	assert_eq(CommodityCatalog.category_of("castIron"), CommodityCatalog.Category.MANUFACTURED)
	assert_eq(CommodityCatalog.category_of("gold"), CommodityCatalog.Category.RICHES)
	assert_eq(CommodityCatalog.category_of("spices"), CommodityCatalog.Category.RICHES)
	assert_eq(CommodityCatalog.category_of("silk"), CommodityCatalog.NO_CATEGORY)
	assert_false(CommodityCatalog.known("silk"))
	assert_eq(CommodityCatalog.category_label(CommodityCatalog.Category.RAW), "Raw materials")

func test_tradeable_excludes_only_riches() -> void:
	assert_true(CommodityCatalog.is_tradeable("timber"))
	assert_true(CommodityCatalog.is_tradeable("lumber"))
	assert_true(CommodityCatalog.is_tradeable("grain"))
	# Spices is a rich: not traded; clears to treasury at 50 (Imperialism II;
	# wiki: world-market § Tradeable commodities; DR-20261113-13).
	assert_false(CommodityCatalog.is_tradeable("spices"))
	assert_false(CommodityCatalog.is_tradeable("gold"))
	assert_false(CommodityCatalog.is_tradeable("diamonds"))
	assert_false(CommodityCatalog.is_tradeable("silk"))
	var tradeable: int = 0
	for id: String in CommodityCatalog.all_ids():
		if CommodityCatalog.is_tradeable(id):
			tradeable += 1
	assert_eq(tradeable, 22)

func test_manufactured_prices_are_break_even() -> void:
	for id: String in MANUFACTURED_ROWS.keys():
		assert_eq(CommodityCatalog.base_price(id), int(MANUFACTURED_ROWS[id]), id)

func test_raw_and_riches_prices_match_the_rules() -> void:
	assert_eq(CommodityCatalog.base_price("grain"), 50)
	assert_eq(CommodityCatalog.base_price("timber"), 30)
	assert_eq(CommodityCatalog.base_price("iron"), 80)
	assert_eq(CommodityCatalog.base_price("coal"), 90)
	assert_eq(CommodityCatalog.base_price("spices"), 50)
	assert_eq(CommodityCatalog.base_price("gold"), 166)
	assert_eq(CommodityCatalog.base_price("diamonds"), 500)
	assert_eq(CommodityCatalog.base_price("silk"), 0)

func test_labels_are_readable_and_stable() -> void:
	assert_eq(CommodityCatalog.label("grain"), "Grain")
	assert_eq(CommodityCatalog.label("castIron"), "Cast Iron")
	assert_eq(CommodityCatalog.label("sugarCane"), "Sugar Cane")
	assert_eq(CommodityCatalog.label("furHats"), "Fur Hats")

func test_ids_in_returns_a_copy_of_the_category() -> void:
	var food: Array[String] = CommodityCatalog.ids_in(CommodityCatalog.Category.FOOD)
	assert_eq(food, ["grain", "meat"] as Array[String])
	food.append("silk")
	assert_eq(CommodityCatalog.ids_in(CommodityCatalog.Category.FOOD).size(), 2)
	assert_eq(CommodityCatalog.ids_in(CommodityCatalog.Category.LUXURY).size(), 0)

func test_ship_stats_cover_the_whole_roster() -> void:
	assert_eq(ShipStats.STATS.size(), ROSTER.size())
	for ship_id: String in ROSTER:
		assert_true(ShipStats.known(ship_id), ship_id)

func test_frozen_merchant_rows_match_the_wiki() -> void:
	var carrack: Dictionary = ShipStats.entry("carrack")
	assert_eq(int(carrack["frp"]), 2)
	assert_eq(int(carrack["rng"]), 1)
	assert_eq(int(carrack["arm"]), 1)
	assert_eq(int(carrack["hull"]), 2)
	assert_eq(int(carrack["mv"]), 2)
	assert_eq(int(carrack["cargo"]), 3)
	var fluyte: Dictionary = ShipStats.entry("fluyte")
	assert_eq(int(fluyte["hull"]), 1)
	assert_eq(int(fluyte["flee"]), 3)
	assert_eq(int(fluyte["cargo"]), 4)

func test_line_and_steam_rows_match_the_wiki() -> void:
	var line: Dictionary = ShipStats.entry("ship_of_the_line")
	assert_eq(int(line["frp"]), 6)
	assert_eq(int(line["hull"]), 8)
	assert_eq(int(line["intercept"]), 2)
	var ironclad: Dictionary = ShipStats.entry("ironclad")
	assert_eq(int(ironclad["arm"]), 8)
	assert_eq(int(ironclad["cargo"]), 0)
	var steamer: Dictionary = ShipStats.entry("merchant_steamship")
	assert_eq(int(steamer["cargo"]), 9)
	assert_eq(int(steamer["arm"]), 3)

func test_role_split_and_cargo_holds() -> void:
	assert_true(ShipStats.is_warship("sloop"))
	assert_true(ShipStats.is_warship("ship_of_the_line"))
	assert_false(ShipStats.is_warship("galleon"))
	for ship_id: String in ROSTER:
		var cargo: int = int(ShipStats.entry(ship_id)["cargo"])
		if ShipStats.is_warship(ship_id):
			assert_eq(cargo, 0, ship_id)
		else:
			assert_gt(cargo, 0, ship_id)

func test_strength_weights_firepower_range_armour_and_speed() -> void:
	# carrack: 2*1.0 + 1*0.4 + 1*0.15 + 2*0.1
	assert_almost_eq(ShipStats.strength("carrack"), 2.75, 0.0001)
	# ironclad: 5 + 1.2 + 1.2 + 0.3
	assert_almost_eq(ShipStats.strength("ironclad"), 7.7, 0.0001)
	# sloop: 2 + 0.8 + 0.15 + 0.3
	assert_almost_eq(ShipStats.strength("sloop"), 3.25, 0.0001)

func test_durability_is_hull_times_armour_bonus() -> void:
	# HULL * (1 + ARM/10)
	assert_almost_eq(ShipStats.durability("carrack"), 2.2, 0.0001)
	assert_almost_eq(ShipStats.durability("ironclad"), 10.8, 0.0001)
	assert_almost_eq(ShipStats.durability("fluyte"), 1.1, 0.0001)

func test_unknown_ship_stats_fall_back_to_the_carrack() -> void:
	assert_false(ShipStats.known("dromon"))
	assert_eq(ShipStats.normalize("dromon"), "carrack")
	assert_eq(ShipStats.entry("dromon"), ShipStats.entry("carrack"))
	assert_almost_eq(ShipStats.strength("dromon"), 2.75, 0.0001)

func test_display_names_are_period_readable() -> void:
	assert_eq(ShipStats.display_name("ship_of_the_line"), "Ship of the Line")
	assert_eq(ShipStats.display_name("merchant_steamship"), "Merchant Steamship")
	assert_eq(ShipStats.display_name("dromon"), "Carrack")

func test_ship_economy_covers_the_whole_roster() -> void:
	assert_eq(ShipEconomy.ENTRIES.size(), ROSTER.size())
	for ship_id: String in ROSTER:
		assert_true(ShipEconomy.known(ship_id), ship_id)
		assert_true(ShipStats.known(ship_id), ship_id)

func test_frozen_baseline_rows_match_the_wiki() -> void:
	assert_eq(ShipEconomy.treasury_cost("carrack"), 8000)
	assert_eq(ShipEconomy.build_inputs("carrack"), {"lumber": 2, "fabric": 1})
	assert_true(ShipEconomy.is_always_buildable("carrack"))
	assert_eq(ShipEconomy.unlock_era("carrack"), 0)
	assert_eq(ShipEconomy.treasury_cost("fluyte"), 6000)
	assert_eq(ShipEconomy.build_inputs("fluyte"), {"lumber": 1, "fabric": 1})
	assert_eq(ShipEconomy.unlock_era("fluyte"), 1)

func test_steam_and_line_rows_match_the_wiki() -> void:
	assert_eq(ShipEconomy.treasury_cost("ship_of_the_line"), 16500)
	assert_eq(ShipEconomy.build_inputs("ship_of_the_line"), {"lumber": 5, "fabric": 3})
	assert_eq(ShipEconomy.unlock_era("ship_of_the_line"), 3)
	assert_eq(ShipEconomy.treasury_cost("ironclad"), 21000)
	assert_eq(
		ShipEconomy.build_inputs("ironclad"), {"lumber": 2, "fabric": 2, "castIron": 5}
	)
	assert_eq(ShipEconomy.unlock_era("ironclad"), 4)
	assert_eq(ShipEconomy.treasury_cost("merchant_steamship"), 15500)
	assert_eq(
		ShipEconomy.build_inputs("merchant_steamship"),
		{"lumber": 2, "fabric": 2, "coal": 3}
	)
	assert_eq(ShipEconomy.treasury_cost("raider"), 11500)
	assert_eq(
		ShipEconomy.build_inputs("raider"), {"lumber": 2, "fabric": 1, "castIron": 2}
	)

func test_roles_align_with_ship_stats() -> void:
	for ship_id: String in ROSTER:
		var role: String = String(ShipEconomy.entry(ship_id)["role"])
		if ShipStats.is_warship(ship_id):
			assert_eq(role, "warship", ship_id)
		else:
			assert_eq(role, "merchant", ship_id)

func test_unknown_ship_economy_falls_back_to_the_carrack() -> void:
	assert_false(ShipEconomy.known("dromon"))
	assert_eq(ShipEconomy.entry("dromon"), ShipEconomy.entry("carrack"))
	assert_eq(ShipEconomy.treasury_cost("dromon"), 8000)

func test_food_upkeep_is_two_per_hull() -> void:
	assert_eq(ShipEconomy.FOOD_UPKEEP_PER_SHIP, 2)
	assert_eq(ShipEconomy.food_upkeep_per_ship("carrack"), 2)
	assert_eq(ShipEconomy.food_upkeep_per_ship("ironclad"), 2)
	var fleet: FleetState = FleetState.at_sea(
		1, 0, 3, ["ship_1", "ship_2", "ship_3"], {"ship_1": "sloop", "ship_2": "carrack"}
	)
	assert_eq(ShipEconomy.food_upkeep_for_fleet(fleet), 6)
	var minted: FleetState = FleetState.at_sea(2, 0, 3, [])
	# Factory still mints one default hull when none are given.
	assert_eq(ShipEconomy.food_upkeep_for_fleet(minted), 2)
	var sunk: FleetState = FleetState.at_sea(3, 0, 3, ["ship_9"])
	sunk.remove_hull("ship_9")
	assert_eq(ShipEconomy.food_upkeep_for_fleet(sunk), 0)
	assert_eq(ShipEconomy.food_upkeep_for_fleet(null), 0)

func test_food_upkeep_sums_owned_fleets_only() -> void:
	var fleets: Array[FleetState] = [
		FleetState.at_sea(1, 0, 1, ["ship_1", "ship_2"]),
		FleetState.at_sea(2, 1, 2, ["ship_3", "ship_4", "ship_5"]),
		FleetState.in_port(3, 0, 4, ["ship_6"]),
	]
	assert_eq(ShipEconomy.food_upkeep_for_owner(fleets, 0), 6)
	assert_eq(ShipEconomy.food_upkeep_for_owner(fleets, 1), 6)
	assert_eq(ShipEconomy.food_upkeep_for_owner(fleets, 2), 0)

func test_can_afford_checks_treasury_and_materials() -> void:
	var stock: Dictionary = {"lumber": 2, "fabric": 1}
	assert_true(ShipEconomy.can_afford("carrack", 8000, stock))
	assert_false(ShipEconomy.can_afford("carrack", 7999, stock))
	assert_false(ShipEconomy.can_afford("carrack", 8000, {"lumber": 1, "fabric": 1}))
	assert_true(ShipEconomy.can_afford("sloop", 5500, {"lumber": 1, "fabric": 1}))
	assert_false(
		ShipEconomy.can_afford("ironclad", 21000, {"lumber": 2, "fabric": 2, "castIron": 4})
	)
	assert_true(
		ShipEconomy.can_afford("ironclad", 21000, {"lumber": 2, "fabric": 2, "castIron": 5})
	)

func test_missing_inputs_lists_shortfalls() -> void:
	var short: Dictionary = ShipEconomy.missing_inputs(
		"raider", {"lumber": 1, "fabric": 1, "castIron": 0}
	)
	assert_eq(short, {"lumber": 1, "castIron": 2})
	assert_eq(ShipEconomy.missing_inputs("carrack", {"lumber": 2, "fabric": 1}), {})

func test_catalog_has_the_published_recipes() -> void:
	assert_eq(ProductionRecipes.ids().size(), 10)
	assert_eq(ProductionRecipes.output("lumber"), "lumber")
	assert_eq(ProductionRecipes.inputs("lumber"), {"timber": 2})
	assert_eq(ProductionRecipes.labour("lumber"), 2)
	assert_eq(ProductionRecipes.inputs("bronze"), {"copper": 1, "tin": 1})
	assert_eq(ProductionRecipes.labour("bronze"), 3)
	assert_eq(ProductionRecipes.output("fabric_from_wool"), "fabric")
	assert_false(ProductionRecipes.known("silk_gown"))

func test_inputs_are_returned_as_a_copy() -> void:
	var inputs: Dictionary = ProductionRecipes.inputs("lumber")
	inputs["timber"] = 99
	assert_eq(ProductionRecipes.inputs("lumber"), {"timber": 2})

func test_cotton_fabric_needs_its_technology() -> void:
	assert_true(ProductionRecipes.available("fabric_from_wool", {}))
	assert_false(ProductionRecipes.available("fabric_from_cotton", {}))
	assert_true(ProductionRecipes.available("fabric_from_cotton", {"cotton_weaving": true}))
	assert_false(ProductionRecipes.available("fabric_from_cotton", {"cotton_weaving": false}))
	var gated: Array[String] = ProductionRecipes.available_ids({})
	assert_false(gated.has("fabric_from_cotton"))
	assert_true(gated.has("fabric_from_wool"))
	assert_true(ProductionRecipes.available("steel", {}))

func test_max_runs_is_limited_by_inputs_and_labour() -> void:
	assert_eq(ProductionRecipes.max_runs("lumber", {"timber": 10}, 6), 3)
	assert_eq(ProductionRecipes.max_runs("lumber", {"timber": 3}, 20), 1)
	assert_eq(ProductionRecipes.max_runs("lumber", {"timber": 0}, 20), 0)
	assert_eq(ProductionRecipes.max_runs("bronze", {"copper": 5, "tin": 2}, 9), 2)
	assert_eq(ProductionRecipes.max_runs("bronze", {"copper": 5, "tin": 2}, 2), 0)
	assert_eq(ProductionRecipes.max_runs("unknown", {"timber": 10}, 10), 0)

## The ledger's per-row ceiling: the whole runs the coming phase could start from
## the post-Consumption store once the other rows hold their claims. The row's
## own assignment is not counted against itself, so a full board still reads a
## true ceiling for each row (wiki: stockpiles-and-production § Production flow;
## issue #453).
func test_allowance_holds_back_the_other_rows_claims() -> void:
	assert_eq(ProductionRecipes.allowance("lumber", {"timber": 4}, 20, []), 2)
	# Paper and lumber share timber: two paper runs eat the whole tonnage.
	assert_eq(
		ProductionRecipes.allowance("lumber", {"timber": 4}, 20, [{"recipe": "paper", "units": 2}]),
		0
	)
	assert_eq(
		ProductionRecipes.allowance("lumber", {"timber": 4}, 20, [{"recipe": "lumber", "units": 1}]),
		2
	)
	# Labour is shared too: two paper runs spend four of six points.
	assert_eq(
		ProductionRecipes.allowance("lumber", {"timber": 8}, 6, [{"recipe": "paper", "units": 2}]),
		1
	)
	assert_eq(ProductionRecipes.allowance("unknown", {"timber": 4}, 20, []), 0)
	assert_eq(ProductionRecipes.claimed_labour([{"recipe": "steel", "units": 3}]), 6)
	# A row with no recipe, and a row that is not a dictionary, claim nothing.
	assert_eq(
		ProductionRecipes.claimed_labour([{"recipe": "bronze", "units": 2}, {"units": 5}, 7]),
		6
	)


func test_plan_runs_whole_recipes_and_scales_io() -> void:
	var stock: Dictionary = {"timber": 5}
	var report: Dictionary = ProductionRecipes.plan(
		[{"recipe": "lumber", "units": 3}], stock, 6, {}
	)
	assert_eq(report["runs"], {"lumber": 2})
	assert_eq(report["consumed"], {"timber": 4})
	assert_eq(report["produced"], {"lumber": 2})
	assert_eq(report["labour_used"], 4)
	assert_eq(stock["timber"], 1)
	assert_eq(stock["lumber"], 2)

func test_plan_skips_recipes_it_cannot_run_once() -> void:
	var stock: Dictionary = {"timber": 1}
	var report: Dictionary = ProductionRecipes.plan(
		[{"recipe": "lumber", "units": 4}], stock, 10, {}
	)
	assert_eq(report["runs"], {})
	assert_eq(report["produced"], {})
	assert_eq(stock["timber"], 1)
	assert_eq(report["labour_used"], 0)

func test_plan_respects_assignment_order_and_labour_budget() -> void:
	var stock: Dictionary = {"iron": 4, "coal": 2}
	var report: Dictionary = ProductionRecipes.plan(
		[
			{"recipe": "steel", "units": 2},
			{"recipe": "castIron", "units": 2},
		],
		stock,
		4,
		{}
	)
	# Steel takes the full labour budget first; castIron never starts. Alloy
	# output stays in the workshop until the next Production phase.
	assert_eq(report["runs"], {"steel": 2})
	assert_eq(report["produced"], {})
	assert_eq(int(stock.get("steel", 0)), 0)
	assert_eq(ProductionWorkshop.units(report["wip"], "steel"), 2)
	assert_eq(stock["iron"], 2)
	assert_eq(stock["coal"], 0)
	assert_eq(report["labour_used"], 4)

func test_plan_ignores_unavailable_and_zero_unit_rows() -> void:
	var stock: Dictionary = {"cotton": 4, "timber": 4}
	var report: Dictionary = ProductionRecipes.plan(
		[
			{"recipe": "fabric_from_cotton", "units": 2},
			{"recipe": "lumber", "units": 0},
			{"recipe": "lumber", "units": -3},
		],
		stock,
		10,
		{}
	)
	assert_eq(report["runs"], {})
	assert_eq(stock["cotton"], 4)
	assert_eq(stock["timber"], 4)
	var allowed: Dictionary = ProductionRecipes.plan(
		[{"recipe": "fabric_from_cotton", "units": 2}], stock, 10, {"cotton_weaving": true}
	)
	assert_eq(allowed["runs"], {"fabric_from_cotton": 2})
	assert_eq(stock["cotton"], 0)
	assert_eq(stock["fabric"], 2)

## The workshop owner cleans a save's batches and serves the landings a phase
## pays, without knowing any recipe (wiki: production-recipes § Turns per unit;
## DR-20261112-11, DR-20261113-02).
func test_workshop_cleans_batches_and_serves_landings() -> void:
	assert_eq(ProductionWorkshop.clean_batch({"units": 2, "turns_left": 1}), {
		"units": 2, "turns_left": 1
	})
	assert_eq(ProductionWorkshop.clean_batch({"units": 0, "turns_left": 1}), {})
	assert_eq(ProductionWorkshop.clean_batch({"units": 2, "turns_left": 0}), {})
	assert_eq(ProductionWorkshop.clean_batch("steel"), {})
	var wip: Dictionary = {
		"steel": [{"units": 3, "turns_left": 1}, {"units": 2, "turns_left": 2}, "bad"],
	}
	assert_eq(ProductionWorkshop.batches(wip, "steel").size(), 2)
	assert_eq(ProductionWorkshop.batches({"steel": "bad"}, "steel"), [])
	assert_eq(ProductionWorkshop.units(wip, "steel"), 5)
	assert_eq(ProductionWorkshop.soonest(wip, "steel"), 1)
	assert_eq(ProductionWorkshop.soonest({}, "steel"), 0)
	assert_eq(ProductionWorkshop.ready_units(wip, "steel", 2), 1, "only the served batch lands")
	assert_eq(ProductionWorkshop.serve(wip, "steel", 2), {
		"landed": 1,
		"kept": [{"units": 2, "turns_left": 1}, {"units": 2, "turns_left": 1}],
	})
	assert_eq(ProductionWorkshop.serve({}, "steel", 2), {"landed": 0, "kept": []})


func test_plan_cannot_drive_quantities_negative() -> void:
	var stock: Dictionary = {"iron": 1, "coal": 1, "timber": 0}
	var report: Dictionary = ProductionRecipes.plan(
		[{"recipe": "steel", "units": 5}], stock, 3, {}
	)
	assert_eq(report["runs"], {"steel": 1})
	assert_eq(stock["iron"], 0)
	assert_eq(stock["coal"], 0)


## A luxury is a trained hand's work: cigars need an apprentice, fur hats a
## journeyman, and a higher tier satisfies the gate (wiki: production-recipes
## § Worker-tier gates; DR-20261114-07).
func test_luxury_rows_need_a_trained_hand() -> void:
	assert_eq(ProductionRecipes.min_tier("cigars"), WorkerPool.Tier.APPRENTICE)
	assert_eq(ProductionRecipes.min_tier("furHats"), WorkerPool.Tier.JOURNEYMAN)
	assert_eq(ProductionRecipes.min_tier("lumber"), 0, "a plain row needs no hand")
	var peasants: WorkerPool = WorkerPool.make(4)
	assert_false(ProductionRecipes.tier_met("cigars", peasants))
	assert_false(ProductionRecipes.tier_met("furHats", peasants))
	assert_true(ProductionRecipes.tier_met("lumber", peasants))
	var apprentices: WorkerPool = WorkerPool.make(3, 1)
	assert_true(ProductionRecipes.tier_met("cigars", apprentices))
	assert_false(ProductionRecipes.tier_met("furHats", apprentices))
	var masters: WorkerPool = WorkerPool.make(3, 0, 0, 1)
	assert_true(ProductionRecipes.tier_met("cigars", masters), "a master runs an apprentice row")
	assert_true(ProductionRecipes.tier_met("furHats", masters), "a master runs a journeyman row")
	# A projection with no pool fails closed rather than opening every row.
	assert_false(ProductionRecipes.tier_met("cigars", null))
	assert_true(ProductionRecipes.tier_met("lumber", null))
	assert_false(ProductionRecipes.available_for("cigars", {}, peasants))
	assert_true(ProductionRecipes.available_for("cigars", {}, apprentices))
	assert_false(ProductionRecipes.available_ids_for({}, peasants).has("cigars"))
	assert_true(ProductionRecipes.available_ids_for({}, apprentices).has("cigars"))
	assert_false(ProductionRecipes.available_ids_for({}, apprentices).has("furHats"))


## A gated row neither runs nor offers a ceiling, and the phase leaves its
## inputs alone (wiki: production-recipes § Worker-tier gates; REQ-P2-03).
func test_a_gated_row_does_not_run_and_its_ceiling_is_zero() -> void:
	var stock: Dictionary = {"tobacco": 4, "furs": 4}
	var peasants: WorkerPool = WorkerPool.make(4)
	var report: Dictionary = ProductionRecipes.plan(
		[{"recipe": "cigars", "units": 2}, {"recipe": "furHats", "units": 2}],
		stock, 20, {}, {}, peasants
	)
	assert_eq(report["runs"], {})
	assert_eq(stock["tobacco"], 4)
	assert_eq(stock["furs"], 4)
	assert_eq(ProductionRecipes.allowance("cigars", stock, 20, [], peasants), 0)
	# A gated row set by the court claims no labour from the rows that do run.
	assert_eq(
		ProductionRecipes.allowance(
			"lumber", {"timber": 8}, 6, [{"recipe": "cigars", "units": 2}], peasants
		),
		3,
		"a gated row claims nothing from the rows that run"
	)
	var apprentices: WorkerPool = WorkerPool.make(3, 1)
	assert_eq(ProductionRecipes.allowance("cigars", stock, 20, [], apprentices), 2)
	assert_eq(ProductionRecipes.allowance("furHats", stock, 20, [], apprentices), 0)
	var allowed: Dictionary = ProductionRecipes.plan(
		[{"recipe": "cigars", "units": 2}], stock, 20, {}, {}, apprentices
	)
	assert_eq(allowed["runs"], {"cigars": 2})
	assert_eq(stock["tobacco"], 0)


## A batch already on the anvil was paid when it started: losing the hand that
## opened the row does not strand its output (DR-20261112-11, DR-20261114-07).
func test_a_carried_batch_lands_even_when_the_hand_is_gone() -> void:
	var stock: Dictionary = {}
	var wip: Dictionary = {"cigars": [{"units": 2, "turns_left": 1}]}
	var report: Dictionary = ProductionRecipes.plan([], stock, 0, {}, wip, WorkerPool.make(4))
	assert_eq(report["produced"], {"cigars": 1}, "a slow row gives up one unit a phase")
	assert_eq(stock["cigars"], 1)
	assert_eq(ProductionRecipes.in_flight(report["wip"], "cigars"), 1, "the rest waits")


## A one-turn row never waits: a carried batch of it (only a damaged or
## hand-edited save can hold one) lands whole (DR-20261113-02).
func test_a_carried_one_turn_batch_lands_whole() -> void:
	var stock: Dictionary = {}
	var wip: Dictionary = {"lumber": [{"units": 2, "turns_left": 1}]}
	var report: Dictionary = ProductionRecipes.plan([], stock, 0, {}, wip, null)
	assert_eq(report["produced"], {"lumber": 2})
	assert_eq(stock["lumber"], 2)


## A luxury is slow work: a cigar ages and a fur hat cures, so both rows take
## two turns while refined sugar — the apprentice's own ration — stays one
## (wiki: production-recipes § Recipe Catalog; DR-20261114-10).
func test_the_luxury_rows_take_two_turns() -> void:
	assert_eq(ProductionRecipes.turns("cigars"), 2)
	assert_eq(ProductionRecipes.turns("furHats"), 2)
	assert_eq(ProductionRecipes.turns("refinedSugar"), 1, "the apprentice's own ration is quick work")
	assert_eq(ProductionRecipes.turns("steel"), 2)
	assert_eq(ProductionRecipes.turns("lumber"), 1)


## A cigar batch pays its tobacco and labour when it starts, lands nothing that
## phase, then gives up one unit a phase (DR-20261113-02, DR-20261114-10).
func test_a_cigar_batch_lands_one_unit_a_phase() -> void:
	var stock: Dictionary = {"tobacco": 4}
	var apprentices: WorkerPool = WorkerPool.make(3, 1)
	var first: Dictionary = ProductionRecipes.plan(
		[{"recipe": "cigars", "units": 2}], stock, 20, {}, {}, apprentices
	)
	assert_eq(first["runs"], {"cigars": 2})
	assert_eq(first["produced"], {}, "a two-turn row lands nothing in the phase it starts")
	assert_eq(stock["tobacco"], 0, "the batch pays its inputs up front")
	assert_eq(ProductionRecipes.in_flight(first["wip"], "cigars"), 2)
	var second: Dictionary = ProductionRecipes.plan([], stock, 0, {}, first["wip"], apprentices)
	assert_eq(second["produced"], {"cigars": 1}, "one unit a phase")
	assert_eq(ProductionRecipes.in_flight(second["wip"], "cigars"), 1)
	var third: Dictionary = ProductionRecipes.plan([], stock, 0, {}, second["wip"], apprentices)
	assert_eq(third["produced"], {"cigars": 1})
	assert_eq(stock["cigars"], 2)
	assert_true(third["wip"].is_empty(), "the batch is spent")

func test_every_track_points_at_a_shipped_file() -> void:
	var ids: Array[String] = MusicPlaylist.ids()
	assert_gte(ids.size(), 6)
	for track_id: String in ids:
		var path: String = MusicPlaylist.path_for(track_id)
		assert_true(path.begins_with(MusicPlaylist.ROOT), track_id)
		assert_true(FileAccess.file_exists(path), path)
	assert_true(FileAccess.file_exists(MusicPlaylist.AMBIENCE))

func test_unknown_track_has_no_path() -> void:
	assert_true(MusicPlaylist.track("sea_shanty_404").is_empty())
	assert_eq(MusicPlaylist.path_for("sea_shanty_404"), "")

func test_eras_open_on_the_consort_and_close_on_the_minuet() -> void:
	assert_eq(MusicPlaylist.bed_id_for_year(1500), MusicPlaylist.AGE_OF_DISCOVERY)
	assert_eq(MusicPlaylist.bed_id_for_year(1549), MusicPlaylist.AGE_OF_DISCOVERY)
	assert_eq(MusicPlaylist.bed_id_for_year(1550), MusicPlaylist.SPANISH_MAIN)
	assert_eq(MusicPlaylist.bed_id_for_year(1699), MusicPlaylist.SPANISH_MAIN)
	assert_eq(MusicPlaylist.bed_id_for_year(1700), MusicPlaylist.GILDED_MINUET)
	assert_eq(MusicPlaylist.bed_id_for_year(1800), MusicPlaylist.GILDED_MINUET)

func test_years_before_the_start_fall_back_to_the_first_bed() -> void:
	assert_eq(MusicPlaylist.bed_id_for_year(1400), MusicPlaylist.AGE_OF_DISCOVERY)

func test_beds_follow_the_turn_calendar() -> void:
	assert_eq(MusicPlaylist.bed_id_for_year(TurnTime.year_for_turn(1)),
		MusicPlaylist.AGE_OF_DISCOVERY)
	assert_eq(MusicPlaylist.bed_for_turn(1)["id"], MusicPlaylist.AGE_OF_DISCOVERY)
	# 1500 + 2 years per turn: turn 30 is 1558, turn 101 is 1700.
	assert_eq(MusicPlaylist.bed_for_turn(30)["id"], MusicPlaylist.SPANISH_MAIN)
	assert_eq(MusicPlaylist.bed_for_turn(101)["id"], MusicPlaylist.GILDED_MINUET)

func test_beds_carry_period_metadata() -> void:
	for bed: Dictionary in MusicPlaylist.ERA_BEDS:
		assert_true(bed.has("title"), "title")
		assert_true(bed.has("era"), "era")
		assert_gt(int(bed["from_year"]), 0)

func test_only_stingers_are_one_shots() -> void:
	assert_true(MusicPlaylist.loops(MusicPlaylist.SPANISH_MAIN))
	assert_true(MusicPlaylist.loops(MusicPlaylist.BROADSIDES))
	assert_false(MusicPlaylist.loops(MusicPlaylist.VICTORY))
	assert_false(MusicPlaylist.loops(MusicPlaylist.DEFEAT))

func test_every_regiment_has_a_training_row() -> void:
	for type_id: String in RegimentCatalog.ids():
		assert_true(RegimentEconomy.TECH.has(type_id), "%s has a tech row" % type_id)
		var tech: String = RegimentEconomy.tech_for(type_id)
		if not tech.is_empty():
			assert_true(TechCatalog.known(tech), "%s maps to a real tech" % type_id)

func test_cavalry_inputs_match_the_published_table() -> void:
	var squires: Dictionary = RegimentEconomy.training_inputs("squires")
	assert_eq(int(squires["fabric"]), 1)
	assert_eq(int(squires["castIron"]), 1)
	assert_eq(int(squires["horses"]), 2)
	var knights: Dictionary = RegimentEconomy.training_inputs("knights")
	assert_eq(int(knights["castIron"]), 2)
	assert_eq(int(knights["horses"]), 2)
	var lancers: Dictionary = RegimentEconomy.training_inputs("lancers")
	assert_false(lancers.has("horses"), "lancers need no horses")

func test_start_regiments_are_buildable_and_later_ones_are_tech_gated() -> void:
	assert_true(RegimentEconomy.buildable("peasant_levies", {}))
	assert_true(RegimentEconomy.buildable("culverin", {}))
	assert_false(RegimentEconomy.buildable("lancers", {}))
	assert_true(RegimentEconomy.buildable("lancers", {"organised_regiments": true}))
	assert_false(RegimentEconomy.buildable("guards", {"needle_guns": true}))
	assert_true(RegimentEconomy.buildable("guards", {"elite_military_training": true}))

func test_blocked_reasons_follow_the_ledger() -> void:
	var stock: Dictionary = {"fabric": 5, "castIron": 5, "bronze": 5}
	assert_eq(
		RegimentEconomy.blocked_reason("pikemen", 0, stock, 5, {}),
		"Insufficient treasury"
	)
	assert_eq(
		RegimentEconomy.blocked_reason("pikemen", 99999, {}, 5, {}),
		"Insufficient materials"
	)
	assert_eq(
		RegimentEconomy.blocked_reason("pikemen", 99999, stock, 0, {}),
		"Insufficient workers"
	)
	assert_eq(
		RegimentEconomy.blocked_reason("lancers", 99999, stock, 5, {}),
		"Requires Organised Regiments"
	)
	assert_eq(RegimentEconomy.blocked_reason("pikemen", 99999, stock, 5, {}), "")

func test_cost_text_lists_cash_materials_and_the_worker() -> void:
	var text: String = RegimentEconomy.cost_text("peasant_levies")
	assert_true(text.contains("2,000 ducats"), text)
	assert_true(text.contains("Fabric"), text)
	assert_true(text.contains("1 worker"), text)

func test_recruit_deducts_the_ledger_and_joins_the_home_army() -> void:
	var economy := PlayerEconomy.starting()
	var home := ArmyState.muster(1, 0, 4, true, [] as Array[String], 1)
	var treasury: int = economy.treasury
	var fabric: int = economy.quantity("fabric")
	var peasants: int = economy.available_peasants()

	var result: Dictionary = ArmyTraining.recruit(economy, home, "peasant_levies", "unit_9")

	assert_true(bool(result["ok"]), String(result.get("reason", "")))
	assert_eq(home.count(), 1)
	assert_eq(home.type_of("unit_9"), "peasant_levies")
	assert_eq(economy.treasury, treasury - RegimentCatalog.treasury_cost("peasant_levies"))
	assert_eq(economy.quantity("fabric"), fabric - 1)
	assert_eq(economy.available_peasants(), peasants - 1)

func test_recruit_refuses_a_field_army() -> void:
	var economy := PlayerEconomy.starting()
	var field := ArmyState.muster(2, 0, 4, false, [] as Array[String], 1)
	var result: Dictionary = ArmyTraining.recruit(economy, field, "peasant_levies", "unit_9")
	assert_false(bool(result["ok"]))
	assert_eq(String(result["reason"]), "Regiments muster only in the Home Army.")
	assert_eq(field.count(), 0)

func test_rows_lead_with_what_the_crown_can_muster_today() -> void:
	var economy := PlayerEconomy.starting()
	var rows: Array[Dictionary] = ArmyTraining.rows(economy)
	assert_eq(rows.size(), RegimentCatalog.ROWS.size())
	assert_true(bool(rows[0]["ok"]), "first row is buildable")
	var seen_locked: bool = false
	for row: Dictionary in rows:
		if not bool(row["ok"]):
			seen_locked = true
		elif seen_locked:
			assert_true(false, "buildable rows must come before locked rows")
