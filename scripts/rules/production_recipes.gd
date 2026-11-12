class_name ProductionRecipes
extends RefCounted
## Production recipe catalog (wiki: production-recipes). Each run consumes whole
## input units from the post-consumption stockpile and labour from idle workers,
## then adds its output. Runs are always whole; a recipe that cannot run once is
## skipped without partial consumption (REQ-P2-03).
##
## A run may occupy the workshop for more than one turn ("turns", default 1).
## Its inputs and labour are paid when the run starts; its output lands after
## that many Production phases, seat of the phase it started in counting as the
## first (wiki: production-recipes § Turns per unit; DR-20261112-11). The alloy
## rows combine two inputs, so they are the catalogue's two-turn work.

## Fabric has two interchangeable raw inputs; the cotton row is tech-gated.
const RECIPES: Dictionary = {
	"lumber": {"output": "lumber", "inputs": {"timber": 2}, "labour": 2},
	"fabric_from_wool": {"output": "fabric", "inputs": {"wool": 2}, "labour": 2},
	"fabric_from_cotton":
	{
		"output": "fabric",
		"inputs": {"cotton": 2},
		"labour": 2,
		"requires": "cotton_weaving",
	},
	"castIron": {"output": "castIron", "inputs": {"iron": 2}, "labour": 2},
	"refinedSugar": {"output": "refinedSugar", "inputs": {"sugarCane": 2}, "labour": 2},
	"cigars": {"output": "cigars", "inputs": {"tobacco": 2}, "labour": 2},
	"furHats": {"output": "furHats", "inputs": {"furs": 2}, "labour": 2},
	"steel":
	{
		"output": "steel",
		"inputs": {"iron": 1, "coal": 1},
		"labour": 2,
		"turns": 2,
	},
	"paper": {"output": "paper", "inputs": {"timber": 2}, "labour": 2},
	"bronze":
	{
		"output": "bronze",
		"inputs": {"copper": 1, "tin": 1},
		"labour": 3,
		"turns": 2,
	},
}

const OUTPUT_PER_RUN: int = 1


static func ids() -> Array[String]:
	var out: Array[String] = []
	for id: Variant in RECIPES.keys():
		out.append(String(id))
	out.sort()
	return out


static func known(recipe_id: String) -> bool:
	return RECIPES.has(recipe_id)


static func entry(recipe_id: String) -> Dictionary:
	return RECIPES.get(recipe_id, {})


static func output(recipe_id: String) -> String:
	return String(entry(recipe_id).get("output", ""))


static func inputs(recipe_id: String) -> Dictionary:
	return (entry(recipe_id).get("inputs", {}) as Dictionary).duplicate()


static func labour(recipe_id: String) -> int:
	return int(entry(recipe_id).get("labour", 0))


static func required_tech(recipe_id: String) -> String:
	return String(entry(recipe_id).get("requires", ""))


## Turns one run occupies the workshop before its output lands; 1 unless the
## row declares more (wiki: production-recipes § Turns per unit).
static func turns(recipe_id: String) -> int:
	return maxi(int(entry(recipe_id).get("turns", 1)), 1)


## Units of this recipe still in the workshop: started on an earlier turn, their
## output not landed yet (DR-20261112-11).
static func in_flight(wip: Dictionary, recipe_id: String) -> int:
	var total: int = 0
	for raw: Variant in (wip.get(recipe_id, []) as Array):
		if typeof(raw) == TYPE_DICTIONARY:
			total += int((raw as Dictionary).get("units", 0))
	return total


## A recipe with no required technology is available to everyone; a gated recipe
## only to players whose tech set holds it (wiki: production-recipes § tech gates).
static func available(recipe_id: String, tech_unlocked: Dictionary) -> bool:
	if not known(recipe_id):
		return false
	var tech: String = required_tech(recipe_id)
	return tech.is_empty() or bool(tech_unlocked.get(tech, false))


static func available_ids(tech_unlocked: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for recipe_id: String in ids():
		if available(recipe_id, tech_unlocked):
			out.append(recipe_id)
	return out


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
		if units <= 0 or not known(recipe_id):
			continue
		var needed: Dictionary = inputs(recipe_id)
		for commodity: Variant in needed.keys():
			var id: String = String(commodity)
			reserved[id] = int(reserved.get(id, 0)) + int(needed[commodity]) * units
	return reserved


## Whole runs a recipe can complete with the given inputs and labour budget.
static func max_runs(recipe_id: String, stockpile: Dictionary, labour_points: int) -> int:
	if not known(recipe_id):
		return 0
	var per_run_labour: int = labour(recipe_id)
	if per_run_labour <= 0:
		return 0
	var runs: int = labour_points / per_run_labour
	var needed: Dictionary = inputs(recipe_id)
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
## the workshop with one phase already served. The returned "wip" replaces the
## caller's (DR-20261112-11).
static func plan(
	assignments: Array[Dictionary],
	stockpile: Dictionary,
	labour_points: int,
	tech_unlocked: Dictionary,
	wip: Dictionary = {}
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
		if not known(recipe_id):
			continue
		var batches: Array = []
		for raw_batch: Variant in (wip[raw_recipe] as Array):
			if typeof(raw_batch) != TYPE_DICTIONARY:
				continue
			var batch: Dictionary = raw_batch
			var units: int = int(batch.get("units", 0))
			if units <= 0:
				continue
			var turns_left: int = int(batch.get("turns_left", 0)) - 1
			if turns_left > 0:
				batches.append({"units": units, "turns_left": turns_left})
				continue
			var landed_id: String = output(recipe_id)
			var landed: int = units * OUTPUT_PER_RUN
			stockpile[landed_id] = int(stockpile.get(landed_id, 0)) + landed
			produced[landed_id] = int(produced.get(landed_id, 0)) + landed
			completed[recipe_id] = int(completed.get(recipe_id, 0)) + units
		if not batches.is_empty():
			next_wip[recipe_id] = batches
	for assignment: Dictionary in assignments:
		var recipe_id: String = String(assignment.get("recipe", ""))
		if not available(recipe_id, tech_unlocked):
			continue
		var desired: int = int(assignment.get("units", 0))
		if desired <= 0:
			continue
		var affordable: int = mini(desired, max_runs(recipe_id, stockpile, remaining_labour))
		if affordable <= 0:
			continue
		var needed: Dictionary = inputs(recipe_id)
		for commodity: Variant in needed.keys():
			var id: String = String(commodity)
			var amount: int = int(needed[commodity]) * affordable
			stockpile[id] = maxi(int(stockpile.get(id, 0)) - amount, 0)
			consumed[id] = int(consumed.get(id, 0)) + amount
		runs_by_recipe[recipe_id] = int(runs_by_recipe.get(recipe_id, 0)) + affordable
		started_units[recipe_id] = int(started_units.get(recipe_id, 0)) + affordable
		remaining_labour -= affordable * labour(recipe_id)
		var turns: int = turns(recipe_id)
		if turns > 1:
			var batches: Array = next_wip.get(recipe_id, [])
			batches.append({"units": affordable, "turns_left": turns - 1})
			next_wip[recipe_id] = batches
			continue
		var out_id: String = output(recipe_id)
		var out_amount: int = affordable * OUTPUT_PER_RUN
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
