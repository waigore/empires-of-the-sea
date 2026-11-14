class_name MainlineAiCargoPlanner
extends RefCounted
## Rival cargo routes (wiki: economy-planner § Cargo; DR-20261110-26).
##
## Colonial tonnage and world-market imports ride the merchant hulls berthed at
## the crown's seat, so a court whose need outruns those holds walks idle
## merchant squadrons home and, if that still falls short, lays down one more
## hull. `NavalMovement`, `FleetYard` and `MainlineAiSeaRoute` own every step and price;
## this module only chooses what to send where (REQ-P2-03, REQ-P3-03).

const KIND_ROUTE: String = "route"
const KIND_LAUNCH: String = "launch"
## MainlineAiSeaRoute answers this sentinel when no sea path reaches a goal zone.
const UNREACHABLE: int = 1 << 30


## Transport plan for `want` holds: the routes home, at most one launch, and the
## scored candidates that explain them. Empty orders mean the berths already
## cover the need.
static func plan(
	config: MainlineAiConfig,
	economy: PlayerEconomy,
	model: MapModel,
	fleets: Array,
	seat: int,
	want: int,
	blocked_zones: Dictionary = {}
) -> Dictionary:
	var routes: Array[Dictionary] = []
	var candidates: Array[Dictionary] = []
	var launch: Dictionary = {}
	var need: int = maxi(want, 0)
	var result: Dictionary = {
		"want": need,
		"holds": 0,
		"shortfall": need,
		"projected": 0,
		"routes": routes,
		"launch": launch,
		"candidates": candidates,
	}
	if config == null or economy == null or model == null or seat < 0:
		return result
	var holds: int = _holds_at_seat(fleets, config.faction, seat)
	result["holds"] = holds
	result["shortfall"] = maxi(need - holds, 0)
	result["projected"] = holds
	if need <= holds:
		return result
	var projected: int = holds
	var cap: int = maxi(config.parameter("cargo.max_routes"), 0)
	for fleet: FleetState in _merchant_squadrons(fleets, config.faction, seat):
		if routes.size() >= cap:
			break
		var route: Dictionary = _route_for(model, fleet, seat, blocked_zones)
		if route.is_empty():
			continue
		route["fleet_id"] = fleet.id
		route["holds"] = TradeCargo.fleet_holds(fleet)
		routes.append(route)
		candidates.append(route.duplicate())
		projected += int(route["holds"])
	if projected < need:
		launch = _launch_for(config, economy, need - projected)
		if not launch.is_empty():
			candidates.append(launch.duplicate())
			projected += int(launch["cargo"])
		result["launch"] = launch
	result["projected"] = projected
	return result


## Applies one planned route through the movement rules; the caller owns rosters
## and markers. A dock order names the seat province, every other names a zone.
static func apply_route(
	model: MapModel, fleet: FleetState, order: Dictionary
) -> Dictionary:
	if model == null or fleet == null or order.is_empty():
		return {"ok": false, "reason": "No route to sail.", "entered_zone": -1}
	if bool(order.get("dock", false)):
		return NavalMovement.apply_move(
			model, fleet, FleetState.Location.IN_PORT, int(order.get("province", -1))
		)
	return NavalMovement.apply_move(
		model, fleet, FleetState.Location.AT_SEA, int(order.get("zone", -1))
	)


## Merchant holds already berthed at the seat, where they count as home cargo
## (wiki: ships-and-naval § Cargo holds and capacity).
static func _holds_at_seat(fleets: Array, owner: int, seat: int) -> int:
	var total: int = 0
	for fleet: FleetState in fleets:
		if fleet == null or fleet.owner != owner or not fleet.is_in_port():
			continue
		if fleet.province != seat:
			continue
		total += TradeCargo.fleet_holds(fleet)
	return total


## Hulls that can still sail home this turn: own, afloat, un-moved, carrying
## cargo space and no expedition. Richest hold first, id to break the tie.
static func _merchant_squadrons(
	fleets: Array, owner: int, seat: int
) -> Array[FleetState]:
	var rows: Array[FleetState] = []
	for fleet: FleetState in fleets:
		if fleet == null or fleet.owner != owner or fleet.moved or not fleet.is_afloat():
			continue
		if TradeCargo.fleet_holds(fleet) <= 0:
			continue
		if fleet.embarked_army >= 0 or not fleet.embarked_civilians.is_empty():
			continue
		if fleet.is_in_port() and fleet.province == seat:
			continue
		rows.append(fleet)
	rows.sort_custom(func(a: FleetState, b: FleetState) -> bool:
		var left: int = TradeCargo.fleet_holds(a)
		var right: int = TradeCargo.fleet_holds(b)
		if left != right:
			return left > right
		return a.id < b.id
	)
	return rows


## One move toward the seat: dock when the harbour borders the squadron's zone,
## otherwise the next zone on the sea path. An empty route means no sea path, or
## a step into water a hostile squadron holds (`blocked`).
static func _route_for(
	model: MapModel, fleet: FleetState, seat: int, blocked: Dictionary
) -> Dictionary:
	var goals: Array[int] = NavalMovement.province_sea_zones(model, seat)
	if goals.is_empty():
		return {}
	if fleet.is_at_sea():
		if NavalMovement.dockable_provinces(model, fleet).has(seat):
			return {"kind": KIND_ROUTE, "dock": true, "province": seat}
		var zone: int = MainlineAiSeaRoute.sail_toward(model, fleet, goals)
		if zone < 0 or blocked.has(zone):
			return {}
		return {"kind": KIND_ROUTE, "dock": false, "zone": zone}
	var step: int = MainlineAiSeaRoute.sail_toward(model, fleet, goals)
	if step < 0 or blocked.has(step):
		return {}
	if MainlineAiSeaRoute.distance_to_goal(model, step, goals) >= UNREACHABLE:
		return {}
	return {"kind": KIND_ROUTE, "dock": false, "zone": step}


## Best merchant hull this ledger can lay down: most cargo per hold for the
## money, payable through ShipEconomy, one hull only, purse kept above the floor.
static func _launch_for(
	config: MainlineAiConfig, economy: PlayerEconomy, shortfall: int
) -> Dictionary:
	if shortfall < config.parameter("cargo.min_launch_shortfall"):
		return {}
	var floor: int = maxi(config.parameter("cargo.min_treasury"), 0)
	var peasants: int = economy.available_peasants()
	var best: Dictionary = {}
	for raw: Variant in ShipEconomy.ENTRIES.keys():
		var type_id: String = String(raw)
		if ShipStats.is_warship(type_id):
			continue
		var cargo: int = int(ShipStats.entry(type_id).get("cargo", 0))
		if cargo <= 0:
			continue
		var price: int = ShipEconomy.treasury_cost(type_id)
		if economy.treasury - price < floor:
			continue
		var reason: String = ShipEconomy.blocked_reason(
			type_id, economy.treasury, economy.stockpile, peasants, economy.tech_unlocked
		)
		if not reason.is_empty():
			continue
		if best.is_empty() or _better_hull(cargo, price, type_id, best):
			best = {"kind": KIND_LAUNCH, "type_id": type_id, "cargo": cargo}
	return best


## Most cargo first, then the cheaper hull, then the catalog id, so the plan is
## deterministic for a given ledger.
static func _better_hull(
	cargo: int, price: int, type_id: String, best: Dictionary
) -> bool:
	var best_cargo: int = int(best["cargo"])
	if cargo != best_cargo:
		return cargo > best_cargo
	var best_price: int = ShipEconomy.treasury_cost(String(best["type_id"]))
	if price != best_price:
		return price < best_price
	return type_id < String(best["type_id"])