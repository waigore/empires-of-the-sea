class_name MapPlayEconomyAi
extends RefCounted
## Rival economy turn (docs/ai.md): resolves extraction, market and production
## for every rival, driving `AiEconomyPlanner` / `AiMarketPlanner` and applying
## the legal orders, and reports the trace (REQ-P2-03, REQ-P3-03).
##
## One court's plan and its application live in `MapPlayEconomyCourt`, so a
## court's ledger turns once and its report row cannot drift from the orders it
## booked. The civilian pass lives in `MapPlayCivilianAi`; the ledger side — the
## overseas yield, the food demand and the reservation rows — lives in
## `MapPlayEconomyLarder`, so neither this walk nor the crown's picks own the
## other's domain (REQ-P3-01, REQ-P3-02).


## Resolves every rival economy once, then plans the next turn. Call after the
## Build/Work pass and before the player's own economy so both read the works
## that just completed.
static func run(play: PlaySession) -> Dictionary:
	var report: Dictionary = {"factions": {}, "orders": []}
	if play == null or play.world == null or play.civilian_layer == null:
		return report
	play.ensure_ai()
	var by_faction: Dictionary = report["factions"]
	var order_log: Array = report["orders"]
	var market: WorldMarket = MapPlayEconomyLarder.market(play)
	# Every rival ledger exists before any court resolves, so a spy observing a
	# court later in the order still reads its known techs this turn.
	MapPlaySpyAi.prepare_ledgers(play)
	for faction: int in MapPlayCourt.planning_factions(play):
		var row: Dictionary = _court_row(play, faction, market)
		order_log.append_array((row.get("civilians", {}) as Dictionary).get("orders", []))
		by_faction[faction] = row
	# Every rival ledger just closed, so the next land battle reads the rations
	# each crown actually got — not full morale by default (wiki: combat
	# § Feeding modifiers; workers-and-population § Consumption). Observer mode
	# still reapplies from MapPlayTurn; a second pass is idempotent.
	AiTurnLog.apply_feeding(play, report)
	return report


## One court's row: a BENCH filler draws seeded random legal orders, a planned
## court runs its full economy turn through `MapPlayEconomyCourt`.
static func _court_row(play: PlaySession, faction: int, market: WorldMarket) -> Dictionary:
	if AiControl.court_kind(play, faction) == AiControl.KIND_RANDOM:
		var economy: PlayerEconomy = play.ai.economy_for(faction)
		MapPlayCivilianAi.seed(play, faction)
		return AiRandomCourt.economy(
			play, faction, market,
			MapPlayEconomyLarder.overseas(play, faction, economy)
		)
	var court: MapPlayEconomyCourt = MapPlayEconomyCourt.open(play, faction, market)
	court.plan_turn()
	return court.apply_turn()
