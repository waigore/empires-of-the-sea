class_name MapPlayArmies
extends RefCounted
## Army selection, march orders, split/combine and land-battle reporting.
## Rules stay in ArmyMovement/ArmyCombat; this only drives PlaySession views.


static func select(play: PlaySession, army: ArmyState) -> void:
	if army == null:
		return
	play.selected_province = -1
	play.overlay.select_province(-1)
	play.hud.panels.hide_province()
	play.hud.panels.hide_fleet()
	play.hud.panels.hide_civilian()
	show_panel(play, army)
	refresh_options(play, army)
	if army.owner != play.player_faction:
		play.hud.toast("Army of %s — observe only" % FactionCatalog.name_of(army.owner))


static func show_panel(play: PlaySession, army: ArmyState) -> void:
	if army == null:
		return
	var is_player: bool = army.owner == play.player_faction
	var command: String = ""
	var muster: Array[Dictionary] = []
	var embark: String = ""
	if is_player and play.economy != null and play.economy.economy != null:
		command = play.army_layer.command_text(army)
		if army.home:
			muster = ArmyTraining.rows(play.economy.economy)
	if is_player:
		embark = _embark_note(play, army)
	play.hud.panels.show_army(
		play.model, army, is_player, can_merge(play, army), command, muster, embark,
		play.battle_plan
	)


## A squadron in port here that can take the army aboard (wiki: ships-and-naval
## § Naval transport).
static func _embark_note(play: PlaySession, army: ArmyState) -> String:
	for fleet: FleetState in play.ship_layer.fleets:
		if fleet == null or fleet.owner != army.owner:
			continue
		if not fleet.is_in_port() or fleet.province != army.province:
			continue
		if bool(NavalTransport.can_embark(play.model, army, fleet).get("ok", false)):
			return "The squadron here can carry %d regiments." % army.count()
	return ""


static func can_merge(play: PlaySession, army: ArmyState) -> bool:
	if army == null or army.owner != play.player_faction:
		return false
	return play.army_layer.armies_in(army.province, army.owner).size() > 1


static func refresh_options(play: PlaySession, army: ArmyState) -> void:
	play.overlay.clear_move_options()
	if army == null or army.owner != play.player_faction:
		return
	var provinces: Array[int] = ArmyMovement.destinations(play.model, army)
	if provinces.is_empty():
		return
	var no_zones: Array[int] = []
	play.overlay.show_move_options(no_zones, provinces)


## Taps a province for the selected army. Returns false when the tap is not an
## army order, so the province dossier can open instead.
static func try_order(play: PlaySession, tile: Vector2i) -> bool:
	var army: ArmyState = play.army_layer.selected_army
	if army == null or army.owner != play.player_faction:
		return false
	var province_id: int = play.model.province_at(tile.x, tile.y)
	if province_id == MapModel.NO_ID:
		return false
	if not ArmyMovement.destinations(play.model, army).has(province_id):
		return false
	var result: Dictionary = play.army_layer.order(army, province_id, may_invade(play, province_id))
	if bool(result.get("ok", false)):
		return true
	play.hud.toast(String(result.get("reason", "")))
	return true


## Invading foreign land needs war with its owner, except a Tribe; unowned land
## is not an attack (wiki: factions § Tribe; diplomacy § War required).
static func may_invade(play: PlaySession, province_id: int) -> bool:
	var owner: int = play.model.province_owner(province_id)
	if owner == MapModel.NO_ID or owner == play.player_faction:
		return true
	return DiplomacyRules.invadable(play.diplomacy, play.player_faction, owner)


## Battles only happen between declared enemies and Tribes (wiki: factions).
static func hostile(play: PlaySession) -> Callable:
	return func(a: int, b: int) -> bool:
		return DiplomacyRules.invadable(play.diplomacy, a, b)


static func on_moved(play: PlaySession, army: ArmyState, result: Dictionary) -> void:
	if army.owner != play.player_faction:
		return
	show_panel(play, army)
	refresh_options(play, army)
	if bool(result.get("attacked", false)):
		play.hud.toast("The army marches on %s" % play.model.province_name(army.province))
	else:
		play.hud.toast("The army reaches %s" % play.model.province_name(army.province))


static func on_action(play: PlaySession, action: String) -> void:
	if play.campaign_over():
		return
	var army: ArmyState = play.army_layer.selected_army
	if army == null or army.owner != play.player_faction:
		return
	if action.begins_with("detach:"):
		var ids: Array[String] = [action.trim_prefix("detach:")]
		detach(play, army, ids)
	elif action == "detach_all":
		detach(play, army, army.regiments.duplicate())
	elif action == "merge":
		merge(play, army)
	elif action == "embark":
		embark(play, army)
	elif action.begins_with("recruit:"):
		recruit(play, action.trim_prefix("recruit:"))
	elif action == "plan:next":
		cycle_plan(play, army)


## One tap cycles the Quick Battle stance; the dossier shows the current plan
## so the choice is never buried (wiki: quick-battle; REQ-P5-03).
static func cycle_plan(play: PlaySession, army: ArmyState) -> void:
	var order: Array[String] = ["balanced", "aggressive", "defensive"]
	var index: int = order.find(play.battle_plan)
	play.battle_plan = order[(index + 1) % order.size()]
	play.hud.toast("Battle plan: %s" % play.battle_plan.capitalize())
	show_panel(play, army)


## Boards the selected army on the squadron sharing its port (wiki:
## ships-and-naval § Naval transport).
static func embark(play: PlaySession, army: ArmyState) -> void:
	var refusal: String = ""
	for fleet: FleetState in play.ship_layer.fleets:
		if fleet == null or fleet.owner != army.owner:
			continue
		if not fleet.is_in_port() or fleet.province != army.province:
			continue
		var check: Dictionary = NavalTransport.can_embark(play.model, army, fleet)
		if not bool(check.get("ok", false)):
			if refusal.is_empty():
				refusal = String(check.get("reason", ""))
			continue
		var result: Dictionary = ArmyTransport.embark(play.army_layer, army, fleet)
		if not bool(result.get("ok", false)):
			play.hud.toast(String(result.get("reason", "The army cannot board.")))
			return
		play.hud.toast(
			"The army boards the fleet at %s" % play.model.province_name(fleet.province)
		)
		show_panel(play, army)
		refresh_options(play, army)
		return
	play.hud.toast(refusal if not refusal.is_empty() else "No squadron waits in this port.")


## Opens the drill yard on the Home Army dossier (the province panel's Recruit
## order lands here, so the muster list is one tap from the map).
static func open_muster(play: PlaySession) -> void:
	var home: ArmyState = ArmyTraining.home_army(
		play.army_layer.armies, play.player_faction
	)
	if home == null:
		play.hud.toast("The Home Army musters at your capital.")
		return
	play.army_layer.select(home)
	play.hud.panels.army_panel.set_muster_open(true)


## Mints one regiment into the Home Army and keeps the HUD count in step.
static func recruit(play: PlaySession, type_id: String) -> void:
	if play.economy == null or play.economy.economy == null:
		return
	var result: Dictionary = play.army_layer.recruit(
		play.player_faction, type_id, play.economy.economy
	)
	if not bool(result.get("ok", false)):
		play.hud.toast(String(result.get("reason", "The regiment cannot muster.")))
		return
	play.hud.set_armies(play.army_layer.regiment_count_all(play.player_faction))
	play.hud.toast(
		"%s joins the Home Army" % RegimentCatalog.display_name(type_id)
	)
	show_panel(play, play.army_layer.selected_army)


## Detaches a batch of regiments in one order (single detach and Detach all
## share this path, so repeated chores stay batched — REQ-P5-04).
static func detach(play: PlaySession, army: ArmyState, ids: Array[String]) -> void:
	var result: Dictionary = play.army_layer.split(army, ids)
	if not bool(result.get("ok", false)):
		play.hud.toast(String(result.get("reason", "The regiments stay.")))
		return
	var created: ArmyState = result["army"] as ArmyState
	play.army_layer.select(created)
	if created.count() == 1:
		play.hud.toast(
			"%s detaches as a field army in %s"
			% [
				RegimentCatalog.display_name(created.type_of(created.regiments[0])),
				play.model.province_name(created.province),
			]
		)
		return
	play.hud.toast(
		"%d regiments form a field army in %s"
		% [created.count(), play.model.province_name(created.province)]
	)


static func merge(play: PlaySession, army: ArmyState) -> void:
	var result: Dictionary = play.army_layer.combine(army)
	if not bool(result.get("ok", false)):
		play.hud.toast(String(result.get("reason", "The armies stay apart.")))
		return
	var target: ArmyState = result["army"] as ArmyState
	play.army_layer.select(target)
	play.hud.toast(
		"The armies combine under one standard in %s"
		% play.model.province_name(target.province)
	)


## Feeding coverage, leader keys and techs for this Combat phase; the seed keeps
## general binding reproducible. `hostile` is the court's war query, so only
## factions at war meet in battle (wiki: diplomacy § War required).
static func battle_context(play: PlaySession) -> Dictionary:
	var tech: Dictionary = {}
	if play.observer_mode and play.ai != null:
		# Every crown fights on its own researched tech (REQ-P2-03).
		for faction: int in FactionCatalog.great_power_ids():
			tech[faction] = play.ai.economy_for(faction).tech_unlocked
	elif play.economy != null and play.economy.economy != null:
		tech[play.player_faction] = play.economy.economy.tech_unlocked
	return {
		"feeding": play.feeding,
		"leaders": play.leaders,
		"tech": tech,
		"seed": play.turn,
		"hostile": hostile(play),
		## The observer has no human battle to plate; every exchange
		## auto-resolves (wiki: quick-battle).
		"quick_battle": not play.observer_mode,
		"player_faction": play.human_faction_id(),
		"battle_plan": play.battle_plan,
	}


## Rival land turn — see MapPlayArmyAi (docs/ai.md).
static func run_ai(play: PlaySession) -> Array[Dictionary]:
	return MapPlayArmyAi.run(play)


## Land battles resolve in every region, then ownership ink refreshes when the
## visible region changed hands. Capital losses resolve in the same pass
## (wiki: capital-and-connectivity § Capital loss and reassignment); returns
## the battle records.
static func resolve_battles(play: PlaySession) -> Array[Dictionary]:
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
		play.hud.toast(line)
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
		show_panel(play, play.army_layer.selected_army)
		refresh_options(play, play.army_layer.selected_army)
	return battles

## Reports the capital verdicts of the Combat phase. A crown with nothing left
## falls and its armies, squadrons and dealings leave play (wiki: victory
## § Great Power defeat; DR-20261109-05). True when the map changed.
static func apply_capital_loss(play: PlaySession, losses: Dictionary) -> bool:
	var changed: bool = false
	var fallen: Array = losses.get("fallen", [])
	for entry: Dictionary in fallen:
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



static func refresh_visibility(play: PlaySession) -> void:
	play.army_layer.sync_visibility(play.visibility, play.player_faction)


static func refresh_panel(play: PlaySession) -> void:
	var army: ArmyState = play.army_layer.selected_army
	if army != null:
		show_panel(play, army)
