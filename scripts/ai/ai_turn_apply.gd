class_name AiTurnApply
extends RefCounted
## Applies one rival court's chosen diplomatic order through the shared rules the
## court panel calls, and speaks the result in that rival's own voice (wiki:
## diplomacy § Diplomatic Order Types; REQ-P2-03). Split out of `AiTurn` so the
## turn pass only dispatches: the planner decides in rules terms, this module
## turns the decision into state plus the lines the crown hears.
##
## Human courts are never auto-committed for a consent decision: the AI declares
## war on them and answers commercial acts in its own voice, while treaties,
## trade pacts, peace and overtures queue for the court UI (DR-20261108-01,
## DR-20261109-06, DR-20261109-07, DR-20261110-15).

const KIND_DECLARE_WAR: String = AiDiplomacyPlanner.KIND_DECLARE_WAR
const KIND_OFFER_PEACE: String = AiDiplomacyPlanner.KIND_OFFER_PEACE


## The chosen action, resolved: `{"result": <rules result>, "message": <one line>,
## "messages": <extra court news>}`. `shared` is the read model the answering
## court needs (`AiTurnRead.context`) when a white peace is put to it.
static func apply(
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
		return _declare(state, world, ai_state, faction, target, turn)
	if kind == KIND_OFFER_PEACE:
		return _peace(state, world, ai_state, faction, action, turn, game_seed, shared)
	if bool(action.get("propose", false)):
		return propose(state, world, ai_state, faction, action)
	return apply_order(
		state, world, ai_state, faction, action,
		(shared.get("power", {}) as Dictionary)
	)


## A declaration of war: the declarer's own Propaganda softens a protest against
## it, so the rules read this rival's ledger rather than assuming none
## (wiki: diplomacy § Intervention; DR-20261110-16).
static func _declare(
	state: DiplomacyState, world: WorldMap, ai_state: AiState,
	faction: int, target: int, turn: int
) -> Dictionary:
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


## A white peace: queued for the human court, answered by the rival court's own
## stance when both sides are AI (DR-20261109-07).
static func _peace(
	state: DiplomacyState, world: WorldMap, ai_state: AiState, faction: int,
	action: Dictionary, turn: int, game_seed: int, shared: Dictionary
) -> Dictionary:
	var target: int = int(action.get("target", -1))
	# A peace offer to the human court is queued, never signed: the phase
	# suspends until the player answers (DR-20261109-07).
	if bool(action.get("propose", false)):
		return _queue_peace(state, world, ai_state, faction, target, turn)
	var peace: Dictionary = DiplomacyRules.make_peace(
		state, faction, target,
		peace_answer(state, world, ai_state, faction, target, turn, game_seed, shared)
	)
	if bool(peace.get("ok", false)) and ai_state != null:
		# Either answer starts the pair's peace-offer cooldown, so a court
		# does not ask again every turn; a refusal also widens the next wait
		# (wiki: diplomacy § Planner selection; DR-20261109-07,
		# DR-20261115-01).
		ai_state.note_peace(faction, target, turn, bool(peace.get("accepted", false)))
		if bool(peace.get("accepted", false)):
			ai_state.note_truce(faction, target, turn)  # issue #475
	return {
		"result": peace,
		"message": String(peace.get("message", "")),
	}


static func _queue_peace(
	state: DiplomacyState, world: WorldMap, ai_state: AiState,
	faction: int, target: int, turn: int
) -> Dictionary:
	var offer: Dictionary = DiplomacyProposals.queue(
		state, world, faction, DiplomacyProposals.KIND_PEACE
	)
	var message: String = ""
	if bool(offer.get("ok", false)):
		message = "%s proposes a white peace." % FactionCatalog.name_of(faction)
		ai_state.note_truce(faction, target, turn)  # issue #475: done fighting
	return {"result": offer, "message": message}


## The answering court's own word on a white peace between two rivals. A court
## that still wants the war it is fighting refuses the offer, so a declaration is
## not undone by the defender in the phase it was made (wiki: diplomacy § Planner
## selection; hidden-agendas — warmonger keeps the war alive; DR-20261111-27).
## Only Great Powers answer by stance; a Minor or Tribe keeps the wiki's "never
## refuses peace", and the rules' auto test answers it.
static func peace_answer(
	state: DiplomacyState,
	world: WorldMap,
	ai_state: AiState,
	offerer: int,
	target: int,
	turn: int,
	game_seed: int,
	shared: Dictionary
) -> String:
	if FactionCatalog.type_of(target) != FactionCatalog.Type.GREAT_POWER:
		return DiplomacyRules.DECISION_AUTO
	if ai_state == null:
		return DiplomacyRules.DECISION_AUTO
	var config: AiConfig = AiProfile.for_court(
		target, game_seed, shared.get("profiles", {})
	)
	var agenda: String = ai_state.agenda_for(config)
	if agenda != config.agenda:
		# A run keeps the agenda it rolled (or a fixture fixed); the answer must
		# read that court's own peace stance, not a fresh roll.
		config.agenda = agenda
		config.agenda_traits = AiAgenda.resolve(agenda)
	# A court fighting enough fronts takes the white peace instead of refusing it:
	# no court wins two wars at once (wiki: phase-planner-architecture § Playable
	# slice; DR-20261113-15). The one war it keeps is the front its field army can
	# march on (issues #1082, #995): the war on a crown whose land touches its own,
	# where a province is stormed next door every turn, is not a front it is
	# overstretched by, so that offer is answered by its stance instead of signed.
	# A court with no frontier stamp and no world to read keeps the published
	# answer.
	var phase: String = AiPhasePlanner.phase_for(config, state)
	if AiPhasePlanner.takes_peace(phase, AiBorderFronts.marches_on(world, target, offerer)) \
			and not AiFrontier.holds(target, offerer, shared):
		return DiplomacyRules.DECISION_AUTO
	var desire: Dictionary = AiDiplomacyDesire.war_desire(
		config, state, world, target, offerer, AiTurnRead.reading(shared, target)
	)
	# Weariness ends a war the court cannot win (wiki: diplomacy § War goals).
	var power: int = int((desire["factors"] as Dictionary).get("relative_power", 0))
	var stronger: bool = power >= AiPower.BONUS_STRONG
	var worn: int = AiWarMemory.penalty(config, ai_state, turn, target, offerer, true, stronger)
	if not AiPeaceStance.refuses(config, maxi(int(desire["score"]) - worn, 0)):
		return DiplomacyRules.DECISION_AUTO
	return DiplomacyRules.DECISION_REFUSE


## Queues a treaty or trade-pact offer for the human court's answer. The court
## answers during the phase; no rule is applied yet. The asking court prices its
## own offer from its own ledger, so a paid rung — the last one, Join Empire —
## is raised only when this rival's purse and studies clear the gate (wiki:
## diplomacy § Join Empire; REQ-P2-03).
static func propose(
	state: DiplomacyState, world: WorldMap, ai_state: AiState, faction: int,
	action: Dictionary
) -> Dictionary:
	var kind: String = String(action.get("kind", ""))
	var stage: String = String(action.get("stage", ""))
	if not DiplomacyProposals.knows(kind):
		return {"result": {"ok": false, "reason": "unknown proposal"}, "message": ""}
	# The asking court's own purse and studies price the offer (wiki: diplomacy
	# § Join Empire). A caller with no AI state — a fixture — keeps the free
	# stages alone, exactly as the court with no ledger does.
	var treasury: int = 0
	var tech: Dictionary = {}
	if ai_state != null:
		var economy: PlayerEconomy = ai_state.economy_for(faction)
		treasury = economy.treasury
		tech = economy.tech_unlocked
	var offer: Dictionary = DiplomacyProposals.queue(
		state, world, faction, kind, stage, treasury, tech
	)
	var message: String = ""
	if bool(offer.get("ok", false)):
		message = "%s proposes %s." % [
			FactionCatalog.name_of(faction), DiplomacyProposals.describe(kind, stage)
		]
	return {"result": offer, "message": message}


## One-sided acts and offers a fellow AI court answers by rule run through the
## shared order catalogue the court panel calls, spending the rival's own ledger
## (wiki: diplomacy § Diplomatic Order Types; REQ-P2-03). `power` is the
## published power map a Join Empire acceptance reads (issue #750).
static func apply_order(
	state: DiplomacyState, world: WorldMap, ai_state: AiState, faction: int,
	action: Dictionary, power: Dictionary = {}
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
		state, world, economy, order, economy.tech_unlocked, power
	)
	return {"result": result, "message": order_message(faction, action, result)}


## Rival voice for the ledger and the player's news feed: the catalogue's own
## wording speaks as "we", which reads wrong for a rival court.
static func order_message(
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
		DiplomacyOrders.KIND_BREAK_NAP:
			return "%s breaks its non-aggression pact with %s." % [who, them]
		DiplomacyOrders.KIND_SUBSIDY:
			return "%s sets a %d%% subsidy for %s." % [
				who, int(action.get("amount", 0)), them
			]
		DiplomacyOrders.KIND_CANCEL_SUBSIDY:
			return "%s ends its subsidy to %s." % [who, them]
		DiplomacyOrders.KIND_ALLIANCE:
			return "%s seals a formal alliance with %s." % [who, them]
	return String(result.get("message", ""))
