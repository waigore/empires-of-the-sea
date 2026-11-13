class_name AiDiplomacyPlanner
extends RefCounted
## Full-AI diplomacy policy (wiki: diplomacy § GP AI policy for war vs. relations,
## diplomacy-planner). Scores one war-desire value per candidate court, turns the
## complement into improve-relations desire, and emits at most one legal order
## per Great Power per turn — war, peace, or any peaceful order the court menu
## offers through AiDiplomacyOffers. Pure rules: state in, orders out
## (REQ-P2-03, REQ-P3-03).

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
	# The two agenda pulls the court's own book of grudges adds (wiki:
	# hidden-agendas § Design intent; DR-20261111-27): a backstabber signs a
	# treaty meaning to break it, and an envious court resents a human crown
	# that has pulled ahead of it.
	var betrayal: int = config.betray_bias() if record.formal_alliance else 0
	if betrayal != 0:
		factors["betrayal"] = betrayal
		score += betrayal
	var rivalry: int = _rival_pull(config, attacker, target, context)
	if rivalry != 0:
		factors["rival"] = rivalry
		score += rivalry
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
	# An agenda moves the bar a war must fall below before the court puts peace
	# to its enemy (wiki: hidden-agendas — peacemaker early peace, warmonger
	# keeps the war alive; DR-20261111-27).
	var bar: int = AiPeaceStance.peace_bar(config)
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
			if int(desire["score"]) >= bar:
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
				config, state, ai_state, turn, target, record, int(desire["score"])
			)
			if (
				String(entry["blocked"]).is_empty()
				and (best_war.is_empty() or int(entry["desire"]) > int(best_war["desire"]))
			):
				best_war = entry
			# Every peaceful order the court menu offers is a candidate, whether
			# the target is a rival court or the human one (DR-20261110-15).
			var offer: Dictionary = AiDiplomacyOffers.best(
				config, state, ai_state, world, turn, target, int(desire["score"]),
				context
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
	for commodity: String in _target_commodities(world, target, attacker, context).keys():
		if int(stock.get(commodity, 0)) <= 0:
			missing += 1
	return mini(missing * RESOURCE_NEED_STEP, RESOURCE_NEED_CAP)


## The target's commodities **this court has charted**: a resource is read on
## `fogged` ground, never in a province the court has not reached (wiki:
## fog-and-exploration § Visibility Levels; DR-20261113-03). Without a chart the
## published map stands, as it does for the order-of-battle reading.
static func _target_commodities(
	world: WorldMap, target: int, reader: int, context: Dictionary
) -> Dictionary:
	var result: Dictionary = {}
	if world == null:
		return result
	var charts: CourtCharts = context.get("charts", null)
	for index in world.region_count():
		var model: MapModel = world.region(index)
		if model == null:
			continue
		for province: ProvinceState in model.provinces:
			if province.owner != target or province.resource == MapModel.NO_ID:
				continue
			if not _charted(charts, reader, index, province.id):
				continue
			var commodity: String = ImprovementCatalog.commodity(province.resource)
			if not commodity.is_empty():
				result[commodity] = true
	return result


## Charted ground: one tile of the province at `fogged` or better. A court with
## no chart for the region (a fixture, or a world never charted) reads the
## published map, exactly as `OobReadings` does.
static func _charted(
	charts: CourtCharts, reader: int, region: int, province: int
) -> bool:
	if charts == null:
		return true
	var view: VisibilityModel = charts.model_for(reader, region)
	return view == null or view.is_province_known(province)


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


## Every agenda that resents a crown's lead reads the same table: a rival of a
## human court that holds at least as much power adds its `rival_bias` to the
## desire to cut it down (wiki: hidden-agendas — envy; DR-20261111-27). With no
## read model for the powers the factor stays out, so a headless trace without
## one is unchanged.
static func _rival_pull(
	config: AiConfig, attacker: int, target: int, context: Dictionary
) -> int:
	var bonus: int = config.rival_bias()
	if bonus == 0:
		return 0
	var human: int = int(context.get("player", -1))
	if target != human:
		return 0
	var powers: Dictionary = context.get("power", {})
	if not powers.has(human) or not powers.has(attacker):
		return 0
	return bonus if int(powers[human]) >= int(powers[attacker]) else 0


static func _is_weak_target(target: int) -> bool:
	return FactionCatalog.type_of(target) != FactionCatalog.Type.GREAT_POWER


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
