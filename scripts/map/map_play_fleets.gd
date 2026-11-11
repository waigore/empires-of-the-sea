class_name MapPlayFleets
extends RefCounted
## Fleet selection, sail and dock orders, and fog intel for enemy markers.
## Naval rules stay in NavalMovement; this only drives PlaySession views.


## Rival naval turn — see MapPlayFleetAi (docs/ai.md).
static func run_ai(play: PlaySession) -> Array[Dictionary]:
	return MapPlayFleetAi.run(play)


static func select(play: PlaySession, ship: Ship) -> void:
	if ship == null:
		return
	var fleet: FleetState = play.ship_layer.fleet_of(ship)
	if fleet == null:
		return
	play.selected_province = -1
	play.overlay.select_province(-1)
	play.hud.panels.hide_province()
	show_dossier(play, fleet)
	refresh_options(play, fleet)
	if fleet.owner != play.player_faction:
		play.hud.toast("Fleet of %s — observe only" % FactionCatalog.name_of(fleet.owner))


## One dossier refresh for selection, movement, the yard, a station and a
## landing, so the missions section always comes from the same place.
static func show_dossier(play: PlaySession, fleet: FleetState) -> void:
	play.hud.panels.show_fleet(
		play.model, fleet, fleet.owner == play.player_faction, passage_note(play, fleet),
		yard_rows(play, fleet), -1, landing_rows(play, fleet), carried(play, fleet),
		MapPlayFleetMissions.rows(play, fleet), MapPlayFleetMissions.note(play, fleet),
		MapPlayCivilianVoyage.crew(play, fleet),
		NavalStrength.dossier(
			play.ship_layer.fleets, fleet, MapPlayBeachhead.hostile(play)
		),
		MapPlayHomeMerge.row(play, fleet)
	)


## Owned coastal provinces the carried army could land on (wiki: ships-and-naval
## § Naval transport); a ready beachhead adds the hostile coast it marked.
static func landing_rows(play: PlaySession, fleet: FleetState) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if fleet == null or fleet.owner != play.player_faction or fleet.embarked_army < 0:
		return rows
	var landing: Array[int] = NavalTransport.landing_provinces(
		play.model, fleet, play.turn, MapPlayBeachhead.hostile(play)
	)
	for province: int in landing:
		rows.append({
			"province": province,
			"name": play.model.province_name(province),
			"invade": play.model.province_owner(province) != play.player_faction,
		})
	return rows


## Regiments the fleet carries, for the dossier line.
static func carried(play: PlaySession, fleet: FleetState) -> int:
	if fleet == null or fleet.embarked_army < 0:
		return 0
	var army: ArmyState = ArmyTransport.army_by_id(play.army_layer, fleet.embarked_army)
	return army.count() if army != null else 0


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
	if play.campaign_over():
		return false
	var fleet: FleetState = play.ship_layer.fleet_of(play.ship_layer.selected())
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
	if result.has("embarked_army"):
		var carried_army: ArmyState = ArmyTransport.army_by_id(
			play.army_layer, int(result["embarked_army"])
		)
		if carried_army != null:
			carried_army.embarked_fleet = fleet.id
	# One squadron carries one army; a second army goes ashore at the port.
	var displaced: int = int(result.get("displaced_army", -1))
	if displaced >= 0:
		MapPlayPortLoss.put_ashore(play, displaced, fleet.province)
	show_dossier(play, fleet)
	refresh_options(play, fleet)
	var zone: int = int(result.get("entered_zone", -1))
	if result.has("merged_into"):
		play.hud.toast(
			MapPlayHomeMerge.merged_line(play, fleet, int(result.get("merged_hulls", 0)))
		)
	elif zone >= 0:
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


# --- the naval yard -----------------------------------------------------------


## True when this squadron is the crown's home fleet at its capital port.
static func is_home(play: PlaySession, fleet: FleetState) -> bool:
	if fleet == null or fleet.owner != play.player_faction or not fleet.is_in_port():
		return false
	return fleet.province >= 0 and fleet.province == play.capital_province


## Yard rows for an own squadron: launching needs the capital port, breaking up
## a hull works anywhere (wiki: ships-and-naval § Ship muster and the breaker's
## yard).
static func yard_rows(play: PlaySession, fleet: FleetState) -> Array[Dictionary]:
	if fleet == null or fleet.owner != play.player_faction or play.economy == null:
		return []
	return FleetYard.rows(play.economy.economy, is_home(play, fleet))


## Opens the capital yard from the province dossier; with no home fleet afloat
## the slip is shown and the first launch founds the squadron.
static func open_yard(play: PlaySession) -> void:
	var province: int = play.capital_province
	if province < 0 or play.model.province_owner(province) != play.player_faction:
		play.hud.toast("Your capital must be in hand to open the yard.")
		return
	if not NavalMovement.has_harbour(play.model, province):
		play.hud.toast("Your capital has no harbour for a yard.")
		return
	var home: FleetState = play.ship_layer.home_fleet(province)
	if home != null:
		refresh_yard(play, home)
		return
	if play.economy == null:
		return
	play.hud.panels.show_fleet(
		play.model, null, true, "", FleetYard.rows(play.economy.economy, true), province
	)


static func refresh_yard(play: PlaySession, fleet: FleetState) -> void:
	if fleet == null:
		return
	play.ship_layer.select(play.ship_layer.ship_for(fleet))
	show_dossier(play, fleet)
	play.hud.panels.fleet_panel.set_yard_open(true)


## The fleet dossier and the province yard both route here (REQ-P3-02).
static func on_action(play: PlaySession, action: String) -> void:
	if play.campaign_over():
		return
	if action.begins_with("yard:build:"):
		launch(play, action.trim_prefix("yard:build:"))
	elif action.begins_with("yard:scrap:"):
		scrap(play, action.trim_prefix("yard:scrap:"))
	elif action.begins_with("beachhead:"):
		var fleet: FleetState = play.ship_layer.fleet_of(play.ship_layer.selected())
		if fleet != null and fleet.owner == play.player_faction:
			MapPlayBeachhead.establish(play, fleet, int(action.trim_prefix("beachhead:")))
	elif action.begins_with("mission:"):
		MapPlayFleetMissions.on_action(play, action)
	elif action == "join_home":
		MapPlayHomeMerge.join(play)
	elif action.begins_with("land:"):
		land(play, int(action.trim_prefix("land:")))
	elif MapPlayCivilianVoyage.on_action(play, action):
		return


## Lands the carried army on an owned coastal province (wiki: ships-and-naval
## § Naval transport).
static func land(play: PlaySession, province_id: int) -> void:
	var fleet: FleetState = play.ship_layer.fleet_of(play.ship_layer.selected())
	if fleet == null or fleet.owner != play.player_faction:
		return
	var invaded: bool = play.model.province_owner(province_id) != play.player_faction
	var result: Dictionary = ArmyTransport.disembark(
		play.army_layer, fleet, province_id, play.turn, MapPlayBeachhead.hostile(play)
	)
	if not bool(result.get("ok", false)):
		play.hud.toast(String(result.get("reason", "The troops cannot land.")))
		return
	if invaded:
		play.hud.toast(
			"The army storms ashore at %s" % play.model.province_name(province_id)
		)
	else:
		play.hud.toast("The army lands at %s" % play.model.province_name(province_id))
	show_dossier(play, fleet)
	MapPlayArmies.refresh_visibility(play)


## Launches one hull into the home fleet, founding it at the capital slip when
## the crown keeps none (wiki: ships-and-naval § Home Fleet).
static func launch(play: PlaySession, type_id: String) -> void:
	if play.economy == null or play.economy.economy == null:
		return
	var province: int = play.capital_province
	if province < 0 or play.model.province_owner(province) != play.player_faction:
		play.hud.toast("Your capital must be in hand to launch hulls.")
		return
	if not NavalMovement.has_harbour(play.model, province):
		play.hud.toast("Your capital has no harbour for a yard.")
		return
	var result: Dictionary = play.ship_layer.launch_hull(province, type_id, play.economy.economy)
	if not bool(result.get("ok", false)):
		play.hud.toast(String(result.get("reason", "The hull cannot launch.")))
		return
	var fleet: FleetState = result.get("fleet") as FleetState
	play.hud.set_fleets(play.ship_layer.hull_count_all(play.player_faction))
	var hull_name: String = String(result.get("name", ""))
	if hull_name.is_empty():
		hull_name = ShipStats.display_name(type_id)
	play.hud.toast(
		"%s joins the home fleet at %s" % [hull_name, play.model.province_name(province)]
	)
	refresh_yard(play, fleet)


## Breaks up one hull and returns its peasant to the pool.
static func scrap(play: PlaySession, hull_id: String) -> void:
	if play.economy == null or play.economy.economy == null:
		return
	var fleet: FleetState = play.ship_layer.fleet_of(play.ship_layer.selected())
	if fleet == null or fleet.owner != play.player_faction:
		return
	var carried_army: ArmyState = ArmyTransport.army_by_id(
		play.army_layer, fleet.embarked_army
	)
	var can_break: Dictionary = NavalTransport.can_scrap(fleet, carried_army)
	if not bool(can_break.get("ok", false)):
		play.hud.toast(String(can_break.get("reason", "The hull stays afloat.")))
		return
	var result: Dictionary = play.ship_layer.scrap_hull(fleet, hull_id, play.economy.economy)
	if not bool(result.get("ok", false)):
		play.hud.toast(String(result.get("reason", "The hull stays afloat.")))
		return
	play.hud.set_fleets(play.ship_layer.hull_count_all(play.player_faction))
	var broken: String = String(result.get("name", ""))
	if broken.is_empty():
		broken = ShipStats.display_name(String(result.get("type", "")))
	play.hud.toast("%s broken up — one peasant returns to the pool" % broken)
	if bool(result.get("retired", false)):
		play.hud.panels.hide_fleet()
		return
	refresh_yard(play, fleet)


## Reports the port verdicts of the Combat phase: a squadron caught in a port
## that changed hands sorts out rather than being taken in harbour, and a
## reassigned crown's home squadron re-moors with its court (wiki:
## ships-and-naval § Ports that change hands; DR-20261109-11, DR-20261109-12).
static func settle_ports(play: PlaySession, reassigned: Array) -> void:
	MapPlayPortLoss.settle(play, reassigned)
