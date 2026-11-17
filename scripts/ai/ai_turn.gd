class_name AiTurn
extends RefCounted
## Per-turn AI order pass (wiki: ai-architecture, phase-planner-dispatch).
##
## One pass per turn: build the shared read model (`AiTurnRead`), ask the
## diplomacy planner for each rival's one order, apply it through the shared
## rules (`AiTurnApply`), and return a turn trace plus player-facing messages
## (wiki: turn-trace-interpretation). This module only dispatches; the read model
## and the application keep their own homes (REQ-P3-01, REQ-P3-03).


## `context`: regiments/ships/stockpiles/strengths, per-court readings
## (DR-20261112-09), charts (DR-20261113-03), hull_chests/warships (#484, #580).
static func run(
	state: DiplomacyState,
	world: WorldMap,
	ai_state: AiState,
	turn: int,
	player: int,
	game_seed: int,
	context: Dictionary = {}
) -> Dictionary:
	var trace: Array[Dictionary] = []
	var messages: Array[String] = []
	var shared: Dictionary = AiTurnRead.context(world, context, player)
	AiTurnRead.stamp_ledgers(shared, ai_state, player)
	# Optional observer gate: when `planning` is present, only listed crowns
	# issue orders; others append a noop trace row (docs/ai-observer.md).
	var gated: bool = context.has("planning")
	var planning: Array = context.get("planning", [])
	for faction: int in FactionCatalog.great_power_ids():
		if faction == player:
			continue
		var config: AiConfig = AiConfig.build(faction, game_seed)
		var agenda: String = ai_state.agenda_for(config)
		if gated and not planning.has(faction):
			trace.append(_noop(faction, config, agenda))
			continue
		var record: Dictionary = _court_turn(
			state, world, ai_state, faction, turn, game_seed, config, agenda, shared
		)
		trace.append(record)
		for line: String in record.get("messages", []):
			messages.append(line)
	return {"trace": trace, "messages": messages}


## One court's order for the turn: its footing and money goal ride the trace, the
## planner names the action, and the apply pass turns it into state and news.
static func _court_turn(
	state: DiplomacyState,
	world: WorldMap,
	ai_state: AiState,
	faction: int,
	turn: int,
	game_seed: int,
	config: AiConfig,
	agenda: String,
	shared: Dictionary
) -> Dictionary:
	# The court's war footing rides the trace; the planners read it through
	# AiPhasePlanner (DR-20261113-15). Its money goal rides beside it: a court
	# short of the muster it is saving for opens no new war (DR-20261113-19).
	var phase: Dictionary = AiPhasePlanner.plan(config, state)
	var income: Dictionary = AiIncome.plan(
		config, AiTurnRead.ledger(ai_state, faction), AiIncome.at_war(state, faction),
		int((shared.get("regiments", {}) as Dictionary).get(faction, 0)),
		int((shared.get("hull_chests", {}) as Dictionary).get(faction, 0)),
		int((shared.get("warships", {}) as Dictionary).get(faction, -1))
	)
	# The one deed partner this court warms: the warmth that prices a deed is the
	# warmth that bars a declaration, so the reading is named once per turn and
	# the envoy nudge goes to that seller alone (issue #841). A court with no
	# Merchant Companies has no chain to open, so it pays for no scan.
	var read: Dictionary = AiTurnRead.reading(shared, faction, income)
	var tech: Dictionary = (shared.get("tech", {}) as Dictionary).get(faction, {})
	if CivilianCatalog.is_unlocked("merchant", tech):
		read["deed_seller"] = AiMerchantWork.deed_seller(
			world, faction, read.get("charts", null), state
		)
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		config, state, ai_state, world, turn, read
	)
	var action: Dictionary = plan["action"]
	var record: Dictionary = {
		"faction": faction,
		"leader": config.leader,
		"agenda": agenda,
		"profile": config.profile,
		"phase": phase,
		# The dispatch slots this footing holds shut, so a closed aim reads in
		# the trace instead of only in the planner that skipped it
		# (DR-20261116-11, REQ-P5-05).
		"holds": AiPhasePlanner.closed_slots(
			String(phase.get("phase", AiPhasePlanner.PHASE_UNKNOWN))
		),
		"income": income,
		# The one Minor this court warms for a deed, so the trace can explain
		# why a conquest reads "relations too warm" on that court alone
		# (issue #841).
		"deed_seller": int(read.get("deed_seller", -1)),
		"action": action.duplicate(true),
		"candidates": plan["candidates"],
	}
	if action.is_empty():
		return record
	var applied: Dictionary = AiTurnApply.apply(
		state, world, ai_state, faction, action, turn, game_seed, shared
	)
	record["result"] = applied.get("result", {})
	var message: String = String(applied.get("message", ""))
	record["message"] = message
	# The court's own player-facing lines, kept per record so a caller
	# can put each in the channel that should carry it: the map pass
	# toasts what changes the crown's turn and leaves World news to the
	# Gazette (wiki: the-gazette § Not the Gazette).
	var lines: Array[String] = []
	if not message.is_empty():
		lines.append(message)
	for extra: String in applied.get("messages", []):
		if not extra.is_empty():
			lines.append(extra)
	record["messages"] = lines
	return record


## The trace row a gated-out court leaves: it took no order this turn, so the
## panel still lists the crown and the headless exporter sees the same shape.
static func _noop(faction: int, config: AiConfig, agenda: String) -> Dictionary:
	return {
		"faction": faction,
		"leader": config.leader,
		"agenda": agenda,
		"profile": config.profile,
		"phase": {},
		"action": {},
		"candidates": [],
		"noop": true,
	}
