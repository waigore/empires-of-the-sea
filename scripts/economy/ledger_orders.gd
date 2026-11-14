class_name LedgerOrders
extends RefCounted
## The ledger's and the college's button presses as intents: a trade staged on
## the book, an order withdrawn, a production row set, a worker hired or
## disbanded, a study started, dropped or re-funded.
##
## Each intent asks the rules (`MarketOrders`, `PlayerEconomy`,
## `ResearchFunding`) for its verdict and reports through the controller's one
## toast/repaint surface, so the sheet never decides an outcome and the
## controller never spells one out (REQ-P2-03, REQ-P3-03).

## The controller this order belongs to; it owns the ledger, the views and the
## panel refresh the verdict is reported on.
var host: EconomyController = null


func _init(p_host: EconomyController = null) -> void:
	host = p_host


## Stages one bid or offer on the shared book. The rules cap it: a bid by the
## holds and purse it needs, an offer by stock after the assigned runs eat their
## inputs (wiki: world-market § Trade orders).
func trade(commodity: String, quantity: int, is_buy: bool) -> Dictionary:
	if host == null or host.market == null or host.economy == null:
		return {}
	var market: WorldMarket = host.market
	var result: Dictionary
	if is_buy:
		var cargo: Dictionary = host.readings.trade_cargo()
		result = MarketOrders.submit(
			market,
			host.player_faction, commodity, MarketOrder.SIDE_BID, quantity,
			{
				"cargo_free": int(cargo.get("clear_free", cargo.get("free", 0))),
				"treasury": host.economy.treasury,
				"tech_unlocked": host.economy.tech_unlocked,
				"buy_price": market.buy_price(commodity, host.player_faction),
			}
		)
	else:
		result = MarketOrders.submit(
			market,
			host.player_faction, commodity, MarketOrder.SIDE_OFFER, quantity,
			{
				"stock": host.economy.quantity(commodity),
				# The assigned runs eat their inputs before the auction clears
				# (wiki: world-market § Trade orders — offer cap; the AI planners
				# reserve the same tons).
				"reserved": ProductionRecipes.reserved_inputs(
					host.economy.production.assignments()
				),
			},
			2
		)
	if bool(result.get("ok", false)):
		var side: String = "Bid" if is_buy else "Offer"
		_toast("%s staged: %d %s. The market clears when the turn closes." % [
			side, quantity, CommodityCatalog.label(commodity)
		])
	else:
		_toast(String(result.get("reason", "Trade refused")))
	host.refresh_panel()
	return result


## A Minor or Tribe harvest row: the offer id names the commodity it sells.
func offer(offer_id: String, quantity: int) -> void:
	if host == null or host.market == null:
		return
	var index: int = MinorMarket.index_of(host.market.minor_offers, offer_id)
	if index < 0:
		_toast("That court has nothing left to sell this turn.")
		return
	var commodity: String = String(
		(host.market.minor_offers[index] as Dictionary).get("commodity", "")
	)
	trade(commodity, quantity, true)


## Cancels one staged order; carry-forward orders are left alone.
func withdraw(order_id: String) -> void:
	if host == null or host.market == null:
		return
	if not MarketOrders.cancel(host.market, host.player_faction, order_id):
		_toast("That order can no longer be withdrawn.")
	host.refresh_panel()


func set_production(recipe_id: String, units: int) -> void:
	if host == null or host.economy == null:
		return
	host.economy.production.set_assignment(recipe_id, units)
	host.refresh_panel()


## One worker action from the ledger. Recruit only queues: the crown pays in
## Build/work and the new worker takes up its labour the turn after
## (wiki: workers-and-population § Phase placement). Disband demotes one trained
## worker to a peasant at once and refunds nothing — the rules own both verdicts.
func worker_action(tier: int, action: String) -> void:
	if host == null or host.economy == null:
		return
	if action == "disband":
		var blocked: String = host.economy.disband_blocked_reason(tier)
		var sent: bool = blocked.is_empty() and host.economy.disband(tier)
		if sent:
			_toast(
				"One %s returns to the fields — no cost is refunded."
				% WorkerPool.tier_one(tier).to_lower()
			)
		else:
			_toast(blocked if not blocked.is_empty() else "Disband refused")
		host.refresh_panel()
		return
	var result: Dictionary = host.economy.queue_recruit(tier)
	if bool(result.get("ok", false)):
		_toast(
			"One %s is engaged — they arrive next turn"
			% WorkerPool.tier_one(tier).to_lower()
		)
	else:
		_toast(String(result.get("reason", "Recruit refused")))
	host.refresh_panel()


func assign_research(tech_id: String) -> void:
	if host == null or host.economy == null:
		return
	host.report_research(host.economy.research.assign(tech_id))


func cancel_research(slot: int) -> void:
	if host == null or host.economy == null:
		return
	host.report_research(host.economy.research.cancel(slot))


func cycle_research_funding(slot: int) -> void:
	if host == null or host.economy == null:
		return
	host.economy.research.cycle_funding(slot)
	host.report_funding()


func _toast(message: String) -> void:
	if host != null and host.hud != null:
		host.hud.toast(message)
