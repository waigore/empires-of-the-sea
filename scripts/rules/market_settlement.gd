class_name MarketSettlement
extends RefCounted
## Post-match world-market settlement (wiki: world-market § Trade orders,
## § Subsidy price adjustment, § Order persistence; world-market-first-right-of-
## refusal). Pays purses and cargo for filled deals, credits first-right profit
## and embassy kickbacks, and carries unfilled Great-Power orders forward. Pure
## rules: every input is data, so a headless test drives exactly the pass the
## clearing does (REQ-P2-03, REQ-P3-03).


## Settles every filled deal: buyer purse, cargo and stock, then seller stock
## and purse. Minor/Tribe sellers have no wallet, so their receipt is the sink.
## Returns {fills, deals} — `deals` keeps only the rows the purse actually paid.
static func settle(
	market: WorldMarket,
	economies: Dictionary,
	deals: Array[Dictionary],
	context: Dictionary,
	notes: Array[Dictionary]
) -> Dictionary:
	var fills: Dictionary = {}
	var kept: Array[Dictionary] = []
	var diplomacy: DiplomacyState = context.get("diplomacy", null)
	for deal: Dictionary in deals:
		var buyer: int = int(deal.get("buyer", MarketOrder.WORLD))
		var seller: int = int(deal.get("seller", MarketOrder.WORLD))
		var commodity: String = String(deal.get("commodity", ""))
		var quantity: int = int(deal.get("quantity", 0))
		if quantity <= 0 or commodity.is_empty():
			continue
		var subsidy: int = subsidy_percent(context, buyer, seller)
		var unit_price: int = buy_unit(market, commodity, buyer, seller, subsidy)
		var bid_quantity: int = quantity
		var buyer_economy: PlayerEconomy = economy(economies, buyer)
		if buyer_economy != null:
			# The debt rounds once from the whole deal, so the per-unit charge
			# cannot say whether one more ton fits (wiki: world-market
			# § Treasury budget for bids — the resolver-side clamp).
			quantity = MarketRules.payable_units(
				market, commodity, quantity, buyer, seller, subsidy,
				buyer_economy.treasury
			)
			if quantity != bid_quantity:
				notes.append({
					"code": "bid_partial_fill_treasury_insufficient",
					"faction": buyer,
					"commodity": commodity,
					"quantity": bid_quantity - quantity,
				})
		var cost: int = MarketRules.deal_total_for(
			market, commodity, quantity, buyer, seller, subsidy, true
		)
		# A purse that cannot pay is not a sale: nothing changes hands.
		if quantity <= 0 or (
			buyer_economy != null
			and not market.settle_purchase(buyer_economy, commodity, quantity, buyer, cost)
		):
			continue
		kept.append(deal)
		# A settled deal lifts its pair's relation next turn (wiki: diplomacy
		# § Relation Model — trade-deal boost, R10). Volume-independent; the
		# state drops the world counterparty and Minor-to-Minor pairs.
		if diplomacy != null:
			DiplomacyTrade.record_deal(diplomacy, buyer, seller)
		# The row carries what the clearing actually settled, not what the matcher
		# proposed: the debt is rounded once from the whole deal, so the Deal Book
		# must read the charged total (wiki: world-market § Subsidy price
		# adjustment — "never a sum of per-unit roundings"; REQ-P5-05).
		deal["quantity"] = quantity
		deal["cost"] = cost
		deal["buy_unit"] = unit_price
		deal["subsidy_percent"] = subsidy
		var seller_economy: PlayerEconomy = economy(economies, seller)
		var proceeds: int = 0
		if seller_economy != null:
			seller_economy.take(commodity, quantity)
			proceeds = MarketRules.deal_total_for(
				market, commodity, quantity, buyer, seller, subsidy, false
			)
			seller_economy.add_treasury(proceeds)
			# The receipt names the ducats, not only the tons (REQ-P5-05): a sale
			# is the one trade a court cannot see the price of in the ledger.
			deal["earned"] = proceeds
		var row: Dictionary = fills.get(buyer, {}) as Dictionary
		row["bought"] = int(row.get("bought", 0)) + quantity
		row["spent"] = int(row.get("spent", 0)) + cost
		fills[buyer] = row
		if seller_economy != null:
			var sold: Dictionary = fills.get(seller, {}) as Dictionary
			sold["sold"] = int(sold.get("sold", 0)) + quantity
			sold["earned"] = int(sold.get("earned", 0)) + proceeds
			fills[seller] = sold
	return {"fills": fills, "deals": kept}


## What the buyer actually pays per unit: the published price times the crown's
## own terms and the pair's subsidy step, inside the rails. The subsidy is a
## step on the deal, so a deal with any other court pays its own terms alone
## (wiki: world-market § Subsidy price adjustment).
static func buy_unit(
	market: WorldMarket, commodity: String, buyer: int, seller: int, subsidy_percent: int
) -> int:
	if buyer == MarketOrder.WORLD:
		return maxi(market.price(commodity), 1)
	return MarketRules.deal_unit_for(market, commodity, buyer, seller, subsidy_percent, true)


## The subsidy percent the pair carries: a Minor/Tribe sale to its payer, or a
## payer's sale to the subsidised court (wiki: world-market § Subsidy price
## adjustment). A deal between two other courts carries 0.
static func subsidy_percent(context: Dictionary, buyer: int, seller: int) -> int:
	var diplomacy: DiplomacyState = context.get("diplomacy", null)
	if diplomacy == null:
		return 0
	var payer: int = -1
	var target: int = -1
	if MarketRules.is_minor(seller) and buyer >= 0:
		payer = buyer
		target = seller
	elif MarketRules.is_minor(buyer) and seller >= 0:
		payer = seller
		target = buyer
	if payer < 0:
		return 0
	return maxi(diplomacy.subsidy(payer, target), 0)


## Credits the tile-owning court its relation share and every other
## embassy-holding court its 10% kickback.
static func first_right(
	world: WorldMap,
	economies: Dictionary,
	deals: Array[Dictionary],
	context: Dictionary
) -> Dictionary:
	var diplomacy: DiplomacyState = context.get("diplomacy", null)
	var relation_for: Callable = func(gp: int, minor: int) -> float:
		var record: DiplomacyRelation = diplomacy.relation(gp, minor) if diplomacy != null else null
		return record.score if record != null else 0.0
	var embassy_for: Callable = func(gp: int, minor: int) -> bool:
		return diplomacy != null and DiplomacyRules.has_embassy(diplomacy, gp, minor)
	var purchased_for: Callable = func(region: int, index: int) -> int:
		return purchased_owner(world, region, index)
	var result: Dictionary = FirstRight.credits(
		deals, purchased_for, relation_for, embassy_for
	)
	var by_gp: Dictionary = result["by_gp"] as Dictionary
	for raw: Variant in by_gp.keys():
		var found: PlayerEconomy = economy(economies, int(raw))
		if found != null:
			found.add_treasury(roundi(float(by_gp[raw])))
	return result


## Unfilled Great-Power orders carry forward unless their stock or holds no
## longer cover them (wiki: world-market § Order persistence).
static func carry(
	orders: Array[MarketOrder],
	matched: Dictionary,
	economies: Dictionary,
	free_holds: Dictionary,
	notes: Array[Dictionary]
) -> Array[MarketOrder]:
	var out: Array[MarketOrder] = []
	for order: MarketOrder in orders:
		if order.auto or order.is_world() or order.faction < 0:
			continue
		var left: int = residual_for(order, matched)
		if left <= 0:
			continue
		if order.is_bid():
			if int(free_holds.get(order.faction, 0)) < left:
				notes.append({
					"code": "carry_forward_dropped_cargo_insufficient",
					"faction": order.faction,
					"commodity": order.commodity,
					"quantity": left,
				})
				continue
		else:
			var found: PlayerEconomy = economy(economies, order.faction)
			var stock: int = found.quantity(order.commodity) if found != null else 0
			if stock < left:
				notes.append({
					"code": "carry_forward_dropped_stockpile_insufficient",
					"faction": order.faction,
					"commodity": order.commodity,
					"quantity": left,
				})
				continue
		var carried: MarketOrder = order.clone()
		carried.quantity = left
		carried.filled = 0
		out.append(carried)
	return out


static func residual_for(order: MarketOrder, matched: Dictionary) -> int:
	for row: Dictionary in matched["residuals"]:
		if String(row.get("order_id", "")) != order.id:
			continue
		return int(row.get("quantity", 0))
	# A filled order has no residual row.
	return 0


static func purchased_owner(world: WorldMap, region: int, index: int) -> int:
	if world == null or region < 0 or index < 0:
		return -1
	var model: MapModel = world.region(region)
	if model == null:
		return -1
	if not model.ownership.is_purchased(index):
		return -1
	return model.ownership.purchaser(index)


static func economy(economies: Dictionary, faction: int) -> PlayerEconomy:
	var found: Variant = economies.get(faction, null)
	if found == null:
		found = economies.get(str(faction), null)
	return found as PlayerEconomy
