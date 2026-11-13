class_name MapPlayFleets
extends RefCounted
## Fleet selection, sail and dock orders, and fog intel for enemy markers.
## Naval rules stay in NavalMovement; this only drives PlaySession views. The
## capital shipyard's slip rows and hull orders live on MapPlayFleetYard.


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
	# A rival the crown has sighted but not read is handed a fogged reading, so
	# the dossier can never assemble her maths (wiki: ships-and-naval
	# § Sighted strength).
	var strength: Dictionary = NavalStrength.fogged()
	if strength_read(play, fleet):
		strength = NavalStrength.dossier(
			play.ship_layer.fleets, fleet, MapPlayBeachhead.hostile(play),
			MapPlayNavalTurn.strength_multipliers(play), play.leaders, intel_filter(play)
		)
	play.hud.panels.show_fleet(
		play.model, fleet, fleet.owner == play.player_faction, passage_note(play, fleet),
		MapPlayFleetYard.rows(play, fleet), -1, landing_rows(play, fleet),
		carried(play, fleet),
		MapPlayFleetMissions.rows(play, fleet), MapPlayFleetMissions.note(play, fleet),
		MapPlayCivilianVoyage.crew(play, fleet),
		strength,
		MapPlayHomeMerge.row(play, fleet),
		MapPlayFleetMissions.hint(play, fleet)
	)


## Whether the crown may read a squadron's fighting weight: its own squadrons
## always, a rival's only once the watch has spanned a turn (wiki:
## ships-and-naval § Sighted strength).
static func strength_read(play: PlaySession, fleet: FleetState) -> bool:
	if fleet == null or fleet.owner == play.player_faction:
		return true
	return play.naval_intel.is_revealed(fleet.id)


## Which squadrons in a zone the crown can weigh; an unread rival contributes
## no figure to the odds (wiki: ships-and-naval § Sighted strength).
static func intel_filter(play: PlaySession) -> Callable:
	return func(other: FleetState) -> bool:
		return strength_read(play, other)


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
	var in_view: Array[int] = []
	for ship: Ship in play.ship_layer.ships:
		var fleet: FleetState = play.ship_layer.fleet_of(ship)
		if fleet == null:
			continue
		var known: bool = _known(play, fleet)
		ship.visible = known
		if known and fleet.owner != play.player_faction:
			in_view.append(fleet.id)
	# One refresh of the crown's watch: a rival seen at the last close and still
	# under the same eye is read now, and one that slipped away is unread again
	# (wiki: ships-and-naval § Sighted strength).
	play.naval_intel.observe(in_view, play.turn)
	for ship: Ship in play.ship_layer.ships:
		var fleet: FleetState = play.ship_layer.fleet_of(ship)
		if fleet != null:
			ship.set_intel(strength_read(play, fleet))


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


## The fleet dossier and the province yard both route here (REQ-P3-02). The
## shipyard's own intents go back to MapPlayFleetYard.
static func on_action(play: PlaySession, action: String) -> void:
	if play.campaign_over():
		return
	if MapPlayFleetYard.on_action(play, action):
		return
	if action.begins_with("beachhead:"):
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


## Reports the port verdicts of the Combat phase: a squadron caught in a port
## that changed hands sorts out rather than being taken in harbour, and a
## reassigned crown's home squadron re-moors with its court (wiki:
## ships-and-naval § Ports that change hands; DR-20261109-11, DR-20261109-12).
static func settle_ports(play: PlaySession, reassigned: Array) -> void:
	MapPlayPortLoss.settle(play, reassigned)
