extends GdToolsTest
## One boot for the map data: the model and region table, fog visibility, and the
## world/store halves of a save (wiki: the-map).

## Merged from test_map_model, test_map_region_table, test_visibility,
## test_save_world, test_save_store.
## One Godot boot (coverage instrumentation) per theme instead of one per file.
## Each test runs only its own suite's setup; teardown follows the setup.

const PLAYER: int = 0
const DIR: String = "user://test_save_store"

var _model: MapModel = null
var _visibility_model: MapModel = null
var _visibility: VisibilityModel = null

var _suite_setup: String = ""

func after_each() -> void:
	match _suite_setup:
		"save_store":
			_teardown_save_store()
	_suite_setup = ""

func _setup_map_model() -> void:
	_suite_setup = "map_model"
	_model = MapModel.new()
	_model.setup(4, 3)
	for x in 4:
		_model.terrain[_model.index_of(x, 0)] = MapModel.Terrain.PLAINS
	_model.terrain[_model.index_of(1, 1)] = MapModel.Terrain.HARDWOOD_FOREST
	_model.terrain[_model.index_of(2, 1)] = MapModel.Terrain.SHALLOW
	_model.province[_model.index_of(0, 0)] = 0
	_model.province[_model.index_of(1, 0)] = 0
	_model.province[_model.index_of(1, 1)] = 1
	_model.sea_zone[_model.index_of(2, 1)] = 0
	_model.sea_zone[_model.index_of(3, 1)] = 0
	var cadiz_tiles: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var coro_tiles: Array[Vector2i] = [Vector2i(1, 1)]
	var sea_tiles: Array[Vector2i] = [Vector2i(2, 1), Vector2i(3, 1)]
	_model.provinces = [
		ProvinceState.create(0, "Cádiz", cadiz_tiles, Vector2(1.0, 0.5), 2, 0, true),
		ProvinceState.create(1, "Coro", coro_tiles, Vector2(1.5, 1.5), 1, 1, false),
	]
	_model.sea_zones = [
		SeaZoneState.create(0, "Mar Caribe", sea_tiles, Vector2(3.0, 1.5), 2),
	]

func _setup_visibility() -> void:
	_suite_setup = "visibility"
	_visibility_model = _build_region()
	_visibility = VisibilityModel.new()
	_visibility.setup(_visibility_model, PLAYER)

func _setup_save_store() -> void:
	_suite_setup = "save_store"
	_clean_dir()

func _teardown_save_store() -> void:
	_clean_dir()

# --- test_map_model ---

func test_setup_sizes_and_clears_arrays() -> void:
	_setup_map_model()
	var fresh := MapModel.new()
	fresh.setup(7, 5)
	assert_eq(fresh.terrain.size(), 35)
	assert_eq(fresh.province.size(), 35)
	assert_eq(fresh.province[0], MapModel.NO_ID)
	assert_eq(fresh.province_count(), 0)

func test_capital_tile_follows_the_province_record() -> void:
	_setup_map_model()
	_model.provinces[0].capital_tile = Vector2i(0, 0)
	assert_eq(_model.capital_tile_of(0), Vector2i(0, 0))
	assert_eq(_model.capital_tile_of(1), CapitalChoice.NO_TILE)
	assert_eq(_model.capital_tile_of(-1), CapitalChoice.NO_TILE)

func test_land_and_sea_classification() -> void:
	_setup_map_model()
	assert_true(_model.is_land(0, 0))
	assert_false(_model.is_land(2, 1))
	assert_true(_model.is_sea(2, 1))
	assert_false(_model.is_land(-1, 0))
	assert_false(_model.is_land(0, 99))

func test_out_of_bounds_reads_as_ocean_and_no_id() -> void:
	_setup_map_model()
	assert_eq(_model.terrain_at(50, 50), MapModel.Terrain.OCEAN)
	assert_eq(_model.province_at(50, 50), MapModel.NO_ID)
	assert_eq(_model.sea_zone_at(-3, 0), MapModel.NO_ID)

func test_province_lookup_helpers() -> void:
	_setup_map_model()
	assert_eq(_model.province_at(1, 0), 0)
	assert_eq(_model.province_name(1), "Coro")
	assert_eq(_model.province_owner(1), 1)
	assert_eq(_model.province_owner(99), MapModel.NO_ID)
	assert_eq(_model.province_center(0), Vector2(1.0, 0.5))
	assert_eq(_model.province_tiles(99), [])

func test_coastal_tiles_touch_sea() -> void:
	_setup_map_model()
	assert_true(MapGeo.is_coastal_tile(_model, 1, 1))
	assert_false(MapGeo.is_coastal_tile(_model, 1, 0))
	assert_false(MapGeo.is_coastal_tile(_model, 2, 1))
	assert_eq(MapGeo.coastal_tiles(_model, 1), [Vector2i(1, 1)])

func test_map_border_is_not_a_coast() -> void:
	_setup_map_model()
	var border := MapModel.new()
	border.setup(3, 3)
	for index in border.terrain.size():
		border.terrain[index] = MapModel.Terrain.PLAINS
	assert_false(MapGeo.is_coastal_tile(border, 0, 0))
	assert_false(MapGeo.is_coastal_tile(border, 2, 2))

func test_tile_deeds_override_the_province_owner() -> void:
	_setup_map_model()
	var tile := Vector2i(1, 1)
	assert_eq(_model.owner_at(tile.x, tile.y), 1)
	assert_true(_model.purchase_tile(tile, 6))
	assert_eq(_model.owner_at(tile.x, tile.y), 6)
	assert_eq(_model.province_owner(1), 1, "the province itself does not change hands")
	assert_true(_model.is_purchased_tile(tile))
	assert_false(_model.purchase_tile(tile, 7), "one deed per tile")

func test_owned_tiles_follow_deeds_in_both_directions() -> void:
	_setup_map_model()
	var deed := Vector2i(1, 1)
	assert_true(_model.purchase_tile(deed, 6))
	var ownership: TileOwnership = _model.ownership
	assert_true(ownership.owned_tiles(_model, 6).has(deed), "buyer holds the enclave")
	assert_false(ownership.owned_tiles(_model, 1).has(deed), "seller no longer holds it")
	assert_true(
		ownership.owned_tiles(_model, 0).has(Vector2i(0, 0)),
		"ordinary province tiles remain"
	)

func test_tile_deeds_round_trip_through_plain_data() -> void:
	_setup_map_model()
	assert_true(_model.purchase_tile(Vector2i(1, 1), 6))
	var restored := TileOwnership.new()
	restored.apply_dict(_model.ownership.to_dict())
	assert_true(restored.is_purchased(_model.index_of(1, 1)))
	assert_eq(restored.owner_of(_model.index_of(1, 1), -1), 6)

func test_province_neighbors_are_cached_and_sorted() -> void:
	_setup_map_model()
	assert_eq(MapGeo.province_neighbors(_model, 0), [1])
	assert_true(_model.provinces[0].neighbors_cached)
	assert_eq(MapGeo.province_neighbors(_model, 99), [])

func test_sea_zone_neighbors() -> void:
	_setup_map_model()
	var second := MapModel.new()
	second.setup(3, 1)
	second.sea_zone[0] = 0
	second.sea_zone[1] = 0
	second.sea_zone[2] = 1
	var tiles_a: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var tiles_b: Array[Vector2i] = [Vector2i(2, 0)]
	second.sea_zones = [
		SeaZoneState.create(0, "A", tiles_a, Vector2.ZERO, 2),
		SeaZoneState.create(1, "B", tiles_b, Vector2.ZERO, 1),
	]
	assert_eq(MapGeo.sea_zone_neighbors(second, 0), [1])
	assert_eq(MapGeo.sea_zone_neighbors(second, 99), [])

func test_world_helpers() -> void:
	_setup_map_model()
	assert_eq(MapGeo.world_size(_model, 10.0), Vector2(40.0, 30.0))
	assert_eq(MapGeo.tile_center(0, 0, 10.0), Vector2(5.0, 5.0))
	assert_eq(MapGeo.tile_at_world(Vector2(15.0, 25.0), 10.0), Vector2i(1, 2))

func test_land_tile_count() -> void:
	_setup_map_model()
	assert_eq(MapGeo.land_tile_count(_model), 5)

func test_terrain_labels_cover_every_type() -> void:
	_setup_map_model()
	for terrain in MapModel.Terrain.values():
		assert_true(MapModel.TERRAIN_LABELS.has(terrain))

func test_palette_covers_every_terrain() -> void:
	_setup_map_model()
	for terrain in MapModel.Terrain.values():
		assert_true(terrain < Palette.TERRAIN_COLORS.size())
	assert_eq(Palette.faction_color(-1), Palette.INK_LINE)
	assert_eq(Palette.faction_color(99), Palette.INK_LINE)
	assert_eq(Palette.terrain_color(99), Color(0.5, 0.5, 0.5))

# --- test_map_region_table ---

func test_missing_region_falls_back_without_creating_a_row() -> void:
	var table := MapRegionTable.new()

	assert_false(table.has_region(3))
	assert_eq(table.value(3, []), [])
	assert_false(table.has_region(3))

func test_rows_are_addressed_by_region_and_clear_together() -> void:
	var table := MapRegionTable.new()
	var roster: Array[int] = [1, 2]
	table.set_region(5, roster)
	table.set_region(2, [9])

	assert_true(table.has_region(5))
	assert_eq(table.value(5, []), [1, 2])
	assert_eq(table.region_ids(), [2, 5])
	assert_eq(table.values().size(), 2)

	table.clear()
	assert_false(table.has_region(5))
	assert_eq(table.values(), [])

func test_snapshot_copies_rosters_so_readers_do_not_alias_live_state() -> void:
	var table := MapRegionTable.new()
	var roster: Array[int] = [1, 2]
	table.set_region(5, roster)
	table.set_region(2, 7)

	var snap: Dictionary = table.snapshot()

	assert_eq(snap.size(), 2)
	assert_eq(snap[5], [1, 2])
	assert_eq(snap[2], 7)
	var live: Array = table.value(5, [])
	live.append(9)
	assert_eq(snap[5], [1, 2], "the snapshot copied the roster")
	table.set_region(5, [4])
	assert_eq(snap[5], [1, 2], "the snapshot does not follow later writes")

func test_encode_walks_rosters_and_single_values() -> void:
	var table := MapRegionTable.new()
	table.set_region(0, [1, 2])
	table.set_region(1, 7)
	table.set_region(2, [])

	var encoded: Dictionary = table.encode(
		func(item: Variant) -> Dictionary: return {"n": int(item)}
	)

	assert_eq(encoded[0], [{"n": 1}, {"n": 2}])
	assert_eq(encoded[1], {"n": 7})
	assert_eq(encoded[2], [])

func test_encode_drops_null_entries_and_null_rows() -> void:
	var table := MapRegionTable.new()
	table.set_region(0, [1, null, 2])
	table.set_region(1, null)

	var encoded: Dictionary = table.encode(func(item: Variant) -> int: return int(item))

	assert_eq(encoded[0], [1, 2])
	assert_false(encoded.has(1))

func test_decode_replaces_rows_and_skips_null_results() -> void:
	var table := MapRegionTable.new()
	table.set_region(9, 99)

	table.decode({0: 4, 1: 5, 2: 6}, func(raw: Variant) -> Variant:
		return null if int(raw) == 5 else int(raw)
	)

	assert_eq(table.value(0, -1), 4)
	assert_eq(table.value(2, -1), 6)
	assert_false(table.has_region(1))
	assert_false(table.has_region(9))

# --- test_visibility ---

func test_old_world_starts_fogged_before_the_setup_pass() -> void:
	_setup_visibility()
	assert_eq(_visibility.level_at(0, 0), VisibilityModel.Level.FOGGED)
	assert_eq(_visibility.level_at(11, 5), VisibilityModel.Level.FOGGED)

func test_new_world_starts_unknown_until_a_reveal() -> void:
	_setup_visibility()
	var map: MapModel = _build_region()
	map.region_id = FactionCatalog.NEW_WORLD
	for province: ProvinceState in map.provinces:
		province.owner = FactionCatalog.tribe_ids()[0]
	var view := VisibilityModel.new()
	view.setup(map, PLAYER)
	var unknown: int = 0
	for index in view.levels.size():
		if view.level_at_index(index) == VisibilityModel.Level.UNKNOWN:
			unknown += 1
	assert_eq(unknown, view.levels.size(), "New World starts unknown, not fogged")
	view.apply_initial()
	unknown = 0
	for index in view.levels.size():
		if view.level_at_index(index) == VisibilityModel.Level.UNKNOWN:
			unknown += 1
	assert_eq(unknown, view.levels.size(), "no ownership means no setup reveal")

func test_new_world_setup_still_lights_land_the_player_owns() -> void:
	_setup_visibility()
	var map: MapModel = _build_region()
	map.region_id = FactionCatalog.NEW_WORLD
	for province: ProvinceState in map.provinces:
		province.owner = FactionCatalog.tribe_ids()[0]
	map.provinces[0].owner = PLAYER
	var view := VisibilityModel.new()
	view.setup(map, PLAYER)
	view.apply_initial()
	var tile: Vector2i = map.province_tiles(0)[0]
	assert_eq(view.level_at(tile.x, tile.y), VisibilityModel.Level.FULLY_VISIBLE)

func test_coast_links_follow_the_tile_grid() -> void:
	_setup_visibility()
	assert_eq(_visibility.province_sea_zones.get(0), [0])
	assert_eq(_visibility.province_sea_zones.get(3), [1, 2])
	assert_false(_visibility.sea_zone_provinces.has(3))
	assert_false(_visibility.sea_zone_provinces.has(4))

func test_setup_makes_own_provinces_visible_and_rival_land_fogged() -> void:
	_setup_visibility()
	_visibility.apply_initial()
	assert_eq(_visibility.level_at(0, 0), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(_visibility.level_at(6, 2), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(_visibility.level_at(2, 2), VisibilityModel.Level.FOGGED)
	assert_eq(_visibility.level_at(5, 0), VisibilityModel.Level.FOGGED)

func test_setup_reveals_sea_zones_next_to_owned_coast() -> void:
	_setup_visibility()
	_visibility.apply_initial()
	for tile: Vector2i in [
		Vector2i(0, 4), Vector2i(3, 5), Vector2i(4, 4), Vector2i(6, 5), Vector2i(7, 0)
	]:
		assert_eq(_visibility.level_at(tile.x, tile.y), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(_visibility.level_at(8, 0), VisibilityModel.Level.FOGGED)
	assert_eq(_visibility.level_at(11, 5), VisibilityModel.Level.FOGGED)

func test_ship_reveal_lights_water_and_the_strict_coastal_ring_only() -> void:
	_setup_visibility()
	_visibility.apply_initial()
	var changed: Array = _visibility.reveal_sea_zone(0)
	assert_eq(changed.size(), 2)
	assert_eq(_visibility.level_at(2, 3), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(_visibility.level_at(3, 3), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(_visibility.level_at(4, 3), VisibilityModel.Level.FOGGED)
	assert_eq(_visibility.level_at(2, 2), VisibilityModel.Level.FOGGED)

func test_ship_reveal_opens_open_water_without_touching_land() -> void:
	_setup_visibility()
	_visibility.apply_initial()
	var changed: Array = _visibility.reveal_sea_zone(3)
	assert_eq(changed.size(), 18)
	assert_eq(_visibility.level_at(8, 0), VisibilityModel.Level.FULLY_VISIBLE)

func test_end_of_turn_decays_only_foreign_fully_visible_land() -> void:
	_setup_visibility()
	_visibility.apply_initial()
	_visibility.reveal_sea_zone(0)
	_visibility.end_of_turn([])
	assert_eq(_visibility.level_at(2, 3), VisibilityModel.Level.FOGGED)
	assert_eq(_visibility.level_at(0, 0), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(_visibility.level_at(6, 2), VisibilityModel.Level.FULLY_VISIBLE)

func test_end_of_turn_never_raises_unknown_tiles() -> void:
	_setup_visibility()
	var index: int = _visibility_model.index_of(8, 0)
	_visibility.lower_to(index, VisibilityModel.Level.UNKNOWN)
	_visibility.end_of_turn([])
	assert_eq(_visibility.level_at(8, 0), VisibilityModel.Level.UNKNOWN)

func test_end_of_turn_fogs_distant_sea_without_a_fleet() -> void:
	_setup_visibility()
	_visibility.apply_initial()
	_visibility.reveal_sea_zone(3)
	_visibility.end_of_turn([])
	assert_eq(_visibility.level_at(8, 0), VisibilityModel.Level.FOGGED)

func test_end_of_turn_keeps_a_zone_where_the_fleet_rides() -> void:
	_setup_visibility()
	_visibility.apply_initial()
	_visibility.reveal_sea_zone(3)
	_visibility.end_of_turn([3])
	assert_eq(_visibility.level_at(8, 0), VisibilityModel.Level.FULLY_VISIBLE)

func test_owning_a_coast_reveals_its_zone_at_end_of_turn() -> void:
	_setup_visibility()
	_visibility_model.provinces[1].owner = PLAYER
	_visibility.end_of_turn([])
	assert_eq(_visibility.level_at(2, 2), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(_visibility.level_at(3, 3), VisibilityModel.Level.FULLY_VISIBLE)

func test_losing_the_only_coast_fogs_its_zone() -> void:
	_setup_visibility()
	_visibility.apply_initial()
	_visibility_model.provinces[3].owner = 2
	_visibility.end_of_turn([])
	assert_eq(_visibility.level_at(4, 4), VisibilityModel.Level.FOGGED)
	assert_eq(_visibility.level_at(7, 0), VisibilityModel.Level.FOGGED)
	assert_eq(_visibility.level_at(0, 4), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(_visibility.level_at(5, 2), VisibilityModel.Level.FOGGED)

func test_a_purchased_tile_stays_visible_in_a_rival_province() -> void:
	_setup_visibility()
	_visibility.apply_initial()
	var tile := Vector2i(2, 2)
	assert_true(_visibility_model.purchase_tile(tile, PLAYER))
	_visibility.end_of_turn([])
	assert_eq(_visibility.level_at(2, 2), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(_visibility.level_at(3, 2), VisibilityModel.Level.FOGGED)

func test_each_player_has_an_independent_map() -> void:
	_setup_visibility()
	var rival := VisibilityModel.new()
	rival.setup(_visibility_model, 1)
	rival.apply_initial()
	_visibility.apply_initial()
	_visibility.reveal_sea_zone(0)
	assert_eq(rival.level_at(0, 0), VisibilityModel.Level.FOGGED)
	assert_eq(rival.level_at(2, 3), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(_visibility.level_at(2, 3), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(_visibility.level_at(2, 2), VisibilityModel.Level.FOGGED)

func test_knowledge_levels_are_ordered() -> void:
	_setup_visibility()
	var index: int = _visibility_model.index_of(2, 2)
	assert_false(_visibility.raise_to(index, VisibilityModel.Level.FOGGED))
	assert_true(_visibility.raise_to(index, VisibilityModel.Level.FULLY_VISIBLE))
	assert_false(_visibility.raise_to(index, VisibilityModel.Level.FOGGED))
	assert_false(_visibility.lower_to(index, VisibilityModel.Level.FULLY_VISIBLE))
	assert_true(_visibility.lower_to(index, VisibilityModel.Level.FOGGED))
	assert_false(_visibility.lower_to(index, VisibilityModel.Level.FOGGED))

func test_reveal_province_opens_every_tile() -> void:
	_setup_visibility()
	var changed: Array = _visibility.reveal_province(1)
	assert_true(changed.size() > 0)
	assert_true(_visibility.is_province_fully_visible(1))

func test_civilian_presence_holds_a_foreign_province() -> void:
	_setup_visibility()
	_visibility.reveal_province(1)
	_visibility.end_of_turn([], [1])
	assert_true(_visibility.is_province_fully_visible(1))
	_visibility.end_of_turn([])
	assert_false(_visibility.is_province_fully_visible(1))

func test_presence_never_surveys_unknown_terrain() -> void:
	_setup_visibility()
	for tile: Vector2i in _visibility_model.province_tiles(1):
		var index: int = _visibility_model.index_of(tile.x, tile.y)
		_visibility.levels[index] = VisibilityModel.Level.UNKNOWN
	var held: Array = _visibility.hold_explored_province(1)
	var unknown_left: int = 0
	for tile: Vector2i in _visibility_model.province_tiles(1):
		var index: int = _visibility_model.index_of(tile.x, tile.y)
		if _visibility.level_at_index(index) == VisibilityModel.Level.UNKNOWN:
			unknown_left += 1
	assert_eq(held, [], "presence holds nothing unknown")
	assert_eq(unknown_left, 12, "every tile stays unknown")

func test_presence_holds_only_the_fogged_tile() -> void:
	_setup_visibility()
	var tiles: Array[Vector2i] = _visibility_model.province_tiles(1)
	var charted: Vector2i = tiles[0]
	var charted_index: int = _visibility_model.index_of(charted.x, charted.y)
	_visibility.levels[charted_index] = VisibilityModel.Level.UNKNOWN
	var opened: int = _visibility.hold_explored_province(1).size()
	var charted_level: int = _visibility.level_at_index(charted_index)
	var still_unknown: int = 0
	for tile: Vector2i in tiles:
		if _visibility.level_at(tile.x, tile.y) == VisibilityModel.Level.UNKNOWN:
			still_unknown += 1
	assert_eq(opened, 11, "every fogged tile is held")
	assert_eq(charted_level, VisibilityModel.Level.UNKNOWN, "unknown stays unknown")
	assert_eq(still_unknown, 1, "only the cleared tile stays unknown")

func test_a_spy_holds_the_province_it_shadows() -> void:
	_setup_visibility()
	# Presence holds, presence never reveals (DR-20261109-04): a spy posted in a
	# rival province keeps its charted tiles in view for its own crown.
	var units: Array[CivilianState] = []
	units.append(CivilianState.create(1, PLAYER, "spy", Vector2i(2, 2)))
	units.append(CivilianState.create(2, 1, "explorer", Vector2i(2, 2)))
	assert_eq(CivilianMovement.held_provinces(_visibility_model, units, PLAYER), [1], "a spy holds")
	assert_eq(CivilianMovement.held_provinces(_visibility_model, units, 1), [1], "own explorer holds")
	assert_eq(
		CivilianMovement.held_provinces(_visibility_model, units, 2), [],
		"another crown reads nothing from these units"
	)

func test_a_spy_never_promotes_unknown_ground() -> void:
	_setup_visibility()
	# A New World province starts unknown; a spy posted there holds it but the
	# tiles stay dark until an Explorer surveys them (DR-20261109-04).
	var map: MapModel = _build_region()
	map.region_id = FactionCatalog.NEW_WORLD
	var view := VisibilityModel.new()
	view.setup(map, PLAYER)
	var units: Array[CivilianState] = [CivilianState.create(1, PLAYER, "spy", Vector2i(2, 2))]
	assert_eq(CivilianMovement.held_provinces(map, units, PLAYER), [1], "posted")
	assert_eq(view.hold_explored_province(1), [], "unknown ground never opens")
	assert_eq(
		view.province_visibility(1), VisibilityModel.Level.UNKNOWN,
		"the province stays unknown"
	)

func test_province_visibility_uses_the_highest_tile() -> void:
	_setup_visibility()
	_visibility.apply_initial()
	assert_eq(_visibility.province_visibility(0), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(_visibility.province_visibility(1), VisibilityModel.Level.FOGGED)
	assert_true(_visibility.is_province_known(1))
	assert_false(_visibility.is_province_fully_visible(1))
	_visibility.reveal_sea_zone(0)
	assert_false(_visibility.is_province_fully_visible(1))
	for tile: Vector2i in _visibility_model.province_tiles(1):
		_visibility.raise_to(_visibility_model.index_of(tile.x, tile.y), VisibilityModel.Level.FULLY_VISIBLE)
	assert_true(_visibility.is_province_fully_visible(1))

func test_out_of_range_reads_are_safe() -> void:
	_setup_visibility()
	assert_eq(_visibility.level_at(-1, 0), VisibilityModel.Level.UNKNOWN)
	assert_eq(_visibility.level_at_index(9999), VisibilityModel.Level.UNKNOWN)
	assert_false(_visibility.raise_to(-1, VisibilityModel.Level.FULLY_VISIBLE))
	assert_false(_visibility.lower_to(9999, VisibilityModel.Level.UNKNOWN))
	assert_eq(_visibility.reveal_sea_zone(99), [])
	assert_eq(_visibility.province_visibility(99), VisibilityModel.Level.UNKNOWN)
	assert_false(_visibility.is_province_fully_visible(99))
	assert_false(_visibility.owns_coast(99))

func test_unassigned_tiles_are_ignored() -> void:
	_setup_visibility()
	var map := MapModel.new()
	map.setup(4, 2)
	for x in 4:
		map.terrain[map.index_of(x, 0)] = MapModel.Terrain.PLAINS
	for x in range(1, 4):
		map.province[map.index_of(x, 0)] = 0
	var lonely_tiles: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	map.provinces.append(
		ProvinceState.create(0, "Lonely", lonely_tiles, Vector2.ZERO, 3, PLAYER)
	)
	for x in 2:
		map.sea_zone[map.index_of(x, 1)] = 0
	var bay_tiles: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 1)]
	map.sea_zones.append(SeaZoneState.create(0, "Bay", bay_tiles, Vector2.ZERO, 2))
	var orphan_tiles: Array[Vector2i] = []
	map.sea_zones.append(SeaZoneState.create(1, "Orphan", orphan_tiles, Vector2.ZERO, 0))

	var visibility := VisibilityModel.new()
	visibility.setup(map, PLAYER)
	visibility.apply_initial()
	assert_eq(visibility.province_sea_zones.get(0), [0])
	assert_eq(visibility.level_at(0, 1), VisibilityModel.Level.FULLY_VISIBLE)
	visibility.end_of_turn([])
	assert_eq(visibility.level_at(0, 0), VisibilityModel.Level.FOGGED)

## One region as a world with a rival chart per Great Power. `human_views` is
## the table the session's own grid lives in, so the human court routes there.
func _charts_for(model: MapModel, human_views: Dictionary = {}) -> CourtCharts:
	var world := WorldMap.new()
	world.add_region(model)
	var charts := CourtCharts.new()
	charts.setup(world, PLAYER, human_views)
	return charts

func test_every_rival_carries_its_own_chart() -> void:
	_setup_visibility()
	var charts: CourtCharts = _charts_for(_visibility_model)
	var rival: int = FactionCatalog.great_power_ids()[1]
	var other: int = FactionCatalog.great_power_ids()[2]
	var view: VisibilityModel = charts.model_for(rival, 0)
	assert_true(view != null, "a rival Great Power has a chart")
	assert_eq(view.player_id, rival)
	assert_true(view != charts.model_for(other, 0), "each court reads its own grid")

func test_a_rival_chart_follows_the_setup_reveals() -> void:
	_setup_visibility()
	var charts: CourtCharts = _charts_for(_visibility_model)
	var rival: int = FactionCatalog.great_power_ids()[1]
	var view: VisibilityModel = charts.model_for(rival, 0)
	assert_eq(
		view.province_visibility(1), VisibilityModel.Level.FULLY_VISIBLE,
		"its own province is fully visible"
	)
	assert_eq(
		view.province_visibility(0), VisibilityModel.Level.FOGGED,
		"a rival coast is fogged, not charted"
	)
	assert_eq(
		view.province_visibility(2), VisibilityModel.Level.FOGGED,
		"another court's land is fogged too"
	)
	assert_true(charts.knows_province(rival, 0, 0))
	assert_true(charts.knows_zone(rival, 0, 0), "its coastal zone is charted")

func test_the_human_grid_is_shared_not_copied() -> void:
	_setup_visibility()
	var human := VisibilityModel.new()
	human.setup(_visibility_model, PLAYER)
	var human_views: Dictionary = {0: human}
	var charts: CourtCharts = _charts_for(_visibility_model, human_views)
	assert_eq(charts.model_for(PLAYER, 0), human, "the session owns the human grid")
	charts.reveal_province(PLAYER, 0, 2)
	assert_eq(
		human.province_visibility(2), VisibilityModel.Level.FULLY_VISIBLE,
		"a human reveal lands on the shared grid"
	)
	assert_eq(charts.regions_of(PLAYER), human_views)

func test_an_uncharted_new_world_is_unknown_to_every_rival() -> void:
	_setup_visibility()
	var map: MapModel = _build_region()
	map.region_id = FactionCatalog.NEW_WORLD
	for province: ProvinceState in map.provinces:
		province.owner = FactionCatalog.tribe_ids()[0]
	var charts: CourtCharts = _charts_for(map)
	var rival: int = FactionCatalog.great_power_ids()[1]
	assert_true(charts.known_zones(rival, 0).is_empty(), "no water is charted")
	assert_false(charts.knows_province(rival, 0, 0))
	assert_true(
		charts.charted_tiles(rival, 0, [Vector2i(1, 3)]).is_empty(),
		"no land is charted"
	)
	charts.reveal_sea_zone(rival, 0, 0)
	assert_true(charts.knows_zone(rival, 0, 0), "the entered zone is charted")
	var zones: Array[int] = [0]
	assert_eq(charts.known_zones(rival, 0), zones)
	var expected: Array[Vector2i] = [Vector2i(1, 3)]
	assert_eq(
		charts.charted_tiles(rival, 0, [Vector2i(1, 3), Vector2i(1, 0)]),
		expected,
		"the coastal ring is charted, the province interior is not"
	)

func test_a_rival_explore_completion_reveals_only_its_own_chart() -> void:
	_setup_visibility()
	var map: MapModel = _build_region()
	map.region_id = FactionCatalog.NEW_WORLD
	for province: ProvinceState in map.provinces:
		province.owner = FactionCatalog.tribe_ids()[0]
	var human := VisibilityModel.new()
	human.setup(map, PLAYER)
	var charts: CourtCharts = _charts_for(map, {0: human})
	var rival: int = FactionCatalog.great_power_ids()[1]
	var beach: Vector2i = map.province_tiles(2)[0]
	charts.reveal_landing(rival, 0, beach)
	var unit: CivilianState = CivilianState.create(1, rival, "explorer", beach)
	unit.start_work("explore", beach, 1)
	var crew: Array[CivilianState] = [unit]
	var reports: Array[Dictionary] = CivilianWork.resolve_turn(
		map, crew, LandWorks.new(), charts.model_for(rival, 0)
	)
	assert_true(bool(reports[0]["completed"]))
	assert_eq(
		charts.model_for(rival, 0).province_visibility(2),
		VisibilityModel.Level.FULLY_VISIBLE,
		"the explorer charts the province for its own court"
	)
	assert_eq(
		human.province_visibility(2), VisibilityModel.Level.UNKNOWN,
		"the player's fog is untouched"
	)

func test_rival_fog_decays_at_the_end_of_the_turn() -> void:
	_setup_visibility()
	var world := WorldMap.new()
	world.add_region(_build_region())
	var play := PlaySession.new()
	play.world = world
	play.model = world.region(0)
	play.player_faction = PLAYER
	play.ship_layer = ShipLayer.new()
	play.ship_layer.model = play.model
	play.ship_layer.world = world
	play.civilian_layer = CivilianLayer.new()
	play.civilian_layer.model = play.model
	MapPlayCourtFog.build(play)
	var rival: int = FactionCatalog.great_power_ids()[1]
	play.court_charts.reveal_sea_zone(rival, 0, 0)
	var view: VisibilityModel = play.court_charts.model_for(rival, 0)
	assert_eq(view.level_at(0, 3), VisibilityModel.Level.FULLY_VISIBLE)
	MapPlayCourtFog.resolve(play)
	assert_eq(
		view.level_at(0, 3), VisibilityModel.Level.FOGGED,
		"a foreign coast fogs once the squadron is gone"
	)
	assert_eq(
		view.province_visibility(1), VisibilityModel.Level.FULLY_VISIBLE,
		"the court's own land never decays"
	)
	play.ship_layer.free()
	play.civilian_layer.free()

func test_no_difficulty_level_widens_a_rival_chart() -> void:
	_setup_visibility()
	var baseline: PackedByteArray = _court_grid(Difficulty.DEFAULT)
	for level: String in Difficulty.IDS:
		assert_eq(_court_grid(level), baseline, "%s charts the same fog" % level)

func _court_grid(difficulty_id: String) -> PackedByteArray:
	var world := WorldMap.new()
	world.add_region(_build_region())
	var play := PlaySession.new()
	play.world = world
	play.model = world.region(0)
	play.player_faction = PLAYER
	play.difficulty = Difficulty.normalize(difficulty_id)
	MapPlayCourtFog.build(play)
	var rival: int = FactionCatalog.great_power_ids()[1]
	return play.court_charts.model_for(rival, 0).levels

func test_a_rival_chart_round_trips_through_the_save() -> void:
	_setup_visibility()
	var map: MapModel = _build_region()
	var world := WorldMap.new()
	world.add_region(map)
	var charts := CourtCharts.new()
	charts.setup(world, PLAYER, {})
	var rival: int = FactionCatalog.great_power_ids()[1]
	charts.reveal_sea_zone(rival, 0, 0)
	var restored := CourtCharts.new()
	assert_true(restored.apply_dict(world, charts.to_dict()))
	assert_eq(
		restored.model_for(rival, 0).levels, charts.model_for(rival, 0).levels,
		"a load restores the chart the rival earned"
	)
	assert_false(restored.apply_dict(world, 7), "a malformed payload is refused")
	assert_false(restored.apply_dict(world, {}), "a save without charts keeps the grid")
	assert_true(restored.courts.is_empty() == false, "the good grid survives")

func _build_region() -> MapModel:
	var map := MapModel.new()
	map.setup(12, 6)
	for y in 4:
		for x in 7:
			map.terrain[map.index_of(x, y)] = MapModel.Terrain.PLAINS
	_claim(map, 0, 0, 1, 0, 3, PLAYER)
	_claim(map, 1, 2, 4, 0, 3, 1)
	_claim(map, 2, 5, 6, 0, 1, 2)
	_claim(map, 3, 5, 6, 2, 3, PLAYER)
	_zone(map, 0, 0, 3, 4, 5)
	_zone(map, 1, 4, 6, 4, 5)
	_zone(map, 2, 7, 7, 0, 5)
	_zone(map, 3, 8, 10, 0, 5)
	_zone(map, 4, 11, 11, 0, 5)
	return map

func _claim(
	map: MapModel, id: int, x_min: int, x_max: int, y_min: int, y_max: int, owner: int
) -> void:
	var tiles: Array[Vector2i] = []
	for y in range(y_min, y_max + 1):
		for x in range(x_min, x_max + 1):
			map.province[map.index_of(x, y)] = id
			tiles.append(Vector2i(x, y))
	map.provinces.append(
		ProvinceState.create(id, "Province %d" % id, tiles, Vector2.ZERO, tiles.size(), owner)
	)

func _zone(
	map: MapModel, id: int, x_min: int, x_max: int, y_min: int, y_max: int
) -> void:
	var tiles: Array[Vector2i] = []
	for y in range(y_min, y_max + 1):
		for x in range(x_min, x_max + 1):
			map.sea_zone[map.index_of(x, y)] = id
			tiles.append(Vector2i(x, y))
	map.sea_zones.append(
		SeaZoneState.create(id, "Sea %d" % id, tiles, Vector2.ZERO, tiles.size())
	)

# --- test_save_world ---

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

# --- test_save_store ---

func test_slots_report_existing_saves_and_empty_slots() -> void:
	_setup_save_store()
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
	_setup_save_store()
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
	_setup_save_store()
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
	_setup_save_store()
	assert_true(SaveStore.save_slot(1, _data(2), DIR))
	assert_true(SaveStore.save_slot(1, _data(11), DIR), "slot overwrites")
	assert_eq(int(SaveStore.slots(DIR)[0]["turn"]), 11, "newer save wins")
	assert_true(SaveStore.delete_slot(1, DIR), "slot deletes")
	assert_false(SaveStore.has_slot(1, DIR), "deleted slot is gone")
	assert_false(SaveStore.delete_slot(1, DIR), "deleting twice is a no-op")

func test_slot_numbers_are_clamped_and_bad_data_is_refused() -> void:
	_setup_save_store()
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
