class_name MapPlayWarp
extends RefCounted
## Follows a fleet through a warp passage: swaps the view onto the destination
## region, reveals the arrival waters and keeps the fleet selected (wiki:
## map-topology § Warp zones). Rules live in WarpTravel; this only presents.

static func on_crossed(play: PlaySession, fleet: FleetState, result: Dictionary) -> void:
	var region: int = int(result.get("to_region", -1))
	if region < 0 or region == play.region_index:
		return
	MapPlayInput.deselect(play)
	play.switch_region(region)
	# The troops cross with the squadron: move the roster entry once the new map
	# has mustered its own armies (wiki: ships-and-naval § Naval transport).
	if fleet.embarked_army >= 0:
		var army: ArmyState = ArmyTransport.army_by_id(
			play.army_layer, fleet.embarked_army
		)
		if army != null:
			army.embarked_fleet = fleet.id
		ArmyTransport.move_to_region(play.army_layer, fleet.embarked_army, region)
	var zone: int = int(result.get("to_zone", -1))
	var ship: Ship = play.ship_layer.ship_for(fleet)
	if ship != null:
		play.ship_layer.select(ship)
		MapPlayFleets.on_zone_entered(play, zone, ship)
	# Contact follows the coast the arrival reveals (wiki: fog § Initial Visibility).
	MapPlayDiplomacy.sync_first_contact(play)
	MapPlayDiplomacy.refresh(play)
	if zone >= 0:
		play.camera.focus_on(
			play.model.sea_zone_center(zone) * PlaySession.TILE_SIZE,
			maxf(play.camera.target_zoom, 0.75)
		)
	RegionBriefing.arrival(play.hud, play.model, region)
	play.hud.toast(
		"The fleet passes the Passage into the %s" % FactionCatalog.region_label(region)
	)
	MapPlayInput.on_view_changed(play)
