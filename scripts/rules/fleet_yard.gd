class_name FleetYard
extends RefCounted
## The naval yard: launch a hull, or break one up (wiki: ships-and-naval
## § Ship build economy, § Ship muster and the breaker's yard; DR-20261109-01).
## Pure rules: validates the row against the crown's ledger, deducts treasury,
## materials and one peasant, and leaves marker work to the layer
## (REQ-P3-03). One gate for the panel and the order path (REQ-P2-03).

## A hard stop on the yard's one press: a slip that never leaves a row ready
## cannot spin, whatever a hand-built table holds (DR-20261118-08).
const BATCH_LIMIT: int = 64

## The reason every row carries away from the crown's capital port; the one press
## speaks the same words, so both read one gate (REQ-P2-03).
const NOT_AT_HOME: String = "Launch hulls at your capital port."


## The hull a crown is weighing, in the words THE CROWN'S NAVY prints for a hull
## she already floats: her own combat line (`NavalStrength.hull_line`, the
## aggregation formula's own figures) and the holds her class carries
## (wiki: ships-and-naval § Ship combat and cargo stats, § Ship build economy).
## A yard that named only the price made the biggest purchase in the game blind —
## a sloop and an indiaman read alike until the first battle (REQ-P5-06).
static func hull_line(type_id: String) -> String:
	var cargo: int = int(ShipStats.entry(type_id).get("cargo", 0))
	var holds: String = (
		"No holds — she fights in the line"
		if cargo <= 0
		else "%d hold%s for the world market" % [cargo, "" if cargo == 1 else "s"]
	)
	return "%s · %s" % [NavalStrength.hull_line(type_id), holds]


## One ledger row per catalog type, payable rows first so the yard leads with
## what can launch today. `at_home` is false when the crown has no capital port
## to launch from; every row then carries that reason.
static func rows(
	economy: PlayerEconomy, at_home: bool = true, flown: Array = []
) -> Array[Dictionary]:
	var out: Array[Dictionary] = _rows(economy, at_home, flown)
	# What the slip's one press would file, carried on the reading itself: the
	# drawer prints the sum under its rows without holding an economy, and the
	# sum is the same walk the press files (DR-20261118-11).
	var plan: Dictionary = batch_plan(economy, at_home, flown)
	for row: Dictionary in out:
		row["batch"] = plan
	return out


## The slip's own rows, before the one press's sum is laid over them.
static func _rows(
	economy: PlayerEconomy, at_home: bool, flown: Array
) -> Array[Dictionary]:
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
				type_id, economy.treasury, economy.stockpile, peasants,
				economy.tech_unlocked, flown
			)
		else:
			reason = NOT_AT_HOME
		var row: Dictionary = {
			"type_id": type_id,
			"name": ShipStats.display_name(type_id),
			"cost_text": ShipEconomy.cost_text(type_id),
			# What she is, not only what she costs: the same line the navy sheet
			# prints for a hull already afloat (REQ-P5-06).
			"line": hull_line(type_id),
			"ok": reason.is_empty(),
			"reason": reason,
			"pending": economy.recruits.pending(RecruitQueue.KIND_SHIP, type_id),
		}
		# What the yard's one press would lay down: a payable row no waiting order
		# already claims. The press's count and the hulls it files read this one
		# flag, so a hull cannot be ordered twice by a single press (REQ-P5-04;
		# DR-20261118-08).
		row["batch_ready"] = bool(row["ok"]) and int(row["pending"]) == 0
		if row["ok"]:
			open_rows.append(row)
		else:
			locked.append(row)
	open_rows.append_array(locked)
	return open_rows


## The slip's one press, read before it is pressed: every ready hull in the yard's
## order, each priced against the ledger the orders before it leave, stopping at
## the first refusal — the walk `queue_all` files, with nothing written
## (DR-20261118-11). Returns `RaiseBatchSum.plan`'s record: count, filed, ducats,
## materials, workers, the purse and the reason the next hull waits.
static func batch_plan(
	economy: PlayerEconomy, at_home: bool = true, flown: Array = []
) -> Dictionary:
	if economy == null:
		return RaiseBatchSum.blank()
	var craft: Array = flown
	return RaiseBatchSum.plan(
		_rows(economy, at_home, craft),
		economy.treasury,
		economy.stockpile,
		func(type_id: String) -> int: return ShipEconomy.treasury_cost(type_id),
		func(type_id: String) -> Dictionary: return ShipEconomy.build_inputs(type_id),
		func(type_id: String, treasury: int, stock: Dictionary, filed: int) -> String:
			return ShipEconomy.blocked_reason(
				type_id,
				treasury,
				stock,
				maxi(economy.available_peasants() - filed, 0),
				economy.tech_unlocked,
				craft
			)
	)


## The yard's batch: one hull per type the slip prints, in its order, each
## validated against the ledger the orders before it leave — the queue reserves
## the peasant and this walk draws the cash and the materials down, so a press
## can never file a hull the turn's Build/work would refuse (REQ-P2-03,
## REQ-P5-04; DR-20261118-08). The walk stops at the first refusal, because that
## refusal is the rules' answer for the realm. Returns {filed, total, ducats,
## materials, workers, refusal}, the spend included so the receipt names it.
static func queue_all(
	economy: PlayerEconomy,
	at_home: bool,
	types: Array[String],
	flown: Array = []
) -> Dictionary:
	var result: Dictionary = {
		"filed": 0, "total": types.size(), "refusal": "",
		"ducats": 0, "materials": {}, "workers": 0,
	}
	if economy == null:
		result["refusal"] = "There is no court to pay for her."
		return result
	if not at_home:
		result["refusal"] = NOT_AT_HOME
		return result
	var treasury: int = economy.treasury
	var stock: Dictionary = economy.stockpile.duplicate()
	for type_id: String in types:
		if int(result["filed"]) >= BATCH_LIMIT:
			break
		var reason: String = ShipEconomy.blocked_reason(
			type_id, treasury, stock, economy.available_peasants(),
			economy.tech_unlocked, flown
		)
		if not reason.is_empty():
			result["refusal"] = reason
			break
		economy.queue_build(RecruitQueue.KIND_SHIP, type_id)
		var cost: int = ShipEconomy.treasury_cost(type_id)
		treasury -= cost
		result["ducats"] = int(result["ducats"]) + cost
		result["workers"] = int(result["workers"]) + 1
		var inputs: Dictionary = ShipEconomy.build_inputs(type_id)
		var spent: Dictionary = result["materials"]
		for commodity: Variant in inputs.keys():
			var id: String = String(commodity)
			stock[id] = int(stock.get(id, 0)) - int(inputs[commodity])
			spent[id] = int(spent.get(id, 0)) + int(inputs[commodity])
		result["filed"] = int(result["filed"]) + 1
	return result


## The types the yard's one press would lay down: every row the crown can pay
## for now that no order already claims. The same flag the rows carry, so the
## press's count and the hulls it files can never disagree (REQ-P5-04).
static func batch_types(
	economy: PlayerEconomy, at_home: bool = true, flown: Array = []
) -> Array[String]:
	var types: Array[String] = []
	for row: Dictionary in rows(economy, at_home, flown):
		if bool(row.get("batch_ready", false)):
			types.append(String(row["type_id"]))
	return types


## Pays for one hull and appends it to the fleet. `hull_id` is the caller's
## stable instance id (wiki: ships-and-naval § Ship instances).
static func launch(
	economy: PlayerEconomy,
	fleet: FleetState,
	type_id: String,
	hull_id: String,
	flown: Array = []
) -> Dictionary:
	if economy == null or fleet == null:
		return _deny("There is no fleet to launch into.")
	var reason: String = ShipEconomy.blocked_reason(
		type_id,
		economy.treasury,
		economy.stockpile,
		economy.available_peasants(),
		economy.tech_unlocked,
		flown
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
	return {
		"ok": true,
		"reason": "",
		"type": type_id,
		"hull": hull_id,
		"name": ShipNames.of(fleet, hull_id),
		"retired": false,
	}


## Breaks up one hull: no treasury or material refund, one peasant returns.
## An emptied squadron retires (wiki: § Ship muster and the breaker's yard).
static func scrap(economy: PlayerEconomy, fleet: FleetState, hull_id: String) -> Dictionary:
	if economy == null or fleet == null:
		return _deny("There is no fleet to break up.")
	if not fleet.hulls.has(hull_id):
		return _deny("That hull does not sail in this fleet.")
	var type_id: String = fleet.type_of(hull_id)
	var hull_name: String = ShipNames.of(fleet, hull_id)
	fleet.remove_hull(hull_id)
	economy.workers.add(WorkerPool.Tier.PEASANT, ShipEconomy.WORKER_COST)
	return {
		"ok": true,
		"reason": "",
		"type": type_id,
		"hull": hull_id,
		"name": hull_name,
		"retired": not fleet.is_afloat(),
	}


static func _deny(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"type": "",
		"hull": "",
		"name": "",
		"retired": false,
	}
