class_name MapPlayEconomyAi
extends RefCounted
## Rival economy turn (docs/ai.md): resolves extraction, market and production
## for every rival, driving `AiEconomyPlanner` / `AiMarketPlanner` and applying
## the legal orders, and reports the trace (REQ-P2-03, REQ-P3-03).
##
## The civilian pass lives in `MapPlayCivilianAi`; this file keeps the ledger
## side (overseas yield, food, trade) so neither pass owns the other's domain.

## Resolves every rival economy once, then plans the next turn. Call after the
## Build/Work pass and before the player's own economy so both read the works
## that just completed.
static func run(play: PlaySession) -> Dictionary:
	var report: Dictionary = {"factions": {}, "orders": []}
	if play == null or play.world == null or play.civilian_layer == null:
		return report
	play.ensure_ai()
	var by_faction: Dictionary = report["factions"]
	var order_log: Array = report["orders"]
	var market: WorldMarket = _market(play)
	var factions: Array[int] = FactionCatalog.great_power_ids()
	# Every rival ledger exists before any court resolves, so a spy observing a
	# court later in the order still reads its known techs this turn.
	MapPlaySpyAi.prepare_ledgers(play)
	for faction: int in factions:
		if faction == play.player_faction and not play.observer_mode:
			continue
		var economy: PlayerEconomy = play.ai.economy_for(faction)
		MapPlayCivilianAi.seed(play, faction)
		var overseas: Dictionary = _overseas(play, faction, economy)
		var config: AiConfig = AiConfig.build(faction, play.map_seed)
		var cargo: Dictionary = MapPlayCargoAi.run(play, faction, economy, overseas)
		var revealed: Dictionary = MapPlayCourtFog.research_revealed(play, faction)
		var production: Dictionary = AiEconomyPlanner.production_orders(config, economy)
		var trade: Dictionary = _trade(play, faction, economy, config, market, overseas, production)
		# Plan before the phase resolves, so the study starts this turn.
		var research: Dictionary = AiResearchPlanner.plan(
			config, economy, {"at_war": _at_war(play, faction), "revealed": revealed}
		)
		# The shared market clears once, after every court has staged its orders.
		var resolved: Dictionary = EconomyTurn.resolve(
			economy, market, overseas["extraction"] as Dictionary, _ships(play, faction),
			_army_food(play, faction), false,
			MapPlaySpyAi.research_bonus(play, faction, economy)
		)
		economy.clear_assignments()
		for assignment: Dictionary in production["assignments"]:
			economy.set_assignment(String(assignment["recipe"]), int(assignment["units"]))
		var recruits: Array[Dictionary] = AiEconomyPlanner.recruitment_orders(config, economy)
		for order: Dictionary in recruits:
			economy.recruit(int(order["tier"]))
		var civilians: Dictionary = MapPlayCivilianAi.run(
			play, faction, economy, config, overseas
		)
		order_log.append_array(civilians["orders"])
		by_faction[faction] = {
			"extraction": overseas["extraction"],
			"resolved": resolved,
			"production": production,
			"trade": trade,
			"cargo": cargo,
			"recruits": recruits,
			"civilians": civilians,
			"research": research,
		}
	return report


# --- economy -----------------------------------------------------------------


## Home yield plus colonial tonnage on home holds, with hold accounting for the
## market pass (wiki: extraction-and-improvements).
static func _overseas(
	play: PlaySession, faction: int, economy: PlayerEconomy
) -> Dictionary:
	var works_by_region: MapRegionTable = play.civilian_layer.works_regions
	var tech_caps: Dictionary = TechCatalog.extraction_caps(economy.tech_unlocked)
	var home_region: int = FactionCatalog.region_of(faction)
	if home_region < 0:
		home_region = WorldMap.OLD_WORLD
	var home: Dictionary = {}
	var home_model: MapModel = play.world.region(home_region)
	if home_model != null and works_by_region.value(home_region, null) != null:
		var works: LandWorks = works_by_region.value(home_region, null)
		var capital: Dictionary = WorldBootstrap.capital_seat(home_model, faction)
		home = Extraction.yields(
			home_model, faction, int(capital["province"]), tech_caps, works,
			capital["tile"], economy.tech_unlocked
		)
	var holds: int = (
		TradeCargo.capacity(play.world, play.ship_layer.regions.snapshot(), faction)
		if play.ship_layer != null else 0
	)
	var plan: Dictionary = EconomyOverseas.delivered(
		home, play.world, home_region, faction, tech_caps, works_by_region, holds,
		economy.tech_unlocked
	)
	plan["home_region"] = home_region
	return plan


static func _market(play: PlaySession) -> WorldMarket:
	if play.economy != null and play.economy.market != null:
		return play.economy.market
	return WorldMarket.with_default_prices()


## Sells above the reserve and this turn's inputs, then bids short build inputs
## with the holds the colonies left (wiki: world-market § Cargo).
static func _trade(
	play: PlaySession,
	faction: int,
	economy: PlayerEconomy,
	config: AiConfig,
	market: WorldMarket,
	overseas: Dictionary,
	production: Dictionary
) -> Dictionary:
	var holds: int = (
		TradeCargo.capacity(play.world, play.ship_layer.regions.snapshot(), faction)
		if play.ship_layer != null else 0
	)
	var free_holds: int = maxi(
		holds - EconomyOverseas.shipped_total(overseas)
		- TradeCargo.used(market, faction),
		0
	)
	var reserved: Dictionary = _reserved_inputs(
		production, _food_demand(play, faction, economy)
	)
	var current: Dictionary = _reserved_inputs({"assignments": economy.assignments()})
	for commodity: Variant in current.keys():
		var id: String = String(commodity)
		reserved[id] = int(reserved.get(id, 0)) + int(current[commodity])
	var plan: Dictionary = AiMarketPlanner.plan(
		config, economy, market, free_holds, economy.tech_unlocked, reserved
	)
	plan["free_holds"] = free_holds
	var result: Dictionary = AiMarketPlanner.stage(
		economy, market, plan, faction, economy.tech_unlocked
	)
	result["plan"] = plan
	result["free_holds"] = free_holds
	return result


## Inputs this turn's production promised, plus food the consumption phase eats,
## so a sale never starves the court or spends a commodity twice.
static func _reserved_inputs(production: Dictionary, food: int = 0) -> Dictionary:
	var reserved: Dictionary = {}
	if food > 0:
		reserved["grain"] = food
	for raw: Variant in production.get("assignments", []):
		var assignment: Dictionary = raw
		var units: int = int(assignment.get("units", 0))
		if units <= 0:
			continue
		var inputs: Dictionary = ProductionRecipes.inputs(String(assignment.get("recipe", "")))
		for commodity: Variant in inputs.keys():
			var id: String = String(commodity)
			reserved[id] = int(reserved.get(id, 0)) + int(inputs[commodity]) * units
	return reserved


static func _ships(play: PlaySession, faction: int) -> int:
	if play.ship_layer == null:
		return 0
	return play.ship_layer.hull_count_all(faction)


## Food this court will eat before Production: army, navy and every worker
## ration (wiki: workers-and-population § Consumption).
static func _food_demand(
	play: PlaySession, faction: int, economy: PlayerEconomy
) -> int:
	var demand: int = _army_food(play, faction)
	demand += _ships(play, faction) * ShipEconomy.FOOD_UPKEEP_PER_SHIP
	for tier in WorkerPool.TIER_COUNT:
		demand += economy.workers.count(tier) * WorkerPool.FOOD_PER_WORKER[tier]
	return demand


static func _army_food(play: PlaySession, faction: int) -> int:
	if play.army_layer == null:
		return 0
	return play.army_layer.food_upkeep_all(faction)


static func _at_war(play: PlaySession, faction: int) -> bool:
	if play.diplomacy == null:
		return false
	for record: DiplomacyRelation in play.diplomacy.relations_of(faction):
		if record.at_war:
			return true
	return false
