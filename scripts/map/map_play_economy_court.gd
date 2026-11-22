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
	court.config = AiBind.config(court.kind, faction, play.map_seed, ai.profiles)
	court.town_level = TownIndustry.best_level(play.world, faction)
	return court


## Plans every order the court will book, applying nothing but the cargo routes
## and the market staging the phase has always staged before it closes.
func plan_turn() -> void:
	cargo = MapPlayCargoAi.run(play, faction, economy, overseas)
	_note_larder()
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
		int(pressure["need"]) > 0
	)
	# The blunt earn-and-chest production skip (issue #484) froze every
	# manufacture — lumber, cast iron, cloth — for the whole save, so a
	# fleetless court could neither raise an estate nor fill the chest it was
	# saving for (#878). The rows the muster and the yard claim stand out of
	# manufacture's reach instead: the plan never promises a run whose inputs
	# would eat the regiment's cloth or the hull's lumber, and the court's own
	# works keep the manufactures they pay for.
	var chest: Dictionary = chest_rows(
		play, faction, kind, config, economy, at_war, regiments, warships,
		hull_chest, int(pressure["extra_regiments"])
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


## The harvest slack the court's land carries — the ration food the extraction
## just landed, less every mouth the consumption phase feeds (issue #807), or the
## `-2` sentinel when there is no harvest to read or no AI pass beside it. The
## muster's growth gate and the provision premium both read it, so a court
## desires its larger army and provisions the food income first. Pure: the
## reading the pass notes and the worker hire reads are the same figure
## (REQ-P2-03; DR-20261122-01).
func harvest_slack() -> int:
	var harvest: Dictionary = overseas.get("extraction", {}) as Dictionary
	if harvest.is_empty() or play.ai == null or economy == null:
		return -2
	# The harvest's ration food, counted the Consumption phase's way, so the
	# growth gate plans with the same total the phase would eat (REQ-P2-03).
	var harvest_food: int = EconomyConsumption.food_available(harvest)
	return harvest_food - MapPlayEconomyLarder.food_demand(play, faction, economy)


## Notes the harvest slack the muster's gate plans with. The economy pass notes
## it every turn, before the crews' plans read it; a sheet that only names the
## plan leaves the note to the pass (DR-20261121-09).
func _note_larder() -> void:
	var slack: int = harvest_slack()
	if slack == -2:
		return
	play.ai.note_food_slack(faction, slack)


## The larder slack the worker hire reads: the harvest's own figure narrowed by
## the pass's note when there is no harvest in hand — the `-1` sentinel (no
## larder to read) is the published default. `AiBindEconomy.fed_slack` is the
## call `apply_turn` has always hired against (issue #489; DR-20261122-01).
func fed_slack() -> int:
	var fed: int = AiBindEconomy.fed_slack(kind, economy, army_food, ships)
	if play.ai != null and (play.ai.food_slack as Dictionary).has(faction):
		fed = mini(fed, int(play.ai.food_slack[faction]))
	return fed


## The harvest slack the hire reads: this turn's own figure where the land has a
## harvest to count, else the pass's own note, else the `-2` sentinel (no
## reading). The one home for the figure `apply_turn` hires against.
func _harvest_reading() -> int:
	var slack: int = harvest_slack()
	if slack == -2 and play.ai != null:
		return int(play.ai.food_slack.get(faction, -2))
	return slack


## The hand the worker hire keeps in the fields: the muster's own reservation
## (issue #807) plus the peasant the yard keeps for the hull it is banking
## (issue #1126), so a court that musters buys no worker its levy would consume.
func muster_hands() -> int:
	if kind == AiControl.KIND_BASELINE:
		return 0
	var navy_hand: int = AiNavy.hands(
		economy, MapPlayCourt.hull_types(play, faction), hull_chest
	)
	return AiArmyReinforce.muster_hands(config, economy, regiments, at_war) + navy_hand


## The workers this court's pass recruits this phase — the `recruitment_orders` call
## `apply_turn` books, read here once so the pass and the WORKERS tab's counsel
## cannot hire two different pools (REQ-P2-03; DR-20261122-01). A reading:
## nothing here enlists a worker or spends a ducat.
##
## `harvest` is the larder's harvest slack the hire paces itself by: the pass
## hands the figure it noted at plan time, so its own hire is unchanged, and a
## sheet naming the plan before the close hands `harvest_slack()` — the figure
## the next plan turn will note, because the note is taken before the phase
## resolves.
func recruit_orders(harvest: int) -> Array[Dictionary]:
	return AiBindEconomy.recruitment_orders(
		kind, config, economy, floor, fed_slack(), muster_hands(), conquest_bank,
		harvest
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
	extra_regiments: int
) -> Dictionary:
	var muster: Dictionary = AiBindEconomy.muster_reserve(
		kind, config, economy, regiments, at_war, extra_regiments
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
		"held": MapPlayEconomyLarder.merge_rows(muster, navy),
	}


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
	for assignment: Dictionary in production["assignments"]:
		economy.production.set_assignment(
			String(assignment["recipe"]), int(assignment["units"])
		)
	# The workers the pass buys this phase — the muster's hand, the yard's crew and
	# the larder's slack all read inside `recruit_orders`, the one home the
	# WORKERS tab's counsel reads too (REQ-P2-03; DR-20261122-01).
	var recruits: Array[Dictionary] = recruit_orders(_harvest_reading())
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
			"harvest": int(play.ai.food_slack.get(faction, -2)) if play.ai != null else -2,
		},
	}
