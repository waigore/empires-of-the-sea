class_name AiMilitaryPlanner
extends RefCounted
## Full-AI land policy (docs/ai.md). At war on its own border a rival court
## detaches the Home Army into a field army, then marches field armies to save an
## occupied province, storm the best adjacent hostile one, or advance to the
## nearest frontier. A court that has reached its muster target cuts a fresh
## field force even while another stands, and an under-strength field army may
## rotate home to merge with the Home Army's mustered mass so the next cut
## re-fields a full-strength replacement (issue #974). Pure rules: state in,
## orders out; the map layer applies them through ArmyMovement so the AI never
## invents an outcome (REQ-P2-03, REQ-P3-03).

const KIND_SPLIT: String = "split_home"
const KIND_MARCH: String = "march"
## An under-strength field army's interior-lines march home to merge with the
## Home Army's mustered mass (issue #974).
const KIND_ROTATE: String = "rotate_home"
## A host standing on ground it does not hold walks home one province at a time:
## no own land touches, so interior lines are shut and the road home is a walk
## through the provinces beside it (wiki: military-armies § Movement and attacks;
## DR-20261121-15).
const KIND_WALK_HOME: String = "walk_home"

## A distance no walk reaches: a province the road home never touches.
const UNREACHABLE: int = 1 << 30

## Score weights and the storm margin live in AiParameterRegistry
## ("military.*"), so a profile tunes the land policy without code edits.


## Detach the Home Army when a hostile province touches the court's own land.
## With no field army standing this is the published first cut: one regiment
## guards the capital (the Home Army never marches); the rest form a field army
## at the seat. While another stands, the guard is a **condition, not a
## lifetime lock** (issue #974): a Home Army that has reached the court's
## muster target holds nothing but the mass a fresh field force can take, so a
## second cut fields it and the musters refill the seat.
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
	var home: ArmyState = ArmyTraining.home_army(armies, owner)
	if home == null or home.count() < 2:
		return actions
	if not ArmyRoster.field_armies(armies, owner).is_empty() and home.count() < AiArmyReinforce.desired_regiments(
		config, AiIncome.at_war(state, owner)
	):
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
## an adjacent hostile province, then staging on the nearest frontier. One
## under-strength field army a turn may instead march home on interior lines
## (issue #974): it merges with the Home Army's mustered mass, and the next
## split re-fields a full-strength replacement. A host standing on ground it does
## not hold has no interior lines, so when no attack, defence or staging order
## answers it walks home one province at a time (DR-20261121-15).
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
	var hostile: Dictionary = Hostility.owners(state, owner)
	var frontier: Array[int] = _staging_provinces(model, owner, state)
	# The rotation is a war move: a court at peace keeps its field armies where
	# they stand. The walk home is not — a host stranded in the wilderness walks
	# back whether or not a war is on (DR-20261121-15).
	var rotating: int = -1
	if not hostile.is_empty():
		rotating = _rotation_army_id(config, model, armies)
	for army: ArmyState in ArmyRoster.field_armies(armies, owner):
		if army.moved or army.is_empty():
			continue
		var best: Dictionary = {}
		if army.id == rotating:
			var home: ArmyState = ArmyTraining.home_army(armies, owner)
			best = _rotation_order(model, army, home)
		else:
			best = _best_order(config, model, armies, army, hostile, frontier)
		if best.is_empty():
			best = _walk_home_order(model, army)
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


## The one field army this turn's rotation takes home (issue #974): the
## smallest standing force — the most under-strength — while the Home Army
## holds mustered mass above the seat's guard, so merging and re-cutting fields
## a strictly stronger replacement. -1 when no rotation pays: no mass beyond
## the guard, no field army away from the seat, or the court reads no seat.
static func _rotation_army_id(
	config: AiConfig,
	model: MapModel,
	armies: Array[ArmyState]
) -> int:
	var owner: int = config.faction
	var home: ArmyState = ArmyTraining.home_army(armies, owner)
	if home == null or home.province != WorldBootstrap.capital_province(model, owner):
		return -1
	if home.count() <= 1:
		return -1
	var chosen: ArmyState = null
	for army: ArmyState in ArmyRoster.field_armies(armies, owner):
		if army.moved or army.is_empty() or army.province == home.province:
			continue
		if chosen == null or army.count() < chosen.count():
			chosen = army
	return chosen.id if chosen != null else -1


## The rotation's own order: the march home to merge, or — when the seat is out
## of one march's reach — the first leg of the walk home, so a stranded host
## never sits on an order the rules would refuse (DR-20261121-15).
static func _rotation_order(
	model: MapModel, army: ArmyState, home: ArmyState
) -> Dictionary:
	if home == null:
		return {}
	if ArmyMovement.destinations(model, army).has(home.province):
		return {"province": home.province, "kind": KIND_ROTATE, "score": 0}
	return _walk_home_order(model, army)


## The first leg of the walk home for a field army that stands on ground it does
## not hold: the province beside it that shortens the road to the seat, over
## ground the army may enter at peace — its own land and unclaimed wilderness.
## Own land is the seat's own distance and always wins: stepping onto it opens
## the interior lines, so a wilderness step that merely reads nearer on the
## wilderness road never draws the host away from its own border. Empty when the
## army stands on its own ground, the court reads no seat, or no step shortens the
## road (a host walled in by foreign land).
static func _walk_home_order(model: MapModel, army: ArmyState) -> Dictionary:
	if model == null or army == null or ArmyMovement.on_own_ground(model, army):
		return {}
	var seat: int = WorldBootstrap.capital_province(model, army.owner)
	if seat == MapModel.NO_ID:
		return {}
	var road: Dictionary = _walk_distances(model, seat, army.owner)
	var best: Dictionary = {}
	var best_distance: int = UNREACHABLE
	for province: int in ArmyMovement.destinations(model, army):
		var holder: int = model.province_owner(province)
		if holder != army.owner and holder != MapModel.NO_ID:
			continue
		var distance: int = int(road.get(province, UNREACHABLE))
		if distance >= UNREACHABLE:
			continue
		# Own land is the seat's own distance 0, because landing on it opens the
		# interior lines, so it always wins; a wilderness step keeps its distance
		# over the walk. Nearest first, the lower id on a tie, so the same state
		# always walks the same way (wiki: military-armies § Movement and
		# attacks; DR-20261121-15).
		var rank: int = 0 if holder == army.owner else distance
		if not best.is_empty():
			if rank > best_distance:
				continue
			if rank == best_distance and province > int(best["province"]):
				continue
		best = {"province": province, "kind": KIND_WALK_HOME, "score": 0}
		best_distance = rank
	return best


## Distance from the seat over the ground a host may walk at peace: the court's
## own land and unclaimed wilderness. Foreign land is no step — a march into it
## is a war, and the attack branch already prices that.
static func _walk_distances(model: MapModel, seat: int, owner: int) -> Dictionary:
	var distances: Dictionary = {}
	if seat < 0:
		return distances
	var queue: Array[int] = [seat]
	distances[seat] = 0
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for neighbor: int in MapGeo.province_neighbors(model, current):
			if distances.has(neighbor):
				continue
			var holder: int = model.province_owner(neighbor)
			if holder != owner and holder != MapModel.NO_ID:
				continue
			distances[neighbor] = int(distances[current]) + 1
			queue.append(neighbor)
	return distances


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
	var defenders: Array[ArmyState] = ArmyForce.armies_of(
		armies, province, model.province_owner(province)
	)
	if defenders.is_empty():
		return true
	var wall: float = FortRules.wall_hp(FortRules.level_at(model, province))
	var attack: float = army.strength() - wall
	var margin: float = float(config.parameter("military.attack_margin_pct")) / 100.0
	return attack > ArmyForce.side_strength(defenders) * margin


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


## True when a hostile army already stands in one of this court's own provinces:
## the land war is on its soil, so no regiment may leave for the Passage
## (DR-20261113-19).
static func invader_on_home_soil(
	model: MapModel, owner: int, armies: Array, state: DiplomacyState
) -> bool:
	var hostile: Dictionary = Hostility.owners(state, owner)
	for raw: Variant in armies:
		var army: ArmyState = raw
		if army == null or army.is_empty() or army.owner == owner:
			continue
		if hostile.has(army.owner) and model.province_owner(army.province) == owner:
			return true
	return false


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
