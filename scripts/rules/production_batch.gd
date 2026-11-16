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
## Returns {"plan": {recipe_id: units}, "runs": int, "rows": int, "skipped": int}.
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
	if economy == null:
		return {"plan": plan, "runs": runs, "rows": rows, "skipped": skipped}
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
	return {"plan": plan, "runs": runs, "rows": rows, "skipped": skipped}


## The one line the press leaves on the court's lane: what it set, and — when it
## set nothing — why the page offered no step (REQ-P5-05).
static func receipt(runs: int) -> String:
	if runs <= 0:
		return "No ready row to set — every row is at its ceiling or waits on a hand or a town."
	return "Set %d run%s — every ready row in this view is ordered." % [
		runs, "" if runs == 1 else "s"
	]


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
