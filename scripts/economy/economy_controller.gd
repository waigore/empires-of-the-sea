class_name EconomyController
extends Node
## Mounts the crown's economy on the map screen: builds the opening ledger, runs
## the end-of-turn phases and repaints the sheet.
##
## The figures the sheet prints belong to [LedgerReadings]; every ledger and
## college button press belongs to [LedgerOrders]. This node owns the mount, the
## turn and the panel surface — never a rule (REQ-P3-01, REQ-P2-03).

signal treasury_changed(value: int)

var model: MapModel = null
var economy: PlayerEconomy = null
var market: WorldMarket = null
var player_faction: int = 0
var capital_province: int = -1
var capital_tile: Vector2i = CivilianState.NO_TILE
var works: LandWorks = null
## The session this ledger belongs to; Build/work's queued recruits land here,
## before the new turn's Consumption (wiki: workers-and-population
## § Phase placement).
var play: PlaySession = null

var ship_layer: ShipLayer = null
var army_layer: ArmyLayer = null
var hud: GameHud = null
## Every region's works, so overseas estates yield (DR-20261109-17).
var works_by_region: MapRegionTable = null
## Tech id -> percent the crown's spy network adds this Research phase, set by
## the turn helper before resolution (wiki: civilian-units § Spy;
## DR-20261110-03). Empty when no spy sits in a rival Great Power's province.
var research_boost: Dictionary = {}
## Reads the court's sealed ports (wiki: capital-and-connectivity § Blockade).
## MapPlayBlockades owns the reading — it needs the fleets and the wars — so the
## controller only asks for it while it prices the harvest (REQ-P2-03).
var blockade_source: Callable = Callable()
## The crown's leaderKey, fixed at game start; its published funding multiplier
## lifts the research points the phase earns (wiki: leader-bonuses — Victoria).
var leader_key: String = ""
## The figures the sheet prints this turn (harvest, cargo, projection).
var readings: LedgerReadings = null
## The ledger's and the college's button presses, as intents.
var orders: LedgerOrders = null
## Last world-market clearing receipt; owned by [member readings], exposed here
## so map helpers keep one ledger handle (REQ-P3-01).
var last_clearing: Dictionary:
	get:
		return readings.last_clearing if readings != null else {}
	set(value):
		if readings != null:
			readings.last_clearing = value


func _init() -> void:
	readings = LedgerReadings.new(self)
	orders = LedgerOrders.new(self)


## Thin pass-throughs: callers that only need a figure keep talking to this
## node; the reading still has one owner (REQ-P3-01).
func fleet_ships() -> int:
	return readings.fleet_ships() if readings != null else 0


func tech_caps() -> Dictionary:
	return readings.tech_caps() if readings != null else {}


func army_food() -> int:
	return readings.army_food() if readings != null else 0


func trade_cargo() -> Dictionary:
	return readings.trade_cargo() if readings != null else {}


func cargo_holds() -> int:
	return readings.cargo_holds() if readings != null else 0


func overseas_plan() -> Dictionary:
	return readings.overseas_plan() if readings != null else {}


func feeding_coverage() -> float:
	return readings.feeding_coverage() if readings != null else 1.0


func extraction() -> Dictionary:
	return readings.extraction() if readings != null else {}


func projected() -> Dictionary:
	return readings.projected() if readings != null else {}


func projected_income() -> int:
	return readings.projected_income() if readings != null else 0


func _on_worker_action(tier: int, action: String) -> void:
	if orders != null:
		orders.worker_action(tier, action)


func setup(
	p_model: MapModel,
	p_faction: int,
	p_capital: int,
	p_ships: ShipLayer,
	p_armies: ArmyLayer,
	p_hud: GameHud,
	p_works: LandWorks = null,
	p_capital_tile: Vector2i = CivilianState.NO_TILE,
	p_leader: String = ""
) -> void:
	model = p_model
	player_faction = p_faction
	capital_province = p_capital
	capital_tile = p_capital_tile
	works = p_works
	ship_layer = p_ships
	army_layer = p_armies
	hud = p_hud
	leader_key = p_leader
	economy = PlayerEconomy.starting()
	market = WorldMarket.with_default_prices()
	_connect()
	MinorMarket.publish(
		market, ship_layer.world if ship_layer != null else null, player_faction
	)


## The ledger and the college press their own orders straight into the intent
## owner; this node only gives them the panels to live on.
func _connect() -> void:
	if hud == null:
		return
	hud.economy_pressed.connect(open_panel)
	hud.research_pressed.connect(open_research)
	var panel: EconomyPanel = hud.panels.economy_panel
	panel.trade_requested.connect(orders.trade)
	panel.offer_requested.connect(orders.offer)
	panel.cancel_requested.connect(orders.withdraw)
	panel.production_changed.connect(orders.set_production)
	panel.recruit_requested.connect(
		func(tier: int, count: int) -> void: orders.worker_action(tier, "recruit", count)
	)
	panel.disband_requested.connect(orders.worker_action.bind("disband"))
	var research: ResearchPanel = hud.panels.research_panel
	research.assign_requested.connect(orders.assign_research)
	research.cancel_requested.connect(orders.cancel_research)
	research.funding_requested.connect(orders.cycle_research_funding)
	research.funding_all_requested.connect(orders.fund_research_all)


## Runs Build/work's recruits, then Extraction -> Riches -> Consumption ->
## Production, and refreshes the HUD.
func resolve_turn() -> Dictionary:
	# The crown's queued orders land before the new turn's Consumption, so a hand
	# hired now eats with the court at this turn's close; the mustered units stand
	# for the next Orders phase. They land after the fighting this turn ordered,
	# so a regiment mustered now never fights in its own turn.
	# The hands that land eat this turn's larder but labour the **next**
	# Production phase: a Build/work recruit never supplies same-turn labour
	# (wiki: workers-and-population § Phase placement). The arrivals are read
	# from Build/work's own records, after the queue has drained: an order the
	# turn cannot keep never lands, and a hand that never landed must not take
	# an idle worker's labour with it.
	var musters: Array[Dictionary] = MapPlayRecruits.complete(play) if play != null else []
	var leaving: Array[int] = MapPlayRecruits.arriving_tiers(musters)
	var before: int = economy.treasury
	var plan: Dictionary = readings.overseas_plan()
	var world: WorldMap = ship_layer.world if ship_layer != null else null
	# The share stays on the controller after the phase so the research panel can
	# still show the "+15%" it just spent (REQ-P5-05); the next end-turn sets it
	# afresh before it is spent again.
	var report: Dictionary = EconomyTurn.resolve(
		economy, market, readings.extraction(), readings.fleet_ships(),
		readings.army_food(), false, research_boost,
		HospitalRules.demand_list(world, player_faction), leader_key,
		TownIndustry.best_level(world, player_faction), leaving
	)
	# The wards eat last and in whole staffs; the flags they set are what the
	# next turn's rest tick reads (wiki: combat § Regiment condition;
	# DR-20261112-04).
	report["hospital"] = HospitalRules.feed(
		world, player_faction,
		int((report.get("consumption", {}) as Dictionary).get("hospital_fed", 0))
	)
	report["overseas"] = plan
	report["musters"] = musters
	# A sealed harbour is a rule, not a lean harvest: the despatch names it
	# (wiki: capital-and-connectivity § Blockade; REQ-P5-05).
	report["blockade"] = Blockades.note(Blockades.of(blockade_source), world)
	readings.last_consumption = report.get("consumption", {}) as Dictionary
	# A new turn's harvest is on the table before the ledger repaints.
	MinorMarket.publish(
		market, ship_layer.world if ship_layer != null else null, player_faction
	)
	if army_layer != null:
		army_layer.sync_generals(player_faction, economy.tech_unlocked)
	if hud != null:
		hud.stats.set_treasury(economy.treasury)
		hud.stats.flash_income(economy.treasury - before)
		var projection: Dictionary = readings.projected()
		hud.stats.set_income(int(projection.get("treasury_delta", 0)))
		hud.stats.set_fleets(readings.fleet_ships())
		if army_layer != null:
			hud.stats.set_armies(army_layer.regiment_count_all(player_faction))
		# The lane raises only what asks the crown to act; a quiet turn's
		# harvest, deliveries and studies read on the ledger sheet and the
		# Gazette (wiki: hud-toasts).
		var trouble: String = LedgerReportText.turn_summary(report, true)
		if not trouble.is_empty():
			hud.toast(trouble)
		# The larder speaks a turn early: a store the next Consumption would
		# strike is named now, while the crown can still hire, feed or sell
		# (wiki: workers-and-population § Consumption; REQ-P5-05, REQ-P5-06).
		var warning: String = larder_warning(report, projection)
		if not warning.is_empty():
			hud.toast(warning)
	refresh_research_panel()
	treasury_changed.emit(economy.treasury)
	return report


func open_panel() -> void:
	if hud == null:
		return
	hud.panels.show_economy(
		economy, market, readings.projected(), readings.trade_cargo(),
		market.minor_offers, player_faction, _production_pick(), _market_pick()
	)


func open_research() -> void:
	if hud == null:
		return
	hud.panels.show_research(
		economy.research, economy.treasury, research_boost, leader_key, _research_pick()
	)


## The study the published research policy would open in the crown's first free
## slot, in the sheet's own voice (wiki: tech-tree § Research model;
## DR-20261121-01). Empty when there is no free slot, no study left to open, or
## no planner behind the seat — the reading, never an order.
func _research_pick() -> String:
	return MapPlayResearchPick.line(play)


## The runs the published economy pass would book for the crown's workshop this
## phase, in the PRODUCTION tab's own voice (wiki: stockpiles-and-production
## § Production flow; DR-20261121-07). Empty when there is no planner behind the
## seat — the reading, never an order.
func _production_pick() -> Dictionary:
	var pick: Dictionary = MapPlayProductionPick.pick(play)
	if pick.is_empty():
		return {}
	return {
		"kind": pick.get("kind", ""),
		"runs": pick.get("runs", {}),
		"line": MapPlayPickProse.sentence(String(pick.get("line", ""))),
	}


## The trade the published market pass would book for the crown this phase, in
## the MARKET tab's own voice (wiki: world-market § Trade orders;
## DR-20261121-09). Empty when there is no planner behind the seat — the
## reading, never an order.
func _market_pick() -> Dictionary:
	var picked: Dictionary = MapPlayMarketPick.pick(play)
	if picked.is_empty():
		return {}
	return {
		"kind": picked.get("kind", ""),
		"offers": picked.get("offers", {}),
		"bids": picked.get("bids", {}),
		"line": MapPlayPickProse.sentence(String(picked.get("line", ""))),
	}


## The larder's warning for the turn about to open: the slack the next
## Consumption phase leaves, read through the ledger's own projection so the
## WORKERS tab and this line can never print two larders for one turn
## (wiki: workers-and-population § Consumption; REQ-P2-03, REQ-P5-05).
## `report` is the phase that just closed: when it already struck, the court has
## heard the news on its own summary line and the forecast stays silent, so the
## warning arrives one turn before the strike, never on every struck turn.
func larder_warning(report: Dictionary, projection: Dictionary = {}) -> String:
	if hud == null or economy == null:
		return ""
	var last: Dictionary = report.get("consumption", {}) as Dictionary
	if int(last.get("strikers", 0)) > 0:
		return ""
	var read: Dictionary = projection if not projection.is_empty() else readings.projected()
	return LarderRead.warning(LarderRead.standing(economy, LarderRead.mouths(read), false))


func refresh_panel() -> void:
	if hud == null:
		return
	var projection: Dictionary = readings.projected()
	if hud.panels.is_economy_open():
		hud.panels.show_economy(
			economy, market, projection, readings.trade_cargo(),
			market.minor_offers, player_faction, _production_pick(), _market_pick()
		)
	hud.stats.set_treasury(economy.treasury)
	hud.stats.set_income(int(projection.get("treasury_delta", 0)))
	treasury_changed.emit(economy.treasury)


## Repaints the college sheet while it is open: a study moved the figures.
func refresh_research_panel() -> void:
	if hud == null:
		return
	if hud.panels.is_research_open():
		hud.panels.show_research(
			economy.research, economy.treasury, research_boost, leader_key, _research_pick()
		)


## A study's verdict: its message on the bar, the sheet repainted, and the
## per-turn figure the chip prints moved with it (REQ-P5-05).
func report_research(result: Dictionary) -> void:
	if hud != null:
		hud.toast(String(result.get("message", "")))
	refresh_research_panel()
	# Starting or abandoning a study changes the per-turn gold; the top bar must
	# read the new figure before the turn is even closed.
	if hud != null:
		hud.stats.set_income(readings.projected_income())


## A funding preset moved the gold the purse pays every turn, and the chip is
## the only place that figure is always visible (REQ-P5-05).
func report_funding() -> void:
	refresh_research_panel()
	if hud != null:
		hud.stats.set_income(readings.projected_income())
