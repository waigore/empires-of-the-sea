extends GdToolsTest
## Integration: the world view — map build, camera, chart (fog) and turn flow.
## Crown orders (fleets, civilians, estates, leaders) live in
## test_map_screen_crown_orders so each native suite stays inside the
## coverage runner's per-suite timeout.

const Fixture = preload("res://tests/map_fixture.gd")

var _screen: MapScreen = null


func before_each() -> void:
	_screen = Fixture.attach_screen(self)


func after_each() -> void:
	# Free immediately: queue_free leaves prior screens processing fog/ships and
	# starves the suite under coverage (process timeout).
	if is_instance_valid(_screen):
		_screen.free()
	_screen = null

func test_world_holds_old_and_new_world() -> void:
	assert_not_null(_screen.world)
	assert_eq(_screen.world.region_count(), 2)
	assert_eq(_screen.region_index, 0)
	assert_eq(_screen.model.region_id, FactionCatalog.OLD_WORLD)


func test_region_toggle_switches_the_whole_view() -> void:
	_screen._cycle_region()
	assert_eq(_screen.region_index, 1)
	assert_eq(_screen.model.region_id, FactionCatalog.NEW_WORLD)
	assert_eq(_screen.canvas.model, _screen.model)
	assert_eq(_screen.overlay.model, _screen.model)
	assert_eq(_screen.ship_layer.model, _screen.model)
	assert_eq(_screen.visibility.model, _screen.model)
	_screen._cycle_region()
	assert_eq(_screen.region_index, 0)
	assert_eq(_screen.model.region_id, FactionCatalog.OLD_WORLD)


func test_the_new_world_stays_uncharted_at_game_start() -> void:
	_screen._cycle_region()
	var model: MapModel = _screen.model
	assert_eq(model.region_id, FactionCatalog.NEW_WORLD)
	var unknown: int = 0
	for index in _screen.visibility.levels.size():
		if _screen.visibility.level_at_index(index) == VisibilityModel.Level.UNKNOWN:
			unknown += 1
	assert_eq(unknown, _screen.visibility.levels.size(), "every tile is unknown")
	var tile: Vector2i = model.provinces[0].tiles[0]
	assert_eq(_screen.overlay.fog_state_at(tile.x, tile.y), MapOverlay.FOG_UNKNOWN)
	assert_true(_screen.overlay._country_borders.is_empty(), "no tribal borders leak")
	var minimap_image: Image = _screen.hud._minimap._texture.get_image()
	var pixel: Color = minimap_image.get_pixel(tile.x, tile.y)
	assert_almost_eq(pixel.r, Palette.PAPER.r, 0.01)
	assert_almost_eq(pixel.g, Palette.PAPER.g, 0.01)
	assert_almost_eq(pixel.b, Palette.PAPER.b, 0.01)
	for tribe: int in FactionCatalog.tribe_ids():
		assert_false(
			_screen.play.diplomacy.has_relation(_screen.play.player_faction, tribe),
			"an uncharted tribe is not a first contact"
		)


func test_tapping_uncharted_land_opens_no_dossier() -> void:
	_screen._cycle_region()
	var province_id: int = _screen.model.provinces[0].id
	var world: Vector2 = _screen.model.province_center(province_id) * MapScreen.TILE_SIZE
	MapPlayInput.on_tapped(_screen.play, world)
	assert_eq(_screen.selected_province, -1, "unknown land is not selectable")
	assert_false(_screen.hud.panels.is_panel_open())


func test_minimap_repaints_when_a_province_is_charted() -> void:
	var minimap: Minimap = _screen.hud._minimap
	var province: int = Fixture.foreign_province(_screen.model)
	var tile: Vector2i = _screen.model.province_tiles(province)[0]
	minimap._process(0.0)
	var before: Color = minimap._texture.get_image().get_pixel(tile.x, tile.y)
	_screen.visibility.reveal_province(province)
	minimap._process(0.0)
	var after: Color = minimap._texture.get_image().get_pixel(tile.x, tile.y)
	assert_ne(before, after, "a charted tile repaints the inset")


func test_country_borders_are_built_for_every_owner() -> void:
	var borders: Dictionary = _screen.overlay._country_borders
	assert_true(borders.size() >= FactionCatalog.great_power_ids().size())
	for owner: int in borders.keys():
		assert_true(FactionCatalog.has_faction(owner))


func test_region_switch_keeps_fleets_and_chart_state() -> void:
	var fleet_id: int = _screen.ship_layer.fleets[0].id
	var tile: Vector2i = _screen.model.province_tiles(Fixture.foreign_province(_screen.model))[0]
	var index: int = _screen.model.index_of(tile.x, tile.y)
	_screen.visibility.raise_to(index, VisibilityModel.Level.FULLY_VISIBLE)

	_screen._cycle_region()
	_screen._cycle_region()

	assert_eq(_screen.ship_layer.fleets[0].id, fleet_id)
	assert_eq(
		_screen.visibility.level_at(tile.x, tile.y), VisibilityModel.Level.FULLY_VISIBLE
	)


## The charted Old World stays clear after a round trip through the New World.
## Each view rebuild used to stack a fresh fog sprite, so the newcomer's
## all-paper wash (every tile unknown) sat under the home map and covered the
## crown's own provinces (wiki: fog-and-exploration § Initial Visibility).
func test_returning_to_the_old_world_keeps_its_chart_clear() -> void:
	var fog: FogLayer = _screen.overlay.fog_layer
	var capital: Vector2i = _screen.capital_tile
	_settle_fog()
	assert_almost_eq(_fog_alpha(fog, capital), 0.0, 0.001, "the seat opens clear")

	# A settled frame paints each map before the next toggle, as play does.
	_screen._cycle_region()
	_settle_fog()
	_screen._cycle_region()
	_settle_fog()

	assert_eq(_screen.region_index, FactionCatalog.OLD_WORLD)
	assert_eq(fog.get_child_count(), 1, "a switch repaints the map's own fog layer")
	assert_almost_eq(_fog_alpha(fog, capital), 0.0, 0.001, "the seat stays clear")
	var foreign: Vector2i = _screen.model.province_tiles(
		Fixture.foreign_province(_screen.model)
	)[0]
	assert_gt(_fog_alpha(fog, foreign), 0.0, "charted foreign land keeps its mist")


func test_world_builds_with_map_ships_and_camera() -> void:
	assert_not_null(_screen.model)
	assert_gt(_screen.model.province_count(), 0)
	assert_eq(_screen.canvas.model, _screen.model)
	assert_eq(_screen.ship_layer.ships.size(), MapScreen.SHIP_COUNT)
	assert_gt(_screen.capital_province, -1)
	var map_width: float = MapGeo.world_size(_screen.model, MapScreen.TILE_SIZE).x
	assert_almost_eq(_screen.camera.map_size.x, map_width, 1.0)


func test_capital_tile_comes_from_the_capital_choice_phase() -> void:
	var province: ProvinceState = _screen.model.province_data(_screen.capital_province)
	assert_true(province.capital)
	assert_eq(_screen.capital_tile, Vector2i(province.capital_tile))
	assert_true(_screen.model.is_land(_screen.capital_tile.x, _screen.capital_tile.y))
	assert_eq(
		_screen.model.terrain_at(_screen.capital_tile.x, _screen.capital_tile.y),
		MapModel.Terrain.PLAINS
	)


func test_focus_capital_centres_on_the_capital_tile() -> void:
	MapPlaySetup.focus_capital(_screen.play)
	for _step in 20:
		_screen.camera._process(0.2)
	var expected: Vector2 = CameraMath.clamp_center(
		MapPlaySetup.capital_world(_screen.play),
		_screen.camera.zoom.x,
		_screen.camera.viewport_size(),
		_screen.camera.map_size
	)
	assert_lt(_screen.camera.position.distance_to(expected), 2.0)


func test_clicking_a_province_selects_it_and_opens_the_panel() -> void:
	var province_id: int = Fixture.inland_province(_screen.model)
	var world: Vector2 = _screen.model.province_center(province_id) * MapScreen.TILE_SIZE
	MapPlayInput.on_tapped(_screen.play, world)
	assert_eq(_screen.selected_province, province_id)
	assert_true(_screen.hud.panels.is_panel_open())


func test_clicking_open_water_clears_the_selection() -> void:
	var province_id: int = Fixture.inland_province(_screen.model)
	MapPlayInput.on_tapped(
		_screen.play, _screen.model.province_center(province_id) * MapScreen.TILE_SIZE
	)
	assert_true(_screen.hud.panels.is_panel_open())

	var sea_tile: Vector2i = _screen.model.sea_zones[0].tiles[0]
	MapPlayInput.on_tapped(
		_screen.play, MapGeo.tile_center(sea_tile.x, sea_tile.y, MapScreen.TILE_SIZE)
	)
	assert_eq(_screen.selected_province, -1)
	assert_false(_screen.hud.panels.is_panel_open())


func test_clicking_a_fleet_selects_it() -> void:
	var ship: Ship = _screen.ship_layer.ships[0]
	MapPlayInput.on_tapped(_screen.play, ship.position)
	assert_eq(_screen.ship_layer.selected(), ship)
	assert_true(ship.selected)


func test_end_turn_advances_calendar_and_treasury() -> void:
	var turn_before: int = _screen.turn
	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)
	assert_eq(_screen.turn, turn_before + 1)
	assert_eq(_screen.treasury, _screen.economy.economy.treasury)
	assert_eq(_screen.income, _screen.economy.projected_income())
	assert_eq(TurnTime.year_for_turn(_screen.turn), TurnTime.START_YEAR + 2)


func test_the_recruit_order_opens_the_home_army_drill_yard() -> void:
	var province_id: int = Fixture.inland_province(_screen.model)
	MapPlayInput.on_tapped(
		_screen.play, _screen.model.province_center(province_id) * MapScreen.TILE_SIZE
	)
	MapPlayInput.on_panel_action(_screen.play, "recruit")
	assert_true(_screen.hud.panels.is_army_panel_open())
	assert_false(_screen.hud.panels.is_panel_open())
	var army: ArmyState = _screen.army_layer.selected_army
	assert_not_null(army)
	assert_true(army.is_home_army())
	assert_true(_screen.hud.panels.army_panel._muster_box.visible)


func test_wheel_zoom_changes_the_camera_scale() -> void:
	# A small chart opens near the MAX_ZOOM clamp, so step out first: the wheel
	# must still move the scale, and the case no longer depends on how much
	# headroom the opening zoom happened to leave.
	_screen.camera.zoom_by(0.5, _screen.camera.viewport_size() * 0.5)
	_screen.camera._process(0.4)
	var before: float = _screen.camera.zoom.x
	assert_lt(before, MapCamera.MAX_ZOOM, "the chart opens with room to zoom in")
	_screen.camera.zoom_by(1.14, _screen.camera.viewport_size() * 0.5)
	assert_gt(_screen.camera.target_zoom, before)
	_screen.camera._process(0.4)
	assert_gt(_screen.camera.zoom.x, before)


func test_zoom_is_clamped_to_limits() -> void:
	_screen.camera.zoom_by(100.0, Vector2.ZERO)
	assert_lte(_screen.camera.target_zoom, MapCamera.MAX_ZOOM)
	_screen.camera.zoom_by(0.0001, Vector2.ZERO)
	assert_gte(_screen.camera.target_zoom, _screen.camera.min_zoom())


func test_drag_pans_the_camera() -> void:
	var start: Vector2 = _screen.camera.position
	_screen.camera._handle_mouse_button(Fixture.mouse_button(true, Vector2(400, 300)))
	_screen.camera._handle_mouse_motion(Fixture.mouse_motion(Vector2(-120, -80)))
	_screen.camera._handle_mouse_button(Fixture.mouse_button(false, Vector2(400, 300)))
	assert_ne(_screen.camera.position, start)


func test_camera_never_leaves_the_map() -> void:
	_screen.camera.position = Vector2(-9000, -9000)
	_screen.camera._process(0.016)
	assert_true(_visible_inside_map())

	_screen.camera.position = Vector2(99999, 99999)
	_screen.camera._process(0.016)
	assert_true(_visible_inside_map())


func test_minimap_jump_settles_on_the_requested_point() -> void:
	var target: Vector2 = _screen.camera.map_size * 0.75
	MapPlayInput.on_minimap_jump(_screen.play, target)
	for _step in 20:
		_screen.camera._process(0.2)
	var expected: Vector2 = CameraMath.clamp_center(
		target,
		_screen.camera.zoom.x,
		_screen.camera.viewport_size(),
		_screen.camera.map_size
	)
	assert_lt(_screen.camera.position.distance_to(expected), 2.0)


func test_player_fleet_reveals_only_for_the_player() -> void:
	var zone: SeaZoneState = _screen.model.sea_zones[1]
	var tile: Vector2i = zone.tiles[0]
	var index: int = _screen.model.index_of(tile.x, tile.y)
	_screen.overlay.set_fog_state(index, MapOverlay.FOG_FOGGED)
	var enemy := Ship.new()
	enemy.faction = 1
	MapPlayFleets.on_zone_entered(_screen.play, int(zone.id), enemy)
	assert_eq(_screen.overlay.fog_state_at(tile.x, tile.y), MapOverlay.FOG_FOGGED)
	enemy.free()


func test_hover_reports_the_province_under_the_cursor() -> void:
	var province_id: int = Fixture.inland_province(_screen.model)
	var world: Vector2 = _screen.model.province_center(province_id) * MapScreen.TILE_SIZE
	_screen.camera.focus_on(world, 0.8, true)
	_screen.camera._process(0.016)
	var screen_point: Vector2 = CameraMath.world_to_screen(
		_screen.camera.position, _screen.camera.zoom.x, world, _screen.camera.viewport_size()
	)
	MapPlayInput.update_hover(_screen.play, screen_point)
	assert_eq(_screen.overlay.hover_province, province_id)
	assert_true(_screen.hud._tooltip.visible)


func test_visibility_starts_from_the_world_rules() -> void:
	assert_not_null(_screen.visibility)
	var own_tile: Vector2i = _screen.model.province_tiles(_screen.capital_province)[0]
	assert_eq(
		_screen.visibility.level_at(own_tile.x, own_tile.y),
		VisibilityModel.Level.FULLY_VISIBLE
	)
	assert_eq(_screen.overlay.fog_state_at(own_tile.x, own_tile.y), MapOverlay.FOG_VISIBLE)
	var foreign: int = Fixture.foreign_province(_screen.model)
	var foreign_tile: Vector2i = _screen.model.province_tiles(foreign)[0]
	assert_eq(
		_screen.visibility.level_at(foreign_tile.x, foreign_tile.y),
		VisibilityModel.Level.FOGGED
	)
	assert_eq(
		_screen.overlay.fog_state_at(foreign_tile.x, foreign_tile.y), MapOverlay.FOG_FOGGED
	)


func test_end_turn_applies_fog_decay_to_foreign_coasts() -> void:
	var tile: Vector2i = _screen.model.province_tiles(Fixture.foreign_province(_screen.model))[0]
	var index: int = _screen.model.index_of(tile.x, tile.y)
	_screen.visibility.raise_to(index, VisibilityModel.Level.FULLY_VISIBLE)
	_screen.overlay.sync_visibility(_screen.visibility, [index])
	assert_eq(_screen.overlay.fog_state_at(tile.x, tile.y), MapOverlay.FOG_VISIBLE)
	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)
	assert_eq(_screen.overlay.fog_state_at(tile.x, tile.y), MapOverlay.FOG_FOGGED)


func test_player_fleet_reveal_charts_the_coastal_ring() -> void:
	var ship: Ship = _screen.ship_layer.ships[0]
	var zone_tiles: Array = _screen.model.sea_zone_data(ship.zone).tiles
	var water: Vector2i = zone_tiles[0]
	var water_index: int = _screen.model.index_of(water.x, water.y)
	_screen.visibility.lower_to(water_index, VisibilityModel.Level.FOGGED)
	_screen.overlay.sync_visibility(_screen.visibility, [water_index])
	MapPlayFleets.on_zone_entered(_screen.play, ship.zone, ship)
	assert_eq(_screen.overlay.fog_state_at(water.x, water.y), MapOverlay.FOG_VISIBLE)
	var land: Vector2i = Fixture.coastal_land_of(_screen.model, ship.zone)
	assert_true(land.x >= 0)
	assert_eq(_screen.overlay.fog_state_at(land.x, land.y), MapOverlay.FOG_VISIBLE)


func test_unknown_land_is_reported_without_terrain_or_owner() -> void:
	var tile: Vector2i = _screen.model.province_tiles(Fixture.foreign_province(_screen.model))[0]
	var index: int = _screen.model.index_of(tile.x, tile.y)
	_screen.visibility.lower_to(index, VisibilityModel.Level.UNKNOWN)
	var world: Vector2 = MapGeo.tile_center(tile.x, tile.y, MapScreen.TILE_SIZE)
	_screen.camera.focus_on(world, 0.8, true)
	_screen.camera._process(0.016)
	var screen_point: Vector2 = CameraMath.world_to_screen(
		_screen.camera.position, _screen.camera.zoom.x, world, _screen.camera.viewport_size()
	)
	MapPlayInput.update_hover(_screen.play, screen_point)
	assert_eq(_screen.hud._tooltip_label.text, "Uncharted land")


func test_end_turn_resolves_a_contested_sea_zone() -> void:
	var player_fleet: FleetState = Fixture.fleet_at_sea(
		_screen.ship_layer.fleets, MapScreen.PLAYER_FACTION
	)
	var enemy_fleet: FleetState = Fixture.fleet_at_sea(_screen.ship_layer.fleets, 2)
	assert_not_null(player_fleet)
	assert_not_null(enemy_fleet)
	# Dock every other squadron so only these two share water.
	for fleet: FleetState in _screen.ship_layer.fleets:
		if fleet == player_fleet or fleet == enemy_fleet:
			continue
		fleet.location = FleetState.Location.IN_PORT
		fleet.province = int(_screen.model.provinces[0].id)
	player_fleet.set_hulls(["hull_player"], {"hull_player": "carrack"})
	enemy_fleet.set_hulls(["hull_enemy"], {"hull_enemy": "fluyte"})
	enemy_fleet.location = FleetState.Location.AT_SEA
	enemy_fleet.sea_zone = int(_screen.model.sea_zones[0].id)
	player_fleet.location = FleetState.Location.AT_SEA
	player_fleet.sea_zone = enemy_fleet.sea_zone
	DiplomacyRules.declare_war(_screen.play.diplomacy, MapScreen.PLAYER_FACTION, 2)
	var toasts_before: int = _screen.hud._toast_box.get_child_count()

	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)

	# A beaten squadron is routed, or slips into adjacent neutral water when the
	# retreat roll succeeds (wiki: ships-and-naval § Naval Retreat Formula).
	if enemy_fleet.is_afloat():
		assert_ne(enemy_fleet.sea_zone, player_fleet.sea_zone,
			"a beaten squadron that survives has left the contested zone")
	else:
		assert_eq(_screen.ship_layer.hull_count_all(2), 0)
	assert_eq(player_fleet.ship_count(), 1)
	assert_gt(_screen.hud._toast_box.get_child_count(), toasts_before)


func test_fleets_at_peace_share_a_zone_without_a_battle() -> void:
	var player_fleet: FleetState = Fixture.fleet_at_sea(
		_screen.ship_layer.fleets, MapScreen.PLAYER_FACTION
	)
	var other_fleet: FleetState = Fixture.fleet_at_sea(_screen.ship_layer.fleets, 2)
	assert_not_null(player_fleet)
	assert_not_null(other_fleet)
	for fleet: FleetState in _screen.ship_layer.fleets:
		if fleet == player_fleet or fleet == other_fleet:
			continue
		fleet.location = FleetState.Location.IN_PORT
		fleet.province = int(_screen.model.provinces[0].id)
	player_fleet.set_hulls(["p"], {"p": "carrack"})
	other_fleet.set_hulls(["o"], {"o": "fluyte"})
	other_fleet.location = FleetState.Location.AT_SEA
	other_fleet.sea_zone = int(_screen.model.sea_zones[0].id)
	player_fleet.location = FleetState.Location.AT_SEA
	player_fleet.sea_zone = other_fleet.sea_zone
	var hulls_before: int = player_fleet.ship_count() + other_fleet.ship_count()

	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)

	assert_false(_screen.play.diplomacy.relation(0, 2).at_war)
	assert_eq(player_fleet.ship_count() + other_fleet.ship_count(), hulls_before)


## The end-of-turn fog pass is a rules pass, not a view pass: knowledge in the
## region the player is not reading must still decay (wiki: fog-and-exploration
## § Fog Decay). Otherwise a rival coast charted once stays charted forever just
## because the map was switched before the turn closed.
func test_end_turn_fogs_rival_coasts_in_the_region_off_screen() -> void:
	_screen._cycle_region()
	var new_world: MapModel = _screen.model
	var province: int = Fixture.foreign_province(new_world)
	var tile: Vector2i = new_world.province_tiles(province)[0]
	var index: int = new_world.index_of(tile.x, tile.y)
	var visibility: VisibilityModel = _screen.play.visibility_by_region[FactionCatalog.NEW_WORLD]
	visibility.raise_to(index, VisibilityModel.Level.FULLY_VISIBLE)
	_screen._cycle_region()
	assert_eq(_screen.region_index, FactionCatalog.OLD_WORLD, "the Old World is on screen")

	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)

	assert_eq(
		visibility.level_at(tile.x, tile.y),
		VisibilityModel.Level.FOGGED,
		"the New World chart decays while the Old World is on screen"
	)


## Same rule for water: a distant sea zone with no owned coast and no fleet at
## sea reverts to fogged in every region, not only the one being looked at
## (wiki: fog-and-exploration § Distant sea zone fog).
func test_end_turn_fogs_distant_water_in_the_region_off_screen() -> void:
	_screen._cycle_region()
	var new_world: MapModel = _screen.model
	var visibility: VisibilityModel = _screen.play.visibility_by_region[FactionCatalog.NEW_WORLD]
	var zone_id: int = _quiet_zone(new_world, visibility)
	assert_gt(zone_id, -1, "the New World holds water nobody is watching")
	var tile: Vector2i = new_world.sea_zone_data(zone_id).tiles[0]
	var index: int = new_world.index_of(tile.x, tile.y)
	visibility.raise_to(index, VisibilityModel.Level.FULLY_VISIBLE)
	_screen._cycle_region()

	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)

	assert_eq(
		visibility.level_at(tile.x, tile.y),
		VisibilityModel.Level.FOGGED,
		"unwatched New World water refogs with the Old World on screen"
	)


## A tap on uncharted land has to say why nothing opened: the hover tooltip is
## mouse-only, so a touch player gets no feedback at all today (P1 readable UI).
func test_tapping_uncharted_land_explains_the_refusal() -> void:
	_screen._cycle_region()
	var province_id: int = _screen.model.provinces[0].id
	var tile: Vector2i = _screen.model.province_tiles(province_id)[0]
	var world: Vector2 = MapGeo.tile_center(tile.x, tile.y, MapScreen.TILE_SIZE)
	var toasts_before: int = _screen.hud._toast_box.get_child_count()

	MapPlayInput.on_tapped(_screen.play, world)

	assert_eq(_screen.selected_province, -1, "uncharted land opens no dossier")
	assert_eq(
		_screen.hud._toast_box.get_child_count(),
		toasts_before + 1,
		"the tap reports that the land is uncharted"
	)


## The map's march order uses the same chart gate as the rules: tapping an
## uncharted province is refused with a reason and the unit stays put.
func test_marching_into_uncharted_land_is_refused_on_the_map() -> void:
	var pair: Array[Vector2i] = _province_border_tiles(_screen.model)
	assert_eq(pair.size(), 2, "the map has two provinces sharing an edge")
	var explorer: CivilianState = _screen.civilian_layer.add_unit(
		_screen.play.player_faction, "explorer", pair[0]
	)
	var hidden: int = _screen.model.province_at(pair[1].x, pair[1].y)
	for tile: Vector2i in _screen.model.province_tiles(hidden):
		_screen.visibility.lower_to(
			_screen.model.index_of(tile.x, tile.y), VisibilityModel.Level.UNKNOWN
		)
	_screen.civilian_layer.select(explorer)
	var toasts_before: int = _screen.hud._toast_box.get_child_count()

	var claimed: bool = MapPlayCivilians.try_move(
		_screen.play, MapGeo.tile_center(pair[1].x, pair[1].y, MapScreen.TILE_SIZE)
	)

	assert_true(claimed, "the tap is a march order, not a dossier tap")
	assert_eq(explorer.tile, pair[0], "the Explorer stays on charted land")
	assert_eq(
		_screen.hud._toast_box.get_child_count(),
		toasts_before + 1,
		"the refusal is reported"
	)


## Espionage in the live session: a spy posted on a rival Great Power's land
## holds that province charted and quickens research the rival has finished
## (wiki: civilian-units § Spy; DR-20261110-03).
func test_a_spy_posted_in_a_rival_province_quickens_research() -> void:
	var rival: int = _rival_great_power()
	assert_true(rival >= 0, "the world has a rival Great Power province")
	var tile: Vector2i = _screen.model.province_tiles(_foreign_province_of(rival))[0]
	_screen.civilian_layer.add_unit(_screen.play.player_faction, "spy", tile)
	if _screen.play.ai == null:
		_screen.play.ai = AiState.new()
	_screen.play.ai.economy_for(rival).tech_unlocked["navigation"] = true
	var boost: Dictionary = MapPlayEspionage.research_boost(_screen.play)
	assert_eq(SpyNetworks.boost_for(boost, "navigation"), 15)
	assert_eq(SpyNetworks.boost_for(boost, "saw_mill"), 0, "unfinished by the rival")


func test_a_spy_on_the_crowns_own_land_quickens_nothing() -> void:
	var tile: Vector2i = _screen.model.province_tiles(_screen.capital_province)[0]
	_screen.civilian_layer.add_unit(_screen.play.player_faction, "spy", tile)
	assert_true(
		MapPlayEspionage.research_boost(_screen.play).is_empty(),
		"own soil hands over no research"
	)


func test_end_turn_holds_the_province_a_spy_shadows() -> void:
	var rival: int = _rival_great_power()
	assert_true(rival >= 0)
	var province: int = _foreign_province_of(rival)
	var tile: Vector2i = _screen.model.province_tiles(province)[0]
	_screen.civilian_layer.add_unit(_screen.play.player_faction, "spy", tile)
	assert_false(_screen.visibility.is_province_fully_visible(province))
	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)
	assert_true(
		_screen.visibility.is_province_fully_visible(province),
		"the shadowed province is held in view"
	)


## The share a spy network wins must be visible where it is spent: the ledger
## reports "1 study quickened", and the slot it lifted carries the "+15%" marker
## (REQ-P5-05; DR-20261110-03). The share used to be wiped before the panel
## repainted, so the marker never appeared at all.
func test_the_quickened_slot_shows_its_share_after_the_turn() -> void:
	var rival: int = _rival_great_power()
	assert_true(rival >= 0, "the world has a rival Great Power province")
	var province: int = _foreign_province_of(rival)
	_screen.civilian_layer.add_unit(
		_screen.play.player_faction, "spy", _screen.model.province_tiles(province)[0]
	)
	if _screen.play.ai == null:
		_screen.play.ai = AiState.new()
	var tech: String = _first_studyable_tech()
	assert_false(tech.is_empty(), "the crown has an advance it could study")
	_screen.play.ai.economy_for(rival).tech_unlocked[tech] = true
	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)
	assert_eq(
		SpyNetworks.boost_for(MapPlayEspionage.research_boost(_screen.play), tech),
		15,
		"the spy still shadows the court whose tech it studies"
	)
	_screen.play.economy.open_research()
	var marked: bool = false
	for row: String in _research_slot_rows():
		if row.contains(TechCatalog.display_name(tech)) and row.contains("+15%"):
			marked = true
	assert_true(marked, "the quickened slot shows the share it earned")


## An advanced start opens at turn 50 or 100, so a briefing that always says
## "Turn 1, 1500" greets a mid-age court with the wrong year (wiki:
## advanced-starts).
func test_the_opening_briefing_names_the_campaigns_own_year() -> void:
	RegionBriefing.opening(_screen.hud, _screen.model, _screen.capital_province, 0, 100)
	assert_true(
		_toast_texts().has("The Indies await — Turn 100, 1698"),
		"the turn-100 preset opens in 1698"
	)
	RegionBriefing.opening(_screen.hud, _screen.model, _screen.capital_province, 0)
	assert_true(
		_toast_texts().has("The Indies await — Turn 1, 1500"),
		"a turn-0 campaign still opens in 1500"
	)


## First advance the crown lacks and could put in a slot right now.
func _first_studyable_tech() -> String:
	for id: String in TechCatalog.ids():
		if _screen.play.has_tech(_screen.play.player_faction, id):
			continue
		if bool(_screen.play.economy.economy.research.assign(id).get("ok", false)):
			return id
	return ""


## One line per occupied research slot, as the panel draws it.
func _research_slot_rows() -> Array[String]:
	var rows: Array[String] = []
	for row: Node in _screen.hud.panels.research_panel.find_children(
		"*", "HBoxContainer", true, false
	):
		var texts: PackedStringArray = PackedStringArray()
		for label: Label in row.find_children("*", "Label", true, false):
			texts.append(label.text)
		if texts.size() >= 2 and " / " in texts[1]:
			rows.append(" | ".join(texts))
	return rows


func _toast_texts() -> Array[String]:
	var texts: Array[String] = []
	for panel: Node in _screen.hud._toast_box.get_children():
		for label: Label in panel.find_children("*", "Label", true, false):
			texts.append(label.text)
	return texts


## Lets the fog fade reach its targets, as a handful of processed frames would.
func _settle_fog() -> void:
	for _frame in 40:
		_screen.overlay.fog_layer.advance(0.016)


## Fog alpha the layer paints on one tile of the region on screen.
func _fog_alpha(fog: FogLayer, tile: Vector2i) -> float:
	return fog._image.get_pixel(tile.x, tile.y).a


## First Old World province owned by a rival Great Power, or -1.
func _rival_great_power() -> int:
	var province: int = _foreign_province_of(-1)
	if province < 0:
		return -1
	return _screen.model.province_owner(province)


## First province owned by `owner` in the shown region (any rival when -1).
func _foreign_province_of(owner: int) -> int:
	for data: ProvinceState in _screen.model.provinces:
		if data.owner == _screen.play.player_faction:
			continue
		if owner >= 0 and data.owner != owner:
			continue
		if owner < 0 and not FactionCatalog.great_power_ids().has(data.owner):
			continue
		return data.id
	return -1


## First orthogonal land pair that straddles two provinces.
func _province_border_tiles(model: MapModel) -> Array[Vector2i]:
	for y in model.height:
		for x in model.width:
			if not model.is_land(x, y):
				continue
			for offset: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
				var nx: int = x + offset.x
				var ny: int = y + offset.y
				if not model.in_bounds(nx, ny) or not model.is_land(nx, ny):
					continue
				if model.province_at(x, y) == model.province_at(nx, ny):
					continue
				return [Vector2i(x, y), Vector2i(nx, ny)] as Array[Vector2i]
	return []


## A New World sea zone no player fleet is watching and no owned coast fronts.
func _quiet_zone(model: MapModel, visibility: VisibilityModel) -> int:
	for zone: SeaZoneState in model.sea_zones:
		var zone_id: int = int(zone.id)
		if visibility.owns_coast(zone_id):
			continue
		var watched: bool = false
		for fleet: FleetState in _screen.ship_layer.fleets:
			if fleet.owner != _screen.play.player_faction or not fleet.is_at_sea():
				continue
			if fleet.sea_zone == zone_id:
				watched = true
				break
		if not watched:
			return zone_id
	return -1


func _visible_inside_map() -> bool:
	var half: Vector2 = _screen.camera.viewport_size() / (2.0 * _screen.camera.zoom.x)
	var low: Vector2 = _screen.camera.position - half
	var high: Vector2 = _screen.camera.position + half
	var map_size: Vector2 = _screen.camera.map_size
	return (
		_axis_settled(low.x, high.x, map_size.x)
		and _axis_settled(low.y, high.y, map_size.y)
	)


## An axis is valid when the view sits inside the map, or the map fits inside
## the view (at that point the camera centres it).
func _axis_settled(low: float, high: float, map_extent: float) -> bool:
	var inside: bool = low >= -1.0 and high <= map_extent + 1.0
	var covering: bool = low <= 1.0 and high >= map_extent - 1.0
	return inside or covering
