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

## The reads the plan and the application share.
var at_war: bool = false
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
	regiments = MapPlayCourt.regiments(play, faction)
	ships = MapPlayCourt.ships(play, faction)
	warships = MapPlayCourt.warships(play, faction)
	hull_chest = MapPlayCourt.navy_chest(play, faction)
	army_food = MapPlayEconomyAi._army_food(play, faction)
	leader = MapPlayEconomyAi._leader(play, faction)
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
	# Skip production buys while earning for the navy chest (issue #484).
	production = (
		{"assignments": []}
		if hull_chest > 0 and String(income["goal"]) == AiIncome.GOAL_EARN
		else AiBind.production_orders(kind, config, economy, town_level)
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
	trade = _plan_trade()


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
	var recruits: Array[Dictionary] = AiBind.recruitment_orders(
		kind, config, economy, floor,
		AiBind.fed_slack(kind, economy, army_food, ships)
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
			economy.tech_unlocked, AiPhasePlanner.phase_for(config, play.diplomacy)
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
	var need: Dictionary = AiBind.muster_reserve(
		kind, config, economy, regiments, at_war,
		int(AiVictoryPressure.read(
			play.world, faction, play.human_faction_id(), play.difficulty, config
		)["extra_regiments"])
	)
	# The hull the court is saving for holds its own material row beside the
	# muster's: a court that sells the last cloth it needs can save the whole
	# 5,500-ducat chest and still never lay the hull (issue #484). A chest that
	# has stood down (the yard re-routed to the muster, issue #603) holds no row
	# either, so the cloth it would have kept back is the regiment's.
	var navy: Dictionary = (
		AiNavy.due_row(
			at_war, warships, MapPlayCourt.hostile_warships(play, faction),
			economy, MapPlayCourt.hull_types(play, faction)
		)
		if hull_chest > 0 else {}
	)
	# The ration the larder cannot cover: a court that cannot feed its own people
	# is in the wiki's lock-recovery mode, so the market liquidates its hoard and
	# buys the missing food before any build input (wiki: treasury-planner
	# § Lock-recovery; issue #489). The reading is forward-looking — the larder
	# must cover this turn's ration and leave the next one in hand, because a
	# court that eats its last grain this turn strikes tomorrow.
	var food: int = MapPlayEconomyAi._food_demand(play, faction, economy)
	var food_short: int = maxi(food * 2 - MapPlayEconomyAi._food_held(economy), 0)
	# One primitive for every reservation: the rations, the muster's row, the
	# works and this turn's production are ranked claims, and the market reads
	# what the allocator funded (issue #491 T3, #498).
	var claims: Dictionary = AiClaims.reserve(MapPlayEconomyAi._claim_rows(
		production, food, economy, need, works_reserved, navy
	))
	var reserved: Dictionary = claims["reserved"]
	var saving: bool = String(income["goal"]) == AiIncome.GOAL_EARN
	var plan: Dictionary = AiBind.market_plan(
		kind, config, economy, market, free_holds, economy.tech_unlocked, reserved,
		MapPlayEconomyAi._merge_rows(need, navy), floor, food_short, saving
	)
	plan["free_holds"] = free_holds
	var result: Dictionary = AiBind.market_stage(
		kind, economy, market, plan, faction, economy.tech_unlocked
	)
	result["plan"] = plan
	result["free_holds"] = free_holds
	result["claims"] = claims["lines"]
	return result
