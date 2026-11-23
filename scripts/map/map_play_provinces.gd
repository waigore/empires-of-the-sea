class_name MapPlayProvinces
extends RefCounted
## The province ledger's two map hooks: the reading (both charts assembled into
## one projection) and Visit (swap region, frame the province, open its
## dossier). Presentation only — the rows come from [ProvinceLedger] and the
## selection flows through the map's own helpers, so the dossier the ledger
## visits is the dossier a tap would have opened (REQ-P1-05, REQ-P3-02).

const NO_TILE := Vector2i(-1, -1)


## One entry per chart, in the order the ledger prints them: the region's own
## model, the crown's armies there, the estates ledger's snapshot and a crown
## link per province (`LandConnectivity.province_link`, the reading the province
## dossier prints).
static func snapshot(play: PlaySession) -> Dictionary:
	if play == null or play.world == null:
		return ProvinceLedger.snapshot([] as Array[Dictionary], MapModel.NO_ID)
	var owner: int = play.player_faction
	var blockade: Blockades = MapPlayBlockades.crown(play)
	var regions: Array[Dictionary] = []
	for region: int in play.world.region_count():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		var works: LandWorks = _works(play, region)
		var seat: Vector2i = _seat(play, model, region, owner)
		var links: Dictionary = {}
		for province: ProvinceState in model.provinces:
			if province == null or province.owner != owner:
				continue
			links[province.id] = LandConnectivity.province_link(
				model, works, owner, seat, province.id, blockade
			)
		regions.append({
			"region": region,
			"model": model,
			"armies": _stored(play.army_layer.regions if play.army_layer != null else null, region),
			"estates": _estates(play, model, works, region, owner, seat),
			"links": links,
			"seat": play.world.seat_province(region, owner),
		})
	return ProvinceLedger.snapshot(
		regions, owner, _market(play), play.tech_unlocked()
	)


## Frames one province and opens its dossier, swapping the chart first when the
## province lies on the other one. Returns false when the map cannot reach it.
static func focus(play: PlaySession, region: int, province_id: int) -> bool:
	if play == null or play.world == null:
		return false
	var model: MapModel = play.world.region(region)
	if model == null or model.province_data(province_id) == null:
		return false
	var same_region: bool = region == play.region_index
	if not same_region:
		play.screen.switch_region(region)
		MapPlayDiplomacy.sync_first_contact(play)
		MapPlayDiplomacy.refresh(play)
	var world_position: Vector2 = (
		play.model.province_center(province_id) * PlaySession.TILE_SIZE
	)
	MapPlayInput.select_province(play, province_id, world_position)
	if play.camera != null:
		play.camera.focus_on(world_position, maxf(play.camera.target_zoom, 0.95), not same_region)
	return true


## The chart's own works: the civilian layer keeps one table per region, so the
## reading never borrows the chart the player happens to be looking at.
static func _works(play: PlaySession, region: int) -> LandWorks:
	if play.civilian_layer == null:
		return null
	return play.civilian_layer.works_regions.value(region, null) as LandWorks


## The region's own seat tile: the capital tile of the province this crown seats
## there, or none when it holds no seat on that chart (overseas provinces then
## reach the crown through a landfall port, as the dossier reads them).
static func _seat(
	play: PlaySession, model: MapModel, region: int, owner: int
) -> Vector2i:
	var seat: int = play.world.seat_province(region, owner)
	if seat < 0:
		return NO_TILE
	return model.capital_tile_of(seat)


## The estates ledger's own snapshot for this chart, so a row's yield is the
## figure the extraction would pay, never a second sum. The crown's sealed
## coasts are read too: a blockaded colony's estates reach the crown by road
## only (wiki: capital-and-connectivity § Blockade).
static func _estates(
	play: PlaySession,
	model: MapModel,
	works: LandWorks,
	region: int,
	owner: int,
	seat: Vector2i
) -> Dictionary:
	if works == null:
		return {}
	return ImprovementLedger.snapshot(
		model, works, MapPlayCharts.crews(play, region), play.stockpile(), owner, seat,
		play.tech_caps(), MapPlayBlockades.crown(play)
	)


## The market the realm prices its harvest at; a screen with no economy yet
## reads zero ducats rather than a fabricated price.
static func _market(play: PlaySession) -> WorldMarket:
	if play.economy == null:
		return null
	return play.economy.market


static func _stored(table: MapRegionTable, region: int) -> Array:
	if table == null:
		return []
	var stored: Variant = table.value(region, [])
	if stored is Array:
		return stored
	return []
