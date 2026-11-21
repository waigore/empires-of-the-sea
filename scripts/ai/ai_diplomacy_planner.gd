class_name AiDiplomacyPlanner
extends RefCounted
## Full-AI diplomacy orders (wiki: diplomacy § GP AI policy for war vs. relations,
## diplomacy-planner). Reads the war-desire tally AiDiplomacyDesire scores for
## every candidate court, turns the complement into improve-relations desire,
## and emits at most one legal order per Great Power per turn — war, peace, or
## any peaceful order the court menu offers through AiDiplomacyOffers. A court
## that cannot re-arm for its crown wars buys out of them (issue #975). The war
## goal, the peace and war gates and the buy-out read live in AiDiplomacyGates,
## so the offers' pact break asks the same copy. Pure rules: state in, orders out
## (REQ-P2-03, REQ-P3-03).
##
## `decide` is the pass; each step keeps its own home: `_candidate` scores one
## relation, `_weigh_peace` and `_weigh_war` read the row's own gates, the
## `_better_*` reads rank the rows, and `_action` assembles the one order.

const KIND_DECLARE_WAR: String = "declare_war"
const KIND_OFFER_PEACE: String = "offer_peace"


## One action for one court: the highest-desire legal war, else a white peace
## when continuing the war scores below the base desire — or when the court
## cannot re-arm for the war it is fighting (issue #975) — applied at once to a
## fellow AI court, queued for the human court's answer to the player.
static func decide(
	config: AiConfig,
	state: DiplomacyState,
	ai_state: AiState,
	world: WorldMap,
	turn: int,
	context: Dictionary
) -> Dictionary:
	var player: int = int(context.get("player", -1))
	var posture: String = _posture(config, state, context)
	var bar: int = AiPeaceStance.peace_bar(config)
	var candidates: Array[Dictionary] = []
	var best_war: Dictionary = {}
	var best_peace: Dictionary = {}
	var best_offer: Dictionary = {}
	for record: DiplomacyRelation in state.relations_of(config.faction):
		var entry: Dictionary = _candidate(
			config, state, ai_state, world, turn, record, context, bar, player, posture
		)
		candidates.append(entry)
		if bool(entry["at_war"]):
			best_peace = _better_peace(best_peace, entry)
		else:
			best_war = _better_war(best_war, entry)
			var offer: Dictionary = entry.get("offer", {})
			best_offer = _better_offer(best_offer, offer)
	best_war = _war_leads(config, state, candidates, best_war, best_offer, context)
	return {
		"action": _action(best_war, best_peace, best_offer, world, player),
		"candidates": candidates,
	}


## The court's footing, read once for the whole pass — a caller that already
## read it this turn posts it in the context: an overstretched court opens no
## third front (DR-20261113-15, DR-20261114-11).
static func _posture(
	config: AiConfig, state: DiplomacyState, context: Dictionary
) -> String:
	var posture: String = String(context.get("posture", ""))
	if posture.is_empty():
		posture = AiPhasePlanner.phase_for(config, state)
	return posture


## One relation's row: the war desire the court scores for that target, the
## memory and pointless-war penalties that shade it, and the row's own read of
## the peace or the war and offers on the table.
static func _candidate(
	config: AiConfig,
	state: DiplomacyState,
	ai_state: AiState,
	world: WorldMap,
	turn: int,
	record: DiplomacyRelation,
	context: Dictionary,
	bar: int,
	player: int,
	posture: String
) -> Dictionary:
	var target: int = record.other(config.faction)
	var desire: Dictionary = AiDiplomacyDesire.war_desire(
		config, state, world, config.faction, target, context
	)
	# War memory (issue #475): the penalty lowers desire, never legality.
	var memory: int = AiWarMemory.penalty(
		config, ai_state, turn, config.faction, target, record.at_war,
		AiWarMemory.outmatches(target, int(desire["factors"].get("relative_power", 0)))
	)
	var score: int = clampi(int(desire["score"]) - memory, 0, 100)
	var factors: Dictionary = desire["factors"]
	if memory > 0:
		factors["memory"] = -memory
	# The pointless-war read names itself in the trace: a war that has taken
	# no attack on the enemy for the window is yielding nothing (issue #999).
	if record.at_war:
		var idle: int = AiWarMemory.pointless(
			config, ai_state, turn, config.faction, target
		)
		if idle > 0:
			factors["pointless"] = -idle
	var entry: Dictionary = {
		"target": target,
		"desire": score,
		"at_war": record.at_war,
		"relation": record.score,
		"factors": factors,
		"blocked": "",
	}
	if record.at_war:
		_weigh_peace(
			config, state, ai_state, world, turn, target, entry, context, posture, bar, player
		)
	else:
		_weigh_war(
			config, state, ai_state, world, turn, target, record, entry, context, posture, score
		)
	return entry


## The peace read on a war the court already fights: the front its army can
## march on, the buy-out a court that cannot re-arm takes, and the consent the
## human court keeps.
static func _weigh_peace(
	config: AiConfig,
	state: DiplomacyState,
	ai_state: AiState,
	world: WorldMap,
	turn: int,
	target: int,
	entry: Dictionary,
	context: Dictionary,
	posture: String,
	bar: int,
	player: int
) -> void:
	# The front the army can march on (issue #995): the war on a crown
	# whose land this court borders is the one war its field army can
	# prosecute, so an overstretched court keeps it instead of taking
	# any peace it is offered or buying out of it. Stamped on the row
	# so the trace names the front the footing keeps.
	var marches: bool = AiBorderFronts.marches_on(world, config.faction, target)
	entry["border_front"] = marches
	# A court that cannot pay for the army its wars need buys out of its
	# crown wars (issue #975): the press may hold the continuing desire
	# above the bar, but a war the court cannot re-arm for is a peace it
	# puts to that crown itself while it saves for the army that can.
	# Minor and Tribe wars stay open — colonial business, the frontier
	# the court re-splits from once the purse recovers.
	if int(entry["desire"]) >= bar and not AiDiplomacyGates.buys_out(
		config, ai_state, target, context, posture, marches
	):
		entry["blocked"] = "war still worth waging"
	elif target == player:
		# The human keeps consent: a rival queues the offer and waits
		# (wiki: diplomacy § Planner selection; DR-20261109-07).
		entry["blocked"] = AiDiplomacyGates.peace_block(
			config, state, ai_state, turn, target
		)
		if String(entry["blocked"]).is_empty():
			entry["propose"] = true
	else:
		# A fellow court signs at once. The 4-turn war cooldown gates a
		# new Declare War on the pair, never the peace leg (wiki:
		# diplomacy § Cooldowns; DR-20261108-01), but the pair's
		# peace-offer cooldown still keeps a refused offer from being
		# repeated every turn (wiki: diplomacy § Planner selection).
		entry["blocked"] = AiDiplomacyGates.peace_cooldown(
			config, ai_state, turn, target
		)


## The war and offer read on a court the crown is not fighting: the war gate,
## and every peaceful order the court menu offers, whether the target is a
## rival court or the human one (DR-20261110-15).
static func _weigh_war(
	config: AiConfig,
	state: DiplomacyState,
	ai_state: AiState,
	world: WorldMap,
	turn: int,
	target: int,
	record: DiplomacyRelation,
	entry: Dictionary,
	context: Dictionary,
	posture: String,
	score: int
) -> void:
	entry["blocked"] = AiDiplomacyGates.war_block(
		config, state, ai_state, turn, target, record, score, world, context, posture
	)
	entry["offer"] = AiDiplomacyOffers.best(
		config, state, ai_state, world, turn, target, score, context
	).duplicate()


## The peace the court would put to this target, when the row's own gate let it
## through: the lowest continuing desire wins, so the war it most wants to end
## is the one it offers to end.
static func _better_peace(best: Dictionary, entry: Dictionary) -> Dictionary:
	if not String(entry.get("blocked", "")).is_empty():
		return best
	if best.is_empty() or int(entry["desire"]) < int(best["desire"]):
		return entry
	return best


## The war the court would declare on this target, when the row's own gate let
## it through: the highest desire wins.
static func _better_war(best: Dictionary, entry: Dictionary) -> Dictionary:
	if not String(entry.get("blocked", "")).is_empty():
		return best
	if best.is_empty() or int(entry["desire"]) > int(best["desire"]):
		return entry
	return best


## The peaceful order the court would send this target, when the offer is legal:
## the highest utility wins.
static func _better_offer(best: Dictionary, offer: Dictionary) -> Dictionary:
	if not bool(offer.get("ok", false)):
		return best
	if best.is_empty() or int(offer["utility"]) > int(best["utility"]):
		return offer
	return best


## The war the pass would declare, unless a quieter order leads: the deed
## partner's chain outranks a Minor war, and the pact break a conquest waits
## behind outranks a petty war.
static func _war_leads(
	config: AiConfig,
	state: DiplomacyState,
	candidates: Array[Dictionary],
	best_war: Dictionary,
	best_offer: Dictionary,
	context: Dictionary
) -> Dictionary:
	# The deed partner's chain outranks a Minor war. A court spends one order a
	# turn, and the warmth that prices a deed is the warmth that bars the
	# declaration, so a court opening the chain it means to buy on takes that
	# step instead of opening one more front — a Great Power war still outranks
	# it, and the chain's own embassy ends the preference (issue #841; wiki:
	# civilian-units § Merchant, diplomacy § GP AI policy for war vs. relations).
	if not best_war.is_empty() and _opens_deed_chain(
		config, state, candidates, best_war, context
	):
		return {}
	# The pact the court means to march on breaks first (issue #995): a court
	# short of the bar whose host stands spends its one order on the pact
	# break that opens the front its conquest needs — the war ban lifts the
	# next turn, and the host the bank built marches on the big holder behind
	# it. A petty war cannot pre-empt the break, and neither can a quieter
	# offer: a court that has banked an army it can only spend on a Minor is
	# the stall this read ends. A Great Power war still leads — it needs no
	# break — and the banking court's own gate keeps the break off the table
	# until the host stands (`AiDiplomacyPacts.break_nap`). The income row's
	# gap carries the scoping: a frozen baseline breaks no pact for a
	# conquest (issue #995's subject-scoped surface).
	if AiDiplomacyTreaties.pact_break_leads(best_offer, best_war, context):
		return {}
	return best_war


## The one order the pass emits: the war first, then the peace, then the
## peaceful offer. A proposal asks for the human court's answer; a rival court
## answers during the same phase, and a one-sided act needs no answer at all
## (wiki: diplomacy § GP AI policy).
static func _action(
	best_war: Dictionary,
	best_peace: Dictionary,
	best_offer: Dictionary,
	world: WorldMap,
	player: int
) -> Dictionary:
	if not best_war.is_empty():
		var provinces: int = DiplomacyRules.provinces_owned(world, int(best_war["target"]))
		return {
			"kind": KIND_DECLARE_WAR,
			"target": int(best_war["target"]),
			"desire": int(best_war["desire"]),
			"desired_territory": AiDiplomacyGates.desired_territory(
				int(best_war["desire"]), provinces
			),
		}
	if not best_peace.is_empty():
		var peace: Dictionary = {
			"kind": KIND_OFFER_PEACE,
			"target": int(best_peace["target"]),
			"desire": int(best_peace["desire"]),
		}
		if bool(best_peace.get("propose", false)):
			peace["propose"] = true
		return peace
	if not best_offer.is_empty():
		var offer: Dictionary = best_offer.duplicate(true)
		offer["propose"] = (
			int(best_offer["target"]) == player
			and DiplomacyProposals.knows(String(best_offer["kind"]))
		)
		return offer
	return {}


## True when the court owes its deed partner the next envoy step and the war on
## the table is only a Minor or Tribe: the one order this turn goes to the chain
## that prices the deed. False for a Great Power war (a front is not a deed), for
## a court with no named seller, for a seller whose embassy already stands, and
## for a chain with no legal overture left (issue #841).
static func _opens_deed_chain(
	config: AiConfig,
	state: DiplomacyState,
	candidates: Array[Dictionary],
	best_war: Dictionary,
	context: Dictionary
) -> bool:
	var seller: int = int(context.get("deed_seller", -1))
	if seller < 0:
		return false
	if FactionCatalog.type_of(int(best_war["target"])) == FactionCatalog.Type.GREAT_POWER:
		return false
	if DiplomacyRules.has_embassy(state, config.faction, seller):
		return false
	for entry: Dictionary in candidates:
		var ranking: Dictionary = entry.get("offer", {})
		if AiDiplomacyOffers.offers_kind(
			ranking.get("candidates", []), seller, AiDiplomacyOffers.KIND_OVERTURE
		):
			return true
	return false


## Every order kind the planner can emit: war and peace are scored here, the
## rest by AiDiplomacyOffers. Kept as one list so the court menu and the rival
## courts cannot drift apart (REQ-P2-03).
static func kinds() -> Array[String]:
	var all: Array[String] = [KIND_DECLARE_WAR, KIND_OFFER_PEACE]
	all.append_array(AiDiplomacyOffers.KINDS)
	return all
