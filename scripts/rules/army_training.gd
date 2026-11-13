class_name ArmyTraining
extends RefCounted
## BuildUnitOrder for land regiments (wiki: military-units § Training Costs,
## military-generals § Regiment Economy). Rules only: validates the row against
## the player's ledger, deducts cash, materials and one worker, and appends the
## regiment to the Home Army. The view mints the stable unit id and animates.
## New regiments always join the Home Army at the capital (wiki: military-armies).


## The faction's Home Army among the given armies, or null.
static func home_army(armies: Array[ArmyState], owner: int) -> ArmyState:
	for army: ArmyState in armies:
		if army != null and army.owner == owner and army.is_home_army():
			return army
	return null


## Empty string when a muster order may be queued for this type; otherwise the
## first reason the rules refuse it. The register, the queue and the Build/work
## pass all read this one gate (REQ-P2-03).
static func muster_blocked_reason(
	economy: PlayerEconomy, armies: Array[ArmyState], owner: int, type_id: String
) -> String:
	if economy == null or home_army(armies, owner) == null:
		return "Regiments muster only in the Home Army."
	return RegimentEconomy.blocked_reason(
		type_id,
		economy.treasury,
		economy.stockpile,
		economy.available_peasants(),
		economy.tech_unlocked
	)


## One ledger row per catalog type, tech-gated and priced for the muster panel.
## Buildable rows come first so the drill yard leads with what can march today.
static func rows(economy: PlayerEconomy) -> Array[Dictionary]:
	var open_rows: Array[Dictionary] = []
	var locked: Array[Dictionary] = []
	if economy == null:
		return open_rows
	var peasants: int = economy.available_peasants()
	for type_id: String in RegimentCatalog.ids():
		var reason: String = RegimentEconomy.blocked_reason(
			type_id, economy.treasury, economy.stockpile, peasants, economy.tech_unlocked
		)
		var row: Dictionary = {
			"type_id": type_id,
			"name": RegimentCatalog.display_name(type_id),
			"era": RegimentCatalog.era(type_id),
			"cost_text": RegimentEconomy.cost_text(type_id),
			"ok": reason.is_empty(),
			"reason": reason,
			"pending": economy.recruits.pending(RecruitQueue.KIND_REGIMENT, type_id),
		}
		if row["ok"]:
			open_rows.append(row)
		else:
			locked.append(row)
	open_rows.append_array(locked)
	return open_rows


## Applies the training order. `unit_id` is the caller's stable regiment id.
static func recruit(
	economy: PlayerEconomy, army: ArmyState, type_id: String, unit_id: String
) -> Dictionary:
	if economy == null or army == null or not army.is_home_army():
		return _deny("Regiments muster only in the Home Army.")
	var reason: String = RegimentEconomy.blocked_reason(
		type_id,
		economy.treasury,
		economy.stockpile,
		economy.available_peasants(),
		economy.tech_unlocked
	)
	if not reason.is_empty():
		return _deny(reason)
	if army.regiments.has(unit_id):
		return _deny("That regiment already exists.")
	if not economy.workers.remove(WorkerPool.Tier.PEASANT):
		return _deny("Insufficient workers")
	economy.spend_treasury(RegimentCatalog.treasury_cost(type_id))
	var inputs: Dictionary = RegimentEconomy.training_inputs(type_id)
	for commodity: Variant in inputs.keys():
		economy.take(String(commodity), int(inputs[commodity]))
	army.add_regiment(unit_id, type_id)
	return {"ok": true, "reason": "", "type": type_id, "regiment": unit_id}


static func _deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "type": "", "regiment": ""}
