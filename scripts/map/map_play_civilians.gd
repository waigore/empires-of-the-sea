class_name MapPlayCivilians
extends RefCounted
## Civilian selection, marching, work orders, and capital training.
## Rules stay in CivilianWork; this only applies the screen's presentation.


static func select(screen: MapScreen, unit: CivilianState) -> void:
	screen.selected_province = -1
	screen.overlay.select_province(-1)
	screen.overlay.clear_tile_options()
	screen.hud.hide_province()
	screen.hud.hide_fleet()
	if unit == null:
		screen.hud.hide_civilian()
		return
	screen.hud.show_civilian(
		screen.model, unit, screen.land_works, screen.civilian_layer.units,
		screen.stockpile, screen.visibility
	)
	if unit.owner == MapScreen.PLAYER_FACTION:
		screen.overlay.show_tile_options(CivilianMovement.valid_tiles(screen.model, unit))
	else:
		screen.hud.toast(
			"Civilian of %s — observe only" % MapGenerator.FACTION_NAMES[unit.owner]
		)


## Tapping a neighbouring land tile marches the selected civilian there.
static func try_move(screen: MapScreen, world_position: Vector2) -> bool:
	var unit: CivilianState = screen.civilian_layer.selected_unit
	if unit == null or unit.owner != MapScreen.PLAYER_FACTION:
		return false
	var tile: Vector2i = MapGeo.tile_at_world(world_position, MapScreen.TILE_SIZE)
	if not screen.model.in_bounds(tile.x, tile.y):
		return false
	var distance: int = absi(unit.tile.x - tile.x) + absi(unit.tile.y - tile.y)
	if distance != 1:
		return false
	var result: Dictionary = screen.civilian_layer.apply_move(unit, tile)
	if not bool(result.get("ok", false)):
		screen.hud.toast(String(result.get("reason", "")))
	return true


static func on_moved(screen: MapScreen, unit: CivilianState, _result: Dictionary) -> void:
	if unit.owner != MapScreen.PLAYER_FACTION:
		return
	var province: int = screen.model.province_at(unit.tile.x, unit.tile.y)
	var place: String = screen.model.province_name(province) if province >= 0 else "the wilds"
	screen.hud.toast("The %s marches into %s" % [unit.display_name(), place])
	refresh_panel(screen)


static func on_action(screen: MapScreen, action: String) -> void:
	var unit: CivilianState = screen.civilian_layer.selected_unit
	if unit == null or unit.owner != MapScreen.PLAYER_FACTION:
		return
	var result: Dictionary = CivilianWork.assign(
		screen.model, unit, action, screen.land_works, screen.civilian_layer.units,
		screen.stockpile, screen.visibility
	)
	if not bool(result.get("ok", false)):
		screen.hud.toast(String(result.get("reason", "")))
		return
	screen.hud.toast("%s begins: %s" % [unit.display_name(), CivilianWork.label(action)])
	refresh_panel(screen)


static func on_cancel(screen: MapScreen) -> void:
	var unit: CivilianState = screen.civilian_layer.selected_unit
	if unit == null or not unit.is_working():
		return
	unit.cancel_work()
	screen.hud.toast("The %s abandons its work." % unit.display_name())
	refresh_panel(screen)


static func refresh_panel(screen: MapScreen) -> void:
	screen.civilian_layer.sync()
	screen.civilian_layer.refresh_works()
	var unit: CivilianState = screen.civilian_layer.selected_unit
	if unit == null:
		return
	screen.hud.show_civilian(
		screen.model, unit, screen.land_works, screen.civilian_layer.units,
		screen.stockpile, screen.visibility
	)
	screen.overlay.clear_tile_options()
	screen.overlay.show_tile_options(CivilianMovement.valid_tiles(screen.model, unit))


## Build/Work pass: advance work orders, apply completions and report them.
static func resolve_work(screen: MapScreen) -> void:
	if screen.land_works == null:
		return
	var reports: Array[Dictionary] = CivilianWork.resolve_turn(
		screen.model, screen.civilian_layer.units, screen.land_works, screen.visibility
	)
	var changed: Array = []
	for report: Dictionary in reports:
		if not bool(report.get("completed", false)):
			continue
		changed.append_array(report.get("changed", []))
		var type_name: String = CivilianCatalog.display_name(String(report["type_id"]))
		var province: int = int(report["province"])
		var place: String = screen.model.province_name(province) if province >= 0 else "the wilds"
		var work_name: String = CivilianWork.label(String(report["action"])).to_lower()
		screen.hud.toast("%s in %s: %s" % [type_name, place, work_name])
	if not changed.is_empty():
		screen.overlay.sync_visibility(screen.visibility, changed)
	screen.civilian_layer.sync()
	screen.civilian_layer.refresh_works()


static func train(screen: MapScreen, type_id: String) -> void:
	if not CivilianCatalog.is_implemented(type_id):
		screen.hud.toast(CivilianCatalog.deferred_reason(type_id))
		return
	if screen.selected_province != screen.capital_province:
		screen.hud.toast("Civilians are trained at the capital.")
		return
	var state: PlayerEconomy = screen.economy.economy
	var paper: int = state.quantity("paper")
	if not CivilianCatalog.can_afford(type_id, state.treasury, paper):
		screen.hud.toast("The crown cannot afford a %s." % CivilianCatalog.display_name(type_id))
		return
	var tile: Vector2i = screen.civilian_layer.mustering_tile(screen.capital_province)
	if tile.x < 0:
		screen.hud.toast("There is no room to muster another civilian.")
		return
	state.spend_treasury(CivilianCatalog.treasury_cost(type_id))
	state.take("paper", CivilianCatalog.paper_cost(type_id))
	var unit: CivilianState = screen.civilian_layer.add_unit(MapScreen.PLAYER_FACTION, type_id, tile)
	screen.treasury = state.treasury
	screen.hud.set_treasury(screen.treasury)
	screen.hud.set_civilians(screen.civilian_layer.unit_count(MapScreen.PLAYER_FACTION))
	screen.hud.toast(
		"%s musters at %s" % [unit.display_name(), screen.model.province_name(screen.capital_province)]
	)
