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


## The drill yard's one press: every ready row the yard prints, one standard
## each, in the yard's order — the same `BuildUnitOrder` a row's Muster press
## files, so the published price, the peasant and every gate stay in
## ArmyTraining (REQ-P2-03, REQ-P5-04; DR-20261118-07). The walk stops at the
## first refusal, because that refusal is the rules' answer for the realm, and
## the court reads one receipt instead of a lane of toasts (REQ-P5-05).
static func muster_all(play: PlaySession) -> void:
	if play.economy == null or play.economy.economy == null:
		return
	var economy: PlayerEconomy = play.economy.economy
	var types: Array[String] = ArmyTraining.batch_types(economy)
	if types.is_empty():
		return
	var result: Dictionary = ArmyTraining.queue_all(
		economy, play.army_layer.armies, play.player_faction, types
	)
	play.hud.toast(_batch_receipt(result))
	MapPlayArmies.show_panel(play, play.army_layer.selected_army)


## The one line the yard's batch leaves on the court's lane: what it ordered,
## what it paid and what the next standard waits on (REQ-P5-05; DR-20261118-11).
static func _batch_receipt(result: Dictionary) -> String:
	var filed: int = int(result.get("filed", 0))
	var total: int = int(result.get("total", 0))
	var refusal: String = String(result.get("refusal", ""))
	if filed == 0 and not refusal.is_empty():
		return refusal
	var spent: String = RaiseBatchSum.paid(result)
	var ordered: String = (
		"%d regiments are under orders for %s — they muster next turn" % [filed, spent]
		if filed != 1
		else "One regiment is under orders for %s — it musters next turn" % spent
	)
	if refusal.is_empty():
		return ordered
	return "%d of %d regiments are under orders for %s — the next waits: %s" % [
		filed, total, spent, refusal
	]


## Detaches a batch of regiments in one order (single detach and Detach all
## share this path, so repeated chores stay batched — REQ-P5-04).
static func detach(play: PlaySession, army: ArmyState, ids: Array[String]) -> void:
	var result: Dictionary = ArmyMusterOps.split(play.army_layer, army, ids)
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


## Dismisses a batch of regiments in one order (Dismiss and Dismiss all share
## this path, so a chore stays batched — REQ-P5-04; wiki: military-armies
## § Dismissing regiments). Each dismissed regiment returns one peasant and
## nothing else; an emptied field army retires at once, so the dossier closes
## with the standard it was reading.
static func dismiss(play: PlaySession, army: ArmyState, ids: Array[String]) -> void:
	if play.economy == null or play.economy.economy == null:
		return
	var result: Dictionary = ArmyMusterOps.dismiss(
		play.army_layer, army, ids, play.economy.economy
	)
	if not bool(result.get("ok", false)):
		play.hud.toast(String(result.get("reason", "The regiments stay.")))
		MapPlayArmies.show_panel(play, army)
		return
	play.hud.stats.set_armies(play.army_layer.regiment_count_all(play.player_faction))
	var count: int = int(result.get("count", 0))
	var peasants: int = int(result.get("peasants", 0))
	var line: String = (
		"%d regiments dismissed — %d peasants return to the pool"
		% [count, peasants]
		if count > 1
		else "%s dismissed — one peasant returns to the pool" % _dismissed_name(result)
	)
	if bool(result.get("retired", false)):
		# An embarked army that retires leaves the deck with the field: the
		# squadron no longer carries an army nobody can land (wiki:
		# ships-and-naval § Naval transport).
		if play.ship_layer != null:
			play.ship_layer.release_deck(army.id)
		play.hud.toast(line + " — the standard retires")
		play.hud.panels.hide_army()
		return
	play.hud.toast(line)
	MapPlayArmies.show_panel(play, army)


## The colours that left, by the name the crown gave them (a single dismissal
## names its regiment; a batch names the count instead).
static func _dismissed_name(result: Dictionary) -> String:
	var names: Array = result.get("names", [])
	if names.is_empty():
		return "The regiment"
	return String(names[0])


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
	var result: Dictionary = ArmyMusterOps.combine(play.army_layer, army)
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
