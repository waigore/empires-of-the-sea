class_name ProductionBatch
extends RefCounted
## The one press the PRODUCTION tab adds: one run on every ready row, in the
## page's own order, each capped by the allowance the rules report once the rows
## before it are set (REQ-P5-04; DR-20261116-08).
##
## The walk is the same arithmetic a row's "+" is capped by, so the press can
## never set a run the row's own ceiling would refuse, and it never fills a row
## to its ceiling: one press files one step per row, exactly as the raise sheets'
## press files one step per row (REQ-P2-03, REQ-P5-04).
##
## Pure: the economy, the projection the page prints and the page's order in, a
## plan out. No nodes, no order of its own (REQ-P3-03).

## A hard stop on the walk, so a hand-built page can never spin.
const BATCH_LIMIT: int = 64


## Units a row may still be set to, read from the projection the page prints:
## the post-Consumption store and the idle labour the phase will see, less the
## other rows' claims and the pieces already on the bench. The rules own the
## arithmetic; this only picks which state the phase will see (REQ-P2-03).
static func allowance(
	economy: PlayerEconomy,
	recipe_id: String,
	town_level: int,
	stock: Dictionary,
	labour: int,
	assignments: Array
) -> int:
	if economy == null:
		return 0
	return ProductionRecipes.allowance(
		recipe_id,
		stock,
		labour,
		assignments,
		economy.workers,
		economy.production_wip,
		town_level
	)


## The store and the idle labour the phase will see, from the projection the page
## prints; a page filled without one reads the live store and pool, so the ceiling
## still answers (REQ-P2-03).
static func budget(economy: PlayerEconomy, report: Dictionary) -> Dictionary:
	if economy == null:
		return {"stock": {}, "labour": 0}
	var stock: Dictionary = report.get("after_consumption", economy.stockpile) as Dictionary
	var labour: int = economy.workers.labour()
	if not report.is_empty():
		labour = int((report.get("consumption", {}) as Dictionary).get("idle_labour", 0))
	return {"stock": stock, "labour": labour}


## One run on every ready row, in the page's order. `order` is the recipe ids as
## the page prints them; `assignments` is the court's current set, which the walk
## updates as it goes so a later row reads the claims the earlier ones made.
## Returns {"plan": {recipe_id: units}, "runs": int, "rows": int, "skipped": int,
## "labour": int, "labour_budget": int, "inputs": {commodity: units}} — the last
## three are what the walk would claim of the phase's idle labour and store, so
## the sheet can price the line before the crown signs (DR-20261118-24).
static func plan(
	order: Array,
	economy: PlayerEconomy,
	town_level: int,
	stock: Dictionary,
	labour: int,
	assignments: Array
) -> Dictionary:
	var plan: Dictionary = {}
	var runs: int = 0
	var rows: int = 0
	var skipped: int = 0
	var claimed: int = 0
	var inputs: Dictionary = {}
	if economy == null:
		return blank()
	var working: Array = assignments.duplicate(true)
	for raw: Variant in order:
		if runs >= BATCH_LIMIT:
			break
		var recipe_id: String = String(raw)
		var units: int = _units(working, recipe_id)
		var limit: int = allowance(
			economy, recipe_id, town_level, stock, labour, working
		)
		# A row at its ceiling, or one whose hand or town's works is missing,
		# has no step to file: the press names only what it would set.
		if limit <= units:
			skipped += 1
			continue
		_assign(working, recipe_id, units + 1)
		plan[recipe_id] = units + 1
		runs += 1
		rows += 1
		claimed += ProductionRecipes.labour(recipe_id)
		var need: Dictionary = ProductionRecipes.inputs(recipe_id)
		for commodity: Variant in need.keys():
			var id: String = String(commodity)
			inputs[id] = int(inputs.get(id, 0)) + int(need[commodity])
	return {
		"plan": plan, "runs": runs, "rows": rows, "skipped": skipped,
		"labour": claimed, "labour_budget": maxi(labour, 0), "inputs": inputs,
	}


## The one line the press leaves on the court's lane: what it set, and — when it
## set nothing — why the page offered no step (REQ-P5-05).
static func receipt(runs: int) -> String:
	if runs <= 0:
		return "No ready row to set — every row is at its ceiling or waits on a hand or a town."
	return "Set %d run%s — every ready row in this view is ordered." % [
		runs, "" if runs == 1 else "s"
	]


## "3 runs · 6 labour · 2 Wool · 2 Timber · 1 Iron": what the walk would claim, in
## the catalogue's own labels and order, or "" when it would set nothing. The
## labour is the idle labour the runs take; the materials are the store they spend.
static func spend_line(reading: Dictionary) -> String:
	var runs: int = int(reading.get("runs", 0))
	if runs <= 0:
		return ""
	var parts: PackedStringArray = ["%d run%s" % [runs, "" if runs == 1 else "s"]]
	var labour: int = int(reading.get("labour", 0))
	if labour > 0:
		parts.append("%d labour" % labour)
	var inputs: Dictionary = reading.get("inputs", {}) as Dictionary
	for id: String in CommodityCatalog.all_ids():
		if not inputs.has(id):
			continue
		parts.append("%d %s" % [int(inputs[id]), CommodityCatalog.label(id)])
	return " · ".join(parts)


## The line under the press, before it is pressed: what the walk would set and
## claim, what the phase keeps of its idle labour, and how many ready rows it
## leaves out — so a crown never learns the price of its runs after it signs
## (REQ-P5-06; DR-20261118-24). "" when the press has nothing to file.
static func sheet_line(reading: Dictionary) -> String:
	var spend: String = spend_line(reading)
	if spend.is_empty():
		return ""
	var line: String = spend
	var budget: int = int(reading.get("labour_budget", 0))
	if budget > 0:
		var idle: int = maxi(budget - int(reading.get("labour", 0)), 0)
		line = "%s — the phase keeps %d of its %d idle labour." % [spend, idle, budget]
	var skipped: int = int(reading.get("skipped", 0))
	if skipped > 0:
		line += " %d row%s wait%s on a ceiling, a hand, a town's works or the labour and store left." % [
			skipped, "" if skipped == 1 else "s", "s" if skipped == 1 else "",
		]
	return line


## A plan with nothing in it: what a page with no court behind it reads, so the
## sheet never has to guard the shape itself.
static func blank() -> Dictionary:
	return {
		"plan": {}, "runs": 0, "rows": 0, "skipped": 0,
		"labour": 0, "labour_budget": 0, "inputs": {},
	}


## Units already set on a row in the working copy of the assignments.
static func _units(assignments: Array, recipe_id: String) -> int:
	for raw: Variant in assignments:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw
		if String(entry.get("recipe", "")) == recipe_id:
			return int(entry.get("units", 0))
	return 0


## Sets a row in the working copy, so the rows after it read the claim.
static func _assign(assignments: Array, recipe_id: String, units: int) -> void:
	for index in assignments.size():
		var entry: Variant = assignments[index]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if String((entry as Dictionary).get("recipe", "")) != recipe_id:
			continue
		assignments[index] = {"recipe": recipe_id, "units": units}
		return
	assignments.append({"recipe": recipe_id, "units": units})
