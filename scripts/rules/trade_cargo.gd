class_name TradeCargo
extends RefCounted
## Merchant cargo holds that cap world-market imports (wiki: ships-and-naval
## § Cargo holds and capacity; world-market § Cargo; DR-20261109-03). Pure rules:
## capacity comes from the crown's home fleet, use from this turn's buys, so the
## ledger, the order path and tests share one gate (REQ-P3-03).


## Holds one squadron carries: merchant hulls only, one hold per cargo point.
static func fleet_holds(fleet: FleetState) -> int:
	if fleet == null:
		return 0
	var total: int = 0
	for hull_id: String in fleet.hulls:
		total += maxi(int(ShipStats.entry(fleet.type_of(hull_id)).get("cargo", 0)), 0)
	return total


## Holds across every region: only the crown's squadrons in port at its seat
## count, because the home fleet never leaves the capital (wiki: § Home Fleet).
static func capacity(
	world: WorldMap, fleets_by_region: Dictionary, owner: int
) -> int:
	if world == null:
		return 0
	var total: int = 0
	for region_index in world.region_count():
		var seat: int = world.seat_province(region_index, owner)
		if seat == MapModel.NO_ID:
			continue
		var stored: Array = fleets_by_region.get(region_index, [])
		for fleet: FleetState in stored:
			if fleet == null or fleet.owner != owner or not fleet.is_in_port():
				continue
			if fleet.province != seat:
				continue
			total += fleet_holds(fleet)
	return total


## Units bought this turn: the buyer ships every imported ton, the seller none.
static func used(market: WorldMarket) -> int:
	if market == null:
		return 0
	return market.bought_units()


static func free_holds(holds: int, market: WorldMarket, reserved: int = 0) -> int:
	return maxi(holds - maxi(reserved, 0) - used(market), 0)


## {"holds": n, "used": n, "reserved": n, "free": n} for the ledger and the
## order toast. `reserved` is the cargo this turn's overseas delivery needs:
## extraction ships before trade (wiki: ships-and-naval § Cargo holds).
static func status(
	world: WorldMap,
	fleets_by_region: Dictionary,
	owner: int,
	market: WorldMarket,
	reserved: int = 0
) -> Dictionary:
	var holds: int = capacity(world, fleets_by_region, owner)
	var laden: int = used(market)
	var promised: int = maxi(reserved, 0)
	return {
		"holds": holds,
		"used": laden,
		"reserved": promised,
		"free": maxi(holds - promised - laden, 0),
	}


## Cargo half of an import: a refusal before the market's price and stock rules.
static func check(
	market: WorldMarket, holds: int, quantity: int, reserved: int = 0
) -> Dictionary:
	if quantity <= 0:
		return {"ok": false, "reason": "Quantity must be positive"}
	var laden: int = used(market)
	var promised: int = maxi(reserved, 0)
	if laden + promised + quantity > holds:
		return {
			"ok": false,
			"reason": _short_reason(holds, laden, promised),
			"holds": holds,
			"free": maxi(holds - promised - laden, 0),
		}
	return {
		"ok": true,
		"reason": "",
		"holds": holds,
		"free": holds - promised - laden,
	}


## The single gate for an import: holds first, then the market's own rules.
static func buy(
	economy: PlayerEconomy,
	market: WorldMarket,
	holds: int,
	id: String,
	quantity: int,
	reserved: int = 0
) -> Dictionary:
	var gate: Dictionary = check(market, holds, quantity, reserved)
	if not bool(gate.get("ok", false)):
		return gate
	return market.buy(economy, id, quantity)


static func _short_reason(holds: int, laden: int, reserved: int) -> String:
	if holds <= 0:
		return "No cargo holds at the capital — launch a merchant hull or moor the home squadron."
	if reserved > 0:
		return (
			"The home fleet carries %d cargo holds; %d are promised to the colonies and %d are already laden this turn."
			% [holds, reserved, laden]
		)
	return (
		"The home fleet carries %d cargo holds and %d are already laden this turn."
		% [holds, laden]
	)
