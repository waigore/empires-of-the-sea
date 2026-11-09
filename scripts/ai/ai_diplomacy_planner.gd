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
const KIND_PROPOSAL: String = "proposal"


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
		factors["intervention"] = _intervention_penalty(state, attacker, target)
		var invasion: Dictionary = _invasion_adjustment(
			state, world, attacker, target, context
		)
		factors["invasion"] = int(invasion["adjustment"])
		factors["wars"] = int(invasion["wars"])
		score += int(invasion["adjustment"]) + int(invasion["wars"])
		score += int(factors["resource_need"]) + int(factors["intervention"])
	return {"score": clampi(score, 0, 100), "factors": factors}


## One action for one court: the highest-desire legal war, else a white peace
## with a fellow AI court when continuing the war scores below the base desire.
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
	var player: int = int(context.get("player", -1))
	var base: int = config.parameter("diplomacy.war_desire_base")
	var cooldown: int = config.parameter("diplomacy.war_cooldown_turns")
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
			if target == player:
				entry["blocked"] = "human decision required"
			elif int(desire["score"]) >= base:
				entry["blocked"] = "war still worth waging"
			elif ai_state.war_on_cooldown(config.faction, target, turn, cooldown):
				entry["blocked"] = "war cooldown"
			elif best_peace.is_empty() or int(entry["desire"]) < int(best_peace["desire"]):
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
	else:
		action = _proposal(config, state, ai_state, world, turn, player, context)
	return {"action": action, "candidates": candidates}


## One offer for the human court, at peace and only when war and peace have no
## claim: an alliance at 76+ relations or the next cost-free overture stage.
## Utility is improve-relations desire plus the agenda's alliance bias; the
## alliance wins a tie (wiki: diplomacy § Court proposals).
static func _proposal(
	config: AiConfig,
	state: DiplomacyState,
	ai_state: AiState,
	world: WorldMap,
	turn: int,
	player: int,
	context: Dictionary
) -> Dictionary:
	if player < 0 or player == config.faction:
		return {}
	if not state.pending_proposals.is_empty():
		return {}
	var record: DiplomacyRelation = state.relation(config.faction, player)
	if record == null or record.at_war:
		return {}
	var desire: int = int(war_desire(
		config, state, world, config.faction, player, context
	)["score"])
	var improve: int = 100 - desire
	var options: Array[Dictionary] = []
	if record.score >= DiplomacyCatalog.ALLIANCE_CLAMP and not record.formal_alliance:
		options.append({
			"offer": DiplomacyProposals.OFFER_ALLIANCE,
			"stage": "",
			"utility": improve + int(config.agenda_traits.get("alliance_bias", 0)),
		})
	var stage: String = DiplomacyCatalog.next_stage(state.overture(config.faction, player))
	var cooldown: int = config.parameter("diplomacy.overture_cooldown_turns")
	if (
		improve >= config.parameter("diplomacy.improve_min_desire")
		and not ai_state.overture_on_cooldown(config.faction, player, turn, cooldown)
		and _is_free_stage(stage)
	):
		options.append({
			"offer": DiplomacyProposals.OFFER_OVERTURE, "stage": stage, "utility": improve
		})
	var best: Dictionary = {}
	for option: Dictionary in options:
		if best.is_empty() or int(option["utility"]) > int(best["utility"]):
			best = option
	if best.is_empty():
		return {}
	return {
		"kind": KIND_PROPOSAL,
		"target": player,
		"offer": String(best["offer"]),
		"stage": String(best["stage"]),
		"utility": int(best["utility"]),
		"desire": improve,
	}


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


## -8 per other Great Power holding an embassy on the target, capped at -24.
static func _intervention_penalty(state: DiplomacyState, attacker: int, target: int) -> int:
	var count: int = 0
	for power: int in FactionCatalog.great_power_ids():
		if power == attacker or power == target:
			continue
		if DiplomacyRules.has_embassy(state, power, target):
			count += 1
	return maxi(count * INTERVENTION_STEP, INTERVENTION_CAP)


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


## Rivals only offer stages they can pay for while their treasuries are
## untracked: Join Empire and the paid embassy steps are never proposed.
static func _is_free_stage(stage: String) -> bool:
	return not stage.is_empty() and DiplomacyCatalog.stage_cost(stage) == 0


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
