class_name EconomyConsumption
extends RefCounted
## Consumption phase (wiki: workers-and-population § Consumption). Deduction order is
## army, then navy, then workers, then the hospital staffs; workers are fed in full
## rations from the highest tier down, and a worker who misses food or their tier
## luxury strikes for the turn without leaving the pool. Idle workers supply the
## next Production phase's labour.
##
## One `pass` reads the larder once — what every mouth wants and what it is
## served — so the turn resolver and the pre-turn forecast share the same
## deduction order (REQ-P2-03, REQ-P3-01).

const FEED_ORDER: Array[int] = [
	WorkerPool.Tier.MASTER,
	WorkerPool.Tier.JOURNEYMAN,
	WorkerPool.Tier.APPRENTICE,
	WorkerPool.Tier.PEASANT,
]


## The larder read, before anything is served: every appetite this pass feeds,
## in the order it feeds them.
class Pass:
	var pool: WorkerPool
	var stockpile: Dictionary
	var army_demand: int
	var navy_demand: int
	var hospital_demands: Array[int]
	var army_fed: int = 0
	var navy_fed: int = 0
	var hospital_fed: int = 0
	var hospital_demand: int = 0
	## Workers fed per tier, and how many keep their labour (fed, and for a
	## trained tier also holding their luxury).
	var fed_counts: Array[int] = [0, 0, 0, 0]
	var idle_counts: Array[int] = [0, 0, 0, 0]
	## Hands that joined the pool at this turn's Build/work, one count per tier.
	## They eat with the court, but their labour is the next Production phase's:
	## same-turn labour from a new recruit is not supported (wiki:
	## workers-and-population § Phase placement).
	var arriving: Array[int] = [0, 0, 0, 0]
	var luxury_spent: Dictionary = {}

	func _init(
		roster: WorkerPool,
		store: Dictionary,
		ship_count: int,
		army_food: int,
		wards: Array[int],
		arriving_tiers: Array[int] = []
	) -> void:
		pool = roster
		stockpile = store
		army_demand = maxi(army_food, 0)
		navy_demand = maxi(ship_count, 0) * ShipEconomy.FOOD_UPKEEP_PER_SHIP
		hospital_demands = wards
		for tier in WorkerPool.TIER_COUNT:
			if tier < arriving_tiers.size():
				arriving[tier] = clampi(arriving_tiers[tier], 0, pool.count(tier))

	## Serves the whole larder in the phase's order, mutating `stockpile`.
	func serve() -> Pass:
		army_fed = EconomyConsumption._eat_food(stockpile, army_demand)
		navy_fed = EconomyConsumption._eat_food(stockpile, navy_demand)
		for tier: int in FEED_ORDER:
			for _index in pool.count(tier):
				if not EconomyConsumption._feed_worker(stockpile, tier):
					break
				fed_counts[tier] += 1
		_spend_luxury()
		_feed_wards()
		return self

	func _spend_luxury() -> void:
		for tier: int in FEED_ORDER:
			if not WorkerPool.is_trained(tier):
				continue
			var luxury: String = WorkerPool.luxury_for(tier)
			var available: int = int(stockpile.get(luxury, 0))
			var assigned: int = mini(fed_counts[tier], available)
			if assigned > 0:
				stockpile[luxury] = available - assigned
				luxury_spent[luxury] = assigned
			idle_counts[tier] = assigned
		idle_counts[WorkerPool.Tier.PEASANT] = fed_counts[WorkerPool.Tier.PEASANT]

	## The hospitals eat last, and only in whole staffs: a ward the larder cannot
	## cover in full goes unstaffed rather than half-fed, and the rest of the
	## larder is offered to the next ward (wiki: combat § Regiment condition;
	## DR-20261112-04).
	func _feed_wards() -> void:
		for raw: int in hospital_demands:
			hospital_demand += maxi(raw, 0)
		hospital_fed = EconomyConsumption._eat_food(
			stockpile,
			HospitalRules.ration(hospital_demands, EconomyConsumption.food_available(stockpile))
		)

	## Workers what their rations came to, this pool's own demand when it was fed
	## whole.
	func food_wanted() -> int:
		return EconomyConsumption._rations(pool.counts)

	## Workers this pass actually fed at their full ration: the store's answer to
	## "would every mouth eat?" without asking `resolve` to spend it.
	func food_fed() -> int:
		return EconomyConsumption._rations(fed_counts)

	## Strikers: workers the pass could not feed — no ration, or no luxury for a
	## trained tier. Reads the report it just served.
	func strikers() -> int:
		var idle_total: int = 0
		for tier in WorkerPool.TIER_COUNT:
			idle_total += idle_counts[tier]
		return pool.total() - idle_total

	## Labour the pool gives **this** Production phase: the workers who kept their
	## ration and their luxury, less the hands that joined at this turn's Build/work.
	## A recruit's labour is the next Production phase's, so the phase that hands it
	## the tools is the turn after it lands (wiki: workers-and-population
	## § Phase placement).
	func idle_labour() -> int:
		var labour: int = 0
		for tier in WorkerPool.TIER_COUNT:
			labour += (idle_counts[tier] - _arriving_idle(tier)) * WorkerPool.LABOUR_PER_WORKER[tier]
		return labour


	## The arriving hands among a tier's labouring workers: only those who kept their
	## ration (and luxury) could have laboured at all, so a hungry arrival withholds
	## nothing.
	func _arriving_idle(tier: int) -> int:
		return mini(arriving[tier], idle_counts[tier])


	## Labour this phase hands to the next one: what the recruits that landed at
	## Build/work will add once the turn has closed.
	func labour_next_turn() -> int:
		var labour: int = 0
		for tier in WorkerPool.TIER_COUNT:
			labour += _arriving_idle(tier) * WorkerPool.LABOUR_PER_WORKER[tier]
		return labour

	## The highest tier with a worker who strikes, or -1 when every mouth eats.
	## The phase feeds Masters before Peasants, so a shortfall bites from the top
	## down (wiki: workers-and-population § Consumption).
	func striking_tier() -> int:
		for tier: int in FEED_ORDER:
			if pool.count(tier) > idle_counts[tier]:
				return tier
		return -1

	## The phase report used by the turn log and UI.
	func report() -> Dictionary:
		var fed_workers: int = 0
		for tier in WorkerPool.TIER_COUNT:
			fed_workers += fed_counts[tier]
		return {
			"army_demand": army_demand,
			"army_fed": army_fed,
			"navy_demand": navy_demand,
			"navy_fed": navy_fed,
			"hospital_demand": hospital_demand,
			"hospital_fed": hospital_fed,
			"hospital_hungry": hospital_fed < hospital_demand,
			# The staffs' demands one per ward, in the order the phase feeds
			# them: a reader that only has the sum cannot tell a larder that
			# covers a small ward from one that covers none (DR-20261112-04).
			"hospital_demands": hospital_demands.duplicate(),
			"fed_workers": fed_workers,
			"strikers": strikers(),
			"fed_counts": fed_counts,
			"idle_counts": idle_counts,
			"idle_labour": idle_labour(),
			# The hands that landed at Build/work and labour from the next
			# Production phase, so a reader can say why the pool and the labour
			# figure differ (wiki: workers-and-population § Phase placement).
			"arriving": arriving.duplicate(),
			"labour_next_turn": labour_next_turn(),
			"luxury_spent": luxury_spent,
			"food_eaten": army_fed + navy_fed + hospital_fed + food_fed(),
		}


## Mutates the stockpile and returns the phase report used by the turn log and UI.
## `arriving` is the per-tier roster that landed at this turn's Build/work: it eats
## here but labours from the next Production phase (wiki:
## workers-and-population § Phase placement).
static func resolve(
	pool: WorkerPool,
	stockpile: Dictionary,
	ship_count: int,
	army_food: int = 0,
	hospital_demands: Array[int] = [],
	arriving: Array[int] = []
) -> Dictionary:
	return pass_over(
		pool, stockpile, ship_count, army_food, hospital_demands, arriving
	).serve().report()


## The phase's larder read, served or not. `resolve` and the pre-turn forecast
## both go through here, so neither can drift from the other's deduction order;
## a caller that only asks a question serves it over a copy (REQ-P2-03).
static func pass_over(
	pool: WorkerPool,
	stockpile: Dictionary,
	ship_count: int,
	army_food: int = 0,
	hospital_demands: Array[int] = [],
	arriving: Array[int] = []
) -> Pass:
	return Pass.new(pool, stockpile, ship_count, army_food, hospital_demands, arriving)



## The phase's own answer without spending the store: `resolve` over a copy, so
## the ledger can forecast a turn it has not taken yet (REQ-P2-03). The pool is
## only read, never changed, so the caller's roster is untouched.
static func preview(
	pool: WorkerPool,
	stockpile: Dictionary,
	ship_count: int,
	army_food: int = 0,
	hospital_demands: Array[int] = [],
	arriving: Array[int] = []
) -> Dictionary:
	return resolve(
		pool, stockpile.duplicate(), ship_count, army_food, hospital_demands, arriving
	)


## Fully fed hulls over hulls: each hull eats two food units, so a half-fed ship
## does not count. The next sea battle scales the crown's strength by this
## coverage (wiki: workers-and-population § Consumption).
static func navy_coverage(consumption: Dictionary) -> float:
	var demand: int = int(consumption.get("navy_demand", 0))
	if demand <= 0:
		return 1.0
	var ships: int = demand / ShipEconomy.FOOD_UPKEEP_PER_SHIP
	if ships <= 0:
		return 1.0
	var fed: int = int(consumption.get("navy_fed", 0))
	return clampf(
		float(fed / ShipEconomy.FOOD_UPKEEP_PER_SHIP) / float(ships), 0.0, 1.0
	)


## Food units the larder holds now: grain and meat, the same two the phase eats
## (wiki: workers-and-population § Consumption).
static func food_available(stockpile: Dictionary) -> int:
	var total: int = 0
	for id: String in CommodityCatalog.FOOD:
		total += maxi(int(stockpile.get(id, 0)), 0)
	return total


## Military, naval and peasant rations take one unit from grain before meat.
static func _eat_food(stockpile: Dictionary, demand: int) -> int:
	var remaining: int = maxi(demand, 0)
	var fed: int = 0
	for id: String in CommodityCatalog.FOOD:
		if remaining <= 0:
			break
		var have: int = int(stockpile.get(id, 0))
		var used: int = mini(have, remaining)
		stockpile[id] = have - used
		remaining -= used
		fed += used
	return fed


## One food unit of either kind feeds a worker at any tier: the published
## trained ration ("one grain and one meat") is trimmed once to the unit row
## as the #807 fallback dial, alongside the hulls' ration, and the forecast's
## `_rations` reads the same table so the phase and the ledger cannot drift
## (wiki: workers-and-population § Consumption; DR-20261116-08).
static func _feed_worker(stockpile: Dictionary, tier: int) -> bool:
	return _eat_food(stockpile, WorkerPool.FOOD_PER_WORKER[tier]) == (
		WorkerPool.FOOD_PER_WORKER[tier]
	)


## Rations a tier roster eats at one Consumption: a tier's workers times its
## per-worker ration.
static func _rations(counts: Array[int]) -> int:
	var total: int = 0
	for tier in WorkerPool.TIER_COUNT:
		total += counts[tier] * WorkerPool.FOOD_PER_WORKER[tier]
	return total
