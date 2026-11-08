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
var _hud: GameHud = null


func setup(
	p_model: MapModel,
	p_faction: int,
	p_capital: int,
	p_ships: ShipLayer,
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
	_hud = p_hud
	economy = PlayerEconomy.starting()
	market = WorldMarket.with_default_prices()
	_connect()


func _connect() -> void:
	if _hud == null:
		return
	_hud.economy_pressed.connect(open_panel)
	var panel: EconomyPanel = _hud.economy_panel()
	panel.trade_requested.connect(_on_trade)
	panel.production_changed.connect(_on_production)
	panel.recruit_requested.connect(_on_recruit)


## Ships in the player's fleets drive naval food upkeep this turn.
func fleet_ships() -> int:
	var total: int = 0
	if _ships == null:
		return total
	for fleet: FleetState in _ships.fleets:
		if fleet != null and fleet.owner == player_faction:
			total += fleet.ship_count()
	return total


func extraction() -> Dictionary:
	return Extraction.yields(
		model, player_faction, capital_province, economy.tech_unlocked, works,
		capital_tile
	)


func projected() -> Dictionary:
	return EconomyTurn.project(economy, market, extraction(), fleet_ships())


func projected_income() -> int:
	return int(projected().get("treasury_delta", 0))


## Runs Extraction -> Riches -> Consumption -> Production and refreshes the HUD.
func resolve_turn() -> Dictionary:
	var before: int = economy.treasury
	var report: Dictionary = EconomyTurn.resolve(
		economy, market, extraction(), fleet_ships()
	)
	if _hud != null:
		_hud.set_treasury(economy.treasury)
		_hud.flash_income(economy.treasury - before)
		_hud.set_fleets(fleet_ships())
		_hud.toast(summary_line(report))
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
	if parts.is_empty():
		return "The ledgers balance — nothing moved this turn."
	return "  ·  ".join(parts)


func open_panel() -> void:
	if _hud != null:
		_hud.show_economy(economy, market, projected())


func _refresh_panel() -> void:
	if _hud == null:
		return
	if _hud.is_economy_open():
		_hud.show_economy(economy, market, projected())
	_hud.set_treasury(economy.treasury)
	treasury_changed.emit(economy.treasury)


func _on_trade(commodity: String, quantity: int, is_buy: bool) -> void:
	var result: Dictionary
	if is_buy:
		result = market.buy(economy, commodity, quantity)
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
