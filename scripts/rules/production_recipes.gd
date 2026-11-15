class_name ProductionRecipes
extends RefCounted
## Production recipe catalog (wiki: production-recipes). Each run consumes whole
## input units from the post-consumption stockpile and labour from idle workers,
## then adds its output. Runs are always whole; a recipe that cannot run once is
## skipped without partial consumption (REQ-P2-03).
##
## A run may occupy the workshop for more than one turn ("turns", default 1).
## Its inputs and labour are paid when it starts; the output lands after that
## many Production phases, seat counting as the first (DR-20261112-11). The two
## alloys combine two inputs, and a cigar ages while a fur hat cures, so the
## alloy and luxury rows are the catalogue's two-turn work (DR-20261114-10).
##
## A batch then lands **one unit a phase** rather than all at once: a batch of
## three steel started in turn 1 delivers one in turn 2, the last in turn 4
## (wiki: production-recipes § Turns per unit; DR-20261113-02). Drip-feeding the
## same runs phase by phase builds the same output from the same inputs, so a
## batch buys no front-loading and no larger order is punished beyond its wait.
##
## A row may also need a **trained hand**: `min_tier` names the lowest worker
## tier whose presence opens it (a higher tier satisfies it), checked wherever a
## row is offered or run — the phase, the ledger's ceiling and the AI's
## candidates (wiki: production-recipes § Worker-tier gates; DR-20261114-07).
##
## A slow row's bench holds **three pieces**: a fourth run of the same row waits
## for a landing, so a court cannot pay ten turns of inputs ahead (wiki:
## production-recipes § Workshop queue; DR-20261114-12).
##
## A row may also need the **town's works**: `min_town` names the lowest town
## level whose presence opens it, read as the crown's best town in any province
## — a presence test like the hand gate, not a per-province count (wiki:
## production-recipes § Town-works gates; DR-20261116-04). The two second-stage
## rows are the catalogue's own: garments from fabric and rum from refined
## sugar, both two-turn work.
##
## The catalogue owns the rows, their gates and the phase plan; the batches a
## court has already paid for are read and served by `ProductionWorkshop`.

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
	"cigars": {"output": "cigars", "inputs": {"tobacco": 2}, "labour": 2, "min_tier": 1, "turns": 2},
	"furHats": {"output": "furHats", "inputs": {"furs": 2}, "labour": 2, "min_tier": 2, "turns": 2},
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
	"garments":
	{
		"output": "garments",
		"inputs": {"fabric": 2},
		"labour": 2,
		"turns": 2,
		"min_town": 2,
	},
	"rum":
	{
		"output": "rum",
		"inputs": {"refinedSugar": 2},
		"labour": 2,
		"turns": 2,
		"min_town": 4,
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


## The lowest worker tier whose presence opens the row; 0 when any hand may run
## it (wiki: production-recipes § Worker-tier gates; DR-20261114-07).
static func min_tier(recipe_id: String) -> int:
	return int(entry(recipe_id).get("min_tier", 0))


## True when the court's pool holds a worker at or above the row's gate. A gate
## is a presence test, not a headcount: one master satisfies a journeyman row,
## and a court with no pool at all (a projection without workers) fails closed.
static func tier_met(recipe_id: String, workers: WorkerPool) -> bool:
	var need: int = min_tier(recipe_id)
	if need <= 0:
		return true
	if workers == null:
		return false
	for tier: int in range(need, WorkerPool.TIER_COUNT):
		if workers.count(tier) > 0:
			return true
	return false


## The lowest town level whose works open the row; 0 when any town may run it
## (wiki: production-recipes § Town-works gates; DR-20261116-04).
static func min_town(recipe_id: String) -> int:
	return int(entry(recipe_id).get("min_town", 0))


## True when the crown owns a town at or above the row's works gate. The reading
## is the crown's best town in any province — a presence test like the hand gate,
## so a court with no town at all (a projection without a world) fails closed.
static func town_met(recipe_id: String, town_level: int) -> bool:
	var need: int = min_town(recipe_id)
	return need <= 0 or town_level >= need


## Both gates a row declares plus the town's works: the study, the hand and the
## town the crown's best town stands at.
static func available_for(
	recipe_id: String,
	tech_unlocked: Dictionary,
	workers: WorkerPool,
	town_level: int = 0
) -> bool:
	return (
		available(recipe_id, tech_unlocked)
		and tier_met(recipe_id, workers)
		and town_met(recipe_id, town_level)
	)


## Rows a court may actually run: tech, hand and town's works all open
## (REQ-P2-03).
static func available_ids_for(
	tech_unlocked: Dictionary, workers: WorkerPool, town_level: int = 0
) -> Array[String]:
	var out: Array[String] = []
	for recipe_id: String in ids():
		if available_for(recipe_id, tech_unlocked, workers, town_level):
			out.append(recipe_id)
	return out


## Turns one run occupies the workshop before its output lands; 1 unless the
## row declares more (wiki: production-recipes § Turns per unit).
static func turns(recipe_id: String) -> int:
	return maxi(int(entry(recipe_id).get("turns", 1)), 1)


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


## Labour the runs in these assignments claim: units × the recipe's labour per
## run. The ledger's per-row ceiling subtracts the other rows' share of it, so a
## court reading one row sees what is left for that row (REQ-P2-03).
static func claimed_labour(assignments: Array) -> int:
	var total: int = 0
	for raw: Variant in assignments:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var assignment: Dictionary = raw
		total += int(assignment.get("units", 0)) * labour(String(assignment.get("recipe", "")))
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
	if not known(recipe_id) or not tier_met(recipe_id, workers):
		return 0
	if not town_met(recipe_id, town_level):
		return 0
	var others: Array = []
	for raw: Variant in assignments:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var other_id: String = String((raw as Dictionary).get("recipe", ""))
		if other_id == recipe_id:
			continue
		# A gated row never runs, so it claims nothing from the rows that do.
		if not tier_met(other_id, workers) or not town_met(other_id, town_level):
			continue
		others.append(raw)
	var left: Dictionary = stockpile.duplicate()
	var claimed: Dictionary = reserved_inputs(others)
	for commodity: Variant in claimed.keys():
		var id: String = String(commodity)
		left[id] = maxi(int(left.get(id, 0)) - int(claimed[commodity]), 0)
	var runs: int = max_runs(recipe_id, left, maxi(labour_points - claimed_labour(others), 0))
	# A slow row's bench holds three pieces: the fourth run waits for a landing,
	# so the stepper stops where the phase would (wiki: production-recipes
	# § Workshop queue; DR-20261114-12).
	if turns(recipe_id) > 1:
		runs = mini(runs, ProductionWorkshop.room(wip, recipe_id, turns(recipe_id)))
	return runs


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
		if not known(recipe_id):
			continue
		var served: Dictionary = ProductionWorkshop.serve(wip, recipe_id, turns(recipe_id))
		var landing_units: int = int(served["landed"])
		if landing_units > 0:
			var landed_id: String = output(recipe_id)
			var landed: int = landing_units * OUTPUT_PER_RUN
			stockpile[landed_id] = int(stockpile.get(landed_id, 0)) + landed
			produced[landed_id] = int(produced.get(landed_id, 0)) + landed
			completed[recipe_id] = int(completed.get(recipe_id, 0)) + landing_units
		var kept: Array[Dictionary] = served["kept"]
		if not kept.is_empty():
			next_wip[recipe_id] = kept
	for assignment: Dictionary in assignments:
		var recipe_id: String = String(assignment.get("recipe", ""))
		if not available_for(recipe_id, tech_unlocked, workers, town_level):
			continue
		var desired: int = int(assignment.get("units", 0))
		if desired <= 0:
			continue
		var turns: int = turns(recipe_id)
		var affordable: int = mini(desired, max_runs(recipe_id, stockpile, remaining_labour))
		# A slow row's bench holds three pieces; a fourth waits for a landing
		# (wiki: production-recipes § Workshop queue; DR-20261114-12). The room
		# is read from the workshop this phase will leave, so two assignments of
		# one row cannot both fill the same bench.
		if turns > 1:
			affordable = mini(affordable, ProductionWorkshop.open_room(next_wip, recipe_id))
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
