class_name MapPlayImprovements
extends RefCounted
## Estates-ledger intents: dispatch or cancel a Builder and frame the tile.
## Rules and costs stay in ImprovementOrders/CivilianWork (REQ-P2-03).


static func on_action(screen: MapScreen, action: String, tile: Vector2i) -> void:
	if action == "focus":
		screen.improvements.close()
		screen.camera.focus_on(
			MapGeo.tile_center(tile.x, tile.y, MapScreen.TILE_SIZE), 0.8
		)
		return
	var result: Dictionary = ImprovementOrders.apply(
		screen.model, screen.civilian_layer.units, screen.land_works,
		screen.stockpile, screen.visibility, MapScreen.PLAYER_FACTION, action, tile
	)
	screen.hud.toast(String(result.get("message", "")))
	screen.improvements.refresh()
	screen.civilian_layer.sync()
