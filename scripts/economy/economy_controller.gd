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
## Consumption report of the last resolved turn, for feeding coverage.
var _last_consumption: Dictionary = {}


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


func _connect() -> void:
	if _hud == null:
		return
	_hud.economy_pressed.connect(open_panel)
	_hud.research_pressed.connect(open_research)
	var panel: EconomyPanel = _hud.panels.economy_panel
	panel.trade_requested.connect(_on_trade)
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


## Merchant cargo for the ledger: holds in the home fleet, imports laden this
## turn (wiki: ships-and-naval § Cargo holds and capacity; DR-20261109-03).
func trade_cargo() -> Dictionary:
	var laden: int = TradeCargo.used(market)
	if _ships == null or _ships.world == null:
		return {"holds": 0, "used": laden, "free": 0}
	return TradeCargo.status(
		_ships.world, _ships.regions.entries(), player_faction, market
	)


## Share of last turn's army rations the granary could cover (0..1). Full
## rations before the first Consumption; armies fight at this coverage.
func feeding_coverage() -> float:
	var demand: int = int(_last_consumption.get("army_demand", 0))
	if demand <= 0:
		return 1.0
	return clampf(float(int(_last_consumption.get("army_fed", 0))) / float(demand), 0.0, 1.0)


func extraction() -> Dictionary:
	return Extraction.yields(
		model, player_faction, capital_province, tech_caps(), works,
		capital_tile
	)


func projected() -> Dictionary:
	return EconomyTurn.project(economy, market, extraction(), fleet_ships(), army_food())


func projected_income() -> int:
	return int(projected().get("treasury_delta", 0))


## Runs Extraction -> Riches -> Consumption -> Production and refreshes the HUD.
func resolve_turn() -> Dictionary:
	var before: int = economy.treasury
	var report: Dictionary = EconomyTurn.resolve(
		economy, market, extraction(), fleet_ships(), army_food()
	)
	_last_consumption = report.get("consumption", {}) as Dictionary
	if _armies != null:
		_armies.sync_generals(player_faction, economy.tech_unlocked)
	if _hud != null:
		_hud.set_treasury(economy.treasury)
		_hud.flash_income(economy.treasury - before)
		_hud.set_fleets(fleet_ships())
		if _armies != null:
			_hud.set_armies(_armies.regiment_count_all(player_faction))
		_hud.toast(summary_line(report))
	_refresh_research_panel()
	treasury_changed.emit(economy.treasury)
	return report


## One-line turn summary for the toast channel.
func summary_line(report: Dictionary) -> String:
	var parts: PackedStringArray = []
	var extracted: Dictionary = report.get("extraction", {})
	if not extracted.is_empty():
		parts.append("gathered %s" % ImprovementSystem.output_text(extracted))
	var treasury: int = int(report.get("riches_treasury", 0))
	if treasury > 0:
		parts.append("+%d from riches" % treasury)
	var production: Dictionary = report.get("production", {})
	var produced: Dictionary = production.get("produced", {})
	for id: String in produced.keys():
		parts.append("%s +%d" % [CommodityCatalog.label(id), int(produced[id])])
	var consumption: Dictionary = report.get("consumption", {})
	var eaters: int = int(consumption.get("food_eaten", 0))
	if eaters > 0:
		parts.append("%d food eaten" % eaters)
	var strikes: int = int(consumption.get("strikers", 0))
	if strikes > 0:
		parts.append("%d on strike" % strikes)
	var research: Dictionary = report.get("research", {})
	var researched: Array = research.get("researched", [])
	for tech_id: Variant in researched:
		parts.append("%s researched" % TechCatalog.display_name(String(tech_id)))
	var unpaid: Array = research.get("unpaid", [])
	if not unpaid.is_empty():
		var plural: String = "" if unpaid.size() == 1 else "s"
		parts.append("%d research slot%s unfunded" % [unpaid.size(), plural])
	if parts.is_empty():
		return "The ledgers balance — nothing moved this turn."
	return "  ·  ".join(parts)


func open_panel() -> void:
	if _hud != null:
		_hud.panels.show_economy(economy, market, projected(), trade_cargo())


func open_research() -> void:
	if _hud != null:
		_hud.panels.show_research(economy.research, economy.treasury)


func _refresh_research_panel() -> void:
	if _hud == null:
		return
	if _hud.panels.is_research_open():
		_hud.panels.show_research(economy.research, economy.treasury)


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
		_hud.panels.show_economy(economy, market, projected(), trade_cargo())
	_hud.set_treasury(economy.treasury)
	treasury_changed.emit(economy.treasury)


func _on_trade(commodity: String, quantity: int, is_buy: bool) -> void:
	var result: Dictionary
	if is_buy:
		result = TradeCargo.buy(
			economy, market, int(trade_cargo().get("holds", 0)), commodity, quantity
		)
	else:
		result = market.sell(economy, commodity, quantity)
	if not bool(result.get("ok", false)) and _hud != null:
		_hud.toast(String(result.get("reason", "Trade refused")))
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
