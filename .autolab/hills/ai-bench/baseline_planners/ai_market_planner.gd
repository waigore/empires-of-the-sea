class_name MainlineAiMarketPlanner
extends RefCounted
## Rival world-market participation (wiki: world-market; economy-planner).
##
## A court sells stock above its reserve and bids its purse and free holds on
## short build inputs. Every order goes through WorldMarket, so prices, treasury
## and cargo obey the same rules as a player's trade (REQ-P2-03). Sells spend no
## holds; imports spend one hold per unit, after overseas extraction has taken
## its reservation (DR-20261109-03, DR-20261109-17).

const BUILD_INPUTS: Array[String] = MainlineAiEconomyPlanner.BUILD_INPUTS
const TRADE_FAIRS: String = "trade_fairs"
## Published baseline; Trade Fairs raises the bid-type cap to six.
const BASELINE_BID_TYPES: int = 3
const TRADE_FAIRS_BID_TYPES: int = 6


## Planned orders plus the scored rows that explain them.
## `free_holds` is what the colonies left this turn, never the raw fleet total.
## `reserved_inputs` is what the court cannot sell at all; `need` is the material
## its next regiment is being provisioned with, which it keeps back and buys
## first (wiki: growth-stage-planner § Recruitment modulation). `floor` is the
## purse the caller keeps in hand — its cash floor and, at war, the muster it is
## saving for — so bids never spend the war chest.
static func plan(
	config: MainlineAiConfig,
	economy: PlayerEconomy,
	market: WorldMarket,
	free_holds: int,
	tech_unlocked: Dictionary = {},
	reserved_inputs: Dictionary = {},
	need: Dictionary = {},
	floor: int = 0
) -> Dictionary:
	var offers: Array[Dictionary] = []
	var bids: Array[Dictionary] = []
	var candidates: Array[Dictionary] = []
	if config == null or economy == null or market == null:
		return {"offers": offers, "bids": bids, "candidates": candidates}
	var reserve: int = maxi(config.parameter("market.sell_reserve"), 0)
	var sold: Dictionary = {}
	for entry: Dictionary in _surpluses(
		economy, market, reserve, _promised(reserved_inputs, need)
	):
		if offers.size() >= config.parameter("market.max_offer_types"):
			break
		var id: String = String(entry["commodity"])
		var quantity: int = mini(
			int(entry["surplus"]), config.parameter("market.max_offer_units")
		)
		if quantity <= 0:
			continue
		offers.append({"commodity": id, "quantity": quantity})
		sold[id] = true
		candidates.append({
			"kind": "offer",
			"commodity": id,
			"quantity": quantity,
			"surplus": int(entry["surplus"]),
		})
	var bid_cap: int = config.parameter("market.max_bid_types")
	if bool(tech_unlocked.get(TRADE_FAIRS, false)):
		bid_cap = TRADE_FAIRS_BID_TYPES
	var budget: int = maxi(
		economy.treasury - maxi(config.parameter("market.min_treasury"), floor), 0
	)
	var holds: int = maxi(free_holds, 0)
	for entry: Dictionary in _deficits(economy, market, reserve, need):
		if bids.size() >= bid_cap:
			break
		var id: String = String(entry["commodity"])
		if sold.has(id):
			continue
		var price: int = int(entry["price"])
		if price <= 0:
			continue
		var quantity: int = mini(
			int(entry["deficit"]), config.parameter("market.max_bid_units")
		)
		quantity = mini(quantity, holds)
		quantity = mini(quantity, int(budget / price))
		if quantity <= 0:
			continue
		bids.append({"commodity": id, "quantity": quantity, "unit_price": price})
		holds -= quantity
		budget -= quantity * price
		candidates.append({
			"kind": "bid",
			"commodity": id,
			"quantity": quantity,
			"deficit": int(entry["deficit"]),
			"unit_price": price,
		})
	return {"offers": offers, "bids": bids, "candidates": candidates}


## Stages the plan in the world-market order book. The clearing pass fills it at
## the turn's close, so stock and treasury move once, under the same matcher as
## the player's orders (wiki: world-market § Trade orders).
static func stage(
	economy: PlayerEconomy,
	market: WorldMarket,
	plan: Dictionary,
	faction: int = FactionCatalog.PLAYER_FACTION,
	tech_unlocked: Dictionary = {}
) -> Dictionary:
	var staged: Array[Dictionary] = []
	var refused: Array[Dictionary] = []
	if economy == null or market == null:
		return {"staged": staged, "refused": refused, "plan": plan}
	var cargo: int = maxi(int(plan.get("free_holds", 0)), 0)
	for raw: Variant in plan.get("offers", []):
		var offer: Dictionary = raw
		var id: String = String(offer.get("commodity", ""))
		var quantity: int = int(offer.get("quantity", 0))
		var result: Dictionary = MarketOrders.submit(
			market,
			faction, id, MarketOrder.SIDE_OFFER, quantity,
			{"stock": economy.quantity(id)}, 2
		)
		if bool(result.get("ok", false)):
			staged.append({"kind": "offer", "commodity": id, "quantity": quantity})
		else:
			refused.append({
				"kind": "offer", "commodity": id,
				"reason": String(result.get("reason", "")),
			})
	for raw: Variant in plan.get("bids", []):
		var bid: Dictionary = raw
		var id: String = String(bid.get("commodity", ""))
		var quantity: int = int(bid.get("quantity", 0))
		var result: Dictionary = MarketOrders.submit(
			market,
			faction, id, MarketOrder.SIDE_BID, quantity,
			{
				"cargo_free": cargo,
				"treasury": economy.treasury,
				"tech_unlocked": tech_unlocked,
				"buy_price": market.buy_price(id, faction),
			},
			1
		)
		if bool(result.get("ok", false)):
			staged.append({"kind": "bid", "commodity": id, "quantity": quantity})
		else:
			refused.append({
				"kind": "bid", "commodity": id,
				"reason": String(result.get("reason", "")),
			})
	return {"staged": staged, "refused": refused, "plan": plan}


## Applies the plan through the shared market at once. Retained for tools and
## tests; live play stages orders so the matcher can order the book.
static func apply(
	economy: PlayerEconomy,
	market: WorldMarket,
	plan: Dictionary,
	faction: int = FactionCatalog.PLAYER_FACTION
) -> Dictionary:
	var sold: Array[Dictionary] = []
	var bought: Array[Dictionary] = []
	var refused: Array[Dictionary] = []
	if economy == null or market == null:
		return {"sold": sold, "bought": bought, "refused": refused}
	for raw: Variant in plan.get("offers", []):
		var offer: Dictionary = raw
		var id: String = String(offer.get("commodity", ""))
		var quantity: int = int(offer.get("quantity", 0))
		var result: Dictionary = market.sell(economy, id, quantity, faction)
		if bool(result.get("ok", false)):
			sold.append({
				"commodity": id,
				"quantity": quantity,
				"revenue": int(result.get("revenue", 0)),
			})
		else:
			refused.append({
				"kind": "offer",
				"commodity": id,
				"reason": String(result.get("reason", "")),
			})
	for raw: Variant in plan.get("bids", []):
		var bid: Dictionary = raw
		var id: String = String(bid.get("commodity", ""))
		var quantity: int = int(bid.get("quantity", 0))
		var result: Dictionary = market.buy(economy, id, quantity, faction)
		if bool(result.get("ok", false)):
			bought.append({
				"commodity": id,
				"quantity": quantity,
				"cost": int(result.get("cost", 0)),
			})
		else:
			refused.append({
				"kind": "bid",
				"commodity": id,
				"reason": String(result.get("reason", "")),
			})
	return {"sold": sold, "bought": bought, "refused": refused}


## Tradeable stock above the reserve and above this turn's production inputs,
## richest surplus first.
static func _surpluses(
	economy: PlayerEconomy,
	market: WorldMarket,
	reserve: int,
	reserved_inputs: Dictionary = {}
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id: String in _tradeable_ids(market):
		var promised: int = int(reserved_inputs.get(id, 0))
		var surplus: int = economy.quantity(id) - reserve - promised
		if surplus > 0:
			rows.append({"commodity": id, "surplus": surplus})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["surplus"]) != int(b["surplus"]):
			return int(a["surplus"]) > int(b["surplus"])
		return String(a["commodity"]) < String(b["commodity"])
	)
	return rows


## Stores the court must not sell. Both sets are added, not maxed: every claim
## consumes the store (wiki: economy-planner § Reservations; growth-stage-planner
## § Recruitment modulation).
static func _promised(
	reserved_inputs: Dictionary, need: Dictionary
) -> Dictionary:
	if need.is_empty():
		return reserved_inputs
	var promised: Dictionary = reserved_inputs.duplicate()
	for commodity: Variant in need.keys():
		var id: String = String(commodity)
		promised[id] = int(promised.get(id, 0)) + int(need[commodity])
	return promised


## Build inputs below the reserve, largest shortfall first. A commodity the next
## regiment is being provisioned with leads, so the court buys its cloth before
## it buys the rest and the bid-type cap cannot starve the muster (wiki:
## growth-stage-planner § Recruitment modulation).
static func _deficits(
	economy: PlayerEconomy, market: WorldMarket, reserve: int, need: Dictionary = {}
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id: String in BUILD_INPUTS:
		if not market.can_trade(id):
			continue
		var deficit: int = reserve - economy.quantity(id)
		if deficit > 0:
			rows.append({
				"commodity": id,
				"deficit": deficit,
				"price": market.price(id),
			})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left: bool = need.has(String(a["commodity"]))
		var right: bool = need.has(String(b["commodity"]))
		if left != right:
			return left
		if int(a["deficit"]) != int(b["deficit"]):
			return int(a["deficit"]) > int(b["deficit"])
		return String(a["commodity"]) < String(b["commodity"])
	)
	return rows


static func _tradeable_ids(market: WorldMarket) -> Array[String]:
	var ids: Array[String] = []
	for id: String in CommodityCatalog.all_ids():
		if market.can_trade(id):
			ids.append(id)
	ids.sort()
	return ids