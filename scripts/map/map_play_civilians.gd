class_name MapPlayCivilians
extends RefCounted
## Civilian selection, marching, work orders, and capital training.
## Rules stay in CivilianWork; this only applies PlaySession presentation.


static func select(play: PlaySession, unit: CivilianState) -> void:
	play.selected_province = -1
	play.overlay.select_province(-1)
	play.overlay.clear_tile_options()
	play.hud.panels.hide_province()
	play.hud.panels.hide_fleet()
	if unit == null:
		play.hud.panels.hide_civilian()
		return
	play.hud.panels.show_civilian(
		play.model, unit, play.land_works, play.civilian_layer.units,
		play.stockpile(), play.visibility, play.tech_caps(), play.tech_unlocked()
	)
	if unit.owner == play.player_faction:
		play.overlay.show_tile_options(CivilianMovement.valid_tiles(play.model, unit))
	else:
		play.hud.toast(
			"Civilian of %s — observe only" % FactionCatalog.name_of(unit.owner)
		)


## Tapping a neighbouring land tile marches the selected civilian there.
static func try_move(play: PlaySession, world_position: Vector2) -> bool:
	var unit: CivilianState = play.civilian_layer.selected_unit
	if unit == null or unit.owner != play.player_faction:
		return false
	var tile: Vector2i = MapGeo.tile_at_world(world_position, PlaySession.TILE_SIZE)
	if not play.model.in_bounds(tile.x, tile.y):
		return false
	var distance: int = absi(unit.tile.x - tile.x) + absi(unit.tile.y - tile.y)
	if distance != 1:
		return false
	var result: Dictionary = play.civilian_layer.apply_move(unit, tile)
	if not bool(result.get("ok", false)):
		play.hud.toast(String(result.get("reason", "")))
	return true


static func on_moved(play: PlaySession, unit: CivilianState, _result: Dictionary) -> void:
	if unit.owner != play.player_faction:
		return
	var province: int = play.model.province_at(unit.tile.x, unit.tile.y)
	var place: String = play.model.province_name(province) if province >= 0 else "the wilds"
	play.hud.toast("The %s marches into %s" % [unit.display_name(), place])
	refresh_panel(play)


static func on_action(play: PlaySession, action: String) -> void:
	if play.victory != null:
		return
	var unit: CivilianState = play.civilian_layer.selected_unit
	if unit == null or unit.owner != play.player_faction:
		return
	var result: Dictionary = CivilianWork.assign(
		play.model, unit, action, play.land_works, play.civilian_layer.units,
		play.stockpile(), play.visibility, CivilianState.NO_TILE, play.tech_caps(),
		play.tech_unlocked()
	)
	if not bool(result.get("ok", false)):
		play.hud.toast(String(result.get("reason", "")))
		return
	play.hud.toast("%s begins: %s" % [unit.display_name(), CivilianWork.label(action)])
	refresh_panel(play)


static func on_cancel(play: PlaySession) -> void:
	var unit: CivilianState = play.civilian_layer.selected_unit
	if unit == null or not unit.is_working():
		return
	unit.cancel_work()
	play.hud.toast("The %s abandons its work." % unit.display_name())
	refresh_panel(play)


static func refresh_panel(play: PlaySession) -> void:
	play.civilian_layer.sync()
	play.civilian_layer.refresh_works()
	var unit: CivilianState = play.civilian_layer.selected_unit
	if unit == null:
		return
	play.hud.panels.show_civilian(
		play.model, unit, play.land_works, play.civilian_layer.units,
		play.stockpile(), play.visibility, play.tech_caps(), play.tech_unlocked()
	)
	play.overlay.clear_tile_options()
	play.overlay.show_tile_options(CivilianMovement.valid_tiles(play.model, unit))


## Build/Work pass: the layer advances every region's orders (looking at another
## map must not pause the empire) and reports completions for the map on screen.
static func resolve_work(play: PlaySession) -> void:
	for report: Dictionary in play.civilian_layer.begin_turn(
		play.world, play.visibility_by_region
	):
		if int(report["region"]) != play.region_index:
			continue
		if not bool(report.get("completed", false)):
			continue
		var changed: Array = report.get("changed", [])
		if not changed.is_empty():
			play.overlay.sync_visibility(play.visibility, changed)
		var type_name: String = CivilianCatalog.display_name(String(report["type_id"]))
		var province: int = int(report["province"])
		var place: String = (
			play.model.province_name(province) if province >= 0 else "the wilds"
		)
		var work_name: String = CivilianWork.label(String(report["action"])).to_lower()
		play.hud.toast("%s in %s: %s" % [type_name, place, work_name])
	play.civilian_layer.sync()
	play.civilian_layer.refresh_works()


static func train(play: PlaySession, type_id: String) -> void:
	if not CivilianCatalog.known(type_id):
		return
	if not CivilianCatalog.is_implemented(type_id):
		play.hud.toast(CivilianCatalog.deferred_reason(type_id))
		return
	if not CivilianCatalog.is_unlocked(type_id, play.tech_unlocked()):
		play.hud.toast(
			"Requires %s." % TechCatalog.display_name(CivilianCatalog.unlock_tech(type_id))
		)
		return
	if play.selected_province != play.capital_province:
		play.hud.toast("Civilians are trained at the capital.")
		return
	var state: PlayerEconomy = play.economy.economy
	var paper: int = state.quantity("paper")
	if not CivilianCatalog.can_afford(type_id, state.treasury, paper):
		play.hud.toast("The crown cannot afford a %s." % CivilianCatalog.display_name(type_id))
		return
	var tile: Vector2i = play.civilian_layer.mustering_tile(play.capital_province)
	if tile.x < 0:
		play.hud.toast("There is no room to muster another civilian.")
		return
	state.spend_treasury(CivilianCatalog.treasury_cost(type_id))
	state.take("paper", CivilianCatalog.paper_cost(type_id))
	var unit: CivilianState = play.civilian_layer.add_unit(
		play.player_faction, type_id, tile
	)
	play.hud.set_treasury(play.treasury())
	play.hud.set_civilians(play.civilian_layer.unit_count_all(play.player_faction))
	play.hud.toast(
		"%s musters at %s" % [unit.display_name(), play.model.province_name(play.capital_province)]
	)
