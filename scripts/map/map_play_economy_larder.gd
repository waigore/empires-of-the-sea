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


## The harvest slack the court's land carries: the ration food the extraction
## just landed, less every mouth the consumption phase feeds (issue #807), or the
## `-2` sentinel when there is no harvest to read or no AI pass beside it. The
## muster's growth gate and the provision premium both read it, so a court
## desires its larger army and provisions the food income first (REQ-P2-03;
## DR-20261122-01).
static func harvest_slack(
	play: PlaySession, faction: int, overseas: Dictionary, economy: PlayerEconomy
) -> int:
	var harvest: Dictionary = overseas.get("extraction", {}) as Dictionary
	if harvest.is_empty() or play.ai == null or economy == null:
		return -2
	# The harvest's ration food, counted the Consumption phase's way, so the
	# growth gate plans with the same total the phase would eat (REQ-P2-03).
	return EconomyConsumption.food_available(harvest) - food_demand(play, faction, economy)


## Notes the harvest slack the muster's gate plans with. The economy pass notes
## it every turn, before the crews' plans read it; a sheet that only names the
## plan leaves the note to the pass (DR-20261121-09).
static func note(court: MapPlayEconomyCourt) -> void:
	var slack: int = harvest_slack(
		court.play, court.faction, court.overseas, court.economy
	)
	if slack == -2:
		return
	court.play.ai.note_food_slack(court.faction, slack)


## The larder slack the worker hire reads: the harvest's own figure narrowed by
## the pass's note when there is no harvest in hand — the `-1` sentinel (no
## larder to read) is the published default. `AiBindEconomy.fed_slack` is the
## call `apply_turn` has always hired against (issue #489; DR-20261122-01).
static func fed_slack(court: MapPlayEconomyCourt) -> int:
	var fed: int = AiBindEconomy.fed_slack(
		court.kind, court.economy, court.army_food, court.ships
	)
	var noted: Dictionary = (
		court.play.ai.food_slack as Dictionary
		if court.play.ai != null else {}
	)
	# The note narrows the hire whenever the pass noted one — a starved land
	# feeds no extra mouth (issue #489).
	if noted.has(court.faction):
		fed = mini(fed, int(noted[court.faction]))
	return fed


## The harvest slack the hire reads: this turn's own figure where the land has a
## harvest to count, else the pass's own note, else the `-2` sentinel (no
## reading). The one home for the figure `apply_turn` hires against.
static func harvest_reading(court: MapPlayEconomyCourt) -> int:
	var slack: int = harvest_slack(
		court.play, court.faction, court.overseas, court.economy
	)
	if slack == -2:
		return noted_slack(court.play, court.faction)
	return slack


## The workers this court's pass recruits this phase — the `recruitment_orders`
## call `apply_turn` books, read here once so the pass and the WORKERS tab's
## counsel cannot hire two different pools (REQ-P2-03; DR-20261122-01). A
## reading: nothing here enlists a worker or spends a ducat.
##
## `harvest` is the harvest slack the hire paces itself by: the pass hands the
## figure it noted at plan time, so its own hire is unchanged, and a sheet
## naming the plan before the close hands `harvest_reading` — the figure the
## next plan turn will note, because the note is taken before the phase closes.
static func recruit_orders(
	court: MapPlayEconomyCourt, harvest: int
) -> Array[Dictionary]:
	return AiBindEconomy.recruitment_orders(
		court.kind, court.config, court.economy, court.floor, fed_slack(court),
		muster_hands(court), court.conquest_bank, harvest
	)


## The hand the worker hire keeps in the fields: the muster's own reservation
## (issue #807) plus the peasant the yard keeps for the hull it is banking
## (issue #1126), so a court that musters buys no worker its levy would consume.
static func muster_hands(court: MapPlayEconomyCourt) -> int:
	if court.kind == AiControl.KIND_BASELINE:
		return 0
	var navy_hand: int = AiNavy.hands(
		court.economy, MapPlayCourt.hull_types(court.play, court.faction),
		court.hull_chest
	)
	return (
		AiArmyReinforce.muster_hands(
			court.config, court.economy, court.regiments, court.at_war
		) + navy_hand
	)


## The raw the muster's and the hull's own material rows claim, merged: the
## stock manufacture plans around so a run never promises inputs the regiment
## or the yard must keep (issue #484, #878). One home, read by the pass and by
## the sheet that names the plan, so the two cannot claim different chests
## (REQ-P2-03; DR-20261121-07).
static func chest_rows(
	play: PlaySession,
	faction: int,
	kind: String,
	config: Variant,
	economy: PlayerEconomy,
	at_war: bool,
	regiments: int,
	warships: int,
	hull_chest: int,
	extra_regiments: int,
	storm_bank: int = 0
) -> Dictionary:
	var muster: Dictionary = AiBindEconomy.muster_reserve(
		kind, config, economy, regiments, at_war, extra_regiments, storm_bank
	)
	var navy: Dictionary = (
		AiNavy.due_row(
			at_war, warships, MapPlayCourt.hostile_warships(play, faction),
			economy, MapPlayCourt.hull_types(play, faction)
		)
		if hull_chest > 0 else {}
	)
	return {
		"muster_row": muster,
		"navy_row": navy,
		"held": merge_rows(muster, navy),
	}


## The larder slack the economy pass noted for this court, or the `-2` sentinel
## (no reading) when the pass has not noted one — the one home for the figure the
## hire, the muster, the cargo walk and the court's report row all read
## (issues #489, #807; DR-20261122-01).
static func noted_slack(play: PlaySession, faction: int) -> int:
	if play == null or play.ai == null:
		return -2
	return int(play.ai.food_slack.get(faction, -2))


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
