class_name MapPlayDiplomacy
extends RefCounted
## Court intents and the diplomacy phase for the map screen. Rules live in
## scripts/rules; this wires orders to the ledger and reports the outcome.


static func open(play: PlaySession) -> void:
	if play.diplomacy == null:
		play.diplomacy = DiplomacyState.new()
		play.diplomacy.initialize(play.turn)
	sync_first_contact(play)
	DiplomacyHud.show(
		play.hud.panels,
		play.diplomacy,
		play.world,
		play.player_faction,
		play.treasury(),
		_tech(play)
	)


static func refresh(play: PlaySession) -> void:
	if play.diplomacy == null:
		return
	DiplomacyHud.refresh(
		play.hud.panels,
		play.diplomacy,
		play.world,
		play.player_faction,
		play.treasury(),
		_tech(play)
	)


static func on_order(play: PlaySession, kind: String, target: int, arg: String) -> void:
	if play.victory != null:
		return
	if play.diplomacy == null:
		return
	var order: Dictionary = {"kind": kind, "from": play.player_faction, "target": target}
	if kind == DiplomacyOrders.KIND_OVERTURE:
		order["stage"] = arg
	elif kind == DiplomacyOrders.KIND_AID or kind == DiplomacyOrders.KIND_SUBSIDY:
		order["amount"] = arg.to_int()
	var economy: PlayerEconomy = play.economy.economy if play.economy != null else null
	var result: Dictionary = DiplomacyOrders.apply(
		play.diplomacy, play.world, economy, order, _tech(play)
	)
	var message: String = String(result.get("message", ""))
	if not bool(result.get("ok", false)):
		play.hud.toast(String(result.get("reason", "The court refuses.")))
	elif not message.is_empty():
		play.hud.toast(message)
	if result.has("absorbed") and play.ship_layer != null:
		play.ship_layer.transfer_owner(int(result["absorbed"]), play.player_faction)
	if bool(result.get("map_changed", false)):
		_rebuild_map(play)
	play.hud.set_treasury(play.treasury())
	refresh(play)


## End-of-turn diplomacy phase: first contact, rival-court AI orders, subsidy
## upkeep, relation drift.
static func resolve_turn(play: PlaySession) -> void:
	if play.diplomacy == null:
		return
	sync_first_contact(play)
	run_ai(play)
	play.diplomacy.end_turn()
	refresh(play)


## Rival Great Powers take their one diplomatic action for the turn before the
## phase closes, so declarations apply to this turn's movement and combat
## (wiki: diplomacy § Turn Sequence).
static func run_ai(play: PlaySession) -> void:
	if play.ai == null:
		play.ai = AiState.new()
	var result: Dictionary = AiTurn.run(
		play.diplomacy,
		play.world,
		play.ai,
		play.turn,
		play.player_faction,
		play.map_seed,
		_ai_context(play)
	)
	play.ai_trace.assign(result.get("trace", []))
	if play.hud == null:
		return
	for message: String in result.get("messages", []):
		play.hud.toast(message)


## Unit counts the war-desire score reads; rival stockpiles arrive with the AI
## economy planner, so the resource-need bonus stays inert for now.
static func _ai_context(play: PlaySession) -> Dictionary:
	var regiments: Dictionary = {}
	var ships: Dictionary = {}
	for raw: Dictionary in FactionCatalog.all():
		var faction: int = int(raw["id"])
		if play.army_layer != null:
			regiments[faction] = play.army_layer.regiment_count_all(faction)
		if play.ship_layer != null:
			ships[faction] = play.ship_layer.hull_count_all(faction)
	return {"regiments": regiments, "ships": ships}


## A Tribe is contacted only by non-unknown tile visibility in its provinces;
## sea-reachable colonial intel alone does not count (wiki: diplomacy § first contact).
static func sync_first_contact(play: PlaySession) -> Array[int]:
	var contacted: Array[int] = []
	if play.diplomacy == null or play.world == null:
		return contacted
	for tribe: int in FactionCatalog.tribe_ids():
		if play.diplomacy.has_relation(play.player_faction, tribe):
			continue
		if not _sees_tribe(play, tribe):
			continue
		play.diplomacy.ensure_relation(play.player_faction, tribe, play.turn)
		play.diplomacy.touch(play.player_faction, tribe, "firstContact")
		contacted.append(tribe)
	if not contacted.is_empty():
		var names: PackedStringArray = []
		for tribe: int in contacted:
			names.append(FactionCatalog.name_of(tribe))
		play.hud.toast("First contact: %s" % ", ".join(names))
	return contacted


static func _sees_tribe(play: PlaySession, tribe: int) -> bool:
	for region_index: int in play.visibility_by_region.keys():
		var visibility: VisibilityModel = play.visibility_by_region[region_index]
		if visibility == null or visibility.model == null:
			continue
		for province: ProvinceState in visibility.model.provinces:
			if province.owner != tribe:
				continue
			if visibility.province_visibility(province.id) != VisibilityModel.Level.UNKNOWN:
				return true
	return false


static func _rebuild_map(play: PlaySession) -> void:
	play.refresh_map_views()


## Researched techs gate embassy and GP Join Empire orders
## (wiki: tech-tree-diplomacy-civilian).
static func _tech(play: PlaySession) -> Dictionary:
	if play.economy == null or play.economy.economy == null:
		return {}
	return play.economy.economy.tech_unlocked
