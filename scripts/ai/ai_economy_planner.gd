class_name AiEconomyPlanner
extends RefCounted
## Full-AI economy policy (wiki: economy-planner, growth-stage-planner).
##
## Scores production recipes by the court's stock deficit, then allocates whole
## runs greedily under the labour and input budget the next Production phase
## will enforce. Recruitment spends the same ledger through PlayerEconomy, so a
## rival never invents resources or bypasses a tech gate (REQ-P2-03, REQ-P3-03).
## A row that needs a trained hand is no candidate until the pool holds one: the
## phase would refuse it, and a phantom run would spend the plan's labour and
## reserve inputs for output that never lands (wiki: production-recipes
## § Worker-tier gates; DR-20261114-07).
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
	# A batch already in the workshop counts toward the target: the court must
	# not keep assigning alloy runs that are still serving their turns
	# (DR-20261112-11).
	var committed: Dictionary = _committed(economy)
	for recipe_id: String in ProductionRecipes.available_ids_for(
		economy.tech_unlocked, economy.workers
	):
		var output: String = ProductionRecipes.output(recipe_id)
		var deficit: int = maxi(
			target - int(stock.get(output, 0)) - int(committed.get(output, 0)), 0
		)
		var score: int = _score(output, deficit, weight)
		candidates.append({
			"recipe": recipe_id,
			"output": output,
			"deficit": deficit,
			"score": score,
			"assigned": 0,
		})
	candidates.sort_custom(_better_candidate)
	# One run at a time in rank order, cycling while labour and inputs last: the
	# highest-scoring input must not take the court's whole labour while every
	# other build input starves. A court whose stores carry iron and wool wove no
	# cloth at all — castIron's deficit never fell (works spend it every turn), so
	# it outranked fabric on every turn and the muster starved with a full war
	# chest (issue #474).
	var progress: bool = true
	while progress and labour > 0:
		progress = false
		for entry: Dictionary in candidates:
			if int(entry["deficit"]) <= 0 or labour <= 0:
				continue
			var recipe_id: String = String(entry["recipe"])
			var runs: int = mini(1, ProductionRecipes.max_runs(recipe_id, stock, labour))
			if runs <= 0:
				continue
			entry["assigned"] = int(entry["assigned"]) + runs
			_reserve(recipe_id, runs, stock)
			labour -= runs * ProductionRecipes.labour(recipe_id)
			# Interchangeable recipes (wool/cotton fabric) must not both fill the
			# same deficit in one plan.
			for other: Dictionary in candidates:
				if String(other["output"]) == String(entry["output"]):
					other["deficit"] = maxi(int(other["deficit"]) - runs, 0)
			progress = true
	for entry: Dictionary in candidates:
		var units: int = int(entry["assigned"])
		if units <= 0:
			continue
		assignments.append({"recipe": String(entry["recipe"]), "units": units})
	assignments.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["recipe"]) < String(b["recipe"])
	)
	return {"assignments": assignments, "candidates": candidates}


## Units already promised to a recipe's output by the time this plan takes
## effect: the batches on the anvil plus the multi-turn run this phase still
## starts from the assignment already queued (the map adapter applies a new plan
## after the phase resolves). A one-turn run lands in that same phase, so the
## stockpile already speaks for it. Without the queued allowance a court starts a
## second alloy batch while one serves, spending two runs against one reserve
## (DR-20261112-11).
static func _committed(economy: PlayerEconomy) -> Dictionary:
	var queued: Dictionary = {}
	for assignment: Dictionary in economy.production.assignments():
		var queued_id: String = String(assignment.get("recipe", ""))
		if ProductionRecipes.turns(queued_id) <= 1:
			continue
		queued[queued_id] = int(queued.get(queued_id, 0)) + int(assignment.get("units", 0))
	var committed: Dictionary = {}
	var labour: int = economy.workers.labour()
	for recipe_id: String in ProductionRecipes.available_ids(economy.tech_unlocked):
		var units: int = economy.production.wip_units(recipe_id)
		if queued.has(recipe_id):
			units += mini(
				int(queued[recipe_id]),
				ProductionRecipes.max_runs(recipe_id, economy.stockpile, labour)
			)
		var made: String = ProductionRecipes.output(recipe_id)
		committed[made] = int(committed.get(made, 0)) + units
	return committed


## Recruit orders, highest affordable tier first, capped per turn and at the
## worker target. A copy is spent first, so the live ledger sees only the rows
## the rules already accepted. Two throttles keep the court growing rather than
## spent out: training never consumes the court's last peasant, and it never
## leaves the purse under its cash floor — `economy.min_treasury` or the war
## chest the caller passes in `floor`, whichever is higher — while the court
## could still train again next turn (wiki: workers-and-population § Rival
## training throttle; growth-stage-planner § Recruitment modulation).
## `fed_slack` is the grain the larder leaves after the army, the navy and the
## workers eat: a court hires no mouth it cannot feed, because a peasant it
## cannot feed strikes instead of working (issue #489). A negative reading means
## the caller has no larder to read, and the gate does not apply.
static func recruitment_orders(
	config: AiConfig, economy: PlayerEconomy, floor: int = 0, fed_slack: int = -1
) -> Array[Dictionary]:
	var orders: Array[Dictionary] = []
	if config == null or economy == null:
		return orders
	var target: int = config.parameter("economy.worker_target")
	if economy.workers.total() >= target:
		return orders
	var min_treasury: int = maxi(config.parameter("economy.min_treasury"), 0)
	# The muster floor a caller hands in is a hard veto: a court saving for its
	# next regiment buys no workers with that purse (issue #474). The court's own
	# cash floor keeps its soft throttle, so peace-time growth still takes the
	# one training a thin purse can pay.
	var muster_floor: int = maxi(floor, 0)
	var sim: PlayerEconomy = economy.copy()
	for _turn in maxi(config.parameter("economy.max_recruits"), 0):
		if sim.workers.total() >= target:
			break
		var tier: int = _best_tier(sim)
		if tier < 0:
			break
		if fed_slack >= 0 and fed_slack < WorkerPool.FOOD_PER_WORKER[tier]:
			break
		if WorkerPool.RECRUIT_CONSUMES_PEASANTS[tier] \
				and sim.workers.count(WorkerPool.Tier.PEASANT) <= 1:
			break
		if muster_floor > min_treasury and sim.treasury - _trains(sim, tier) < muster_floor:
			break
		if sim.treasury - _trains(sim, tier) < min_treasury \
				and _next_training_affordable(sim, min_treasury):
			break
		var result: Dictionary = sim.recruit(tier)
		if not bool(result.get("ok", false)):
			break
		fed_slack -= WorkerPool.FOOD_PER_WORKER[tier]
		orders.append({"tier": tier})
	return orders


## True when the purse could already pay a trained-tier row today, i.e. the
## court has slack outside `economy.min_treasury` and could train again next
## turn once its materials land. Peasant count is checked by the caller.
static func _next_training_affordable(economy: PlayerEconomy, reserve: int) -> bool:
	for tier in range(1, WorkerPool.TIER_COUNT):
		if not _techs_open(economy, tier):
			continue
		if economy.treasury - reserve >= _trains(economy, tier):
			return true
	return false


## True when this court's own techs already open `tier`, whatever its materials
## or peasant count say today.
static func _techs_open(economy: PlayerEconomy, tier: int) -> bool:
	return economy != null and WorkerPool.techs_unlocked(tier, economy.tech_unlocked)


## Treasury a training of `tier` would cost this court, or -1 for a bad tier.
static func _trains(economy: PlayerEconomy, tier: int) -> int:
	if economy == null or tier < 0 or tier >= WorkerPool.TIER_COUNT:
		return -1
	return int(WorkerPool.recruit_cost(tier).get("treasury", 0))


## Highest tier this court can legally train right now, or -1. Peasants are the
## fallback: a court with no worker tech still buys one peasant a turn, which is
## how the pool ever reaches `economy.worker_target` (wiki: workers-and-population
## § Recruit vs. train).
static func _best_tier(economy: PlayerEconomy) -> int:
	for tier in range(WorkerPool.TIER_COUNT - 1, -1, -1):
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
