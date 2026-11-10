class_name MapPlayArmies
extends RefCounted
## Army selection, march orders, split/combine and the drill yard.
## Rules stay in ArmyMovement/ArmyCombat; this only drives PlaySession views.
## The land combat pass and its capital verdicts report through
## MapPlayArmyBattles (REQ-P3-01).


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


## One tap cycles the crown's Quick Battle plan; the dossier names it crown-wide
## so it is never mistaken for one army's (wiki: quick-battle § The crown's plan).
static func cycle_plan(play: PlaySession, army: ArmyState) -> void:
	var order: Array[String] = ["balanced", "aggressive", "defensive"]
	var index: int = order.find(QuickBattleActions.normalize_plan(play.battle_plan))
	play.battle_plan = order[(index + 1) % order.size()]
	play.hud.toast("Crown battle plan: %s" % play.battle_plan.capitalize())
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
		"hostile": hostile(play),
		## The observer has no human plate; every exchange auto-resolves (wiki: quick-battle).
		"quick_battle": not play.observer_mode,
		"player_faction": play.human_faction_id(),
		"battle_plan": play.battle_plan,
		"difficulty": Difficulty.combat_multipliers(
			play.human_faction_id(), play.difficulty, FactionCatalog.great_power_ids()),
	}


## Rival land turn — see MapPlayArmyAi (docs/ai.md).
static func run_ai(play: PlaySession) -> Array[Dictionary]:
	return MapPlayArmyAi.run(play)


static func refresh_visibility(play: PlaySession) -> void:
	play.army_layer.sync_visibility(play.visibility, play.player_faction)


static func refresh_panel(play: PlaySession) -> void:
	var army: ArmyState = play.army_layer.selected_army
	if army != null:
		show_panel(play, army)
