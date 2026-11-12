class_name EconomyTurn
extends RefCounted
## One turn of economy resolution: Extraction -> Riches to treasury -> Consumption
## -> Production, then world-market price discovery (wiki: stockpiles-and-production
## § Production flow). The same routine powers the end-of-turn projection so the UI
## never shows arithmetic the live resolution would not reproduce.


## `advance_market` is false for rival courts sharing one world market: the
## player's own resolution moves prices once per turn. `hospital_demands` is the
## ordered ration of every hospital staff in the crown, seat first
## (DR-20261112-04).
static func resolve(
	economy: PlayerEconomy,
	market: WorldMarket,
	extraction: Dictionary,
	ship_count: int,
	army_food: int = 0,
	advance_market: bool = true,
	research_boost: Dictionary = {},
	hospital_demands: Array[int] = []
) -> Dictionary:
	return _run(
		economy, market, extraction, ship_count, army_food, advance_market,
		research_boost, hospital_demands
	)


## Dry run on copied state; reports stockpile and treasury deltas, no side effects.
static func project(
	economy: PlayerEconomy,
	market: WorldMarket,
	extraction: Dictionary,
	ship_count: int,
	army_food: int = 0,
	research_boost: Dictionary = {},
	hospital_demands: Array[int] = []
) -> Dictionary:
	var before: Dictionary = economy.stockpile.duplicate()
	var treasury_before: int = economy.treasury
	var report: Dictionary = _run(
		economy.copy(), market.copy(), extraction, ship_count, army_food, false,
		research_boost, hospital_demands
	)
	var deltas: Dictionary = {}
	for id: String in CommodityCatalog.all_ids():
		var delta: int = int(report["economy"].stockpile.get(id, 0)) - int(before.get(id, 0))
		if delta != 0:
			deltas[id] = delta
	report["stockpile_delta"] = deltas
	report["treasury_delta"] = int(report["economy"].treasury) - treasury_before
	return report


static func _run(
	economy: PlayerEconomy,
	market: WorldMarket,
	extraction: Dictionary,
	ship_count: int,
	army_food: int,
	advance_market: bool,
	research_boost: Dictionary = {},
	hospital_demands: Array[int] = []
) -> Dictionary:
	var extracted: Dictionary = {}
	for commodity: Variant in extraction.keys():
		var id: String = String(commodity)
		var amount: int = int(extraction[commodity])
		if amount > 0:
			economy.add(id, amount)
			extracted[id] = amount

	var riches: Dictionary = {}
	var riches_total: int = 0
	for id: String in CommodityCatalog.treasury_ids():
		var held: int = economy.quantity(id)
		if held <= 0:
			continue
		var gained: int = held * CommodityCatalog.base_price(id)
		economy.take(id, held)
		economy.add_treasury(gained)
		riches[id] = held
		riches_total += gained

	var consumption: Dictionary = EconomyConsumption.resolve(
		economy.workers, economy.stockpile, ship_count, army_food, hospital_demands
	)
	# The next sea battle reads how many hulls this turn's granary fed in full
	# (wiki: workers-and-population § Consumption).
	economy.navy_feeding = EconomyConsumption.navy_coverage(consumption)
	var production: Dictionary = ProductionRecipes.plan(
		economy.assignments(),
		economy.stockpile,
		int(consumption["idle_labour"]),
		economy.tech_unlocked,
		economy.production_wip
	)
	# The workshop rides into the next turn: multi-turn batches keep serving
	# until their output lands (DR-20261112-11).
	economy.production_wip = (production.get("wip", {}) as Dictionary).duplicate(true)
	# Research runs last: its gold comes out of the treasury Production left.
	var research: Dictionary = ResearchTurn.resolve(
		economy.research, economy, research_boost
	)
	var prices: Dictionary = {}
	if advance_market:
		prices = market.advance_prices()

	return {
		"extraction": extracted,
		"riches": riches,
		"riches_treasury": riches_total,
		"consumption": consumption,
		"production": production,
		"research": research,
		"prices": prices,
		"economy": economy,
		"market": market,
	}
