class_name MapPlayArmies
extends RefCounted
## The army dossier and march orders: selecting a standard, the province taps it
## takes, boarding a squadron, the crown's battle plan, the rival land turn and
## the view refreshes that follow (wiki: military-armies; ships-and-naval
## § Naval transport). Rules stay in ArmyMovement/ArmyCombat; this only drives
## PlaySession views.
##
## Register changes live in MapPlayArmyMuster, end-of-turn land combat in
## MapPlayLandTurn (REQ-P3-02).


## The province panel's Recruit order lands here, so the muster list is one tap
## from the map. The dossier belongs to MapPlayArmies; only the register moves.
static func open_muster(play: PlaySession) -> void:
	var home: ArmyState = ArmyTraining.home_army(
		play.army_layer.armies, play.player_faction
	)
	if home == null:
		play.hud.toast("The Home Army musters at your capital.")
		return
	play.army_layer.select(home)
	play.hud.panels.army_panel.set_muster_open(true)


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
	var hospital: Dictionary = {}
	if is_player and play.economy != null and play.economy.economy != null:
		command = play.army_layer.command_text(army)
		if army.home:
			muster = ArmyTraining.rows(play.economy.economy)
		hospital = hospital_order(play, army)
	if is_player:
		embark = _embark_note(play, army)
	play.hud.panels.show_army(
		play.model, army, is_player, can_merge(play, army), command, muster, embark,
		play.battle_plan, hospital
	)


## The dossier's field-hospital order: `{caption, ok}` or empty when the crown
## has nothing to offer (no ledger, or the army already carries one). A blocked
## order still shows, disabled, with the rules' own reason as its caption
## (DR-20261112-07).
static func hospital_order(play: PlaySession, army: ArmyState) -> Dictionary:
	if army == null or play.model == null or army.field_hospital:
		return {}
	if play.economy == null or play.economy.economy == null:
		return {}
	var economy: PlayerEconomy = play.economy.economy
	var check: Dictionary = HospitalTrain.check(
		play.model, army, economy.tech_unlocked, economy.stockpile
	)
	if not bool(check.get("ok", false)):
		return {"caption": String(check.get("reason", "")), "ok": false}
	return {"caption": "Pitch a field hospital (%s)" % HospitalTrain.price_text(), "ok": true}


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


static func on_moved(play: PlaySession, army: ArmyState, result: Dictionary) -> void:
	if army.owner != play.player_faction:
		return
	show_panel(play, army)
	refresh_options(play, army)
	if bool(result.get("attacked", false)):
		play.hud.toast("The army marches on %s" % play.model.province_name(army.province))
	else:
		play.hud.toast("The army reaches %s" % play.model.province_name(army.province))


## One door for every dossier order: the tap names the order, the owning module
## applies it (registers in MapPlayArmyMuster — REQ-P3-02).
static func on_action(play: PlaySession, action: String) -> void:
	if play.campaign_over():
		return
	var army: ArmyState = play.army_layer.selected_army
	if army == null or army.owner != play.player_faction:
		return
	if action.begins_with("detach:"):
		var ids: Array[String] = [action.trim_prefix("detach:")]
		MapPlayArmyMuster.detach(play, army, ids)
	elif action == "detach_all":
		MapPlayArmyMuster.detach(play, army, army.regiments.duplicate())
	elif action == "merge":
		MapPlayArmyMuster.merge(play, army)
	elif action == "embark":
		embark(play, army)
	elif action.begins_with("recruit:"):
		MapPlayArmyMuster.recruit(play, action.trim_prefix("recruit:"))
	elif action == "plan:next":
		cycle_plan(play, army)
	elif action == "hospital":
		MapPlayArmyMuster.pitch_hospital(play, army)
	elif action.begins_with("rename:"):
		rename_colours(play, army, action.trim_prefix("rename:"))


## The crown names its colours (wiki: naming § Regiment names; DR-20261113-03).
## A name is identity only, so the order spends no move, coin or phase: the
## dossier offers it, the rules tidy it and refuse what a title cannot bear, and
## the army carries it through a split, a merge and the save like any christened
## title. `args` is `<instance id>:<typed name>`, the instance id holding no
## colon, so a name may contain one.
static func rename_colours(play: PlaySession, army: ArmyState, args: String) -> void:
	var cut: int = args.find(":")
	if cut <= 0:
		return
	var regiment_id: String = args.substr(0, cut)
	var result: Dictionary = RegimentRename.apply(army, regiment_id, args.substr(cut + 1))
	if not bool(result.get("ok", false)):
		play.hud.toast(String(result.get("reason", "That name cannot be borne.")))
		show_panel(play, army)
		return
	play.hud.toast("The colours are renamed — %s" % String(result["name"]))
	show_panel(play, army)


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
		# The fleet now carries troops: its dossier says so at once.
		MapPlayFleets.show_dossier(play, fleet)
		show_panel(play, army)
		refresh_options(play, army)
		return
	play.hud.toast(refusal if not refusal.is_empty() else "No squadron waits in this port.")


## Rival land turn — see MapPlayArmyAi (docs/ai.md).
static func run_ai(play: PlaySession) -> Array[Dictionary]:
	return MapPlayArmyAi.run(play)


static func hide_dossier(play: PlaySession) -> void:
	play.hud.panels.hide_army()


static func refresh_visibility(play: PlaySession) -> void:
	play.army_layer.sync_visibility(play.visibility, play.player_faction)


static func refresh_panel(play: PlaySession) -> void:
	var army: ArmyState = play.army_layer.selected_army
	if army != null:
		show_panel(play, army)
