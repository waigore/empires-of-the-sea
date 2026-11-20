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
## with no report feeds the pool alone. `wards` carries the hospital staffs'
## demands **one per ward**, because the phase feeds them in order and in whole
## staffs: a summed appetite would let one big ward swallow a larder that would
## have covered a smaller one behind it (wiki: workers-and-population
## § Consumption; DR-20261112-04). A report that predates the list keeps the
## scalar, and the reading feeds it as the one ward it says.
static func mouths(report: Dictionary) -> Dictionary:
	var last: Dictionary = report.get("consumption", {}) as Dictionary
	if last == null or last.is_empty():
		return {"army": 0, "ships": 0, "hospital": 0, "wards": []}
	var hospital: int = int(last.get("hospital_demand", 0))
	var listed: Variant = last.get("hospital_demands", null)
	var wards: Array[int] = []
	if typeof(listed) == TYPE_ARRAY:
		for value: Variant in listed:
			wards.append(int(value))
	else:
		wards.append(hospital)
	return {
		"army": int(last.get("army_demand", 0)),
		"ships": int(last.get("navy_demand", 0)) / ShipEconomy.FOOD_UPKEEP_PER_SHIP,
		"hospital": hospital,
		"wards": wards,
	}


## The ward demands a call carries: the list when the caller has it, else the
## scalar appetite as one ward. The phase reads the list, so this keeps the
## dry-run the phase's own answer (REQ-P2-03).
static func _wards(mouths: Dictionary) -> Array[int]:
	var raw: Variant = mouths.get("wards", null)
	if typeof(raw) != TYPE_ARRAY:
		return [int(mouths.get("hospital", 0))]
	var out: Array[int] = []
	for value: Variant in raw:
		out.append(int(value))
	return out


## The ration the crown's waiting musters and launches will eat at this turn's
## close: a regiment or a hull under orders lands at Build/work, before
## Consumption runs, so the phase pays its upkeep even though the muster roll
## does not show it yet (wiki: workers-and-population § Consumption — "every
## appetite the phase pays … the recruits already under orders"). A regiment's
## ration is its catalogue row's (`RegimentCatalog.food_upkeep`), a hull's the
## published two units (`ShipEconomy.FOOD_UPKEEP_PER_SHIP`), and a civilian hire
## eats nothing. `ships` is a hull count, the unit `mouths` carries.
static func pending_rations(economy: PlayerEconomy) -> Dictionary:
	var rations: Dictionary = {"army": 0, "ships": 0}
	if economy == null:
		return rations
	for row: Dictionary in economy.recruits.orders:
		match String(row.get("kind", "")):
			RecruitQueue.KIND_REGIMENT:
				rations["army"] = int(rations["army"]) \
					+ RegimentCatalog.food_upkeep(String(row.get("key", "")))
			RecruitQueue.KIND_SHIP:
				rations["ships"] = int(rations["ships"]) + 1
	return rations


## The next Consumption phase, dry-run: what the store holds, what every mouth
## wants, how many strike and which tier strikes first. `striking_tier` is -1 when
## the larder covers every mouth; otherwise it is the highest tier with a striker,
## because the phase feeds Masters before Peasants and a shortfall always bites
## from the top down (wiki: workers-and-population § Consumption).
## The appetites the caller hands in are the last phase's; the musters and
## launches already under orders are added here, because they land at this turn's
## Build/work and eat at its close (wiki: workers-and-population § Phase
## placement; § Consumption). `waiting` is false for a caller whose `mouths`
## already name the turn the phase will run — the ledger's own projection counts
## the waiting orders itself, so adding them again would feed one mouth twice.
static func forecast(
	economy: PlayerEconomy, mouths: Dictionary = {}, waiting: bool = true
) -> Dictionary:
	var pool: WorkerPool = pool_next(economy)
	var fed: Dictionary = mouths.duplicate()
	if waiting:
		var queued: Dictionary = pending_rations(economy)
		fed["army"] = int(fed.get("army", 0)) + int(queued["army"])
		fed["ships"] = int(fed.get("ships", 0)) + int(queued["ships"])
	return reading(
		pool,
		economy.stockpile,
		fed,
		economy.recruits.pending_kind(RecruitQueue.KIND_WORKER),
		economy.recruits.arriving_by_tier(),
	)


## The same dry-run for a pool the caller already made. The pool is read, never
## changed, and the store is served over a copy, so the answer is the phase's own
## and asking it spends nothing (REQ-P2-03). The phase owns the order; this owns
## the before-shot a crown needs to plan a recruit. `store_short` is the whole
## larder's shortfall — every mouth the phase feeds, not the pool alone — so a
## store that covers the pool but starves a ward or the army reads short here.
## `arriving` is the per-tier roster that lands at this turn's Build/work: it eats
## here but its labour is the next Production phase's (wiki:
## workers-and-population § Phase placement).
static func reading(
	pool: WorkerPool,
	stockpile: Dictionary,
	mouths: Dictionary = {},
	arriving: int = 0,
	arriving_tiers: Array[int] = []
) -> Dictionary:
	var larder: EconomyConsumption.Pass = EconomyConsumption.pass_over(
		pool,
		stockpile.duplicate(),
		int(mouths.get("ships", 0)),
		int(mouths.get("army", 0)),
		_wards(mouths),
		arriving_tiers,
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
	# Every appetite this pass pays, in the phase's own deduction order: the army
	# and the navy eat before the pool, the wards after it (wiki:
	# workers-and-population § Consumption). The ledger names each one, because a
	# store that covers the pool alone must not read as a calm larder.
	var appetites: Dictionary = {
		"army": int(report["army_demand"]),
		"navy": int(report["navy_demand"]),
		"pool": larder.food_wanted(),
		"wards": int(report["hospital_demand"]),
	}
	var store_food: int = EconomyConsumption.food_available(stockpile)
	var wanted: int = (
		int(appetites["army"]) + int(appetites["navy"])
		+ int(appetites["pool"]) + int(appetites["wards"])
	)
	return {
		"mouths": pool.total(),
		"arriving": arriving,
		"food": larder.food_wanted(),
		"appetites": appetites,
		"luxury": luxury,
		"store_food": store_food,
		"store_luxury": store_luxury,
		"fed": int(report["fed_workers"]),
		"strikers": int(report["strikers"]),
		"striking_tier": larder.striking_tier(),
		"food_short": maxi(larder.food_wanted() - larder.food_fed(), 0),
		# The whole larder's shortfall: every mouth the phase feeds, so a store
		# that covers the pool but starves a ward or the army is never read calm
		# (wiki: workers-and-population § Consumption — total food demand).
		"store_short": maxi(wanted - store_food, 0),
		"luxury_short": luxury_short,
		"report": report,
	}


## The crown's larder standing for the turn about to open: the store's food, the
## slack the next Consumption phase leaves (negative when it comes up short) and
## the strikers it would leave. A caller that carries the ledger's own projection
## passes its mouths with `waiting = false`, because that projection already
## counts the musters and launches under orders — the turn's warning and the
## WORKERS tab then print one larder for one turn (wiki:
## workers-and-population § Consumption; REQ-P2-03, REQ-P5-05). Nothing is spent:
## the figure is the tab's own dry run.
static func standing(
	economy: PlayerEconomy, mouths: Dictionary = {}, waiting: bool = true
) -> Dictionary:
	var read: Dictionary = forecast(economy, mouths, waiting)
	var appetites: Dictionary = read["appetites"] as Dictionary
	var wanted: int = (
		int(appetites.get("army", 0)) + int(appetites.get("navy", 0))
		+ int(appetites.get("pool", 0)) + int(appetites.get("wards", 0))
	)
	return {
		"food": int(read["store_food"]),
		"wanted": wanted,
		"slack": int(read["store_food"]) - wanted,
		"strikers": int(read["strikers"]),
		"striking_tier": int(read["striking_tier"]),
		"luxury_short": read["luxury_short"],
	}


## The warning a court hears a turn before the larder bites: what runs short and
## how many hands strike if nothing is done, in the phase's own order — food
## first, then the tier the shortfall takes from the top down (wiki:
## workers-and-population § Consumption; REQ-P5-05, REQ-P5-06). Empty when the
## store covers every mouth, so a calm larder says nothing at all.
static func warning(standing: Dictionary) -> String:
	var strikers: int = int(standing.get("strikers", 0))
	if strikers <= 0:
		return ""
	var short: int = int(standing.get("slack", 0))
	var head: String = "The larder runs short"
	## The shortfall and the strike are two clauses of one line. The published
	## line separates them with a semicolon when the food figure leads it
	## (`The larder runs short — 2 food; 1 worker will strike …`) and keeps the
	## dash for the luxury form (`The larder runs short of Refined Sugar ×1 — …`)
	## (wiki: workers-and-population § Consumption; DR-20261119-11).
	var gap: String = " — "
	if short < 0:
		head += " — %d food" % -short
		gap = "; "
	else:
		var luxuries: Dictionary = standing.get("luxury_short", {}) as Dictionary
		for id: Variant in luxuries.keys():
			head += " of %s ×%d" % [CommodityCatalog.label(String(id)), int(luxuries[id])]
			break
	var who: String = "%d %s will strike at the next close, %s first" % [
		strikers,
		"worker" if strikers == 1 else "workers",
		WorkerPool.tier_name(maxi(int(standing.get("striking_tier", 0)), 0)).to_lower(),
	]
	return "%s%s%s." % [head, gap, who]
