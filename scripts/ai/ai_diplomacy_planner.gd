class_name AiDiplomacyPlanner
extends RefCounted
## Full-AI diplomacy policy (wiki: diplomacy § GP AI policy for war vs. relations,
## diplomacy-planner). Scores one war-desire value per candidate court, turns the
## complement into improve-relations desire, and emits at most one legal order
## per Great Power per turn. Pure rules: state in, orders out (REQ-P2-03,
## REQ-P3-03).

## War-desire factors (wiki seed values).
const RELATION_WARM_PENALTY: int = -40
const RELATION_NEUTRAL_PENALTY: int = -20
const RELATION_HOSTILE_BONUS: int = 10
const RESOURCE_NEED_STEP: int = 5
const RESOURCE_NEED_CAP: int = 15
const INTERVENTION_STEP: int = -8
const INTERVENTION_CAP: int = -24
const INVASION_TOO_SMALL: int = -20
const INVASION_SUPERIOR: int = 10
const INVASION_NO_SHIPS: int = -25
const MULTI_WAR_PENALTY: int = -15
const DESIRE_PER_PROVINCE: float = 25.0

const KIND_DECLARE_WAR: String = "declare_war"
const KIND_OFFER_PEACE: String = "offer_peace"
const KIND_ALLIANCE: String = "alliance"
const KIND_OVERTURE: String = "overture"


## War desire 0..100 for one (attacker, target) pair plus the factors that made
## it, so a turn trace can explain the number (wiki: turn-trace-interpretation).
static func war_desire(
	config: AiConfig,
	state: DiplomacyState,
	world: WorldMap,
	attacker: int,
	target: int,
	context: Dictionary
) -> Dictionary:
	var record: DiplomacyRelation = state.relation(attacker, target)
	if record == null:
		return {"score": 0, "factors": {}}
	var powers: Dictionary = context.get("power", {})
	var band: Dictionary = AiPower.relative_band(
		int(powers.get(attacker, 0)), int(powers.get(target, 0))
	)
	var factors: Dictionary = {
		"base": config.parameter("diplomacy.war_desire_base"),
		"relative_power": int(band["bonus"]),
		"relation": _relation_pressure(record.score),
		"personality": config.war_bias(),
	}
	var score: int = 0
	for value: Variant in factors.values():
		score += int(value)
	if _is_weak_target(target):
		factors["resource_need"] = _resource_need(attacker, world, target, context)
		factors["intervention"] = _intervention_penalty(state, world, attacker, target)
		var invasion: Dictionary = _invasion_adjustment(
			state, world, attacker, target, context
		)
		factors["invasion"] = int(invasion["adjustment"])
		factors["wars"] = int(invasion["wars"])
		score += int(invasion["adjustment"]) + int(invasion["wars"])
		score += int(factors["resource_need"]) + int(factors["intervention"])
	return {"score": clampi(score, 0, 100), "factors": factors}


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
	var base: int = config.parameter("diplomacy.war_desire_base")
	for record: DiplomacyRelation in state.relations_of(config.faction):
		var target: int = record.other(config.faction)
		var desire: Dictionary = war_desire(
			config, state, world, config.faction, target, context
		)
		var entry: Dictionary = {
			"target": target,
			"desire": int(desire["score"]),
			"at_war": record.at_war,
			"relation": record.score,
			"factors": desire["factors"],
			"blocked": "",
		}
		if record.at_war:
			if int(desire["score"]) >= base:
				entry["blocked"] = "war still worth waging"
			elif target == player:
				# The human keeps consent: a rival queues the offer and waits
				# (wiki: diplomacy § Planner selection; DR-20261109-07).
				entry["blocked"] = _peace_block(config, state, ai_state, turn, target)
				if String(entry["blocked"]).is_empty():
					entry["propose"] = true
					if best_peace.is_empty() or int(entry["desire"]) < int(best_peace["desire"]):
						best_peace = entry
			elif best_peace.is_empty() or int(entry["desire"]) < int(best_peace["desire"]):
				# A fellow court signs at once. The 4-turn war cooldown gates a
				# new Declare War on the pair, never the peace leg (wiki:
				# diplomacy § Cooldowns; DR-20261108-01).
				best_peace = entry
		else:
			entry["blocked"] = _war_block(
				config, state, ai_state, turn, target, record, int(desire["score"])
			)
			if (
				String(entry["blocked"]).is_empty()
				and (best_war.is_empty() or int(entry["desire"]) > int(best_war["desire"]))
			):
				best_war = entry
			# Rival courts offer treaties only to the human court: an AI target
			# would answer the proposal during the same phase (wiki: diplomacy).
			if target == player:
				var offer: Dictionary = _offer_candidate(
					config, state, ai_state, world, turn, target,
					int(desire["score"]), record.score
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
		action = best_offer.duplicate()
	return {"action": action, "candidates": candidates}


## War-goal objective: clamp(round(warDesire / 25), 1, targetProvinceCount).
static func desired_territory(war_desire_score: int, province_count: int) -> int:
	var target: int = int(roundf(float(war_desire_score) / DESIRE_PER_PROVINCE))
	return clampi(target, 1, maxi(1, province_count))


static func _relation_pressure(score: float) -> int:
	if score >= 70.0:
		return RELATION_WARM_PENALTY
	if score >= 50.0:
		return RELATION_NEUTRAL_PENALTY
	if score <= 25.0:
		return RELATION_HOSTILE_BONUS
	return 0


## +5 per distinct target commodity the attacker holds none of, capped at +15.
## Skipped until the caller supplies stockpiles (rival economies are deferred).
static func _resource_need(
	attacker: int, world: WorldMap, target: int, context: Dictionary
) -> int:
	var stockpiles: Dictionary = context.get("stockpiles", {})
	if not stockpiles.has(attacker):
		return 0
	var stock: Dictionary = stockpiles[attacker]
	var missing: int = 0
	for commodity: String in _target_commodities(world, target).keys():
		if int(stock.get(commodity, 0)) <= 0:
			missing += 1
	return mini(missing * RESOURCE_NEED_STEP, RESOURCE_NEED_CAP)


static func _target_commodities(world: WorldMap, target: int) -> Dictionary:
	var result: Dictionary = {}
	if world == null:
		return result
	for model: MapModel in world.regions:
		for province: ProvinceState in model.provinces:
			if province.owner != target or province.resource == MapModel.NO_ID:
				continue
			var commodity: String = ImprovementCatalog.commodity(province.resource)
			if not commodity.is_empty():
				result[commodity] = true
	return result


## -8 per other Great Power the declaration would call to the victim's aid,
## capped at -24. The count comes from the intervention rule itself, so an
## embassy **and** a rival's deed in the victim's land both protect it: a minor
## whose ground a crown has bought is harder to attack than a bare one
## (wiki: diplomacy § Intervention "investment protection"; DR-20261110-20).
static func _intervention_penalty(
	state: DiplomacyState, world: WorldMap, attacker: int, target: int
) -> int:
	return maxi(
		Intervention.candidates(state, attacker, target, world).size() * INTERVENTION_STEP,
		INTERVENTION_CAP
	)


static func _invasion_adjustment(
	state: DiplomacyState, world: WorldMap, attacker: int, target: int, context: Dictionary
) -> Dictionary:
	var regiments: Dictionary = context.get("regiments", {})
	var own: int = int(regiments.get(attacker, 0))
	var theirs: int = int(regiments.get(target, 0))
	var adjustment: int = 0
	if own < maxi(2, theirs / 2):
		adjustment += INVASION_TOO_SMALL
	elif own > theirs:
		adjustment += INVASION_SUPERIOR
	var ships: Dictionary = context.get("ships", {})
	if _needs_overseas(world, attacker, target) and int(ships.get(attacker, 0)) == 0:
		adjustment += INVASION_NO_SHIPS
	var wars: int = _active_wars(state, attacker)
	var penalty: int = MULTI_WAR_PENALTY if wars >= 2 else 0
	return {"adjustment": adjustment, "wars": penalty}


static func _active_wars(state: DiplomacyState, faction: int) -> int:
	var total: int = 0
	for record: DiplomacyRelation in state.relations_of(faction):
		if record.at_war:
			total += 1
	return total


static func _needs_overseas(world: WorldMap, attacker: int, target: int) -> bool:
	if world == null:
		return false
	var mine: Dictionary = {}
	for index in world.region_count():
		if world.owned_provinces(index, attacker) > 0:
			mine[index] = true
	for index in world.region_count():
		if world.owned_provinces(index, target) > 0 and not mine.has(index):
			return true
	return false


static func _is_weak_target(target: int) -> bool:
	return FactionCatalog.type_of(target) != FactionCatalog.Type.GREAT_POWER


## Improve-relations proposal for the human court: the next free overture, or a
## formal alliance when the relation is already Allied and the agenda favours
## one. A blocked result keeps the trace readable (wiki: diplomacy § GP AI
## policy; DR-20261109-06).
static func _offer_candidate(
	config: AiConfig,
	state: DiplomacyState,
	ai_state: AiState,
	world: WorldMap,
	turn: int,
	target: int,
	desire: int,
	relation_score: float
) -> Dictionary:
	var improve: int = 100 - desire
	if improve < config.parameter("diplomacy.improve_min_desire"):
		return {"ok": false, "blocked": "improve-relations desire too low"}
	var cooldown: int = config.parameter("diplomacy.overture_cooldown_turns")
	if ai_state.overture_on_cooldown(config.faction, target, turn, cooldown):
		return {"ok": false, "blocked": "overture cooldown"}
	if DiplomacyProposals.has_pending(state, target):
		return {"ok": false, "blocked": "the court is already considering a proposal"}
	var best: Dictionary = {"ok": false, "blocked": "no legal proposal"}
	if relation_score >= DiplomacyCatalog.ALLIANCE_CLAMP:
		var alliance: Dictionary = DiplomacyRules.can_form_alliance(
			state, config.faction, target
		)
		if bool(alliance.get("ok", false)):
			best = {
				"ok": true,
				"kind": KIND_ALLIANCE,
				"target": target,
				"stage": "",
				"utility": improve + int(config.agenda_traits.get("alliance_bias", 0)),
				"improve": improve,
			}
	var next: String = DiplomacyCatalog.next_stage(state.overture(config.faction, target))
	if not next.is_empty():
		var overture: Dictionary = DiplomacyRules.can_establish_overture(
			state, world, config.faction, target, next, 0, {}
		)
		if (
			bool(overture.get("ok", false))
			and (not bool(best.get("ok", false)) or improve > int(best["utility"]))
		):
			best = {
				"ok": true,
				"kind": KIND_OVERTURE,
				"target": target,
				"stage": next,
				"utility": improve,
				"improve": improve,
			}
	return best


## Why this court cannot put a white peace to the human court right now ("" when
## it may). A queued proposal waits for the answer, so a second one would only
## be refused by the court queue (DR-20261109-07).
static func _peace_block(
	config: AiConfig, state: DiplomacyState, ai_state: AiState, turn: int, target: int
) -> String:
	if DiplomacyProposals.has_pending(state, target):
		return "the court is already considering a proposal"
	var cooldown: int = config.parameter("diplomacy.peace_cooldown_turns")
	if ai_state.peace_on_cooldown(config.faction, target, turn, cooldown):
		return "peace cooldown"
	var check: Dictionary = DiplomacyRules.can_make_peace(state, config.faction, target)
	if not bool(check.get("ok", false)):
		return String(check.get("reason", "illegal"))
	return ""


## Why this court will not declare war right now ("" when it may).
static func _war_block(
	config: AiConfig,
	state: DiplomacyState,
	ai_state: AiState,
	turn: int,
	target: int,
	record: DiplomacyRelation,
	desire: int
) -> String:
	var check: Dictionary = DiplomacyRules.can_declare_war(state, config.faction, target)
	if not bool(check.get("ok", false)):
		return String(check.get("reason", "illegal"))
	var cooldown: int = config.parameter("diplomacy.war_cooldown_turns")
	if ai_state.war_on_cooldown(config.faction, target, turn, cooldown):
		return "war cooldown"
	if record.score > float(config.war_relation_ceiling()):
		return "relations too warm"
	if desire < config.parameter("diplomacy.war_declare_min_desire"):
		return "war desire too low"
	return ""
