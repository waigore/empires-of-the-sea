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
	_seat_carried(play, home)
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


## One squadron per seat, every turn. A rival that docks at its own capital
## through a planner that only moves hulls — the invasion, voyage or cargo pass —
## is folded into the home fleet here, so the seat never ends a turn holding two
## (wiki: ships-and-naval § Home Fleet — "any naval move that docks at the
## capital resolves by merging"). Idempotent, and administrative: no move is
## spent, no fog revealed. The chart follows the fold on the region it shows, and
## a crown whose own squadron is folded at the close reads the line it would have
## read had it docked by hand (REQ-P5-05; DR-20261119-17). Returns how many
## squadrons joined.
static func settle_seats(play: PlaySession) -> int:
	if play == null or play.ship_layer == null or play.world == null:
		return 0
	var joined: int = 0
	var shown: int = _shown_region(play)
	var chart_changed: bool = false
	for region: int in play.ship_layer.regions.region_ids():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		var roster: Array[FleetState] = MapPlayCourtRoster.region_fleets(play, region)
		var changed: bool = false
		for faction: int in FactionCatalog.great_power_ids():
			var reports: Array[Dictionary] = FleetHomeMerge.settle(model, roster, faction)
			var home: FleetState = FleetHomeMerge.home_fleet(model, roster, faction)
			for report: Dictionary in reports:
				changed = true
				joined += 1
				# put_ashore is quiet without a HUD, so the pass still lands a
				# displaced army when the harness runs headless.
				if int(report.get("displaced", -1)) >= 0:
					MapPlayPortLoss.put_ashore(play, int(report["displaced"]), int(report["seat"]))
				if faction == play.player_faction and play.hud != null:
					play.hud.toast(merged_line(play, home, int(report.get("hulls", 0))))
			if not reports.is_empty():
				_seat_carried(play, home)
		if changed:
			play.ship_layer.regions.set_region(region, roster)
			chart_changed = chart_changed or region == shown
	if chart_changed:
		play.ship_layer.roster_changed()
	return joined


## The region the chart is showing, or `MapModel.NO_ID` when the layer has none.
static func _shown_region(play: PlaySession) -> int:
	if play.ship_layer.model == null:
		return MapModel.NO_ID
	return play.ship_layer.model.region_id


## A docking move folds into the home fleet where the move happens, so a planner
## that only moves hulls never leaves two squadrons at the seat (wiki:
## ships-and-naval § Home Fleet — "any naval move that docks at the capital
## resolves by merging"). A merge that finds an army already aboard lands the
## surplus at the port rather than drowning it. Empty when she did not moor at
## her own seat.
static func fold(
	play: PlaySession, model: MapModel, roster: Array[FleetState], fleet: FleetState
) -> Dictionary:
	var merged: Dictionary = FleetHomeMerge.absorb(model, roster, fleet)
	var home: FleetState = merged.get("fleet") as FleetState
	if home == null:
		return {}
	var displaced: int = int(merged.get("displaced", -1))
	if displaced >= 0:
		MapPlayPortLoss.put_ashore(play, displaced, home.province)
	_seat_carried(play, home)
	return merged


## The army a merge keeps aboard rides the squadron that now holds her hulls: her
## id is stored on the squadron that carries her (wiki: ships-and-naval
## § Naval transport), so the court's book, the OOB and the invasion pass find a
## live seat instead of the squadron the merge struck off. The naval pass's
## `ArmyTransport.drop_lost` would repair the seat a turn later; a merge must not
## leave a carried army pointing at a squadron no chart holds.
static func _seat_carried(play: PlaySession, home: FleetState) -> void:
	if play == null or play.army_layer == null:
		return
	ArmyTransport.seat_carried(play.army_layer, home)


## Load repair: a save written before the merge could park a squadron at the
## seat. Fold it in on load and say so once, so holds, the yard and the dossier
## all read one home fleet (wiki: ships-and-naval § Home Fleet). This is a load
## receipt, not a turn despatch: it fires only on a legacy save.
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
	_seat_carried(play, FleetHomeMerge.home_fleet(
		play.model, play.ship_layer.fleets, play.player_faction
	))


## "1 hull" / "4 hulls", for a report line.
static func squadron(hulls: int) -> String:
	return "1 hull" if hulls == 1 else "%d hulls" % hulls


## "no cargo holds" / "1 cargo hold" / "12 cargo holds".
static func cargo(holds: int) -> String:
	if holds <= 0:
		return "no cargo holds"
	return "1 cargo hold" if holds == 1 else "%d cargo holds" % holds
