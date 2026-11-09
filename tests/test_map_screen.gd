# gdlint: disable=max-public-methods
extends GdToolsTest
## Integration: the world view — map build, camera, chart (fog) and turn flow.
## Crown orders (fleets, civilians, estates, leaders) live in
## test_map_screen_crown_orders so each native suite stays inside the
## coverage runner's per-suite timeout.

const Fixture = preload("res://tests/map_fixture.gd")

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


func test_country_borders_are_built_for_every_owner() -> void:
	var borders: Dictionary = _screen.overlay._country_borders
	assert_true(borders.size() >= FactionCatalog.great_power_ids().size())
	for owner: int in borders.keys():
		assert_true(FactionCatalog.has_faction(owner))


func test_region_switch_keeps_fleets_and_chart_state() -> void:
	var fleet_id: int = _screen.ship_layer.fleets[0].id
	var tile: Vector2i = _screen.model.province_tiles(_foreign_province())[0]
	var index: int = _screen.model.index_of(tile.x, tile.y)
	_screen.visibility.raise_to(index, VisibilityModel.Level.FULLY_VISIBLE)

	_screen._cycle_region()
	_screen._cycle_region()

	assert_eq(_screen.ship_layer.fleets[0].id, fleet_id)
	assert_eq(
		_screen.visibility.level_at(tile.x, tile.y), VisibilityModel.Level.FULLY_VISIBLE
	)


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
	MapPlayTurn.focus_capital(_screen.play)
	for _step in 20:
		_screen.camera._process(0.2)
	var expected: Vector2 = CameraMath.clamp_center(
		MapPlayTurn.capital_world(_screen.play),
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
	assert_eq(_screen.ship_layer.selected_ship, ship)
	assert_true(ship.selected)


func test_end_turn_advances_calendar_and_treasury() -> void:
	var turn_before: int = _screen.turn
	MapPlayTurn.end_turn(_screen.play)
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
	var before: float = _screen.camera.target_zoom
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

	assert_eq(enemy_fleet.ship_count(), 0)
	assert_eq(player_fleet.ship_count(), 1)
	assert_eq(_screen.ship_layer.hull_count(2), 0)
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

	assert_false(_screen.play.diplomacy.relation(0, 2).at_war)
	assert_eq(player_fleet.ship_count() + other_fleet.ship_count(), hulls_before)


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
