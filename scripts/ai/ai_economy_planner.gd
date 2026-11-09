class_name AiEconomyPlanner
extends RefCounted
## Full-AI economy policy (wiki: economy-planner, growth-stage-planner).
##
## Scores production recipes by the court's stock deficit, then allocates whole
## runs greedily under the labour and input budget the next Production phase
## will enforce. Recruitment spends the same ledger through PlayerEconomy, so a
## rival never invents resources or bypasses a tech gate (REQ-P2-03, REQ-P3-03).
## Pure rules: state in, orders out; the map adapter applies them.

## Outputs that unblock civilian work and industry; they win ties over purely
## commercial goods because every court needs them to keep building.
const BUILD_INPUTS: Array[String] = [
	"lumber", "castIron", "fabric", "paper", "steel", "bronze",
]


## Production assignments for the next Production phase plus the scored
## candidates that explain them (wiki: turn-trace-interpretation).
static func production_orders(
	config: AiConfig, economy: PlayerEconomy
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var assignments: Array[Dictionary] = []
	if config == null or economy == null:
		return {"assignments": assignments, "candidates": candidates}
	var target: int = config.parameter("economy.reserve_target")
	var weight: int = maxi(config.parameter("economy.recipe_weight"), 1)
	var stock: Dictionary = economy.stockpile.duplicate()
	var labour: int = economy.workers.labour()
	for recipe_id: String in ProductionRecipes.available_ids(economy.tech_unlocked):
		var output: String = ProductionRecipes.output(recipe_id)
		var deficit: int = maxi(target - int(stock.get(output, 0)), 0)
		var score: int = _score(output, deficit, weight)
		candidates.append({
			"recipe": recipe_id,
			"output": output,
			"deficit": deficit,
			"score": score,
			"assigned": 0,
		})
	candidates.sort_custom(_better_candidate)
	for entry: Dictionary in candidates:
		if int(entry["deficit"]) <= 0 or labour <= 0:
			continue
		var recipe_id: String = String(entry["recipe"])
		var runs: int = mini(
			int(entry["deficit"]),
			ProductionRecipes.max_runs(recipe_id, stock, labour)
		)
		if runs <= 0:
			continue
		entry["assigned"] = runs
		assignments.append({"recipe": recipe_id, "units": runs})
		_reserve(recipe_id, runs, stock)
		labour -= runs * ProductionRecipes.labour(recipe_id)
		# Interchangeable recipes (wool/cotton fabric) must not both fill the
		# same deficit in one plan.
		for other: Dictionary in candidates:
			if String(other["output"]) == String(entry["output"]):
				other["deficit"] = maxi(int(other["deficit"]) - runs, 0)
	assignments.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["recipe"]) < String(b["recipe"])
	)
	return {"assignments": assignments, "candidates": candidates}


## Recruit orders, highest affordable tier first, capped per turn and at the
## worker target. A copy is spent first, so the live ledger sees only the rows
## the rules already accepted.
static func recruitment_orders(
	config: AiConfig, economy: PlayerEconomy
) -> Array[Dictionary]:
	var orders: Array[Dictionary] = []
	if config == null or economy == null:
		return orders
	var target: int = config.parameter("economy.worker_target")
	if economy.workers.total() >= target:
		return orders
	var sim: PlayerEconomy = economy.copy()
	for _turn in maxi(config.parameter("economy.max_recruits"), 0):
		if sim.workers.total() >= target:
			break
		var tier: int = _best_tier(sim)
		if tier < 0:
			break
		var result: Dictionary = sim.recruit(tier)
		if not bool(result.get("ok", false)):
			break
		orders.append({"tier": tier})
	return orders


## Highest tier this court can legally train right now, or -1.
static func _best_tier(economy: PlayerEconomy) -> int:
	for tier in range(WorkerPool.TIER_COUNT - 1, 0, -1):
		if economy.recruit_blocked_reason(tier).is_empty():
			return tier
	return -1


## A short store of a build input is worth more than the same shortfall of a
## luxury line: the base premium keeps civilian work supplied first.
static func _score(output: String, deficit: int, weight: int) -> int:
	var score: int = deficit * weight
	if BUILD_INPUTS.has(output):
		score += weight
	return score


## Removes the inputs and adds the output for runs already promised, so the
## next recipe in the same plan cannot spend the same commodity twice.
static func _reserve(recipe_id: String, runs: int, stock: Dictionary) -> void:
	var needed: Dictionary = ProductionRecipes.inputs(recipe_id)
	for commodity: Variant in needed.keys():
		var id: String = String(commodity)
		stock[id] = int(stock.get(id, 0)) - int(needed[commodity]) * runs
	var output: String = ProductionRecipes.output(recipe_id)
	stock[output] = int(stock.get(output, 0)) + runs


## Highest score first; recipe id breaks a tie so the plan is deterministic.
static func _better_candidate(a: Dictionary, b: Dictionary) -> bool:
	if int(a["score"]) != int(b["score"]):
		return int(a["score"]) > int(b["score"])
	return String(a["recipe"]) < String(b["recipe"])
