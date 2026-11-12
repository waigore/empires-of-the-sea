class_name ArmyMovement
extends RefCounted
## Land army movement (wiki: military-armies § Movement and attacks).
## Pure rules: callers apply the result; this module never touches nodes
## (REQ-P3-03).
##
## One army marches once per turn. An army may enter any province it owns in
## its region (interior lines) and only an adjacent province it does not own
## (hostile or neutral land). The Home Army never leaves the capital.

const NO_PROVINCE: int = MapModel.NO_ID


## Legal destinations for the army's one march this turn. Foreign land is listed
## but a march into it is refused at order time unless at war with its owner
## (wiki: diplomacy § War required for hostile actions).
static func destinations(model: MapModel, army: ArmyState) -> Array[int]:
	var result: Array[int] = []
	if not _can_act(model, army):
		return result
	var reachable: Array[int] = land_reachable(model, army.province, army.owner)
	for province: ProvinceState in model.provinces:
		var province_id: int = province.id
		if province_id == army.province:
			continue
		if province.owner == army.owner and reachable.has(province_id):
			result.append(province_id)
	if army.province != NO_PROVINCE:
		for neighbor: int in MapGeo.province_neighbors(model, army.province):
			if not result.has(neighbor):
				result.append(neighbor)
	result.sort()
	return result


## Own provinces on the same landmass and connected through own territory.
## Interior lines are abstracted as one march, but a land army cannot cross
## open water or foreign land without transports and battles.
static func land_reachable(
	model: MapModel, province_id: int, owner: int = MapModel.NO_ID
) -> Array[int]:
	var found: Array[int] = []
	if model == null or model.province_data(province_id) == null:
		return found
	var queue: Array[int] = [province_id]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		if found.has(current):
			continue
		found.append(current)
		for neighbor: int in MapGeo.province_neighbors(model, current):
			if found.has(neighbor):
				continue
			if owner != MapModel.NO_ID and model.province_owner(neighbor) != owner:
				continue
			queue.append(neighbor)
	return found


static func can_move(
	model: MapModel, army: ArmyState, province_id: int, at_war: bool = true
) -> Dictionary:
	if army == null:
		return _deny("There is no army to order.")
	if army.home:
		return _deny("The Home Army never leaves the capital; detach a field army first.")
	if army.moved:
		return _deny("This army has already marched this turn.")
	if army.is_empty():
		return _deny("An army with no regiments cannot march.")
	if model == null or model.province_data(province_id) == null:
		return _deny("That is not a province.")
	if province_id == army.province:
		return _deny("The army is already in that province.")
	if model.province_owner(province_id) == army.owner:
		if land_reachable(model, army.province, army.owner).has(province_id):
			return _allow()
		return _deny("Own land across open water or foreign land needs a naval transport.")
	if not MapGeo.province_neighbors(model, army.province).has(province_id):
		return _deny("Enemy or neutral land may only be entered from an adjacent province.")
	if not at_war and _is_foreign(model, army, province_id):
		return _deny(
			"Peace holds with %s; declare war before invading."
			% FactionCatalog.name_of(model.province_owner(province_id))
		)
	return _allow()


## Validates, then moves every regiment with the army. `attacked` reports that
## the destination belongs to another faction.
static func apply_move(
	model: MapModel, army: ArmyState, province_id: int, at_war: bool = true
) -> Dictionary:
	var check: Dictionary = can_move(model, army, province_id, at_war)
	if not bool(check.get("ok", false)):
		return {"ok": false, "reason": String(check.get("reason", "")), "attacked": false}
	var attacked: bool = model.province_owner(province_id) != army.owner
	army.province = province_id
	army.moved = true
	return {"ok": true, "reason": "", "attacked": attacked}


## Land held by another faction; unowned wilderness is not an invasion.
static func _is_foreign(model: MapModel, army: ArmyState, province_id: int) -> bool:
	var owner: int = model.province_owner(province_id)
	return owner != MapModel.NO_ID and owner != army.owner


static func begin_turn(armies: Array[ArmyState], model: MapModel = null) -> void:
	for army: ArmyState in armies:
		if army != null:
			army.moved = false
			# Field depots replace part of the battle's wear each turn; a
			# province hospital sets a faster tempo, and an army's own train
			# carries the field's tempo wherever it stands — the better of the
			# two, never both (wiki: combat § Strength; DR-20261110-19,
			# DR-20261111-12, DR-20261112-07).
			var share: float = HospitalRules.army_rest_share(
				model, army.province, army.field_hospital
			)
			RegimentCondition.rest(army, share)


static func _can_act(model: MapModel, army: ArmyState) -> bool:
	return (
		model != null
		and army != null
		and not army.home
		and not army.moved
		and not army.is_empty()
		and army.province != NO_PROVINCE
	)


static func _allow() -> Dictionary:
	return {"ok": true, "reason": ""}


static func _deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
