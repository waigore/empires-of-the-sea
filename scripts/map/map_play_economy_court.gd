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
## read the same numbers. Research and trade live in `MapPlayEconomyCourtBook`.

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
## The pre-market treasury delta the last plan projected (issue #995's probe):
## what the phase itself moves before the shared book clears.
var projected_treasury: int = 0

## The reads the plan and the application share.
var at_war: bool = false
## The court's war footing this turn (DR-20261113-15): the dispatch table every
## domain planner reads its slot from (DR-20261117-01).
var phase: String = AiPhasePlanner.PHASE_UNKNOWN
## True while this court banks for the army its conquest still needs (issue
## #995): on `earn` and short of the bar, the works purse and the college's
## doors draw on the bank, not the cash floor.
var conquest_bank: bool = false
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
	# Every discretionary spend reads the same reserve, so the war chest is
	# never auctioned away for imports (wiki: treasury-planner § Priority).
	# A court short of the bar banks at peace too (issue #995): the conquest
	# shortfall is the trigger, not the war.
	var pressure: Dictionary = AiVictoryPressure.read(
		play.world, faction, play.human_faction_id(), play.difficulty, config
	)
	income = AiBindEconomy.income_plan(
		kind, config, economy, at_war, regiments, hull_chest, warships,
		# A war chest the court has stalled on re-routes (#603).
		AiDeferral.stall_for(play.ai.deferrals, faction, "muster.line"),
		# The win-bar reading the bank rides on (issue #995).
		int(pressure["need"]) > 0
	)
	# The blunt earn-and-chest production skip (issue #484) froze every
	# manufacture — lumber, cast iron, cloth — for the whole save, so a
	# fleetless court could neither raise an estate nor fill the chest it was
	# saving for (#878). The rows the muster and the yard claim stand out of
	# manufacture's reach instead: the plan never promises a run whose inputs
	# would eat the regiment's cloth or the hull's lumber, and the court's own
	# works keep the manufactures they pay for.
	muster_row = AiBindEconomy.muster_reserve(
		kind, config, economy, regiments, at_war, int(pressure["extra_regiments"])
	)
	navy_row = (
		AiNavy.due_row(
			at_war, warships, MapPlayCourt.hostile_warships(play, faction),
			economy, MapPlayCourt.hull_types(play, faction)
		)
		if hull_chest > 0 else {}
	)
	production = AiBindEconomy.production_orders(
		kind, config, economy, town_level, _chest_rows()
	)
	floor = int(income["reserve"])
	# The conquest bank (issue #995): the canonical read — the gap, the host
	# and the purse, never the money goal (which wobbles on the re-route
	# cycle). Baselines keep their published doctrine.
	conquest_bank = (
		kind != AiControl.KIND_BASELINE
		and AiIncome.banking(config, play.ai, income)
	)
	research = MapPlayEconomyCourtBook.research(self)
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
	# The pre-market treasury delta the trace's flow row reports (issue #995's
	# probe), read before the shared book clears the staged offers and bids.
	projected_treasury = int(projected.get("treasury_delta", 0))
	# A court on `earn` still works its own land: extraction draws on the
	# cash floor, everything else waits for the muster (issue #489). The
	# conquest bank keeps that purse open for its farms (issue #995) — a
	# court that cannot buy the lumber its farms spend stops carrying the
	# mouth the levy needs. The deeds and chains that could eat the same
	# purse wait behind the bank's own gates instead.
	var works_floor: int = (
		config.parameter("economy.min_treasury")
		if String(income["goal"]) == AiIncome.GOAL_EARN else -1
	)
	plans = MapPlayCivilianAi.plan_all(
		play, faction, economy, config, overseas,
		(projected["economy"] as PlayerEconomy).stockpile, floor, works_floor,
		conquest_bank
	)
	works_reserved = MapPlayCivilianAi.work_rows(plans)
	hire_margin = MapPlayEconomyCourtBook.hire_margin(self)
	trade = MapPlayEconomyCourtBook.trade(self)


## The raw the muster's and the hull's own material rows claim, merged: the
## stock manufacture plans around so a run never promises inputs the regiment
## or the yard must keep (issue #484, #878).
func _chest_rows() -> Dictionary:
	if navy_row.is_empty():
		return muster_row
	return MapPlayEconomyAi._merge_rows(muster_row, navy_row)


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
	var fed: int = AiBindEconomy.fed_slack(kind, economy, army_food, ships)
	if play.ai != null and (play.ai.food_slack as Dictionary).has(faction):
		fed = mini(fed, int(play.ai.food_slack[faction]))
	# The conquest bank rides the worker buys (issue #995): the harvest slack
	# rides beside it (issue #1059) — the pace the hires keep is the pace the
	# muster's own ration gate plans with.
	var recruits: Array[Dictionary] = AiBindEconomy.recruitment_orders(
		kind, config, economy, floor, fed, hands, conquest_bank,
		int(play.ai.food_slack.get(faction, -2)) if play.ai != null else -2
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
		# The pre-market delta and the labour pool the levy reads (issue
		# #995's probe rows).
		"projected": projected_treasury,
		"pool": {
			"workers": economy.workers.total(),
			"peasants": economy.workers.count(WorkerPool.Tier.PEASANT),
			"available": economy.available_peasants(),
			"harvest": int(play.ai.food_slack.get(faction, -2)) if play.ai != null else -2,
		},
	}
