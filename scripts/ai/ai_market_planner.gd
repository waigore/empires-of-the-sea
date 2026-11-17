class_name AiMarketPlanner
extends RefCounted
## Rival world-market participation (wiki: world-market; economy-planner).
##
## A court sells stock above its reserve and bids its purse and free holds on
## short build inputs, through the same WorldMarket as a player's trade
## (REQ-P2-03). Sells spend no holds; imports spend one hold per unit, after
## overseas extraction has taken its reservation (DR-20261109-03, -17).

const BUILD_INPUTS: Array[String] = AiEconomyPlanner.BUILD_INPUTS
## The estate raise's own pair (CivilianWorkPlan.IMPROVEMENT_COSTS): the two
## build inputs every level spends, so their bids lead the cap (#878).
const ESTATE_FEEDSTOCK: Array[String] = ["lumber", "castIron"]
const TRADE_FAIRS: String = "trade_fairs"
## Why a court opens no speculative bid: the war footing holds the slot shut
## (DR-20261117-01).
const REASON_SPECULATE: String = "at war: no top-up"
## Published baseline; Trade Fairs raises the bid-type cap to six.
const BASELINE_BID_TYPES: int = 3
const TRADE_FAIRS_BID_TYPES: int = 6


## Planned orders plus the scored rows that explain them. `free_holds` is what
## the colonies left this turn; `reserved_inputs` is what the court cannot sell
## at all; `need` is the material its next regiment is being provisioned with,
## kept back and bought first (growth-stage-planner § Recruitment modulation);
## `floor` is the purse the caller keeps in hand, so bids never spend the chest.
##
## `food_shortfall` is the ration the court's own people will eat this turn and
## its larder cannot cover. A shortfall opens the wiki's **lock-recovery** mode
## (treasury-planner § Modes): the comfort reserve stops holding stock back, and
## the missing food is bought ahead of every build input out of the whole purse
## rather than the surplus above the war chest. A court that can feed itself
## trades exactly as published.
##
## `saving` is true while the court is on its money goal — its purse stands under
## the reserve it is saving for (the muster at war, its cash floor at peace). The
## lock-recovery liquidation applies only when the comfort reserve has trapped
## the whole hoard, the France shape in issue #489; a normal surplus keeps the
## published reserve.
##
## `speculate` is the dispatch slot (`trade.market`, DR-20261117-01): a court at
## war opens no speculative top-up, so it bids only the rows this turn's
## commitments already claim — the ration, the muster's, the hull's, the works'
## and the production's — and food. A court at peace bids as published.
##
## `works_floor` is the works purse the caller keeps for the court's own land
## (`economy.min_treasury` while the money goal is `earn`, else unset). While
## the court saves, the build inputs are that programme's own provisioning,
## not a deferrable import: they bid out of the works purse, so a court saving
## for a muster or a yard still raises the estates its cash floor can pay for —
## a poorer court keeps its cash floor and grows, research and works first
## (ai-architecture § Land reinforcement; #878). The dispatch slot reads the
## same: the feedstock is one of the commitments the footing keeps.
##
## `hire_margin` is the price of the crew the hire order would take this turn.
## The bids never spend it: a court that has lost a Builder to a conquest and
## sits at its cash floor must still be able to buy another, and the food bid
## and the hire price would otherwise share one margin (issue #894).
static func plan(
	config: AiConfig,
	economy: PlayerEconomy,
	market: WorldMarket,
	free_holds: int,
	tech_unlocked: Dictionary = {},
	reserved_inputs: Dictionary = {},
	need: Dictionary = {},
	floor: int = 0,
	food_shortfall: int = 0,
	saving: bool = false,
	speculate: bool = true,
	works_floor: int = -1,
	hire_margin: int = 0
) -> Dictionary:
	var offers: Array[Dictionary] = []
	var bids: Array[Dictionary] = []
	var candidates: Array[Dictionary] = []
	if config == null or economy == null or market == null:
		return {"offers": offers, "bids": bids, "candidates": candidates}
	var starving: bool = food_shortfall > 0
	var reserve: int = maxi(config.parameter("market.sell_reserve"), 0)
	var promised: Dictionary = _promised(reserved_inputs, need)
	var trapped: bool = saving and _hoard_trapped(economy, market, reserve, promised)
	var sold: Dictionary = {}
	for entry: Dictionary in _surpluses(
		economy, market, reserve, promised, starving or trapped
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
		candidates.append({"kind": "offer", "commodity": id,
			"quantity": quantity, "surplus": int(entry["surplus"])})
	var bid_cap: int = config.parameter("market.max_bid_types")
	if bool(tech_unlocked.get(TRADE_FAIRS, false)):
		bid_cap = TRADE_FAIRS_BID_TYPES
	var budget: int = maxi(
		economy.treasury - maxi(config.parameter("market.min_treasury"), floor), 0
	)
	# The crew the hire order would take this turn is not the market's to spend:
	# a court at its cash floor that has lost a Builder must still be able to buy
	# one, so the bids keep its price back (issue #894).
	var margin: int = maxi(hire_margin, 0)
	budget = maxi(budget - margin, 0)
	# The works purse (#878): the cash the court's own land may draw on while it
	# saves — the war chest stands behind every import above the build inputs.
	var works_budget: int = maxi(
		economy.treasury - maxi(config.parameter("market.min_treasury"), works_floor), 0
	) if works_floor >= 0 else budget
	# Food is not a discretionary spend: a starving court bids out of the whole
	# purse, because a strike costs it every hand (treasury-planner
	# § Lock-recovery) — less the crew it must still be able to hire (issue #894).
	var food_budget: int = (
		maxi(economy.treasury - margin, 0) if starving else budget
	)
	var holds: int = maxi(free_holds, 0)
	var rows: Array[Dictionary] = _deficits(economy, market, reserve, need, promised)
	if starving:
		var food: Array[Dictionary] = _food_deficits(market, food_shortfall)
		food.append_array(rows)
		rows = food
	# A court at war opens no speculative top-up: only the rows this turn's
	# commitments already claim, and food (DR-20261117-01). A saving court's
	# build inputs count among them — without them the estates never rise.
	var held: int = 0
	if not speculate:
		var claimed: Array[Dictionary] = []
		for entry: Dictionary in rows:
			var id: String = String(entry["commodity"])
			if promised.has(id) or CommodityCatalog.is_food(id) or (
				works_floor >= 0 and BUILD_INPUTS.has(id)
			):
				claimed.append(entry)
			else:
				held += 1
		rows = claimed
	for entry: Dictionary in rows:
		if bids.size() >= bid_cap:
			break
		var id: String = String(entry["commodity"])
		if sold.has(id):
			continue
		var price: int = int(entry["price"])
		if price <= 0:
			continue
		# The build inputs are the works programme's own provisioning while the
		# court saves: they draw on the works purse, not the war chest (#878).
		var row_budget: int = food_budget if CommodityCatalog.is_food(id) else (
			works_budget if works_floor >= 0 else budget
		)
		# The ration is bought in full, not in the five-unit trade lot: a court
		# that can only import half its dinner still strikes (wiki:
		# treasury-planner § Lock-recovery).
		var lot: int = (
			int(entry["deficit"]) if CommodityCatalog.is_food(id)
			else config.parameter("market.max_bid_units")
		)
		var quantity: int = mini(int(entry["deficit"]), lot)
		quantity = mini(quantity, holds)
		quantity = mini(quantity, int(row_budget / price))
		if quantity <= 0:
			continue
		bids.append({"commodity": id, "quantity": quantity, "unit_price": price})
		holds -= quantity
		if CommodityCatalog.is_food(id):
			food_budget -= quantity * price
		elif works_floor >= 0:
			works_budget -= quantity * price
		else:
			budget -= quantity * price
		candidates.append({"kind": "bid", "commodity": id, "quantity": quantity,
			"deficit": int(entry["deficit"]), "unit_price": price})
	return {"offers": offers, "bids": bids, "candidates": candidates, "held": held}


## Stages the plan in the world-market order book; the clearing pass fills it at
## the turn's close under the same matcher as the player's orders (wiki:
## world-market § Trade orders).
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


## Applies the plan at once; live play stages orders so the matcher can order
## the book (retained for tools and tests).
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
			sold.append({"commodity": id, "quantity": quantity,
				"revenue": int(result.get("revenue", 0))})
		else:
			refused.append({"kind": "offer", "commodity": id,
				"reason": String(result.get("reason", ""))})
	for raw: Variant in plan.get("bids", []):
		var bid: Dictionary = raw
		var id: String = String(bid.get("commodity", ""))
		var quantity: int = int(bid.get("quantity", 0))
		var result: Dictionary = market.buy(economy, id, quantity, faction)
		if bool(result.get("ok", false)):
			bought.append({"commodity": id, "quantity": quantity,
				"cost": int(result.get("cost", 0))})
		else:
			refused.append({"kind": "bid", "commodity": id,
				"reason": String(result.get("reason", ""))})
	return {"sold": sold, "bought": bought, "refused": refused}


## True when a saving court would offer nothing under the comfort reserve, yet
## still holds stock above its claims: every tradeable row is trapped under
## `market.sell_reserve` (the France shape, issue #489). A court with a normal
## surplus already sells under the published rule and is not trapped.
static func _hoard_trapped(
	economy: PlayerEconomy,
	market: WorldMarket,
	reserve: int,
	reserved_inputs: Dictionary = {}
) -> bool:
	if economy == null or market == null:
		return false
	var any_stock: bool = false
	for id: String in _tradeable_ids(market):
		if CommodityCatalog.is_food(id):
			continue
		var promised: int = int(reserved_inputs.get(id, 0))
		var quantity: int = economy.quantity(id)
		if quantity > promised:
			any_stock = true
		if quantity - reserve - promised > 0:
			return false
	return any_stock


## Tradeable stock above the reserve and above this turn's production inputs,
## richest surplus first. A court in lock-recovery — starving for food, or a
## saving court whose whole non-food hoard sits under the comfort reserve —
## keeps no comfort reserve on anything it is not about to spend: the stock is
## worth more as the food or the regiment it buys than as a hoard beside an
## empty purse (wiki: treasury-planner § Lock-recovery; issue #489). Food itself
## keeps its reserve either way: a court never sells its own dinner.
static func _surpluses(
	economy: PlayerEconomy,
	market: WorldMarket,
	reserve: int,
	reserved_inputs: Dictionary = {},
	liquidate: bool = false
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id: String in _tradeable_ids(market):
		var promised: int = int(reserved_inputs.get(id, 0))
		var keep: int = 0 if liquidate and not CommodityCatalog.is_food(id) else reserve
		var surplus: int = economy.quantity(id) - keep - promised
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


## Build inputs below the reserve, largest shortfall first. The next regiment's
## commodity leads, then the works' claims, then the raise's own pair — the cap
## can never starve the muster, the works or the land programme (wiki:
## growth-stage-planner § Recruitment modulation; #878).
static func _deficits(
	economy: PlayerEconomy, market: WorldMarket, reserve: int, need: Dictionary = {},
	promised: Dictionary = {}
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
		left = promised.has(String(a["commodity"]))
		right = promised.has(String(b["commodity"]))
		if left != right:
			return left
		# The raise's own pair leads the rest, so the bid-type cap cannot be
		# spent on a row the works are not waiting for (issue #878).
		left = ESTATE_FEEDSTOCK.has(String(a["commodity"]))
		right = ESTATE_FEEDSTOCK.has(String(b["commodity"]))
		if left != right:
			return left
		if int(a["deficit"]) != int(b["deficit"]):
			return int(a["deficit"]) > int(b["deficit"])
		return String(a["commodity"]) < String(b["commodity"])
	)
	return rows


## The ration the larder cannot cover, grain first: the one purchase made out
## of the whole purse, because a strike costs every hand (wiki: treasury-planner
## § Lock-recovery; workers-and-population § Consumption).
static func _food_deficits(
	market: WorldMarket, shortfall: int
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var remaining: int = maxi(shortfall, 0)
	for id: String in CommodityCatalog.FOOD:
		if remaining <= 0:
			break
		if not market.can_trade(id):
			continue
		var price: int = market.price(id)
		if price <= 0:
			continue
		rows.append({"commodity": id, "deficit": remaining, "price": price})
		remaining = 0
	return rows


static func _tradeable_ids(market: WorldMarket) -> Array[String]:
	var ids: Array[String] = []
	for id: String in CommodityCatalog.all_ids():
		if market.can_trade(id):
			ids.append(id)
	ids.sort()
	return ids
