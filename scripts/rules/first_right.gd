class_name FirstRight
extends RefCounted
## First right of refusal and overseas profit (wiki: world-market § First right
## of refusal; world-market-first-right-of-refusal). The tile-owning Great Power
## earns the full relation-linear share of a minor/tribe sale; every other
## embassy-holding court earns a 10% kickback of its own relation portion. Pure
## arithmetic, deterministic and free of RNG or logging (REQ-P3-03).

const KICKBACK_MULTIPLIER: float = 0.10
const RELATION_MAX: float = 100.0


## Tile-owner share: filledQuantity x price x (relation / 100), no 40% cap.
static func profit(relation_score: float, filled_quantity: int, price: float) -> float:
	if filled_quantity <= 0 or price <= 0.0:
		return 0.0
	var rate: float = clampf(relation_score, 0.0, RELATION_MAX) / RELATION_MAX
	return float(filled_quantity) * price * rate


## Embassy kickback: 10% of that court's relation portion.
static func kickback(relation_score: float, filled_quantity: int, price: float) -> float:
	return profit(relation_score, filled_quantity, price) * KICKBACK_MULTIPLIER


## Aggregates every minor/tribe deal into credits per Great Power.
## `purchased_for(region, index)` returns the owning Great Power id or -1;
## `relation_for(gp, minor)` returns the hidden relation score;
## `embassy_for(gp, minor)` says whether that court holds an Embassy.
static func credits(
	deals: Array[Dictionary],
	purchased_for: Callable,
	relation_for: Callable,
	embassy_for: Callable
) -> Dictionary:
	var by_gp: Dictionary = {}
	var rows: Array[Dictionary] = []
	var gross_total: float = 0.0
	var owner_total: float = 0.0
	var kickback_total: float = 0.0
	for deal: Dictionary in deals:
		if not bool(deal.get("seller_is_minor", false)):
			continue
		var quantity: int = int(deal.get("quantity", 0))
		var price: float = float(deal.get("price", 0.0))
		if quantity <= 0 or price <= 0.0:
			continue
		var seller: int = int(deal.get("seller", MarketOrder.WORLD))
		var buyer: int = int(deal.get("buyer", MarketOrder.WORLD))
		if not _paid_by_a_court(buyer):
			# The standing world counterparty is no court: nobody paid a clear
			# price, so there is no share to take from it (wiki:
			# world-market-first-right-of-refusal § Eligibility — "another GP
			# buys those units"; § Treasury transfer D4).
			continue
		var gross: float = float(quantity) * price
		gross_total += gross
		var owner: int = _owner(purchased_for, deal)
		var owner_credit: float = 0.0
		if owner >= 0 and owner != buyer:
			owner_credit = profit(float(relation_for.call(owner, seller)), quantity, price)
			by_gp[owner] = float(by_gp.get(owner, 0.0)) + owner_credit
			owner_total += owner_credit
		var kickbacks: Array[Dictionary] = []
		for gp: int in FactionCatalog.great_power_ids():
			if gp == owner:
				continue
			if not bool(embassy_for.call(gp, seller)):
				continue
			var credit: float = kickback(float(relation_for.call(gp, seller)), quantity, price)
			if credit <= 0.0:
				continue
			by_gp[gp] = float(by_gp.get(gp, 0.0)) + credit
			kickback_total += credit
			kickbacks.append({"faction": gp, "credit": credit})
		rows.append({
			"seller": seller,
			"buyer": buyer,
			"commodity": String(deal.get("commodity", "")),
			"quantity": quantity,
			"price": price,
			"owner": owner,
			"owner_credit": owner_credit,
			"kickbacks": kickbacks,
		})
	return {
		"by_gp": by_gp,
		"rows": rows,
		"gross": gross_total,
		"owner_total": owner_total,
		"kickback_total": kickback_total,
		"sink": maxf(gross_total - owner_total - kickback_total, 0.0),
	}


## Only a Great Power's clear price funds an overseas share; the standing world
## counterparty (no court) pays nothing, so it owes nothing.
static func _paid_by_a_court(faction: int) -> bool:
	return FactionCatalog.type_of(faction) == FactionCatalog.Type.GREAT_POWER


static func _owner(purchased_for: Callable, deal: Dictionary) -> int:
	var region: int = int(deal.get("origin_region", MarketOrder.NO_ORIGIN))
	var index: int = int(deal.get("origin_index", MarketOrder.NO_ORIGIN))
	if region < 0 or index < 0:
		return -1
	return int(purchased_for.call(region, index))
