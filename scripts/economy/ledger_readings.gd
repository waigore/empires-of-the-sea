class_name LedgerReadings
extends RefCounted
## What the crown's ledger reads this turn: hulls, rations, cargo, the overseas
## delivery plan, the harvest, the last auction receipt and the projection the
## sheet prints (wiki: extraction-and-improvements, world-market).
##
## `EconomyController` owns the mount — its views and its bound map state — and
## asks this module for every figure, so the ledger's numbers have one owner
## while the controller keeps the turn and the panel surface (REQ-P3-01,
## REQ-P2-03). Every reading is a pure function of the state it reads.

## The controller this reading belongs to; it owns the state read here.
var host: EconomyController = null
## Consumption report of the last resolved turn, for feeding coverage.
var last_consumption: Dictionary = {}
## Last world-market clearing (deals, fills, credits), so the ledger can name
## the auction's receipt and the overseas share it paid (wiki: world-market
## § First right of refusal; REQ-P5-05).
var last_clearing: Dictionary = {}


func _init(p_host: EconomyController = null) -> void:
	host = p_host


## Ships in the player's fleets drive naval food upkeep this turn. Every region
## counts: a squadron parked on the other map still eats.
func fleet_ships() -> int:
	if host == null or host.ship_layer == null:
		return 0
	return host.ship_layer.hull_count_all(host.player_faction)


## Extraction ceilings from the researched tech tree (wiki:
## tech-and-extraction-cap), per commodity.
func tech_caps() -> Dictionary:
	if host == null or host.economy == null:
		return {}
	return TechCatalog.extraction_caps(host.economy.tech_unlocked)


## Army rations across every region (wiki: economy § Consumption: army first).
func army_food() -> int:
	if host == null or host.army_layer == null:
		return 0
	return host.army_layer.food_upkeep_all(host.player_faction)


## Merchant cargo for the ledger: holds in the home fleet, this turn's colonial
## delivery reserved first, imports laden this turn (wiki: ships-and-naval
## § Cargo holds and capacity; DR-20261109-03, DR-20261109-17).
func trade_cargo() -> Dictionary:
	if host == null or host.market == null:
		return {"holds": 0, "used": 0, "reserved": 0, "free": 0}
	var market: WorldMarket = host.market
	var status: Dictionary
	if host.ship_layer == null or host.ship_layer.world == null:
		status = {"holds": 0, "used": TradeCargo.used(market), "reserved": 0, "free": 0}
	else:
		status = TradeCargo.status(
			host.ship_layer.world, host.ship_layer.regions.snapshot(),
			host.player_faction, market, int(overseas_plan().get("used", 0))
		)
	# The ledger shows what is still free after staged bids; the clearing pass
	# needs the gross figure, because the bids themselves are not yet laden.
	var pending: int = market.book.pending_buy_units(host.player_faction)
	var gross: int = int(status.get("free", 0))
	status["pending"] = pending
	status["clear_free"] = gross
	status["free"] = maxi(gross - pending, 0)
	return status


## Holds the crown's home squadron carries this turn (0 while it is away).
func cargo_holds() -> int:
	if host == null or host.ship_layer == null or host.ship_layer.world == null:
		return 0
	return TradeCargo.capacity(
		host.ship_layer.world, host.ship_layer.regions.snapshot(), host.player_faction
	)


## Overseas yield delivered this turn. Extraction takes the home fleet's holds
## before trade, richest commodity first; undelivered cargo stays abroad
## (wiki: extraction-and-improvements § Flow to Stockpile; DR-20261109-17).
func overseas_plan() -> Dictionary:
	if host == null:
		return EconomyOverseas.plan({}, 0)
	var by_region: Dictionary = {}
	if host.ship_layer != null and host.ship_layer.world != null:
		var home_region: int = host.model.region_id if host.model != null else WorldMap.OLD_WORLD
		by_region = EconomyOverseas.region_totals(
			host.ship_layer.world, home_region, host.player_faction, tech_caps(),
			host.works_by_region, {}, {}, Blockades.of(host.blockade_source)
		)
	return EconomyOverseas.plan(by_region, cargo_holds())


## Share of last turn's army rations the granary could cover (0..1). Full
## rations before the first Consumption; armies fight at this coverage.
func feeding_coverage() -> float:
	var demand: int = int(last_consumption.get("army_demand", 0))
	if demand <= 0:
		return 1.0
	return clampf(float(int(last_consumption.get("army_fed", 0))) / float(demand), 0.0, 1.0)


## Everything that reaches the crown's stockpile this turn: home-region land
## yield plus the overseas cargo the home fleet actually delivers.
func extraction() -> Dictionary:
	if host == null or host.model == null or host.economy == null:
		return {}
	var seals: Blockades = Blockades.of(host.blockade_source)
	var home: Dictionary = Extraction.yields(
		host.model, host.player_faction, host.capital_province, tech_caps(), host.works,
		host.capital_tile, host.economy.tech_unlocked, true, {}, seals
	)
	if host.ship_layer == null or host.ship_layer.world == null:
		return home
	var home_region: int = host.model.region_id
	return EconomyOverseas.delivered(
		home, host.ship_layer.world, home_region, host.player_faction, tech_caps(),
		host.works_by_region, cargo_holds(), host.economy.tech_unlocked, seals
	)["extraction"] as Dictionary


func projected() -> Dictionary:
	if host == null or host.economy == null:
		return {}
	var world: WorldMap = host.ship_layer.world if host.ship_layer != null else null
	var report: Dictionary = EconomyTurn.project(
		host.economy, host.market, extraction(), fleet_ships(), army_food(),
		host.research_boost, HospitalRules.demand_list(world, host.player_faction),
		host.leader_key
	)
	# The auction clears after these phases, so the ledger names what is staged
	# and what the last clearing paid: the per-turn figure alone is not the
	# whole purse movement (wiki: world-market § Trade orders; REQ-P5-05).
	report["staged_orders"] = (
		host.market.book.orders_for(host.player_faction).size()
		if host.market != null else 0
	)
	report["clearing"] = last_clearing
	return report


func projected_income() -> int:
	return int(projected().get("treasury_delta", 0))
