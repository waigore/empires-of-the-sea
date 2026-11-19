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
	var candidates: Array[Dictionary] = []
	var best_war: Dictionary = {}
	var best_peace: Dictionary = {}
	var best_offer: Dictionary = {}
	var player: int = int(context.get("player", -1))
	# The court's footing, read once for the whole pass — a caller that already
	# read it this turn posts it in the context: an overstretched court opens no
	# third front (DR-20261113-15, DR-20261114-11).
	var posture: String = String(context.get("posture", ""))
	if posture.is_empty():
		posture = AiPhasePlanner.phase_for(config, state)
	# An agenda moves the bar a war must fall below before the court puts peace
	# to its enemy (wiki: hidden-agendas — peacemaker early peace, warmonger
	# keeps the war alive; DR-20261111-27).
	var bar: int = AiPeaceStance.peace_bar(config)
	for record: DiplomacyRelation in state.relations_of(config.faction):
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
			# A court that cannot pay for the army its wars need buys out of its
			# crown wars (issue #975): the press may hold the continuing desire
			# above the bar, but a war the court cannot re-arm for is a peace it
			# puts to that crown itself while it saves for the army that can.
			# Minor and Tribe wars stay open — colonial business, the frontier
			# the court re-splits from once the purse recovers.
			if score >= bar and not AiDiplomacyGates.buys_out(config, ai_state, target, context, posture):
				entry["blocked"] = "war still worth waging"
			elif target == player:
				# The human keeps consent: a rival queues the offer and waits
				# (wiki: diplomacy § Planner selection; DR-20261109-07).
				entry["blocked"] = AiDiplomacyGates.peace_block(
					config, state, ai_state, turn, target
				)
				if String(entry["blocked"]).is_empty():
					entry["propose"] = true
					if best_peace.is_empty() or int(entry["desire"]) < int(best_peace["desire"]):
						best_peace = entry
			else:
				# A fellow court signs at once. The 4-turn war cooldown gates a
				# new Declare War on the pair, never the peace leg (wiki:
				# diplomacy § Cooldowns; DR-20261108-01), but the pair's
				# peace-offer cooldown still keeps a refused offer from being
				# repeated every turn (wiki: diplomacy § Planner selection).
				entry["blocked"] = AiDiplomacyGates.peace_cooldown(
					config, ai_state, turn, target
				)
				if String(entry["blocked"]).is_empty() and (
					best_peace.is_empty() or int(entry["desire"]) < int(best_peace["desire"])
				):
					best_peace = entry
		else:
			entry["blocked"] = AiDiplomacyGates.war_block(
				config, state, ai_state, turn, target, record, score, world, context, posture
			)
			if (
				String(entry["blocked"]).is_empty()
				and (best_war.is_empty() or int(entry["desire"]) > int(best_war["desire"]))
			):
				best_war = entry
			# Every peaceful order the court menu offers is a candidate, whether
			# the target is a rival court or the human one (DR-20261110-15).
			var offer: Dictionary = AiDiplomacyOffers.best(
				config, state, ai_state, world, turn, target, score, context
			)
			entry["offer"] = offer.duplicate()
			if bool(offer.get("ok", false)) and (
				best_offer.is_empty()
				or int(offer["utility"]) > int(best_offer["utility"])
			):
				best_offer = offer
		candidates.append(entry)
	var action: Dictionary = {}
	# The deed partner's chain outranks a Minor war. A court spends one order a
	# turn, and the warmth that prices a deed is the warmth that bars the
	# declaration, so a court opening the chain it means to buy on takes that
	# step instead of opening one more front — a Great Power war still outranks
	# it, and the chain's own embassy ends the preference (issue #841; wiki:
	# civilian-units § Merchant, diplomacy § GP AI policy for war vs. relations).
	if not best_war.is_empty() and _opens_deed_chain(
		config, state, candidates, best_war, context
	):
		best_war = {}
	# The pact the court means to march on breaks first (issue #995): a court
	# short of the bar whose host stands spends its one order on the pact
	# break that opens the front its conquest needs — the war ban lifts the
	# next turn, and the host the bank built marches on the big holder behind
	# it. A petty war cannot pre-empt the break, and neither can a quieter
	# offer: a court that has banked an army it can only spend on a Minor is
	# the stall this read ends. A Great Power war still leads — it needs no
	# break — and the banking court's own gate keeps the break off the table
	# until the host stands (`AiDiplomacyOffers._break_nap`). The income row's
	# gap carries the scoping: a frozen baseline breaks no pact for a
	# conquest (issue #995's subject-scoped surface).
	if AiDiplomacyTreaties.pact_break_leads(best_offer, best_war, context):
		best_war = {}
	if not best_war.is_empty():
		var provinces: int = DiplomacyRules.provinces_owned(world, int(best_war["target"]))
		action = {
			"kind": KIND_DECLARE_WAR,
			"target": int(best_war["target"]),
			"desire": int(best_war["desire"]),
			"desired_territory": AiDiplomacyGates.desired_territory(
				int(best_war["desire"]), provinces
			),
		}
	elif not best_peace.is_empty():
		action = {
			"kind": KIND_OFFER_PEACE,
			"target": int(best_peace["target"]),
			"desire": int(best_peace["desire"]),
		}
		if bool(best_peace.get("propose", false)):
			action["propose"] = true
	elif not best_offer.is_empty():
		action = best_offer.duplicate(true)
		# A proposal asks for the human court's answer; a rival court answers
		# during the same phase, and a one-sided act needs no answer at all
		# (wiki: diplomacy § GP AI policy).
		action["propose"] = (
			int(best_offer["target"]) == player
			and DiplomacyProposals.knows(String(best_offer["kind"]))
		)
	return {"action": action, "candidates": candidates}


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

