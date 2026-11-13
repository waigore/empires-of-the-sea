class_name AiTurn
extends RefCounted
## Per-turn AI order pass (wiki: ai-architecture, phase-planner-dispatch).
##
## Builds one read-only config per AI Great Power, runs the diplomacy planner,
## applies the resulting order through the shared diplomacy rules, and returns a
## turn trace plus player-facing messages (wiki: turn-trace-interpretation).
## Human courts are never auto-committed for a consent decision: the AI declares
## war on them and answers commercial acts in its own voice, while treaties,
## trade pacts, peace and overtures queue for the court UI (DR-20261108-01,
## DR-20261109-06, DR-20261109-07, DR-20261110-15).

const KIND_DECLARE_WAR: String = AiDiplomacyPlanner.KIND_DECLARE_WAR
const KIND_OFFER_PEACE: String = AiDiplomacyPlanner.KIND_OFFER_PEACE


## `context` may carry "regiments", "ships" and "stockpiles" maps by faction, plus
## "strengths": the order of battle the published power score reads, so a court
## weighs relative power by FPN + FPM and not by a head count (wiki: diplomacy
## § Great Power power score). "readings" is per court, the order of battle that
## court has charted, so each rival scores its war desire against what it has seen
## (DR-20261112-09), and "charts": the session's `CourtCharts`, so every
## diplomacy read — the resource need behind a war and the land an envoy chain
## would open — stays on the court's own chart (DR-20261113-03).
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
	var shared: Dictionary = _context(world, context, player)
	_stamp_ledgers(shared, ai_state, player)
	for faction: int in FactionCatalog.great_power_ids():
		if faction == player:
			continue
		var config: AiConfig = AiConfig.build(faction, game_seed)
		var agenda: String = ai_state.agenda_for(config)
		# The court's war footing rides the trace; the planners read it through
		# AiPhasePlanner (DR-20261113-15).
		var phase: Dictionary = AiPhasePlanner.plan(config, state)
		var plan: Dictionary = AiDiplomacyPlanner.decide(
			config, state, ai_state, world, turn, _reading(shared, faction)
		)
		var action: Dictionary = plan["action"]
		var record: Dictionary = {
			"faction": faction,
			"leader": config.leader,
			"agenda": agenda,
			"profile": config.profile,
			"phase": phase,
			"action": action.duplicate(true),
			"candidates": plan["candidates"],
		}
		if not action.is_empty():
			var applied: Dictionary = _apply(
				state, world, ai_state, faction, action, turn, game_seed, shared
			)
			record["result"] = applied.get("result", {})
			var message: String = String(applied.get("message", ""))
			record["message"] = message
			if not message.is_empty():
				messages.append(message)
			for extra: String in applied.get("messages", []):
				if not extra.is_empty():
					messages.append(extra)
		trace.append(record)
	return {"trace": trace, "messages": messages}


## Shared read model for the planners: absolute power per faction plus the unit
## counts and player id they need to explain their scores. When the caller
## supplies per-court "readings", each court also gets its own view of the terms
## (see `_reading`), so no rival plans against an order of battle it has never
## charted (DR-20261112-09).
##
## `strengths` is the order of battle the published power score reads (FPN + FPM
## × chevrons × health, wiki: diplomacy § Great Power power score); `regiments`
## stays the head count the invasion-capacity rule reads. A caller that supplies
## no strengths keeps the legacy count of the old call sites.
static func _context(world: WorldMap, supplied: Dictionary, player: int) -> Dictionary:
	var regiments: Dictionary = supplied.get("regiments", {})
	var ships: Dictionary = supplied.get("ships", {})
	var strengths: Dictionary = supplied.get("strengths", {})
	var context: Dictionary = {
		"power": _powers(world, regiments, ships, strengths),
		"regiments": regiments,
		"ships": ships,
		"player": player,
	}
	if not strengths.is_empty():
		context["strengths"] = strengths
	var views: Dictionary = _views(world, supplied.get("readings", {}))
	if not views.is_empty():
		context["views"] = views
	if supplied.has("charts"):
		context["charts"] = supplied["charts"]
	if supplied.has("stockpiles"):
		context["stockpiles"] = supplied["stockpiles"]
	return context


## The read model one court decides with: its own charted docket when the caller
## supplied readings, else the shared published one.
static func _reading(shared: Dictionary, faction: int) -> Dictionary:
	var views: Variant = shared.get("views", null)
	if typeof(views) != TYPE_DICTIONARY:
		return shared
	var view: Variant = (views as Dictionary).get(faction, null)
	if typeof(view) != TYPE_DICTIONARY:
		return shared
	var reading: Dictionary = shared.duplicate()
	reading.merge(view, true)
	return reading


## Absolute power per faction from one order of battle, read the published way
## (wiki: diplomacy § Great Power power score). The strength term is the order of
## battle — rounded as the panel and the calendar round it — and a caller that
## supplies none falls back to the head count its context already carries.
static func _powers(
	world: WorldMap, regiments: Dictionary, ships: Dictionary, strengths: Dictionary = {}
) -> Dictionary:
	var power: Dictionary = {}
	var by_strength: bool = not strengths.is_empty()
	for raw: Dictionary in FactionCatalog.all():
		var faction: int = int(raw["id"])
		var troops: int = (
			int(roundf(float(strengths.get(faction, 0.0))))
			if by_strength
			else int(regiments.get(faction, 0))
		)
		power[faction] = AiPower.score(
			world, faction, troops, int(ships.get(faction, 0))
		)
	return power


## One view per court that supplied a reading. Empty when the caller supplied
## none, which keeps a headless trace on the published order of battle.
static func _views(world: WorldMap, readings: Variant) -> Dictionary:
	var views: Dictionary = {}
	if typeof(readings) != TYPE_DICTIONARY:
		return views
	var by_court: Dictionary = readings
	for raw: Variant in by_court.keys():
		var entry: Variant = by_court[raw]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var docket: Dictionary = entry
		var regiments: Dictionary = docket.get("regiments", {})
		var ships: Dictionary = docket.get("ships", {})
		var strengths: Dictionary = docket.get("strength", {})
		var view: Dictionary = {
			"power": _powers(world, regiments, ships, strengths),
			"regiments": regiments,
			"ships": ships,
		}
		if not strengths.is_empty():
			view["strengths"] = strengths
		views[int(raw)] = view
	return views


## Rival ledgers supply the treasury and tech a peaceful order must satisfy, so
## a court never offers a stage it cannot pay for (wiki: diplomacy
## § Diplomatic Order Types). The human court's fake ledger stays out of the
## read model, matching the stockpile map.
static func _stamp_ledgers(shared: Dictionary, ai_state: AiState, player: int) -> void:
	var treasury: Dictionary = {}
	var tech: Dictionary = {}
	if ai_state != null:
		for faction: int in FactionCatalog.great_power_ids():
			if faction == player:
				continue
			var economy: PlayerEconomy = ai_state.economy_for(faction)
			treasury[faction] = economy.treasury
			tech[faction] = economy.tech_unlocked
	shared["treasury"] = treasury
	shared["tech"] = tech


static func _apply(
	state: DiplomacyState,
	world: WorldMap,
	ai_state: AiState,
	faction: int,
	action: Dictionary,
	turn: int,
	game_seed: int,
	shared: Dictionary
) -> Dictionary:
	var target: int = int(action.get("target", -1))
	var kind: String = String(action.get("kind", ""))
	if kind == KIND_DECLARE_WAR:
		# The declarer's own Propaganda softens a protest against it, so the
		# rules read this rival's ledger rather than assuming none
		# (wiki: diplomacy § Intervention; DR-20261110-16).
		var tech: Dictionary = ai_state.economy_for(faction).tech_unlocked
		var war: Dictionary = DiplomacyRules.declare_war(
			state, faction, target, true, world, tech
		)
		if bool(war.get("ok", false)):
			ai_state.note_war(faction, target, turn)
		var news: Array = war.get("calls", [])
		news.append_array(war.get("interventions", []))
		return {
			"result": war,
			"message": String(war.get("message", "")),
			"messages": news,
		}
	if kind == KIND_OFFER_PEACE:
		# A peace offer to the human court is queued, never signed: the phase
		# suspends until the player answers (DR-20261109-07).
		if bool(action.get("propose", false)):
			var offer: Dictionary = DiplomacyProposals.queue(
				state, world, faction, DiplomacyProposals.KIND_PEACE
			)
			var message: String = ""
			if bool(offer.get("ok", false)):
				message = "%s proposes a white peace." % FactionCatalog.name_of(faction)
			return {"result": offer, "message": message}
		var peace: Dictionary = DiplomacyRules.make_peace(
			state, faction, target,
			_peace_answer(state, world, ai_state, faction, target, game_seed, shared)
		)
		if bool(peace.get("ok", false)) and ai_state != null:
			# Either answer starts the pair's peace-offer cooldown, so a court
			# does not ask again every turn (wiki: diplomacy § Planner
			# selection; DR-20261109-07).
			ai_state.note_peace(faction, target, turn)
		return {
			"result": peace,
			"message": String(peace.get("message", "")),
		}
	if bool(action.get("propose", false)):
		return _propose(state, world, faction, action)
	return _apply_order(state, world, ai_state, faction, action)


## The answering court's own word on a white peace between two rivals. A court
## that still wants the war it is fighting refuses the offer, so a declaration is
## not undone by the defender in the phase it was made (wiki: diplomacy § Planner
## selection; hidden-agendas — warmonger keeps the war alive; DR-20261111-27).
## Only Great Powers answer by stance; a Minor or Tribe keeps the wiki's "never
## refuses peace", and the rules' auto test answers it.
static func _peace_answer(
	state: DiplomacyState,
	world: WorldMap,
	ai_state: AiState,
	offerer: int,
	target: int,
	game_seed: int,
	shared: Dictionary
) -> String:
	if FactionCatalog.type_of(target) != FactionCatalog.Type.GREAT_POWER:
		return DiplomacyRules.DECISION_AUTO
	if ai_state == null:
		return DiplomacyRules.DECISION_AUTO
	var config: AiConfig = AiConfig.build(target, game_seed)
	var agenda: String = ai_state.agenda_for(config)
	if agenda != config.agenda:
		# A run keeps the agenda it rolled (or a fixture fixed); the answer must
		# read that court's own peace stance, not a fresh roll.
		config.agenda = agenda
		config.agenda_traits = AiAgenda.resolve(agenda)
	# A court fighting enough fronts takes the white peace instead of refusing it:
	# no court wins two wars at once (wiki: phase-planner-architecture § Playable
	# slice; DR-20261113-15).
	if AiPhasePlanner.takes_any_peace(AiPhasePlanner.phase_for(config, state)):
		return DiplomacyRules.DECISION_AUTO
	var desire: Dictionary = AiDiplomacyPlanner.war_desire(
		config, state, world, target, offerer, _reading(shared, target)
	)
	if not AiPeaceStance.refuses(config, int(desire["score"])):
		return DiplomacyRules.DECISION_AUTO
	return DiplomacyRules.DECISION_REFUSE


## Queues a treaty or trade-pact offer for the human court's answer. The court
## answers during the phase; no rule is applied yet.
static func _propose(
	state: DiplomacyState, world: WorldMap, faction: int, action: Dictionary
) -> Dictionary:
	var kind: String = String(action.get("kind", ""))
	var stage: String = String(action.get("stage", ""))
	if not DiplomacyProposals.knows(kind):
		return {"result": {"ok": false, "reason": "unknown proposal"}, "message": ""}
	var offer: Dictionary = DiplomacyProposals.queue(state, world, faction, kind, stage)
	var message: String = ""
	if bool(offer.get("ok", false)):
		message = "%s proposes %s." % [
			FactionCatalog.name_of(faction), DiplomacyProposals.describe(kind, stage)
		]
	return {"result": offer, "message": message}


## One-sided acts and offers a fellow AI court answers by rule run through the
## shared order catalogue the court panel calls, spending the rival's own ledger
## (wiki: diplomacy § Diplomatic Order Types; REQ-P2-03).
static func _apply_order(
	state: DiplomacyState, world: WorldMap, ai_state: AiState, faction: int,
	action: Dictionary
) -> Dictionary:
	var kind: String = String(action.get("kind", ""))
	var order: Dictionary = {
		"kind": kind,
		"from": faction,
		"target": int(action.get("target", -1)),
	}
	if kind == DiplomacyOrders.KIND_OVERTURE:
		order["stage"] = String(action.get("stage", ""))
	elif kind == DiplomacyOrders.KIND_AID or kind == DiplomacyOrders.KIND_SUBSIDY:
		order["amount"] = int(action.get("amount", 0))
	var economy: PlayerEconomy = ai_state.economy_for(faction)
	var result: Dictionary = DiplomacyOrders.apply(
		state, world, economy, order, economy.tech_unlocked
	)
	return {"result": result, "message": _order_message(faction, action, result)}


## Rival voice for the ledger and the player's news feed: the catalogue's own
## wording speaks as "we", which reads wrong for a rival court.
static func _order_message(
	faction: int, action: Dictionary, result: Dictionary
) -> String:
	if not bool(result.get("ok", false)):
		return ""
	if not bool(result.get("accepted", true)):
		return String(result.get("message", ""))
	var who: String = FactionCatalog.name_of(faction)
	var them: String = FactionCatalog.name_of(int(action.get("target", -1)))
	match String(action.get("kind", "")):
		DiplomacyOrders.KIND_FTP:
			return "%s signs a favoured trading pact with %s." % [who, them]
		DiplomacyOrders.KIND_BOYCOTT:
			return "%s closes its colonies to %s." % [who, them]
		DiplomacyOrders.KIND_REVOKE_BOYCOTT:
			return "%s reopens its colonies to %s." % [who, them]
		DiplomacyOrders.KIND_BREAK:
			return "%s breaks its alliance with %s." % [who, them]
		DiplomacyOrders.KIND_SUBSIDY:
			return "%s sets a %d%% subsidy for %s." % [
				who, int(action.get("amount", 0)), them
			]
		DiplomacyOrders.KIND_CANCEL_SUBSIDY:
			return "%s ends its subsidy to %s." % [who, them]
		DiplomacyOrders.KIND_ALLIANCE:
			return "%s seals a formal alliance with %s." % [who, them]
	return String(result.get("message", ""))
