class_name AiTurn
extends RefCounted
## Per-turn AI order pass (wiki: ai-architecture, phase-planner-dispatch).
##
## Builds one read-only config per AI Great Power, runs the diplomacy planner,
## applies the resulting order through the shared diplomacy rules, and returns a
## turn trace plus player-facing messages (wiki: turn-trace-interpretation).
## Human courts are never auto-committed: the AI declares war on them, while
## peace and treaty offers queue for the court UI (DR-20261108-01,
## DR-20261109-06, DR-20261109-07).

const KIND_DECLARE_WAR: String = AiDiplomacyPlanner.KIND_DECLARE_WAR
const KIND_OFFER_PEACE: String = AiDiplomacyPlanner.KIND_OFFER_PEACE


## `context` may carry "regiments", "ships" and "stockpiles" maps by faction.
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
	for faction: int in FactionCatalog.great_power_ids():
		if faction == player:
			continue
		var config: AiConfig = AiConfig.build(faction, game_seed)
		var agenda: String = ai_state.agenda_for(config)
		var plan: Dictionary = AiDiplomacyPlanner.decide(
			config, state, ai_state, world, turn, shared
		)
		var action: Dictionary = plan["action"]
		var record: Dictionary = {
			"faction": faction,
			"leader": config.leader,
			"agenda": agenda,
			"profile": config.profile,
			"action": action.duplicate(true),
			"candidates": plan["candidates"],
		}
		if not action.is_empty():
			var applied: Dictionary = _apply(state, world, ai_state, faction, action, turn)
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
## counts and player id they need to explain their scores.
static func _context(world: WorldMap, supplied: Dictionary, player: int) -> Dictionary:
	var regiments: Dictionary = supplied.get("regiments", {})
	var ships: Dictionary = supplied.get("ships", {})
	var power: Dictionary = {}
	for raw: Dictionary in FactionCatalog.all():
		var faction: int = int(raw["id"])
		power[faction] = AiPower.score(
			world, faction, int(regiments.get(faction, 0)), int(ships.get(faction, 0))
		)
	var context: Dictionary = {
		"power": power,
		"regiments": regiments,
		"ships": ships,
		"player": player,
	}
	if supplied.has("stockpiles"):
		context["stockpiles"] = supplied["stockpiles"]
	return context


static func _apply(
	state: DiplomacyState,
	world: WorldMap,
	ai_state: AiState,
	faction: int,
	action: Dictionary,
	turn: int
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
		var peace: Dictionary = DiplomacyRules.make_peace(state, faction, target)
		return {
			"result": peace,
			"message": String(peace.get("message", "")),
		}
	if kind == AiDiplomacyPlanner.KIND_ALLIANCE or kind == AiDiplomacyPlanner.KIND_OVERTURE:
		var stage: String = String(action.get("stage", ""))
		var offer: Dictionary = DiplomacyProposals.queue(
			state, world, faction, kind, stage
		)
		var message: String = ""
		if bool(offer.get("ok", false)):
			# The court answers this during the phase; no rule is applied yet.
			message = "%s proposes %s." % [
				FactionCatalog.name_of(faction),
				DiplomacyProposals.describe(kind, stage),
			]
		return {"result": offer, "message": message}
	return {"result": {"ok": false, "reason": "unknown order"}, "message": ""}
