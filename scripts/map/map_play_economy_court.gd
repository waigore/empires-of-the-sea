class_name MapPlayEconomyCourt
extends RefCounted
## One rival court's economy turn (docs/ai.md): plan income, research, works and
## trade against the store the phase will close with, then resolve extraction,
## market and production and book the orders the rules accept. `MapPlayEconomyAi`
## owns the pass; this object owns one court's ledger, so a court's plan and its
## application cannot drift apart (REQ-P2-03, REQ-P3-03).
##
## The footing, order of battle and larder are read once in `plan_turn`, so the
## projection the market stages against and the phase that closes the ledger
## read the same numbers.

var play: PlaySession
var faction: int
var market: WorldMarket
var kind: String
var economy: PlayerEconomy
var config: Variant

## Home yield plus colonial tonnage on home holds, and the cargo routes planned.
var overseas: Dictionary = {}
var cargo: Dictionary = {}
## The plan this court books: its money goal, production runs, research and trade.
var income: Dictionary = {}
var production: Dictionary = {}
var research: Dictionary = {}
var trade: Dictionary = {}
## The crews' plans and the stockpile rows they claim before the market stages.
var plans: Array[Dictionary] = []
var works_reserved: Dictionary = {}
## The raw the muster's and the hull's own material rows claim this turn: the
## stock the market keeps and manufacture plans around, read once in `plan_turn`
## (issue #484; wiki: growth-stage-planner § Recruitment modulation;
## DR-20261114-09).
var muster_row: Dictionary = {}
var navy_row: Dictionary = {}
## The cash the market must not spend: the price of the crew the hire order would
## take this turn, so a court that has lost a Builder can still buy one (issue
## #894).
var hire_margin: int = 0

## The reads the plan and the application share.
var at_war: bool = false
## The court's war footing this turn (DR-20261113-15): the dispatch table every
## domain planner reads its slot from (DR-20261117-01).
var phase: String = AiPhasePlanner.PHASE_UNKNOWN
var regiments: int = 0
var ships: int = 0
var warships: int = 0
var hull_chest: int = 0
var army_food: int = 0
var floor: int = 0
var boost: Dictionary = {}
var hospitals: Array[int] = []
var leader: String = ""
## The crown's best town in any province: the presence test the second-stage
## rows' works gate reads, so the plan and the phase agree on what may run
## (wiki: production-recipes § Town-works gates; DR-20261116-04).
var town_level: int = 0


## Opens one court's turn: its ledger, its opening civilians and its overseas
## yield, in the order the pass has always run them.
static func open(
	play: PlaySession, faction: int, market: WorldMarket
) -> MapPlayEconomyCourt:
	var court := MapPlayEconomyCourt.new()
	court.play = play
	court.faction = faction
	court.market = market
	court.kind = AiControl.court_kind(play, faction)
	court.economy = play.ai.economy_for(faction)
	court.config = AiBind.config(court.kind, faction, play.map_seed)
	court.town_level = TownIndustry.best_level(play.world, faction)
	MapPlayCivilianAi.seed(play, faction)
	court.overseas = MapPlayEconomyAi._overseas(play, faction, court.economy)
	return court


## Plans every order the court will book, applying nothing but the cargo routes
## and the market staging the phase has always staged before it closes.
func plan_turn() -> void:
	cargo = MapPlayCargoAi.run(play, faction, economy, overseas)
	at_war = MapPlayCourt.at_war(play, faction)
	# Routed through AiBind: a baseline court's config is a MainlineAiConfig,
	# which the submission planner's typed signature must never see. Since #853
	# the direct call crashed the baseline courts' whole economy pass every
	# turn — their rivals played no market, no production and no recruits
	# (issue #910).
	phase = AiBind.phase_for(kind, config, play.diplomacy)
	regiments = MapPlayCourt.regiments(play, faction)
	ships = MapPlayCourt.ships(play, faction)
	warships = MapPlayCourt.warships(play, faction)
	hull_chest = MapPlayCourt.navy_chest(play, faction)
	army_food = MapPlayEconomyAi._army_food(play, faction)
	leader = MapPlayEconomyAi._leader(play, faction)
	# The harvest slack the court's land carries — the ration food the
	# extraction just landed, less every mouth the consumption phase feeds
	# (issue #807). The muster's growth gate and the provision premium both read
	# it, so a court desires its larger army and provisions the food income
	# first; the economy pass re-notes it every turn.
	var harvest: Dictionary = overseas.get("extraction", {}) as Dictionary
	if not harvest.is_empty() and play.ai != null:
		# The harvest's ration food, counted the Consumption phase's way, so the
		# growth gate plans with the same total the phase would eat (REQ-P2-03).
		var harvest_food: int = EconomyConsumption.food_available(harvest)
		play.ai.note_food_slack(
			faction,
			harvest_food - MapPlayEconomyAi._food_demand(play, faction, economy)
		)
	# The goal the court plans with this turn: money first (DR-20261113-19).
	# The reserve is the muster it is saving for while it stands under its
	# regiment target, else its own cash floor; a court short of it is on
	# `earn` and every deferrable spend stands down while its income planners
	# lead. Every discretionary spend reads the same reserve, so the war chest
	# is never auctioned away for imports (wiki: growth-stage-planner
	# § Recruitment modulation; treasury-planner § Priority).
	income = AiBind.income_plan(
		kind, config, economy, at_war, regiments, hull_chest, warships,
		# A war chest the court has stalled on re-routes (#603).
		AiDeferral.stall_for(play.ai.deferrals, faction, "muster.line")
	)
	# The blunt earn-and-chest production skip (issue #484) froze every
	# manufacture — lumber, cast iron, cloth — for the whole save, so a
	# fleetless court could neither raise an estate nor fill the chest it was
	# saving for (#878). The rows the muster and the yard claim stand out of
	# manufacture's reach instead: the plan never promises a run whose inputs
	# would eat the regiment's cloth or the hull's lumber, and the court's own
	# works keep the manufactures they pay for.
	var pressure: Dictionary = AiVictoryPressure.read(
		play.world, faction, play.human_faction_id(), play.difficulty, config
	)
	muster_row = AiBind.muster_reserve(
		kind, config, economy, regiments, at_war, int(pressure["extra_regiments"])
	)
	navy_row = (
		AiNavy.due_row(
			at_war, warships, MapPlayCourt.hostile_warships(play, faction),
			economy, MapPlayCourt.hull_types(play, faction)
		)
		if hull_chest > 0 else {}
	)
	production = AiBind.production_orders(
		kind, config, economy, town_level, _chest_rows()
	)
	floor = int(income["reserve"])
	research = _plan_research()
	boost = MapPlaySpyAi.research_bonus(play, faction, economy)
	hospitals = HospitalRules.demand_list(play.world, faction)
	# The works a crew will start this turn are planned against the ledger
	# the phase will close with, so the market knows which feedstock they
	# need before it stages a sale: build, work and trade never spend the
	# same commodity twice (wiki: economy-planner § Reservations). The same
	# plans are applied once the phase has resolved.
	var projected: Dictionary = EconomyTurn.project(
		economy, market, overseas["extraction"] as Dictionary, ships,
		army_food, boost, hospitals, leader, town_level
	)
	# A court on `earn` still works its own land: extraction draws on the
	# cash floor, everything else waits for the muster (issue #489).
	var works_floor: int = (
		config.parameter("economy.min_treasury")
		if String(income["goal"]) == AiIncome.GOAL_EARN else -1
	)
	plans = MapPlayCivilianAi.plan_all(
		play, faction, economy, config, overseas,
		(projected["economy"] as PlayerEconomy).stockpile, floor, works_floor
	)
	works_reserved = MapPlayCivilianAi.work_rows(plans)
	hire_margin = _hire_margin()
	trade = _plan_trade()


## The raw the muster's and the hull's own material rows claim, merged: the
## stock manufacture plans around so a run never promises inputs the regiment
## or the yard must keep (issue #484, #878).
func _chest_rows() -> Dictionary:
	if navy_row.is_empty():
		return muster_row
	return MapPlayEconomyAi._merge_rows(muster_row, navy_row)


## The crew the hire order would take this turn, at the catalogue's price: the
## market keeps that cash back from its bids, so a court at its cash floor that
## has lost a Builder can still buy one (issue #894). Read from the home region's
## plan, which is where the court musters its crews.
func _hire_margin() -> int:
	# The baseline planners keep their published market: the margin is the
	# submission surface's own reading (AiBind).
	if kind == AiControl.KIND_BASELINE:
		return 0
	var home: int = FactionCatalog.region_of(faction)
	for entry: Dictionary in plans:
		if int(entry.get("region", -1)) != home:
			continue
		var plan: Dictionary = entry.get("plan", {})
		var next: String = String(plan.get("next_crew", ""))
		if next.is_empty():
			return 0
		return CivilianCatalog.treasury_cost(next)
	return 0


## Resolves the shared market and books this court's next production and
## recruits, then applies the crews' plans. Returns the court's report row.
func apply_turn() -> Dictionary:
	# The shared market clears once, after every court has staged its orders.
	var resolved: Dictionary = EconomyTurn.resolve(
		economy, market, overseas["extraction"] as Dictionary, ships, army_food,
		false, boost, hospitals, leader, town_level
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
		economy.production.set_assignment(
			String(assignment["recipe"]), int(assignment["units"])
		)
	# The muster hand reservation keeps `army.min_peasants` + the levy's own
	# hand in the fields while the muster is legal and funded (issue #807).
	# The baseline planner has no reading, so its rivals keep the old throttle.
	var hands: int = (
		AiArmyReinforce.muster_hands(config, economy, regiments, at_war)
		if kind != AiControl.KIND_BASELINE else 0
	)
	# The harvest, not just the pantry, carries the mouth (DR-20261116-14 reads
	# the harvest the muster plans with): a worker hired against a fat pantry
	# the land cannot carry strikes the month the store runs down, so training
	# also reads the slack the plan noted this turn (issue #878).
	var fed: int = AiBind.fed_slack(kind, economy, army_food, ships)
	if play.ai != null and (play.ai.food_slack as Dictionary).has(faction):
		fed = mini(fed, int(play.ai.food_slack[faction]))
	var recruits: Array[Dictionary] = AiBind.recruitment_orders(
		kind, config, economy, floor, fed, hands
	)
	for order: Dictionary in recruits:
		economy.recruit(int(order["tier"]))
	var civilians: Dictionary = MapPlayCivilianAi.apply(play, faction, economy, plans)
	return {
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


## What the court studies this turn: surplus above the money-first reserve,
## the navy unlock door first and the Tribe chain after it (issue #484, #490).
func _plan_research() -> Dictionary:
	var revealed: Dictionary = MapPlayCourtFog.research_revealed(play, faction)
	# Surplus research still leaves the money-first reserve alone; the standing
	# study alone may dip to the cash floor so a war-time court parked at 500
	# while saving 2,400 still learns (issue #490).
	var research_floor: int = AiBind.research_floor(kind, config)
	# Navy unlock door first, else Tribe chain (issue #484; DR-20261114-05).
	var door: String = ""
	if AiNavy.due(
		at_war, warships, MapPlayCourt.hostile_warships(play, faction)
	):
		door = AiNavy.unlock_tech(economy, MapPlayCourt.hull_types(play, faction))
	if door.is_empty():
		door = AiTribeColony.door(
			play.diplomacy, play.world, play.court_charts, faction,
			economy.tech_unlocked, phase
		)
	# The deed door, buyer-gated: a court that has a priced deed on its chart and
	# no Merchant Companies studies the tech that hires the buyer. The study is
	# the closed link — the hire, the envoy chain and the purchase all wait on it
	# (issue #841; wiki: civilian-units § Merchant).
	if door.is_empty():
		door = AiMerchantWork.deed_door(
			play.world, faction, play.court_charts, play.diplomacy,
			economy.tech_unlocked
		)
	return AiBind.research_plan(
		kind, config, economy,
		{
			"at_war": at_war,
			"revealed": revealed,
			"treasury_floor": floor,
			"cash_floor": research_floor,
			"door": door,
			"defer_standing": hull_chest > 0,  # yard fills before standing (#484)
		}
	)


## Sells above the reserve and this turn's inputs, then bids short build inputs
## with the holds the colonies left (wiki: world-market § Cargo). The cloth the
## next regiment must have is kept back and bid for first (wiki:
## growth-stage-planner § Recruitment modulation), and so is every material a
## crew's planned work will spend (wiki: economy-planner § Reservations).
func _plan_trade() -> Dictionary:
	var holds: int = (
		TradeCargo.capacity(play.world, play.ship_layer.regions.snapshot(), faction)
		if play.ship_layer != null else 0
	)
	var free_holds: int = maxi(
		holds - EconomyOverseas.shipped_total(overseas)
		- TradeCargo.used(market, faction),
		0
	)
	# The muster's material row and the hull's: read once in `plan_turn`, so
	# production, the market and the claims read one row apiece (issue #484).
	var need: Dictionary = muster_row
	# The hull the court is saving for holds its own material row beside the
	# muster's: a court that sells the last cloth it needs can save the whole
	# 5,500-ducat chest and still never lay the hull (issue #484). A chest that
	# has stood down (the yard re-routed to the muster, issue #603) holds no row
	# either, so the cloth it would have kept back is the regiment's.
	var navy: Dictionary = navy_row
	# The ration the larder cannot cover: a court that cannot feed its own people
	# is in the wiki's lock-recovery mode, so the market liquidates its hoard and
	# buys the missing food before any build input (wiki: treasury-planner
	# § Lock-recovery; issue #489). The reading is forward-looking — the larder
	# must cover this turn's ration and leave the next one in hand, because a
	# court that eats its last grain this turn strikes tomorrow.
	var food: int = MapPlayEconomyAi._food_demand(play, faction, economy)
	var food_short: int = maxi(food * 2 - EconomyConsumption.food_available(economy.stockpile), 0)
	# One primitive for every reservation: the rations, the muster's row, the
	# works and this turn's production are ranked claims, and the market reads
	# what the allocator funded (issue #491 T3, #498).
	var claims: Dictionary = AiClaims.reserve(MapPlayEconomyAi._claim_rows(
		production, food, economy, need, works_reserved, navy
	))
	var reserved: Dictionary = claims["reserved"]
	var saving: bool = String(income["goal"]) == AiIncome.GOAL_EARN
	# Market feedstock bids sit behind the war chest while the court is saving:
	# the civilian pass still draws extraction on the cash floor (#878), but the
	# bid book must not auction away the muster the earn goal is holding for —
	# otherwise a timber court spends every spare ducat on lumber/iron and the
	# chest never closes (#910 stall on seed 1500).
	var works_floor: int = floor if saving else -1
	# A court at war opens no speculative top-up: the slot is the footing's
	# (DR-20261117-01), and the published market fills the rest.
	var speculate: bool = AiPhasePlanner.opens(phase, AiPhasePlanner.SLOT_MARKET)
	var plan: Dictionary = AiBind.market_plan(
		kind, config, economy, market, free_holds, economy.tech_unlocked, reserved,
		MapPlayEconomyAi._merge_rows(need, navy), floor, food_short, saving,
		speculate, works_floor, hire_margin
	)
	plan["free_holds"] = free_holds
	var result: Dictionary = AiBind.market_stage(
		kind, economy, market, plan, faction, economy.tech_unlocked
	)
	result["plan"] = plan
	result["free_holds"] = free_holds
	result["claims"] = claims["lines"]
	# The bidding the footing held shut prints with its reason rather than going
	# quiet (REQ-P5-05; DR-20261117-01).
	if not speculate and int(plan.get("held", 0)) > 0:
		result["bids_blocked"] = AiMarketPlanner.REASON_SPECULATE
	return result
