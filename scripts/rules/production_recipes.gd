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
##
## A batch then lands **one unit a phase** rather than all at once: a batch of
## three steel started in turn 1 delivers one in turn 2, the last in turn 4
## (wiki: production-recipes § Turns per unit; DR-20261113-02). Drip-feeding the
## same runs phase by phase builds the same output from the same inputs, so a
## batch buys no front-loading and no larger order is punished beyond its wait.

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


## Units one batch of this row lands in a Production phase: a multi-turn batch
## lands **one** and keeps the rest for the phases after it; a one-turn row never
## waits, so a carried batch of it (only a damaged or hand-edited save can hold
## one) lands whole (wiki: production-recipes § Turns per unit; DR-20261113-02).
static func landing(recipe_id: String, units: int) -> int:
	if turns(recipe_id) <= 1:
		return maxi(units, 0)
	return mini(1, maxi(units, 0))


## One workshop row, cleaned: a batch with whole units and turns left, or {} when
## the value is not a batch at all. A hand-edited or damaged save is dropped,
## never trusted (wiki: production-recipes § Acceptance Criteria; DR-20261112-11).
static func batch(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var units: int = int((raw as Dictionary).get("units", 0))
	var turns_left: int = int((raw as Dictionary).get("turns_left", 0))
	if units <= 0 or turns_left <= 0:
		return {}
	return {"units": units, "turns_left": turns_left}


## The batches a recipe's workshop entry holds. An entry of any other shape holds
## none, so the phase, the save and the ledger all read a malformed row as an
## empty workshop instead of failing on the cast.
static func batches(wip: Dictionary, recipe_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw_entry: Variant = wip.get(recipe_id, [])
	if typeof(raw_entry) != TYPE_ARRAY:
		return out
	for raw: Variant in (raw_entry as Array):
		var cleaned: Dictionary = batch(raw)
		if not cleaned.is_empty():
			out.append(cleaned)
	return out


## Units of this recipe still in the workshop: started on an earlier turn, their
## output not landed yet (DR-20261112-11).
static func in_flight(wip: Dictionary, recipe_id: String) -> int:
	var total: int = 0
	for cleaned: Dictionary in batches(wip, recipe_id):
		total += int(cleaned["units"])
	return total


## Phases until the next unit of this recipe lands; 0 when the workshop is idle.
## The soonest batch speaks for the row: a later batch cannot delay the unit that
## is already one phase from the store (DR-20261113-02's "the next landing").
static func turns_left(wip: Dictionary, recipe_id: String) -> int:
	var all: Array[Dictionary] = batches(wip, recipe_id)
	if all.is_empty():
		return 0
	var soonest: int = int(all[0]["turns_left"])
	for cleaned: Dictionary in all:
		soonest = mini(soonest, int(cleaned["turns_left"]))
	return soonest


## Units that leave the workshop in the next Production phase: one per batch
## whose turns are served, so a court that left the row set and has two batches
## on the anvil lands two a phase. The row's reading uses this so the note never
## promises fewer landings than the phase pays (wiki: production-recipes
## § Turns per unit; DR-20261113-02).
static func next_landing(wip: Dictionary, recipe_id: String) -> int:
	var total: int = 0
	for cleaned: Dictionary in batches(wip, recipe_id):
		if int(cleaned["turns_left"]) > 1:
			continue
		total += landing(recipe_id, int(cleaned["units"]))
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
## the workshop with one phase already served. A multi-turn batch then lands one
## unit a phase and keeps the rest for the phases after it, so a batch of three
## started in turn 1 delivers its last unit in turn 4 (DR-20261113-02). The
## returned "wip" replaces the caller's.
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
		var kept: Array[Dictionary] = []
		for carried: Dictionary in batches(wip, recipe_id):
			var units: int = int(carried["units"])
			var turns_left: int = int(carried["turns_left"]) - 1
			if turns_left > 0:
				kept.append({"units": units, "turns_left": turns_left})
				continue
			var landing_units: int = landing(recipe_id, units)
			var landed_id: String = output(recipe_id)
			var landed: int = landing_units * OUTPUT_PER_RUN
			stockpile[landed_id] = int(stockpile.get(landed_id, 0)) + landed
			produced[landed_id] = int(produced.get(landed_id, 0)) + landed
			completed[recipe_id] = int(completed.get(recipe_id, 0)) + landing_units
			if units > landing_units:
				kept.append({"units": units - landing_units, "turns_left": 1})
		if not kept.is_empty():
			next_wip[recipe_id] = kept
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
