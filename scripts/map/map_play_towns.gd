class_name MapPlayTowns
extends RefCounted
## The towns ledger's two map hooks: the reading (both charts assembled into one
## projection) and Raise (swap the chart when the province lies on the other
## one, then file the Builder's order). Presentation only — the rows come from
## [TownLedger] and the order goes through [MapPlayImprovements], so the press
## is the province dossier's own order and the rules stay in one place
## (REQ-P2-03, REQ-P3-02).


## One entry per chart, in the order the ledger prints them: the region's own
## model, the crown's crews there and the studies it holds.
static func snapshot(play: PlaySession) -> Dictionary:
	if play == null or play.world == null:
		return TownLedger.snapshot([] as Array[Dictionary], MapModel.NO_ID)
	var tech_unlocked: Dictionary = play.tech_unlocked()
	var regions: Array[Dictionary] = []
	for region: int in play.world.region_count():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		regions.append({
			"region": region,
			"model": model,
			"units": _civilians(play, region),
			"tech_unlocked": tech_unlocked,
			## The crown's own stores: the price a row prints is the price the
			## order charges, so the press is never offered short (REQ-P2-03).
			"stockpile": play.stockpile(),
		})
	return TownLedger.snapshot(regions, play.player_faction)


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


## The chart's own crews: the civilian layer keeps one table per region, so the
## reading never borrows the chart the player happens to be looking at.
static func _civilians(play: PlaySession, region: int) -> Array[CivilianState]:
	if play.civilian_layer == null:
		return [] as Array[CivilianState]
	var units: Array[CivilianState] = []
	units.assign(play.civilian_layer.regions.value(region, []))
	return units
