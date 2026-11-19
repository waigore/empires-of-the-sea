class_name ProductionPhase
extends RefCounted
## One Production phase: reserved claims, per-row allowance, and the plan that
## spends inputs and idle labour (wiki: stockpiles-and-production § Production
## flow; production-recipes § Turns per unit, § Workshop queue).
##
## The recipe catalogue owns the rows and their gates; this owner runs the phase
## against them and the workshop batches already paid for. Pure rules: every
## input is data, so a headless test drives exactly the pass the turn does
## (REQ-P2-03, REQ-P3-01, REQ-P3-03).


## Inputs the assigned runs claim from the stockpile, commodity -> units. The
## ledger caps an offer at what production leaves behind, exactly as the AI
## planners already reserve (wiki: world-market § Trade orders — validation
## rule 7; REQ-P2-03 one rule for player and AI).
static func reserved_inputs(assignments: Array) -> Dictionary:
	var reserved: Dictionary = {}
	for raw: Variant in assignments:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var assignment: Dictionary = raw
		var recipe_id: String = String(assignment.get("recipe", ""))
		var units: int = int(assignment.get("units", 0))
		if units <= 0 or not ProductionRecipes.known(recipe_id):
			continue
		var needed: Dictionary = ProductionRecipes.inputs(recipe_id)
		for commodity: Variant in needed.keys():
			var id: String = String(commodity)
			reserved[id] = int(reserved.get(id, 0)) + int(needed[commodity]) * units
	return reserved


## Labour the runs in these assignments claim: units × the recipe's labour per
## run. The ledger's per-row ceiling subtracts the other rows' share of it, so a
## court reading one row sees what is left for that row (REQ-P2-03).
static func claimed_labour(assignments: Array) -> int:
	var total: int = 0
	for raw: Variant in assignments:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var assignment: Dictionary = raw
		total += (
			int(assignment.get("units", 0))
			* ProductionRecipes.labour(String(assignment.get("recipe", "")))
		)
	return total


## Units one row may still be set to for the coming Production phase: whole runs
## its inputs and labour could start once the court's other rows have claimed
## theirs. `stockpile` is the post-Consumption store and `labour_points` the idle
## labour the projection reports, so the ledger never offers what the phase
## would refuse (wiki: stockpiles-and-production § Production flow; REQ-P2-03).
static func allowance(
	recipe_id: String,
	stockpile: Dictionary,
	labour_points: int,
	assignments: Array,
	workers: WorkerPool = null,
	wip: Dictionary = {},
	town_level: int = 0
) -> int:
	if not ProductionRecipes.known(recipe_id) or not ProductionRecipes.tier_met(
		recipe_id, workers
	):
		return 0
	if not ProductionRecipes.town_met(recipe_id, town_level):
		return 0
	var others: Array = []
	for raw: Variant in assignments:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var other_id: String = String((raw as Dictionary).get("recipe", ""))
		if other_id == recipe_id:
			continue
		# A gated row never runs, so it claims nothing from the rows that do.
		if (
			not ProductionRecipes.tier_met(other_id, workers)
			or not ProductionRecipes.town_met(other_id, town_level)
		):
			continue
		others.append(raw)
	var left: Dictionary = stockpile.duplicate()
	var claimed: Dictionary = reserved_inputs(others)
	for commodity: Variant in claimed.keys():
		var id: String = String(commodity)
		left[id] = maxi(int(left.get(id, 0)) - int(claimed[commodity]), 0)
	var runs: int = max_runs(
		recipe_id, left, maxi(labour_points - claimed_labour(others), 0)
	)
	# A slow row's bench holds three pieces: the fourth run waits for a landing,
	# so the stepper stops where the phase would (wiki: production-recipes
	# § Workshop queue; DR-20261114-12).
	if ProductionRecipes.turns(recipe_id) > 1:
		runs = mini(
			runs,
			ProductionWorkshop.room(wip, recipe_id, ProductionRecipes.turns(recipe_id))
		)
	return runs


## Whole runs a recipe can complete with the given inputs and labour budget.
static func max_runs(recipe_id: String, stockpile: Dictionary, labour_points: int) -> int:
	if not ProductionRecipes.known(recipe_id):
		return 0
	var per_run_labour: int = ProductionRecipes.labour(recipe_id)
	if per_run_labour <= 0:
		return 0
	var runs: int = labour_points / per_run_labour
	var needed: Dictionary = ProductionRecipes.inputs(recipe_id)
	for commodity: Variant in needed.keys():
		var need: int = int(needed[commodity])
		if need <= 0:
			continue
		var have: int = int(stockpile.get(String(commodity), 0))
		runs = mini(runs, have / need)
	if runs < 0:
		return 0
	return runs


## Executes assignments in order. Each assignment is {"recipe": id, "units": n};
## units are output units, so a recipe needing 2 labour per unit spends 2 labour
## per run. Returns runs, produced and consumed so the turn log can be inspected.
##
## `wip` is the workshop carried from the last Production phase (recipe id ->
## array of {"units", "turns_left"}). Batches already in the workshop finish
## first; their inputs and labour were paid when they started, so they cost this
## phase nothing. Runs started now pay immediately, and a multi-turn row joins
## the workshop with one phase already served. A multi-turn batch then lands one
## unit a phase and keeps the rest for the phases after it, so a batch of three
## started in turn 1 delivers its last unit in turn 4 (DR-20261113-02). The
## returned "wip" replaces the caller's.
static func plan(
	assignments: Array[Dictionary],
	stockpile: Dictionary,
	labour_points: int,
	tech_unlocked: Dictionary,
	wip: Dictionary = {},
	workers: WorkerPool = null,
	town_level: int = 0
) -> Dictionary:
	var remaining_labour: int = maxi(labour_points, 0)
	var runs_by_recipe: Dictionary = {}
	var produced: Dictionary = {}
	var consumed: Dictionary = {}
	var started_units: Dictionary = {}
	var completed: Dictionary = {}
	var next_wip: Dictionary = {}
	for raw_recipe: Variant in wip.keys():
		var recipe_id: String = String(raw_recipe)
		if not ProductionRecipes.known(recipe_id):
			continue
		var served: Dictionary = ProductionWorkshop.serve(
			wip, recipe_id, ProductionRecipes.turns(recipe_id)
		)
		var landing_units: int = int(served["landed"])
		if landing_units > 0:
			var landed_id: String = ProductionRecipes.output(recipe_id)
			var landed: int = landing_units * ProductionRecipes.OUTPUT_PER_RUN
			stockpile[landed_id] = int(stockpile.get(landed_id, 0)) + landed
			produced[landed_id] = int(produced.get(landed_id, 0)) + landed
			completed[recipe_id] = int(completed.get(recipe_id, 0)) + landing_units
		var kept: Array[Dictionary] = served["kept"]
		if not kept.is_empty():
			next_wip[recipe_id] = kept
	for assignment: Dictionary in assignments:
		var recipe_id: String = String(assignment.get("recipe", ""))
		if not ProductionRecipes.available_for(
			recipe_id, tech_unlocked, workers, town_level
		):
			continue
		var desired: int = int(assignment.get("units", 0))
		if desired <= 0:
			continue
		var turns: int = ProductionRecipes.turns(recipe_id)
		var affordable: int = mini(
			desired, max_runs(recipe_id, stockpile, remaining_labour)
		)
		# A slow row's bench holds three pieces; a fourth waits for a landing
		# (wiki: production-recipes § Workshop queue; DR-20261114-12). The room
		# is read from the workshop this phase will leave, so two assignments of
		# one row cannot both fill the same bench.
		if turns > 1:
			affordable = mini(affordable, ProductionWorkshop.open_room(next_wip, recipe_id))
		if affordable <= 0:
			continue
		var needed: Dictionary = ProductionRecipes.inputs(recipe_id)
		for commodity: Variant in needed.keys():
			var id: String = String(commodity)
			var amount: int = int(needed[commodity]) * affordable
			stockpile[id] = maxi(int(stockpile.get(id, 0)) - amount, 0)
			consumed[id] = int(consumed.get(id, 0)) + amount
		runs_by_recipe[recipe_id] = int(runs_by_recipe.get(recipe_id, 0)) + affordable
		started_units[recipe_id] = int(started_units.get(recipe_id, 0)) + affordable
		remaining_labour -= affordable * ProductionRecipes.labour(recipe_id)
		if turns > 1:
			var batches: Array = next_wip.get(recipe_id, [])
			batches.append({"units": affordable, "turns_left": turns - 1})
			next_wip[recipe_id] = batches
			continue
		var out_id: String = ProductionRecipes.output(recipe_id)
		var out_amount: int = affordable * ProductionRecipes.OUTPUT_PER_RUN
		stockpile[out_id] = int(stockpile.get(out_id, 0)) + out_amount
		produced[out_id] = int(produced.get(out_id, 0)) + out_amount
	return {
		"runs": runs_by_recipe,
		"started": started_units,
		"completed": completed,
		"produced": produced,
		"consumed": consumed,
		"wip": next_wip,
		"labour_used": maxi(labour_points, 0) - remaining_labour,
	}
