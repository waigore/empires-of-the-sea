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
## phase's own (REQ-P2-03, REQ-P3-03).


## The pool the next phase feeds: the roster plus the recruits already under
## orders, which the crown's ledger drains before Consumption runs
## (wiki: workers-and-population § Phase placement).
static func pool_next(economy: PlayerEconomy) -> WorkerPool:
	var pool: WorkerPool = economy.workers.copy()
	for tier in WorkerPool.TIER_COUNT:
		pool.add(tier, economy.recruits.pending(RecruitQueue.KIND_WORKER, str(tier)))
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
	var report: Dictionary = EconomyConsumption.preview(
		pool,
		economy.stockpile,
		int(mouths.get("ships", 0)),
		int(mouths.get("army", 0)),
		[int(mouths.get("hospital", 0))],
	)
	var idle: Array = report.get("idle_counts", [])
	var striking_tier: int = -1
	for tier: int in EconomyConsumption.FEED_ORDER:
		if pool.count(tier) > int(idle[tier]):
			striking_tier = tier
			break
	var luxury: Dictionary = {}
	for tier in WorkerPool.TIER_COUNT:
		var id: String = WorkerPool.luxury_for(tier)
		if id.is_empty() or pool.count(tier) <= 0:
			continue
		luxury[id] = int(luxury.get(id, 0)) + pool.count(tier)
	var store_luxury: Dictionary = {}
	for id: Variant in luxury.keys():
		store_luxury[id] = int(economy.stockpile.get(String(id), 0))
	var fed_counts: Array = report.get("fed_counts", [])
	var fed_food: int = 0
	for tier in WorkerPool.TIER_COUNT:
		fed_food += int(fed_counts[tier]) * WorkerPool.FOOD_PER_WORKER[tier]
	var spent: Dictionary = report.get("luxury_spent", {})
	var luxury_short: Dictionary = {}
	for id: Variant in luxury.keys():
		var short: int = int(luxury[id]) - int(spent.get(String(id), 0))
		if short > 0:
			luxury_short[id] = short
	return {
		"mouths": pool.total(),
		"arriving": economy.recruits.pending_kind(RecruitQueue.KIND_WORKER),
		"food": pool.food_demand(),
		"luxury": luxury,
		"store_food": _store_food(economy.stockpile),
		"store_luxury": store_luxury,
		"fed": int(report.get("fed_workers", 0)),
		"strikers": int(report.get("strikers", 0)),
		"striking_tier": striking_tier,
		"food_short": maxi(pool.food_demand() - fed_food, 0),
		"luxury_short": luxury_short,
		"report": report,
	}


## Food units the larder holds now: grain and meat, the same two the phase eats
## (wiki: workers-and-population § Consumption).
static func _store_food(stockpile: Dictionary) -> int:
	var total: int = 0
	for id: String in CommodityCatalog.FOOD:
		total += maxi(int(stockpile.get(id, 0)), 0)
	return total
