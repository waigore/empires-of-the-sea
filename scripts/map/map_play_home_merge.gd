class_name MapPlayHomeMerge
extends RefCounted
## The home-fleet merge as the player meets it: the dossier row that offers the
## one-tap join (or nudges a squadron that could dock into her), the report the
## toast prints, and the load repair for a save that parked two squadrons at
## the seat (wiki: ships-and-naval § Home Fleet). Rules live in FleetHomeMerge;
## this module only routes the intent and words the report (REQ-P3-02).


## What the fleet dossier shows for this squadron: a one-tap join when it is
## moored at the crown's seat beside the home fleet, the home fleet's holds when
## she is the selection, and a nudge when docking at the seat would merge.
static func row(play: PlaySession, fleet: FleetState) -> Dictionary:
	if play == null or fleet == null or fleet.owner != play.player_faction:
		return {}
	var home: FleetState = FleetHomeMerge.home_fleet(
		play.model, play.ship_layer.fleets, play.player_faction
	)
	var holds: int = TradeCargo.fleet_holds(fleet)
	if fleet.is_in_port():
		if fleet == home:
			return {"home": true, "holds_text": cargo(holds)}
		var check: Dictionary = FleetHomeMerge.can_join(
			play.model, play.ship_layer.fleets, fleet
		)
		if not bool(check.get("ok", false)):
			return {}
		return {
			"ok": true,
			"label": "Join the home fleet",
			"note": "Adds %s · %s to the home fleet." % [
				squadron(fleet.ship_count()), cargo(holds)
			],
		}
	var seat: int = play.capital_province
	if home == null or seat < 0:
		return {}
	if not NavalMovement.dockable_provinces(play.model, fleet).has(seat):
		return {}
	var line: String = "Docking at %s joins the home fleet" % play.model.province_name(seat)
	if holds > 0:
		line += " (%s)" % cargo(holds)
	return {"note": line + "."}


## The dossier button: fold the selected squadron into the home fleet, then keep
## the player looking at the squadron that now holds their hulls.
static func join(play: PlaySession) -> void:
	if play == null or play.campaign_over():
		return
	var fleet: FleetState = play.ship_layer.fleet_of(play.ship_layer.selected())
	if fleet == null or fleet.owner != play.player_faction:
		return
	var check: Dictionary = FleetHomeMerge.can_join(
		play.model, play.ship_layer.fleets, fleet
	)
	if not bool(check.get("ok", false)):
		play.hud.toast(String(check.get("reason", "The squadron stays as it is.")))
		return
	var hulls: int = fleet.ship_count()
	var merged: Dictionary = FleetHomeMerge.join(play.model, play.ship_layer.fleets, fleet)
	var home: FleetState = merged.get("fleet") as FleetState
	if home == null:
		return
	var displaced: int = int(merged.get("displaced", -1))
	if displaced >= 0:
		MapPlayPortLoss.put_ashore(play, displaced, home.province)
	play.ship_layer.rebuild_markers()
	play.ship_layer.select(play.ship_layer.ship_for(home))
	play.hud.toast(merged_line(play, home, hulls))


## The report a finished merge prints, shared by a docking order and the dossier
## button so the court reads the same numbers either way.
static func merged_line(play: PlaySession, home: FleetState, hulls: int) -> String:
	if play == null or home == null:
		return "The squadron joins the home fleet."
	var joined: int = hulls if hulls > 0 else home.ship_count()
	return "%s %s the home fleet at %s — she now carries %s." % [
		squadron(joined),
		"joins" if joined == 1 else "join",
		play.model.province_name(home.province),
		cargo(TradeCargo.fleet_holds(home)),
	]


## Load repair: a save written before the merge could park a squadron at the
## seat. Fold it in on load and say so, so holds, the yard and the dossier all
## read one home fleet (wiki: ships-and-naval § Home Fleet).
static func repair(play: PlaySession) -> void:
	if play == null or play.hud == null:
		return
	var reports: Array[Dictionary] = FleetHomeMerge.settle(
		play.model, play.ship_layer.fleets, play.player_faction
	)
	if reports.is_empty():
		return
	play.ship_layer.rebuild_markers()
	for report: Dictionary in reports:
		var seat: int = int(report.get("seat", -1))
		if int(report.get("displaced", -1)) >= 0:
			MapPlayPortLoss.put_ashore(play, int(report["displaced"]), seat)
		play.hud.toast(
			"%s rejoined the home fleet at %s"
			% [squadron(int(report.get("hulls", 0))), play.model.province_name(seat)]
		)


## "1 hull" / "4 hulls", for a report line.
static func squadron(hulls: int) -> String:
	return "1 hull" if hulls == 1 else "%d hulls" % hulls


## "no cargo holds" / "1 cargo hold" / "12 cargo holds".
static func cargo(holds: int) -> String:
	if holds <= 0:
		return "no cargo holds"
	return "1 cargo hold" if holds == 1 else "%d cargo holds" % holds
