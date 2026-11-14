class_name MapPlayLandTurn
extends RefCounted
## End-of-turn land combat: every region fights, then the capital verdicts settle
## and the map ink follows the result (wiki: military-armies, capital-and-
## connectivity § Capital loss). Mirrors MapPlayNavalTurn for the sea: the rules
## resolve each battle, this only orders the pass, reports it and emits the
## plate signal (REQ-P3-02).
##
## The army dossier and march orders live in MapPlayArmies; musters live in
## MapPlayArmyMuster. This module owns the one land battle pass and the crown
## falls it decides.


## Feeding, leaders, techs and difficulty for Combat; seed binds generals.
## `hostile` is the war query (wiki: diplomacy § War required).
static func battle_context(play: PlaySession) -> Dictionary:
	# Every crown fights on its own tech (REQ-P2-03) and pays its own price.
	var tech: Dictionary = MapPlayCampaign.tech_by_faction(play)
	if play.observer_mode and play.ai != null:
		tech[play.player_faction] = play.ai.economy_for(play.player_faction).tech_unlocked
	return {
		"feeding": play.feeding,
		"leaders": play.leaders,
		"tech": tech,
		"pay_attack": func(f: int, c: int) -> int: return ArmyAttackCost.pay(play.ledger_for(f), c),
		## Minor Nations reform a garrison at the parity level applied this turn.
		"parity_era": MilitaryParity.max_great_power_era(MapPlayCampaign.tech_by_faction(play)),
		"seed": play.turn,
		"hostile": _war_query(play),
		## The observer has no human plate; every exchange auto-resolves (wiki: quick-battle).
		"quick_battle": not play.observer_mode,
		"player_faction": play.human_faction_id(),
		"battle_plan": play.battle_plan,
		"difficulty": Difficulty.combat_multipliers(
			play.human_faction_id(), play.difficulty, FactionCatalog.great_power_ids()),
	}


## Battles only happen between declared enemies and Tribes (wiki: factions).
static func _war_query(play: PlaySession) -> Callable:
	return func(a: int, b: int) -> bool:
		return DiplomacyRules.invadable(play.diplomacy, a, b)


## Land battles resolve in every region, then the map's ownership ink is
## refreshed when the visible region changed hands; capital losses resolve in the
## same pass (wiki: capital-and-connectivity § Capital loss). Returns the records.
static func resolve(play: PlaySession) -> Array[Dictionary]:
	var before: Array = CapitalLoss.snapshot_world(play.world)
	var battles: Array[Dictionary] = play.army_layer.resolve_battles(
		play.world, battle_context(play)
	)
	if battles.is_empty():
		return battles
	play.emit_battle_resolved(battles)
	var repaint: bool = false
	for battle: Dictionary in battles:
		var region: int = int(battle.get("region", play.region_index))
		var model: MapModel = play.model if region == play.region_index else play.world.region(region)
		var province: String = model.province_name(int(battle["province"])) if model != null else "—"
		var prefix: String = ""
		if region != play.region_index:
			prefix = "%s — " % FactionCatalog.region_label(region)
		var line: String = prefix + BattleReport.describe_land(
			battle, province, FactionCatalog.names()
		)
		if int(battle.get("attack_paid", 0)) > 0:
			line += " — %d ducats spent" % int(battle["attack_paid"])
		# A Quick Battle plate replays this clash for the court, so the despatch
		# that repeats its outcome is the first line the held-news cap may drop
		# (REQ-P5-06).
		var on_plate: bool = battle.has("quick") and play.hud != null
		if on_plate:
			battle["player_faction"] = play.player_faction
			play.hud.show_quick_battle(battle, prefix + province)
		var medal: String = String(battle.get("medal_gain", ""))
		if not medal.is_empty():
			var winner: int = int(battle.get("medal_owner", -1))
			var general: String = play.army_layer.generals.label(winner, medal)
			if not general.is_empty():
				# The commander's name and the medal he now carries, so a standing
				# that moved is always attributable (wiki: naming § General names;
				# military-generals § Medals).
				line += " — %s earns a medal (%d now)" % [
					general, play.army_layer.generals.medals(winner, medal)
				]
		if on_plate:
			play.hud.toast_plate_line(line, BattleReport.icon_of(battle))
		else:
			play.hud.toast(line, BattleReport.icon_of(battle))
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
		if _recall_home(play, faction, province, region) and play.model != null:
			play.refresh_map_views()
		changed = true
	MapPlayFleets.settle_ports(play, reassigned)
	if changed:
		sync_player_capital(play)
	if play.defeat != null:
		play.hud.show_defeat(play.defeat, play.player_faction)
		play.emit_campaign_end(null, play.defeat)
	return changed


## The court's guard follows its court: a reassigned seat takes the Home Army
## with it, and a court that lost its Home Army with the old seat reforms one at
## the new, because the standard is never deleted (wiki: military-armies
## § Home Army; capital-and-connectivity § Capital loss and reassignment;
## issue #474). Returns true when the region's roster changed.
static func _recall_home(
	play: PlaySession, faction: int, seat: int, region: int
) -> bool:
	if play.army_layer == null or seat < 0:
		return false
	var roster: Array[ArmyState] = []
	roster.assign(play.army_layer.regions.value(region, []))
	var settled: Dictionary = ArmyTraining.settle_seat(
		roster, faction, seat, play.army_layer.next_army
	)
	if settled["army"] == null:
		return false
	if bool(settled.get("minted", false)):
		play.army_layer.next_army += 1
	play.army_layer.regions.set_region(region, roster)
	return true


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
