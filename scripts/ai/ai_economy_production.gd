class_name AiEconomyProduction
extends RefCounted
## Rival workshop plan: which production rows to run next phase
## (wiki: economy-planner, production-recipes).
##
## Scores recipes by stock deficit, then allocates whole runs greedily under
## the labour and input budget the next Production phase will enforce. A row
## that needs a trained hand, a free bench slot, or a town at its level is no
## candidate until those gates open — the same presence tests the phase and the
## crown's ledger read (REQ-P2-03, REQ-P3-03; DR-20261114-07, DR-20261114-12,
## DR-20261116-04). Pure rules: state in, orders out; the map adapter applies
## them. [AiEconomyPlanner] keeps the public door; recruitment and ground
## appetite live on [AiEconomyRecruitment] and [AiEconomyAppetite].

## Outputs that unblock civilian work and industry; they win ties over purely
## commercial goods because every court needs them to keep building.
const BUILD_INPUTS: Array[String] = [
	"lumber", "castIron", "fabric", "paper", "steel", "bronze",
]


## Production assignments for the next Production phase plus the scored
## candidates that explain them (wiki: turn-trace-interpretation). `town_level`
## is the crown's best town in any province: the presence test the second-stage
## rows' works gate reads, so the plan never offers a run the phase refuses
## (wiki: production-recipes § Town-works gates; DR-20261116-04).
##
## `held` is the raw the muster's and the hull's own material rows claim — the
## stock the market must keep for the regiment and the yard (issue #484). The
## plan never promises a run whose inputs would eat that raw, so a court
## saving for a muster or a hull can still manufacture without costing the
## launch its timber or cloth; the rows themselves stay the claims' to rank
## (wiki: economy-planner § Reservations; issue #878).
static func production_orders(
	config: AiConfig, economy: PlayerEconomy, town_level: int = 0,
	held: Dictionary = {}
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var assignments: Array[Dictionary] = []
	if config == null or economy == null:
		return {"assignments": assignments, "candidates": candidates}
	var target: int = config.parameter("economy.reserve_target")
	var weight: int = maxi(config.parameter("economy.recipe_weight"), 1)
	var stock: Dictionary = economy.stockpile.duplicate()
	for commodity: Variant in held.keys():
		var id: String = String(commodity)
		stock[id] = maxi(int(stock.get(id, 0)) - maxi(int(held[commodity]), 0), 0)
	var labour: int = economy.workers.labour()
	# A batch already in the workshop counts toward the target: the court must
	# not keep assigning alloy runs that are still serving their turns
	# (DR-20261112-11).
	var committed: Dictionary = _committed(economy)
	# The room each slow row's bench has left once this phase's landings are
	# served: the plan takes effect after the phase resolves, so this is the
	# same reading `ProductionPhase.plan` will cap the runs with.
	var bench: Dictionary = _bench_room(economy)
	for recipe_id: String in ProductionRecipes.available_ids_for(
		economy.tech_unlocked, economy.workers, town_level
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
			var runs: int = mini(1, ProductionPhase.max_runs(recipe_id, stock, labour))
			# A slow row's bench holds three pieces: a fourth run waits for a
			# landing, so the phase would refuse it and the plan would have
			# spent its labour and inputs on nothing (DR-20261114-12).
			if bench.has(recipe_id):
				runs = mini(runs, int(bench[recipe_id]))
			if runs <= 0:
				continue
			entry["assigned"] = int(entry["assigned"]) + runs
			if bench.has(recipe_id):
				bench[recipe_id] = int(bench[recipe_id]) - runs
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
				ProductionPhase.max_runs(recipe_id, economy.stockpile, labour)
			)
		var made: String = ProductionRecipes.output(recipe_id)
		committed[made] = int(committed.get(made, 0)) + units
	return committed


## Room each slow row's bench has left for the runs this plan sets: recipe id ->
## pieces, read from the workshop this phase leaves. The plan is applied after
## the phase resolves, so its runs start one phase later — and by then every
## batch on the bench has served another phase, and a batch that starts this
## phase joins with one already served, so the bench it meets holds no more than
## `serve` keeps. A one-turn row never waits, so it is absent and never capped
## (wiki: production-recipes § Workshop queue; DR-20261114-12, DR-20261115-02).
static func _bench_room(economy: PlayerEconomy) -> Dictionary:
	var room: Dictionary = {}
	if economy == null or economy.production == null:
		return room
	var wip: Dictionary = economy.production.wip
	for recipe_id: String in ProductionRecipes.available_ids(economy.tech_unlocked):
		var turns: int = ProductionRecipes.turns(recipe_id)
		if turns <= 1:
			continue
		room[recipe_id] = ProductionWorkshop.room(wip, recipe_id, turns)
	return room


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
