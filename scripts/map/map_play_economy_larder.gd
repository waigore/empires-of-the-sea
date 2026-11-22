class_name MapPlayEconomyLarder
extends RefCounted
## A court's larder reads and the rows the market must keep for it (docs/ai.md):
## the home and colonial yield, the food the phase will eat, and the ranked
## reservation rows the market plans around (REQ-P2-03, REQ-P3-01).
##
## These were loose helpers on the rival pass (`MapPlayEconomyAi`), reached from
## one court's turn (`MapPlayEconomyCourt`, `MapPlayEconomyCourtBook`) and from
## the crown's own picks (`MapPlayCivilianPick`, `MapPlayHirePick`) as private
## names. They belong to the ledger side, not to the pass that walks the rivals,
## so they live here and the pass owns only its walk (REQ-P3-02).


## Home yield plus colonial tonnage on home holds, with hold accounting for the
## market pass (wiki: extraction-and-improvements).
static func overseas(play: PlaySession, faction: int, economy: PlayerEconomy) -> Dictionary:
	var works_by_region: MapRegionTable = play.civilian_layer.works_regions
	var tech_caps: Dictionary = TechCatalog.extraction_caps(economy.tech_unlocked)
	var home_region: int = maxi(FactionCatalog.region_of(faction), 0)
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
	# The crossing reads the home squadron's holds, never the seat harbour's
	# trade allowance: a court with no merchant hull in port at its capital lands
	# nothing abroad, however many turns its yards still owe it
	# (wiki: ships-and-naval § Cargo holds and capacity — "the home squadron's
	# merchant hulls are the only holds"; DR-20261114-11).
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


## The market the session trades on: the crown's own when it keeps a ledger, else
## the published default prices a court plans against (wiki: world-market).
static func market(play: PlaySession) -> WorldMarket:
	if play.economy != null and play.economy.market != null:
		return play.economy.market
	return WorldMarket.with_default_prices()


## Food this court will eat before Production: army, navy, every worker ration
## and every hospital staff (wiki: workers-and-population § Consumption;
## combat § Regiment condition). The mouths are `LarderRead`'s own, so the
## court's shortfall and the phase's bill name one total (issue #489; REQ-P2-03).
static func food_demand(
	play: PlaySession, faction: int, economy: PlayerEconomy
) -> int:
	var read: Dictionary = LarderRead.reading(
		economy.workers,
		economy.stockpile,
		{
			"army": army_food(play, faction),
			"ships": MapPlayCourt.ships(play, faction),
			"wards": HospitalRules.demand_list(play.world, faction),
		}
	)
	var appetites: Dictionary = read["appetites"]
	return (
		int(appetites["army"]) + int(appetites["navy"])
		+ int(appetites["pool"]) + int(appetites["wards"])
	)


## The rations this court's army eats a turn (wiki: combat § Feeding modifiers).
static func army_food(play: PlaySession, faction: int) -> int:
	if play.army_layer == null:
		return 0
	return play.army_layer.food_upkeep_all(faction)


## The named rows one turn reserves, in the order the market must keep stock.
## Each row is an `AiObjective` cost: the ration the consumption phase eats
## (grain first, holding what the court actually has), the inputs this turn's
## production promised, the row the next regiment is provisioned with, the row
## the hull the court is saving for needs, every material the crews' planned
## works will spend, and the inputs the orders already booked hold (wiki:
## workers-and-population § Consumption; DR-20261112-04; growth-stage-planner
## § Recruitment modulation; economy-planner § Reservations; issue #484).
static func claim_rows(
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


## The merged reservation the market keeps back. Kept as the published shape so
## the economy suites and any caller read the same dictionary as before.
static func reserved_inputs(
	production: Dictionary,
	food: int = 0,
	economy: PlayerEconomy = null,
	muster: Dictionary = {},
	works: Dictionary = {},
	navy: Dictionary = {}
) -> Dictionary:
	var rows: Array[Dictionary] = claim_rows(
		production, food, economy, muster, works, navy
	)
	return AiClaims.reserve(rows)["reserved"]


## Two material rows added together: the muster's cloth and the hull's, so the
## market bids for both before the rest of the build inputs (issue #484).
static func merge_rows(left: Dictionary, right: Dictionary) -> Dictionary:
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
