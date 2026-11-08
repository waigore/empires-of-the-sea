class_name MapPlayFleets
extends RefCounted
## Fleet selection, sail and dock orders, and fog intel for enemy markers.
## Naval rules stay in NavalMovement; this only drives PlaySession views.


static func select(play: PlaySession, ship: Ship) -> void:
	if ship == null:
		return
	var fleet: FleetState = play.ship_layer.fleet_of(ship)
	if fleet == null:
		return
	play.selected_province = -1
	play.overlay.select_province(-1)
	play.hud.hide_province()
	play.hud.show_fleet(play.model, fleet, fleet.owner == PlaySession.PLAYER_FACTION)
	refresh_options(play, fleet)
	if fleet.owner != PlaySession.PLAYER_FACTION:
		play.hud.toast("Fleet of %s — observe only" % FactionCatalog.name_of(fleet.owner))


static func refresh_options(play: PlaySession, fleet: FleetState) -> void:
	play.overlay.clear_move_options()
	if fleet == null or fleet.owner != PlaySession.PLAYER_FACTION or fleet.moved:
		return
	var options: Dictionary = NavalMovement.valid_destinations(play.model, fleet)
	var zones: Array[int] = []
	for zone: int in options.get("sea_zones", []):
		zones.append(zone)
	var provinces: Array[int] = []
	for province: int in options.get("provinces", []):
		provinces.append(province)
	play.overlay.show_move_options(zones, provinces)


static func try_order(play: PlaySession, tile: Vector2i) -> bool:
	var fleet: FleetState = play.ship_layer.fleet_of(play.ship_layer.selected_ship)
	if fleet == null or fleet.owner != PlaySession.PLAYER_FACTION:
		return false
	var zone_id: int = play.model.sea_zone_at(tile.x, tile.y)
	if zone_id != MapModel.NO_ID:
		return try_sea_order(play, fleet, zone_id)
	var province_id: int = play.model.province_at(tile.x, tile.y)
	if province_id == MapModel.NO_ID:
		return false
	if not NavalMovement.dockable_provinces(play.model, fleet).has(province_id):
		return false
	var port_result: Dictionary = play.ship_layer.order(
		fleet, FleetState.Location.IN_PORT, province_id
	)
	if bool(port_result.get("ok", false)):
		return true
	play.hud.toast(String(port_result.get("reason", "")))
	return true


static func try_sea_order(play: PlaySession, fleet: FleetState, zone_id: int) -> bool:
	if fleet.moved:
		play.hud.toast("This fleet has already moved this turn.")
		return true
	if zone_id == fleet.sea_zone:
		play.hud.toast("The fleet is already in the %s" % play.model.sea_zone_name(zone_id))
		return true
	var result: Dictionary = play.ship_layer.order(fleet, FleetState.Location.AT_SEA, zone_id)
	if bool(result.get("ok", false)):
		return true
	play.hud.toast(String(result.get("reason", "")))
	return true


static func on_moved(play: PlaySession, fleet: FleetState, result: Dictionary) -> void:
	if fleet.owner != PlaySession.PLAYER_FACTION:
		return
	play.hud.show_fleet(play.model, fleet, true)
	refresh_options(play, fleet)
	var zone: int = int(result.get("entered_zone", -1))
	if zone >= 0:
		play.hud.toast("The fleet enters the %s" % play.model.sea_zone_name(zone))
	else:
		play.hud.toast("The fleet docks at %s" % play.model.province_name(fleet.province))
	refresh_visibility(play)


static func on_zone_entered(play: PlaySession, zone_id: int, ship: Ship) -> void:
	if ship == null or ship.faction != PlaySession.PLAYER_FACTION or play.visibility == null:
		return
	var changed: Array = play.visibility.reveal_sea_zone(zone_id)
	if not changed.is_empty():
		play.overlay.sync_visibility(play.visibility, changed)
	_announce_charted_coast(play, changed)
	refresh_visibility(play)


static func refresh_visibility(play: PlaySession) -> void:
	for ship: Ship in play.ship_layer.ships:
		var fleet: FleetState = play.ship_layer.fleet_of(ship)
		if fleet == null:
			continue
		ship.visible = _known(play, fleet)


## First sighting of a province's coast earns a quiet note, once per province.
static func _announce_charted_coast(play: PlaySession, changed: Array) -> void:
	for raw: Variant in changed:
		var index: int = int(raw)
		var y: int = int(floor(float(index) / float(play.model.width)))
		var x: int = index - y * play.model.width
		if not play.model.is_land(x, y):
			continue
		var province_id: int = play.model.province_at(x, y)
		if province_id == MapModel.NO_ID or play.charted_provinces.has(province_id):
			continue
		play.charted_provinces[province_id] = true
		play.hud.toast("The coast of %s is charted" % play.model.province_name(province_id))
		play.emit_coast_charted(province_id)
		return


static func _known(play: PlaySession, fleet: FleetState) -> bool:
	if fleet.owner == PlaySession.PLAYER_FACTION or play.visibility == null:
		return true
	var tile: Vector2i = _tile(play, fleet)
	if tile.x < 0:
		return true
	return play.visibility.level_at(tile.x, tile.y) == VisibilityModel.Level.FULLY_VISIBLE


static func _tile(play: PlaySession, fleet: FleetState) -> Vector2i:
	if fleet.is_at_sea():
		var zone: Dictionary = play.model.sea_zone_data(fleet.sea_zone)
		var tiles: Array = zone.get("tiles", [])
		if tiles.is_empty():
			return Vector2i(-1, -1)
		return tiles[0]
	var data: Dictionary = play.model.province_data(fleet.province)
	return data.get("port_tile", Vector2i(-1, -1))
