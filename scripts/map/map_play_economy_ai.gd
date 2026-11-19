class_name MapPlayEconomyAi
extends RefCounted
## Rival economy turn (docs/ai.md): resolves extraction, market and production
## for every rival, driving `AiEconomyPlanner` / `AiMarketPlanner` and applying
## the legal orders, and reports the trace (REQ-P2-03, REQ-P3-03).
##
## One court's plan and its application live in `MapPlayEconomyCourt`, so a
## court's ledger turns once and its report row cannot drift from the orders it
## booked. The civilian pass lives in `MapPlayCivilianAi`; this file keeps the
## ledger side (overseas yield, food, reservations) so neither pass owns the
## other's domain.

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
		var row: Dictionary = _court_row(play, faction, market)
		order_log.append_array((row.get("civilians", {}) as Dictionary).get("orders", []))
		by_faction[faction] = row
	# Every rival ledger just closed, so the next land battle reads the rations
	# each crown actually got — not full morale by default (wiki: combat
	# § Feeding modifiers; workers-and-population § Consumption). Observer mode
	# still reapplies from MapPlayTurn; a second pass is idempotent.
	AiTurnLog.apply_feeding(play, report)
	return report


## One court's row: a BENCH filler draws seeded random legal orders, a planned
## court runs its full economy turn through `MapPlayEconomyCourt`.
static func _court_row(play: PlaySession, faction: int, market: WorldMarket) -> Dictionary:
	if AiControl.court_kind(play, faction) == AiControl.KIND_RANDOM:
		var economy: PlayerEconomy = play.ai.economy_for(faction)
		MapPlayCivilianAi.seed(play, faction)
		return AiRandomCourt.economy(play, faction, market, _overseas(play, faction, economy))
	var court: MapPlayEconomyCourt = MapPlayEconomyCourt.open(play, faction, market)
	court.plan_turn()
	return court.apply_turn()


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
		TradeCargo.home_holds(play.world, play.ship_layer.regions.snapshot(), faction)
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


## The named rows one turn reserves, in the order the market must keep stock.
## Each row is an `AiObjective` cost: the ration the consumption phase eats
## (grain first, holding what the court actually has), the inputs this turn's
## production promised, the row the next regiment is provisioned with, the row
## the hull the court is saving for needs, every material the crews' planned
## works will spend, and the inputs the orders already booked hold (wiki:
## workers-and-population § Consumption; DR-20261112-04; growth-stage-planner
## § Recruitment modulation; economy-planner § Reservations; issue #484).
static func _claim_rows(
	production: Dictionary,
	food: int = 0,
	economy: PlayerEconomy = null,
	muster: Dictionary = {},
	works: Dictionary = {},
	navy: Dictionary = {}
) -> Array[Dictionary]:
	var rows: Dictionary = {
		AiClaims.RATIONS: _ration_row(food, economy),
		AiClaims.PRODUCTION: _production_row(production),
		AiClaims.MUSTER: muster,
		AiClaims.NAVY: navy,
		AiClaims.WORKS: works,
		AiClaims.KEPT: (
			_production_row({"assignments": economy.production.assignments()})
			if economy != null else {}
		),
	}
	return AiClaims.sources(rows)


## Two material rows added together: the muster's cloth and the hull's, so the
## market bids for both before the rest of the build inputs (issue #484).
static func _merge_rows(left: Dictionary, right: Dictionary) -> Dictionary:
	if right.is_empty():
		return left
	var merged: Dictionary = left.duplicate()
	for commodity: Variant in right.keys():
		var id: String = String(commodity)
		merged[id] = int(merged.get(id, 0)) + int(right[commodity])
	return merged


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
	works: Dictionary = {},
	navy: Dictionary = {}
) -> Dictionary:
	return AiClaims.reserve(_claim_rows(production, food, economy, muster, works, navy))["reserved"]


## Food this court will eat before Production: army, navy, every worker ration
## and every hospital staff (wiki: workers-and-population § Consumption;
## combat § Regiment condition). The mouths are `LarderRead`'s own, so the
## court's shortfall and the phase's bill name one total (issue #489; REQ-P2-03).
static func _food_demand(
	play: PlaySession, faction: int, economy: PlayerEconomy
) -> int:
	var read: Dictionary = LarderRead.reading(
		economy.workers,
		economy.stockpile,
		{
			"army": _army_food(play, faction),
			"ships": MapPlayCourt.ships(play, faction),
			"wards": HospitalRules.demand_list(play.world, faction),
		}
	)
	var appetites: Dictionary = read["appetites"]
	return (
		int(appetites["army"]) + int(appetites["navy"])
		+ int(appetites["pool"]) + int(appetites["wards"])
	)


static func _army_food(play: PlaySession, faction: int) -> int:
	if play.army_layer == null:
		return 0
	return play.army_layer.food_upkeep_all(faction)


## The rival's leaderKey, whose published funding multiplier lifts its research
## points (wiki: leader-bonuses § Bonus Table — Victoria).
static func _leader(play: PlaySession, faction: int) -> String:
	return String(play.leaders.get(faction, ""))
