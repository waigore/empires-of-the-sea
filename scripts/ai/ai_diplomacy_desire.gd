class_name AiDiplomacyDesire
extends RefCounted
## The war-desire tally a rival court prices a war with (wiki: diplomacy § GP AI
## policy for war vs. relations, diplomacy-planner; docs/ai.md). One 0..100
## value per (attacker, target) pair plus the factors that made it, so a turn
## trace can explain the number (wiki: turn-trace-interpretation). Pure rules:
## state in, score out — AiDiplomacyPlanner turns a score into an order
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
