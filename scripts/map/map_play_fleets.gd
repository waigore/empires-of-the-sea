class_name MapPlayFleets
extends RefCounted
## Fleet selection, sail and dock orders, and fog intel for enemy markers.
## Naval rules stay in NavalMovement; this only drives the screen.


static func select(screen: MapScreen, ship: Ship) -> void:
	if ship == null:
		return
	var fleet: FleetState = screen.ship_layer.fleet_of(ship)
	if fleet == null:
		return
	screen.selected_province = -1
	screen.overlay.select_province(-1)
	screen.hud.hide_province()
	screen.hud.show_fleet(screen.model, fleet, fleet.owner == MapScreen.PLAYER_FACTION)
	refresh_options(screen, fleet)
	if fleet.owner != MapScreen.PLAYER_FACTION:
		screen.hud.toast("Fleet of %s — observe only" % MapGenerator.FACTION_NAMES[fleet.owner])


static func refresh_options(screen: MapScreen, fleet: FleetState) -> void:
	screen.overlay.clear_move_options()
	if fleet == null or fleet.owner != MapScreen.PLAYER_FACTION or fleet.moved:
		return
	var options: Dictionary = NavalMovement.valid_destinations(screen.model, fleet)
	var zones: Array[int] = []
	for zone: int in options.get("sea_zones", []):
		zones.append(zone)
	var provinces: Array[int] = []
	for province: int in options.get("provinces", []):
		provinces.append(province)
	screen.overlay.show_move_options(zones, provinces)


static func try_order(screen: MapScreen, tile: Vector2i) -> bool:
	var fleet: FleetState = screen.ship_layer.fleet_of(screen.ship_layer.selected_ship)
	if fleet == null or fleet.owner != MapScreen.PLAYER_FACTION:
		return false
	var zone_id: int = screen.model.sea_zone_at(tile.x, tile.y)
	if zone_id != MapModel.NO_ID:
		return try_sea_order(screen, fleet, zone_id)
	var province_id: int = screen.model.province_at(tile.x, tile.y)
	if province_id == MapModel.NO_ID:
		return false
	if not NavalMovement.dockable_provinces(screen.model, fleet).has(province_id):
		return false
	var port_result: Dictionary = screen.ship_layer.order(
		fleet, FleetState.Location.IN_PORT, province_id
	)
	if bool(port_result.get("ok", false)):
		return true
	screen.hud.toast(String(port_result.get("reason", "")))
	return true


static func try_sea_order(screen: MapScreen, fleet: FleetState, zone_id: int) -> bool:
	if fleet.moved:
		screen.hud.toast("This fleet has already moved this turn.")
		return true
	if zone_id == fleet.sea_zone:
		screen.hud.toast("The fleet is already in the %s" % screen.model.sea_zone_name(zone_id))
		return true
	var result: Dictionary = screen.ship_layer.order(fleet, FleetState.Location.AT_SEA, zone_id)
	if bool(result.get("ok", false)):
		return true
	screen.hud.toast(String(result.get("reason", "")))
	return true


static func on_moved(screen: MapScreen, fleet: FleetState, result: Dictionary) -> void:
	if fleet.owner != MapScreen.PLAYER_FACTION:
		return
	screen.hud.show_fleet(screen.model, fleet, true)
	refresh_options(screen, fleet)
	var zone: int = int(result.get("entered_zone", -1))
	if zone >= 0:
		screen.hud.toast("The fleet enters the %s" % screen.model.sea_zone_name(zone))
	else:
		screen.hud.toast("The fleet docks at %s" % screen.model.province_name(fleet.province))
	refresh_visibility(screen)


static func on_zone_entered(screen: MapScreen, zone_id: int, ship: Ship) -> void:
	if ship == null or ship.faction != MapScreen.PLAYER_FACTION or screen.visibility == null:
		return
	var changed: Array = screen.visibility.reveal_sea_zone(zone_id)
	if not changed.is_empty():
		screen.overlay.sync_visibility(screen.visibility, changed)
	_announce_charted_coast(screen, changed)
	refresh_visibility(screen)


static func refresh_visibility(screen: MapScreen) -> void:
	for ship: Ship in screen.ship_layer.ships:
		var fleet: FleetState = screen.ship_layer.fleet_of(ship)
		if fleet == null:
			continue
		ship.visible = _known(screen, fleet)


## First sighting of a province's coast earns a quiet note, once per province.
static func _announce_charted_coast(screen: MapScreen, changed: Array) -> void:
	for raw: Variant in changed:
		var index: int = int(raw)
		var y: int = int(floor(float(index) / float(screen.model.width)))
		var x: int = index - y * screen.model.width
		if not screen.model.is_land(x, y):
			continue
		var province_id: int = screen.model.province_at(x, y)
		if province_id == MapModel.NO_ID or screen._charted_provinces.has(province_id):
			continue
		screen._charted_provinces[province_id] = true
		screen.hud.toast("The coast of %s is charted" % screen.model.province_name(province_id))
		screen.coast_charted.emit(province_id)
		return


static func _known(screen: MapScreen, fleet: FleetState) -> bool:
	if fleet.owner == MapScreen.PLAYER_FACTION or screen.visibility == null:
		return true
	var tile: Vector2i = _tile(screen, fleet)
	if tile.x < 0:
		return true
	return screen.visibility.level_at(tile.x, tile.y) == VisibilityModel.Level.FULLY_VISIBLE


static func _tile(screen: MapScreen, fleet: FleetState) -> Vector2i:
	if fleet.is_at_sea():
		var zone: Dictionary = screen.model.sea_zone_data(fleet.sea_zone)
		var tiles: Array = zone.get("tiles", [])
		if tiles.is_empty():
			return Vector2i(-1, -1)
		return tiles[0]
	var data: Dictionary = screen.model.province_data(fleet.province)
	return data.get("port_tile", Vector2i(-1, -1))
