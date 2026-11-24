class_name EconomySheet
extends RefCounted
## The ledger's and the college's sheet surface: which sheet stands, what the
## sheet is painted from, and the picks it marks (REQ-P3-01, REQ-P3-03).
##
## The sheet is a reading of the ledger, never an order: every figure comes from
## [LedgerReadings] or the published pick helpers, and a press never lands here.
## [EconomyController] owns the mount, the turn and the verdict toasts and hands
## this module the panels to live on, so the mount's argument list is written
## once instead of once per door (open, repaint on a closing turn or an auction).

## The controller this surface belongs to; it owns the ledger and the HUD.
var host: EconomyController = null


func _init(p_host: EconomyController = null) -> void:
	host = p_host


## Shows the ledger sheet: the harvest, the staging book, the crown's purse and
## the passes the published planners would book, so the rows they name can wear
## the court's mark (wiki: world-market § Trade orders; DR-20261121-07/09).
func open_ledger() -> void:
	if host == null or host.hud == null:
		return
	host.hud.panels.show_economy(
		host.economy, host.market, host.readings.projected(),
		host.readings.trade_cargo(), host.market.minor_offers, host.player_faction,
		production_pick(), market_pick(), MapPlayRecruitPick.sheet(host.play)
	)


## Repaints the ledger where it stands. A sheet that is not open stays closed:
## nothing is revealed behind the player's back.
func repaint_ledger() -> void:
	if host == null or host.hud == null:
		return
	if host.hud.panels.is_economy_open():
		open_ledger()
	paint_crown()


## Writes the crown's figures on the top bar: purse, the income chip the bills
## promise, this turn's gain (flashed on a closing turn, `gain` other than zero),
## and — when `counts` — the hulls afloat and the regiments afield. One writer,
## so no door can leave a stale figure behind (REQ-P5-05).
func paint_crown(gain: int = 0, projection: Dictionary = {}, counts: bool = false) -> void:
	if host == null or host.hud == null or host.economy == null:
		return
	var stats: HudStatChips = host.hud.stats
	stats.set_treasury(host.economy.treasury)
	if gain != 0:
		stats.flash_income(gain)
	var read: Dictionary = projection
	if read.is_empty():
		read = host.readings.projected()
	stats.set_income(int(read.get("treasury_delta", 0)))
	# The label is the phases' figure. The court's staged orders and the last
	# clearing settle after it, so the plaque names both rather than letting the
	# per-turn number read as the whole purse movement (wiki: world-market
	# § Trade orders; REQ-P5-05).
	stats.set_income_scope(
		int(read.get("staged_orders", 0)),
		LedgerMarketText.clearing_net(
			read.get("clearing", {}) as Dictionary, host.player_faction
		)
	)
	if not counts:
		return
	stats.set_fleets(host.readings.fleet_ships())
	if host.army_layer != null:
		stats.set_armies(host.army_layer.regiment_count_all(host.player_faction))


## Shows the college sheet, with the spy network's boost and the crown's leader
## so the RP figures say why they move (wiki: leader-bonuses — Victoria).
func open_college() -> void:
	if host == null or host.hud == null:
		return
	var pick: Dictionary = research_pick()
	host.hud.panels.show_research(
		host.economy.research, host.economy.treasury, host.research_boost,
		host.leader_key, String(pick.get("line", "")), String(pick.get("tech", ""))
	)


## Repaints the college where it stands: a study, a priority or a funding
## preset moved the figures on the faces the player is already reading.
func repaint_college() -> void:
	if host == null or host.hud == null:
		return
	if host.hud.panels.is_research_open():
		open_college()
	paint_crown()


## The study the published research policy would open in the crown's first free
## slot: the sheet's line and the advance it names, so the AVAILABLE row the
## crown would press can wear the court's mark (wiki: tech-tree § Research model;
## DR-20261121-01, DR-20261122-19). Empty when there is no free slot, no study
## left to open, or no planner behind the seat — the reading, never an order.
func research_pick() -> Dictionary:
	if host == null or host.play == null:
		return {}
	var pick: Dictionary = MapPlayResearchPick.pick(host.play)
	if pick.is_empty():
		return {}
	return {
		"tech": String(pick.get("tech", "")),
		"line": MapPlayPickProse.sentence_of(pick),
	}


## The runs the published economy pass would book for the crown's workshop this
## phase, in the PRODUCTION tab's own voice (wiki: stockpiles-and-production
## § Production flow; DR-20261121-07). Empty when there is no planner behind the
## seat — the reading, never an order.
func production_pick() -> Dictionary:
	if host == null or host.play == null:
		return {}
	var pick: Dictionary = MapPlayProductionPick.pick(host.play)
	if pick.is_empty():
		return {}
	return {
		"kind": pick.get("kind", ""),
		"runs": pick.get("runs", {}),
		"line": MapPlayPickProse.sentence(String(pick.get("line", ""))),
	}


## The trade the published market pass would book for the crown this phase, in
## the MARKET tab's own voice (wiki: world-market § Trade orders;
## DR-20261121-09). Empty when there is no planner behind the seat — the
## reading, never an order.
func market_pick() -> Dictionary:
	if host == null or host.play == null:
		return {}
	var picked: Dictionary = MapPlayMarketPick.pick(host.play)
	if picked.is_empty():
		return {}
	return {
		"kind": picked.get("kind", ""),
		"offers": picked.get("offers", {}),
		"bids": picked.get("bids", {}),
		"line": MapPlayPickProse.sentence(String(picked.get("line", ""))),
	}
