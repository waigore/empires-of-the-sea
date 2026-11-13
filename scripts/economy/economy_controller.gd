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
	panel.recruit_requested.connect(orders.worker_action.bind("recruit"))
	panel.disband_requested.connect(orders.worker_action.bind("disband"))
	var research: ResearchPanel = hud.panels.research_panel
	research.assign_requested.connect(orders.assign_research)
	research.cancel_requested.connect(orders.cancel_research)
	research.funding_requested.connect(orders.cycle_research_funding)


## Runs Build/work's recruits, then Extraction -> Riches -> Consumption ->
## Production, and refreshes the HUD.
func resolve_turn() -> Dictionary:
	# The crown's queued orders land before the new turn's Consumption: the new
	# worker eats and labours with the court from this turn, and the mustered
	# units stand for the next Orders phase. They land after the fighting this
	# turn ordered, so a regiment mustered now never fights in its own turn.
	var musters: Array[Dictionary] = MapPlayRecruits.complete(play) if play != null else []
	var before: int = economy.treasury
	var plan: Dictionary = readings.overseas_plan()
	var world: WorldMap = ship_layer.world if ship_layer != null else null
	# The share stays on the controller after the phase so the research panel can
	# still show the "+15%" it just spent (REQ-P5-05); the next end-turn sets it
	# afresh before it is spent again.
	var report: Dictionary = EconomyTurn.resolve(
		economy, market, readings.extraction(), readings.fleet_ships(),
		readings.army_food(), false, research_boost,
		HospitalRules.demand_list(world, player_faction), leader_key
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
		hud.set_treasury(economy.treasury)
		hud.flash_income(economy.treasury - before)
		hud.set_income(readings.projected_income())
		hud.set_fleets(readings.fleet_ships())
		if army_layer != null:
			hud.set_armies(army_layer.regiment_count_all(player_faction))
		hud.toast(LedgerText.turn_summary(report))
	refresh_research_panel()
	treasury_changed.emit(economy.treasury)
	return report


func open_panel() -> void:
	if hud == null:
		return
	hud.panels.show_economy(
		economy, market, readings.projected(), readings.trade_cargo(),
		market.minor_offers, player_faction
	)


func open_research() -> void:
	if hud == null:
		return
	hud.panels.show_research(economy.research, economy.treasury, research_boost, leader_key)


func refresh_panel() -> void:
	if hud == null:
		return
	if hud.panels.is_economy_open():
		hud.panels.show_economy(
			economy, market, readings.projected(), readings.trade_cargo(),
			market.minor_offers, player_faction
		)
	hud.set_treasury(economy.treasury)
	hud.set_income(readings.projected_income())
	treasury_changed.emit(economy.treasury)


## Repaints the college sheet while it is open: a study moved the figures.
func refresh_research_panel() -> void:
	if hud == null:
		return
	if hud.panels.is_research_open():
		hud.panels.show_research(
			economy.research, economy.treasury, research_boost, leader_key
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
		hud.set_income(readings.projected_income())


## A funding preset moved the gold the purse pays every turn, and the chip is
## the only place that figure is always visible (REQ-P5-05).
func report_funding() -> void:
	refresh_research_panel()
	if hud != null:
		hud.set_income(readings.projected_income())
