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
		province_id
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
