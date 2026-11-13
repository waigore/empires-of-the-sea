class_name AiDiplomacyPlanner
extends RefCounted
## Full-AI diplomacy orders (wiki: diplomacy § GP AI policy for war vs. relations,
## diplomacy-planner). Reads the war-desire tally AiDiplomacyDesire scores for
## every candidate court, turns the complement into improve-relations desire,
## and emits at most one legal order per Great Power per turn — war, peace, or
## any peaceful order the court menu offers through AiDiplomacyOffers. Pure
## rules: state in, orders out (REQ-P2-03, REQ-P3-03).

## War-goal objective: one province per 25 desire (wiki: diplomacy § War goals).
const DESIRE_PER_PROVINCE: float = 25.0

const KIND_DECLARE_WAR: String = "declare_war"
const KIND_OFFER_PEACE: String = "offer_peace"


## One action for one court: the highest-desire legal war, else a white peace
## when continuing the war scores below the base desire — applied at once to a
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
		var entry: Dictionary = {
			"target": target,
			"desire": score,
			"at_war": record.at_war,
			"relation": record.score,
			"factors": factors,
			"blocked": "",
		}
		if record.at_war:
			if score >= bar:
				entry["blocked"] = "war still worth waging"
			elif target == player:
				# The human keeps consent: a rival queues the offer and waits
				# (wiki: diplomacy § Planner selection; DR-20261109-07).
				entry["blocked"] = _peace_block(config, state, ai_state, turn, target)
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
				entry["blocked"] = _peace_cooldown(config, ai_state, turn, target)
				if String(entry["blocked"]).is_empty() and (
					best_peace.is_empty() or int(entry["desire"]) < int(best_peace["desire"])
				):
					best_peace = entry
		else:
			entry["blocked"] = _war_block(
				config, state, ai_state, turn, target, record, score, world, context
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
	if not best_war.is_empty():
		var provinces: int = DiplomacyRules.provinces_owned(world, int(best_war["target"]))
		action = {
			"kind": KIND_DECLARE_WAR,
			"target": int(best_war["target"]),
			"desire": int(best_war["desire"]),
			"desired_territory": desired_territory(int(best_war["desire"]), provinces),
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


## Every order kind the planner can emit: war and peace are scored here, the
## rest by AiDiplomacyOffers. Kept as one list so the court menu and the rival
## courts cannot drift apart (REQ-P2-03).
static func kinds() -> Array[String]:
	var all: Array[String] = [KIND_DECLARE_WAR, KIND_OFFER_PEACE]
	all.append_array(AiDiplomacyOffers.KINDS)
	return all


## War-goal objective: clamp(round(warDesire / 25), 1, targetProvinceCount).
static func desired_territory(war_desire_score: int, province_count: int) -> int:
	var target: int = int(roundf(float(war_desire_score) / DESIRE_PER_PROVINCE))
	return clampi(target, 1, maxi(1, province_count))


## Why this court cannot put a white peace to the human court right now ("" when
## it may). A queued proposal waits for the answer, so a second one would only
## be refused by the court queue (DR-20261109-07).
static func _peace_block(
	config: AiConfig, state: DiplomacyState, ai_state: AiState, turn: int, target: int
) -> String:
	if DiplomacyProposals.has_pending(state, target):
		return "the court is already considering a proposal"
	var cooling: String = _peace_cooldown(config, ai_state, turn, target)
	if not cooling.is_empty():
		return cooling
	var check: Dictionary = DiplomacyRules.can_make_peace(state, config.faction, target)
	if not bool(check.get("ok", false)):
		return String(check.get("reason", "illegal"))
	return ""


## The pair's peace-offer cooldown: either answer starts it, so a court does not
## ask again every turn (wiki: diplomacy § Planner selection; DR-20261109-07).
static func _peace_cooldown(
	config: AiConfig, ai_state: AiState, turn: int, target: int
) -> String:
	var cooldown: int = config.parameter("diplomacy.peace_cooldown_turns")
	if ai_state.peace_on_cooldown(config.faction, target, turn, cooldown):
		return "peace cooldown"
	return ""


## Why this court will not declare war right now ("" when it may). A Tribe the
## court is drawing into its empire is not a war target: the declaration would
## clear the envoy chain, and its provinces never count toward victory
## (wiki: factions § Tribe; diplomacy § GP–Tribe Rules; DR-20261114-02).
static func _war_block(
	config: AiConfig,
	state: DiplomacyState,
	ai_state: AiState,
	turn: int,
	target: int,
	record: DiplomacyRelation,
	desire: int,
	world: WorldMap = null,
	context: Dictionary = {}
) -> String:
	var check: Dictionary = DiplomacyRules.can_declare_war(state, config.faction, target)
	if not bool(check.get("ok", false)):
		return String(check.get("reason", "illegal"))
	var cooldown: int = config.parameter("diplomacy.war_cooldown_turns")
	if ai_state.war_on_cooldown(config.faction, target, turn, cooldown):
		return "war cooldown"
	var treasury: int = int((context.get("treasury", {}) as Dictionary).get(config.faction, 0))
	var tech: Dictionary = (context.get("tech", {}) as Dictionary).get(config.faction, {})
	var colony: Dictionary = AiTribeColony.ambition(
		state, world, context.get("charts", null), config.faction, target,
		treasury, tech
	)
	if bool(colony.get("wanted", false)) or bool(colony.get("held", false)):
		return "an envoy chain has a claim on that court"
	if record.score > float(config.war_relation_ceiling()):
		return "relations too warm"
	if desire < config.parameter("diplomacy.war_declare_min_desire"):
		return "war desire too low"
	return ""
