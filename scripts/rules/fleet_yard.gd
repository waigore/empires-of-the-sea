class_name FleetYard
extends RefCounted
## The naval yard: launch a hull, or break one up (wiki: ships-and-naval
## § Ship build economy, § Ship muster and the breaker's yard; DR-20261109-01).
## Pure rules: validates the row against the crown's ledger, deducts treasury,
## materials and one peasant, and leaves marker work to the layer
## (REQ-P3-03). One gate for the panel and the order path (REQ-P2-03).


## One ledger row per catalog type, payable rows first so the yard leads with
## what can launch today. `at_home` is false when the crown has no capital port
## to launch from; every row then carries that reason.
static func rows(economy: PlayerEconomy, at_home: bool = true) -> Array[Dictionary]:
	var open_rows: Array[Dictionary] = []
	var locked: Array[Dictionary] = []
	if economy == null:
		return open_rows
	var peasants: int = economy.available_peasants()
	var ids: Array = ShipEconomy.ENTRIES.keys()
	for raw: Variant in ids:
		var type_id: String = String(raw)
		var reason: String = ""
		if at_home:
			reason = ShipEconomy.blocked_reason(
				type_id, economy.treasury, economy.stockpile, peasants, economy.tech_unlocked
			)
		else:
			reason = "Launch hulls at your capital port."
		var row: Dictionary = {
			"type_id": type_id,
			"name": ShipStats.display_name(type_id),
			"cost_text": ShipEconomy.cost_text(type_id),
			"ok": reason.is_empty(),
			"reason": reason,
		}
		if row["ok"]:
			open_rows.append(row)
		else:
			locked.append(row)
	open_rows.append_array(locked)
	return open_rows


## Pays for one hull and appends it to the fleet. `hull_id` is the caller's
## stable instance id (wiki: ships-and-naval § Ship instances).
static func launch(
	economy: PlayerEconomy, fleet: FleetState, type_id: String, hull_id: String
) -> Dictionary:
	if economy == null or fleet == null:
		return _deny("There is no fleet to launch into.")
	var reason: String = ShipEconomy.blocked_reason(
		type_id,
		economy.treasury,
		economy.stockpile,
		economy.available_peasants(),
		economy.tech_unlocked
	)
	if not reason.is_empty():
		return _deny(reason)
	if hull_id.is_empty() or fleet.hulls.has(hull_id):
		return _deny("That hull already sails.")
	if not economy.workers.remove(WorkerPool.Tier.PEASANT):
		return _deny("Insufficient workers")
	economy.spend_treasury(ShipEconomy.treasury_cost(type_id))
	var inputs: Dictionary = ShipEconomy.build_inputs(type_id)
	for commodity: Variant in inputs.keys():
		economy.take(String(commodity), int(inputs[commodity]))
	fleet.add_hull(hull_id, type_id)
	return {"ok": true, "reason": "", "type": type_id, "hull": hull_id, "retired": false}


## Breaks up one hull: no treasury or material refund, one peasant returns.
## An emptied squadron retires (wiki: § Ship muster and the breaker's yard).
static func scrap(economy: PlayerEconomy, fleet: FleetState, hull_id: String) -> Dictionary:
	if economy == null or fleet == null:
		return _deny("There is no fleet to break up.")
	if not fleet.hulls.has(hull_id):
		return _deny("That hull does not sail in this fleet.")
	var type_id: String = fleet.type_of(hull_id)
	fleet.remove_hull(hull_id)
	economy.workers.add(WorkerPool.Tier.PEASANT, ShipEconomy.WORKER_COST)
	return {
		"ok": true,
		"reason": "",
		"type": type_id,
		"hull": hull_id,
		"retired": not fleet.is_afloat(),
	}


static func _deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "type": "", "hull": "", "retired": false}
