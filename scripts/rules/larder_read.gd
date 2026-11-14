class_name LarderRead
extends RefCounted
## What the next Consumption phase would do to the crown's larder, read before it
## happens (wiki: workers-and-population § Consumption; REQ-P5-06).
##
## The phase feeds the army, then the navy, then the workers from the highest tier
## down, then the hospital wards; a worker who misses food, or a trained worker who
## misses their tier luxury, strikes for the turn. The phase report only speaks
## **after** the fact, so a crown that recruits into a thin larder learns of the
## strike a turn late. This reading runs the phase's own deduction order over
## copies: the store is never spent to answer a question, and the answer is the
## phase's own (REQ-P2-03, REQ-P3-01, REQ-P3-03).


## The pool the next phase feeds: the roster plus the recruits already under
## orders, less the peasants those orders spend, because the crown's ledger
## drains the queue before Consumption runs (wiki: workers-and-population
## § Phase placement). A waiting train trades a peasant for its tier, and a
## mustered regiment or a launched hull takes a headcount too, so counting only
## the arrivals would feed one mouth that is no longer there
## (wiki: workers-and-population § Recruiting; § Military and naval
## construction).
static func pool_next(economy: PlayerEconomy) -> WorkerPool:
	var pool: WorkerPool = economy.workers.copy()
	for tier in WorkerPool.TIER_COUNT:
		pool.add(tier, economy.recruits.pending(RecruitQueue.KIND_WORKER, str(tier)))
	pool.remove(WorkerPool.Tier.PEASANT, economy.recruits.reserved_peasants())
	return pool


## The other appetites the phase feeds **before** the workers, as the last
## resolution read them: `army` food, `ships` hulls and `hospital` food. A caller
## with no report feeds the pool alone.
static func mouths(report: Dictionary) -> Dictionary:
	var last: Dictionary = report.get("consumption", {}) as Dictionary
	if last == null:
		return {"army": 0, "ships": 0, "hospital": 0}
	return {
		"army": int(last.get("army_demand", 0)),
		"ships": int(last.get("navy_demand", 0)) / ShipEconomy.FOOD_UPKEEP_PER_SHIP,
		"hospital": int(last.get("hospital_demand", 0)),
	}


## The next Consumption phase, dry-run: what the store holds, what every mouth
## wants, how many strike and which tier strikes first. `striking_tier` is -1 when
## the larder covers every mouth; otherwise it is the highest tier with a striker,
## because the phase feeds Masters before Peasants and a shortfall always bites
## from the top down (wiki: workers-and-population § Consumption).
static func forecast(economy: PlayerEconomy, mouths: Dictionary = {}) -> Dictionary:
	var pool: WorkerPool = pool_next(economy)
	return reading(
		pool,
		economy.stockpile,
		mouths,
		economy.recruits.pending_kind(RecruitQueue.KIND_WORKER),
	)


## The same dry-run for a pool the caller already made. The pool is read, never
## changed, and the store is served over a copy, so the answer is the phase's own
## and asking it spends nothing (REQ-P2-03). The phase owns the order; this owns
## the before-shot a crown needs to plan a recruit.
static func reading(
	pool: WorkerPool, stockpile: Dictionary, mouths: Dictionary = {}, arriving: int = 0
) -> Dictionary:
	var larder: EconomyConsumption.Pass = EconomyConsumption.pass_over(
		pool,
		stockpile.duplicate(),
		int(mouths.get("ships", 0)),
		int(mouths.get("army", 0)),
		[int(mouths.get("hospital", 0))],
	)
	larder.serve()
	var report: Dictionary = larder.report()
	var luxury: Dictionary = {}
	for tier in WorkerPool.TIER_COUNT:
		var id: String = WorkerPool.luxury_for(tier)
		if id.is_empty() or pool.count(tier) <= 0:
			continue
		luxury[id] = int(luxury.get(id, 0)) + pool.count(tier)
	var store_luxury: Dictionary = {}
	for id: Variant in luxury.keys():
		store_luxury[id] = int(stockpile.get(String(id), 0))
	var luxury_short: Dictionary = {}
	for id: Variant in luxury.keys():
		var short: int = int(luxury[id]) - int(larder.luxury_spent.get(String(id), 0))
		if short > 0:
			luxury_short[id] = short
	return {
		"mouths": pool.total(),
		"arriving": arriving,
		"food": larder.food_wanted(),
		"luxury": luxury,
		"store_food": EconomyConsumption.food_available(stockpile),
		"store_luxury": store_luxury,
		"fed": int(report["fed_workers"]),
		"strikers": int(report["strikers"]),
		"striking_tier": larder.striking_tier(),
		"food_short": maxi(larder.food_wanted() - larder.food_fed(), 0),
		"luxury_short": luxury_short,
		"report": report,
	}
