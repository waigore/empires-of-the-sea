# gdlint: disable=max-public-methods
extends GdToolsTest
## Integration: the real map screen, driven through its own input handlers.

var _screen: MapScreen = null


func before_each() -> void:
	_screen = load("res://scenes/map_screen.tscn").instantiate()
	_screen.map_width = 64
	_screen.map_height = 42
	add_child(_screen)


func after_each() -> void:
	# Free immediately: queue_free leaves prior screens processing fog/ships and
	# starves the suite under coverage (process timeout).
	if is_instance_valid(_screen):
		_screen.free()
	_screen = null


func test_world_builds_with_map_ships_and_camera() -> void:
	assert_not_null(_screen.model)
	assert_gt(_screen.model.province_count(), 0)
	assert_eq(_screen.canvas.model, _screen.model)
	assert_eq(_screen.ship_layer.ships.size(), MapScreen.SHIP_COUNT)
	assert_gt(_screen.capital_province, -1)
	var map_width: float = MapGeo.world_size(_screen.model, MapScreen.TILE_SIZE).x
	assert_almost_eq(_screen.camera.map_size.x, map_width, 1.0)


func test_capital_tile_comes_from_the_capital_choice_phase() -> void:
	var province: Dictionary = _screen.model.province_data(_screen.capital_province)
	assert_true(bool(province["capital"]))
	assert_eq(_screen.capital_tile, Vector2i(province["capital_tile"]))
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
	var province_id: int = _inland_province()
	var world: Vector2 = _screen.model.province_center(province_id) * MapScreen.TILE_SIZE
	MapPlayInput.on_tapped(_screen.play, world)
	assert_eq(_screen.selected_province, province_id)
	assert_true(_screen.hud.is_panel_open())


func test_clicking_open_water_clears_the_selection() -> void:
	var province_id: int = _inland_province()
	MapPlayInput.on_tapped(_screen.play, _screen.model.province_center(province_id) * MapScreen.TILE_SIZE)
	assert_true(_screen.hud.is_panel_open())

	var sea_tile: Vector2i = _screen.model.sea_zones[0]["tiles"][0]
	MapPlayInput.on_tapped(_screen.play, MapGeo.tile_center(sea_tile.x, sea_tile.y, MapScreen.TILE_SIZE))
	assert_eq(_screen.selected_province, -1)
	assert_false(_screen.hud.is_panel_open())


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


func test_panel_orders_raise_a_toast() -> void:
	var province_id: int = _inland_province()
	MapPlayInput.on_tapped(_screen.play, _screen.model.province_center(province_id) * MapScreen.TILE_SIZE)
	var toasts_before: int = _screen.hud._toast_box.get_child_count()
	MapPlayInput.on_panel_action(_screen.play, "recruit")
	assert_eq(_screen.hud._toast_box.get_child_count(), toasts_before + 1)


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
	_screen.camera._handle_mouse_button(_mouse_button(true, Vector2(400, 300)))
	_screen.camera._handle_mouse_motion(_mouse_motion(Vector2(-120, -80)))
	_screen.camera._handle_mouse_button(_mouse_button(false, Vector2(400, 300)))
	assert_ne(_screen.camera.position, start)


func test_camera_never_leaves_the_map() -> void:
	_screen.camera.position = Vector2(-9000, -9000)
	_screen.camera._process(0.016)
	assert_true(_visible_inside_map())

	_screen.camera.position = Vector2(99999, 99999)
	_screen.camera._process(0.016)
	assert_true(_visible_inside_map())


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


func _visible_rect() -> Rect2:
	var half: Vector2 = _screen.camera.viewport_size() / (2.0 * _screen.camera.zoom.x)
	return Rect2(_screen.camera.position - half, half * 2.0)


func test_player_fleet_reveals_only_for_the_player() -> void:
	var zone: Dictionary = _screen.model.sea_zones[1]
	var tile: Vector2i = zone["tiles"][0]
	var index: int = _screen.model.index_of(tile.x, tile.y)
	_screen.overlay.set_fog_state(index, MapOverlay.FOG_FOGGED)
	var enemy := Ship.new()
	enemy.faction = 1
	MapPlayFleets.on_zone_entered(_screen.play, int(zone["id"]), enemy)
	assert_eq(_screen.overlay.fog_state_at(tile.x, tile.y), MapOverlay.FOG_FOGGED)
	enemy.free()


func test_hover_reports_the_province_under_the_cursor() -> void:
	var province_id: int = _inland_province()
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
	var foreign_tile: Vector2i = _screen.model.province_tiles(_foreign_province())[0]
	assert_eq(
		_screen.visibility.level_at(foreign_tile.x, foreign_tile.y),
		VisibilityModel.Level.FOGGED
	)
	assert_eq(
		_screen.overlay.fog_state_at(foreign_tile.x, foreign_tile.y), MapOverlay.FOG_FOGGED
	)


func test_end_turn_applies_fog_decay_to_foreign_coasts() -> void:
	var tile: Vector2i = _screen.model.province_tiles(_foreign_province())[0]
	var index: int = _screen.model.index_of(tile.x, tile.y)
	_screen.visibility.raise_to(index, VisibilityModel.Level.FULLY_VISIBLE)
	_screen.overlay.sync_visibility(_screen.visibility, [index])
	assert_eq(_screen.overlay.fog_state_at(tile.x, tile.y), MapOverlay.FOG_VISIBLE)
	MapPlayTurn.end_turn(_screen.play)
	assert_eq(_screen.overlay.fog_state_at(tile.x, tile.y), MapOverlay.FOG_FOGGED)


func test_player_fleet_reveal_charts_the_coastal_ring() -> void:
	var ship: Ship = _screen.ship_layer.ships[0]
	var zone_tiles: Array = _screen.model.sea_zone_data(ship.zone)["tiles"]
	var water: Vector2i = zone_tiles[0]
	var water_index: int = _screen.model.index_of(water.x, water.y)
	_screen.visibility.lower_to(water_index, VisibilityModel.Level.FOGGED)
	_screen.overlay.sync_visibility(_screen.visibility, [water_index])
	MapPlayFleets.on_zone_entered(_screen.play, ship.zone, ship)
	assert_eq(_screen.overlay.fog_state_at(water.x, water.y), MapOverlay.FOG_VISIBLE)
	var land: Vector2i = _coastal_land_of(ship.zone)
	assert_true(land.x >= 0)
	assert_eq(_screen.overlay.fog_state_at(land.x, land.y), MapOverlay.FOG_VISIBLE)


func test_unknown_land_is_reported_without_terrain_or_owner() -> void:
	var tile: Vector2i = _screen.model.province_tiles(_foreign_province())[0]
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
	var player_fleet: FleetState = _fleet_at_sea(MapScreen.PLAYER_FACTION)
	var enemy_fleet: FleetState = _fleet_at_sea(2)
	assert_not_null(player_fleet)
	assert_not_null(enemy_fleet)
	# Dock every other squadron so only these two share water.
	for fleet: FleetState in _screen.ship_layer.fleets:
		if fleet == player_fleet or fleet == enemy_fleet:
			continue
		fleet.location = FleetState.Location.IN_PORT
		fleet.province = int(_screen.model.provinces[0]["id"])
	player_fleet.set_hulls(["hull_player"], {"hull_player": "carrack"})
	enemy_fleet.set_hulls(["hull_enemy"], {"hull_enemy": "fluyte"})
	enemy_fleet.location = FleetState.Location.AT_SEA
	enemy_fleet.sea_zone = int(_screen.model.sea_zones[0]["id"])
	player_fleet.location = FleetState.Location.AT_SEA
	player_fleet.sea_zone = enemy_fleet.sea_zone
	var toasts_before: int = _screen.hud._toast_box.get_child_count()

	MapPlayTurn.end_turn(_screen.play)

	assert_eq(enemy_fleet.ship_count(), 0)
	assert_eq(player_fleet.ship_count(), 1)
	assert_eq(_screen.ship_layer.hull_count(2), 0)
	assert_gt(_screen.hud._toast_box.get_child_count(), toasts_before)


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
	assert_true(_screen.hud.is_civilian_panel_open())
	assert_false(_screen.hud.is_panel_open())


func test_a_work_order_costs_materials_and_completes_on_end_turn() -> void:
	var tile: Vector2i = _owned_resource_tile()
	assert_true(tile.x >= 0, "map has an owned resource tile")
	var builder: CivilianState = _screen.civilian_layer.units[1]
	assert_eq(builder.type_id, "builder")
	builder.tile = tile
	_screen.civilian_layer.select(builder)
	var lumber_before: int = int(_screen.stockpile["lumber"])
	MapPlayCivilians.on_action(_screen.play, "build_improvement")
	assert_eq(int(_screen.stockpile["lumber"]), lumber_before - 1)
	assert_true(builder.is_working())
	MapPlayTurn.end_turn(_screen.play)
	assert_eq(_screen.land_works.improvement_at(_screen.model, tile), 1)
	assert_true(builder.is_idle())


func test_training_a_civilian_spends_treasury_and_paper() -> void:
	MapPlayInput.select_province(_screen.play, _screen.capital_province, _capital_point())
	var units_before: int = _screen.civilian_layer.units.size()
	var treasury_before: int = _screen.treasury
	var paper_before: int = int(_screen.stockpile["paper"])
	MapPlayInput.on_panel_action(_screen.play, "train_explorer")
	assert_eq(_screen.treasury, treasury_before - 1000)
	assert_eq(int(_screen.stockpile["paper"]), paper_before - 2)
	assert_eq(_screen.civilian_layer.units.size(), units_before + 1)


func test_training_is_refused_outside_the_capital() -> void:
	var province_id: int = _foreign_province()
	MapPlayInput.select_province(
		_screen.play, province_id, _screen.model.province_center(province_id) * MapScreen.TILE_SIZE
	)
	var units_before: int = _screen.civilian_layer.units.size()
	var treasury_before: int = _screen.treasury
	MapPlayInput.on_panel_action(_screen.play, "train_explorer")
	assert_eq(_screen.civilian_layer.units.size(), units_before)
	assert_eq(_screen.treasury, treasury_before)


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


func _capital_estate_tile() -> Vector2i:
	var capital: Vector2i = _screen.capital_tile
	for offset: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var tile: Vector2i = capital + offset
		if not _screen.model.is_land(tile.x, tile.y):
			continue
		var province: int = _screen.model.province_at(tile.x, tile.y)
		if _screen.model.province_owner(province) != MapScreen.PLAYER_FACTION:
			continue
		_screen.model.resource[_screen.model.index_of(tile.x, tile.y)] = 0
		return tile
	return Vector2i(-1, -1)


func _capital_point() -> Vector2:
	return _screen.model.province_center(_screen.capital_province) * MapScreen.TILE_SIZE


func _owned_resource_tile() -> Vector2i:
	for province: Dictionary in _screen.model.provinces:
		if int(province["owner"]) != MapScreen.PLAYER_FACTION:
			continue
		for tile: Vector2i in province["tiles"]:
			if _screen.model.resource_at(tile.x, tile.y) >= 0:
				return tile
	return Vector2i(-1, -1)


func _fleet_at_sea(owner: int) -> FleetState:
	for fleet: FleetState in _screen.ship_layer.fleets:
		if fleet.owner == owner and fleet.is_at_sea():
			return fleet
	return null


func _foreign_province() -> int:
	for province: Dictionary in _screen.model.provinces:
		if int(province["owner"]) != MapScreen.PLAYER_FACTION:
			return int(province["id"])
	return -1


func _coastal_land_of(zone_id: int) -> Vector2i:
	var tiles: Array = _screen.model.sea_zone_data(zone_id).get("tiles", [])
	for tile: Vector2i in tiles:
		for offset: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var nx: int = tile.x + offset.x
			var ny: int = tile.y + offset.y
			if _screen.model.is_land(nx, ny):
				return Vector2i(nx, ny)
	return Vector2i(-1, -1)


func _inland_province() -> int:
	for province: Dictionary in _screen.model.provinces:
		if not bool(province["coastal"]) and int(province["area"]) > 30:
			return int(province["id"])
	return int(_screen.model.provinces[0]["id"])


func _mouse_button(pressed: bool, position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	return event


func _mouse_motion(relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	event.position = Vector2(400, 300)
	return event
