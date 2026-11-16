class_name MapPlayFleetCombine
extends RefCounted
## Combining the selected squadron into another of the crown's in the same
## station: the one tap that files the order and the report the toast prints
## (wiki: ships-and-naval § Ship instances; DR-20261116-13). Rules live in
## FleetCombine; this module files the roster the way the split does and words
## the news (REQ-P3-02).


## Files the combine and keeps the player looking at the squadron that keeps the
## station, so the hulls that joined are found where the orders are.
static func combine(play: PlaySession, target_id: int) -> void:
	if play == null or play.campaign_over():
		return
	var fleet: FleetState = play.ship_layer.fleet_of(play.ship_layer.selected())
	if fleet == null or fleet.owner != play.player_faction:
		return
	var target: FleetState = FleetRosters.find(play.ship_layer.fleets, target_id)
	var result: Dictionary = FleetCombine.combine(
		play.model, play.ship_layer.fleets, fleet, target
	)
	if not bool(result.get("ok", false)):
		play.hud.toast(String(result.get("reason", "The squadrons stay as they are.")))
		return
	# The roster is the layer's own live array, so the merged squadron is already
	# stored; one rebuild retires the emptied marker and redraws the rest.
	play.ship_layer.rebuild_markers()
	play.ship_layer.select(play.ship_layer.ship_for(target))
	play.hud.toast(line(play, target, result))


## "San Salvador joins Trinidad in the Mar Caribe — one squadron of five." The
## station is the target's, so the news says where the hulls now answer.
static func line(play: PlaySession, target: FleetState, result: Dictionary) -> String:
	var from_name: String = String(result.get("name", ""))
	var into_name: String = String(result.get("into", ""))
	var where: String = "at %s" % play.model.province_name(target.province)
	if target.is_at_sea():
		where = "in the %s" % play.model.sea_zone_name(target.sea_zone)
	return "%s joins %s %s — one squadron of %d." % [
		from_name, into_name, where, target.ship_count(),
	]
