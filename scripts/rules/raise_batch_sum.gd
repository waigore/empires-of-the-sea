class_name RaiseBatchSum
extends RefCounted
## What a raise sheet's one press costs, in one hand: how many rows the walk
## would file, the purse and the materials they take, and the reason the next
## one waits (wiki: ships-and-naval § Ship muster, military-armies § Recruitment;
## DR-20261118-11). The yards filed a whole line on a count alone, so a crown
## learned the purse's answer after it signed — the opening slip spends 19,500
## of 20,000 ducats.
##
## The walk is the batch's own: every row the yard flags `batch_ready`, in the
## yard's order, each priced against the ledger the orders before it leave, and
## it stops at the first refusal the rules give. The sheet reads it with `plan`
## and the press signs it with `file` — one loop, so the price a crown reads and
## the orders it receives can never drift (REQ-P2-03, REQ-P5-04). The yard still
## owns its own gate, its own price and its own order (REQ-P3-03).
##
## Pure projection over integers and catalogs, no nodes: the walk itself writes
## nothing — the yard's own `queue` lays down the order it keeps (REQ-P3-03).


## A hard stop on the press: a yard that never leaves a row unready cannot spin,
## whatever a hand-built table holds (DR-20261118-08).
const BATCH_LIMIT: int = 64


## A plan with nothing in it: what a yard with no court to pay reads, so a sheet
## never has to guard the shape itself.
static func blank() -> Dictionary:
	return {
		"count": 0,
		"filed": 0,
		"ducats": 0,
		"materials": {},
		"workers": 0,
		"purse": 0,
		"purse_after": 0,
		"refusal": "",
	}


## The plan a yard's one press would file. `price` returns a type's ducats,
## `inputs` its materials and `gate` the reason the rules would refuse it, read
## as `(type_id, purse, stock, filed)` — the ledger the orders before this one
## leave, and how many of them the press has already filed. All three are the
## yard's own readings, so the sum a sheet prints and the orders a press files
## can never disagree (REQ-P2-03).
static func plan(
	rows: Array[Dictionary],
	purse: int,
	stock: Dictionary,
	price: Callable,
	inputs: Callable,
	gate: Callable
) -> Dictionary:
	return _walk(rows, purse, stock, price, inputs, gate)


## The orders a yard's one press files: the same walk `plan` reads, with `queue`
## laid down for every step it keeps (the type id is the argument). The receipt
## carries the spend the sheet priced, so a press that files the line a crown
## read pays exactly that line (REQ-P2-03, REQ-P5-04; DR-20261118-08).
static func file(
	types: Array[String],
	purse: int,
	stock: Dictionary,
	price: Callable,
	inputs: Callable,
	gate: Callable,
	queue: Callable
) -> Dictionary:
	var rows: Array[Dictionary] = []
	for type_id: String in types:
		rows.append({"type_id": type_id, "batch_ready": true})
	return _walk(rows, purse, stock, price, inputs, gate, queue)


## A receipt with nothing filed, for a yard whose own guard says it may not
## order at all (no court, no Home Army, no capital port). The yard names the
## words; this keeps the shape a press reads.
static func blocked(total: int, reason: String) -> Dictionary:
	var receipt: Dictionary = blank()
	receipt["count"] = total
	receipt["total"] = total
	receipt["refusal"] = reason
	return receipt


## The one walk behind both readings: every row the yard flags `batch_ready`, in
## the yard's order, each priced against the ledger the orders before it leave,
## stopping at the first refusal the rules give. A `queue` callable turns the
## read into the press that writes what it priced; without one the walk only
## reads, and the caller's stores are left untouched.
static func _walk(
	rows: Array[Dictionary],
	purse: int,
	stock: Dictionary,
	price: Callable,
	inputs: Callable,
	gate: Callable,
	queue: Callable = Callable()
) -> Dictionary:
	var plan: Dictionary = {
		"count": 0,
		"filed": 0,
		"ducats": 0,
		"materials": {},
		"workers": 0,
		"purse": purse,
		"purse_after": purse,
		"refusal": "",
	}
	var gold: int = purse
	var left: Dictionary = stock.duplicate()
	for row: Dictionary in rows:
		if not bool(row.get("batch_ready", false)):
			continue
		if queue.is_valid() and int(plan["filed"]) >= BATCH_LIMIT:
			break
		plan["count"] = int(plan["count"]) + 1
		if not String(plan["refusal"]).is_empty():
			continue
		var type_id: String = String(row.get("type_id", ""))
		var reason: String = String(
			gate.call(type_id, gold, left, maxi(int(plan["filed"]), 0))
		)
		if not reason.is_empty():
			plan["refusal"] = reason
			continue
		var cost: int = int(price.call(type_id))
		var needs: Dictionary = inputs.call(type_id)
		# The order is laid down before the next gate reads the pool: a recruit
		# reserves her peasant, so the press can never file one hand twice
		# (DR-20261118-07).
		if queue.is_valid():
			queue.call(type_id)
		gold -= cost
		plan["ducats"] = int(plan["ducats"]) + cost
		plan["workers"] = int(plan["workers"]) + 1
		var materials: Dictionary = plan["materials"]
		for commodity: Variant in needs.keys():
			var id: String = String(commodity)
			left[id] = int(left.get(id, 0)) - int(needs[commodity])
			materials[id] = int(materials.get(id, 0)) + int(needs[commodity])
		plan["filed"] = int(plan["filed"]) + 1
	plan["purse_after"] = gold
	return plan


## How many of the yard's ready rows the line carries — the count the press's
## armed face names — or `-1` when the plan was never read (a suite's fixture, or
## a yard with no court behind it), so the press keeps its published face
## (DR-20261118-21).
static func carries(plan: Dictionary) -> int:
	if int(plan.get("count", 0)) <= 0:
		return -1
	return int(plan.get("filed", 0))


## "19,500 ducats · 4 Lumber · 3 Fabric · 3 workers": what a line of orders
## costs, in the rows' own catalog labels and the purse's own grouping.
static func paid(reading: Dictionary) -> String:
	return MoneyText.cost_line(
		int(reading.get("ducats", 0)),
		reading.get("materials", {}),
		int(reading.get("workers", 0))
	)


## The line under the press, before it is pressed: what the line costs and the
## purse it leaves — or, when the walk stops short, how many of the ready rows
## wait and why. `""` when the press has nothing to file. A yard whose walk
## carries nothing prints only the gate's own refusal, which is the sentence the
## disabled press above it sends the reader to (DR-20261118-21).
static func sheet_line(reading: Dictionary) -> String:
	var filed: int = int(reading.get("filed", 0))
	if filed <= 0:
		var total: int = int(reading.get("count", 0))
		var stop: String = String(reading.get("refusal", ""))
		if total <= 0 or stop.is_empty():
			return ""
		var why: String = stop if stop.ends_with(".") else stop + "."
		return "Nothing in this yard can be ordered — %d wait%s: %s" % [
			total, "" if total != 1 else "s", why,
		]
	var costs: String = paid(reading)
	var refusal: String = String(reading.get("refusal", ""))
	if refusal.is_empty():
		return "%s — the purse keeps %s of %s." % [
			costs,
			MoneyText.thousands(int(reading.get("purse_after", 0))),
			MoneyText.thousands(int(reading.get("purse", 0))),
		]
	var waiting: int = int(reading.get("count", 0)) - filed
	return "%s — %d of %d wait%s: %s." % [
		costs,
		waiting,
		int(reading.get("count", 0)),
		"" if waiting != 1 else "s",
		refusal,
	]