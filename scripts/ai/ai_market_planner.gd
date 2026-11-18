class_name AiMarketPlanner
extends RefCounted
## Rival world-market participation (wiki: world-market; economy-planner).
##
## A court sells stock above its reserve and bids its purse and free holds on
## short build inputs, through the same WorldMarket as a player's trade
## (REQ-P2-03). Sells spend no holds; imports spend one hold per unit, after
## overseas extraction has taken its reservation (DR-20261109-03, -17).
##
## The rows themselves — what is promised, trapped, spare, short, or the ration
## the larder cannot cover — are MarketPressure's. This planner keeps the
## court's own policy: the purses, the caps and the dispatch slot.

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
## same: the feedstock is one of the commitments the footing keeps. `hire_margin` is the crew price the bids never spend (#894).
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
	works_floor: int = -1, hire_margin: int = 0
) -> Dictionary:
	if config == null or economy == null or market == null:
		return {"offers": [], "bids": [], "candidates": []}
	var starving: bool = food_shortfall > 0
	var reserve: int = maxi(config.parameter("market.sell_reserve"), 0)
	var promised: Dictionary = MarketPressure.promised(reserved_inputs, need)
	var trapped: bool = (
		saving and MarketPressure.hoard_trapped(economy, market, reserve, promised)
	)
	var offers: Array[Dictionary] = []
	var bids: Array[Dictionary] = []
	var candidates: Array[Dictionary] = []
	var sold: Dictionary = {}
	_offer_book(
		config, economy, market, reserve, promised, starving or trapped,
		offers, candidates, sold
	)
	var rows: Array[Dictionary] = _bid_rows(
		economy, market, reserve, need, promised, starving, food_shortfall
	)
	var held: int = _claim_rows(rows, promised, works_floor, speculate)
	var bid_cap: int = config.parameter("market.max_bid_types")
	if bool(tech_unlocked.get(TRADE_FAIRS, false)):
		bid_cap = TRADE_FAIRS_BID_TYPES
	var purses: Dictionary = _purses(
		config, economy, floor, works_floor, starving, hire_margin
	)
	_bid_book(
		config, rows, sold, purses, maxi(free_holds, 0), works_floor, bid_cap,
		bids, candidates
	)
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


# --- the plan's row book ----------------------------------------------------


## Offers the court can spare, capped by type and size; `sold` records what the
## bids may no longer buy. Mutates the output rows in place (Array/Dictionary
## are passed by reference), so the plan keeps one flat candidate trace.
static func _offer_book(
	config: AiConfig,
	economy: PlayerEconomy,
	market: WorldMarket,
	reserve: int,
	promised: Dictionary,
	liquidate: bool,
	offers: Array[Dictionary],
	candidates: Array[Dictionary],
	sold: Dictionary
) -> void:
	for entry: Dictionary in MarketPressure.surpluses(
		economy, market, reserve, promised, liquidate
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


## The rows a court bids this turn, in priority order: the ration first when it
## is starving, then the build-input deficits.
static func _bid_rows(
	economy: PlayerEconomy,
	market: WorldMarket,
	reserve: int,
	need: Dictionary,
	promised: Dictionary,
	starving: bool,
	food_shortfall: int
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = MarketPressure.deficits(
		economy, market, BUILD_INPUTS, reserve, need, promised, ESTATE_FEEDSTOCK
	)
	if not starving:
		return rows
	var food: Array[Dictionary] = MarketPressure.food_deficits(
		market, food_shortfall
	)
	food.append_array(rows)
	return food


## A court at war opens no speculative top-up: only the rows this turn's
## commitments already claim, and food (DR-20261117-01). A saving court's build
## inputs count among them — without them the estates never rise. Returns how
## many rows the footing held back.
static func _claim_rows(
	rows: Array[Dictionary],
	promised: Dictionary,
	works_floor: int,
	speculate: bool
) -> int:
	if speculate:
		return 0
	var claimed: Array[Dictionary] = []
	var held: int = 0
	for entry: Dictionary in rows:
		var id: String = String(entry["commodity"])
		if promised.has(id) or CommodityCatalog.is_food(id) or (
			works_floor >= 0 and BUILD_INPUTS.has(id)
		):
			claimed.append(entry)
		else:
			held += 1
	rows.clear()
	rows.append_array(claimed)
	return held


## The three purses a bid may draw on (#878, treasury-planner § Lock-recovery):
## the general treasury above the caller's floor, the works purse the court's own
## land draws on while it saves, and the ration's — the whole chest, because a
## strike costs every hand. `hire_margin` is the crew price the bids never spend
## (#894).
static func _purses(
	config: AiConfig,
	economy: PlayerEconomy,
	floor: int,
	works_floor: int,
	starving: bool,
	hire_margin: int = 0
) -> Dictionary:
	var margin: int = maxi(hire_margin, 0)
	# A crew whose price the whole purse cannot hold is not banked by a starving
	# court: with its hands down the court earns nothing, so the bank can never
	# grow — the ration takes everything until the purse can hold the crew's
	# price beside the dinner. Otherwise a poor court holds back a price it never
	# reaches, buys no food at all and strikes forever (issue #910).
	if starving and economy.treasury <= margin:
		margin = 0
	var budget: int = maxi(
		economy.treasury - maxi(config.parameter("market.min_treasury"), floor) - margin,
		0
	)
	return {
		"general": budget,
		"works": maxi(
			economy.treasury - maxi(config.parameter("market.min_treasury"), works_floor),
			0
		) if works_floor >= 0 else budget,
		"food": maxi(economy.treasury - margin, 0) if starving else budget,
	}


## Bids down the rows until a purse, the holds or the type cap runs out; each
## accepted row draws on its own purse.
static func _bid_book(
	config: AiConfig,
	rows: Array[Dictionary],
	sold: Dictionary,
	purses: Dictionary,
	holds: int,
	works_floor: int,
	bid_cap: int,
	bids: Array[Dictionary],
	candidates: Array[Dictionary]
) -> void:
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
		var purse: String = _purse_for(id, works_floor)
		# The ration is bought in full, not in the five-unit trade lot: a court
		# that can only import half its dinner still strikes (wiki:
		# treasury-planner § Lock-recovery).
		var lot: int = (
			int(entry["deficit"]) if CommodityCatalog.is_food(id)
			else config.parameter("market.max_bid_units")
		)
		var quantity: int = mini(int(entry["deficit"]), lot)
		quantity = mini(quantity, holds)
		quantity = mini(quantity, int(int(purses[purse]) / price))
		if quantity <= 0:
			continue
		bids.append({"commodity": id, "quantity": quantity, "unit_price": price})
		holds -= quantity
		purses[purse] = int(purses[purse]) - quantity * price
		candidates.append({"kind": "bid", "commodity": id, "quantity": quantity,
			"deficit": int(entry["deficit"]), "unit_price": price})


## The purse a row draws on: the ration's, the works' while the court saves out
## of that programme, else the general treasury.
static func _purse_for(id: String, works_floor: int) -> String:
	if CommodityCatalog.is_food(id):
		return "food"
	return "works" if works_floor >= 0 else "general"
