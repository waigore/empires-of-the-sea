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
		play.stockpile(), play.visibility, PlaySession.PLAYER_FACTION, action, tile,
		play.tech_caps(), play.tech_unlocked()
	)
	play.hud.toast(String(result.get("message", "")))
	play.improvements.refresh()
	play.civilian_layer.sync()
