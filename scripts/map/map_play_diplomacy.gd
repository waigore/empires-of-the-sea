class_name MapPlayDiplomacy
extends RefCounted
## Court intents and the diplomacy phase for the map screen. Rules live in
## scripts/rules; this wires orders to the ledger and reports the outcome.

const PLAYER_FACTION: int = FactionCatalog.PLAYER_FACTION


static func open(play: PlaySession) -> void:
	if play.diplomacy == null:
		play.diplomacy = DiplomacyState.new()
		play.diplomacy.initialize(play.turn)
	sync_first_contact(play)
	DiplomacyHud.show(
		play.hud.panels,
		play.diplomacy,
		play.world,
		PLAYER_FACTION,
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
		PLAYER_FACTION,
		play.treasury(),
		_tech(play)
	)


static func on_order(play: PlaySession, kind: String, target: int, arg: String) -> void:
	if play.diplomacy == null:
		return
	var order: Dictionary = {"kind": kind, "from": PLAYER_FACTION, "target": target}
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
		play.ship_layer.transfer_owner(int(result["absorbed"]), PLAYER_FACTION)
	if bool(result.get("map_changed", false)):
		_rebuild_map(play)
	play.hud.set_treasury(play.treasury())
	refresh(play)


## End-of-turn diplomacy phase: first contact, subsidy upkeep, relation drift.
static func resolve_turn(play: PlaySession) -> void:
	if play.diplomacy == null:
		return
	sync_first_contact(play)
	play.diplomacy.end_turn()
	refresh(play)


## A Tribe is contacted only by non-unknown tile visibility in its provinces;
## sea-reachable colonial intel alone does not count (wiki: diplomacy § first contact).
static func sync_first_contact(play: PlaySession) -> Array[int]:
	var contacted: Array[int] = []
	if play.diplomacy == null or play.world == null:
		return contacted
	for tribe: int in FactionCatalog.tribe_ids():
		if play.diplomacy.has_relation(PLAYER_FACTION, tribe):
			continue
		if not _sees_tribe(play, tribe):
			continue
		play.diplomacy.ensure_relation(PLAYER_FACTION, tribe, play.turn)
		play.diplomacy.touch(PLAYER_FACTION, tribe, "firstContact")
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
