extends GdToolsTest
## Fog of war rules (wiki: fog-and-exploration) on a hand-built region:
## P0 player coast, P1 rival coast, P2 rival inland, P3 player coast.
## Sea zones: 0/1 coastal, 2 rival coast, 3/4 open water.

const PLAYER: int = 0

var _model: MapModel = null
var _visibility: VisibilityModel = null


func before_each() -> void:
	_model = _build_region()
	_visibility = VisibilityModel.new()
	_visibility.setup(_model, PLAYER)


func test_old_world_starts_fogged_before_the_setup_pass() -> void:
	assert_eq(_visibility.level_at(0, 0), VisibilityModel.Level.FOGGED)
	assert_eq(_visibility.level_at(11, 5), VisibilityModel.Level.FOGGED)


func test_new_world_starts_unknown_until_a_reveal() -> void:
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
	assert_eq(_visibility.province_sea_zones.get(0), [0])
	assert_eq(_visibility.province_sea_zones.get(3), [1, 2])
	assert_false(_visibility.sea_zone_provinces.has(3))
	assert_false(_visibility.sea_zone_provinces.has(4))


func test_setup_makes_own_provinces_visible_and_rival_land_fogged() -> void:
	_visibility.apply_initial()
	assert_eq(_visibility.level_at(0, 0), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(_visibility.level_at(6, 2), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(_visibility.level_at(2, 2), VisibilityModel.Level.FOGGED)
	assert_eq(_visibility.level_at(5, 0), VisibilityModel.Level.FOGGED)


func test_setup_reveals_sea_zones_next_to_owned_coast() -> void:
	_visibility.apply_initial()
	for tile: Vector2i in [
		Vector2i(0, 4), Vector2i(3, 5), Vector2i(4, 4), Vector2i(6, 5), Vector2i(7, 0)
	]:
		assert_eq(_visibility.level_at(tile.x, tile.y), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(_visibility.level_at(8, 0), VisibilityModel.Level.FOGGED)
	assert_eq(_visibility.level_at(11, 5), VisibilityModel.Level.FOGGED)


func test_ship_reveal_lights_water_and_the_strict_coastal_ring_only() -> void:
	_visibility.apply_initial()
	var changed: Array = _visibility.reveal_sea_zone(0)
	assert_eq(changed.size(), 2)
	assert_eq(_visibility.level_at(2, 3), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(_visibility.level_at(3, 3), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(_visibility.level_at(4, 3), VisibilityModel.Level.FOGGED)
	assert_eq(_visibility.level_at(2, 2), VisibilityModel.Level.FOGGED)


func test_ship_reveal_opens_open_water_without_touching_land() -> void:
	_visibility.apply_initial()
	var changed: Array = _visibility.reveal_sea_zone(3)
	assert_eq(changed.size(), 18)
	assert_eq(_visibility.level_at(8, 0), VisibilityModel.Level.FULLY_VISIBLE)


func test_end_of_turn_decays_only_foreign_fully_visible_land() -> void:
	_visibility.apply_initial()
	_visibility.reveal_sea_zone(0)
	_visibility.end_of_turn([])
	assert_eq(_visibility.level_at(2, 3), VisibilityModel.Level.FOGGED)
	assert_eq(_visibility.level_at(0, 0), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(_visibility.level_at(6, 2), VisibilityModel.Level.FULLY_VISIBLE)


func test_end_of_turn_never_raises_unknown_tiles() -> void:
	var index: int = _model.index_of(8, 0)
	_visibility.lower_to(index, VisibilityModel.Level.UNKNOWN)
	_visibility.end_of_turn([])
	assert_eq(_visibility.level_at(8, 0), VisibilityModel.Level.UNKNOWN)


func test_end_of_turn_fogs_distant_sea_without_a_fleet() -> void:
	_visibility.apply_initial()
	_visibility.reveal_sea_zone(3)
	_visibility.end_of_turn([])
	assert_eq(_visibility.level_at(8, 0), VisibilityModel.Level.FOGGED)


func test_end_of_turn_keeps_a_zone_where_the_fleet_rides() -> void:
	_visibility.apply_initial()
	_visibility.reveal_sea_zone(3)
	_visibility.end_of_turn([3])
	assert_eq(_visibility.level_at(8, 0), VisibilityModel.Level.FULLY_VISIBLE)


func test_owning_a_coast_reveals_its_zone_at_end_of_turn() -> void:
	_model.provinces[1].owner = PLAYER
	_visibility.end_of_turn([])
	assert_eq(_visibility.level_at(2, 2), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(_visibility.level_at(3, 3), VisibilityModel.Level.FULLY_VISIBLE)


func test_losing_the_only_coast_fogs_its_zone() -> void:
	_visibility.apply_initial()
	_model.provinces[3].owner = 2
	_visibility.end_of_turn([])
	assert_eq(_visibility.level_at(4, 4), VisibilityModel.Level.FOGGED)
	assert_eq(_visibility.level_at(7, 0), VisibilityModel.Level.FOGGED)
	assert_eq(_visibility.level_at(0, 4), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(_visibility.level_at(5, 2), VisibilityModel.Level.FOGGED)


func test_a_purchased_tile_stays_visible_in_a_rival_province() -> void:
	_visibility.apply_initial()
	var tile := Vector2i(2, 2)
	assert_true(_model.purchase_tile(tile, PLAYER))
	_visibility.end_of_turn([])
	assert_eq(_visibility.level_at(2, 2), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(_visibility.level_at(3, 2), VisibilityModel.Level.FOGGED)


func test_each_player_has_an_independent_map() -> void:
	var rival := VisibilityModel.new()
	rival.setup(_model, 1)
	rival.apply_initial()
	_visibility.apply_initial()
	_visibility.reveal_sea_zone(0)
	assert_eq(rival.level_at(0, 0), VisibilityModel.Level.FOGGED)
	assert_eq(rival.level_at(2, 3), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(_visibility.level_at(2, 3), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(_visibility.level_at(2, 2), VisibilityModel.Level.FOGGED)


func test_knowledge_levels_are_ordered() -> void:
	var index: int = _model.index_of(2, 2)
	assert_false(_visibility.raise_to(index, VisibilityModel.Level.FOGGED))
	assert_true(_visibility.raise_to(index, VisibilityModel.Level.FULLY_VISIBLE))
	assert_false(_visibility.raise_to(index, VisibilityModel.Level.FOGGED))
	assert_false(_visibility.lower_to(index, VisibilityModel.Level.FULLY_VISIBLE))
	assert_true(_visibility.lower_to(index, VisibilityModel.Level.FOGGED))
	assert_false(_visibility.lower_to(index, VisibilityModel.Level.FOGGED))


func test_reveal_province_opens_every_tile() -> void:
	var changed: Array = _visibility.reveal_province(1)
	assert_true(changed.size() > 0)
	assert_true(_visibility.is_province_fully_visible(1))


func test_civilian_presence_holds_a_foreign_province() -> void:
	_visibility.reveal_province(1)
	_visibility.end_of_turn([], [1])
	assert_true(_visibility.is_province_fully_visible(1))
	_visibility.end_of_turn([])
	assert_false(_visibility.is_province_fully_visible(1))


func test_presence_never_surveys_unknown_terrain() -> void:
	for tile: Vector2i in _model.province_tiles(1):
		var index: int = _model.index_of(tile.x, tile.y)
		_visibility.levels[index] = VisibilityModel.Level.UNKNOWN
	var held: Array = _visibility.hold_explored_province(1)
	var unknown_left: int = 0
	for tile: Vector2i in _model.province_tiles(1):
		var index: int = _model.index_of(tile.x, tile.y)
		if _visibility.level_at_index(index) == VisibilityModel.Level.UNKNOWN:
			unknown_left += 1
	assert_eq(held, [], "presence holds nothing unknown")
	assert_eq(unknown_left, 12, "every tile stays unknown")


func test_presence_holds_only_the_fogged_tile() -> void:
	var tiles: Array[Vector2i] = _model.province_tiles(1)
	var charted: Vector2i = tiles[0]
	var charted_index: int = _model.index_of(charted.x, charted.y)
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
	# Presence holds, presence never reveals (DR-20261109-04): a spy posted in a
	# rival province keeps its charted tiles in view for its own crown.
	var units: Array[CivilianState] = []
	units.append(CivilianState.create(1, PLAYER, "spy", Vector2i(2, 2)))
	units.append(CivilianState.create(2, 1, "explorer", Vector2i(2, 2)))
	assert_eq(CivilianMovement.held_provinces(_model, units, PLAYER), [1], "a spy holds")
	assert_eq(CivilianMovement.held_provinces(_model, units, 1), [1], "own explorer holds")
	assert_eq(
		CivilianMovement.held_provinces(_model, units, 2), [],
		"another crown reads nothing from these units"
	)


func test_a_spy_never_promotes_unknown_ground() -> void:
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
	_visibility.apply_initial()
	assert_eq(_visibility.province_visibility(0), VisibilityModel.Level.FULLY_VISIBLE)
	assert_eq(_visibility.province_visibility(1), VisibilityModel.Level.FOGGED)
	assert_true(_visibility.is_province_known(1))
	assert_false(_visibility.is_province_fully_visible(1))
	_visibility.reveal_sea_zone(0)
	assert_false(_visibility.is_province_fully_visible(1))
	for tile: Vector2i in _model.province_tiles(1):
		_visibility.raise_to(_model.index_of(tile.x, tile.y), VisibilityModel.Level.FULLY_VISIBLE)
	assert_true(_visibility.is_province_fully_visible(1))


func test_out_of_range_reads_are_safe() -> void:
	assert_eq(_visibility.level_at(-1, 0), VisibilityModel.Level.UNKNOWN)
	assert_eq(_visibility.level_at_index(9999), VisibilityModel.Level.UNKNOWN)
	assert_false(_visibility.raise_to(-1, VisibilityModel.Level.FULLY_VISIBLE))
	assert_false(_visibility.lower_to(9999, VisibilityModel.Level.UNKNOWN))
	assert_eq(_visibility.reveal_sea_zone(99), [])
	assert_eq(_visibility.province_visibility(99), VisibilityModel.Level.UNKNOWN)
	assert_false(_visibility.is_province_fully_visible(99))
	assert_false(_visibility.owns_coast(99))


func test_unassigned_tiles_are_ignored() -> void:
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


# --- rival courts (CourtCharts; DR-20261110-21) ------------------------------


## One region as a world with a rival chart per Great Power. `human_views` is
## the table the session's own grid lives in, so the human court routes there.
func _charts_for(model: MapModel, human_views: Dictionary = {}) -> CourtCharts:
	var world := WorldMap.new()
	world.add_region(model)
	var charts := CourtCharts.new()
	charts.setup(world, PLAYER, human_views)
	return charts


func test_every_rival_carries_its_own_chart() -> void:
	var charts: CourtCharts = _charts_for(_model)
	var rival: int = FactionCatalog.great_power_ids()[1]
	var other: int = FactionCatalog.great_power_ids()[2]
	var view: VisibilityModel = charts.model_for(rival, 0)
	assert_true(view != null, "a rival Great Power has a chart")
	assert_eq(view.player_id, rival)
	assert_true(view != charts.model_for(other, 0), "each court reads its own grid")


func test_a_rival_chart_follows_the_setup_reveals() -> void:
	var charts: CourtCharts = _charts_for(_model)
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
	var human := VisibilityModel.new()
	human.setup(_model, PLAYER)
	var human_views: Dictionary = {0: human}
	var charts: CourtCharts = _charts_for(_model, human_views)
	assert_eq(charts.model_for(PLAYER, 0), human, "the session owns the human grid")
	charts.reveal_province(PLAYER, 0, 2)
	assert_eq(
		human.province_visibility(2), VisibilityModel.Level.FULLY_VISIBLE,
		"a human reveal lands on the shared grid"
	)
	assert_eq(charts.regions_of(PLAYER), human_views)


func test_an_uncharted_new_world_is_unknown_to_every_rival() -> void:
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


# --- fixture ----------------------------------------------------------------


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
