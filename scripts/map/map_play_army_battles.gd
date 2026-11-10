class_name MapPlayArmyBattles
extends RefCounted
## The land combat pass: every region's field battles, their despatches, and the
## capital verdicts that resolve in the same pass (wiki: combat;
## capital-and-connectivity § Capital loss). Rules stay in ArmyCombat and
## CapitalLoss; this only reports, repaints and keeps the session framing
## (REQ-P3-01, REQ-P3-03).


## Land battles resolve in every region, then the map's ownership ink is
## refreshed when the visible region changed hands; capital losses resolve in the
## same pass. Returns the records for the turn report.
static func resolve(play: PlaySession) -> Array[Dictionary]:
	var before: Array = CapitalLoss.snapshot_world(play.world)
	var battles: Array[Dictionary] = play.army_layer.resolve_battles(
		play.world, MapPlayArmies.battle_context(play)
	)
	if battles.is_empty():
		return battles
	play.emit_battle_resolved(battles)
	var repaint: bool = false
	for battle: Dictionary in battles:
		_report(play, battle)
		var region: int = int(battle.get("region", play.region_index))
		if region == play.region_index and bool(battle.get("captured", false)):
			repaint = true
	var losses: Dictionary = CapitalLoss.resolve_world(play.world, before)
	var capital_changed: bool = apply_capital_loss(play, losses)
	if capital_changed:
		repaint = true
	if repaint:
		if capital_changed:
			# A new seat moves the palace glyphs and the seat labels with it.
			play.refresh_map_views()
		else:
			play.canvas.refresh_ownership()
			play.overlay.refresh_borders()
			play.hud.refresh_minimap()
	play.hud.set_armies(play.army_layer.regiment_count_all(play.player_faction))
	play.hud.set_fleets(play.ship_layer.hull_count_all(play.player_faction))
	if play.army_layer.selected_army != null:
		MapPlayArmies.show_panel(play, play.army_layer.selected_army)
		MapPlayArmies.refresh_options(play, play.army_layer.selected_army)
	return battles


## One battle's despatch: the report line, what a paid attack cost, the plate for
## the human's Quick Battle, and the medal a general earned (wiki: quick-battle).
static func _report(play: PlaySession, battle: Dictionary) -> void:
	var region: int = int(battle.get("region", play.region_index))
	var model: MapModel = (
		play.model if region == play.region_index else play.world.region(region)
	)
	var province: String = model.province_name(int(battle["province"])) if model != null else "—"
	var prefix: String = ""
	if region != play.region_index:
		prefix = "%s — " % FactionCatalog.region_label(region)
	var line: String = prefix + BattleReport.describe_land(
		battle, province, FactionCatalog.names()
	)
	if int(battle.get("attack_paid", 0)) > 0:
		line += " — %d ducats spent" % int(battle["attack_paid"])
	if battle.has("quick") and play.hud != null:
		battle["player_faction"] = play.player_faction
		play.hud.show_quick_battle(battle, prefix + province)
	var medal: String = String(battle.get("medal_gain", ""))
	if not medal.is_empty():
		var general: String = play.army_layer.generals.label(
			int(battle.get("medal_owner", -1)), medal
		)
		if not general.is_empty():
			line += " — %s earns a medal" % general
	play.hud.toast(line, BattleReport.icon_of(battle))


## Reports the capital verdicts of Combat; returns true when the map changed. A
## crown with nothing left falls and its units and dealings leave play.
static func apply_capital_loss(play: PlaySession, losses: Dictionary) -> bool:
	var changed: bool = false
	var fallen: Array = losses.get("fallen", [])
	for entry: Dictionary in fallen:
		play.last_falls.append(entry)
		var faction: int = int(entry["faction"])
		var conqueror: int = int(entry["conqueror"])
		if play.army_layer != null:
			# A fall removes the crown's armies: hand them to nobody.
			play.army_layer.transfer_owner(faction, MapModel.NO_ID)
			play.army_layer.deselect()
		if play.ship_layer != null:
			play.ship_layer.transfer_owner(faction, MapModel.NO_ID)
		CivilianStrandingPass.remove_owner(play.civilian_layer, faction)
		if play.diplomacy != null:
			play.diplomacy.clear_relations_of(faction)
		play.hud.toast(
			"%s falls to %s — its provinces change hands"
			% [FactionCatalog.name_of(faction), FactionCatalog.name_of(conqueror)]
		)
		changed = true
	_record_defeat(play, fallen)
	var reassigned: Array = losses.get("reassigned", [])
	for entry: Dictionary in reassigned:
		var faction: int = int(entry["faction"])
		var region: int = int(entry.get("region", play.region_index))
		var model: MapModel = play.world.region(region)
		var province: int = int(entry["province"])
		var seat: String = model.province_name(province) if model != null else "—"
		play.hud.toast(
			"%s moves its court to %s" % [FactionCatalog.name_of(faction), seat]
		)
		changed = true
	MapPlayFleets.settle_ports(play, reassigned)
	if changed:
		sync_player_capital(play)
	if play.defeat != null:
		play.hud.show_defeat(play.defeat, play.player_faction)
		play.emit_campaign_end(null, play.defeat)
	return changed


## The human crown's terminal fall becomes the session's defeat exactly once.
## AI falls remove that crown and the campaign continues; Minor Nations and
## Tribes are map cleanup, never a player defeat (wiki: victory § Great Power
## defeat; DR-20261109-05).
static func _record_defeat(play: PlaySession, fallen: Array) -> void:
	if play.defeat != null:
		return
	play.defeat = CampaignDefeat.resolve(fallen, play.human_faction_id(), play.turn)


## Keeps the session's capital framing on the player's current seat after a
## reassignment (training and civilian muster read it).
static func sync_player_capital(play: PlaySession) -> void:
	var region: int = FactionCatalog.region_of(play.player_faction)
	var model: MapModel = play.world.region(region)
	if model == null:
		return
	var seat: int = CapitalLoss.seat_of(model, play.player_faction)
	if seat == CapitalLoss.NO_ID:
		return
	play.capital_province = seat
	play.capital_tile = model.capital_tile_of(seat)
