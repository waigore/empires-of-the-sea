class_name EconomyTurn
extends RefCounted
## One turn of economy resolution: Extraction -> Riches to treasury -> Consumption
## -> Production, then world-market price discovery (wiki: stockpiles-and-production
## § Production flow). The same routine powers the end-of-turn projection so the UI
## never shows arithmetic the live resolution would not reproduce.

const TREASURY_COMMODITIES: Array[String] = ["gold", "silver", "gems", "diamonds", "spices"]


static func resolve(
	economy: PlayerEconomy,
	market: WorldMarket,
	extraction: Dictionary,
	ship_count: int,
	army_food: int = 0
) -> Dictionary:
	return _run(economy, market, extraction, ship_count, army_food, true)


## Dry run on copied state; reports stockpile and treasury deltas, no side effects.
static func project(
	economy: PlayerEconomy,
	market: WorldMarket,
	extraction: Dictionary,
	ship_count: int,
	army_food: int = 0
) -> Dictionary:
	var before: Dictionary = economy.stockpile.duplicate()
	var treasury_before: int = economy.treasury
	var report: Dictionary = _run(
		economy.copy(), market.copy(), extraction, ship_count, army_food, false
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
	advance_market: bool
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
	for id: String in TREASURY_COMMODITIES:
		var held: int = economy.quantity(id)
		if held <= 0:
			continue
		var gained: int = held * CommodityCatalog.base_price(id)
		economy.take(id, held)
		economy.add_treasury(gained)
		riches[id] = held
		riches_total += gained

	var consumption: Dictionary = EconomyConsumption.resolve(
		economy.workers, economy.stockpile, ship_count, army_food
	)
	var production: Dictionary = ProductionRecipes.plan(
		economy.assignments(),
		economy.stockpile,
		int(consumption["idle_labour"]),
		economy.tech_unlocked
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
		"prices": prices,
		"economy": economy,
		"market": market,
	}
