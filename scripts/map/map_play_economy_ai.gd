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
	# Every rival ledger exists before any court resolves, so a spy observing a
	# court later in the order still reads its known techs this turn.
	MapPlaySpyAi.prepare_ledgers(play)
	for faction: int in MapPlayCourt.planning_factions(play):
		var economy: PlayerEconomy = play.ai.economy_for(faction)
		MapPlayCivilianAi.seed(play, faction)
		var overseas: Dictionary = _overseas(play, faction, economy)
		var config: AiConfig = AiConfig.build(faction, play.map_seed)
		var cargo: Dictionary = MapPlayCargoAi.run(play, faction, economy, overseas)
		var revealed: Dictionary = MapPlayCourtFog.research_revealed(play, faction)
		var production: Dictionary = AiEconomyPlanner.production_orders(config, economy)
		var at_war: bool = MapPlayCourt.at_war(play, faction)
		var regiments: int = MapPlayCourt.regiments(play, faction)
		# The goal the court plans with this turn: money first (DR-20261113-19).
		# The reserve is the muster it is saving for while it stands under its
		# regiment target, else its own cash floor; a court short of it is on
		# `earn` and every deferrable spend stands down while its income planners
		# lead. Every discretionary spend reads the same reserve, so the war chest
		# is never auctioned away for imports (wiki: growth-stage-planner
		# § Recruitment modulation; treasury-planner § Priority).
		var income: Dictionary = AiIncome.plan(
			config, economy, at_war, regiments, MapPlayCourt.navy_chest(play, faction)
		)
		var floor: int = int(income["reserve"])
		# Surplus research still leaves the money-first reserve alone; the standing
		# study alone may dip to the cash floor so a war-time court parked at 500
		# while saving 2,400 still learns (issue #490).
		var research_floor: int = AiResearchPlanner.research_floor(config)
		# Plan before the phase resolves, so the study starts this turn.
		var research: Dictionary = AiResearchPlanner.plan(
			config, economy,
			{
				"at_war": at_war,
				"revealed": revealed,
				"treasury_floor": floor,
				"cash_floor": research_floor,
			}
		)
		var boost: Dictionary = MapPlaySpyAi.research_bonus(play, faction, economy)
		var hospitals: Array[int] = HospitalRules.demand_list(play.world, faction)
		# The works a crew will start this turn are planned against the ledger
		# the phase will close with, so the market knows which feedstock they
		# need before it stages a sale: build, work and trade never spend the
		# same commodity twice (wiki: economy-planner § Reservations). The same
		# plans are applied once the phase has resolved.
		var projected: Dictionary = EconomyTurn.project(
			economy, market, overseas["extraction"] as Dictionary, MapPlayCourt.ships(play, faction),
			_army_food(play, faction), boost, hospitals, _leader(play, faction)
		)
		# A court on `earn` still works its own land: extraction draws on the
		# cash floor, everything else waits for the muster (issue #489).
		var works_floor: int = (
			config.parameter("economy.min_treasury")
			if String(income["goal"]) == AiIncome.GOAL_EARN else -1
		)
		var plans: Array[Dictionary] = MapPlayCivilianAi.plan_all(
			play, faction, economy, config, overseas,
			(projected["economy"] as PlayerEconomy).stockpile, floor, works_floor
		)
		var works_reserved: Dictionary = MapPlayCivilianAi.work_rows(plans)
		var trade: Dictionary = _trade(
			play, faction, economy, config, market, overseas, production,
			works_reserved, floor
		)
		# The shared market clears once, after every court has staged its orders.
		var resolved: Dictionary = EconomyTurn.resolve(
			economy, market, overseas["extraction"] as Dictionary, MapPlayCourt.ships(play, faction),
			_army_food(play, faction), false, boost, hospitals, _leader(play, faction)
		)
		# A rival's wards eat in the same pass as the crown's: whole staffs, seat
		# first, and the flags they set are what its next rest tick reads
		# (wiki: combat § Regiment condition; DR-20261112-04).
		HospitalRules.feed(
			play.world, faction,
			int((resolved.get("consumption", {}) as Dictionary).get("hospital_fed", 0))
		)
		economy.production.clear_assignments()
		for assignment: Dictionary in production["assignments"]:
			economy.production.set_assignment(String(assignment["recipe"]), int(assignment["units"]))
		var recruits: Array[Dictionary] = AiEconomyPlanner.recruitment_orders(
			config, economy, floor
		)
		for order: Dictionary in recruits:
			economy.recruit(int(order["tier"]))
		var civilians: Dictionary = MapPlayCivilianAi.apply(play, faction, economy, plans)
		order_log.append_array(civilians["orders"])
		by_faction[faction] = {
			"extraction": overseas["extraction"],
			"resolved": resolved,
			"production": production,
			"trade": trade,
			"cargo": cargo,
			"recruits": recruits,
			"civilians": civilians,
			"works_reserved": works_reserved,
			"claims": trade.get("claims", []),
			"research": research,
			"income": income,
		}
	# Every rival ledger just closed, so the next land battle reads the rations
	# each crown actually got — not full morale by default (wiki: combat
	# § Feeding modifiers; workers-and-population § Consumption). Observer mode
	# still reapplies from MapPlayTurn; a second pass is idempotent.
	AiTurnLog.apply_feeding(play, report)
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
	var capital: Dictionary = {"province": -1, "tile": CivilianState.NO_TILE}
	var home_model: MapModel = play.world.region(home_region)
	# The crown's own sealed ports reach its ledger the way the player's do
	# (wiki: capital-and-connectivity § Blockade; DR-20261110-13 equal rule).
	var seals: Blockades = MapPlayBlockades.of(play, faction)
	if home_model != null and works_by_region.value(home_region, null) != null:
		var works: LandWorks = works_by_region.value(home_region, null)
		capital = WorldBootstrap.capital_seat(home_model, faction)
		home = Extraction.yields(
			home_model, faction, int(capital["province"]), tech_caps, works,
			capital["tile"], economy.tech_unlocked, true, {}, seals
		)
	var holds: int = (
		TradeCargo.capacity(play.world, play.ship_layer.regions.snapshot(), faction)
		if play.ship_layer != null else 0
	)
	var plan: Dictionary = EconomyOverseas.delivered(
		home, play.world, home_region, faction, tech_caps, works_by_region, holds,
		economy.tech_unlocked, seals
	)
	plan["home_region"] = home_region
	return plan


static func _market(play: PlaySession) -> WorldMarket:
	if play.economy != null and play.economy.market != null:
		return play.economy.market
	return WorldMarket.with_default_prices()


## Sells above the reserve and this turn's inputs, then bids short build inputs
## with the holds the colonies left (wiki: world-market § Cargo). The cloth the
## next regiment must have is kept back and bid for first (wiki:
## growth-stage-planner § Recruitment modulation), and so is every material a
## crew's planned work will spend (wiki: economy-planner § Reservations).
static func _trade(
	play: PlaySession,
	faction: int,
	economy: PlayerEconomy,
	config: AiConfig,
	market: WorldMarket,
	overseas: Dictionary,
	production: Dictionary,
	works: Dictionary = {},
	floor: int = 0
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
	var need: Dictionary = AiArmyReinforce.muster_reserve(
		config, economy, MapPlayCourt.regiments(play, faction),
		MapPlayCourt.at_war(play, faction),
		int(AiVictoryPressure.read(
			play.world, faction, play.human_faction_id(), play.difficulty, config
		)["extra_regiments"])
	)
	# The ration the larder cannot cover: a court that cannot feed its own people
	# is in the wiki's lock-recovery mode, so the market liquidates its hoard and
	# buys the missing food before any build input (wiki: treasury-planner
	# § Lock-recovery; issue #489). The reading is forward-looking — the larder
	# must cover this turn's ration and leave the next one in hand, because a
	# court that eats its last grain this turn strikes tomorrow.
	var food: int = _food_demand(play, faction, economy)
	var food_short: int = maxi(food * 2 - _food_held(economy), 0)
	# One primitive for every reservation: the rations, the muster's row, the
	# works and this turn's production are ranked claims, and the market reads
	# what the allocator funded (issue #491 T3, #498).
	var claims: Dictionary = AiClaims.reserve(_claim_rows(
		production, food, economy, need, works
	))
	var reserved: Dictionary = claims["reserved"]
	var plan: Dictionary = AiMarketPlanner.plan(
		config, economy, market, free_holds, economy.tech_unlocked, reserved, need,
		floor, food_short
	)
	plan["free_holds"] = free_holds
	var result: Dictionary = AiMarketPlanner.stage(
		economy, market, plan, faction, economy.tech_unlocked
	)
	result["plan"] = plan
	result["free_holds"] = free_holds
	result["claims"] = claims["lines"]
	return result


## The named rows one turn reserves, in the order the market must keep stock.
## Each row is an `AiObjective` cost: the ration the consumption phase eats
## (grain first, holding what the court actually has), the inputs this turn's
## production promised, the row the next regiment is provisioned with, every
## material the crews' planned works will spend, and the inputs the orders
## already booked hold (wiki: workers-and-population § Consumption;
## DR-20261112-04; growth-stage-planner § Recruitment modulation;
## economy-planner § Reservations).
static func _claim_rows(
	production: Dictionary,
	food: int = 0,
	economy: PlayerEconomy = null,
	muster: Dictionary = {},
	works: Dictionary = {}
) -> Array[Dictionary]:
	var rows: Dictionary = {
		AiClaims.RATIONS: _ration_row(food, economy),
		AiClaims.PRODUCTION: _production_row(production),
		AiClaims.MUSTER: muster,
		AiClaims.WORKS: works,
		AiClaims.KEPT: (
			_production_row({"assignments": economy.production.assignments()})
			if economy != null else {}
		),
	}
	return AiClaims.sources(rows)


## The ration row: grain, then meat, holding only what the court actually has of
## each so a court whose larder is meat does not sell its regiments' dinner.
static func _ration_row(food: int, economy: PlayerEconomy) -> Dictionary:
	var row: Dictionary = {}
	var ration: int = maxi(food, 0)
	for id: String in CommodityCatalog.FOOD:
		if ration <= 0:
			break
		var held: int = maxi(economy.quantity(id), 0) if economy != null else ration
		var kept: int = mini(ration, held)
		if kept > 0:
			row[id] = kept
		ration -= kept
	return row


## The material row a production plan promised: recipe inputs × units.
static func _production_row(production: Dictionary) -> Dictionary:
	var row: Dictionary = {}
	for raw: Variant in production.get("assignments", []):
		var assignment: Dictionary = raw
		var units: int = int(assignment.get("units", 0))
		if units <= 0:
			continue
		var inputs: Dictionary = ProductionRecipes.inputs(String(assignment.get("recipe", "")))
		for commodity: Variant in inputs.keys():
			var id: String = String(commodity)
			row[id] = int(row.get(id, 0)) + int(inputs[commodity]) * units
	return row


## The merged reservation the market keeps back. Kept as the published shape so
## the economy suites and any caller read the same dictionary as before.
static func _reserved_inputs(
	production: Dictionary,
	food: int = 0,
	economy: PlayerEconomy = null,
	muster: Dictionary = {},
	works: Dictionary = {}
) -> Dictionary:
	return AiClaims.reserve(_claim_rows(production, food, economy, muster, works))["reserved"]


## Food the larder already holds: the two ration commodities, grain first.
static func _food_held(economy: PlayerEconomy) -> int:
	if economy == null:
		return 0
	var held: int = 0
	for id: String in CommodityCatalog.FOOD:
		held += maxi(economy.quantity(id), 0)
	return held


## Food this court will eat before Production: army, navy, every worker ration
## and every hospital staff (wiki: workers-and-population § Consumption;
## combat § Regiment condition).
static func _food_demand(
	play: PlaySession, faction: int, economy: PlayerEconomy
) -> int:
	var demand: int = _army_food(play, faction)
	demand += MapPlayCourt.ships(play, faction) * ShipEconomy.FOOD_UPKEEP_PER_SHIP
	for ration: int in HospitalRules.demand_list(play.world, faction):
		demand += ration
	for tier in WorkerPool.TIER_COUNT:
		demand += economy.workers.count(tier) * WorkerPool.FOOD_PER_WORKER[tier]
	return demand


static func _army_food(play: PlaySession, faction: int) -> int:
	if play.army_layer == null:
		return 0
	return play.army_layer.food_upkeep_all(faction)


## The rival's leaderKey, whose published funding multiplier lifts its research
## points (wiki: leader-bonuses § Bonus Table — Victoria).
static func _leader(play: PlaySession, faction: int) -> String:
	return String(play.leaders.get(faction, ""))
