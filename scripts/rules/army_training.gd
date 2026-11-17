class_name ArmyTraining
extends RefCounted
## BuildUnitOrder for land regiments (wiki: military-units § Training Costs,
## military-generals § Regiment Economy). Rules only: validates the row against
## the player's ledger, deducts cash, materials and one worker, and appends the
## regiment to the Home Army. The view mints the stable unit id and animates.
## New regiments always join the Home Army at the capital (wiki: military-armies).


## A hard stop on the drill yard's one press: a sheet that never leaves a row
## ready cannot spin, whatever a hand-built table holds (DR-20261118-07).
const BATCH_LIMIT: int = 64


## The faction's Home Army among the given armies, or null. The list is read as
## the layer's generic roster, so a caller holding an untyped `Array` needs no
## copy of this scan.
static func home_army(armies: Array, owner: int) -> ArmyState:
	for raw: Variant in armies:
		var army: ArmyState = raw
		if army != null and army.owner == owner and army.is_home_army():
			return army
	return null


## The Home Army always stands in the court's seat (wiki: military-armies
## § Home Army). A reassignment moves the court when its old capital falls, so
## the guard goes with it; a court whose Home Army died with the old seat reforms
## one at the new seat, because the standard is never deleted. Without this the
## Home Army is stranded off the seat and no muster can ever land again
## (wiki: capital-and-connectivity § Capital loss and reassignment; issue #474).
## Returns {army, minted}; `army` is null when `seat` is no province.
static func settle_seat(
	armies: Array[ArmyState], owner: int, seat: int, next_army_id: int
) -> Dictionary:
	if seat < 0:
		return {"army": null, "minted": false}
	var home: ArmyState = home_army(armies, owner)
	if home == null:
		home = ArmyState.muster(next_army_id, owner, seat, true, [])
		armies.append(home)
		return {"army": home, "minted": true}
	home.province = seat
	return {"army": home, "minted": false}


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


## The drill yard's batch: one order per type the view prints, in its order,
## each validated against the ledger the orders before it leave — the queue
## reserves the peasant and this walk reserves the cash and the materials, so a
## press can never file a standard the turn's Build/work would refuse (REQ-P2-03,
## REQ-P5-04; DR-20261118-07). The walk stops at the first refusal, because that
## refusal is the rules' answer for the realm. Returns {filed, total, ducats,
## materials, workers, refusal}, the spend included so the receipt names it.
static func queue_all(
	economy: PlayerEconomy,
	armies: Array[ArmyState],
	owner: int,
	types: Array[String]
) -> Dictionary:
	var result: Dictionary = {
		"filed": 0, "total": types.size(), "refusal": "",
		"ducats": 0, "materials": {}, "workers": 0,
	}
	if economy == null or home_army(armies, owner) == null:
		result["refusal"] = "Regiments muster only in the Home Army."
		return result
	var treasury: int = economy.treasury
	var stock: Dictionary = economy.stockpile.duplicate()
	for type_id: String in types:
		if int(result["filed"]) >= BATCH_LIMIT:
			break
		var reason: String = RegimentEconomy.blocked_reason(
			type_id, treasury, stock, economy.available_peasants(), economy.tech_unlocked
		)
		if not reason.is_empty():
			result["refusal"] = reason
			break
		economy.queue_build(RecruitQueue.KIND_REGIMENT, type_id)
		var cost: int = RegimentCatalog.treasury_cost(type_id)
		treasury -= cost
		result["ducats"] = int(result["ducats"]) + cost
		result["workers"] = int(result["workers"]) + 1
		var inputs: Dictionary = RegimentEconomy.training_inputs(type_id)
		var spent: Dictionary = result["materials"]
		for commodity: Variant in inputs.keys():
			var id: String = String(commodity)
			stock[id] = int(stock.get(id, 0)) - int(inputs[commodity])
			spent[id] = int(spent.get(id, 0)) + int(inputs[commodity])
		result["filed"] = int(result["filed"]) + 1
	return result


## The drill yard's one press, read before it is pressed: every ready standard in
## the yard's order, each priced against the ledger the orders before it leave,
## stopping at the first refusal — the walk `queue_all` files, with nothing
## written (DR-20261118-10).
static func batch_plan(economy: PlayerEconomy) -> Dictionary:
	if economy == null:
		return RaiseBatchSum.blank()
	return RaiseBatchSum.plan(
		_rows(economy),
		economy.treasury,
		economy.stockpile,
		func(type_id: String) -> int: return RegimentCatalog.treasury_cost(type_id),
		func(type_id: String) -> Dictionary: return RegimentEconomy.training_inputs(type_id),
		func(type_id: String, treasury: int, stock: Dictionary, filed: int) -> String:
			return RegimentEconomy.blocked_reason(
				type_id,
				treasury,
				stock,
				maxi(economy.available_peasants() - filed, 0),
				economy.tech_unlocked
			)
	)


## The types the drill yard's one press would file: every row the crown can pay
## for now that no order already claims. The same flag the rows carry, so the
## press's count and the orders it files can never disagree (REQ-P5-04).
static func batch_types(economy: PlayerEconomy) -> Array[String]:
	var types: Array[String] = []
	for row: Dictionary in rows(economy):
		if bool(row.get("batch_ready", false)):
			types.append(String(row["type_id"]))
	return types


## One ledger row per catalog type, tech-gated and priced for the muster panel.
## Buildable rows come first so the drill yard leads with what can march today.
## Every row carries the one press's plan (`batch`), so the sheet prints the sum
## it would file without holding an economy (DR-20261118-10).
static func rows(economy: PlayerEconomy) -> Array[Dictionary]:
	var out: Array[Dictionary] = _rows(economy)
	var plan: Dictionary = batch_plan(economy)
	for row: Dictionary in out:
		row["batch"] = plan
	return out


## The yard's own rows, before the one press's sum is laid over them.
static func _rows(economy: PlayerEconomy) -> Array[Dictionary]:
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
			# What it is, not only what it costs: the same line the roster prints
			# for a regiment already at the colours (REQ-P5-06).
			"line": RegimentCatalog.muster_line(type_id),
			"ok": reason.is_empty(),
			"reason": reason,
			"pending": economy.recruits.pending(RecruitQueue.KIND_REGIMENT, type_id),
		}
		# What the yard's one press would file: a payable row no waiting order
		# already claims. The press's count and the orders it files read this one
		# flag, so a standard cannot be ordered twice by a single press
		# (REQ-P5-04; DR-20261118-07).
		row["batch_ready"] = bool(row["ok"]) and int(row["pending"]) == 0
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
