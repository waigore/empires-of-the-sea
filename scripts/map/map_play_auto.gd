class_name MapPlayAuto
extends RefCounted
## Mid-campaign Auto mode (wiki: auto-mode; issue #725): the crown's own seat
## handed to the same planners the rival courts run, paced so the player can
## AFK and watch. `MapPlayAuto` owns the lifecycle, the pacing and the action
## log; the planners and the rules modules decide every outcome, exactly as they
## do for a rival seat (REQ-P2-03, REQ-P3-02).
##
## Deliberately not `observer_mode`: a live campaign keeps its crown, its fog,
## its calendar, saving and its defeat. The debug full-AI observer runs every
## court on whole turns and no human seat at all (docs/ai-observer.md).
##
## One tick closes one of the crown's own passes — the household, crews,
## expeditions, land orders, voyages, sails — in the order `MapPlayTurnFinish`
## runs them for a rival. When the queue drains the rest of the turn (rivals,
## combat, upkeep) resumes through `MapPlayTurnFinish.finish`, so the seat is
## never a silent end-of-turn dump: every resolved order is a line in the log.

## Seconds per tick, indexed by `auto_speed`; 0 freezes mid-sequence.
const SPEED_SECONDS: Array[float] = [0.0, 1.0, 0.5, 0.25]
const SPEED_LABELS: Array[String] = ["PAUSE", "1x", "2x", "3x"]
## The crown's seat, in phase order — the order the rival passes run in. The
## household comes first: a court files its works, its studies and its trade
## before its crews take to the land (wiki: auto-mode § The crown's household).
const STEPS: Array[String] = [
	"household", "crews", "expedition", "land", "voyage", "sea",
]
const STEP_HOUSEHOLD: String = "household"
const STEP_CREWS: String = "crews"
## Said in place of a household line when the crown runs no planner at all: a
## tick that files nothing still answers, so the seat never reads as broken.
const NO_PLAN_LINE: String = "The crown runs no household plan this turn."
## The log keeps the last few turns; the panel prints the tail.
const LOG_CAP: int = 40
const NO_ID: int = MapModel.NO_ID
## The seat's own phrasing for the order kinds the rival trace merges. The
## published `AiTurnLog` labels name a court's habit ("marches", "regiments
## raised"); the crown's log reads as despatches, so the verb comes first.
const SEAT_LABELS: Dictionary = {
	AiMilitaryPlanner.KIND_MARCH: "Marches",
	AiMilitaryPlanner.KIND_SPLIT: "Detaches a column",
	MapPlayArmyMusterAi.KIND_REINFORCE: "Raises a regiment",
	MapPlayArmyMusterAi.KIND_HOSPITAL: "Pitches a field hospital",
	MapPlayArmyMusterAi.KIND_RECALL: "Re-forms the Home Army",
	AiNavalPlanner.KIND_SORTIE: "Sorties",
	AiNavalPlanner.KIND_PURSUE: "Pursues",
	AiNavalPlanner.KIND_HOME: "Sails home",
	AiNavalPlanner.KIND_RAID: "Raids the coast",
	AiNavalPlanner.KIND_CONVOY: "Sails a convoy",
	AiInvasionPlanner.KIND_DOCK: "Docks the expedition",
	AiInvasionPlanner.KIND_EMBARK: "Boards an army",
	AiInvasionPlanner.KIND_SAIL: "Sails with the expedition",
	AiInvasionPlanner.KIND_CROSS: "Crosses the Passage",
	AiInvasionPlanner.KIND_BEACHHEAD: "Holds a beachhead",
	AiInvasionPlanner.KIND_LAND: "Lands an army",
}


## True while the AI holds the crown's seat. The staged turn in flight does not
## end it: only the turn boundary does (see `settle_turn_end`).
static func active(play: PlaySession) -> bool:
	return play != null and play.auto_active and not play.campaign_over()


## True when the driver may spend a tick: the seat is AI-held and not paused.
static func running(play: PlaySession) -> bool:
	return active(play) and play.auto_speed > 0


static func seconds(play: PlaySession) -> float:
	if play == null:
		return 0.0
	return SPEED_SECONDS[clampi(play.auto_speed, 0, SPEED_SECONDS.size() - 1)]


static func speed_label(play: PlaySession) -> String:
	if play == null:
		return SPEED_LABELS[1]
	return SPEED_LABELS[clampi(play.auto_speed, 0, SPEED_LABELS.size() - 1)]


## PAUSE -> 1x -> 2x -> 3x -> PAUSE: the speed seal's one press.
static func cycle_speed(play: PlaySession) -> int:
	if play == null:
		return 0
	play.auto_speed = (play.auto_speed + 1) % SPEED_SECONDS.size()
	return play.auto_speed


## Asks for Auto at this turn's close: the AI seats itself for the next turn.
static func arm(play: PlaySession) -> void:
	if play == null or play.auto_armed:
		return
	play.auto_armed = true
	note(play, "Auto — the AI takes the crown's seat after this turn.")


## Releases the seat at this turn's close: the court answers the next turn.
static func disarm(play: PlaySession) -> void:
	if play == null or not play.auto_armed:
		return
	play.auto_armed = false
	note(play, "Auto — the court returns to your hand when this turn ends.")


## One line in the Auto log (oldest dropped past the cap).
static func note(play: PlaySession, line: String) -> void:
	if play == null or line.is_empty():
		return
	play.auto_log.append(line)
	while play.auto_log.size() > LOG_CAP:
		play.auto_log.remove_at(0)


## The crown's own orders are ignored while Auto holds the seat; the chart, the
## dossiers and the ledgers stay open for inspection (wiki: auto-mode
## § Read-only while it runs).
static func blocks_orders(play: PlaySession) -> bool:
	return play != null and play.auto_active


## The seat's passes for the turn about to resolve, in phase order.
static func begin_turn(play: PlaySession) -> void:
	play.auto_steps.assign(STEPS)
	note(play, "Turn %d — the AI holds the crown's seat." % play.turn)


## One paced step: close the next seat pass, or finish the turn once drained.
## Called by the driver (AutoBar) at the chosen speed; tests call it directly.
static func tick(play: PlaySession) -> void:
	if play == null or not active(play):
		return
	if play.auto_book == null:
		# No turn in flight: Auto presses the turn itself.
		MapPlayTurn.auto_turn(play)
		return
	if not play.auto_steps.is_empty():
		var step: String = String(play.auto_steps[0])
		play.auto_steps.remove_at(0)
		run_step(play, step)
		if not play.auto_steps.is_empty():
			return
	MapPlayTurnFinish.finish(play)
	finish_turn(play)


## Runs one of the crown's own passes as the rival passes would, and logs what
## the rules actually resolved (REQ-P2-03: one planner surface for every court).
static func run_step(play: PlaySession, step: String) -> void:
	if step == STEP_HOUSEHOLD:
		household(play)
		return
	if step == STEP_CREWS:
		# Civilians work for every court in the pass, so the crown's crews run
		# where the rival courts' crews run: first, before anything marches.
		MapPlayTurnFinish.resolve_work(play)
		note(play, "Crews work the crown's orders.")
		return
	ensure_seat_ledger(play)
	var trace: Array = []
	match step:
		"expedition":
			trace.assign(_seat_pass(play, MapPlayInvasionAi.run))
		"land":
			trace.assign(_seat_pass(play, MapPlayArmyAi.run))
		"voyage":
			trace.assign(_seat_pass(play, MapPlayColonisationAi.run))
		"sea":
			trace.assign(_seat_pass(play, MapPlayFleetAi.run))
	_describe(play, trace)


## Runs a planner pass with the crown's seat staged — `ai_stage_faction` is the
## only court the pass may plan, so no rival is charged twice (MapPlayCourt).
static func _seat_pass(play: PlaySession, pass_fn: Callable) -> Array:
	play.ai_stage_faction = play.player_faction
	var trace: Variant = pass_fn.call(play)
	play.ai_stage_faction = NO_ID
	if trace is Array:
		return trace
	return []


## The crown's household, planned by the pass a rival court runs and booked as
## the player's own presses — the production runs, the workers the Build/work
## phase buys, the crews' work orders, the college's study and the market's
## trade. Opened through `draft`, not `open`, so the seat never seeds a rival's
## opening crew for the crown it does not hire. The crown's ledger is not closed
## here: its own `resolve_turn` carries the orders out where every human turn's
## are, so the seat neither pays twice nor re-times a rule (wiki: auto-mode
## § The crown's household; REQ-P2-03).
static func household(play: PlaySession) -> void:
	if play == null or play.economy == null or play.economy.market == null:
		return
	if not AiControl.plans(play, play.player_faction):
		note(play, NO_PLAN_LINE)
		return
	ensure_seat_ledger(play)
	var court: MapPlayEconomyCourt = MapPlayEconomyCourt.draft(
		play, play.player_faction, play.economy.market
	)
	court.plan_turn()
	_describe_household(play, court.book_orders())


## The household's booked row as despatch lines, one per kind it filed: the
## studies it opened, the runs it set, the hands it bought, the works it gave the
## crews and the trade it staged. A tick that files nothing says so, because a
## silent pass reads as a broken one (wiki: auto-mode § Pacing).
static func _describe_household(play: PlaySession, row: Dictionary) -> void:
	var lines: Array[String] = []
	for raw: Variant in (row.get("research", {}) as Dictionary).get("assignments", []):
		var tech: String = String((raw as Dictionary).get("tech", ""))
		if not tech.is_empty():
			lines.append("Studies %s" % TechCatalog.display_name(tech))
	var runs: int = 0
	for raw: Variant in (row.get("production", {}) as Dictionary).get("assignments", []):
		runs += int((raw as Dictionary).get("units", 0))
	if runs > 0:
		lines.append("Sets %d production run%s" % [runs, "" if runs == 1 else "s"])
	var tiers: Dictionary = {}
	for raw: Variant in row.get("recruits", []):
		var tier: int = int((raw as Dictionary).get("tier", -1))
		if tier >= 0:
			tiers[tier] = int(tiers.get(tier, 0)) + 1
	for tier: Variant in tiers.keys():
		var heads: int = int(tiers[tier])
		lines.append("Recruits %d %s" % [heads, WorkerPool.tier_name(int(tier))])
	var civilians: Dictionary = row.get("civilians", {}) as Dictionary
	var orders: int = (civilians.get("orders", []) as Array).size()
	if orders > 0:
		lines.append("Sets %d work order%s" % [orders, "" if orders == 1 else "s"])
	for raw: Variant in civilians.get("training", []):
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
	if bids > 0:
		lines.append("Bids at the mart — %d good%s" % [bids, "" if bids == 1 else "s"])
	if offers > 0:
		lines.append("Offers at the mart — %d good%s" % [offers, "" if offers == 1 else "s"])
	if lines.is_empty():
		note(play, "The household files no order this turn.")
		return
	for line: String in lines:
		note(play, line)


## The planners read one ledger per court; for the crown that is its own real
## ledger, so the seat spends the crown's purse rather than a shadow copy
## (wiki: ai-architecture § Provisioning; REQ-P2-03). A save taken during Auto
## carries a duplicate of it under `ai`, which a load never reads back.
static func ensure_seat_ledger(play: PlaySession) -> void:
	if play.economy == null or play.economy.economy == null:
		return
	play.ensure_ai().economies[play.player_faction] = play.economy.economy


## Turns the pass's trace into log lines: one per resolved order, grouped by
## kind and place so a court that marches three armies says so in one line.
static func _describe(play: PlaySession, trace: Array) -> void:
	var order: Array[String] = []
	var counts: Dictionary = {}
	for raw: Variant in trace:
		if not (raw is Dictionary):
			continue
		var record: Dictionary = raw
		if int(record.get("faction", NO_ID)) != play.player_faction:
			continue
		var line: String = _line(record)
		if line.is_empty():
			continue
		if counts.has(line):
			counts[line] = int(counts[line]) + 1
			continue
		counts[line] = 1
		order.append(line)
	for line: String in order:
		var count: int = int(counts[line])
		note(play, line if count == 1 else "%s (%d)" % [line, count])


## One trace record as a despatch line. The place is the province an army stands
## in or the sea zone a squadron entered.
static func _line(record: Dictionary) -> String:
	var kind: String = String(record.get("kind", ""))
	var label: String = String(
		SEAT_LABELS.get(kind, AiTurnLog.ACTION_LABELS.get(kind, kind))
	)
	var place: String = String(record.get("province_name", record.get("zone_name", "")))
	if label.is_empty():
		return ""
	if place.is_empty():
		return label
	return "%s — %s" % [label, place]


## Auto never stalls the court: a waiting decision is answered in the crown's
## interest — an alliance is honoured, a war it did not choose and a rival's
## offer are declined — and the answer is logged (wiki: auto-mode
## § No interruptions).
static func answer_pending(play: PlaySession) -> bool:
	if play == null or play.diplomacy == null:
		return false
	var human: int = play.player_faction
	match ConsentLadder.pending_kind(play.diplomacy, human):
		ConsentLadder.CALL:
			CallToArms.resolve_human(play.diplomacy, true)
			note(play, "Auto answers the call to arms: the alliance is honoured.")
		ConsentLadder.INTERVENTION:
			Intervention.resolve_human(play.diplomacy, Intervention.KIND_NOTHING)
			note(play, "Auto stays out of a war it did not choose.")
		ConsentLadder.OFFER:
			DiplomacyProposals.resolve_human(play.diplomacy, play.world, false)
			note(play, "Auto declines a rival's proposal.")
		_:
			return false
	return true


## The turn boundary, for both seats: an armed court takes the seat at the close
## of the turn the player just played, and a discharged one gives it back
## (wiki: auto-mode § Arming and disarming).
static func settle_turn_end(play: PlaySession) -> void:
	if play == null:
		return
	if play.auto_armed and not play.auto_active:
		play.auto_active = true
		note(play, "The AI takes the crown's seat.")
	elif play.auto_active and not play.auto_armed:
		play.auto_active = false
		note(play, "The court returns to your hand.")


## The paced turn is closed: the book is spent and the queue emptied, so the
## next tick presses a fresh turn.
static func finish_turn(play: PlaySession) -> void:
	play.auto_book = null
	play.auto_steps.clear()
