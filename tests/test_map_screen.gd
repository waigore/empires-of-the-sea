# gdlint: disable=max-public-methods
extends GdToolsTest
## Integration: the live map — one mount pays every reading of it: the world
## view (map build, camera, chart/fog, turn flow), crown orders (fleets,
## civilians, estates, leaders), the four lenses, and the agent debug bridge's
## live projection.
##
## Merged from test_map_screen_crown_orders, test_map_lenses and
## test_agent_debug_bridge: one Godot boot (coverage instrumentation) per theme
## instead of one per file (docs/testing.md § Speed rules).

const Fixture = preload("res://tests/map_fixture.gd")

## One mounted screen for the whole suite: under coverage a mount costs ~0.5 s
## and a re-seat from the pristine save ~0.15 s, so the cases share the chart
## and reset the session instead of remounting (`Fixture.suite_reset`).
var mounted: MapScreen = null
var pristine: Dictionary = {}
var pristine_map: Array = []
var _screen: MapScreen = null


func before_all() -> void:
	pristine_map = Fixture.snapshot(Fixture.world())
	mounted = Fixture.attach_screen(self)
	pristine = Fixture.suite_capture(mounted)


func before_each() -> void:
	Fixture.restore(Fixture.world(), pristine_map)
	Fixture.suite_reset(mounted, pristine)
	_screen = mounted


func after_all() -> void:
	if is_instance_valid(mounted):
		mounted.free()
	mounted = null
	_screen = null
	pristine = {}


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


## Join Empire repaints where the layers do not: the host delegate hands the
## whole political redraw to MapPlayRegion, and the chart, fog and lens follow.
func test_a_political_refresh_repaints_chart_and_lens() -> void:
	MapPlayInput.set_diplomacy_lens(_screen.play, true)
	var before: int = int(_screen.play.diplomacy_lens.survey["tiles"]["self"])
	assert_gt(before, 0)
	_screen.refresh_political_map()
	assert_eq(_screen.canvas.model, _screen.model)
	assert_eq(_screen.overlay.model, _screen.model)
	assert_eq(_screen.play.diplomacy_lens.model, _screen.model)
	assert_true(_screen.play.diplomacy_lens.active, "the raised lens survives the refresh")
	assert_eq(int(_screen.play.diplomacy_lens.survey["tiles"]["self"]), before)


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


## The mount must leave a readable chart in the inset: the frame around it is a
## near-black panel, so an inset that never built — or built at zero size, which
## projects no ink — reads as a black box on the opening screen (issue #563).
func test_the_minimap_inset_paints_the_chart_on_mount() -> void:
	var minimap: Minimap = _screen.hud._minimap
	assert_not_null(minimap)
	assert_gt(minimap.size.x, 0.0, "the inset has a positive width")
	assert_gt(minimap.size.y, 0.0, "the inset has a positive height")
	assert_not_null(minimap._texture, "the mount built the chart texture")
	var image: Image = minimap._texture.get_image()
	assert_eq(
		image.get_size(), Vector2i(_screen.model.width, _screen.model.height),
		"one texel per chart tile"
	)
	# Ink is projected against the inset's own size, so a zero-size build is what
	# leaves the coast and the owners' ribbons empty.
	assert_gt(minimap._ink_coast.size(), 0, "the coast is inked into the inset")
	assert_gt(minimap._ink_borders.size(), 0, "the owners' borders are inked too")
	var dark: int = 0
	var distinct: Dictionary = {}
	for y in image.get_height():
		for x in image.get_width():
			var color: Color = image.get_pixel(x, y)
			if (color.r + color.g + color.b) / 3.0 < 0.12:
				dark += 1
			distinct[color.to_rgba32()] = true
	var total: int = image.get_width() * image.get_height()
	assert_lt(float(dark) / float(total), 0.02, "the inset is not a solid black fill")
	assert_gt(distinct.size(), 8, "sea, terrain and the owner wash all read")


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
	assert_eq(_screen.income, _screen.economy.readings.projected_income())
	assert_eq(TurnTime.year_for_turn(_screen.turn), TurnTime.START_YEAR + 2)


## Every court's rations are recorded, not just the human's: a rival's hungry
## army or squadron must fight at the published morale band next turn
## (wiki: combat § Feeding modifiers; workers-and-population § Consumption).
func test_end_turn_records_every_courts_rations() -> void:
	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)
	for faction: int in FactionCatalog.great_power_ids():
		assert_true(
			_screen.play.feeding.has(faction),
			"%s keeps an army feeding record" % FactionCatalog.name_of(faction)
		)
		var ledger: PlayerEconomy = _screen.play.ledger_for(faction)
		assert_not_null(ledger, "%s keeps a ledger" % FactionCatalog.name_of(faction))
		assert_true(
			ledger.navy_feeding >= 0.0 and ledger.navy_feeding <= 1.0,
			"%s keeps a navy feeding record" % FactionCatalog.name_of(faction)
		)


## The crown's own rations are filed under the crown the player chose, not the
## legacy default: a court that sails as England must still fight at the
## published feeding band, and her record must not land on Spain
## (wiki: combat § Feeding modifiers; game-setup § Human/AI slot assignment).
func test_the_chosen_crowns_rations_are_filed_under_its_own_colour() -> void:
	var english: MapScreen = Fixture.attach_screen(self, 1)
	assert_eq(english.play.player_faction, 1)
	MapPlayTurn.end_turn(english.play)
	Fixture.settle(english.play)
	var coverage: float = english.economy.readings.feeding_coverage()
	assert_true(
		english.play.feeding.has(english.play.player_faction),
		"England keeps her own army feeding record"
	)
	assert_almost_eq(
		float(english.play.feeding.get(english.play.player_faction, -1.0)),
		coverage, 0.001,
		"the chosen crown's record is her own consumption"
	)
	english.free()


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
## region the player is not reading must still decay for rival coasts and for
## distant water (wiki: fog-and-exploration § Fog Decay, § Distant sea zone fog).
## One turn covers both: each used to pay a full end_turn under coverage (~2 s).
func test_end_turn_fogs_rival_coasts_and_distant_water_off_screen() -> void:
	_screen._cycle_region()
	var new_world: MapModel = _screen.model
	var visibility: VisibilityModel = _screen.play.visibility_by_region[FactionCatalog.NEW_WORLD]
	var province: int = Fixture.foreign_province(new_world)
	var coast: Vector2i = new_world.province_tiles(province)[0]
	visibility.raise_to(
		new_world.index_of(coast.x, coast.y), VisibilityModel.Level.FULLY_VISIBLE
	)
	var zone_id: int = _quiet_zone(new_world, visibility)
	assert_gt(zone_id, -1, "the New World holds water nobody is watching")
	var water: Vector2i = new_world.sea_zone_data(zone_id).tiles[0]
	visibility.raise_to(
		new_world.index_of(water.x, water.y), VisibilityModel.Level.FULLY_VISIBLE
	)
	_screen._cycle_region()
	assert_eq(_screen.region_index, FactionCatalog.OLD_WORLD, "the Old World is on screen")

	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)

	assert_eq(
		visibility.level_at(coast.x, coast.y),
		VisibilityModel.Level.FOGGED,
		"the New World chart decays while the Old World is on screen"
	)
	assert_eq(
		visibility.level_at(water.x, water.y),
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
	var panel: ResearchPanel = _screen.hud.panels.research_panel
	for node: Node in panel._slots_body.get_children():
		var texts: PackedStringArray = PackedStringArray()
		for label: Label in node.find_children("*", "Label", true, false):
			if label.is_visible_in_tree():
				texts.append(label.text)
		if texts.size() >= 2 and " RP" in " | ".join(texts):
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


# --- folded: the map lenses (survey / political wash / crown road / defence) ---
## One boot for the live map pays these too: the survey lens (L), the political
## wash (P), the crown road lens and the defence reading (K) — toggle, key,
## mutual exclusion, repaint on the signal, slip taps, the hover line, and the
## defence projection on a four-province chart of its own
## (merged from test_resource_lens, test_diplomacy_lens, test_defence_lens).


## --- the survey lens (L) -----------------------------------------------------


func test_lens_toggle_raises_the_key_and_builds_a_survey() -> void:
	var lens: ResourceLens = _screen.play.lens
	assert_not_null(lens)
	assert_false(lens.active)
	assert_false(_screen.hud.lens_legend.visible)

	MapPlayInput.set_lens(_screen.play, true)
	assert_true(lens.active)
	assert_true(_screen.hud.lens_legend.visible)
	assert_true(_screen.hud.lens_seal.button_pressed)
	assert_eq(_screen.hud.lens_seal.active_kind, LensLegend.KIND_SURVEY)
	assert_gt(int(lens.survey["counts"]["estates"]), 0)
	assert_gt((lens.survey.get("routes", []) as Array).size(), 0, "the lens carries the roads")
	assert_eq(
		(lens._runs as Array).size(), RoadInk.ink_paths(lens.survey["routes"]).size(),
		"the lens bakes the road ink once, from the same segments"
	)
	assert_almost_eq(_screen.civilian_layer.modulate.a, 0.22, 0.001)

	lens._reveal = 1.0
	lens.queue_redraw()
	await get_tree().process_frame

	MapPlayInput.set_lens(_screen.play, false)
	assert_false(lens.active)
	assert_false(_screen.hud.lens_legend.visible)
	assert_false(_screen.hud.lens_seal.button_pressed)
	assert_almost_eq(_screen.civilian_layer.modulate.a, 1.0, 0.001)


func test_a_completed_estate_refreshes_the_survey() -> void:
	MapPlayInput.set_lens(_screen.play, true)
	var lens: ResourceLens = _screen.play.lens
	var found: Array = _owned_vacant(lens.survey)
	assert_false(found.is_empty())
	var entry: Dictionary = found[0]
	var row: Dictionary = found[1]
	var tile: Vector2i = row["tile"]
	var before: int = int(entry["counts"]["worked"])

	_screen.land_works.set_improvement(_screen.model, tile, 2)
	_screen.land_works.set_prospected(_screen.player_faction, _screen.model, tile)
	assert_true(
		_screen.civilian_layer.works_changed.is_connected(lens.refresh)
	)
	_screen.civilian_layer.refresh_works()

	var after: Dictionary = _entry(lens.survey, int(entry["id"]))
	assert_eq(int(after["counts"]["worked"]), before + 1)
	assert_eq(int(_row(after, tile)["level"]), 2)


func test_a_working_estate_animates_the_lens() -> void:
	MapPlayInput.set_lens(_screen.play, true)
	var lens: ResourceLens = _screen.play.lens
	var found: Array = _owned_vacant(lens.survey)
	assert_false(found.is_empty())
	var entry: Dictionary = found[0]
	var tile: Vector2i = (found[1] as Dictionary)["tile"]
	var unit: CivilianState = _screen.civilian_layer.add_unit(
		_screen.player_faction, "builder", tile
	)
	unit.start_work("build_improvement", tile, 2)
	_screen.civilian_layer.refresh_works()
	assert_true(lens._animating)
	var row: Dictionary = _row(_entry(lens.survey, int(entry["id"])), tile)
	assert_eq(String(row["status"]), "building")
	lens._reveal = 1.0
	lens.queue_redraw()
	await get_tree().process_frame


func test_region_switch_rebuilds_the_survey_lens() -> void:
	MapPlayInput.set_lens(_screen.play, true)
	_screen._cycle_region()
	assert_eq(_screen.play.lens.model, _screen.model)
	assert_eq(int(_screen.play.lens.model.region_id), FactionCatalog.NEW_WORLD)
	assert_true(_screen.play.lens.survey.has("counts"))


func test_hover_reports_the_estate_line_while_the_lens_is_on() -> void:
	MapPlayInput.set_lens(_screen.play, true)
	var entry: Dictionary = _visible_estate_entry(_screen.play.lens.survey)
	assert_false(entry.is_empty())
	var world: Vector2 = Vector2(entry["center"]) * MapScreen.TILE_SIZE
	_screen.camera.focus_on(world, 0.8, true)
	_screen.camera._process(0.016)
	var screen_point: Vector2 = CameraMath.world_to_screen(
		_screen.camera.position, _screen.camera.zoom.x, world,
		_screen.camera.viewport_size()
	)
	MapPlayInput.update_hover(_screen.play, screen_point)
	assert_true(_screen.hud._tooltip_label.text.contains("\n"))
	assert_true(_screen.hud._tooltip_label.text.contains(String(entry["summary"])))
	assert_eq(_screen.play.lens.hover_province, int(entry["id"]))
	MapPlayInput.clear_hover(_screen.play)
	assert_eq(_screen.play.lens.hover_province, -1)


func test_plates_are_packed_without_overlap_and_anchor_on_land() -> void:
	MapPlayInput.set_lens(_screen.play, true)
	var lens: ResourceLens = _screen.play.lens
	var rects: Dictionary = lens._rects
	assert_false(rects.is_empty())
	var ids: Array = rects.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			assert_false((rects[ids[i]] as Rect2).intersects(rects[ids[j]]))
	assert_eq(lens.hit_test((rects[ids[0]] as Rect2).get_center()), int(ids[0]))
	assert_eq(lens.hit_test(Vector2(-9999, -9999)), -1)
	for raw: Variant in lens.survey["provinces"]:
		var anchor: Vector2 = (raw as Dictionary)["anchor"]
		assert_true(_screen.model.is_land(int(anchor.x), int(anchor.y)))


func test_tapping_a_plate_selects_its_province() -> void:
	MapPlayInput.set_lens(_screen.play, true)
	var lens: ResourceLens = _screen.play.lens
	for raw: Variant in lens.survey["provinces"]:
		var id: int = int((raw as Dictionary)["id"])
		var point: Vector2 = (lens._rects[id] as Rect2).get_center()
		if _screen.civilian_layer.unit_at(point) != null:
			continue
		if _screen.army_layer.army_at(point) != null:
			continue
		MapPlayInput.on_tapped(_screen.play, point)
		assert_eq(_screen.selected_province, id)
		return
	assert_true(false, "no clear survey plaque to tap")


func test_summary_for_an_unsurveyed_province_is_empty() -> void:
	MapPlayInput.set_lens(_screen.play, true)
	assert_eq(_screen.play.lens.summary_for(9999), "")


func test_road_ink_draws_linked_cut_rail_and_fogged_strokes() -> void:
	var probe := _RoadInkProbe.new()
	# Each reading takes a turn as well as a straight, so the sleeper and dash
	# walks are exercised over a bend and not only a single chord.
	probe.segments = [
		{"a": Vector2i(1, 1), "b": Vector2i(2, 1), "linked": true, "rail": false},
		{"a": Vector2i(2, 1), "b": Vector2i(3, 1), "linked": true, "rail": true},
		{"a": Vector2i(3, 1), "b": Vector2i(3, 2), "linked": true, "rail": true},
		{
			"a": Vector2i(1, 2),
			"b": Vector2i(2, 2),
			"linked": false,
			"rail": false,
			"fogged": true,
		},
		{
			"a": Vector2i(2, 2),
			"b": Vector2i(2, 3),
			"linked": false,
			"rail": false,
			"fogged": true,
		},
	]
	add_child(probe)
	probe.queue_redraw()
	await get_tree().process_frame
	assert_eq(probe.segments.size(), 5)
	probe.queue_free()


## A road that turns is one inked curve, not two tile-centre chords: the corner
## is cut, so the stroke never passes through the grid vertex (REQ-P1-03).
func test_a_turning_road_inks_as_one_curve_with_a_cut_corner() -> void:
	var runs: Array[Dictionary] = RoadInk.ink_paths([
		{"a": Vector2i(1, 1), "b": Vector2i(2, 1), "linked": true, "rail": false},
		{"a": Vector2i(2, 1), "b": Vector2i(2, 2), "linked": true, "rail": false},
	])
	assert_eq(runs.size(), 1, "a linked turn is one run, not one stroke a tile")
	var points: PackedVector2Array = runs[0]["points"]
	assert_gt(points.size(), 4, "the corner is subdivided, not a hard vertex")
	var corner: Vector2 = MapGeo.tile_center(2, 1, RoadInk.TILE_SIZE)
	var nearest: float = INF
	for point: Vector2 in points:
		nearest = minf(nearest, point.distance_to(corner))
	assert_gt(nearest, 1.5, "the stroke cuts the corner instead of touching the vertex")


## A long straight run bows off the tile-centre line, so the network does not
## read as a ruled grid (REQ-P1-03).
func test_a_straight_road_bows_off_the_tile_centres() -> void:
	var runs: Array[Dictionary] = RoadInk.ink_paths([
		{"a": Vector2i(1, 1), "b": Vector2i(2, 1), "linked": true, "rail": false},
		{"a": Vector2i(2, 1), "b": Vector2i(3, 1), "linked": true, "rail": false},
		{"a": Vector2i(3, 1), "b": Vector2i(4, 1), "linked": true, "rail": false},
	])
	assert_eq(runs.size(), 1)
	var points: PackedVector2Array = runs[0]["points"]
	var a: Vector2 = MapGeo.tile_center(1, 1, RoadInk.TILE_SIZE)
	var b: Vector2 = MapGeo.tile_center(4, 1, RoadInk.TILE_SIZE)
	var bow: float = 0.0
	for point: Vector2 in points:
		bow = maxf(bow, absf((b - a).cross(point - a) / a.distance_to(b)))
	assert_gt(bow, 0.3, "the stroke bows off the straight chord")
	assert_lt(bow, 3.0, "and stays on its own tiles")


## Two runs of different readings still meet at the tile centre they share, so a
## road never breaks where a railroad begins.
func test_runs_of_different_readings_still_meet_at_a_junction() -> void:
	var runs: Array[Dictionary] = RoadInk.ink_paths([
		{"a": Vector2i(1, 1), "b": Vector2i(2, 1), "linked": true, "rail": false},
		{"a": Vector2i(2, 1), "b": Vector2i(3, 1), "linked": true, "rail": true},
	])
	assert_eq(runs.size(), 2, "a road and a railroad keep their own strokes")
	var road: PackedVector2Array = runs[0]["points"]
	var rail: PackedVector2Array = runs[1]["points"]
	assert_almost_eq(road[road.size() - 1].distance_to(rail[0]), 0.0, 0.01)


## Ground still to read is a count on the plate, so a province says how many
## tiles an Explorer could prospect instead of only that some exist (#698).
func test_an_unsurveyed_province_carries_its_prospect_count() -> void:
	MapPlayInput.set_lens(_screen.play, true)
	var lens: ResourceLens = _screen.play.lens
	var found: Dictionary = _first_with_ground(lens)
	if found.is_empty():
		return
	assert_true(String(found["summary"]).contains("unsurveyed"))
	var plain: float = (
		ResourceLens.PLATE_PAD * 2.0 + ResourceLens.RIBBON
		+ float((found["types"] as Array).size()) * ResourceLens.TYPE_COL
	)
	assert_almost_eq(lens._plate_size(found).x, plain + ResourceLens.CUE_W, 0.01)
	found["unsurveyed"] = 0
	assert_almost_eq(lens._plate_size(found).x, plain, 0.01, "no ground, no cue column")
	found["unsurveyed"] = 1
	lens._reveal = 1.0
	lens.queue_redraw()
	await get_tree().process_frame


## The plate draws a column per type in every estate state, the badge inks amber
## when a kind is only partly linked, and the key names the Explorer cue.
func test_a_plate_draws_every_type_state_and_the_explorer_cue() -> void:
	MapPlayInput.set_lens(_screen.play, true)
	var lens: ResourceLens = _screen.play.lens
	var first: Dictionary = _crafted_plate(
		1, ["producing", "vacant", "foreign", "disconnected"], 3
	)
	var second: Dictionary = _crafted_plate(2, ["building", "maxed", "producing", "vacant"])
	# One kind, one estate cut off: the reading a single-estate column never makes.
	var third: Dictionary = _crafted_plate(3, ["producing", "disconnected"], 0, "tree")
	var saved: Dictionary = lens.survey
	lens._reveal = 1.0
	lens.survey = {"provinces": [first, second, third], "counts": {}, "routes": []}
	lens._layout_plates()
	lens.queue_redraw()
	await get_tree().process_frame
	assert_eq((lens._plate_rect(first).size as Vector2).y, ResourceLens.PLATE_H)
	assert_eq(String(first["types"][0]["status"]), "producing")
	assert_eq(String(second["types"][0]["status"]), "building")
	assert_eq(String(third["types"][0]["badge"]), "2/1/2", "one of the two is cut off")
	lens.survey = saved
	lens.refresh()
	var key: LensLegend = _screen.hud.lens_legend
	assert_true(key.is_survey())
	var named: bool = false
	for row: Dictionary in LensLegend.SURVEY_ROWS:
		if String(row["status"]) == "survey":
			named = String(row["text"]).contains("Explorer")
	assert_true(named, "the key still says an Explorer reads the ground")
	key.queue_redraw()
	await get_tree().process_frame


## The first plate with ground still to read (empty when the chart is read).
func _first_with_ground(lens: ResourceLens) -> Dictionary:
	for raw: Variant in lens.survey.get("provinces", []):
		if int((raw as Dictionary).get("unsurveyed", 0)) > 0:
			return raw
	return {}


## A plate holding one estate of every kind in the states a case asks for.
## `kind` pins every row to one emblem so a case can build a multi-estate column.
func _crafted_plate(
	province_id: int, statuses: Array, unsurveyed: int = 0, kind: String = ""
) -> Dictionary:
	var rows: Array[Dictionary] = []
	for i in statuses.size():
		var icon: String = kind if not kind.is_empty() else (
			ResourceTypes.ORDER[i % ResourceTypes.ORDER.size()]
		)
		rows.append(_crafted_row(icon, String(statuses[i]), i))
	var entry: Dictionary = {
		"id": province_id, "name": "Fixture", "center": Vector2(6, 6),
		"anchor": Vector2(6, 6), "owner": _screen.player_faction, "capital": false,
		"charted": VisibilityModel.Level.FULLY_VISIBLE, "rows": rows,
		"counts": {}, "output": {}, "output_text": "", "tile_owners": [],
		"unsurveyed": unsurveyed,
	}
	entry["types"] = ResourceTypes.rows(entry)
	entry["summary"] = ResourceSurvey.summary_text(entry)
	return entry


## One crafted estate row in the state a case asks for.
func _crafted_row(kind: String, status: String, index: int) -> Dictionary:
	var maxed: bool = status == "maxed"
	return {
		"icon": kind, "ours": status != "foreign", "status": status,
		"level": ImprovementCatalog.MAX_LEVEL if maxed else (
			1 if status in ["producing", "disconnected"] else 0
		),
		"connected": status != "disconnected", "tile": Vector2i(index, index),
		"commodity": "timber",
	}


## Every resource kind owns its commodity ink, so the lens never paints a coin,
## a sheaf, a stone and a tree the same hue (REQ-P1-08).
func test_each_resource_kind_owns_a_distinct_commodity_ink() -> void:
	var seen: Array[Color] = []
	for kind: String in ["tree", "ore", "coin", "wheat"]:
		var ink: Color = Palette.resource_ink(kind)
		assert_false(seen.has(ink), "%s must not borrow another kind's ink" % kind)
		seen.append(ink)
	assert_ne(Palette.resource_ink("coin"), Palette.GOLD, "coined gold is its own gold")
	assert_eq(
		Palette.resource_ink("cartload"), Palette.GOLD,
		"an unknown kind keeps the old gold mark (REQ-P3-02)"
	)


## Status inks ring the emblem and never repaint its fill; only a foreign
## holding dims the commodity, and the hue still reads through the grey.
func test_status_ink_rings_the_emblem_without_erasing_the_commodity() -> void:
	for status: String in ["producing", "maxed", "vacant", "building", "disconnected"]:
		assert_eq(
			Palette.emblem_ink("wheat", status), Palette.resource_ink("wheat"),
			"%s must not repaint the sheaf" % status
		)
	var iron: Color = Palette.emblem_ink("ore", "foreign")
	assert_ne(iron, Palette.resource_ink("ore"), "a foreign holding still dims the mark")
	assert_ne(iron, Palette.SURVEY_FOREIGN, "and never wipes the kind to plain grey")
	var straw: Color = Palette.emblem_ink("wheat", "foreign_worked")
	assert_gt(straw.r, iron.r, "straw stays warmer than iron under the same tint")
	assert_gt(iron.b, straw.b, "iron stays cooler than straw under the same tint")


func test_all_four_emblems_draw_in_their_commodity_ink() -> void:
	var probe := _EmblemProbe.new()
	add_child(probe)
	probe.queue_redraw()
	await get_tree().process_frame
	assert_eq(probe.kinds.size(), 4)
	probe.queue_free()


## Drawing is only legal inside `_draw`; the probe hosts every emblem for
## coverage of the four inks (the lens only shows the kinds a chart seeds).
class _EmblemProbe extends Node2D:
	var kinds: Array[String] = ["tree", "ore", "coin", "wheat"]

	func _draw() -> void:
		for i in kinds.size():
			MapGlyphs.resource(
				self, kinds[i], Vector2(float(i) * 20.0, 0), 14.0,
				Palette.resource_ink(kinds[i])
			)


## Drawing is only legal inside `_draw`; the probe hosts the ink for coverage.
class _RoadInkProbe extends Node2D:
	var segments: Array = []

	func _draw() -> void:
		RoadInk.draw_routes(self, segments, 1.0)


# --- helpers -----------------------------------------------------------------


func _entry(survey: Dictionary, province_id: int) -> Dictionary:
	for raw: Variant in survey["provinces"]:
		var entry: Dictionary = raw
		if int(entry["id"]) == province_id:
			return entry
	return {}


func _row(entry: Dictionary, tile: Vector2i) -> Dictionary:
	for raw: Variant in entry.get("rows", []):
		var row: Dictionary = raw
		if row["tile"] == tile:
			return row
	return {}


func _owned_vacant(survey: Dictionary) -> Array:
	for raw: Variant in survey["provinces"]:
		var entry: Dictionary = raw
		for raw_row: Variant in entry["rows"]:
			var row: Dictionary = raw_row
			if bool(row["ours"]) and int(row["level"]) == 0:
				return [entry, row]
	return []


func _visible_estate_entry(survey: Dictionary) -> Dictionary:
	for raw: Variant in survey["provinces"]:
		var entry: Dictionary = raw
		var center: Vector2 = entry["center"]
		var tile := Vector2i(int(center.x), int(center.y))
		if (
			_screen.visibility != null
			and _screen.visibility.level_at(tile.x, tile.y) != VisibilityModel.Level.UNKNOWN
		):
			return entry
	return {}


## --- the political wash (P) --------------------------------------------------


func test_toggle_raises_the_key_and_builds_a_survey() -> void:
	var lens: DiplomacyLens = _screen.play.diplomacy_lens
	assert_not_null(lens)
	assert_false(lens.active)
	assert_false(_screen.hud.lens_legend.visible)

	MapPlayInput.set_diplomacy_lens(_screen.play, true)
	assert_true(lens.active)
	assert_true(_screen.hud.lens_legend.visible)
	assert_eq(_screen.hud.lens_legend.kind, LensLegend.KIND_DIPLOMACY)
	assert_true(_screen.hud.lens_seal.button_pressed)
	assert_eq(_screen.hud.lens_seal.active_kind, LensLegend.KIND_DIPLOMACY)
	assert_gt(int(lens.survey["tiles"]["self"]), 0)
	assert_almost_eq(_screen.civilian_layer.modulate.a, 0.22, 0.001)

	lens._reveal = 1.0
	lens.queue_redraw()
	await get_tree().process_frame

	MapPlayInput.set_diplomacy_lens(_screen.play, false)
	assert_false(lens.active)
	assert_false(_screen.hud.lens_legend.visible)
	assert_false(_screen.hud.lens_seal.button_pressed)
	assert_almost_eq(_screen.civilian_layer.modulate.a, 1.0, 0.001)


## The two lenses are readings of the same map: raising one lowers the other,
## so the key can never show two legends at once.
func test_the_two_lenses_are_exclusive() -> void:
	MapPlayInput.set_lens(_screen.play, true)
	assert_true(_screen.play.lens.active)
	assert_eq(_screen.hud.lens_legend.kind, LensLegend.KIND_SURVEY)

	MapPlayInput.set_diplomacy_lens(_screen.play, true)
	assert_false(_screen.play.lens.active)
	assert_true(_screen.play.diplomacy_lens.active)
	assert_true(_screen.hud.lens_seal.button_pressed, "the one seal stays raised")
	assert_eq(_screen.hud.lens_seal.active_kind, LensLegend.KIND_DIPLOMACY)
	assert_eq(_screen.hud.lens_legend.kind, LensLegend.KIND_DIPLOMACY)
	assert_almost_eq(_screen.civilian_layer.modulate.a, 0.22, 0.001)

	MapPlayInput.set_lens(_screen.play, true)
	assert_false(_screen.play.diplomacy_lens.active)
	assert_eq(_screen.hud.lens_seal.active_kind, LensLegend.KIND_SURVEY)
	assert_eq(_screen.hud.lens_legend.kind, LensLegend.KIND_SURVEY)


func test_a_declaration_of_war_repaints_the_wash() -> void:
	MapPlayInput.set_diplomacy_lens(_screen.play, true)
	var owner: int = _foreign_owner()
	assert_true(owner >= 0)
	var relation: DiplomacyRelation = _screen.play.diplomacy.ensure_relation(
		_screen.player_faction, owner, _screen.play.turn
	)
	relation.set_score(50.0)
	MapPlayLens.mount_diplomacy(_screen.play)
	assert_eq(
		DiplomacySurvey.band_for(
			_screen.play.diplomacy, _screen.player_faction, owner
		),
		DiplomacySurvey.BAND_NEUTRAL
	)

	relation.at_war = true
	relation.normalize()
	MapPlayLens.mount_diplomacy(_screen.play)
	var entry: Dictionary = _entry(_screen.play.diplomacy_lens.survey, _province_of(owner))
	assert_eq(String(entry["band"]), DiplomacySurvey.BAND_WAR)
	assert_gt(int(_screen.play.diplomacy_lens.survey["tiles"]["war"]), 0)


func test_region_switch_rebuilds_the_political_wash() -> void:
	MapPlayInput.set_diplomacy_lens(_screen.play, true)
	_screen._cycle_region()
	assert_eq(_screen.play.diplomacy_lens.model, _screen.model)
	assert_eq(int(_screen.play.diplomacy_lens.model.region_id), FactionCatalog.NEW_WORLD)
	assert_true(_screen.play.diplomacy_lens.survey.has("runs"))
	# The New World starts unknown, so the wash paints nothing yet.
	assert_eq(int(_screen.play.diplomacy_lens.survey["counts"]["neutral"]), 0)

	# Charting one province makes it readable as neutral (no court yet).
	var province: ProvinceState = _screen.model.provinces[0]
	_screen.visibility.reveal_province(province.id)
	MapPlayLens.mount_diplomacy(_screen.play)
	assert_false(
		_entry(_screen.play.diplomacy_lens.survey, province.id).is_empty()
	)


func test_hover_reports_the_standing_while_the_lens_is_on() -> void:
	MapPlayInput.set_diplomacy_lens(_screen.play, true)
	var entry: Dictionary = _visible_band_entry(_screen.play.diplomacy_lens.survey)
	assert_false(entry.is_empty())
	var province: ProvinceState = _screen.model.province_data(int(entry["id"]))
	var world: Vector2 = province.center * MapScreen.TILE_SIZE
	_screen.camera.focus_on(world, 0.8, true)
	_screen.camera._process(0.016)
	var screen_point: Vector2 = CameraMath.world_to_screen(
		_screen.camera.position, _screen.camera.zoom.x, world,
		_screen.camera.viewport_size()
	)
	MapPlayInput.update_hover(_screen.play, screen_point)
	assert_true(_screen.hud._tooltip_label.text.contains("Standing: "))
	assert_true(_screen.hud._tooltip_label.text.contains(String(entry["standing"])))


## Raising the lens must refresh a tooltip that is already open: a stationary
## cursor is the common case, and the pre-lens line has no standing.
func test_the_hover_line_appears_when_the_lens_is_raised() -> void:
	var entry: Dictionary = _visible_band_entry(
		DiplomacySurvey.snapshot(
			_screen.model, _screen.play.diplomacy, _screen.player_faction,
			_screen.visibility
		)
	)
	assert_false(entry.is_empty())
	var province: ProvinceState = _screen.model.province_data(int(entry["id"]))
	var point: Vector2 = _screen_point(province.center)
	MapPlayInput.update_hover(_screen.play, point)
	assert_false(_screen.hud._tooltip_label.text.contains("Standing:"))

	MapPlayInput.set_diplomacy_lens(_screen.play, true)
	MapPlayInput.update_hover(_screen.play, point)
	assert_true(_screen.hud._tooltip_label.text.contains("Standing: "))


func test_the_key_action_binds_the_p_and_l_keys() -> void:
	InputActions.ensure_actions()
	assert_true(InputMap.has_action(InputActions.DIPLOMACY_LENS))
	assert_true(InputMap.has_action(InputActions.LENS))
	assert_ne(InputActions.DIPLOMACY_LENS, InputActions.LENS)


## P toggles the political wash from the keyboard, like L does the survey.
func test_the_p_key_toggles_the_lens() -> void:
	MapPlayInput.set_diplomacy_lens(_screen.play, true)
	var event := InputEventKey.new()
	event.physical_keycode = KEY_P
	event.pressed = true
	_screen._unhandled_input(event)
	assert_false(_screen.play.diplomacy_lens.active)
	assert_false(_screen.hud.lens_legend.visible)


## A political map refresh (Join Empire) rebuilds the wash with the new owners.
func test_a_political_refresh_rebuilds_the_lens() -> void:
	MapPlayInput.set_diplomacy_lens(_screen.play, true)
	var before: int = int(_screen.play.diplomacy_lens.survey["tiles"]["self"])
	assert_gt(before, 0)
	_screen.refresh_political_map()
	assert_eq(_screen.play.diplomacy_lens.model, _screen.model)
	assert_eq(int(_screen.play.diplomacy_lens.survey["tiles"]["self"]), before)


# --- helpers -----------------------------------------------------------------


func _foreign_owner() -> int:
	for province: ProvinceState in _screen.model.provinces:
		if (
			province.owner != _screen.player_faction
			and province.owner != MapModel.NO_ID
		):
			return province.owner
	return MapModel.NO_ID


func _province_of(owner: int) -> int:
	for province: ProvinceState in _screen.model.provinces:
		if province.owner == owner:
			return province.id
	return -1


func _visible_band_entry(survey: Dictionary) -> Dictionary:
	for raw: Variant in survey.get("provinces", []):
		var entry: Dictionary = raw
		if int(entry["charted"]) != VisibilityModel.Level.UNKNOWN:
			return entry
	return {}


func _screen_point(world_in_tiles: Vector2) -> Vector2:
	var world: Vector2 = world_in_tiles * MapScreen.TILE_SIZE
	_screen.camera.focus_on(world, 0.8, true)
	_screen.camera._process(0.016)
	return CameraMath.world_to_screen(
		_screen.camera.position, _screen.camera.zoom.x, world,
		_screen.camera.viewport_size()
	)


## --- the defence reading (K) -------------------------------------------------


func test_the_key_action_binds_the_k_key() -> void:
	InputActions.ensure_actions()
	assert_true(InputMap.has_action(InputActions.DEFENCE_LENS))
	assert_ne(InputActions.DEFENCE_LENS, InputActions.LENS)
	assert_ne(InputActions.DEFENCE_LENS, InputActions.DIPLOMACY_LENS)
	assert_ne(InputActions.DEFENCE_LENS, InputActions.CROWN_LENS)
	# The key still lands on the bar's one seal, which raises its reading.
	var event := InputEventAction.new()
	event.action = InputActions.DEFENCE_LENS
	event.pressed = true
	_screen.hud.lens_seal._shortcut_input(event)
	assert_true(_screen.play.defence_lens.active, "K names the defence reading")
	MapPlayInput.set_defence_lens(_screen.play, false)


func test_toggle_key_exclusivity_and_draw() -> void:
	var lens: DefenceLens = _screen.play.defence_lens
	assert_not_null(lens)
	assert_false(lens.active)

	MapPlayInput.set_defence_lens(_screen.play, true)
	assert_true(lens.active)
	assert_true(_screen.hud.lens_legend.visible)
	assert_eq(_screen.hud.lens_legend.kind, LensLegend.KIND_DEFENCE)
	assert_true(_screen.hud.lens_seal.button_pressed)
	assert_eq(_screen.hud.lens_seal.active_kind, LensLegend.KIND_DEFENCE)
	assert_gt((lens.survey["provinces"] as Array).size(), 0)
	assert_almost_eq(_screen.civilian_layer.modulate.a, 0.22, 0.001)

	# Every other reading lowers when this one is raised, and vice versa.
	MapPlayInput.set_lens(_screen.play, true)
	assert_true(_screen.play.lens.active)
	assert_false(lens.active)
	MapPlayInput.set_crown_lens(_screen.play, true)
	assert_true(_screen.play.crown_lens.active)
	assert_false(_screen.play.lens.active)
	MapPlayInput.set_defence_lens(_screen.play, true)
	assert_true(lens.active)
	assert_false(_screen.play.crown_lens.active)
	assert_eq(_screen.hud.lens_legend.kind, LensLegend.KIND_DEFENCE)
	assert_eq(_screen.hud.lens_seal.active_kind, LensLegend.KIND_DEFENCE)

	lens._reveal = 1.0
	lens.queue_redraw()
	await get_tree().process_frame

	MapPlayInput.set_defence_lens(_screen.play, false)
	assert_false(lens.active)
	assert_false(_screen.hud.lens_legend.visible)
	assert_false(_screen.hud.lens_seal.button_pressed)
	assert_almost_eq(_screen.civilian_layer.modulate.a, 1.0, 0.001)


func test_the_reading_names_the_crown_garrison_and_its_wall() -> void:
	MapPlayInput.set_defence_lens(_screen.play, true)
	var lens: DefenceLens = _screen.play.defence_lens
	var province: ProvinceState = _crown_garrisoned()
	assert_true(province != null, "the crown keeps a garrison on the fixture map")
	var entry: Dictionary = _entry(lens.survey, province.id)
	assert_gt(int(entry["strength"]), 0)
	assert_gt(int(entry["regiments"]), 0)
	var summary: String = lens.summary_for(province.id)
	assert_true(summary.contains("strength"), summary)


## A march moves a garrison: the lens reads the roster again on the signal, not
## on a frame poll.
func test_a_roster_change_repaints_the_reading() -> void:
	MapPlayInput.set_defence_lens(_screen.play, true)
	var lens: DefenceLens = _screen.play.defence_lens
	var army: ArmyState = _first_army_with_regiments()
	assert_true(army != null)
	var before: int = int(_entry(lens.survey, army.province)["regiments"])
	army.remove_regiment(army.regiments[0])
	_screen.army_layer.army_moved.emit(army, {})
	var after: int = int(_entry(lens.survey, army.province)["regiments"])
	assert_eq(after, before - 1)


## A tap on a slip selects the province it belongs to, even when the slip was
## packed away from the province centre.
func test_a_tap_on_a_slip_selects_its_province() -> void:
	MapPlayInput.set_defence_lens(_screen.play, true)
	var lens: DefenceLens = _screen.play.defence_lens
	var province: ProvinceState = _unowned_slip()
	assert_true(province != null, "the fixture map offers a foreign slip")
	var rect: Rect2 = lens._rects[province.id]
	MapPlayInput.on_tapped(_screen.play, rect.get_center())
	assert_eq(_screen.play.selected_province, province.id)


func test_the_legend_carries_every_band() -> void:
	assert_eq(LensLegend.DEFENCE_ROWS.size(), DefenceSurvey.BANDS.size())
	_screen.hud.lens_legend.set_kind(LensLegend.KIND_DEFENCE)
	_screen.hud.lens_legend.queue_redraw()
	await get_tree().process_frame
	assert_eq(_screen.hud.lens_legend.kind, LensLegend.KIND_DEFENCE)


## The hover line carries the reading, and only while the lens is up.
func test_hover_reports_the_defence_while_the_lens_is_on() -> void:
	var province: ProvinceState = _crown_garrisoned()
	assert_true(province != null)
	var world: Vector2 = province.center * MapScreen.TILE_SIZE
	var point: Vector2 = CameraMath.world_to_screen(
		_screen.camera.position, _screen.camera.zoom.x, world,
		_screen.camera.viewport_size()
	)
	MapPlayInput.update_hover(_screen.play, point)
	assert_false(_screen.hud._tooltip_label.text.contains("Defence:"))
	MapPlayInput.set_defence_lens(_screen.play, true)
	MapPlayInput.update_hover(_screen.play, point)
	assert_true(_screen.hud._tooltip_label.text.contains("Defence: "))


# --- fixture helpers ---------------------------------------------------------


func _crown_garrisoned() -> ProvinceState:
	for province: ProvinceState in _screen.model.provinces:
		if province.owner != _screen.player_faction:
			continue
		if not _screen.army_layer.armies_in(province.id, _screen.player_faction).is_empty():
			return province
	return null


func _first_army_with_regiments() -> ArmyState:
	for raw: Variant in _screen.army_layer.regions.value(_screen.model.region_id, []):
		var army: ArmyState = raw
		if army.owner == _screen.player_faction and not army.regiments.is_empty():
			return army
	return null


## A charted province the crown does not own and keeps no unit in, so the tap
## can only resolve through the slip.
func _unowned_slip() -> ProvinceState:
	var lens: DefenceLens = _screen.play.defence_lens
	for province: ProvinceState in _screen.model.provinces:
		if province.owner == _screen.player_faction or not lens._rects.has(province.id):
			continue
		if _screen.army_layer.army_at(lens._rects[province.id].get_center()) != null:
			continue
		if _screen.civilian_layer.unit_at(lens._rects[province.id].get_center()) != null:
			continue
		return province
	return null

# --- defence_survey ---
## Defence projection for the military lens: a province is banded by its wall
## first and its garrison second, the garrison is the published order of battle
## (FPN + FPM, no medals and no wounds) of the province's owner, and ground the
## crown has not charted never reaches the reading.

const WIDTH: int = 12
const HEIGHT: int = 4
const PLAYER: int = FactionCatalog.PLAYER_FACTION
const RIVAL: int = 3

var _model: MapModel = null
var _armies: Array[ArmyState] = []


func _setup_defence_survey() -> void:
	_model = _build()
	_armies = []


## Four provinces, three columns each: the crown's open ground, a garrisoned
## province in the open, a rival's stone wall and the crown's modern citadel.
func _build() -> MapModel:
	var model := MapModel.new()
	model.setup(WIDTH, HEIGHT)
	var groups: Dictionary = {0: [], 1: [], 2: [], 3: []}
	for y in HEIGHT:
		for x in WIDTH:
			var sea: bool = y == HEIGHT - 1
			model.terrain[model.index_of(x, y)] = (
				MapModel.Terrain.OCEAN if sea else MapModel.Terrain.PLAINS
			)
			if sea:
				model.sea_zone[model.index_of(x, y)] = 0
				continue
			var province_id: int = mini(x / 3, 3)
			model.province[model.index_of(x, y)] = province_id
			(groups[province_id] as Array).append(Vector2i(x, y))
	var names: Array[String] = ["Sevilla", "Córdoba", "Évora", "Lisboa"]
	var owners: Array[int] = [PLAYER, PLAYER, RIVAL, PLAYER]
	var forts: Array[int] = [0, 0, 2, 3]
	var provinces: Array[ProvinceState] = []
	for province_id in 4:
		var tiles: Array[Vector2i] = []
		for raw: Variant in groups[province_id]:
			tiles.append(raw as Vector2i)
		var province := ProvinceState.create(
			province_id, names[province_id], tiles, Vector2(tiles[0]),
			tiles.size(), owners[province_id], province_id == 0
		)
		province.fort_level = forts[province_id]
		provinces.append(province)
	provinces[1].hospital_level = 1
	model.provinces = provinces
	return model


func _army(owner: int, province: int, types: Array[String]) -> ArmyState:
	var army: ArmyState = ArmyState.muster(
		_armies.size() + 1, owner, province, false, types, 1
	)
	_armies.append(army)
	return army


func _snapshot(visibility: VisibilityModel = null) -> Dictionary:
	return DefenceSurvey.snapshot(_model, _armies, visibility, PLAYER)


func defence_survey_entry(survey: Dictionary, province_id: int) -> Dictionary:
	for raw: Variant in survey.get("provinces", []):
		var entry: Dictionary = raw
		if int(entry["id"]) == province_id:
			return entry
	return {}


func test_the_wall_outranks_the_garrison() -> void:
	_setup_defence_survey()
	assert_eq(DefenceSurvey.band_for(0, 0), DefenceSurvey.BAND_OPEN)
	assert_eq(DefenceSurvey.band_for(0, 3), DefenceSurvey.BAND_HELD)
	assert_eq(DefenceSurvey.band_for(1, 0), DefenceSurvey.BAND_WALLED)
	assert_eq(DefenceSurvey.band_for(2, 4), DefenceSurvey.BAND_WALLED)
	assert_eq(DefenceSurvey.band_for(3, 0), DefenceSurvey.BAND_CITADEL)


func test_a_garrison_is_read_on_the_published_order_of_battle() -> void:
	_setup_defence_survey()
	var army: ArmyState = _army(PLAYER, 1, ["musketeers", "pikemen"])
	# Chevrons and wounds are the crown's own reading, not the published one.
	army.regiment_medals["unit_1"] = 4
	army.regiment_health["unit_1"] = 10
	var survey: Dictionary = _snapshot()
	var held: Dictionary = defence_survey_entry(survey, 1)
	assert_eq(int(held["strength"]), 14, "9 + 5, with no medal multiplier")
	assert_eq(int(held["regiments"]), 2)
	assert_eq(String(held["band"]), DefenceSurvey.BAND_HELD)
	assert_eq(int(held["hospital"]), 1)


func test_an_empty_province_reads_open_and_a_wall_reads_walled() -> void:
	_setup_defence_survey()
	_army(PLAYER, 3, ["guards"])
	var survey: Dictionary = _snapshot()
	assert_eq(String(defence_survey_entry(survey, 0)["band"]), DefenceSurvey.BAND_OPEN)
	assert_eq(int(defence_survey_entry(survey, 0)["strength"]), 0)
	var citadel: Dictionary = defence_survey_entry(survey, 3)
	assert_eq(String(citadel["band"]), DefenceSurvey.BAND_CITADEL)
	assert_eq(int(citadel["fort"]), 3)
	assert_eq(int(citadel["guns"]), 3)
	var rival: Dictionary = defence_survey_entry(survey, 2)
	assert_eq(String(rival["band"]), DefenceSurvey.BAND_WALLED)
	assert_eq(int(rival["guns"]), 2)


## The garrison is the owner's: a foreign host ashore is a contested ground,
## never part of the province's defence.
func test_a_foreign_host_is_flagged_and_never_counted_as_the_garrison() -> void:
	_setup_defence_survey()
	_army(PLAYER, 2, ["musketeers"])
	var rival: Dictionary = defence_survey_entry(_snapshot(), 2)
	assert_true(bool(rival["foreign"]))
	assert_eq(int(rival["strength"]), 0)
	assert_eq(int(rival["regiments"]), 0)


func test_counts_and_the_crown_totals() -> void:
	_setup_defence_survey()
	_army(PLAYER, 1, ["musketeers"])
	_army(PLAYER, 3, ["pikemen"])
	var survey: Dictionary = _snapshot()
	var counts: Dictionary = survey["counts"]
	assert_eq(int(counts[DefenceSurvey.BAND_OPEN]), 1)
	assert_eq(int(counts[DefenceSurvey.BAND_HELD]), 1)
	assert_eq(int(counts[DefenceSurvey.BAND_WALLED]), 1)
	assert_eq(int(counts[DefenceSurvey.BAND_CITADEL]), 1)
	var totals: Dictionary = survey["totals"]
	assert_eq(int(totals["provinces"]), 4)
	assert_eq(int(totals["undefended"]), 1, "Sevilla is the crown's only open province")
	assert_eq(int(totals["strength"]), 14, "9 + 5 over the crown's own garrisons")


func test_uncharted_ground_never_reaches_the_reading() -> void:
	_setup_defence_survey()
	_army(PLAYER, 1, ["musketeers"])
	var visibility := VisibilityModel.new()
	visibility.setup(_model, PLAYER)
	for tile: Vector2i in _model.provinces[0].tiles:
		visibility.lower_to(
			_model.index_of(tile.x, tile.y), VisibilityModel.Level.UNKNOWN
		)
	var survey: Dictionary = _snapshot(visibility)
	assert_true(defence_survey_entry(survey, 0).is_empty())
	assert_false(defence_survey_entry(survey, 1).is_empty())
	assert_eq(int(survey["totals"]["provinces"]), 3)


func test_the_hover_line_names_the_strength_the_wall_and_the_hospital() -> void:
	_setup_defence_survey()
	_army(PLAYER, 1, ["musketeers", "pikemen"])
	var held: Dictionary = defence_survey_entry(_snapshot(), 1)
	var text: String = DefenceSurvey.summary_text(held)
	assert_true(text.contains("14 strength"), text)
	assert_true(text.contains("2 regiments"), text)
	assert_true(text.contains("No wall"), text)
	assert_true(text.contains(HospitalRules.level_name(1)), text)
	var open_line: String = DefenceSurvey.summary_text(defence_survey_entry(_snapshot(), 0))
	assert_true(open_line.contains("No garrison"), open_line)
	assert_true(open_line.contains("No wall"), open_line)


func test_one_regiment_and_one_gun_read_in_the_singular() -> void:
	_setup_defence_survey()
	_army(PLAYER, 3, ["guards"])
	var text: String = DefenceSurvey.summary_text(defence_survey_entry(_snapshot(), 3))
	assert_true(text.contains("22 strength · 1 regiment"), text)
	assert_true(text.contains("Fort 3 (3 guns)"), text)


func test_an_embarked_army_defends_nothing() -> void:
	_setup_defence_survey()
	var army: ArmyState = _army(PLAYER, 1, ["musketeers"])
	army.embarked_fleet = 7
	var held: Dictionary = defence_survey_entry(_snapshot(), 1)
	assert_eq(int(held["strength"]), 0)
	assert_eq(String(held["band"]), DefenceSurvey.BAND_OPEN)


## --- the sea reading (H) -----------------------------------------------------


func test_the_key_action_binds_the_h_key() -> void:
	InputActions.ensure_actions()
	assert_true(InputMap.has_action(InputActions.SEA_LENS))
	assert_ne(InputActions.SEA_LENS, InputActions.LENS)
	assert_ne(InputActions.SEA_LENS, InputActions.DEFENCE_LENS)
	# The key lands on the bar's one seal, which raises its reading.
	var event := InputEventAction.new()
	event.action = InputActions.SEA_LENS
	event.pressed = true
	_screen.hud.lens_seal._shortcut_input(event)
	assert_true(_screen.play.sea_lens.active, "H names the sea reading")
	MapPlayInput.set_sea_lens(_screen.play, false)


func test_the_sea_reading_raises_its_key_and_survey() -> void:
	var lens: SeaLens = _screen.play.sea_lens
	assert_not_null(lens, "the chart mounts the sea lens")
	_sail_a_crown_squadron()
	MapPlayLens.mount_all(_screen.play)
	assert_false(lens.active)

	MapPlayInput.set_sea_lens(_screen.play, true)
	assert_true(lens.active)
	assert_true(_screen.hud.lens_legend.visible)
	assert_eq(_screen.hud.lens_legend.kind, LensLegend.KIND_SEA)
	assert_true(_screen.hud.lens_seal.button_pressed)
	assert_eq(_screen.hud.lens_seal.active_kind, LensLegend.KIND_SEA)
	assert_gt((lens.survey["zones"] as Array).size(), 0, "a squadron at sea reads")
	assert_almost_eq(_screen.civilian_layer.modulate.a, 0.22, 0.001)

	# The readings never stack: a peer takes this one down and is taken down by it.
	MapPlayInput.set_defence_lens(_screen.play, true)
	assert_true(_screen.play.defence_lens.active)
	assert_false(lens.active)
	MapPlayInput.set_sea_lens(_screen.play, true)
	assert_true(lens.active)
	assert_false(_screen.play.defence_lens.active)

	lens._reveal = 1.0
	lens.queue_redraw()
	await get_tree().process_frame

	MapPlayInput.set_sea_lens(_screen.play, false)
	assert_false(lens.active)
	assert_false(_screen.hud.lens_legend.visible)
	assert_almost_eq(_screen.civilian_layer.modulate.a, 1.0, 0.001)


func test_a_sail_repaints_the_sea_reading() -> void:
	var fleet: FleetState = _sail_a_crown_squadron()
	MapPlayLens.mount_all(_screen.play)
	var lens: SeaLens = _screen.play.sea_lens
	var before: int = fleet.sea_zone
	var next: int = _other_zone(before)
	var hulls: int = fleet.ship_count()
	var here: int = _own_hulls(lens.survey, before)
	var there: int = _own_hulls(lens.survey, next)
	assert_true(_has_zone(lens.survey, before), "the reading follows her water")
	fleet.sea_zone = next
	_screen.ship_layer.fleet_moved.emit(fleet, {})
	assert_true(_has_zone(lens.survey, next), "the new water is read")
	assert_eq(_own_hulls(lens.survey, next), there + hulls, "her hulls are counted there")
	assert_eq(_own_hulls(lens.survey, before), here - hulls, "and not where she was")


func test_hover_reports_the_sea_line_while_the_lens_is_on() -> void:
	var fleet: FleetState = _sail_a_crown_squadron()
	MapPlayLens.mount_all(_screen.play)
	MapPlayInput.set_sea_lens(_screen.play, true)
	var zone: SeaZoneState = _screen.model.sea_zone_data(fleet.sea_zone)
	var point: Vector2 = _screen_point(Vector2(zone.tiles[0]))
	MapPlayInput.update_hover(_screen.play, point)
	assert_true(
		_screen.hud._tooltip_label.text.contains("Ours "),
		"the hover names the squadron: " + _screen.hud._tooltip_label.text
	)
	MapPlayInput.set_sea_lens(_screen.play, false)


## Puts a crown squadron at sea in the water beside its capital, so the reading
## has a sail to read.
func _sail_a_crown_squadron() -> FleetState:
	var capital: int = _screen.play.capital_province
	var zones: Array[int] = NavalMovement.province_sea_zones(_screen.model, capital)
	var zone: int = zones[0] if not zones.is_empty() else 0
	for raw: Variant in _screen.ship_layer.fleets:
		var fleet: FleetState = raw
		if fleet.owner != _screen.player_faction or fleet.ship_count() <= 0:
			continue
		fleet.location = FleetState.Location.AT_SEA
		fleet.sea_zone = zone
		fleet.province = MapModel.NO_ID
		fleet.mission = FleetState.Mission.PATROL
		return fleet
	return null


## Our hulls the reading counts in one zone.
func _own_hulls(survey: Dictionary, zone_id: int) -> int:
	for raw: Variant in survey.get("zones", []):
		var entry: Dictionary = raw
		if int(entry["id"]) == zone_id:
			return int(entry["own_hulls"])
	return 0


func _has_zone(survey: Dictionary, zone_id: int) -> bool:
	for raw: Variant in survey.get("zones", []):
		if int((raw as Dictionary)["id"]) == zone_id:
			return true
	return false


func _other_zone(zone_id: int) -> int:
	for zone: SeaZoneState in _screen.model.sea_zones:
		if zone.id != zone_id:
			return zone.id
	return zone_id

# --- sea_survey ---
## Sea projection for the water reading: a zone is banded by who stands in it and
## whether they are at war, the fight is the resolver's own contested test, a
## rival the chart withholds or has not watched contributes nothing, and a
## harbour (a squadron in port) never reaches the reading.

const SEA_WIDTH: int = 12
const SEA_HEIGHT: int = 4
const SEA_PLAYER: int = FactionCatalog.PLAYER_FACTION
const SEA_RIVAL: int = 3
const SEA_OTHER: int = 4
const SEA_WEST: int = 0
const SEA_EAST: int = 1

var _sea_model: MapModel = null
var _sea_fleets: Array[FleetState] = []


func _setup_sea_survey() -> void:
	_sea_model = _build_sea()
	_sea_fleets = []


## Two sea zones under a strip of the crown's land: the west water and the east.
func _build_sea() -> MapModel:
	var model := MapModel.new()
	model.setup(SEA_WIDTH, SEA_HEIGHT)
	var west: Array[Vector2i] = []
	var east: Array[Vector2i] = []
	var land: Array[Vector2i] = []
	for y in SEA_HEIGHT:
		for x in SEA_WIDTH:
			var index: int = model.index_of(x, y)
			var tile := Vector2i(x, y)
			if y < SEA_HEIGHT - 2:
				model.terrain[index] = MapModel.Terrain.PLAINS
				model.province[index] = 0
				land.append(tile)
				continue
			model.terrain[index] = MapModel.Terrain.OCEAN
			var zone: int = SEA_WEST if x < SEA_WIDTH / 2 else SEA_EAST
			model.sea_zone[index] = zone
			if zone == SEA_WEST:
				west.append(tile)
			else:
				east.append(tile)
	var provinces: Array[ProvinceState] = []
	provinces.append(
		ProvinceState.create(
			0, "Sevilla", land, _sea_center(land), land.size(), SEA_PLAYER, true
		)
	)
	model.provinces = provinces
	model.sea_zones = [
		SeaZoneState.create(SEA_WEST, "Mar de Levante", west, _sea_center(west), west.size()),
		SeaZoneState.create(SEA_EAST, "Mar Océano", east, _sea_center(east), east.size()),
	]
	return model


func _sea_center(tiles: Array[Vector2i]) -> Vector2:
	var total := Vector2.ZERO
	for tile: Vector2i in tiles:
		total += Vector2(tile)
	return total / maxf(float(tiles.size()), 1.0)


func _fleet(owner: int, zone: int, types: Array[String]) -> FleetState:
	var hulls: Array[String] = []
	var catalog: Dictionary = {}
	for i in types.size():
		var hull_id: String = "ship_%d_%d" % [_sea_fleets.size() + 1, i]
		hulls.append(hull_id)
		catalog[hull_id] = types[i]
	var fleet: FleetState = FleetState.at_sea(
		_sea_fleets.size() + 1, owner, zone, hulls, catalog
	)
	_sea_fleets.append(fleet)
	return fleet


func _sea_snapshot(
	hostile: Callable = Callable(),
	view: Callable = Callable(),
	visibility: VisibilityModel = null
) -> Dictionary:
	return SeaSurvey.snapshot(_sea_model, _sea_fleets, visibility, SEA_PLAYER, hostile, view)


## Two courts at war with each other and with nobody else.
func _war_between(a: int, b: int) -> Callable:
	return func(left: int, right: int) -> bool:
		return (left == a and right == b) or (left == b and right == a)


func _nobody_is_hostile() -> Callable:
	return func(_a: int, _b: int) -> bool:
		return false


func sea_entry(survey: Dictionary, zone_id: int) -> Dictionary:
	for raw: Variant in survey.get("zones", []):
		var entry: Dictionary = raw
		if int(entry["id"]) == zone_id:
			return entry
	return {}


## The chart's answer for one squadron, the way `MapPlayFleets.view_filter` hands
## it in: a rival either drawn and read, drawn and unread, or not drawn at all.
func _view(drawn: bool, read: bool) -> Callable:
	return func(_fleet_in: FleetState) -> Dictionary:
		return {"drawn": drawn, "read": read}


func test_the_crowns_own_water_reads_quiet() -> void:
	_setup_sea_survey()
	var squadron: FleetState = _fleet(SEA_PLAYER, SEA_WEST, ["frigate", "carrack"])
	squadron.mission = FleetState.Mission.PATROL
	var entry: Dictionary = sea_entry(_sea_snapshot(), SEA_WEST)
	assert_eq(String(entry["band"]), SeaSurvey.BAND_QUIET)
	assert_eq(int(entry["own_hulls"]), 2)
	assert_gt(float(entry["own_strength"]), 0.0)
	assert_eq(String(entry["station_text"]), "Patrol")
	assert_false(bool(entry["fight"]))
	var text: String = SeaSurvey.summary_text(entry)
	assert_true(text.contains("Ours 1 squadron"), text)
	assert_true(text.contains("2 hulls"), text)
	assert_true(text.contains("Patrol"), text)


func test_a_rival_under_the_peace_reads_watched() -> void:
	_setup_sea_survey()
	_fleet(SEA_RIVAL, SEA_EAST, ["frigate"])
	var entry: Dictionary = sea_entry(_sea_snapshot(_nobody_is_hostile()), SEA_EAST)
	assert_eq(String(entry["band"]), SeaSurvey.BAND_WATCHED)
	assert_false(bool(entry["fight"]))
	assert_eq(int(entry["foe_squadrons"]), 1)
	assert_eq(String((entry["foe_courts"] as Array)[0]), FactionCatalog.name_of(SEA_RIVAL))


## A hostile sail alone in a zone resolves no battle — a fight needs two sides —
## but the water is hers and the crown holds nothing there.
func test_a_hostile_sail_we_do_not_share_reads_standoff() -> void:
	_setup_sea_survey()
	_fleet(SEA_RIVAL, SEA_EAST, ["frigate"])
	var entry: Dictionary = sea_entry(_sea_snapshot(_war_between(SEA_PLAYER, SEA_RIVAL)), SEA_EAST)
	assert_eq(String(entry["band"]), SeaSurvey.BAND_STANDOFF)
	assert_false(bool(entry["fight"]), "no second side, so no battle")
	assert_eq(int(entry["own_hulls"]), 0)
	assert_true(SeaSurvey.summary_text(entry).contains("No sail of ours"))


func test_a_shared_zone_at_war_reads_contested_and_names_the_battle() -> void:
	_setup_sea_survey()
	_fleet(SEA_PLAYER, SEA_WEST, ["frigate"])
	_fleet(SEA_RIVAL, SEA_WEST, ["frigate", "galleon"])
	var entry: Dictionary = sea_entry(
		_sea_snapshot(_war_between(SEA_PLAYER, SEA_RIVAL), _view(true, true)),
		SEA_WEST
	)
	assert_eq(String(entry["band"]), SeaSurvey.BAND_CONTESTED)
	assert_true(bool(entry["fight"]), "the resolver fights this zone")
	assert_true(bool(entry["own_engaged"]))
	assert_gt(float(entry["foe_strength"]), 0.0, "a read rival is weighed")
	assert_true(
		SeaSurvey.summary_text(entry).contains("a battle resolves here at turn end"),
		SeaSurvey.summary_text(entry)
	)


## An unread rival fights with nothing the crown can count: her figure is left
## out whole rather than printed short (wiki: ships-and-naval § Sighted strength).
func test_an_unread_rival_reads_blind_and_prints_no_weight() -> void:
	_setup_sea_survey()
	_fleet(SEA_PLAYER, SEA_WEST, ["frigate"])
	_fleet(SEA_RIVAL, SEA_WEST, ["frigate"])
	var entry: Dictionary = sea_entry(
		_sea_snapshot(_war_between(SEA_PLAYER, SEA_RIVAL), _view(true, false)),
		SEA_WEST
	)
	assert_eq(String(entry["band"]), SeaSurvey.BAND_BLIND)
	assert_true(bool(entry["fight"]), "she fights whether or not she is read")
	assert_eq(int(entry["foe_unread"]), 1)
	assert_almost_eq(float(entry["foe_strength"]), 0.0, 0.001)
	assert_true(SeaSurvey.summary_text(entry).contains("weight unread"))

## A rival the fog withholds is not the crown's to read: she adds no plaque, no
## hull and no fight to the water she stands in.
func test_a_withheld_rival_never_reaches_the_reading() -> void:
	_setup_sea_survey()
	_fleet(SEA_PLAYER, SEA_WEST, ["frigate"])
	_fleet(SEA_RIVAL, SEA_WEST, ["frigate"])
	var survey: Dictionary = _sea_snapshot(
		_war_between(SEA_PLAYER, SEA_RIVAL), _view(false, false)
	)
	var entry: Dictionary = sea_entry(survey, SEA_WEST)
	assert_eq(String(entry["band"]), SeaSurvey.BAND_QUIET)
	assert_eq(int(entry["foe_squadrons"]), 0)
	assert_false(bool(entry["fight"]), "the crown sees no fight here to name")
	assert_eq(int(survey["totals"]["zones"]), 1, "only the water she can see")


## Two rivals at war in water the crown does not hold still fight at turn end;
## the reading says so without claiming the battle as ours.
func test_two_rivals_at_war_in_water_we_do_not_hold() -> void:
	_setup_sea_survey()
	_fleet(SEA_RIVAL, SEA_EAST, ["frigate"])
	_fleet(SEA_OTHER, SEA_EAST, ["frigate"])
	var entry: Dictionary = sea_entry(
		_sea_snapshot(_war_between(SEA_RIVAL, SEA_OTHER), _view(true, true)),
		SEA_EAST
	)
	assert_eq(String(entry["band"]), SeaSurvey.BAND_STANDOFF)
	assert_true(bool(entry["fight"]))
	assert_false(bool(entry["own_engaged"]), "no sail of ours is in it")
	assert_true(
		SeaSurvey.summary_text(entry).contains("two rivals fight here at turn end"),
		SeaSurvey.summary_text(entry)
	)


## Two rivals at war with each other, with a crown squadron standing in the same
## water at peace with both: the close fights the rivals and never the crown, so
## the reading must not claim that battle as ours (wiki: ships-and-naval § Naval
## Combat Resolution; DR-20261115-17 § Change — "the chart can never promise a
## battle the close would not strike").
func test_a_spectator_squadron_does_not_claim_a_rival_battle() -> void:
	_setup_sea_survey()
	_fleet(SEA_PLAYER, SEA_WEST, ["frigate"])
	_fleet(SEA_RIVAL, SEA_WEST, ["frigate"])
	_fleet(SEA_OTHER, SEA_WEST, ["frigate"])
	var entry: Dictionary = sea_entry(
		_sea_snapshot(_war_between(SEA_RIVAL, SEA_OTHER), _view(true, true)),
		SEA_WEST
	)
	assert_true(bool(entry["fight"]), "the rivals fight this zone")
	assert_false(bool(entry["own_engaged"]), "no hostile sail of ours shares the water")
	assert_eq(String(entry["band"]), SeaSurvey.BAND_WATCHED)
	assert_true(
		SeaSurvey.summary_text(entry).contains("two rivals fight here at turn end"),
		SeaSurvey.summary_text(entry)
	)


func test_a_squadron_in_port_reads_no_water() -> void:
	_setup_sea_survey()
	var moored: FleetState = FleetState.in_port(9, SEA_PLAYER, 0, ["ship_9"], {"ship_9": "frigate"})
	_sea_fleets.append(moored)
	var survey: Dictionary = _sea_snapshot()
	assert_eq((survey["zones"] as Array).size(), 0, "a harbour fights nothing")
	assert_eq(int(survey["totals"]["hulls"]), 0)


func test_sea_counts_and_the_crown_totals() -> void:
	_setup_sea_survey()
	_fleet(SEA_PLAYER, SEA_WEST, ["frigate", "frigate"])
	_fleet(SEA_RIVAL, SEA_WEST, ["frigate"])
	_fleet(SEA_PLAYER, SEA_EAST, ["frigate"])
	var survey: Dictionary = _sea_snapshot(_war_between(SEA_PLAYER, SEA_RIVAL), _view(true, true))
	assert_eq(int(survey["counts"][SeaSurvey.BAND_CONTESTED]), 1)
	assert_eq(int(survey["counts"][SeaSurvey.BAND_QUIET]), 1)
	assert_eq(int(survey["totals"]["zones"]), 2)
	assert_eq(int(survey["totals"]["hulls"]), 3, "our hulls only, never hers")
	assert_eq(int(survey["totals"]["contested"]), 1)
	assert_eq(int(survey["totals"]["blind"]), 0)


## The reading is remembered, not invented: charted water draws, and a plate
## anchors on the brightest water of its own zone. The crown's own sail is
## charted by definition — a fleet never floats in water it cannot read.
func test_the_zone_carries_the_chart_the_crown_holds() -> void:
	_setup_sea_survey()
	_fleet(SEA_PLAYER, SEA_WEST, ["frigate"])
	_fleet(SEA_RIVAL, SEA_EAST, ["frigate"])
	var visibility := VisibilityModel.new()
	visibility.setup(_sea_model, SEA_PLAYER)
	var survey: Dictionary = _sea_snapshot(
		_nobody_is_hostile(), _view(true, true), visibility
	)
	var entry: Dictionary = sea_entry(survey, SEA_WEST)
	assert_eq(int(entry["charted"]), VisibilityModel.Level.FULLY_VISIBLE, "our own water")
	var anchor: Vector2i = entry["anchor"]
	assert_eq(_sea_model.sea_zone_at(anchor.x, anchor.y), SEA_WEST, "the plate sits on its own water")
	for tile: Vector2i in _sea_model.sea_zone_data(SEA_EAST).tiles:
		visibility.lower_to(_sea_model.index_of(tile.x, tile.y), VisibilityModel.Level.UNKNOWN)
	assert_eq(
		int(sea_entry(_sea_snapshot(
			_nobody_is_hostile(), _view(true, true), visibility
		), SEA_EAST)["charted"]),
		VisibilityModel.Level.UNKNOWN,
		"water nobody charted is drawn at nothing"
	)


func test_one_hull_reads_in_the_singular() -> void:
	_setup_sea_survey()
	_fleet(SEA_PLAYER, SEA_WEST, ["frigate"])
	var text: String = SeaSurvey.summary_text(sea_entry(_sea_snapshot(), SEA_WEST))
	assert_true(text.contains("1 squadron"), text)
	assert_true(text.contains("1 hull"), text)
	assert_false(text.contains("1 hulls"), text)


func test_every_band_has_a_label_and_an_ink() -> void:
	var inks: Dictionary = {}
	for band: String in SeaSurvey.BANDS:
		assert_true(SeaSurvey.BAND_LABELS.has(band), "no label for " + band)
		inks[Palette.sea_color(band)] = band
	assert_eq(inks.size(), SeaSurvey.BANDS.size(), "each band owns its own ink")
	assert_eq(SeaSurvey.band_for(false, false, false, 0, false), SeaSurvey.BAND_QUIET)
	assert_eq(SeaSurvey.band_for(true, true, true, 0, true), SeaSurvey.BAND_CONTESTED)
	assert_eq(SeaSurvey.band_for(true, true, true, 1, true), SeaSurvey.BAND_BLIND)
	assert_eq(SeaSurvey.band_for(false, true, true, 0, false), SeaSurvey.BAND_STANDOFF)
	assert_eq(SeaSurvey.band_for(true, true, false, 0, false), SeaSurvey.BAND_WATCHED)


# --- folded: crown orders through the real map screen ---
## Civilians, training, estates and setup leaders (merged from
## test_map_screen_crown_orders): the same mount, the same re-seat.


func test_civilians_muster_at_the_capital() -> void:
	assert_eq(
		_screen.civilian_layer.units.size(), MapScreen.STARTING_CIVILIANS.size()
	)
	assert_eq(
		_screen.hud._civilian_label.text, str(MapScreen.STARTING_CIVILIANS.size())
	)
	for unit: CivilianState in _screen.civilian_layer.units:
		assert_eq(unit.owner, MapScreen.PLAYER_FACTION)
		assert_eq(
			_screen.model.province_at(unit.tile.x, unit.tile.y), _screen.capital_province
		)


func test_tapping_a_civilian_opens_its_dossier() -> void:
	var unit: CivilianState = _screen.civilian_layer.units[0]
	MapPlayInput.on_tapped(
		_screen.play, MapGeo.tile_center(unit.tile.x, unit.tile.y, MapScreen.TILE_SIZE)
	)
	assert_eq(_screen.civilian_layer.selected_unit, unit)
	assert_true(_screen.hud.panels.is_civilian_panel_open())
	assert_false(_screen.hud.panels.is_panel_open())


func test_a_work_order_costs_materials_and_completes_on_end_turn() -> void:
	var tile: Vector2i = _buildable_owned_resource_tile()
	assert_true(tile.x >= 0, "map has an owned resource a Builder can raise")
	var builder: CivilianState = _screen.civilian_layer.units[1]
	assert_eq(builder.type_id, "builder")
	builder.tile = tile
	_screen.civilian_layer.select(builder)
	var lumber_before: int = int(_screen.stockpile["lumber"])
	MapPlayCivilians.on_action(_screen.play, "build_improvement")
	assert_eq(int(_screen.stockpile["lumber"]), lumber_before - 1)
	assert_true(builder.is_working())
	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)
	assert_eq(_screen.land_works.improvement_at(_screen.model, tile), 1)
	assert_true(builder.is_idle())


## The chart carries the pick (DR-20261117-07): the survey lens is mounted with
## the crown's own picks, and the ground an idle crew's planner names wears the
## mark — the same reading its sheet prints, drawn where the crown plans work.
func test_the_survey_lens_marks_the_ground_the_court_would_work() -> void:
	var tile: Vector2i = _buildable_owned_resource_tile()
	assert_true(tile.x >= 0, "map has an owned resource a Builder can raise")
	var builder: CivilianState = _screen.civilian_layer.units[1]
	assert_eq(builder.type_id, "builder")
	builder.tile = tile
	_screen.stockpile["lumber"] = 40
	_screen.stockpile["castIron"] = 40

	MapPlayLens.mount_survey(_screen.play)
	MapPlayInput.set_lens(_screen.play, true)

	var lens: ResourceLens = _screen.play.lens
	assert_true(lens.active, "the survey reading is up")
	assert_true(lens.picks.has(builder.id), "the lens carries the court's pick")
	var pick: Dictionary = lens.picks[builder.id]
	var marked: Array[Vector2i] = []
	for mark: Dictionary in lens.marks:
		marked.append(Vector2i(mark["tile"]))
	assert_true(
		marked.has(Vector2i(pick["tile"])),
		"the ground the court named is marked on the chart"
	)
	assert_false(builder.is_working(), "a reading, not an order")


## A wall is the one work whose completion changes how the province is fought
## over, so the despatch names the level raised and the battery it mounts — a
## crown that spent its materials and a turn learns what it bought (wiki:
## siege-mechanics § Fort Levels, § Emplaced Artillery; REQ-P5-05).
func test_a_finished_fort_names_the_wall_it_raised() -> void:
	var engineer: CivilianState = null
	for unit: CivilianState in _screen.civilian_layer.units:
		if unit.type_id == "engineer":
			engineer = unit
			break
	assert_true(engineer != null, "the crown keeps an Engineer")
	var province: int = _screen.model.province_at(engineer.tile.x, engineer.tile.y)
	_screen.stockpile["lumber"] = 40
	_screen.stockpile["bronze"] = 12
	_screen.civilian_layer.select(engineer)

	MapPlayCivilians.on_action(_screen.play, "build_fort")
	assert_true(engineer.is_working(), "the order is taken from the dossier")
	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)

	assert_eq(FortRules.level_at(_screen.model, province), 1)
	var said: String = _toast_text()
	assert_true(said.contains("wood fort raised"), said)
	assert_true(said.contains("1 emplaced gun"), said)


## The hire is a BuildUnitOrder: the press queues it, and Build/work pays the
## 1,000 ducats and 2 paper and musters the explorer that turn
## (wiki: civilian-units § Training; workers-and-population § Phase placement).
func test_training_a_civilian_is_queued_then_mustered_in_build_work() -> void:
	MapPlayInput.select_province(_screen.play, _screen.capital_province, _capital_point())
	var units_before: int = _screen.civilian_layer.units.size()
	var treasury_before: int = _screen.treasury
	var paper_before: int = int(_screen.stockpile["paper"])
	MapPlayInput.on_panel_action(_screen.play, "train_explorer")
	assert_eq(_screen.civilian_layer.units.size(), units_before, "nothing musters at the press")
	assert_eq(_screen.treasury, treasury_before, "nothing is paid at the press")
	assert_eq(
		_screen.play.economy.economy.recruits.pending(RecruitQueue.KIND_CIVILIAN, "explorer"),
		1
	)

	MapPlayRecruits.complete(_screen.play)

	assert_eq(_screen.treasury, treasury_before - 1000)
	assert_eq(int(_screen.stockpile["paper"]), paper_before - 2)
	assert_eq(_screen.civilian_layer.units.size(), units_before + 1)


## Every kind of recruit is one turn of work: the Orders press files the order,
## the turn's Build/work pays and delivers it, and the gazette names what landed
## (wiki: workers-and-population § Phase placement; the-gazette § Item catalog).
func test_a_turn_delivers_every_queued_recruit_and_the_gazette_names_them() -> void:
	var play: PlaySession = _screen.play
	MapPlayInput.select_province(play, _screen.capital_province, _capital_point())
	var economy: PlayerEconomy = play.economy.economy
	economy.treasury = 60000
	economy.stockpile["fabric"] = 12
	economy.stockpile["paper"] = 12
	economy.stockpile["lumber"] = 40
	var civilians: int = _screen.civilian_layer.unit_count_all(play.player_faction)
	var regiments: int = _screen.army_layer.regiment_count_all(play.player_faction)
	var hulls: int = _screen.ship_layer.hull_count_all(play.player_faction)
	var peasants: int = economy.workers.count(WorkerPool.Tier.PEASANT)

	_screen.economy.orders.worker_action(WorkerPool.Tier.PEASANT, "recruit")
	MapPlayInput.on_panel_action(play, "train_explorer")
	MapPlayArmyMuster.recruit(play, "peasant_levies")
	MapPlayFleetYard.launch(play, "carrack")

	assert_eq(economy.recruits.total(), 4, "four orders wait for Build/work")
	assert_eq(
		_screen.civilian_layer.unit_count_all(play.player_faction), civilians,
		"nothing lands at the press"
	)
	assert_eq(_screen.army_layer.regiment_count_all(play.player_faction), regiments)
	assert_eq(_screen.ship_layer.hull_count_all(play.player_faction), hulls)

	MapPlayTurn.end_turn(play)
	Fixture.settle(play)

	assert_eq(
		_screen.civilian_layer.unit_count_all(play.player_faction), civilians + 1,
		"the hire musters"
	)
	assert_eq(_screen.army_layer.regiment_count_all(play.player_faction), regiments + 1)
	assert_eq(_screen.ship_layer.hull_count_all(play.player_faction), hulls + 1)
	assert_eq(
		economy.workers.count(WorkerPool.Tier.PEASANT), peasants - 1,
		"one peasant hired, two mustered"
	)
	assert_true(economy.recruits.is_empty(), "Build/work drained the queue")

	var kinds: Array[String] = []
	for item: Dictionary in play.gazette.sheets.back().get("items", []) as Array:
		kinds.append(String(item.get("kind", "")))
	for expected: String in [
		"workerRecruited", "civilianMustered", "regimentMustered", "shipLaunched"
	]:
		assert_true(kinds.has(expected), "the sheet names %s (%s)" % [expected, kinds])


## A promise the turn cannot keep is spoken and dropped: a muster the purse can
## no longer pay leaves no phantom order behind (REQ-P2-03).
func test_an_order_the_build_work_cannot_pay_is_refused_and_dropped() -> void:
	var play: PlaySession = _screen.play
	MapPlayInput.select_province(play, _screen.capital_province, _capital_point())
	var economy: PlayerEconomy = play.economy.economy
	economy.treasury = 60000
	var regiments: int = _screen.army_layer.regiment_count_all(play.player_faction)
	MapPlayArmyMuster.recruit(play, "peasant_levies")
	economy.treasury = 0
	var toasts: int = _screen.hud._toast_box.get_child_count()

	MapPlayRecruits.complete(play)

	assert_eq(_screen.army_layer.regiment_count_all(play.player_faction), regiments)
	assert_true(economy.recruits.is_empty(), "the order is dropped, not retried")
	assert_gt(_screen.hud._toast_box.get_child_count(), toasts, "the court hears why")


## A hull ordered at the slip is not delivered once the capital has fallen: the
## crown keeps no phantom squadron (wiki: ships-and-naval § Ship build economy).
func test_a_hull_ordered_at_a_lost_capital_is_refused() -> void:
	var play: PlaySession = _screen.play
	var capital: int = play.capital_province
	play.selected_province = capital
	play.economy.economy.treasury = 60000
	var hulls: int = _screen.ship_layer.hull_count_all(play.player_faction)
	MapPlayFleetYard.launch(play, "carrack")
	play.capital_province = Fixture.foreign_province(_screen.model)

	MapPlayRecruits.complete(play)

	assert_eq(_screen.ship_layer.hull_count_all(play.player_faction), hulls)
	assert_true(play.economy.economy.recruits.is_empty())


## A worker order whose cloth was sold before Build/work is refused there with
## the wiki's reason, and the pool keeps its count (REQ-P2-03).
func test_a_worker_order_the_ledger_cannot_pay_is_refused() -> void:
	var play: PlaySession = _screen.play
	var economy: PlayerEconomy = play.economy.economy
	economy.stockpile["fabric"] = 2
	var peasants: int = economy.workers.count(WorkerPool.Tier.PEASANT)
	_screen.economy.orders.worker_action(WorkerPool.Tier.PEASANT, "recruit")
	economy.stockpile["fabric"] = 0
	var toasts: int = _screen.hud._toast_box.get_child_count()

	MapPlayRecruits.complete(play)

	assert_eq(economy.workers.count(WorkerPool.Tier.PEASANT), peasants)
	assert_true(economy.recruits.is_empty(), "the order is dropped, not retried")
	assert_gt(_screen.hud._toast_box.get_child_count(), toasts, "the court hears why")


## A hire whose purse is spent before Build/work is refused there and the order
## is dropped, so the crown never keeps a promise it cannot pay (REQ-P2-03).
func test_a_hire_the_purse_cannot_close_is_refused() -> void:
	var play: PlaySession = _screen.play
	MapPlayInput.select_province(play, _screen.capital_province, _capital_point())
	var civilians: int = _screen.civilian_layer.unit_count_all(play.player_faction)
	MapPlayInput.on_panel_action(play, "train_explorer")
	play.economy.economy.treasury = 0
	var toasts: int = _screen.hud._toast_box.get_child_count()

	MapPlayRecruits.complete(play)

	assert_eq(_screen.civilian_layer.unit_count_all(play.player_faction), civilians)
	assert_true(play.economy.economy.recruits.is_empty(), "the order is dropped")
	assert_gt(_screen.hud._toast_box.get_child_count(), toasts, "the court hears why")


## The civilian gate names an unknown type and a deferred one, so the muster
## list never queues an order the rules would refuse.
func test_the_civilian_gate_names_what_it_refuses() -> void:
	var play: PlaySession = _screen.play
	assert_eq(String(MapPlayTraining.settle(play, "dragon")["reason"]), "Unknown civilian.")
	assert_true(
		play.economy.economy.recruits.is_empty(), "a refused hire is never queued"
	)


func test_training_is_refused_outside_the_capital() -> void:
	var province_id: int = Fixture.foreign_province(_screen.model)
	MapPlayInput.select_province(
		_screen.play, province_id, _screen.model.province_center(province_id) * MapScreen.TILE_SIZE
	)
	var units_before: int = _screen.civilian_layer.units.size()
	var treasury_before: int = _screen.treasury
	MapPlayInput.on_panel_action(_screen.play, "train_explorer")
	assert_eq(_screen.civilian_layer.units.size(), units_before)
	assert_eq(_screen.treasury, treasury_before)


func test_training_a_rail_builder_waits_for_early_steam_engine() -> void:
	MapPlayInput.select_province(_screen.play, _screen.capital_province, _capital_point())
	var units_before: int = _screen.civilian_layer.units.size()
	MapPlayInput.on_panel_action(_screen.play, "train_rail_builder")
	assert_eq(_screen.civilian_layer.units.size(), units_before)

	_screen.play.economy.economy.research.unlock("early_steam_engine")
	var treasury_before: int = _screen.treasury
	MapPlayInput.on_panel_action(_screen.play, "train_rail_builder")
	assert_eq(_screen.civilian_layer.units.size(), units_before, "queued, not mustered")
	MapPlayRecruits.complete(_screen.play)
	assert_eq(_screen.civilian_layer.units.size(), units_before + 1)
	assert_eq(_screen.civilian_layer.units.back().type_id, "rail_builder")
	assert_eq(_screen.treasury, treasury_before - 2000)


func test_unknown_civilian_orders_do_not_train() -> void:
	MapPlayInput.select_province(_screen.play, _screen.capital_province, _capital_point())
	var units_before: int = _screen.civilian_layer.units.size()
	MapPlayInput.on_panel_action(_screen.play, "train_dragon")
	assert_eq(_screen.civilian_layer.units.size(), units_before)


func test_region_switch_keeps_the_civilian_roster_and_works() -> void:
	var builder: CivilianState = _screen.civilian_layer.units[1]
	var resource: Vector2i = _buildable_owned_resource_tile()
	assert_true(resource.x >= 0, "map has an owned resource a Builder can raise")
	builder.tile = resource
	_screen.civilian_layer.select(builder)
	MapPlayCivilians.on_action(_screen.play, "build_improvement")
	var works: LandWorks = _screen.land_works

	_screen._cycle_region()
	assert_eq(_screen.civilian_layer.units.size(), 0, "no crown holdings in the New World")

	_screen._cycle_region()
	assert_eq(_screen.civilian_layer.units.size(), MapScreen.STARTING_CIVILIANS.size())
	assert_true(_screen.civilian_layer.units.has(builder))
	assert_eq(builder.tile, resource)
	assert_true(builder.is_working())
	assert_eq(_screen.land_works, works)


func test_each_region_keeps_its_own_fleets() -> void:
	var old_fleet: FleetState = _screen.ship_layer.fleets[0]
	var old_zone: int = old_fleet.sea_zone

	_screen._cycle_region()
	for fleet: FleetState in _screen.ship_layer.fleets:
		assert_false(fleet == old_fleet, "the New World fields its own squadrons")

	_screen._cycle_region()
	assert_eq(_screen.ship_layer.fleets[0], old_fleet)
	assert_eq(old_fleet.sea_zone, old_zone)


func test_end_turn_restores_orders_in_the_region_off_screen() -> void:
	var fleet: FleetState = _screen.ship_layer.fleets[0]
	fleet.moved = true
	_screen._cycle_region()
	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)
	assert_false(fleet.moved, "a fleet must be ready when its map reopens")


func test_battles_resolve_in_the_region_off_screen() -> void:
	_screen._cycle_region()
	assert_eq(_screen.region_index, 1)
	var zone: int = _screen.model.sea_zones[0].id
	var first: FleetState = null
	var second: FleetState = null
	for fleet: FleetState in _screen.ship_layer.fleets:
		if first == null:
			first = fleet
		elif second == null and fleet.owner != first.owner:
			second = fleet
		else:
			fleet.location = FleetState.Location.IN_PORT
			fleet.province = _screen.model.provinces[0].id
	assert_not_null(first)
	assert_not_null(second)
	for fleet: FleetState in [first, second]:
		fleet.location = FleetState.Location.AT_SEA
		fleet.sea_zone = zone
	first.set_hulls(["a"], {"a": "carrack"})
	second.set_hulls(["b"], {"b": "fluyte"})
	DiplomacyRules.declare_war(_screen.play.diplomacy, first.owner, second.owner)
	var hulls_before: int = first.ship_count() + second.ship_count()
	var toasts_before: int = _screen.hud._toast_box.get_child_count()

	_screen._cycle_region()
	assert_eq(_screen.region_index, 0)
	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)

	var hulls_after: int = first.ship_count() + second.ship_count()
	if hulls_after == hulls_before:
		assert_ne(
			first.sea_zone, second.sea_zone,
			"a beaten squadron that survives withdraws to adjacent water"
		)
	else:
		assert_lt(hulls_after, hulls_before)
	assert_gt(_screen.hud._toast_box.get_child_count(), toasts_before)


func test_empire_counters_survive_a_region_switch() -> void:
	var ships: int = _screen.economy.readings.fleet_ships()
	assert_gt(ships, 0)
	_screen._cycle_region()
	assert_eq(_screen.economy.readings.fleet_ships(), ships, "navy upkeep follows the empire")
	assert_eq(_screen.hud._fleet_label.text, str(ships))
	assert_eq(
		_screen.hud._civilian_label.text, str(MapScreen.STARTING_CIVILIANS.size())
	)
	var need: int = int(_screen.economy.readings.projected()["consumption"]["navy_demand"])
	assert_eq(need, ships * ShipEconomy.FOOD_UPKEEP_PER_SHIP)


func test_the_civilian_chip_opens_the_whole_empire_roster() -> void:
	_screen.hud.ledger_door_pressed.emit(HudLedgerDoors.CIVILIANS)
	var roster: CivilianRosterPanel = _screen.hud.civilian_roster
	assert_not_null(roster)
	assert_true(roster.is_open())
	assert_eq(int(roster._snapshot["total"]), MapScreen.STARTING_CIVILIANS.size())
	assert_eq(roster._head.region, LedgerRows.REGION_ALL)
	assert_eq(roster._head.type_id, CivilianRosterHead.TYPE_ALL)
	roster.close()
	assert_false(roster.is_open())


func test_the_roster_filters_the_new_world_and_visits_its_civilian() -> void:
	_screen._cycle_region()
	assert_eq(_screen.region_index, FactionCatalog.NEW_WORLD)
	var tile: Vector2i = _screen.model.provinces[0].tiles[0]
	var unit: CivilianState = _screen.civilian_layer.add_unit(
		_screen.play.player_faction, "merchant", tile
	)
	_screen._cycle_region()
	assert_eq(_screen.region_index, FactionCatalog.OLD_WORLD)

	_screen.hud.ledger_door_pressed.emit(HudLedgerDoors.CIVILIANS)
	var roster: CivilianRosterPanel = _screen.hud.civilian_roster
	roster._head._region_buttons[LedgerRows.REGION_NEW].pressed.emit()
	roster._head._type_buttons["merchant"].pressed.emit()
	assert_eq(
		CivilianRoster.count(roster._snapshot, LedgerRows.REGION_NEW, "merchant"), 1
	)
	var row: CivilianRosterRow = _first_row(roster)
	assert_not_null(row)
	assert_eq(int(row.data["unit_id"]), unit.id)
	assert_eq(String(row.data["province_name"]), _screen.world.region(1).province_name(
		_screen.world.region(1).province_at(tile.x, tile.y)
	))

	var tap := InputEventMouseButton.new()
	tap.pressed = true
	tap.button_index = MOUSE_BUTTON_LEFT
	row._gui_input(tap)
	assert_false(roster.is_open(), "a tap on the row visits the civilian")
	assert_eq(_screen.region_index, FactionCatalog.NEW_WORLD)
	assert_eq(_screen.civilian_layer.selected_unit, unit)
	assert_true(_screen.hud.panels.is_civilian_panel_open())


func test_the_roster_filters_by_region_craft_and_empty_view() -> void:
	_screen.hud.ledger_door_pressed.emit(HudLedgerDoors.CIVILIANS)
	var roster: CivilianRosterPanel = _screen.hud.civilian_roster
	var head: CivilianRosterHead = roster._head
	head._region_buttons[LedgerRows.REGION_OLD].pressed.emit()
	assert_eq(roster._region, LedgerRows.REGION_OLD)
	assert_eq(CivilianRoster.count(roster._snapshot, roster._region), 3)
	head._type_buttons["explorer"].pressed.emit()
	assert_eq(roster._type, "explorer")
	assert_eq(CivilianRoster.count(roster._snapshot, roster._region, roster._type), 1)
	head._type_buttons["explorer"].pressed.emit()
	assert_eq(roster._type, CivilianRosterHead.TYPE_ALL, "tapping the craft clears it")
	head._type_buttons[CivilianRosterHead.TYPE_ALL].pressed.emit()
	head._region_buttons[LedgerRows.REGION_NEW].pressed.emit()
	assert_true(roster._empty.visible, "an empty world gets an explanation")
	assert_true(String(roster._empty.text).contains("No civilians"))
	assert_true(roster.is_open())


func test_the_roster_reads_who_waits_for_orders() -> void:
	_screen.hud.ledger_door_pressed.emit(HudLedgerDoors.CIVILIANS)
	var roster: CivilianRosterPanel = _screen.hud.civilian_roster
	var head: CivilianRosterHead = roster._head
	head._region_buttons[LedgerRows.REGION_ALL].pressed.emit()
	head._type_buttons[CivilianRosterHead.TYPE_ALL].pressed.emit()
	var total: int = int(roster._snapshot["total"])
	var idle: int = int(roster._snapshot["idle"])
	var working: int = int(roster._snapshot["working"])
	assert_eq(idle + working, total, "every crew is either waiting or at work")
	head._status_buttons[CivilianRoster.STATUS_IDLE].pressed.emit()
	assert_eq(roster._status, CivilianRoster.STATUS_IDLE)
	assert_eq(
		CivilianRoster.count(
			roster._snapshot, roster._region, roster._type, roster._status
		),
		idle,
		"the idle view is the roster's own idle tally",
	)
	assert_true(String(roster._subtitle.text).contains("idle only"))
	head._status_buttons[CivilianRoster.STATUS_WORKING].pressed.emit()
	assert_eq(
		CivilianRoster.count(
			roster._snapshot, roster._region, roster._type, roster._status
		),
		working,
	)
	if working == 0:
		assert_true(roster._empty.visible, "an empty at-work view is explained")
		assert_true(String(roster._empty.text).contains("is at work"))
	else:
		assert_false(roster._empty.visible)
	head._status_buttons[CivilianRoster.STATUS_WORKING].pressed.emit()
	assert_eq(roster._status, CivilianRoster.STATUS_ALL, "tapping the lit chip clears it")
	assert_eq(
		CivilianRoster.count(roster._snapshot, roster._region, roster._type, roster._status),
		total,
	)
	head._status_buttons[CivilianRoster.STATUS_IDLE].pressed.emit()
	roster.close()
	_screen.hud.ledger_door_pressed.emit(HudLedgerDoors.CIVILIANS)
	assert_eq(roster._status, CivilianRoster.STATUS_IDLE, "the filter is the reader's")
	assert_eq(roster._head.status, CivilianRoster.STATUS_IDLE, "the chips mirror it back")
	roster.close()


## The chore's own door: one press takes the crown to the next crew that waits,
## closing the sheet and opening that crew's dossier, and the walk covers both
## worlds (REQ-P5-03, REQ-P5-04).
func test_the_roster_finds_the_next_crew_that_waits() -> void:
	_screen.hud.ledger_door_pressed.emit(HudLedgerDoors.CIVILIANS)
	var roster: CivilianRosterPanel = _screen.hud.civilian_roster
	var head: CivilianRosterHead = roster._head
	var idle: int = int(roster._snapshot["idle"])
	assert_gt(idle, 0, "the opening roster holds a crew with no order")
	var expected: Dictionary = CivilianRoster.next_idle(
		roster._snapshot, _screen.play.region_index, -1
	)
	var press: Button = head.find_button()
	assert_not_null(press)
	assert_true(press.visible, "a crown with a crew waiting is offered the walk")
	assert_eq(press.text, CivilianRoster.find_caption(roster._snapshot))
	assert_eq(press.text, "Find the next crew that waits (%d)" % idle)

	press.pressed.emit()
	assert_false(roster.is_open(), "the sheet steps aside for the crew it found")
	var first: CivilianState = _screen.civilian_layer.selected_unit
	assert_not_null(first, "the walk selects the crew it found")
	assert_eq(first.id, int(expected["unit_id"]), "the walk starts at the first crew that waits")
	assert_false(first.is_working(), "the walk lands on a crew that waits")
	assert_true(_screen.hud.panels.is_civilian_panel_open(), "its dossier is open")
	assert_eq(
		_toast_texts().back(),
		CivilianRoster.idle_receipt(expected, idle - 1),
		"the receipt is the rules' own line",
	)

	# A second walk starts after the crew now selected, so the press covers the
	# whole column instead of landing on the same crew twice.
	_screen.hud.ledger_door_pressed.emit(HudLedgerDoors.CIVILIANS)
	head.find_button().pressed.emit()
	var second: CivilianState = _screen.civilian_layer.selected_unit
	assert_not_null(second)
	assert_false(second.is_working())
	if idle > 1:
		assert_ne(second.id, first.id, "the walk moves on to the next crew that waits")


## A crown with every crew at work is offered no walk at all, and the press that
## races the turn's close is answered rather than silent (REQ-P5-05).
func test_the_roster_offers_no_walk_when_every_crew_has_an_order() -> void:
	_screen.hud.ledger_door_pressed.emit(HudLedgerDoors.CIVILIANS)
	var roster: CivilianRosterPanel = _screen.hud.civilian_roster
	for unit: CivilianState in _screen.civilian_layer.units:
		if unit != null and unit.owner == _screen.play.player_faction:
			unit.start_work("build_improvement", unit.tile, 2, unit.tile)
	roster.refresh()
	assert_eq(int(roster._snapshot["idle"]), 0)
	assert_false(roster._head.find_button().visible, "no crew waits, so no press")
	roster._find_idle()
	assert_true(
		_toast_texts().back().contains("No crew waits for orders"),
		"a press with nothing to find says so: '%s'" % _toast_texts().back(),
	)
	roster.close()


func test_the_roster_opens_and_closes_from_the_keyboard() -> void:
	var roster: CivilianRosterPanel = _screen.hud.civilian_roster
	var toggle := InputEventAction.new()
	toggle.action = InputActions.CIVILIAN_ROSTER
	toggle.pressed = true
	roster._unhandled_input(toggle)
	assert_true(roster.is_open())
	roster._unhandled_input(toggle)
	assert_false(roster.is_open())
	var cancel := InputEventAction.new()
	cancel.action = InputActions.CANCEL
	cancel.pressed = true
	roster._unhandled_input(toggle)
	roster._input(cancel)
	assert_false(roster.is_open(), "Escape closes the ledger")


## The summary's door opens the full sheet, and back closes the sheet before the
## court hears the press (REQ-P5-01, REQ-P5-07; DR-20261110-25).
func test_the_full_dossier_opens_from_the_court_and_back_closes_it() -> void:
	_screen.play.diplomacy.apply_delta(0, 1, 22.0, "dossierSample")
	MapPlayDiplomacy.open(_screen.play)
	var panel: DiplomacyPanel = _screen.hud.panels.diplomacy_panel
	assert_true(panel.selected_faction() >= 0, "the court opens on a known crown")
	var button: Button = _find_button(panel._detail, "dossier")
	assert_not_null(button, "the summary says it has a full copy")
	button.pressed.emit()
	var sheet: CourtDossierScreen = _screen.hud.dossier_screen
	assert_true(sheet.is_open(), "the sheet is up over the court")
	assert_true(_has_text(sheet._body, "SUSPICION"))
	assert_true(_has_text(sheet._body, "BEHAVIOUR & BUILD NOTES"))
	BackRequest._last_ms = -BackRequest.DEBOUNCE_MS
	assert_true(BackRequest.handle(_screen.play, _screen.improvements))
	assert_false(sheet.is_open(), "back closes the sheet")
	assert_true(DiplomacyHud.is_open(_screen.hud.panels), "the court stays open")


func test_the_back_gesture_closes_the_roster_first() -> void:
	_screen.hud.civilian_roster.open()
	assert_true(_screen.hud.civilian_roster.is_open())
	BackRequest._last_ms = -BackRequest.DEBOUNCE_MS
	assert_true(BackRequest.handle(_screen.play, _screen.improvements))
	assert_false(_screen.hud.civilian_roster.is_open(), "back closes the ledger only")


func _find_button(node: Node, needle: String) -> Button:
	if node is Button and String((node as Button).text).contains(needle):
		return node as Button
	for child: Node in node.get_children():
		var found: Button = _find_button(child, needle)
		if found != null:
			return found
	return null


func _has_text(node: Node, needle: String) -> bool:
	if node is Label and String((node as Label).text).contains(needle):
		return true
	for child: Node in node.get_children():
		if _has_text(child, needle):
			return true
	return false


func _first_row(roster: CivilianRosterPanel) -> CivilianRosterRow:
	for child: Node in roster._rows.get_children():
		if child is CivilianRosterRow:
			return child
	return null


func test_estates_ledger_dispatches_a_builder_and_shows_the_yield() -> void:
	var tile: Vector2i = _capital_estate_tile()
	assert_true(tile.x >= 0, "capital has an owned neighbouring land tile")
	_screen.improvements.open()
	assert_true(_screen.improvements.is_open())
	assert_true(int(_screen.improvements._data["counts"]["estates"]) > 0)
	var builder: CivilianState = _screen.civilian_layer.units[1]
	assert_eq(builder.type_id, "builder")
	var lumber_before: int = int(_screen.stockpile["lumber"])
	var timber_before: int = int(_screen.stockpile.get("timber", 0))
	MapPlayImprovements.on_action(_screen.play, "build", tile)
	assert_true(builder.is_working())
	assert_eq(builder.work_tile(), tile)
	assert_eq(int(_screen.stockpile["lumber"]), lumber_before - 1)
	var row: Dictionary = ImprovementLedger.estate_row(
		_screen.model, _screen.land_works, _screen.civilian_layer.units,
		_screen.stockpile, MapScreen.PLAYER_FACTION, tile, _screen.capital_tile
	)
	assert_eq(String(row["status"]), "building")

	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)
	assert_eq(_screen.land_works.improvement_at(_screen.model, tile), 1)
	assert_true(builder.is_idle())
	assert_eq(int(_screen.stockpile["lumber"]), lumber_before - 1)
	assert_eq(int(_screen.stockpile.get("timber", 0)), timber_before + 1)


func test_estates_ledger_cancels_a_build_and_returns_the_builder() -> void:
	var tile: Vector2i = _capital_estate_tile()
	assert_true(tile.x >= 0, "capital has an owned neighbouring land tile")
	var builder: CivilianState = _screen.civilian_layer.units[1]
	var origin: Vector2i = builder.tile
	MapPlayImprovements.on_action(_screen.play, "build", tile)
	assert_true(builder.is_working())
	MapPlayImprovements.on_action(_screen.play, "cancel", tile)
	assert_true(builder.is_idle())
	assert_eq(builder.tile, origin)
	assert_eq(_screen.land_works.improvement_at(_screen.model, tile), 0)


func test_tapping_a_survey_mark_starts_the_survey() -> void:
	var play: PlaySession = _screen.play
	var explorer: CivilianState = _explorer()
	assert_not_null(explorer, "the crown fields an Explorer")
	if explorer == null:
		return
	var province: int = _screen.model.province_at(explorer.tile.x, explorer.tile.y)
	var ground: Array[Vector2i] = MineralSurvey.unsurveyed_in_province(
		_screen.model, _screen.land_works, play.player_faction, province,
		_screen.visibility
	)
	if ground.size() < 2:
		return
	var stand: Vector2i = ground[0]
	var target: Vector2i = stand
	for tile: Vector2i in ground:
		if absi(tile.x - stand.x) + absi(tile.y - stand.y) > 1:
			target = tile
			break
	if target == stand:
		return
	explorer.tile = stand
	_screen.civilian_layer.select(explorer)
	assert_true(_screen.overlay.survey_tiles.has(stand), "the marks cover the province")
	assert_true(_detail_text().contains("Survey"), "the dossier carries the survey row")
	# A tap on marked ground starts the survey without a march.
	assert_true(
		MapPlayCivilians.try_move(
			play, MapGeo.tile_center(target.x, target.y, MapScreen.TILE_SIZE)
		),
		"the tap is consumed by the survey"
	)
	assert_true(explorer.is_working())
	assert_eq(explorer.work_action(), "prospect")
	assert_eq(explorer.work_tile(), target)
	# A working Explorer takes no second survey.
	assert_false(MapPlayCivilians.try_survey(play, explorer, stand))
	await get_tree().process_frame
	# Ending the turn uncovers the ground for the court that paid for it.
	MapPlayTurn.end_turn(play)
	Fixture.settle(play)
	assert_true(
		_screen.land_works.is_prospected(play.player_faction, _screen.model, target),
		"the survey lands on end turn"
	)


func test_a_rivals_survey_never_names_its_find() -> void:
	var play: PlaySession = _screen.play
	var rival: int = -1
	for faction: int in FactionCatalog.great_power_ids():
		if faction != play.player_faction:
			rival = faction
			break
	assert_true(rival >= 0, "the chart seats more than one Great Power")
	var report: Dictionary = {"owner": rival, "find": "iron"}
	var line: String = MapPlayCivilians._survey_line(play, report, "Explorer", "Cádiz")
	assert_false(line.contains("iron"), "a rival's uncover is never ours to read")
	assert_true(line.contains("Explorer"))
	# The court that paid for the survey does hear what it found.
	report = {"owner": play.player_faction, "find": "iron"}
	line = MapPlayCivilians._survey_line(play, report, "Explorer", "Cádiz")
	assert_true(line.contains("iron"))
	assert_true(line.contains("Cádiz"))
	# An empty find is a real answer, not silence (DR-20261111-26).
	report = {"owner": play.player_faction, "find": ""}
	line = MapPlayCivilians._survey_line(play, report, "Explorer", "Cádiz")
	assert_true(line.contains("no mineral"))


func test_new_game_assigns_a_leader_to_every_great_power() -> void:
	var play: PlaySession = _screen.play
	for faction: int in FactionCatalog.great_power_ids():
		assert_eq(
			String(play.leaders.get(faction, "")),
			LeaderCatalog.default_key(faction),
			"crown %d fields its config leader" % faction
		)
	assert_eq(String(play.leaders.get(play.player_faction, "")), "isabella")


func test_setup_leader_choice_reaches_land_combat() -> void:
	# A second crown's opening, on its own screen: the suite's shared chart keeps
	# the fixture's seat for every other case.
	var chosen: MapScreen = Fixture.attach_screen(self, 2, "napoleon")
	var play: PlaySession = chosen.play
	assert_eq(play.player_faction, 2)
	assert_eq(String(play.leaders.get(2, "")), "napoleon", "the human crown keeps its choice")
	var context: Dictionary = MapPlayLandTurn.battle_context(play)
	var leaders: Dictionary = context["leaders"]
	assert_eq(String(leaders.get(2, "")), "napoleon", "combat reads the chosen leader")
	MapPlayTurn.end_turn(play)
	Fixture.settle(play)
	assert_eq(String(play.leaders.get(2, "")), "napoleon", "leaders never change mid-game")
	chosen.free()


func test_the_home_fleet_carries_a_field_army_across_its_port() -> void:
	var play: PlaySession = _screen.play
	var home: ArmyState = ArmyTraining.home_army(
		_screen.army_layer.armies, play.player_faction
	)
	assert_not_null(home)
	var detach: Dictionary = _screen.army_layer.split(home, [home.regiments[0]])
	assert_true(bool(detach.get("ok", false)))
	var army: ArmyState = detach["army"] as ArmyState
	var fleet: FleetState = _screen.ship_layer.home_fleet(_screen.capital_province)
	assert_not_null(fleet)
	_screen.army_layer.select(army)
	MapPlayArmies.on_action(play, "embark")
	assert_true(army.is_embarked())
	assert_eq(fleet.embarked_army, army.id)
	assert_eq(army.province, MapModel.NO_ID)

	var ship: Ship = _screen.ship_layer.ship_for(fleet)
	_screen.ship_layer.select(ship)
	MapPlayFleets.select(play, ship)
	assert_eq(MapPlayFleets.carried(play, fleet), army.count())
	assert_eq(MapPlayFleets.landing_rows(play, fleet).size(), 1)

	MapPlayFleets.land(play, _screen.capital_province)
	assert_false(army.is_embarked())
	assert_eq(army.province, _screen.capital_province)
	assert_eq(fleet.embarked_army, -1)


func test_a_crew_caught_in_a_captured_province_withdraws_or_is_lost() -> void:
	var play: PlaySession = _screen.play
	var pair: Array = _border_tiles(play)
	assert_gte(pair.size(), 2, "the fixture has a land border")
	var foreign: Vector2i = pair[1]
	var crew: CivilianState = _screen.civilian_layer.add_unit(
		play.player_faction, "builder", foreign
	)

	var reports: Array[Dictionary] = CivilianStrandingPass.settle_stranding(
		_screen.civilian_layer, play.world
	)

	assert_true(reports.size() >= 1, "the stranded crew is reported")
	if _screen.civilian_layer.units.has(crew):
		assert_ne(crew.tile, foreign, "withdraws off the lost ground")
		assert_true(CivilianMovement.may_enter(
			_screen.model, crew.type_id, crew.owner, crew.tile
		), "the new tile is legal")
	else:
		assert_true(bool(reports[0].get("lost", false)), "or is lost with the province")


func test_the_human_court_is_told_when_a_crew_withdraws() -> void:
	var play: PlaySession = _screen.play
	var pair: Array = _border_tiles(play)
	assert_gte(pair.size(), 2, "the fixture has a land border")
	var crew: CivilianState = _screen.civilian_layer.add_unit(
		play.player_faction, "builder", pair[1]
	)
	var toasts_before: int = _screen.hud._toast_box.get_child_count()

	MapPlayCivilians.settle_stranding(play)

	assert_gt(
		_screen.hud._toast_box.get_child_count(), toasts_before,
		"the court hears the crew's fate"
	)
	if _screen.civilian_layer.units.has(crew):
		assert_ne(crew.tile, pair[1])


## A signed deed develops the seller's town, and the crown is told the level it
## now stands at (DR-20261112-01; RUB-P5-05).
func test_a_signed_deed_names_the_town_it_raised() -> void:
	var play: PlaySession = _screen.play
	var model: MapModel = play.model
	var found: Array = _minor_estate(model)
	assert_eq(found.size(), 2, "the chart seats a Minor with an estate")
	var province: ProvinceState = found[0]
	var tile: Vector2i = found[1]
	var saved: Array = Fixture.snapshot(play.world)
	var town_before: int = province.town_development

	var report: Dictionary = {}
	assert_true(LandPurchase.complete(
		model, tile, play.player_faction, play.economy.economy, report
	), "the deed is signed")
	MapPlayCivilians._settle_purchase(play, {
		"owner": play.player_faction,
		"region": model.region_id,
		"tile": tile,
		"province": province.id,
		"town_level": int(report.get("town_level", 0)),
	})

	assert_eq(province.town_level(), 2, "one deed lifts the seller's town")
	assert_true(
		_last_toast_text().ends_with("The town rises to level 2."),
		"the court hears the deed and the level it bought: %s" % _last_toast_text()
	)
	# A town already at its deed ceiling must not announce a rise it never took.
	province.town_development = 4
	MapPlayCivilians._settle_purchase(play, {
		"owner": play.player_faction,
		"region": model.region_id,
		"tile": tile,
		"province": province.id,
		"town_level": 0,
	})
	assert_false(
		_last_toast_text().contains("town"),
		"a fully grown town is not announced as rising: %s" % _last_toast_text()
	)
	Fixture.restore(play.world, saved)
	province.town_development = town_before


## The text of the most recent despatch plate, or "" when none is on screen.
func _last_toast_text() -> String:
	var box: Node = _screen.hud._toast_box
	if box.get_child_count() == 0:
		return ""
	return _label_text(box.get_child(box.get_child_count() - 1))


func _label_text(node: Node) -> String:
	for child: Node in node.get_children():
		if child is Label:
			return (child as Label).text
		var inner: String = _label_text(child)
		if not inner.is_empty():
			return inner
	return ""


## A Minor or Tribe province and one of its resource tiles.
func _minor_estate(model: MapModel) -> Array:
	for province: ProvinceState in model.provinces:
		var kind: int = FactionCatalog.type_of(province.owner)
		if kind != FactionCatalog.Type.MINOR_NATION and kind != FactionCatalog.Type.TRIBE:
			continue
		for tile: Vector2i in province.tiles:
			if model.resource_at(tile.x, tile.y) != MapModel.NO_ID:
				return [province, tile]
	return []


## An owned land tile and a foreign neighbour across the border.
func _border_tiles(play: PlaySession) -> Array:
	var model: MapModel = play.model
	for province: ProvinceState in model.provinces:
		if province.owner != play.player_faction:
			continue
		for tile: Vector2i in province.tiles:
			for offset: Vector2i in [
				Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP
			]:
				var other: Vector2i = tile + offset
				if not model.is_land(other.x, other.y):
					continue
				var province_id: int = model.province_at(other.x, other.y)
				if province_id == MapModel.NO_ID:
					continue
				if model.province_owner(province_id) == play.player_faction:
					continue
				return [tile, other]
	return []


func _capital_estate_tile() -> Vector2i:
	var capital: Vector2i = _screen.capital_tile
	for offset: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var tile: Vector2i = capital + offset
		if not _screen.model.is_land(tile.x, tile.y):
			continue
		var province: int = _screen.model.province_at(tile.x, tile.y)
		if _screen.model.province_owner(province) != MapScreen.PLAYER_FACTION:
			continue
		var index: int = _screen.model.index_of(tile.x, tile.y)
		_screen.model.resource[index] = 0
		# The setup post-pass may have raised a bootstrap farm here.
		_screen.land_works.set_improvement(_screen.model, tile, 0)
		return tile
	return Vector2i(-1, -1)


func _capital_point() -> Vector2:
	return _screen.model.province_center(_screen.capital_province) * MapScreen.TILE_SIZE


## The crown's Explorer (the starting roster carries exactly one).
func _explorer() -> CivilianState:
	for unit: CivilianState in _screen.civilian_layer.units:
		if unit.type_id == "explorer":
			return unit
	return null


## Every caption and value printed on the civilian dossier's detail grid.
func _detail_text() -> String:
	var parts: PackedStringArray = PackedStringArray()
	var panel: CivilianPanel = _screen.hud.panels.civilian_panel
	for node: Node in panel._detail.find_children("*", "Label", true, false):
		parts.append((node as Label).text)
	return " ".join(parts)


## Prefer a crown resource a Builder can raise without an Explorer first. The
## shared seed's first owned tile can be tin/iron; skipping those keeps work
## orders stable without widening `map_fixture` (which forces a full suite).
func _buildable_owned_resource_tile() -> Vector2i:
	for province: ProvinceState in _screen.model.provinces:
		if province.owner != FactionCatalog.PLAYER_FACTION:
			continue
		for tile: Vector2i in province.tiles:
			var resource: int = _screen.model.resource_at(tile.x, tile.y)
			if resource < 0:
				continue
			if _screen.land_works.improvement_at(_screen.model, tile) > 0:
				continue
			if ImprovementCatalog.needs_prospecting(resource):
				continue
			return tile
	return Vector2i(-1, -1)


## Everything the court has been told this turn, as the toast box holds it.
func _toast_text() -> String:
	var parts: PackedStringArray = PackedStringArray()
	_collect(_screen.hud._toast_box, parts)
	return " | ".join(parts)


func _collect(node: Node, out: PackedStringArray) -> void:
	if node == null:
		return
	var label: Label = node as Label
	if label != null and not label.text.is_empty():
		out.append(label.text)
	for child: Node in node.get_children():
		_collect(child, out)


# --- folded: the agent debug bridge (issue #699) ---
## The projector's JSON shapes, the flag parser and the thin server's
## lifecycle — one live loopback round-trip in process. The projector is the
## rules surface (REQ-P3-03); the bridge owns only the socket.

const DUMP_KEYS: Array[String] = [
	"version", "game_version", "saved_at", "session", "regions", "visibility",
	"economy", "market", "diplomacy", "ai", "victory", "defeat", "gazette",
	"civilians", "fleets", "armies", "generals",
]
const LIVE_KEYS: Array[String] = [
	"observer_mode", "ai_mode", "ai_live_faction", "ai_turns", "ai_trace",
	"turn_suspended", "announced_decisions", "market_report", "court_reports",
	"selection", "hover", "region", "hud",
]

## Non-underscore: gd-tools clones a fresh suite instance per test and does not
## copy underscore fields out of before_all (docs/testing.md speed rules).


# --- the projector's dump shapes ---------------------------------------------


func test_dump_carries_the_save_bag_plus_live_overlays() -> void:
	var play: PlaySession = mounted.play
	var dump: Dictionary = AgentDebugDump.capture(play)
	for key: String in DUMP_KEYS:
		assert_true(dump.has(key), "the dump carries the save bag's %s" % key)
	var live: Dictionary = dump["live"]
	for key: String in LIVE_KEYS:
		assert_true(live.has(key), "the live overlay reports %s" % key)
	assert_eq(bool(live["observer_mode"]), play.observer_mode, "the overlay reads the session")
	assert_eq(int(live["selection"]), play.selected_province, "the overlay reports the selection")
	assert_eq(int(live["region"]), play.region_index, "the overlay reports the region")
	assert_true(live["hud"] is Dictionary, "hud hints ride with the overlay")
	assert_ne(JSON.stringify(dump), "", "the full dump is JSON-safe")


func test_a_session_without_a_world_still_dumps_its_overlays() -> void:
	var dump: Dictionary = AgentDebugDump.capture(PlaySession.new())
	assert_true(dump.has("live"), "the overlays ride alone without a world")
	assert_false(dump.has("regions"), "an empty save bag carries no regions")
	assert_ne(JSON.stringify(dump), "", "the overlay-only dump is JSON-safe")


# --- the protocol frame --------------------------------------------------------


func test_ping_answers_and_keeps_the_id() -> void:
	var answer: Dictionary = AgentDebugDump.frame({"id": 1, "op": "ping"}, mounted.play)
	assert_true(bool(answer["ok"]), "ping answers ok")
	assert_eq(int(answer["id"]), 1, "the answer carries the request id")
	assert_true(bool(answer["data"]["pong"]), "ping pongs")


func test_session_reports_the_live_card() -> void:
	var play: PlaySession = mounted.play
	var answer: Dictionary = AgentDebugDump.frame({"id": 2, "op": "session"}, play)
	assert_true(bool(answer["ok"]), "session answers ok")
	var data: Dictionary = answer["data"]
	assert_eq(int(data["turn"]), play.turn, "the card names the turn")
	assert_eq(int(data["player_faction"]), play.player_faction, "the card names the crown")
	assert_eq(int(data["seed"]), play.map_seed, "the card names the seed")
	assert_ne(JSON.stringify(data), "", "the card is JSON-safe")


func test_dump_observer_and_get_answer_ok() -> void:
	var play: PlaySession = mounted.play
	var dump: Dictionary = AgentDebugDump.frame({"id": 3, "op": "dump"}, play)
	assert_true(bool(dump["ok"]), "dump answers ok")
	assert_true((dump["data"] as Dictionary).has("live"), "dump carries the overlays")
	var observer: Dictionary = AgentDebugDump.frame({"id": 4, "op": "observer"}, play)
	assert_true(bool(observer["ok"]), "observer answers ok")
	assert_true((observer["data"] as Dictionary).has("rows"), "observer is the scoreboard")
	var slice: Dictionary = AgentDebugDump.frame({"id": 5, "op": "get", "path": "session"}, play)
	assert_true(bool(slice["ok"]), "get answers ok")
	assert_eq(
		int(slice["data"]["turn"]), play.turn,
		"a top-level path slices the god-mode bag"
	)
	var nested: Dictionary = AgentDebugDump.frame(
		{"id": 6, "op": "get", "path": "live.ai_mode"}, play
	)
	assert_true(bool(nested["ok"]), "a nested path resolves")


func test_get_reports_unknown_and_missing_paths() -> void:
	var play: PlaySession = mounted.play
	var unknown: Dictionary = AgentDebugDump.frame({"id": 7, "op": "get", "path": "mystery"}, play)
	assert_false(bool(unknown["ok"]), "an unknown top-level key answers error")
	assert_true(String(unknown["error"]).contains("mystery"), "the error names the path")
	var missing: Dictionary = AgentDebugDump.frame({"id": 8, "op": "get"}, play)
	assert_false(bool(missing["ok"]), "a get without a path is an error")
	var deep: Dictionary = AgentDebugDump.frame(
		{"id": 9, "op": "get", "path": "live.nope.x"}, play
	)
	assert_false(bool(deep["ok"]), "a missing hop answers error")


func test_bad_frames_answer_errors_not_dangles() -> void:
	var play: PlaySession = mounted.play
	var unparseable: Dictionary = AgentDebugDump.frame(17, play)
	assert_false(bool(unparseable["ok"]), "a non-object frame answers an error")
	assert_eq(int(unparseable["id"]), -1, "no id can be kept")
	var unknown_op: Dictionary = AgentDebugDump.frame({"id": 10, "op": "mystery"}, play)
	assert_false(bool(unknown_op["ok"]), "an unknown op answers an error")
	var no_id: Dictionary = AgentDebugDump.frame({"op": "ping"}, play)
	assert_eq(int(no_id["id"]), -1, "a missing id falls back to -1")


func test_frames_without_a_session_error_but_ping_lives() -> void:
	var dump: Dictionary = AgentDebugDump.frame({"id": 11, "op": "dump"}, null)
	assert_false(bool(dump["ok"]), "no session, no dump")
	assert_eq(String(dump["error"]), "no live session", "the error is plain")
	var pong: Dictionary = AgentDebugDump.frame({"id": 12, "op": "ping"}, null)
	assert_true(bool(pong["ok"]), "ping still answers without a session")


# --- the flag parser -----------------------------------------------------------


func test_parse_port_reads_the_flag() -> void:
	assert_eq(AgentDebugBridge.parse_port(PackedStringArray()), 0, "no flag, no port")
	assert_eq(
		AgentDebugBridge.parse_port(PackedStringArray(["--agent-debug=8765"])),
		8765, "an explicit port wins"
	)
	assert_eq(
		AgentDebugBridge.parse_port(PackedStringArray(["--agent-debug"])),
		AgentDebugBridge.DEFAULT_PORT, "a bare flag takes the default port"
	)
	assert_eq(
		AgentDebugBridge.parse_port(PackedStringArray(["--quiet", "--agent-debug=1234"])),
		1234, "the flag is read among other user args"
	)


func test_parse_port_refuses_bad_ports() -> void:
	for bad: String in ["0", "-1", "99999", "abc", "8765x"]:
		assert_eq(
			AgentDebugBridge.parse_port(PackedStringArray(["--agent-debug=%s" % bad])),
			-1, "port %s is refused" % bad
		)
	assert_eq(
		AgentDebugBridge.parse_port(PackedStringArray(["--agent-debug-port=1"])),
		0, "a different flag sharing the prefix is ignored"
	)


func test_flag_mentioned_spots_a_misformed_enable() -> void:
	assert_false(
		AgentDebugBridge.flag_mentioned(PackedStringArray()),
		"an empty list never mentions the flag"
	)
	assert_false(
		AgentDebugBridge.flag_mentioned(PackedStringArray(["--quiet"])),
		"unrelated args do not mention the flag"
	)
	assert_true(
		AgentDebugBridge.flag_mentioned(PackedStringArray(["--agent-debug"])),
		"a bare flag is mentioned"
	)
	assert_true(
		AgentDebugBridge.flag_mentioned(PackedStringArray(["--agent-debug=8765"])),
		"an explicit port is mentioned"
	)
	assert_true(
		AgentDebugBridge.flag_mentioned(PackedStringArray(["--agent-debugfoo"])),
		"a misformed token still mentions the flag for the diagnostic"
	)


func test_resolve_launch_prefers_user_args_then_cmdline() -> void:
	var from_user: Dictionary = AgentDebugBridge.resolve_launch(
		PackedStringArray(["--agent-debug=1234"]),
		PackedStringArray(["--agent-debug=9999"]),
	)
	assert_eq(int(from_user["port"]), 1234, "user args win over the full cmdline")
	assert_false(bool(from_user["warn_unparsed"]), "a parsed port needs no warn")
	var from_cmdline: Dictionary = AgentDebugBridge.resolve_launch(
		PackedStringArray(),
		PackedStringArray(["--agent-debug=4321"]),
	)
	assert_eq(int(from_cmdline["port"]), 4321, "Android-style cmdline is the fallback")
	assert_false(bool(from_cmdline["warn_unparsed"]), "a cmdline parse needs no warn")
	var absent: Dictionary = AgentDebugBridge.resolve_launch(
		PackedStringArray(["--quiet"]),
		PackedStringArray(["--path", "."]),
	)
	assert_eq(int(absent["port"]), 0, "no flag means the bridge stays off")
	assert_false(bool(absent["warn_unparsed"]), "absence is not a misform")
	var misformed: Dictionary = AgentDebugBridge.resolve_launch(
		PackedStringArray(),
		PackedStringArray(["--agent-debugfoo"]),
	)
	assert_eq(int(misformed["port"]), 0, "a misformed token does not parse")
	assert_true(bool(misformed["warn_unparsed"]), "a misformed enable still warns")
	var bad_port: Dictionary = AgentDebugBridge.resolve_launch(
		PackedStringArray(["--agent-debug=0"]),
		PackedStringArray(),
	)
	assert_eq(int(bad_port["port"]), -1, "an out-of-range user port is refused")
	assert_false(bool(bad_port["warn_unparsed"]), "a refused parse is not unparsed")


# --- the thin server -----------------------------------------------------------


func test_the_screen_hosts_an_inert_bridge() -> void:
	var bridge: AgentDebugBridge = mounted.get_node_or_null("AgentDebugBridge") as AgentDebugBridge
	assert_not_null(bridge, "the map screen hosts the bridge")
	if bridge == null:
		return
	assert_false(bridge.is_listening(), "the bridge is off without the flag")
	assert_eq(bridge.play, mounted.play, "the bridge holds the live session")


func test_start_stop_and_a_live_loopback_round_trip() -> void:
	var bridge := AgentDebugBridge.new()
	bridge.name = "AgentDebugBridgeProbe"
	bridge.play = mounted.play
	add_child(bridge)
	bridge.start(0)
	assert_false(bridge.is_listening(), "an out-of-range port never listens")
	var bound: int = bridge.start_first_free(9377)
	assert_true(bound > 0, "the bridge binds a loopback port")
	var ws := WebSocketPeer.new()
	ws.connect_to_url("ws://127.0.0.1:%d" % bound)
	var opened: bool = _await_open(bridge, ws)
	assert_true(opened, "a local peer completes the handshake")
	if opened:
		ws.send_text('{"id":7,"op":"ping"}')
		var reply: String = _await_reply(bridge, ws)
		assert_ne(reply, "", "the bridge answers the frame")
		var answer: Variant = JSON.parse_string(reply)
		if typeof(answer) == TYPE_DICTIONARY:
			assert_eq(int(answer["id"]), 7, "the reply keeps the request id")
			assert_true(bool(answer["ok"]), "ping rides the live socket")
	bridge.stop()
	assert_false(bridge.is_listening(), "stop closes the listener")
	bridge.free()


func test_the_enable_file_optin_is_read_and_consumed() -> void:
	# The Android path: the launcher alias drops the launch intent's extra, so
	# the bridge also accepts a one-line `user://agent_debug.enable`. One
	# boot, one file: it is removed when the boot acts on it.
	var handle := FileAccess.open("user://agent_debug.enable", FileAccess.WRITE)
	handle.store_line("9377")
	handle = null
	var bridge := AgentDebugBridge.new()
	bridge.name = "AgentDebugBridgeFile"
	add_child(bridge)
	assert_true(bridge.is_listening(), "the enable file starts the listener")
	assert_eq(bridge.port, 9377, "the file names the port")
	assert_false(
		FileAccess.file_exists("user://agent_debug.enable"),
		"a consumed enable file is removed"
	)
	bridge.stop()
	bridge.free()


func test_an_empty_enable_file_takes_the_default_port() -> void:
	# Parse-only: binding DEFAULT_PORT under `--parallel` races any other
	# worker that already holds 8765 and used to fail the suite on listen.
	# The opt-in wire (file → start) is covered with an exclusive port above.
	var handle := FileAccess.open("user://agent_debug.enable", FileAccess.WRITE)
	handle.store_line("")
	handle = null
	assert_eq(
		AgentDebugBridge.read_enable_file(),
		AgentDebugBridge.DEFAULT_PORT,
		"empty file, default port"
	)
	assert_false(
		FileAccess.file_exists("user://agent_debug.enable"),
		"a consumed enable file is removed"
	)


func _await_open(bridge: AgentDebugBridge, ws: WebSocketPeer) -> bool:
	for _attempt in 200:
		ws.poll()
		bridge._process(0.0)
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			return true
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			return false
		OS.delay_msec(2)
	return false


func _await_reply(bridge: AgentDebugBridge, ws: WebSocketPeer) -> String:
	for _attempt in 200:
		bridge._process(0.0)
		ws.poll()
		if ws.get_available_packet_count() > 0:
			return ws.get_packet().get_string_from_utf8()
		OS.delay_msec(2)
	return ""
