class_name MapPlayImprovements
extends RefCounted
## Estates-ledger intents: dispatch or cancel a Builder, file a raise sheet's
## order and frame the tile. Rules and costs stay in
## ImprovementOrders/CivilianWork (REQ-P2-03).
##
## The three raise sheets — towns, walls and hospitals — file through one door
## here (`raise`): the chart swap, the order's own receipt and the repaint of
## the estates surfaces are the same step for all three, so each sheet's map
## hook only names the order it raises.

## The orders a raise sheet files: the town's next level, the province's next
## wall or its ward. The sheet names one of these; `raise` dispatches it.
const RAISE_TOWN: String = "upgrade_town"
const RAISE_WALL: String = "build_fort"
const RAISE_WARD: String = "build_hospital"


static func on_action(play: PlaySession, action: String, tile: Vector2i) -> void:
	if action == "focus":
		play.improvements.close()
		play.camera.focus_on(
			MapGeo.tile_center(tile.x, tile.y, PlaySession.TILE_SIZE), 0.8
		)
		return
	var result: Dictionary = ImprovementOrders.apply(
		play.model, play.civilian_layer.units, play.land_works,
		play.stockpile(), play.visibility, play.player_faction, action, tile,
		play.tech_caps(), play.tech_unlocked()
	)
	_receipt(play, result)


## The estates sheet's one press: every ready estate the view prints, in its
## order, through the same Build order a row's press files — the nearest idle
## Builder, the published price and every gate stay in ImprovementOrders
## (REQ-P2-03, REQ-P5-04; DR-20261116-06). The walk stops at the first refusal,
## because that refusal is the rules' answer for the realm, and the court reads
## one receipt instead of a lane of thirty lines (REQ-P5-05, REQ-P5-06).
static func raise_all(play: PlaySession, tiles: Array) -> void:
	if play == null or play.model == null:
		return
	var targets: Array[Dictionary] = []
	for raw: Variant in tiles:
		var tile: Vector2i = raw
		targets.append({
			"region": play.region_index,
			"id": play.model.index_of(tile.x, tile.y),
			"tile": tile,
		})
	var receipt: Dictionary = RaiseLedger.file_batch(
		targets,
		func(target: Dictionary) -> Dictionary: return _build(play, target["tile"])
	)
	play.improvements.refresh()
	play.civilian_layer.sync()
	play.hud.toast(RaiseLedger.batch_receipt(receipt, "estates"))


## One estate's Build order, worded by the rules and printed by nobody: the
## batch's receipt is the one line the court reads.
static func _build(play: PlaySession, tile: Vector2i) -> Dictionary:
	return ImprovementOrders.build(
		play.model, play.civilian_layer.units, play.land_works, play.stockpile(),
		play.visibility, play.player_faction, tile, play.tech_caps(),
		play.tech_unlocked()
	)


## The province's crown link for the dossier: live road tiles, whether its town
## reaches the capital, and how far the gap still is (LandConnectivity owns the
## rule; the panel only prints it).
static func crown_link(play: PlaySession, province_id: int) -> Dictionary:
	return LandConnectivity.province_link(
		play.model, play.land_works, play.player_faction, play.capital_tile,
		province_id, MapPlayBlockades.crown(play)
	)


## Province dossier intent: dispatch the nearest idle Engineer onto the first
## road tile that links an unlinked estate. RoadWorks owns the route and the
## gates; the panel only prints them (REQ-P2-03).
static func build_road(play: PlaySession, tile: Vector2i) -> void:
	if tile.x < 0:
		return
	var result: Dictionary = RoadWorks.dispatch(
		play.model, play.civilian_layer.units, play.land_works, play.stockpile(),
		play.visibility, play.player_faction, play.capital_tile, tile,
		play.tech_unlocked()
	)
	play.hud.toast(String(result.get("message", "")))
	play.civilian_layer.sync()
	# The dossier is the sheet the order came from, so it repaints in place.
	if play.selected_province >= 0 and play.hud.panels.is_panel_open():
		play.hud.panels.panel.refresh(
			play.model, play.selected_province,
			crown_link(play, play.selected_province)
		)


## Province dossier intent: dispatch the nearest idle Rail Builder onto the road
## tile the rail block names. RailWorks owns the gate and CivilianWork the price;
## the panel only prints them (REQ-P2-03; DR-20261117-10).
static func build_rail(play: PlaySession, tile: Vector2i) -> void:
	if tile.x < 0:
		return
	var result: Dictionary = RailWorks.dispatch(
		play.model, play.civilian_layer.units, play.land_works, play.stockpile(),
		play.visibility, play.player_faction, tile, play.tech_unlocked()
	)
	play.hud.toast(String(result.get("message", "")))
	play.civilian_layer.sync()
	# The dossier is the sheet the order came from, so it repaints in place.
	if play.selected_province >= 0 and play.hud.panels.is_panel_open():
		play.hud.panels.panel.refresh(
			play.model, play.selected_province,
			crown_link(play, play.selected_province)
		)


## Files one raise sheet's order on the chart the province lies on: the chart is
## swapped first when the province is on the other one — the same step Visit
## takes — so the order reads the mounted chart's works and crews. `order` names
## what is raised (`RAISE_*`). The order's own message reaches the court as the
## toast unless `quiet` holds it back for a batch, whose receipt is the one line
## the court reads (REQ-P5-05; DR-20261116-03).
static func raise(
	play: PlaySession,
	region: int,
	province_id: int,
	order: String,
	quiet: bool = false
) -> Dictionary:
	if play == null or play.world == null:
		return {"ok": false, "message": ""}
	var model: MapModel = play.world.region(region)
	if model == null or model.province_data(province_id) == null:
		return {"ok": false, "message": ""}
	if region != play.region_index:
		play.screen.switch_region(region)
	return _file(play, province_id, order, quiet)


## Province dossier intent: dispatch the nearest Builder to the town site. Same
## order and receipt as the towns sheet's press, so the dossier and the sheet
## cannot word one step two ways (REQ-P5-05).
static func upgrade_town(
	play: PlaySession, province_id: int, quiet: bool = false
) -> Dictionary:
	if play == null or play.model == null:
		return {"ok": false, "message": ""}
	return _file(play, province_id, RAISE_TOWN, quiet)


## Runs one raise order on the mounted chart and prints its receipt.
static func _file(
	play: PlaySession, province_id: int, order: String, quiet: bool
) -> Dictionary:
	var result: Dictionary = _order(play, province_id, order)
	_receipt(play, result, quiet)
	return result


## The order itself: the town site a Builder raises, or the province the
## Engineer works. Every gate and every price stays in ImprovementOrders.
static func _order(play: PlaySession, province_id: int, order: String) -> Dictionary:
	if order == RAISE_WALL:
		return ImprovementOrders.build_fort(
			play.model, play.civilian_layer.units, play.land_works,
			play.stockpile(), play.visibility, play.player_faction, province_id,
			play.tech_caps(), play.tech_unlocked()
		)
	if order == RAISE_WARD:
		return ImprovementOrders.build_hospital(
			play.model, play.civilian_layer.units, play.land_works,
			play.stockpile(), play.visibility, play.player_faction, province_id,
			play.tech_caps(), play.tech_unlocked()
		)
	if order != RAISE_TOWN:
		return {"ok": false, "message": "Unknown estates order."}
	var province: ProvinceState = play.model.province_data(province_id)
	if province == null:
		return {"ok": false, "message": ""}
	return ImprovementOrders.upgrade_town(
		play.model, play.civilian_layer.units, play.land_works, play.stockpile(),
		play.visibility, play.player_faction, province.town_site(),
		play.tech_unlocked()
	)


## The one receipt a filed order gets: the order's own words on the despatch
## lane unless the caller prints a batch receipt instead, and the estates
## surfaces repainted from what the order moved.
static func _receipt(
	play: PlaySession, result: Dictionary, quiet: bool = false
) -> void:
	if not quiet:
		play.hud.toast(String(result.get("message", "")))
	play.improvements.refresh()
	play.civilian_layer.sync()
