class_name MapPlayImprovements
extends RefCounted
## Estates-ledger intents: dispatch or cancel a Builder and frame the tile.
## Rules and costs stay in ImprovementOrders/CivilianWork (REQ-P2-03).


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
	play.hud.toast(String(result.get("message", "")))
	play.improvements.refresh()
	play.civilian_layer.sync()


## The province's crown link for the dossier: live road tiles, whether its town
## reaches the capital, and how far the gap still is (LandConnectivity owns the
## rule; the panel only prints it).
static func crown_link(play: PlaySession, province_id: int) -> Dictionary:
	return LandConnectivity.province_link(
		play.model, play.land_works, play.player_faction, play.capital_tile,
		province_id, MapPlayBlockades.crown(play)
	)


## Province dossier intent: dispatch the nearest Builder to the town tile.
static func upgrade_town(play: PlaySession, province_id: int) -> void:
	if province_id < 0:
		return
	var province: ProvinceState = play.model.province_data(province_id)
	if province == null:
		return
	var result: Dictionary = ImprovementOrders.upgrade_town(
		play.model, play.civilian_layer.units, play.land_works, play.stockpile(),
		play.visibility, play.player_faction, province.town_tile, play.tech_unlocked()
	)
	play.hud.toast(String(result.get("message", "")))
	play.improvements.refresh()
	play.civilian_layer.sync()


## Province dossier intent: send the nearest idle Engineer to the next road tile
## that links a cut-off estate. One order lays one tile, so a longer route is
## laid a press at a time; the sheet then names the next step (EstateRoadPlan).
static func build_road(play: PlaySession, tile: Vector2i) -> void:
	var result: Dictionary = ImprovementOrders.build_road(
		play.model, play.civilian_layer.units, play.land_works, play.stockpile(),
		play.visibility, play.player_faction, tile, play.capital_tile,
		play.tech_unlocked()
	)
	play.hud.toast(String(result.get("message", "")))
	play.civilian_layer.sync()
	var province_id: int = play.model.province_at(tile.x, tile.y)
	if province_id < 0 or play.selected_province < 0 or not play.hud.panels.is_panel_open():
		return
	# The Engineer is now at work, so the row's own reading moves on without the
	# player reopening the province.
	play.hud.panels.panel.refresh(
		play.model, play.selected_province,
		crown_link(play, play.selected_province)
	)
