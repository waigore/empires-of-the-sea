class_name MapPlayTowns
extends RefCounted
## The towns ledger's two map hooks: the reading (both charts assembled into one
## projection) and Raise (file the Builder's order on the chart the province
## lies on). Presentation only — the rows come from [TownLedger], the two-chart
## read from [MapPlayCharts], and the press goes through
## [MapPlayImprovements], the same door the province dossier's town order uses,
## so the rules stay in one place (REQ-P2-03, REQ-P3-02).


## One entry per chart, in the order the ledger prints them: the region's own
## model, the crown's crews there, the studies it holds and the stores the next
## step is paid from.
static func snapshot(play: PlaySession) -> Dictionary:
	return TownLedger.snapshot(MapPlayCharts.charts(play), MapPlayCharts.owner(play))


## Files the town order on the chart the province lies on, on the province's own
## town site. `quiet` keeps the order's line off the lane for a batch press,
## whose receipt is the one line the court reads (REQ-P5-05; DR-20261116-03).
static func raise(
	play: PlaySession, region: int, province_id: int, quiet: bool = false
) -> Dictionary:
	return MapPlayImprovements.raise(
		play, region, province_id, MapPlayImprovements.RAISE_TOWN, quiet
	)
