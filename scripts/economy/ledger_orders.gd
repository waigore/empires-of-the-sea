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
	if host == null or host.market == null or host.economy == null or seat_held_elsewhere():
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
				# The turn's waiting Build/work orders are paid before the
				# auction clears, so the bid budget is the purse they leave
				# (wiki: world-market § Treasury budget for bids;
				# DR-20261115-13).
				"projected_non_bid_delta": MarketBudget.projected_non_bid_delta(
					host.economy
				),
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
	if seat_held_elsewhere():
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
	if seat_held_elsewhere():
		return
	if not MarketOrders.cancel(host.market, host.player_faction, order_id):
		_toast("That order can no longer be withdrawn.")
	host.refresh_panel()


func set_production(recipe_id: String, units: int) -> void:
	if host == null or host.economy == null:
		return
	if seat_held_elsewhere():
		return
	host.economy.production.set_assignment(recipe_id, units)
	host.refresh_panel()


## The PRODUCTION tab's one press: every run the page's walk planned, set through
## the same assignment a row's "+" makes, then one repaint and one receipt — the
## press never leaves a lane of per-row lines (REQ-P5-04, REQ-P5-05).
func set_production_batch(plan: Dictionary) -> void:
	if host == null or host.economy == null:
		return
	if seat_held_elsewhere():
		return
	for raw: Variant in plan.keys():
		var recipe_id: String = String(raw)
		host.economy.production.set_assignment(recipe_id, int(plan[raw]))
	host.refresh_panel()
	_toast(ProductionBatch.receipt(plan.size()))


## One worker action from the ledger. Recruit only queues: the crown pays in
## Build/work and the new worker takes up its labour the turn after
## (wiki: workers-and-population § Phase placement). A press may file a batch —
## `count` heads, each paying its own published cost — and the toast names how
## many landed and why a batch stopped short (REQ-P5-04, REQ-P5-05). Disband
## demotes one trained worker to a peasant at once and refunds nothing — the
## rules own both verdicts.
func worker_action(tier: int, action: String, count: int = 1) -> void:
	if host == null or host.economy == null:
		return
	if seat_held_elsewhere():
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
	var result: Dictionary = host.economy.queue_recruit(tier, count)
	var queued: int = int(result.get("queued", 0))
	var asked: int = int(result.get("asked", maxi(count, 1)))
	if queued <= 0:
		_toast(String(result.get("reason", "Recruit refused")))
		host.refresh_panel()
		return
	var line: String
	if queued == 1:
		line = "One %s is engaged — they arrive next turn" % WorkerPool.tier_one(tier).to_lower()
	else:
		line = "%d %s are engaged — %s, arriving next turn" % [
			queued,
			WorkerPool.tier_name(tier).to_lower(),
			LedgerWorkersText.recruit_batch_cost(tier, queued),
		]
	if queued < asked:
		line += " (%d of %d — %s)" % [
			queued, asked, String(result.get("reason", "")).to_lower()
		]
	_toast(line)
	host.refresh_panel()


func assign_research(tech_id: String) -> void:
	if host == null or host.economy == null:
		return
	if seat_held_elsewhere():
		return
	host.report_research(host.economy.research.assign(tech_id))


func cancel_research(slot: int) -> void:
	if host == null or host.economy == null:
		return
	if seat_held_elsewhere():
		return
	host.report_research(host.economy.research.cancel(slot))


func cycle_research_funding(slot: int) -> void:
	if host == null or host.economy == null:
		return
	if seat_held_elsewhere():
		return
	host.economy.research.cycle_funding(slot)
	host.report_funding()


## The college's one press: every study under way takes `preset` in one act, and
## the receipt names what moved and what the college pays a turn (wiki: tech-tree
## § Research Model; DR-20261118-26; REQ-P5-04, REQ-P5-05). The rows are filed
## through the published `set_funding`, so no rule, preset, floor or save key
## moves — only the taps a crown would have made one row at a time.
func fund_research_all(preset: String) -> void:
	if host == null or host.economy == null:
		return
	if seat_held_elsewhere():
		return
	var rows: Array[Dictionary] = ResearchBatch.apply(host.economy.research, preset)
	if not rows.is_empty():
		_toast(ResearchBatch.receipt(
			ResearchBatch.plan(host.economy.research, preset, host.economy.treasury)
		))
	host.report_funding()


## Auto holds the crown's seat: the ledger and the college stay readable, but
## no press on them raises an order (wiki: auto-mode § Read-only while it runs).
func seat_held_elsewhere() -> bool:
	return host != null and MapPlayAuto.blocks_orders(host.play)


func _toast(message: String) -> void:
	if host != null and host.hud != null:
		host.hud.toast(message)
