class_name EconomyController
extends Node
## Connects the player's economy to the map screen: builds the opening economy,
## runs turn resolution, and turns ledger button presses into market/production
## intents. Rules live in scripts/rules; this node only wires and reports.

signal treasury_changed(value: int)

var model: MapModel = null
var economy: PlayerEconomy = null
var market: WorldMarket = null
var player_faction: int = 0
var capital_province: int = -1
var capital_tile: Vector2i = CivilianState.NO_TILE
var works: LandWorks = null

var _ships: ShipLayer = null
var _armies: ArmyLayer = null
var _hud: GameHud = null
## Every region's works, so overseas estates yield (DR-20261109-17).
var works_by_region: MapRegionTable = null
## Consumption report of the last resolved turn, for feeding coverage.
var _last_consumption: Dictionary = {}
## Tech id -> percent the crown's spy network adds this Research phase, set by
## the turn helper before resolution (wiki: civilian-units § Spy;
## DR-20261110-03). Empty when no spy sits in a rival Great Power's province.
var research_boost: Dictionary = {}


func setup(
	p_model: MapModel,
	p_faction: int,
	p_capital: int,
	p_ships: ShipLayer,
	p_armies: ArmyLayer,
	p_hud: GameHud,
	p_works: LandWorks = null,
	p_capital_tile: Vector2i = CivilianState.NO_TILE
) -> void:
	model = p_model
	player_faction = p_faction
	capital_province = p_capital
	capital_tile = p_capital_tile
	works = p_works
	_ships = p_ships
	_armies = p_armies
	_hud = p_hud
	economy = PlayerEconomy.starting()
	market = WorldMarket.with_default_prices()
	_connect()
	MinorMarket.publish(market, _ships.world if _ships != null else null, player_faction)


func _connect() -> void:
	if _hud == null:
		return
	_hud.economy_pressed.connect(open_panel)
	_hud.research_pressed.connect(open_research)
	var panel: EconomyPanel = _hud.panels.economy_panel
	panel.trade_requested.connect(_on_trade)
	panel.offer_requested.connect(_on_offer)
	panel.production_changed.connect(_on_production)
	panel.recruit_requested.connect(_on_recruit)
	var research: ResearchPanel = _hud.panels.research_panel
	research.assign_requested.connect(_on_research_assign)
	research.cancel_requested.connect(_on_research_cancel)
	research.funding_requested.connect(_on_research_funding)


## Ships in the player's fleets drive naval food upkeep this turn. Every region
## counts: a squadron parked on the other map still eats.
func fleet_ships() -> int:
	if _ships == null:
		return 0
	return _ships.hull_count_all(player_faction)


## Extraction ceilings from the researched tech tree (wiki:
## tech-and-extraction-cap), per commodity.
func tech_caps() -> Dictionary:
	return TechCatalog.extraction_caps(economy.tech_unlocked)


## Army rations across every region (wiki: economy § Consumption: army first).
func army_food() -> int:
	if _armies == null:
		return 0
	return _armies.food_upkeep_all(player_faction)


## Merchant cargo for the ledger: holds in the home fleet, this turn's colonial
## delivery reserved first, imports laden this turn (wiki: ships-and-naval
## § Cargo holds and capacity; DR-20261109-03, DR-20261109-17).
func trade_cargo() -> Dictionary:
	var laden: int = TradeCargo.used(market)
	if _ships == null or _ships.world == null:
		return {"holds": 0, "used": laden, "reserved": 0, "free": 0}
	return TradeCargo.status(
		_ships.world, _ships.regions.snapshot(), player_faction, market,
		int(overseas_plan().get("used", 0))
	)


## Holds the crown's home squadron carries this turn (0 while it is away).
func cargo_holds() -> int:
	if _ships == null or _ships.world == null:
		return 0
	return TradeCargo.capacity(_ships.world, _ships.regions.snapshot(), player_faction)


## Overseas yield delivered this turn. Extraction takes the home fleet's holds
## before trade, richest commodity first; undelivered cargo stays abroad
## (wiki: extraction-and-improvements § Flow to Stockpile; DR-20261109-17).
func overseas_plan() -> Dictionary:
	var by_region: Dictionary = {}
	if _ships != null and _ships.world != null:
		var home_region: int = model.region_id if model != null else WorldMap.OLD_WORLD
		by_region = EconomyOverseas.region_totals(
			_ships.world, home_region, player_faction, tech_caps(), works_by_region
		)
	return EconomyOverseas.plan(by_region, cargo_holds())


## Share of last turn's army rations the granary could cover (0..1). Full
## rations before the first Consumption; armies fight at this coverage.
func feeding_coverage() -> float:
	var demand: int = int(_last_consumption.get("army_demand", 0))
	if demand <= 0:
		return 1.0
	return clampf(float(int(_last_consumption.get("army_fed", 0))) / float(demand), 0.0, 1.0)


## Everything that reaches the crown's stockpile this turn: home-region land
## yield plus the overseas cargo the home fleet actually delivers.
func extraction() -> Dictionary:
	var home: Dictionary = Extraction.yields(
		model, player_faction, capital_province, tech_caps(), works,
		capital_tile, economy.tech_unlocked
	)
	if _ships == null or _ships.world == null:
		return home
	var home_region: int = model.region_id if model != null else WorldMap.OLD_WORLD
	return EconomyOverseas.delivered(
		home, _ships.world, home_region, player_faction, tech_caps(),
		works_by_region, cargo_holds()
	)["extraction"] as Dictionary


func projected() -> Dictionary:
	return EconomyTurn.project(
		economy, market, extraction(), fleet_ships(), army_food(), research_boost
	)


func projected_income() -> int:
	return int(projected().get("treasury_delta", 0))


## Runs Extraction -> Riches -> Consumption -> Production and refreshes the HUD.
func resolve_turn() -> Dictionary:
	var before: int = economy.treasury
	var plan: Dictionary = overseas_plan()
	var report: Dictionary = EconomyTurn.resolve(
		economy, market, extraction(), fleet_ships(), army_food(), true,
		research_boost
	)
	research_boost = {}
	report["overseas"] = plan
	_last_consumption = report.get("consumption", {}) as Dictionary
	# A new turn's harvest is on the table before the ledger repaints.
	MinorMarket.publish(market, _ships.world if _ships != null else null, player_faction)
	if _armies != null:
		_armies.sync_generals(player_faction, economy.tech_unlocked)
	if _hud != null:
		_hud.set_treasury(economy.treasury)
		_hud.flash_income(economy.treasury - before)
		_hud.set_income(projected_income())
		_hud.set_fleets(fleet_ships())
		if _armies != null:
			_hud.set_armies(_armies.regiment_count_all(player_faction))
		_hud.toast(LedgerText.turn_summary(report))
	_refresh_research_panel()
	treasury_changed.emit(economy.treasury)
	return report


func open_panel() -> void:
	if _hud != null:
		_hud.panels.show_economy(
			economy, market, projected(), trade_cargo(), market.minor_offers
		)


func open_research() -> void:
	if _hud != null:
		_hud.panels.show_research(economy.research, economy.treasury, research_boost)


func _refresh_research_panel() -> void:
	if _hud == null:
		return
	if _hud.panels.is_research_open():
		_hud.panels.show_research(economy.research, economy.treasury, research_boost)


func _on_research_assign(tech_id: String) -> void:
	var result: Dictionary = economy.research.assign(tech_id)
	_after_research(result)


func _on_research_cancel(slot: int) -> void:
	var result: Dictionary = economy.research.cancel(slot)
	_after_research(result)


func _on_research_funding(slot: int) -> void:
	economy.research.cycle_funding(slot)
	_refresh_research_panel()


func _after_research(result: Dictionary) -> void:
	if _hud != null:
		_hud.toast(String(result.get("message", "")))
	_refresh_research_panel()


func _refresh_panel() -> void:
	if _hud == null:
		return
	if _hud.panels.is_economy_open():
		_hud.panels.show_economy(
			economy, market, projected(), trade_cargo(), market.minor_offers
		)
	_hud.set_treasury(economy.treasury)
	_hud.set_income(projected_income())
	treasury_changed.emit(economy.treasury)


func _on_trade(commodity: String, quantity: int, is_buy: bool) -> void:
	var result: Dictionary
	if is_buy:
		var cargo: Dictionary = trade_cargo()
		result = TradeCargo.buy(
			economy, market, int(cargo.get("holds", 0)), commodity, quantity,
			int(cargo.get("reserved", 0))
		)
	else:
		result = market.sell(economy, commodity, quantity)
	if not bool(result.get("ok", false)) and _hud != null:
		_hud.toast(String(result.get("reason", "Trade refused")))
	_refresh_panel()


## A direct purchase from a Minor Nation or a Tribe: the rules decide, the
## ledger reports the receipt or the refusal (REQ-P2-03, REQ-P5-05).
func _on_offer(offer_id: String, quantity: int) -> void:
	var cargo: Dictionary = trade_cargo()
	var result: Dictionary = MinorMarket.buy(
		market, economy, market.minor_offers, offer_id, quantity,
		int(cargo.get("holds", 0)), int(cargo.get("reserved", 0)), player_faction
	)
	if _hud != null:
		if bool(result.get("ok", false)):
			_hud.toast("Bought %d %s from %s for %d ducats" % [
				int(result.get("quantity", 0)),
				CommodityCatalog.label(String(result.get("commodity", ""))),
				FactionCatalog.name_of(int(result.get("faction", -1))),
				int(result.get("cost", 0)),
			])
		else:
			_hud.toast(String(result.get("reason", "That purchase was refused")))
	_refresh_panel()


func _on_production(recipe_id: String, units: int) -> void:
	economy.set_assignment(recipe_id, units)
	_refresh_panel()


func _on_recruit(tier: int) -> void:
	var result: Dictionary = economy.recruit(tier)
	if _hud != null:
		if bool(result.get("ok", false)):
			_hud.toast("A %s joins the capital's workshops" % WorkerPool.tier_name(tier))
		else:
			_hud.toast(String(result.get("reason", "Recruit refused")))
	_refresh_panel()
