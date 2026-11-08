extends GdToolsTest
## Fleet orders end-to-end through the real map screen (wiki: ships-and-naval).
## Kept separate from test_map_screen so each native suite stays inside the
## coverage runner's per-suite timeout.

var _screen: MapScreen = null


func before_each() -> void:
	_screen = load("res://scenes/map_screen.tscn").instantiate()
	_screen.map_width = 64
	_screen.map_height = 42
	add_child(_screen)


func after_each() -> void:
	if is_instance_valid(_screen):
		_screen.queue_free()
	_screen = null


func test_selecting_a_player_fleet_opens_orders() -> void:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	_screen.ship_layer.select(ship)
	assert_true(_screen.hud.is_fleet_panel_open())
	assert_false(_screen.hud._panel_open)
	assert_eq(_screen.overlay.move_zones, NavalMovement.destination_zones(_screen.model, fleet))


func test_ordering_a_move_spends_the_turn_and_reveals_the_zone() -> void:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	_screen.ship_layer.select(ship)
	var zone: int = NavalMovement.destination_zones(_screen.model, fleet)[0]
	var tile: Vector2i = _screen.model.sea_zones[zone]["tiles"][0]

	assert_true(MapPlayFleets.try_order(_screen.play, tile))

	assert_eq(fleet.sea_zone, zone)
	assert_true(fleet.moved)
	assert_eq(_screen.overlay.move_zones.size(), 0)
	assert_eq(_screen.overlay.fog_state_at(tile.x, tile.y), MapOverlay.FOG_VISIBLE)
	assert_eq(
		_screen.visibility.level_at(tile.x, tile.y), VisibilityModel.Level.FULLY_VISIBLE
	)


func test_a_fleet_cannot_move_twice_in_one_turn() -> void:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	_screen.ship_layer.select(ship)
	var zone: int = NavalMovement.destination_zones(_screen.model, fleet)[0]
	MapPlayFleets.try_order(_screen.play, _screen.model.sea_zones[zone]["tiles"][0])
	var zone_after_move: int = fleet.sea_zone
	var next_zone: int = NavalMovement.destination_zones(_screen.model, fleet)[0]
	var toasts_before: int = _screen.hud._toast_box.get_child_count()

	assert_true(MapPlayFleets.try_order(_screen.play, _screen.model.sea_zones[next_zone]["tiles"][0]))

	assert_eq(fleet.sea_zone, zone_after_move)
	assert_eq(_screen.hud._toast_box.get_child_count(), toasts_before + 1)


func test_docking_puts_the_fleet_in_port() -> void:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	_screen.ship_layer.select(ship)
	var ports: Array[int] = NavalMovement.dockable_provinces(_screen.model, fleet)
	assert_gt(ports.size(), 0)
	var province_id: int = ports[0]
	var port: Vector2i = _screen.model.provinces[province_id]["port_tile"]

	assert_true(MapPlayFleets.try_order(_screen.play, port))

	assert_eq(fleet.location, FleetState.Location.IN_PORT)
	assert_eq(fleet.province, province_id)
	assert_true(ship.docked)
	assert_eq(_screen.overlay.move_provinces.size(), 0)


func test_enemy_fleets_reject_player_orders() -> void:
	var enemy: Ship = _enemy_ship()
	var fleet: FleetState = _screen.ship_layer.fleet_of(enemy)
	_screen.ship_layer.select(enemy)
	var zone: int = NavalMovement.destination_zones(_screen.model, fleet)[0]
	var zone_before: int = fleet.sea_zone

	assert_false(MapPlayFleets.try_order(_screen.play, _screen.model.sea_zones[zone]["tiles"][0]))

	assert_eq(fleet.sea_zone, zone_before)
	assert_false(fleet.moved)


func test_end_turn_restores_fleet_moves() -> void:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	_screen.ship_layer.select(ship)
	var zone: int = NavalMovement.destination_zones(_screen.model, fleet)[0]
	MapPlayFleets.try_order(_screen.play, _screen.model.sea_zones[zone]["tiles"][0])
	assert_true(fleet.moved)

	MapPlayTurn.end_turn(_screen.play)

	assert_false(fleet.moved)
	assert_gt(_screen.overlay.move_zones.size(), 0)


func test_end_turn_leaves_unknown_tiles_unknown() -> void:
	var zone_id: int = _remote_zone()
	assert_gt(zone_id, -1)
	var tile: Vector2i = _screen.model.sea_zones[zone_id]["tiles"][0]
	var index: int = _screen.model.index_of(tile.x, tile.y)
	_screen.visibility.lower_to(index, VisibilityModel.Level.UNKNOWN)
	_screen.overlay.sync_visibility(_screen.visibility, [index])

	MapPlayTurn.end_turn(_screen.play)

	assert_eq(_screen.visibility.level_at(tile.x, tile.y), VisibilityModel.Level.UNKNOWN)
	assert_eq(_screen.overlay.fog_state_at(tile.x, tile.y), MapOverlay.FOG_UNKNOWN)


func test_end_turn_refogs_distant_known_waters() -> void:
	var zone_id: int = _remote_zone()
	assert_gt(zone_id, -1)
	var tile: Vector2i = _screen.model.sea_zones[zone_id]["tiles"][0]
	var index: int = _screen.model.index_of(tile.x, tile.y)
	_screen.visibility.raise_to(index, VisibilityModel.Level.FULLY_VISIBLE)
	_screen.overlay.sync_visibility(_screen.visibility, [index])

	MapPlayTurn.end_turn(_screen.play)

	assert_eq(_screen.visibility.level_at(tile.x, tile.y), VisibilityModel.Level.FOGGED)
	assert_eq(_screen.overlay.fog_state_at(tile.x, tile.y), MapOverlay.FOG_FOGGED)


func test_end_turn_reveals_owned_coastal_waters() -> void:
	var zones: Array[int] = []
	for zone: Dictionary in _screen.model.sea_zones:
		var zone_id: int = int(zone["id"])
		if _screen.visibility.owns_coast(zone_id):
			zones.append(zone_id)
	assert_gt(zones.size(), 0)
	var tile: Vector2i = _screen.model.sea_zones[zones[0]]["tiles"][0]
	var index: int = _screen.model.index_of(tile.x, tile.y)
	_screen.visibility.lower_to(index, VisibilityModel.Level.FOGGED)
	_screen.overlay.sync_visibility(_screen.visibility, [index])

	MapPlayTurn.end_turn(_screen.play)

	assert_eq(
		_screen.visibility.level_at(tile.x, tile.y), VisibilityModel.Level.FULLY_VISIBLE
	)
	assert_eq(_screen.overlay.fog_state_at(tile.x, tile.y), MapOverlay.FOG_VISIBLE)


func test_enemy_markers_follow_fog_intel() -> void:
	var enemy: Ship = _enemy_ship()
	var fleet: FleetState = _screen.ship_layer.fleet_of(enemy)
	var tile: Vector2i = _screen.model.sea_zones[fleet.sea_zone]["tiles"][0]
	var index: int = _screen.model.index_of(tile.x, tile.y)

	_screen.visibility.lower_to(index, VisibilityModel.Level.FOGGED)
	_screen.overlay.sync_visibility(_screen.visibility, [index])
	MapPlayFleets.refresh_visibility(_screen.play)
	assert_false(enemy.visible)

	_screen.visibility.raise_to(index, VisibilityModel.Level.FULLY_VISIBLE)
	_screen.overlay.sync_visibility(_screen.visibility, [index])
	MapPlayFleets.refresh_visibility(_screen.play)
	assert_true(enemy.visible)


func _player_ship_at_sea() -> Ship:
	for ship: Ship in _screen.ship_layer.ships:
		var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
		if fleet != null and fleet.owner == MapScreen.PLAYER_FACTION and fleet.is_at_sea():
			return ship
	return _screen.ship_layer.ships[0]


func _enemy_ship() -> Ship:
	for ship: Ship in _screen.ship_layer.ships:
		var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
		if fleet != null and fleet.owner != MapScreen.PLAYER_FACTION:
			return ship
	return _screen.ship_layer.ships[0]


func _remote_zone() -> int:
	var occupied: Array[int] = _screen.ship_layer.at_sea_zones(MapScreen.PLAYER_FACTION)
	for zone: Dictionary in _screen.model.sea_zones:
		var zone_id: int = int(zone["id"])
		if _screen.visibility.owns_coast(zone_id) or occupied.has(zone_id):
			continue
		return zone_id
	return -1
