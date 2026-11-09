extends GdToolsTest
## Fleet orders end-to-end through the real map screen (wiki: ships-and-naval).
## Kept separate from test_map_screen so each native suite stays inside the
## coverage runner's per-suite timeout.

const Fixture = preload("res://tests/map_fixture.gd")

var _screen: MapScreen = null


func before_each() -> void:
	_screen = Fixture.attach_screen(self)


func after_each() -> void:
	if is_instance_valid(_screen):
		_screen.free()
	_screen = null


func test_selecting_a_player_fleet_opens_orders() -> void:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	_screen.ship_layer.select(ship)
	assert_true(_screen.hud.panels.is_fleet_panel_open())
	assert_false(_screen.hud.panels.is_panel_open())
	assert_eq(_screen.overlay.move_zones, NavalMovement.destination_zones(_screen.model, fleet))


func test_fleet_dossier_can_dock_left_or_right() -> void:
	var ship: Ship = _player_ship_at_sea()
	_screen.ship_layer.select(ship)
	assert_eq(_screen.hud.panels.dock.side, PanelDock.Side.RIGHT)
	_screen.hud.panels.toggle_dock_side()
	assert_eq(_screen.hud.panels.dock.side, PanelDock.Side.LEFT)
	assert_eq(_screen.hud._fleet_wrap.anchor_left, 0.0)
	assert_true(_screen.hud.panels.is_fleet_panel_open())
	_screen.hud.panels.toggle_dock_side()
	assert_eq(_screen.hud.panels.dock.side, PanelDock.Side.RIGHT)
	assert_eq(_screen.hud._fleet_wrap.anchor_left, 1.0)


func test_transfer_owner_reassigns_a_squadron_and_its_marker() -> void:
	var fleet: FleetState = _screen.ship_layer.fleets[0]
	var from_id: int = fleet.owner
	var to_id: int = 1 if from_id != 1 else 2
	_screen.ship_layer.transfer_owner(from_id, to_id)
	assert_eq(fleet.owner, to_id)
	var marker: Ship = _screen.ship_layer.ship_for(fleet)
	assert_not_null(marker)
	assert_eq(marker.faction, to_id)


func test_ordering_a_move_spends_the_turn_and_reveals_the_zone() -> void:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	_screen.ship_layer.select(ship)
	var zone: int = NavalMovement.destination_zones(_screen.model, fleet)[0]
	var tile: Vector2i = _screen.model.sea_zones[zone].tiles[0]

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
	MapPlayFleets.try_order(_screen.play, _screen.model.sea_zones[zone].tiles[0])
	var zone_after_move: int = fleet.sea_zone
	var next_zone: int = NavalMovement.destination_zones(_screen.model, fleet)[0]
	var toasts_before: int = _screen.hud._toast_box.get_child_count()

	assert_true(MapPlayFleets.try_order(_screen.play, _screen.model.sea_zones[next_zone].tiles[0]))

	assert_eq(fleet.sea_zone, zone_after_move)
	assert_eq(_screen.hud._toast_box.get_child_count(), toasts_before + 1)


func test_docking_puts_the_fleet_in_port() -> void:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	_screen.ship_layer.select(ship)
	var ports: Array[int] = NavalMovement.dockable_provinces(_screen.model, fleet)
	assert_gt(ports.size(), 0)
	var province_id: int = ports[0]
	var port: Vector2i = _screen.model.provinces[province_id].port_tile

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

	assert_false(MapPlayFleets.try_order(_screen.play, _screen.model.sea_zones[zone].tiles[0]))

	assert_eq(fleet.sea_zone, zone_before)
	assert_false(fleet.moved)


func test_end_turn_restores_fleet_moves() -> void:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	_screen.ship_layer.select(ship)
	var zone: int = NavalMovement.destination_zones(_screen.model, fleet)[0]
	MapPlayFleets.try_order(_screen.play, _screen.model.sea_zones[zone].tiles[0])
	assert_true(fleet.moved)

	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)

	assert_false(fleet.moved)
	assert_gt(_screen.overlay.move_zones.size(), 0)


func test_end_turn_leaves_unknown_tiles_unknown() -> void:
	var zone_id: int = _remote_zone()
	assert_gt(zone_id, -1)
	var tile: Vector2i = _screen.model.sea_zones[zone_id].tiles[0]
	var index: int = _screen.model.index_of(tile.x, tile.y)
	_screen.visibility.lower_to(index, VisibilityModel.Level.UNKNOWN)
	_screen.overlay.sync_visibility(_screen.visibility, [index])

	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)

	assert_eq(_screen.visibility.level_at(tile.x, tile.y), VisibilityModel.Level.UNKNOWN)
	assert_eq(_screen.overlay.fog_state_at(tile.x, tile.y), MapOverlay.FOG_UNKNOWN)


func test_end_turn_refogs_distant_known_waters() -> void:
	var zone_id: int = _remote_zone()
	assert_gt(zone_id, -1)
	var tile: Vector2i = _screen.model.sea_zones[zone_id].tiles[0]
	var index: int = _screen.model.index_of(tile.x, tile.y)
	_screen.visibility.raise_to(index, VisibilityModel.Level.FULLY_VISIBLE)
	_screen.overlay.sync_visibility(_screen.visibility, [index])

	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)

	assert_eq(_screen.visibility.level_at(tile.x, tile.y), VisibilityModel.Level.FOGGED)
	assert_eq(_screen.overlay.fog_state_at(tile.x, tile.y), MapOverlay.FOG_FOGGED)


func test_end_turn_reveals_owned_coastal_waters() -> void:
	var zones: Array[int] = []
	for zone: SeaZoneState in _screen.model.sea_zones:
		var zone_id: int = int(zone.id)
		if _screen.visibility.owns_coast(zone_id):
			zones.append(zone_id)
	assert_gt(zones.size(), 0)
	var tile: Vector2i = _screen.model.sea_zones[zones[0]].tiles[0]
	var index: int = _screen.model.index_of(tile.x, tile.y)
	_screen.visibility.lower_to(index, VisibilityModel.Level.FOGGED)
	_screen.overlay.sync_visibility(_screen.visibility, [index])

	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)

	assert_eq(
		_screen.visibility.level_at(tile.x, tile.y), VisibilityModel.Level.FULLY_VISIBLE
	)
	assert_eq(_screen.overlay.fog_state_at(tile.x, tile.y), MapOverlay.FOG_VISIBLE)


func test_enemy_markers_follow_fog_intel() -> void:
	var enemy: Ship = _enemy_ship()
	var fleet: FleetState = _screen.ship_layer.fleet_of(enemy)
	var tile: Vector2i = _screen.model.sea_zones[fleet.sea_zone].tiles[0]
	var index: int = _screen.model.index_of(tile.x, tile.y)

	_screen.visibility.lower_to(index, VisibilityModel.Level.FOGGED)
	_screen.overlay.sync_visibility(_screen.visibility, [index])
	MapPlayFleets.refresh_visibility(_screen.play)
	assert_false(enemy.visible)

	_screen.visibility.raise_to(index, VisibilityModel.Level.FULLY_VISIBLE)
	_screen.overlay.sync_visibility(_screen.visibility, [index])
	MapPlayFleets.refresh_visibility(_screen.play)
	assert_true(enemy.visible)


func test_a_fleet_crosses_the_passage_into_the_new_world() -> void:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	var zone: int = _old_world_passage()
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = zone
	fleet.province = MapModel.NO_ID
	_screen.ship_layer.select(ship)
	var link: Dictionary = _screen.world.warp_partner(FactionCatalog.OLD_WORLD, zone)

	assert_true(MapPlayFleets.try_order(_screen.play, _screen.model.sea_zone_data(zone).tiles[0]))

	assert_eq(_screen.region_index, FactionCatalog.NEW_WORLD, "the view follows the fleet")
	assert_eq(_screen.model.region_id, FactionCatalog.NEW_WORLD)
	assert_eq(fleet.sea_zone, int(link["to_zone"]))
	assert_true(fleet.moved)
	assert_true(_screen.ship_layer.fleets.has(fleet), "it sails the New World now")
	assert_false(_roster(FactionCatalog.OLD_WORLD).has(fleet), "it left the Old World roster")
	assert_eq(_screen.ship_layer.selected_ship, _screen.ship_layer.ship_for(fleet))
	assert_eq(_zone_fog(fleet.sea_zone), MapOverlay.FOG_VISIBLE, "arrival waters reveal")
	assert_true(_unique_fleet_ids(), "both rosters keep distinct fleet ids")


func test_a_crossed_fleet_cannot_cross_again_this_turn() -> void:
	var fleet: FleetState = _cross_to_new_world()
	var zone_after: int = fleet.sea_zone
	var region_after: int = _screen.region_index
	var toasts_before: int = _screen.hud._toast_box.get_child_count()

	assert_true(MapPlayFleets.try_order(_screen.play, _passage_tile(zone_after)))

	assert_eq(fleet.sea_zone, zone_after)
	assert_eq(_screen.region_index, region_after)
	assert_eq(_screen.hud._toast_box.get_child_count(), toasts_before + 1)


func test_a_crossed_fleet_sails_back_on_a_later_turn() -> void:
	var fleet: FleetState = _cross_to_new_world()

	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)
	assert_false(fleet.moved, "the passage crossing spent only that turn's move")
	var zone: int = fleet.sea_zone

	assert_true(MapPlayFleets.try_order(_screen.play, _passage_tile(zone)))

	assert_eq(_screen.region_index, FactionCatalog.OLD_WORLD)
	assert_true(_roster(FactionCatalog.OLD_WORLD).has(fleet))
	assert_true(_screen.world.is_warp_zone(FactionCatalog.OLD_WORLD, fleet.sea_zone))


func test_the_fleet_dossier_names_the_passage() -> void:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = _old_world_passage()

	_screen.ship_layer.select(ship)

	assert_true(_screen.hud._fleet_panel._hint.text.contains("Passage"))
	assert_true(_screen.hud._fleet_panel._hint.text.contains("New World"))


func _cross_to_new_world() -> FleetState:
	var ship: Ship = _player_ship_at_sea()
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = _old_world_passage()
	fleet.province = MapModel.NO_ID
	_screen.ship_layer.select(ship)
	MapPlayFleets.try_order(_screen.play, _passage_tile(fleet.sea_zone))
	assert_eq(_screen.region_index, FactionCatalog.NEW_WORLD)
	return fleet


func _old_world_passage() -> int:
	var zones: Array[int] = _screen.world.warp_zones(FactionCatalog.OLD_WORLD)
	assert_gt(zones.size(), 0, "the Old World has a passage")
	return zones[0]


func _passage_tile(zone_id: int) -> Vector2i:
	return _screen.model.sea_zone_data(zone_id).tiles[0]


func _zone_fog(zone_id: int) -> int:
	var tile: Vector2i = _passage_tile(zone_id)
	return _screen.overlay.fog_state_at(tile.x, tile.y)


func _roster(region: int) -> Array[FleetState]:
	var stored: Array[FleetState] = []
	stored.assign(_screen.ship_layer.regions.value(region, []))
	return stored


func _unique_fleet_ids() -> bool:
	var seen: Dictionary = {}
	for fleet: FleetState in _screen.ship_layer.fleets:
		if seen.has(fleet.id):
			return false
		seen[fleet.id] = true
	return true


func _player_ship_at_sea() -> Ship:
	for ship: Ship in _screen.ship_layer.ships:
		var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
		if fleet != null and fleet.owner == MapScreen.PLAYER_FACTION and fleet.is_at_sea():
			return ship
	return _screen.ship_layer.ships[0]


# --- the naval yard -----------------------------------------------------------


func test_the_capital_dossier_opens_the_shipyard() -> void:
	var capital: int = _screen.play.capital_province
	assert_gte(capital, 0, "the fixture crowns a capital")

	_screen.play.selected_province = capital
	MapPlayFleets.open_yard(_screen.play)

	assert_true(_screen.hud.panels.is_fleet_panel_open())
	assert_true(_screen.hud.panels.fleet_panel._yard_open)
	assert_false(_screen.hud.panels.fleet_panel._yard_rows.is_empty())


func test_launching_pays_the_row_and_moors_the_hull() -> void:
	var capital: int = _screen.play.capital_province
	_screen.play.selected_province = capital
	var econ: PlayerEconomy = _screen.play.economy.economy
	econ.treasury = 60000
	var treasury: int = econ.treasury
	var peasants: int = econ.available_peasants()
	var hulls: int = _screen.ship_layer.hull_count_all(MapScreen.PLAYER_FACTION)

	MapPlayFleets.on_action(_screen.play, "yard:build:carrack")

	var fleet: FleetState = _screen.ship_layer.home_fleet(capital)
	assert_not_null(fleet, "the launch founds or joins the home fleet")
	assert_eq(fleet.count_of_type("carrack"), 1)
	assert_eq(_screen.ship_layer.hull_count_all(MapScreen.PLAYER_FACTION), hulls + 1)
	assert_eq(econ.treasury, treasury - ShipEconomy.treasury_cost("carrack"))
	assert_eq(econ.available_peasants(), peasants - 1)


func test_breaking_up_a_hull_asks_once() -> void:
	var capital: int = _screen.play.capital_province
	_screen.play.selected_province = capital
	_screen.play.economy.economy.treasury = 60000
	MapPlayFleets.on_action(_screen.play, "yard:build:carrack")
	var fleet: FleetState = _screen.ship_layer.home_fleet(capital)
	assert_not_null(fleet, "the yard founds the home fleet")
	var hull_id: String = fleet.hulls[fleet.hulls.size() - 1]
	var panel: FleetPanel = _screen.hud.panels.fleet_panel

	panel._on_scrap_pressed(hull_id)

	assert_eq(panel._armed_hull, hull_id, "the first tap only arms")
	assert_true(fleet.hulls.has(hull_id))

	panel._on_scrap_pressed(hull_id)

	assert_false(fleet.hulls.has(hull_id), "the second tap scraps")


func _enemy_ship() -> Ship:
	for ship: Ship in _screen.ship_layer.ships:
		var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
		if fleet != null and fleet.owner != MapScreen.PLAYER_FACTION:
			return ship
	return _screen.ship_layer.ships[0]


func _remote_zone() -> int:
	var occupied: Array[int] = _screen.ship_layer.at_sea_zones(MapScreen.PLAYER_FACTION)
	for zone: SeaZoneState in _screen.model.sea_zones:
		var zone_id: int = int(zone.id)
		if _screen.visibility.owns_coast(zone_id) or occupied.has(zone_id):
			continue
		return zone_id
	return -1
