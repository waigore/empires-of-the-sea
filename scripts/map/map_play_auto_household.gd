class_name MapPlayAutoHousehold
extends RefCounted
## Auto mode's household pass (wiki: auto-mode § The crown's household;
## issue #725, #1302, #1433). Plans the crown's works, studies, crews and
## trade through the same economy court a rival seat runs, then words each
## booked kind as a despatch line.
##
## `MapPlayAuto` keeps the lifecycle and pacing; this home owns the household
## plan and its wording (REQ-P3-01, REQ-P3-02). The famine order (shed) speaks
## first when the court sheds mouths its harvest cannot carry.

## Said in place of a household line when the crown runs no planner at all: a
## tick that files nothing still answers, so the seat never reads as broken.
const NO_PLAN_LINE: String = "The crown runs no household plan this turn."


## The crown's household, planned by the pass a rival court runs and booked as
## the player's own presses — the production runs, the workers the Build/work
## phase buys, the crews' work orders, the college's study and the market's
## trade. Opened through `draft`, not `open`, so the seat never seeds a rival's
## opening crew for the crown it does not hire. The crown's ledger is not closed
## here: its own `resolve_turn` carries the orders out where every human turn's
## are, so the seat neither pays twice nor re-times a rule (wiki: auto-mode
## § The crown's household; REQ-P2-03).
static func run(play: PlaySession) -> void:
	if play == null or play.economy == null or play.economy.market == null:
		return
	if not AiControl.plans(play, play.player_faction):
		MapPlayAuto.note(play, NO_PLAN_LINE)
		return
	MapPlayAuto.ensure_seat_ledger(play)
	var court: MapPlayEconomyCourt = MapPlayEconomyCourt.draft(
		play, play.player_faction, play.economy.market
	)
	court.plan_turn()
	# The famine order: a court whose hands have struck past a thin turn sheds
	# the mouths its harvest cannot carry, so the pool is fed and works again
	# (wiki: military-armies § Dismissing regiments; ships-and-naval § The
	# breaker's yard; issue #1433). The crown's own route — a rival court's
	# shed waits on its own pass.
	var shed: Dictionary = MapPlayLarderRecovery.shed(court)
	var row: Dictionary = court.book_orders()
	row["shed"] = shed
	describe(play, row)


## The household's booked row as despatch lines, one per kind it filed: the
## studies it opened, the hands it bought, the ledger work it set and the trade
## it staged. A tick that files nothing says so, because a silent pass reads as
## a broken one (wiki: auto-mode § Pacing).
static func describe(play: PlaySession, row: Dictionary) -> void:
	var lines: Array[String] = []
	# The famine order speaks first: the court sheds mouths before it fills them.
	for raw: Variant in (row.get("shed", {}) as Dictionary).get("lines", []):
		var said: String = String(raw)
		if not said.is_empty():
			lines.append(said)
	for raw: Variant in (row.get("research", {}) as Dictionary).get("assignments", []):
		var tech: String = String((raw as Dictionary).get("tech", ""))
		if not tech.is_empty():
			lines.append("Studies %s" % TechCatalog.display_name(tech))
	var tiers: Dictionary = {}
	for raw: Variant in row.get("recruits", []):
		var tier: int = int((raw as Dictionary).get("tier", -1))
		if tier >= 0:
			tiers[tier] = int(tiers.get(tier, 0)) + 1
	for tier: Variant in tiers.keys():
		var heads: int = int(tiers[tier])
		lines.append("Recruits %d %s" % [heads, WorkerPool.tier_name(int(tier))])
	# One line for the ledger's own work: the runs and the crews' orders are one
	# press each on the tab, so the seat words them as one despatch.
	var runs: int = 0
	for raw: Variant in (row.get("production", {}) as Dictionary).get("assignments", []):
		runs += int((raw as Dictionary).get("units", 0))
	var orders: int = (
		(row.get("civilians", {}) as Dictionary).get("orders", []) as Array
	).size()
	if runs > 0 and orders > 0:
		lines.append("Sets %d run%s and %d work order%s" % [
			runs, "" if runs == 1 else "s", orders, "" if orders == 1 else "s",
		])
	elif runs > 0:
		lines.append("Sets %d production run%s" % [runs, "" if runs == 1 else "s"])
	elif orders > 0:
		lines.append("Sets %d work order%s" % [orders, "" if orders == 1 else "s"])
	for raw: Variant in (row.get("civilians", {}) as Dictionary).get("training", []):
		var crew: String = String((raw as Dictionary).get("type_id", ""))
		if not crew.is_empty():
			lines.append("Hires — %s" % CivilianCatalog.display_name(crew))
	var bids: int = 0
	var offers: int = 0
	for raw: Variant in (row.get("trade", {}) as Dictionary).get("staged", []):
		match String((raw as Dictionary).get("kind", "")):
			"bid":
				bids += 1
			"offer":
				offers += 1
	if bids > 0 and offers > 0:
		lines.append("Trades at the mart — %d bid%s, %d offer%s" % [
			bids, "" if bids == 1 else "s", offers, "" if offers == 1 else "s",
		])
	elif bids > 0:
		lines.append("Bids at the mart — %d good%s" % [bids, "" if bids == 1 else "s"])
	elif offers > 0:
		lines.append("Offers at the mart — %d good%s" % [offers, "" if offers == 1 else "s"])
	if lines.is_empty():
		MapPlayAuto.note(play, "The household files no order this turn.")
		return
	for line: String in lines:
		MapPlayAuto.note(play, line)
