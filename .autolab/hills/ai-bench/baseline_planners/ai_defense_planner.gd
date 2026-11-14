class_name MainlineAiDefensePlanner
extends RefCounted
## Reactive home defence for Minor Nations and Tribes (wiki: factions § Minor
## Nation, § Tribe; military-armies § Home Army).
##
## Those crowns submit no orders. At peace they hold. When a hostile army stands
## on their soil, a relief column detaches from the Home Army — one regiment
## keeps the seat — and marches onto the invaded province. The column only ever
## moves through land the faction owns, so a Minor or Tribe never attacks.
## Pure rules: state in, orders out; the map layer applies them through
## ArmyMovement (REQ-P2-03, REQ-P3-03).

const KIND_RELIEVE: String = "relieve"


## Detach a relief column when an invader holds home soil away from the seat and
## no field army exists yet. An invaded capital needs no column: the Home Army
## already stands there.
static func split_orders(
	state: DiplomacyState,
	model: MapModel,
	armies: Array[ArmyState],
	faction: int
) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if not _can_plan(state, model, faction):
		return actions
	var home: ArmyState = _home_army(armies, faction)
	var wanted: Array[int] = []
	for province: int in _threatened(state, model, armies, faction):
		if home == null or home.province != province:
			wanted.append(province)
	if wanted.is_empty() or not _field_armies(armies, faction).is_empty():
		return actions
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
	actions.append({
		"kind": MainlineAiMilitaryPlanner.KIND_SPLIT,
		"army_id": home.id,
		"regiments": ids,
	})
	return actions


## One march per field army onto a threatened own province, the seat first and
## ties broken by province id. `candidates` mirrors `orders` for the turn trace.
static func march_orders(
	state: DiplomacyState,
	model: MapModel,
	armies: Array[ArmyState],
	faction: int
) -> Dictionary:
	var orders: Array[Dictionary] = []
	var candidates: Array[Dictionary] = []
	if not _can_plan(state, model, faction):
		return {"orders": orders, "candidates": candidates}
	var threatened: Array[int] = _threatened(state, model, armies, faction)
	if threatened.is_empty():
		return {"orders": orders, "candidates": candidates}
	for army: ArmyState in _field_armies(armies, faction):
		if army.moved or army.is_empty():
			continue
		var target: int = _relief_target(model, army, faction, threatened)
		if target < 0:
			continue
		var entry: Dictionary = {
			"army_id": army.id,
			"province": target,
			"kind": KIND_RELIEVE,
		}
		candidates.append(entry)
		orders.append(entry.duplicate())
	return {"orders": orders, "candidates": candidates}


## Own provinces where an army of a crown at war with this faction stands.
static func _threatened(
	state: DiplomacyState,
	model: MapModel,
	armies: Array[ArmyState],
	faction: int
) -> Array[int]:
	var provinces: Array[int] = []
	for army: ArmyState in armies:
		if army == null or army.is_empty() or army.province < 0:
			continue
		if army.owner == faction or not DiplomacyRules.at_war_with(state, faction, army.owner):
			continue
		if model.province_owner(army.province) != faction:
			continue
		if not provinces.has(army.province):
			provinces.append(army.province)
	provinces.sort()
	return provinces


## Best own threatened province this army can reach: the seat outranks the rest,
## then the lowest province id keeps the choice deterministic.
static func _relief_target(
	model: MapModel, army: ArmyState, faction: int, threatened: Array[int]
) -> int:
	var best: int = -1
	var best_rank: int = -1
	for province: int in ArmyMovement.destinations(model, army):
		if model.province_owner(province) != faction or not threatened.has(province):
			continue
		var data: ProvinceState = model.province_data(province)
		var rank: int = 1
		if data != null and data.capital:
			rank = 2
		if best < 0 or rank > best_rank or (rank == best_rank and province < best):
			best = province
			best_rank = rank
	return best


## Only Minor Nations and Tribes use this planner; a Great Power keeps the
## offensive policy in MainlineAiMilitaryPlanner.
static func _can_plan(state: DiplomacyState, model: MapModel, faction: int) -> bool:
	if state == null or model == null or faction < 0:
		return false
	return FactionCatalog.type_of(faction) != FactionCatalog.Type.GREAT_POWER


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