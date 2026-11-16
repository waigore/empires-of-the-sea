class_name MapPlayCharts
extends RefCounted
## The two-chart read the crown's raise ledgers share: one entry per chart in the
## order the sheets print them — the region's own model, the crown's crews there
## and the studies it holds — plus the owner a session reads as. Presentation
## only: the orders stay with each sheet's own hook and the rules stay in
## scripts/rules (REQ-P3-02, REQ-P3-03).


## One entry per chart, empty before the campaign seats a world. A chart with no
## model is skipped, so a one-region world reads as one heading. The crown's own
## stores ride every entry: the price a row prints is the price the order
## charges, so the press is never offered short (REQ-P2-03).
static func charts(play: PlaySession) -> Array[Dictionary]:
	var regions: Array[Dictionary] = []
	if play == null or play.world == null:
		return regions
	var tech_unlocked: Dictionary = play.tech_unlocked()
	var stockpile: Dictionary = play.stockpile()
	for region: int in play.world.region_count():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		regions.append({
			"region": region,
			"model": model,
			"units": crews(play, region),
			"tech_unlocked": tech_unlocked,
			"stockpile": stockpile,
		})
	return regions


## The crown the sheets read, or NO_ID before a campaign seats one — so a sheet
## that opens first reads an empty roll rather than another faction's holdings.
static func owner(play: PlaySession) -> int:
	return play.player_faction if play != null else MapModel.NO_ID


## The chart's own crews: the civilian layer keeps one table per region, so the
## reading never borrows the chart the player happens to be looking at.
static func crews(play: PlaySession, region: int) -> Array[CivilianState]:
	if play == null or play.civilian_layer == null:
		return [] as Array[CivilianState]
	var units: Array[CivilianState] = []
	units.assign(play.civilian_layer.regions.value(region, []))
	return units
