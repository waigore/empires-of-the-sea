class_name AiMilitaryPlanner
extends RefCounted
## Full-AI land policy (docs/ai.md). At war on its own border a rival court
## detaches the Home Army into a field army, then marches field armies to save an
## occupied province, storm the best adjacent hostile one, or advance to the
## nearest frontier. Pure rules: state in, orders out; the map layer applies them
## through ArmyMovement so the AI never invents an outcome (REQ-P2-03,
## REQ-P3-03).

const KIND_SPLIT: String = "split_home"
const KIND_MARCH: String = "march"

## Score weights and the storm margin live in AiParameterRegistry
## ("military.*"), so a profile tunes the land policy without code edits.


## Detach the Home Army when a hostile province touches the court's own land and
## no field army exists yet. One regiment guards the capital (the Home Army never
## marches); the rest form a field army at the seat.
static func split_orders(
	config: AiConfig,
	state: DiplomacyState,
	model: MapModel,
	armies: Array[ArmyState]
) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if config == null or state == null or model == null:
		return actions
	var owner: int = config.faction
	if frontier_hostile(model, owner, state).is_empty():
		return actions
	if not _field_armies(armies, owner).is_empty():
		return actions
	var home: ArmyState = _home_army(armies, owner)
	if home == null or home.count() < 2:
		return actions
	var ordered: Array[String] = home.regiments.duplicate()
	ordered.sort_custom(func(a: String, b: String) -> bool:
		var left: int = RegimentCatalog.strength(home.type_of(a))
		var right: int = RegimentCatalog.strength(home.type_of(b))
		if left != right:
			return left < right
		return a < b
	)
	var ids: Array[String] = []
	for index in range(1, ordered.size()):
		ids.append(ordered[index])
	actions.append({"kind": KIND_SPLIT, "army_id": home.id, "regiments": ids})
	return actions


## One march per field army: defence of an occupied own province, then storming
## an adjacent hostile province, then staging on the nearest frontier.
static func march_orders(
	config: AiConfig,
	state: DiplomacyState,
	model: MapModel,
	armies: Array[ArmyState]
) -> Dictionary:
	var orders: Array[Dictionary] = []
	var candidates: Array[Dictionary] = []
	if config == null or state == null or model == null:
		return {"orders": orders, "candidates": candidates}
	var owner: int = config.faction
	var hostile: Dictionary = _hostile_owners(state, owner)
	if hostile.is_empty():
		return {"orders": orders, "candidates": candidates}
	var frontier: Array[int] = _staging_provinces(model, owner, state)
	for army: ArmyState in _field_armies(armies, owner):
		if army.moved or army.is_empty():
			continue
		var best: Dictionary = _best_order(config, model, armies, army, hostile, frontier)
		if best.is_empty():
			continue
		var entry: Dictionary = {
			"army_id": army.id,
			"province": int(best["province"]),
			"kind": String(best["kind"]),
			"score": int(best["score"]),
		}
		candidates.append(entry)
		orders.append(entry.duplicate())
	return {"orders": orders, "candidates": candidates}


## Highest-scoring legal destination for one field army. Attack scores come from
## the province itself, defence adds a premium, staging is a distance tie-break.
static func _best_order(
	config: AiConfig,
	model: MapModel,
	armies: Array[ArmyState],
	army: ArmyState,
	hostile: Dictionary,
	frontier: Array[int]
) -> Dictionary:
	var best: Dictionary = {}
	var distances: Dictionary = _own_distances(model, army.province, army.owner)
	for province: int in ArmyMovement.destinations(model, army):
		var owner: int = model.province_owner(province)
		var score: int = 0
		var kind: String = ""
		if owner == army.owner:
			if not _hostile_army_at(armies, province, army.owner, hostile):
				if not frontier.has(province) or frontier.has(army.province):
					continue
				score = -int(distances.get(province, 999)) * config.parameter(
					"military.stage_distance_weight"
				)
				kind = "stage"
			else:
				score = config.parameter("military.defence_weight") + province_score(
					config, model, province
				)
				kind = "defend"
		elif hostile.has(owner):
			if not _can_storm(config, model, armies, army, province):
				continue
			score = province_score(config, model, province)
			kind = "attack"
		else:
			continue
		if best.is_empty() or score > int(best["score"]):
			best = {"province": province, "score": score, "kind": kind}
		elif score == int(best["score"]) and province < int(best["province"]):
			best = {"province": province, "score": score, "kind": kind}
	return best


## Walls soak incoming strength, so a storm needs a margin over the defenders.
static func _can_storm(
	config: AiConfig,
	model: MapModel,
	armies: Array[ArmyState],
	army: ArmyState,
	province: int
) -> bool:
	var defenders: Array[ArmyState] = ArmyCombat.armies_of(
		armies, province, model.province_owner(province)
	)
	if defenders.is_empty():
		return true
	var wall: float = FortRules.wall_hp(FortRules.level_at(model, province))
	var attack: float = army.strength() - wall
	var margin: float = float(config.parameter("military.attack_margin_pct")) / 100.0
	return attack > ArmyCombat.side_strength(defenders) * margin


## Value of a province to a court: population, its seat, its resources and its
## walls. Shared with the overseas invasion planner, which wants the same
## ranking of worth (wiki: ai-architecture).
static func province_score(config: AiConfig, model: MapModel, province: int) -> int:
	var data: ProvinceState = model.province_data(province)
	if data == null:
		return 0
	var score: int = 1 + data.population
	if data.capital:
		score += config.parameter("military.capital_weight")
	if data.has_resource_tile():
		score += config.parameter("military.resource_weight")
	score += FortRules.level_at(model, province) * config.parameter("military.fort_weight")
	return score


## Factions this court is at war with, as a membership set.
static func _hostile_owners(state: DiplomacyState, owner: int) -> Dictionary:
	var hostile: Dictionary = {}
	for record: DiplomacyRelation in state.relations_of(owner):
		if record.at_war:
			hostile[record.other(owner)] = true
	return hostile


## Provinces owned by the court that touch a province of a hostile faction. The
## invasion planner reads it too: a war on the court's own border is a land war.
static func frontier_hostile(
	model: MapModel, owner: int, state: DiplomacyState
) -> Array[int]:
	var frontier: Array[int] = []
	for province: ProvinceState in model.provinces:
		if province.owner != owner:
			continue
		for neighbor: int in MapGeo.province_neighbors(model, province.id):
			var other: int = model.province_owner(neighbor)
			if other == MapModel.NO_ID or other == owner:
				continue
			var record: DiplomacyRelation = state.relation(owner, other)
			if record != null and record.at_war and not frontier.has(neighbor):
				frontier.append(neighbor)
	frontier.sort()
	return frontier


## Own provinces on the hostile border: where a field army stages before it can
## storm an adjacent hostile province.
static func _staging_provinces(
	model: MapModel, owner: int, state: DiplomacyState
) -> Array[int]:
	var staging: Array[int] = []
	for province: ProvinceState in model.provinces:
		if province.owner != owner:
			continue
		for neighbor: int in MapGeo.province_neighbors(model, province.id):
			var other: int = model.province_owner(neighbor)
			if other == MapModel.NO_ID or other == owner:
				continue
			var record: DiplomacyRelation = state.relation(owner, other)
			if record != null and record.at_war:
				staging.append(province.id)
				break
	staging.sort()
	return staging


static func _hostile_army_at(
	armies: Array[ArmyState], province: int, owner: int, hostile: Dictionary
) -> bool:
	for army: ArmyState in armies:
		if army == null or army.is_empty() or army.province != province:
			continue
		if army.owner != owner and hostile.has(army.owner):
			return true
	return false


static func _home_army(armies: Array[ArmyState], owner: int) -> ArmyState:
	for army: ArmyState in armies:
		if army != null and army.owner == owner and army.home:
			return army
	return null


static func _field_armies(armies: Array[ArmyState], owner: int) -> Array[ArmyState]:
	var field: Array[ArmyState] = []
	for army: ArmyState in armies:
		if army != null and army.owner == owner and not army.home and not army.is_empty():
			field.append(army)
	field.sort_custom(func(a: ArmyState, b: ArmyState) -> bool: return a.id < b.id)
	return field


## BFS distance through the court's own provinces, so staging picks the nearest
## frontier rather than the lowest province id.
static func _own_distances(model: MapModel, start: int, owner: int) -> Dictionary:
	var distances: Dictionary = {}
	if start < 0:
		return distances
	var queue: Array[int] = [start]
	distances[start] = 0
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for neighbor: int in MapGeo.province_neighbors(model, current):
			if distances.has(neighbor) or model.province_owner(neighbor) != owner:
				continue
			distances[neighbor] = int(distances[current]) + 1
			queue.append(neighbor)
	return distances
