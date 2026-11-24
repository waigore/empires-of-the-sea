class_name MapPlayEconomyCourt
extends RefCounted
## One rival court's economy turn (docs/ai.md): plan income, research, works and
## trade against the store the phase will close with, then resolve extraction,
## market and production and book the orders the rules accept. The pass
## (`MapPlayEconomyAi`) opens the court; this object owns one court's ledger, so
## a court's plan and its application cannot drift apart (REQ-P2-03, REQ-P3-03).
##
## The footing, order of battle and larder are read once in `plan_turn`, so the
## projection the market stages against and the phase that closes the ledger
## read the same numbers. Research and trade live in `MapPlayEconomyCourtBook`;
## the yield, the food demand and the reservation rows in `MapPlayEconomyLarder`.

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
## True while the court's own bank (issue #995) holds the works purse and the
## college's doors on the cash floor.
var conquest_bank: bool = false
## True while the money goal reads `earn` on the submission surface (issue
## #1384): the split that names the bank's income investments — the studies
## and the region's own crews that lead while the chest itself keeps its
## claim on the deferrable purchases.
var invest_bank: bool = false
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
	var court: MapPlayEconomyCourt = _base(play, faction, market)
	MapPlayCivilianAi.seed(play, faction)
	court.overseas = MapPlayEconomyLarder.overseas(play, faction, court.economy)
	return court


## The same reads `open` takes, and none of its seeding: a sheet that only names
## the plan (`MapPlayMarketPick`) may not mint a crew the crown never hired
## (wiki: world-market § Trade orders; DR-20261121-09).
static func draft(
	play: PlaySession, faction: int, market: WorldMarket
) -> MapPlayEconomyCourt:
	var court: MapPlayEconomyCourt = _base(play, faction, market)
	court.overseas = MapPlayEconomyLarder.overseas(play, faction, court.economy)
	return court


static func _base(
	play: PlaySession, faction: int, market: WorldMarket
) -> MapPlayEconomyCourt:
	var court := MapPlayEconomyCourt.new()
	court.play = play
	court.faction = faction
	court.market = market
	court.kind = AiControl.court_kind(play, faction)
	# The court's ledger from the session's one home: the crown's own ledger for
	# the human's faction, a rival's from the AI. `ai.economy_for` would hand the
	# crown a fresh opening copy that no pass ever resolves, so every pick read a
	# ledger a hundred turns behind the sheet it answered — the WORKERS tab said
	# `would recruit 1 Peasant` beside a pool of 20 (wiki:
	# workers-and-population § Recruiting; DR-20261121-09, DR-20261122-01).
	var ledger: PlayerEconomy = play.ledger_for(faction)
	var ai: AiState = play.ensure_ai()
	court.economy = ledger if ledger != null else ai.economy_for(faction)
	# The court's one shared run config (issue #1356), so the rows this pass
	# reads carry the same storm reading the muster pass notes.
	court.config = ai.court_config(court.kind, faction, play.map_seed, ai.profiles)
	court.town_level = TownIndustry.best_level(play.world, faction)
	return court


## Plans every order the court will book, applying nothing but the cargo routes
## and the market staging the phase has always staged before it closes.
func plan_turn() -> void:
	cargo = MapPlayCargoAi.run(play, faction, economy, overseas)
	MapPlayEconomyLarder.note(self)
	rehearse()
	# The college's book is the pass's own: the research planner writes the
	# research state (its slots, the revealed set, a refund), so a sheet that
	# only names the plan may not take it (DR-20261121-09).
	research = MapPlayEconomyCourtBook.research(self)
	trade = MapPlayEconomyCourtBook.trade(self)


## Every read the court's plan takes, and nothing it books: the footing, the
## order of battle, the chest, the purse and the crews' plans. The pass reads
## them after its cargo walk and its larder note; a sheet that only names the
## plan (`MapPlayMarketPick`) reads them through `draft` and this method, so the
## trade the sheet names and the trade the pass stages come from one set of
## figures (wiki: world-market § Trade orders; DR-20261121-09).
func rehearse() -> void:
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
	army_food = MapPlayEconomyLarder.army_food(play, faction)
	leader = MapPlayEconomyCourtBook.leader(play, faction)
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
		int(pressure["need"]) > 0,
		# The storm chest the thinnest wall ahead prices (issue #1381): the
		# same read the muster pass banks, on the one shared config.
		MapPlayArmyMusterAi.storm_chest(play, play.model, faction, regiments)
	)
	# The blunt earn-and-chest production skip (issue #484) froze every
	# manufacture — lumber, cast iron, cloth — for the whole save, so a
	# fleetless court could neither raise an estate nor fill the chest it was
	# saving for (#878). The rows the muster and the yard claim stand out of
	# manufacture's reach instead: the plan never promises a run whose inputs
	# would eat the regiment's cloth or the hull's lumber, and the court's own
	# works keep the manufactures they pay for.
	var chest: Dictionary = MapPlayEconomyLarder.chest_rows(
		play, faction, kind, config, economy, at_war, regiments, warships,
		hull_chest, int(pressure["extra_regiments"]), int(income["storm_bank"])
	)
	muster_row = chest["muster_row"] as Dictionary
	navy_row = chest["navy_row"] as Dictionary
	production = AiBindEconomy.production_orders(
		kind, config, economy, town_level, chest["held"] as Dictionary
	)
	floor = int(income["reserve"])
	# The conquest bank (issue #995): the canonical read — the gap, the host
	# and the purse, never the money goal (which wobbles on the re-route
	# cycle). Baselines keep their published doctrine.
	conquest_bank = (
		kind != AiControl.KIND_BASELINE
		and AiIncome.banking(config, play.ai, income)
	)
	# The bank's own split (issue #1384): the money goal names the court's
	# money first, and the readers that priced the whole stand-down off it
	# held the college and the hire shut while the chest filled. This flag
	# is the investments' half: the studies and the region's own crews lead
	# while the chest keeps its claim on the deferrable purchases — the bid
	# book, the deed, a new war. Baselines keep their published doctrine.
	invest_bank = (
		kind != AiControl.KIND_BASELINE
		and AiIncome.invests(config, play.ai, income)
	)
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
	works_reserved = MapPlayCivilianPlan.work_rows(plans)
	hire_margin = MapPlayEconomyCourtBook.hire_margin(self)


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
	var row: Dictionary = book_orders()
	row["resolved"] = resolved
	return row


## Books every order the plan files — the production runs, the workers the
## Build/work phase buys and the crews' work orders — and closes no ledger. The
## Auto seat books the crown's household through this and lets the crown's own
## `resolve_turn` carry the orders out (wiki: auto-mode § The crown's household;
## REQ-P2-03); `apply_turn` adds a rival's resolution to the same row.
func book_orders() -> Dictionary:
	economy.production.clear_assignments()
	for assignment: Dictionary in production.get("assignments", []):
		economy.production.set_assignment(
			String(assignment["recipe"]), int(assignment["units"])
		)
	# The workers the pass buys this phase — the muster's hand, the yard's crew and
	# the larder's slack all read inside `recruit_orders`, the one home the
	# WORKERS tab's counsel reads too (REQ-P2-03; DR-20261122-01).
	var recruits: Array[Dictionary] = MapPlayEconomyLarder.recruit_orders(
		self, MapPlayEconomyLarder.harvest_reading(self)
	)
	for order: Dictionary in recruits:
		economy.recruit(int(order["tier"]))
	var civilians: Dictionary = MapPlayCivilianAi.apply(play, faction, economy, plans)
	return {
		"extraction": overseas["extraction"],
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
			"harvest": MapPlayEconomyLarder.noted_slack(play, faction),
		},
	}
