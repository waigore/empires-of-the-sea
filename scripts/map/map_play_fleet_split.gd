class_name MapPlayFleetSplit
extends RefCounted
## Detaching a hull as the player meets it: the one tap that files the order and
## the report the toast prints (wiki: ships-and-naval § Ship instances;
## DR-20261116-12). Rules live in FleetSplit; this module files the roster the
## way the home merge does and words the news (REQ-P3-02).


## Files the detach for the selected squadron and keeps the player looking at
## the squadron she split, so the new command is found on the chart.
static func detach(play: PlaySession, hull_id: String) -> void:
	if play == null or play.campaign_over():
		return
	var fleet: FleetState = play.ship_layer.fleet_of(play.ship_layer.selected())
	if fleet == null or fleet.owner != play.player_faction:
		return
	var result: Dictionary = FleetSplit.detach(
		play.model, play.ship_layer.fleets, fleet, hull_id,
		FleetRosters.next_id(play.ship_layer.fleets)
	)
	if not bool(result.get("ok", false)):
		play.hud.toast(String(result.get("reason", "The squadron stays as she is.")))
		return
	# The roster is the layer's own live array, so the new command is already
	# stored; one rebuild draws both markers under the chart's watch, and the
	# player keeps the squadron she split in view.
	play.ship_layer.rebuild_markers()
	play.ship_layer.select(play.ship_layer.ship_for(fleet))
	play.hud.toast(line(play, fleet, result))


## "San Salvador (Sloop) detaches in the Mar Caribe as a squadron of her own."
## The station is the one the hull keeps, so the news says where to look.
static func line(play: PlaySession, fleet: FleetState, result: Dictionary) -> String:
	var hull_name: String = String(result.get("name", ""))
	var type_name: String = ShipStats.display_name(String(result.get("type", "")))
	var label: String = type_name if hull_name.is_empty() else "%s (%s)" % [hull_name, type_name]
	var where: String = "at %s" % play.model.province_name(fleet.province)
	if fleet.is_at_sea():
		where = "in the %s" % play.model.sea_zone_name(fleet.sea_zone)
	return "%s detaches %s as a squadron of her own." % [label, where]
