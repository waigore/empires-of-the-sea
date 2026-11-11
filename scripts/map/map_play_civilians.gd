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
		play.stockpile(), play.visibility, play.tech_caps(), play.tech_unlocked(),
		_context(play)
	)
	if unit.owner == play.player_faction:
		play.overlay.show_tile_options(
			CivilianMovement.valid_tiles(play.model, unit, play.visibility),
			_survey_tiles(play, unit)
		)
	else:
		play.hud.toast(
			"Civilian of %s — observe only" % FactionCatalog.name_of(unit.owner)
		)


## Ground the selected Explorer could read: the survey is a choice of where to
## dig, so the map has to show the choices (wiki: fog-and-exploration
## § Prospecting; DR-20261111-26).
static func _survey_tiles(play: PlaySession, unit: CivilianState) -> Array[Vector2i]:
	if unit.type_id != "explorer":
		return [] as Array[Vector2i]
	var province: int = play.model.province_at(unit.tile.x, unit.tile.y)
	if province == MapModel.NO_ID:
		return [] as Array[Vector2i]
	return MineralSurvey.unsurveyed_in_province(
		play.model, play.land_works, unit.owner, province, play.visibility
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
		# Not a march: a survey mark under the tap starts the survey instead.
		return try_survey(play, unit, tile)
	var result: Dictionary = play.civilian_layer.apply_move(unit, tile, play.visibility)
	if not bool(result.get("ok", false)):
		play.hud.toast(String(result.get("reason", "")))
	return true


## Sends the selected Explorer to read one marked tile in its own province.
static func try_survey(play: PlaySession, unit: CivilianState, tile: Vector2i) -> bool:
	if unit.type_id != "explorer" or unit.is_working():
		return false
	if not MineralSurvey.can_prospect(
		play.model, play.land_works, unit.owner, tile, play.visibility
	):
		return false
	return assign_order(play, "prospect", tile)


static func on_moved(play: PlaySession, unit: CivilianState, _result: Dictionary) -> void:
	if unit.owner != play.player_faction:
		return
	var province: int = play.model.province_at(unit.tile.x, unit.tile.y)
	var place: String = play.model.province_name(province) if province >= 0 else "the wilds"
	play.hud.toast("The %s marches into %s" % [unit.display_name(), place])
	refresh_panel(play)


static func on_action(play: PlaySession, action: String) -> void:
	assign_order(play, action, CivilianState.NO_TILE)


## An order aimed at a tile the unit is not standing on: the survey targets the
## map marks, and any cross-map order a caller names. Returns true when the rules
## accepted it, so a tap that misses falls through to plain selection.
static func assign_order(play: PlaySession, action: String, tile: Vector2i) -> bool:
	if play.campaign_over():
		return false
	var unit: CivilianState = play.civilian_layer.selected_unit
	if unit == null or unit.owner != play.player_faction:
		return false
	var result: Dictionary = CivilianWork.assign(
		play.model, unit, action, play.land_works, play.civilian_layer.units,
		play.stockpile(), play.visibility, tile, play.tech_caps(),
		play.tech_unlocked(), _context(play)
	)
	if not bool(result.get("ok", false)):
		play.hud.toast(String(result.get("reason", "")))
		return false
	play.hud.toast("%s begins: %s" % [unit.display_name(), CivilianWork.label(action)])
	refresh_panel(play)
	return true


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
		play.stockpile(), play.visibility, play.tech_caps(), play.tech_unlocked(),
		_context(play)
	)
	play.overlay.clear_tile_options()
	play.overlay.show_tile_options(
		CivilianMovement.valid_tiles(play.model, unit, play.visibility),
		_survey_tiles(play, unit)
	)


## Build/Work pass: CivilianTurnPass advances every region's orders (looking at
## another map must not pause the empire) and reports completions for the map on
## screen. Each crown's deed is charged to its own ledger, so a rival's purchase
## never touches the human treasury (wiki: civilian-units § Merchant).
static func resolve_work(play: PlaySession) -> void:
	for report: Dictionary in CivilianTurnPass.resolve(
		play.civilian_layer, play.world, play.court_charts, _purses(play)
	):
		if not bool(report.get("completed", false)):
			continue
		if String(report["action"]) == LandPurchase.ACTION:
			_settle_purchase(play, report)
			if int(report["region"]) == play.region_index:
				# The tile's owner changed, so borders, tint and the region chip
				# all redraw whoever holds the new deed.
				play.refresh_map_views()
			continue
		if int(report["region"]) != play.region_index:
			continue
		var changed: Array = report.get("changed", [])
		if not changed.is_empty():
			play.overlay.sync_visibility(play.visibility, changed)
		var type_name: String = CivilianCatalog.display_name(String(report["type_id"]))
		var province: int = int(report["province"])
		var place: String = (
			play.model.province_name(province) if province >= 0 else "the wilds"
		)
		if String(report["action"]) == "prospect":
			play.hud.toast(_survey_line(play, report, type_name, place))
			# The province sheet now names the deposit (or its absence).
			if play.selected_province >= 0 and play.hud.panels.is_panel_open():
				play.hud.panels.panel.refresh(
					play.model, play.selected_province,
					MapPlayImprovements.crown_link(play, play.selected_province)
				)
			continue
		var work_name: String = CivilianWork.label(String(report["action"])).to_lower()
		play.hud.toast("%s%s in %s: %s" % [
			_owner_label(play, int(report.get("owner", -1))), type_name, place, work_name
		])
	play.civilian_layer.sync()
	play.civilian_layer.refresh_works()
	# A completed road or a grown town changes what the province sheet says, so
	# repaint it in place (the player may be reading it while the turn resolves).
	if play.selected_province >= 0 and play.hud.panels.is_panel_open():
		play.hud.panels.panel.refresh_crown(
			MapPlayImprovements.crown_link(play, play.selected_province)
		)


## Combat can take the land under a crown-land crew. It withdraws to a legal
## tile or is lost with the province (`CivilianStranding`); the human court is
## told what happened, rivals are resolved silently like every other AI move.
static func settle_stranding(play: PlaySession) -> void:
	if play.civilian_layer == null or play.world == null:
		return
	var had_selection: bool = play.civilian_layer.selected_unit != null
	for report: Dictionary in CivilianStrandingPass.settle_stranding(play.civilian_layer, play.world):
		if int(report.get("owner", -1)) != play.player_faction:
			continue
		var region: int = int(report.get("region", play.region_index))
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		var type_name: String = CivilianCatalog.display_name(String(report["type"]))
		var from: Vector2i = report["from"]
		var province: int = model.province_at(from.x, from.y)
		var place: String = model.province_name(province) if province >= 0 else "the wilds"
		if bool(report.get("lost", false)):
			play.hud.toast("%s in %s is lost with the province" % [type_name, place])
		else:
			play.hud.toast("%s withdraws from %s" % [type_name, place])
	if had_selection and play.civilian_layer.selected_unit == null:
		play.hud.panels.hide_civilian()


## A finished survey names the find for the court that paid for it, or says the
## ground held nothing: a hidden deposit never changes hands silently (wiki:
## fog-and-exploration § Prospecting; RUB-P5-06). A rival's survey is news that
## ground was read — never what was in it (DR-20261111-26, per court).
static func _survey_line(
	play: PlaySession, report: Dictionary, type_name: String, place: String
) -> String:
	var owner_id: int = int(report.get("owner", -1))
	var owner: String = _owner_label(play, owner_id)
	if owner_id != play.player_faction:
		return "%s%s surveys %s." % [owner, type_name, place]
	var found: String = String(report.get("find", ""))
	if found.is_empty():
		return "%s%s surveys %s — no mineral in the ground." % [owner, type_name, place]
	return "%s%s finds %s in %s — a mine can rise." % [
		owner, type_name, ImprovementCatalog.commodity_label(found), place
	]


## A rival's finished work is announced with its crown, so the player never
## mistakes it for their own crew (wiki: civilian-units; DR-20261109-14).
static func _owner_label(play: PlaySession, owner: int) -> String:
	if owner < 0 or owner == play.player_faction:
		return ""
	return "%s's " % FactionCatalog.name_of(owner)


## One purse per crown: the human ledger, or each rival's own (the observer runs
## every crown on an AI ledger). A crown with no ledger buys no land.
static func _purses(play: PlaySession) -> Dictionary:
	var purses: Dictionary = {}
	if play == null:
		return purses
	play.ensure_ai()
	for faction: int in FactionCatalog.great_power_ids():
		var ledger: PlayerEconomy = play.ledger_for(faction)
		if ledger != null:
			purses[faction] = ledger
	return purses


## A deed is signed (or the purse fails it) during Build/Work. Only the human
## court hears about it; a rival's purchase is silent news to the player, but
## the tile's owner changed, so the caller redraws the political map.
static func _settle_purchase(play: PlaySession, report: Dictionary) -> void:
	if int(report.get("owner", -1)) != play.player_faction:
		return
	var region: int = int(report["region"])
	var model: MapModel = play.world.region(region)
	var tile: Vector2i = report["tile"]
	var province: int = int(report["province"])
	var place: String = model.province_name(province) if province >= 0 else "the wilds"
	if model.is_purchased_tile(tile):
		play.hud.set_treasury(play.treasury())
		# The deed is the only play path that develops a Minor or Tribe town
		# (wiki: civilian-units § Merchant; DR-20261112-01).
		play.hud.toast(
			MinorTownGrowth.deed_line(
				model, model.province_data(province), place,
				int(report.get("town_level", 0))
			)
		)
		return
	play.hud.toast("The purchase in %s failed — the treasury could not close it." % place)


static func _context(play: PlaySession) -> Dictionary:
	return {"treasury": play.treasury(), "diplomacy": play.diplomacy}


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
