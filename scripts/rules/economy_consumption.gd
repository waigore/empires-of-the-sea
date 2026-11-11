class_name EconomyConsumption
extends RefCounted
## Consumption phase (wiki: workers-and-population § Consumption). Deduction order is
## army, then navy, then workers; workers are fed in full rations from the highest
## tier down, and a worker who misses food or their tier luxury strikes for the turn
## without leaving the pool. Idle workers supply the next Production phase's labour.

const FEED_ORDER: Array[int] = [
	WorkerPool.Tier.MASTER,
	WorkerPool.Tier.JOURNEYMAN,
	WorkerPool.Tier.APPRENTICE,
	WorkerPool.Tier.PEASANT,
]


## Mutates the stockpile and returns the phase report used by the turn log and UI.
static func resolve(
	pool: WorkerPool,
	stockpile: Dictionary,
	ship_count: int,
	army_food: int = 0
) -> Dictionary:
	var army_demand: int = maxi(army_food, 0)
	var army_fed: int = _eat_food(stockpile, army_demand)
	var navy_demand: int = maxi(ship_count, 0) * ShipEconomy.FOOD_UPKEEP_PER_SHIP
	var navy_fed: int = _eat_food(stockpile, navy_demand)

	var idle_counts: Array[int] = [0, 0, 0, 0]
	var fed_counts: Array[int] = [0, 0, 0, 0]
	for tier: int in FEED_ORDER:
		for _index in pool.count(tier):
			if not _feed_worker(stockpile, tier):
				break
			fed_counts[tier] += 1

	var luxury_spent: Dictionary = {}
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

	var fed_workers: int = 0
	var idle_labour: int = 0
	var idle_total: int = 0
	for tier in WorkerPool.TIER_COUNT:
		fed_workers += fed_counts[tier]
		idle_total += idle_counts[tier]
		idle_labour += idle_counts[tier] * WorkerPool.LABOUR_PER_WORKER[tier]

	return {
		"army_demand": army_demand,
		"army_fed": army_fed,
		"navy_demand": navy_demand,
		"navy_fed": navy_fed,
		"fed_workers": fed_workers,
		"strikers": pool.total() - idle_total,
		"fed_counts": fed_counts,
		"idle_counts": idle_counts,
		"idle_labour": idle_labour,
		"luxury_spent": luxury_spent,
		"food_eaten": army_fed + navy_fed + _worker_rations(fed_counts),
	}


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


## Trained workers need one grain and one meat; peasants need a single food unit.
static func _feed_worker(stockpile: Dictionary, tier: int) -> bool:
	if not WorkerPool.is_trained(tier):
		return _eat_food(stockpile, 1) == 1
	for id: String in CommodityCatalog.FOOD:
		if int(stockpile.get(id, 0)) < 1:
			return false
	for id: String in CommodityCatalog.FOOD:
		stockpile[id] = int(stockpile.get(id, 0)) - 1
	return true


static func _worker_rations(fed_counts: Array[int]) -> int:
	var total: int = 0
	for tier in WorkerPool.TIER_COUNT:
		total += fed_counts[tier] * WorkerPool.FOOD_PER_WORKER[tier]
	return total
