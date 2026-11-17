class_name MarketPressure
extends RefCounted
## What a court's stores press on the world market, read as rows: the stock it
## can spare, the build inputs it is short of and the ration its larder cannot
## cover (wiki: world-market; economy-planner § Reservations; treasury-planner
## § Lock-recovery; growth-stage-planner § Recruitment modulation).
##
## Pure projections over one court and the book: state in, scored rows out, so a
## headless test drives exactly the rows the planner reads. AiMarketPlanner
## keeps the court's own purses, bid caps and dispatch; the row maths lives here.


## Stores the court must not sell. Both sets are added, not maxed: every claim
## consumes the store (wiki: economy-planner § Reservations; growth-stage-planner
## § Recruitment modulation).
static func promised(
	reserved_inputs: Dictionary, need: Dictionary
) -> Dictionary:
	if need.is_empty():
		return reserved_inputs
	var claims: Dictionary = reserved_inputs.duplicate()
	for commodity: Variant in need.keys():
		var id: String = String(commodity)
		claims[id] = int(claims.get(id, 0)) + int(need[commodity])
	return claims


## True when a saving court would offer nothing under the comfort reserve, yet
## still holds stock above its claims: every tradeable row is trapped under
## `reserve` (the France shape, issue #489). A court with a normal surplus
## already sells under the published rule and is not trapped.
static func hoard_trapped(
	economy: PlayerEconomy,
	market: WorldMarket,
	reserve: int,
	reserved_inputs: Dictionary = {}
) -> bool:
	if economy == null or market == null:
		return false
	var any_stock: bool = false
	for id: String in tradeable_ids(market):
		if CommodityCatalog.is_food(id):
			continue
		var claims: int = int(reserved_inputs.get(id, 0))
		var quantity: int = economy.quantity(id)
		if quantity > claims:
			any_stock = true
		if quantity - reserve - claims > 0:
			return false
	return any_stock


## Tradeable stock above the reserve and above this turn's production inputs,
## richest surplus first. A court in lock-recovery — starving for food, or a
## saving court whose whole non-food hoard sits under the comfort reserve —
## keeps no comfort reserve on anything it is not about to spend: the stock is
## worth more as the food or the regiment it buys than as a hoard beside an
## empty purse (wiki: treasury-planner § Lock-recovery; issue #489). Food itself
## keeps its reserve either way: a court never sells its own dinner.
static func surpluses(
	economy: PlayerEconomy,
	market: WorldMarket,
	reserve: int,
	reserved_inputs: Dictionary = {},
	liquidate: bool = false
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if economy == null or market == null:
		return rows
	for id: String in tradeable_ids(market):
		var claims: int = int(reserved_inputs.get(id, 0))
		var keep: int = 0 if liquidate and not CommodityCatalog.is_food(id) else reserve
		var surplus: int = economy.quantity(id) - keep - claims
		if surplus > 0:
			rows.append({"commodity": id, "surplus": surplus})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["surplus"]) != int(b["surplus"]):
			return int(a["surplus"]) > int(b["surplus"])
		return String(a["commodity"]) < String(b["commodity"])
	)
	return rows


## Build inputs below the reserve, largest shortfall first. The next regiment's
## commodity leads, then the works' claims, then the raise's own feedstock — the
## bid-type cap can never starve the muster, the works or the land programme
## (wiki: growth-stage-planner § Recruitment modulation; #878).
static func deficits(
	economy: PlayerEconomy,
	market: WorldMarket,
	build_inputs: Array[String],
	reserve: int,
	need: Dictionary = {},
	promised: Dictionary = {},
	lead: Array[String] = []
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if economy == null or market == null:
		return rows
	for id: String in build_inputs:
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
		# The raise's own feedstock leads the rest, so the bid-type cap cannot
		# be spent on a row the works are not waiting for (issue #878).
		left = lead.has(String(a["commodity"]))
		right = lead.has(String(b["commodity"]))
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
static func food_deficits(
	market: WorldMarket, shortfall: int
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if market == null:
		return rows
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


## The commodities this book prices, sorted, so every pass reads one order.
static func tradeable_ids(market: WorldMarket) -> Array[String]:
	var ids: Array[String] = []
	if market == null:
		return ids
	for id: String in CommodityCatalog.all_ids():
		if market.can_trade(id):
			ids.append(id)
	ids.sort()
	return ids
