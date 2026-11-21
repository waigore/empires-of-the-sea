class_name MapPlayFleets
extends RefCounted
## Fleet selection, sail and dock orders. Naval rules stay in NavalMovement;
## this only drives PlaySession views. The crown's watch over rival squadrons
## (fog, sighted strength, charted coast) lives on MapPlayFleetIntel — thin
## forwards below keep call sites off that module's impact fan-out — and the
## capital shipyard's slip rows and hull orders on MapPlayFleetYard.


## Rival naval turn — see MapPlayFleetAi (docs/ai.md).
static func run_ai(play: PlaySession) -> Array[Dictionary]:
	return MapPlayFleetAi.run(play)


## Forwards: the crown's watch (see MapPlayFleetIntel).
static func view_filter(play: PlaySession) -> Callable:
	return MapPlayFleetIntel.view_filter(play)


static func on_zone_entered(play: PlaySession, zone_id: int, ship: Ship) -> void:
	MapPlayFleetIntel.on_zone_entered(play, zone_id, ship)


static func refresh_visibility(play: PlaySession) -> void:
	MapPlayFleetIntel.refresh_visibility(play)


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
	# A crowded station says where the crown stands in it, so a tap that cycled a
	# stack never swaps one squadron for another without a word (REQ-P5-05).
	var line: String = selection_line(play, ship, fleet)
	if not line.is_empty():
		play.hud.toast(line)


## What a selection says out loud: her place in a shared station, and whether
## the crown may order her at all (wiki: ships-and-naval § Fleets in one
## station). The place is read over every squadron the chart draws there — the
## crown's row and the stack behind it — so a tap that landed beside three other
## hulls never swaps one command for another without a word, and a water the fog
## half-hides is counted by what the crown can see (REQ-P5-05).
static func selection_line(play: PlaySession, ship: Ship, fleet: FleetState) -> String:
	var parts: Array[String] = []
	if ship.station.size() > 1:
		var index: int = maxi(ship.station.find(ship.fleet_id), 0) + 1
		parts.append(
			"%d of %d squadrons here — %s" % [
				index, ship.station.size(), FleetCombine.flagship(fleet)
			]
		)
	if fleet.owner != play.player_faction:
		parts.append("Fleet of %s — observe only" % FactionCatalog.name_of(fleet.owner))
	return " · ".join(parts)


## One dossier refresh for selection, movement, the yard, a station and a
## landing, so the missions section always comes from the same place.
static func show_dossier(play: PlaySession, fleet: FleetState) -> void:
	# A station taken or given up at the dossier is the loop the chart reads
	# back on her marker (issue #1198).
	play.ship_layer.station(fleet)
	# A rival the crown has sighted but not read is handed a fogged reading, so
	# the dossier can never assemble her maths (wiki: ships-and-naval
	# § Sighted strength).
	var strength: Dictionary = NavalStrength.fogged()
	if MapPlayFleetIntel.strength_read(play, fleet):
		strength = NavalStrength.dossier(
			play.ship_layer.fleets, fleet, MapPlayBeachhead.hostile(play),
			MapPlayNavalTurn.strength_multipliers(play), play.leaders,
			MapPlayFleetIntel.intel_filter(play)
		)
	var opening := FleetDossierOpening.new()
	opening.fleet = fleet
	opening.is_player = fleet.owner == play.player_faction
	opening.passage = passage_note(play, fleet)
	opening.yard_rows = MapPlayFleetYard.rows(play, fleet)
	opening.land_rows = landing_rows(play, fleet)
	opening.carried = carried(play, fleet)
	opening.beach_rows = MapPlayFleetMissions.rows(play, fleet)
	opening.beach_note = MapPlayFleetMissions.note(play, fleet)
	opening.crew = MapPlayCivilianVoyage.crew(play, fleet)
	opening.strength = strength
	opening.merge = MapPlayHomeMerge.row(play, fleet)
	opening.beach_hint = MapPlayFleetMissions.hint(play, fleet)
	opening.roster = play.ship_layer.fleets
	opening.pick = MapPlayFleetPick.line(play, fleet)
	# The yard's own claim: the hull this court means to lay, printed in the
	# slip the crown launches from (DR-20261121-02). A rival answers to her own
	# court, and the block draws no rows for her anyway.
	opening.yard_pick = MapPlayYardPick.line(play) if fleet.owner == play.player_faction else ""
	play.hud.panels.show_fleet(play.model, opening)


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
	MapPlayFleetIntel.refresh_visibility(play)


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
	elif action.begins_with("split:"):
		MapPlayFleetSplit.detach(play, action.trim_prefix("split:"))
	elif action.begins_with("combine:"):
		MapPlayFleetCombine.combine(play, int(action.trim_prefix("combine:")))
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
		play.army_layer, fleet, province_id, play.turn, MapPlayBeachhead.hostile(play),
		play.diplomacy
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
