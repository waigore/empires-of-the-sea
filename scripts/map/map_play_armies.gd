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
	if is_player and play.economy != null and play.economy.economy != null:
		command = play.army_layer.command_text(army)
		if army.home:
			muster = ArmyTraining.rows(play.economy.economy)
	play.hud.panels.show_army(
		play.model, army, is_player, can_merge(play, army), command, muster
	)


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


## Invading foreign land needs war with its owner; unowned land is not an attack
## (wiki: diplomacy § War required for hostile actions).
static func may_invade(play: PlaySession, province_id: int) -> bool:
	var owner: int = play.model.province_owner(province_id)
	if owner == MapModel.NO_ID or owner == play.player_faction:
		return true
	return DiplomacyRules.at_war_with(play.diplomacy, play.player_faction, owner)


## Battles only happen between factions at war.
static func hostile(play: PlaySession) -> Callable:
	return func(a: int, b: int) -> bool:
		return DiplomacyRules.at_war_with(play.diplomacy, a, b)


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
	elif action.begins_with("recruit:"):
		recruit(play, action.trim_prefix("recruit:"))


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


## Feeding coverage, leader keys and the player's techs for this Combat phase;
## the seed keeps general binding reproducible for a given turn. `hostile` is the
## court's war query, so only factions at war meet in battle (wiki: diplomacy §
## War required for hostile actions).
static func battle_context(play: PlaySession) -> Dictionary:
	var tech: Dictionary = {}
	if play.economy != null and play.economy.economy != null:
		tech[play.player_faction] = play.economy.economy.tech_unlocked
	return {
		"feeding": play.feeding,
		"leaders": play.leaders,
		"tech": tech,
		"seed": play.turn,
		"hostile": hostile(play),
	}


## Land battles resolve in every region, then the map's ownership ink is
## refreshed when the visible region changed hands.
static func resolve_battles(play: PlaySession) -> void:
	var battles: Array[Dictionary] = play.army_layer.resolve_battles(
		play.world, battle_context(play)
	)
	if battles.is_empty():
		return
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
	if repaint:
		play.canvas.refresh_ownership()
		play.overlay.refresh_borders()
	play.hud.set_armies(play.army_layer.regiment_count_all(play.player_faction))
	if play.army_layer.selected_army != null:
		show_panel(play, play.army_layer.selected_army)
		refresh_options(play, play.army_layer.selected_army)


static func refresh_visibility(play: PlaySession) -> void:
	play.army_layer.sync_visibility(play.visibility, play.player_faction)


static func refresh_panel(play: PlaySession) -> void:
	var army: ArmyState = play.army_layer.selected_army
	if army != null:
		show_panel(play, army)
