class_name MapPlayArmyMuster
extends RefCounted
## The crown's register: mustering into the Home Army and splitting or combining
## a field army (wiki: military-armies § Recruitment, § Splitting and
## combining). Presentation only — ArmyTraining, ArmyLayer and the roster rules
## own every outcome; this reports them (REQ-P3-02).
##
## March orders and the dossier door live in MapPlayArmies; this module only
## changes what a standard carries.


## Queues one regiment into the Home Army. The drill yard's order is a
## `BuildUnitOrder`: it is paid and christened in Build/work at the turn's close,
## so the standard marches with the next Orders phase (wiki: military-armies
## § Recruitment; workers-and-population § Phase placement).
static func recruit(play: PlaySession, type_id: String) -> void:
	if play.economy == null or play.economy.economy == null:
		return
	var economy: PlayerEconomy = play.economy.economy
	var reason: String = ArmyTraining.muster_blocked_reason(
		economy, play.army_layer.armies, play.player_faction, type_id
	)
	if not reason.is_empty():
		play.hud.toast(reason)
		return
	economy.queue_build(RecruitQueue.KIND_REGIMENT, type_id)
	play.hud.toast(
		"%s is under orders — it musters next turn"
		% RegimentCatalog.display_name(type_id)
	)
	MapPlayArmies.show_panel(play, play.army_layer.selected_army)


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
		var regiment_id: String = created.regiments[0]
		play.hud.toast(
			"%s (%s) detaches as a field army in %s"
			% [
				RegimentNames.of(created, regiment_id),
				RegimentCatalog.display_name(created.type_of(regiment_id)),
				play.model.province_name(created.province),
			]
		)
		return
	play.hud.toast(
		"%d regiments form a field army in %s"
		% [created.count(), play.model.province_name(created.province)]
	)


## Pitching a field hospital train: the register's materials buy the tents that
## march with the standard from now on (DR-20261112-07). The rules own the
## refusal; this spends the stockpile and reports it.
static func pitch_hospital(play: PlaySession, army: ArmyState) -> void:
	if play.economy == null or play.economy.economy == null or play.model == null:
		return
	var economy: PlayerEconomy = play.economy.economy
	var check: Dictionary = HospitalTrain.check(
		play.model, army, economy.tech_unlocked, economy.stockpile
	)
	if not bool(check.get("ok", false)):
		play.hud.toast(String(check.get("reason", "The train cannot march.")))
		return
	var cost: Dictionary = HospitalTrain.cost()
	for commodity: String in cost.keys():
		economy.take(commodity, int(cost[commodity]))
	HospitalTrain.apply(army)
	play.hud.toast(
		"The army pitches a field hospital train — %s from the stores"
		% HospitalTrain.price_text()
	)
	MapPlayArmies.show_panel(play, army)


## Pitching a field hospital train: the register's materials buy the tents that
## march with the standard from now on (DR-20261112-07). The rules own the
## refusal; this spends the stockpile and reports it.
static func pitch_hospital(play: PlaySession, army: ArmyState) -> void:
	if play.economy == null or play.economy.economy == null or play.model == null:
		return
	var economy: PlayerEconomy = play.economy.economy
	var check: Dictionary = HospitalTrain.check(
		play.model, army, economy.tech_unlocked, economy.stockpile
	)
	if not bool(check.get("ok", false)):
		play.hud.toast(String(check.get("reason", "The train cannot march.")))
		return
	var cost: Dictionary = HospitalTrain.cost()
	for commodity: String in cost.keys():
		economy.take(commodity, int(cost[commodity]))
	HospitalTrain.apply(army)
	play.hud.toast(
		"The army pitches a field hospital train — %s from the stores"
		% HospitalTrain.price_text()
	)
	MapPlayArmies.show_panel(play, army)


## Combines the selected standard with the friendly army sharing its province.
static func merge(play: PlaySession, army: ArmyState) -> void:
	var result: Dictionary = play.army_layer.combine(army)
	if not bool(result.get("ok", false)):
		play.hud.toast(String(result.get("reason", "The armies stay apart.")))
		return
	var target: ArmyState = result["army"] as ArmyState
	play.army_layer.select(target)
	var line: String = (
		"The armies combine under one standard in %s"
		% play.model.province_name(target.province)
	)
	# A train belongs to a standard, so a combine can move the tents from the
	# player's field army to the standard that absorbs it (DR-20261112-07) —
	# name it, or the dossier the crown was watching silently loses them.
	if target.field_hospital:
		line += " — the field hospital train rides with it"
	play.hud.toast(line)
