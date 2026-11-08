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
	play.hud.panels.hide_province()
	play.hud.panels.show_fleet(
		play.model, fleet, fleet.owner == play.player_faction, passage_note(play, fleet)
	)
	refresh_options(play, fleet)
	if fleet.owner != play.player_faction:
		play.hud.toast("Fleet of %s — observe only" % FactionCatalog.name_of(fleet.owner))


static func refresh_options(play: PlaySession, fleet: FleetState) -> void:
	play.overlay.clear_move_options()
	if fleet == null or fleet.owner != play.player_faction or fleet.moved:
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
	if play.victory != null:
		return false
	var fleet: FleetState = play.ship_layer.fleet_of(play.ship_layer.selected_ship)
	if fleet == null or fleet.owner != play.player_faction:
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
		return _try_passage(play, fleet)
	var result: Dictionary = play.ship_layer.order(fleet, FleetState.Location.AT_SEA, zone_id)
	if bool(result.get("ok", false)):
		return true
	play.hud.toast(String(result.get("reason", "")))
	return true


## Clicking the fleet's own zone crosses a passage when that zone is a warp
## zone; otherwise it stays the old "already there" refusal (wiki:
## map-topology § Warp zones).
static func _try_passage(play: PlaySession, fleet: FleetState) -> bool:
	if bool(WarpTravel.can_cross(play.world, play.region_index, fleet).get("ok", false)):
		var crossed: Dictionary = play.ship_layer.cross(fleet)
		if not bool(crossed.get("ok", false)):
			play.hud.toast(String(crossed.get("reason", "")))
		return true
	play.hud.toast("The fleet is already in the %s" % play.model.sea_zone_name(fleet.sea_zone))
	return true


## Dossier hint when the selected fleet sits in a passage it could cross.
static func passage_note(play: PlaySession, fleet: FleetState) -> String:
	if fleet == null or fleet.owner != play.player_faction:
		return ""
	var check: Dictionary = WarpTravel.can_cross(play.world, play.region_index, fleet)
	if not bool(check.get("ok", false)):
		return ""
	return "Tap this Passage to cross to the %s." % FactionCatalog.region_label(
		int(check["to_region"])
	)


static func on_moved(play: PlaySession, fleet: FleetState, result: Dictionary) -> void:
	if fleet.owner != play.player_faction:
		return
	play.hud.panels.show_fleet(play.model, fleet, true, passage_note(play, fleet))
	refresh_options(play, fleet)
	var zone: int = int(result.get("entered_zone", -1))
	if zone >= 0:
		play.hud.toast("The fleet enters the %s" % play.model.sea_zone_name(zone))
	else:
		play.hud.toast("The fleet docks at %s" % play.model.province_name(fleet.province))
	refresh_visibility(play)


static func on_zone_entered(play: PlaySession, zone_id: int, ship: Ship) -> void:
	if ship == null or ship.faction != play.player_faction or play.visibility == null:
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
	if fleet.owner == play.player_faction or play.visibility == null:
		return true
	var tile: Vector2i = _tile(play, fleet)
	if tile.x < 0:
		return true
	return play.visibility.level_at(tile.x, tile.y) == VisibilityModel.Level.FULLY_VISIBLE


static func _tile(play: PlaySession, fleet: FleetState) -> Vector2i:
	if fleet.is_at_sea():
		var zone: SeaZoneState = play.model.sea_zone_data(fleet.sea_zone)
		var tiles: Array = zone.tiles if zone != null else []
		if tiles.is_empty():
			return Vector2i(-1, -1)
		return tiles[0]
	var data: ProvinceState = play.model.province_data(fleet.province)
	return data.port_tile if data != null else Vector2i(-1, -1)
