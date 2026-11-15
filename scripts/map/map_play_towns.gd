class_name MapPlayTowns
extends RefCounted
## The towns ledger's two map hooks: the reading (both charts assembled into one
## projection) and Raise (swap the chart when the province lies on the other
## one, then file the Builder's order). Presentation only — the rows come from
## [TownLedger], the two-chart read from [MapPlayCharts], and the order goes
## through [MapPlayImprovements], so the press is the province dossier's own
## order and the rules stay in one place (REQ-P2-03, REQ-P3-02).


## One entry per chart, in the order the ledger prints them: the region's own
## model, the crown's crews there, the studies it holds and the stores the next
## step is paid from.
static func snapshot(play: PlaySession) -> Dictionary:
	return TownLedger.snapshot(MapPlayCharts.charts(play), MapPlayCharts.owner(play))


## Files the town order on the chart the province lies on. The order reads the
## mounted chart's works and crews, so the chart is swapped first when the
## province is on the other one — the same step Visit takes. The order's own
## message reaches the court as the toast (REQ-P5-05).
static func raise(play: PlaySession, region: int, province_id: int) -> void:
	if play == null or play.world == null:
		return
	var model: MapModel = play.world.region(region)
	if model == null or model.province_data(province_id) == null:
		return
	if region != play.region_index:
		play.switch_region(region)
	MapPlayImprovements.upgrade_town(play, province_id)
