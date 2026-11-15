class_name MapPlayWalls
extends RefCounted
## The walls ledger's two map hooks: the reading (both charts assembled into one
## projection) and Raise (swap the chart when the province lies on the other
## one, then file the Engineer's order). Presentation only — the rows come from
## [WallLedger], the two-chart read from [MapPlayCharts], and the order goes
## through [ImprovementOrders], so the press is the same `build_fort` order the
## civilian panel files and the rules stay in one place (REQ-P2-03, REQ-P3-02;
## DR-20261116-01).


## One entry per chart, in the order the ledger prints them: the region's own
## model, the crown's crews there, the studies it holds and the stores the next
## step is paid from.
static func snapshot(play: PlaySession) -> Dictionary:
	return WallLedger.snapshot(MapPlayCharts.charts(play), MapPlayCharts.owner(play))


## Files the wall order on the chart the province lies on. The order reads the
## mounted chart's crews and works, so the chart is swapped first when the
## province is on the other one — the same step Visit takes. The order's own
## message reaches the court as the toast (REQ-P5-05); `quiet` keeps it off the
## lane for a batch press, whose receipt is the one line the court reads
## (DR-20261116-03).
static func raise(
	play: PlaySession, region: int, province_id: int, quiet: bool = false
) -> Dictionary:
	if play == null or play.world == null:
		return {"ok": false, "message": ""}
	var model: MapModel = play.world.region(region)
	if model == null or model.province_data(province_id) == null:
		return {"ok": false, "message": ""}
	if region != play.region_index:
		play.switch_region(region)
	var result: Dictionary = ImprovementOrders.build_fort(
		play.model, play.civilian_layer.units, play.land_works, play.stockpile(),
		play.visibility, play.player_faction, province_id, play.tech_caps(),
		play.tech_unlocked()
	)
	if not quiet:
		play.hud.toast(String(result.get("message", "")))
	play.improvements.refresh()
	play.civilian_layer.sync()
	return result
